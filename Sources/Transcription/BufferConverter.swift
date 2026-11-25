import AVFoundation

/// Resamples microphone buffers into the format a transcription engine expects.
///
/// Short, and entirely load-bearing. The input node hands over 48 kHz mono;
/// `SpeechAnalyzer` asks for whatever its model was trained on. Give it the
/// wrong format and it does not complain, does not throw, and does not
/// transcribe — the failure looks exactly like a microphone that heard nothing.
///
/// Not an actor: it is owned by one session, touched only from that session's
/// isolation, and `AVAudioConverter` keeps internal resampler state that must
/// see every buffer in order.
final class BufferConverter {
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) {
        self.outputFormat = outputFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let inputFormat = buffer.format
        guard inputFormat != outputFormat else { return buffer }

        if converter == nil || converter?.inputFormat != inputFormat {
            guard let made = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw DictationError.transcriptionFailed(
                    reason: "No conversion from \(inputFormat) to \(outputFormat)"
                )
            }
            // Priming prepends silence so the resampler can settle. That is right
            // for a one-shot file and wrong here: converting a continuous stream
            // chunk by chunk, it would sprinkle silence through the middle of
            // every sentence.
            made.primeMethod = .none
            converter = made
        }
        guard let converter else {
            throw DictationError.transcriptionFailed(reason: "Converter unavailable")
        }

        // Round up, then leave headroom: a resampler's output length per chunk
        // is not exactly the ratio, and a buffer one frame too small truncates
        // audio silently.
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64

        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw DictationError.transcriptionFailed(reason: "Could not allocate an output buffer")
        }

        var conversionError: NSError?
        var alreadySupplied = false

        // The callback is pull-based: it may be asked for input more than once
        // per call, so the flag is what stops the same buffer being converted
        // twice and the audio stuttering.
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if alreadySupplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            alreadySupplied = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if let conversionError { throw conversionError }
        guard status != .error else {
            throw DictationError.transcriptionFailed(reason: "Audio conversion failed")
        }
        return output
    }
}
