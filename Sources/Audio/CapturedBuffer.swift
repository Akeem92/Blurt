import AVFoundation

/// Carries one slice of microphone audio from the audio thread to its consumer.
///
/// `AVAudioPCMBuffer` is a class, so the compiler cannot prove it is safe to send
/// between concurrency domains and `@unchecked Sendable` is a promise made in its
/// place. The promise here is kept by construction: `AudioCaptureService` copies
/// each buffer the engine hands it and ships the copy, which nothing else holds a
/// reference to. Exactly one owner at a time, no sharing, no mutation after
/// sending.
///
/// The copy is not pedantry. `AVAudioEngine` guarantees its tap buffer only for
/// the duration of the callback and is free to reuse the memory afterwards;
/// retaining it would mean reading audio that has already been overwritten.
struct CapturedBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    /// Deep-copies a tap buffer so it outlives the callback.
    /// Returns `nil` for non-float formats, which the input node does not produce.
    init?(copying source: AVAudioPCMBuffer) {
        guard
            let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength),
            let destination = copy.floatChannelData,
            let origin = source.floatChannelData
        else { return nil }

        copy.frameLength = source.frameLength

        let bytes = Int(source.frameLength) * MemoryLayout<Float>.size
        for channel in 0..<Int(source.format.channelCount) {
            memcpy(destination[channel], origin[channel], bytes)
        }

        self.buffer = copy
    }
}
