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
    /// Always mono, whatever the input node happened to hand over.
    let buffer: AVAudioPCMBuffer

    /// Deep-copies the first channel of a tap buffer into a mono buffer.
    ///
    /// Mono is not a simplification, it is a normalisation. Switching Apple's
    /// voice processing on changes the input node from one channel to three:
    /// the processed microphone plus reference channels the echo canceller
    /// works from. Those extra channels are plumbing, not speech. Passing them
    /// downstream would make recordings with and without voice processing
    /// incomparable, and would have to be undone again before transcription,
    /// which wants one channel.
    ///
    /// Channel 0 is the processed microphone signal in both configurations.
    ///
    /// Returns `nil` for non-float formats, which the input node does not produce.
    init?(copyingChannel0Of source: AVAudioPCMBuffer, as format: AVAudioFormat) {
        guard
            source.format.sampleRate == format.sampleRate,
            let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: source.frameLength),
            let destination = copy.floatChannelData,
            let origin = source.floatChannelData
        else { return nil }

        copy.frameLength = source.frameLength
        memcpy(
            destination[0],
            origin[0],
            Int(source.frameLength) * MemoryLayout<Float>.size
        )

        self.buffer = copy
    }
}
