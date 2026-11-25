import AVFoundation
import Accelerate

/// Opens the microphone and turns it into an `AsyncStream` of audio buffers.
///
/// `AsyncStream` is not an arbitrary choice: it is the shape `SpeechAnalyzer`
/// consumes in step 4, so the pipeline built here is the one transcription will
/// plug straight into.
///
/// Main-actor isolated because `AVAudioEngine` is not thread-safe and every call
/// into it should come from one place. The tap callback is the exception — it
/// arrives on an engine-owned audio thread, and everything it touches is either
/// `Sendable` or freshly allocated.
@MainActor
final class AudioCaptureService {
    /// Latest input level, 0...1. Written by the audio thread, read by the UI.
    let level = AudioLevelMeter()

    /// Apple's voice-processing unit: echo cancellation, noise suppression, and
    /// automatic ducking of other apps' audio on the same output device — the
    /// same machinery FaceTime uses. Must be set before `start()`; it changes the
    /// format the input node delivers.
    var isVoiceProcessingEnabled = false

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<CapturedBuffer>.Continuation?

    /// Format the input node is currently delivering. With voice processing on,
    /// this is three channels: the processed microphone plus echo-canceller
    /// reference channels.
    private(set) var captureFormat: AVAudioFormat?

    /// Format the buffers in the stream actually arrive in: always mono, so the
    /// rest of the app never has to care which way voice processing is set.
    private(set) var deliveryFormat: AVAudioFormat?

    var isRunning: Bool { engine.isRunning }

    // MARK: - Lifecycle

    /// Opens the microphone and starts delivering buffers.
    ///
    /// The returned stream finishes when `stop()` is called, so a `for await` loop
    /// over it ends on its own and needs no cancellation flag.
    func start() throws -> AsyncStream<CapturedBuffer> {
        guard !engine.isRunning else { throw CaptureFailure.alreadyRunning }

        let input = engine.inputNode

        // Order matters: enabling voice processing reconfigures the node, so the
        // format has to be read afterwards.
        if input.isVoiceProcessingEnabled != isVoiceProcessingEnabled {
            try input.setVoiceProcessingEnabled(isVoiceProcessingEnabled)
        }

        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureFailure.noInputDevice
        }
        captureFormat = format

        guard let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1) else {
            throw CaptureFailure.noInputDevice
        }
        deliveryFormat = mono

        // Unbounded: dropping microphone audio to save memory would mean losing
        // words. A dictation is seconds long, so the buffer cannot grow far.
        let (stream, continuation) = AsyncStream<CapturedBuffer>.makeStream(
            bufferingPolicy: .unbounded
        )
        self.continuation = continuation

        // `@Sendable` on this closure is load-bearing, and its absence does not
        // fail to compile — it crashes on the first buffer.
        //
        // `AVAudioNodeTapBlock` carries no `@Sendable` annotation in the SDK, so
        // without one here Swift infers the closure to be isolated to this type's
        // actor, the main actor. It does not complain: it quietly inserts a
        // runtime isolation check. AVFoundation then calls the block from its own
        // audio queue, the check fails, and the process traps with
        // `dispatch_assert_queue_fail`. Compiles clean, dies the instant real
        // audio arrives.
        //
        // `@Sendable` states the truth — this runs anywhere — so no check is
        // inserted, and in exchange the compiler now verifies that everything
        // captured is safe to send. Hence capturing `meter` and `continuation`
        // explicitly rather than reaching through `self`.
        //
        // 2048 frames is roughly 43 ms at 48 kHz: frequent enough for a
        // responsive waveform, large enough not to wake the consumer constantly.
        let meter = level
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable buffer, _ in
            meter.store(Self.normalizedLevel(of: buffer))
            if let captured = CapturedBuffer(copyingChannel0Of: buffer, as: mono) {
                continuation.yield(captured)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            self.continuation = nil
            captureFormat = nil
            deliveryFormat = nil
            throw CaptureFailure.engineFailed(error.localizedDescription)
        }

        return stream
    }

    /// Closes the microphone and ends the stream.
    func stop() {
        guard engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        captureFormat = nil
        deliveryFormat = nil
        level.store(0)
    }

    // MARK: - Metering

    /// Loudness of one buffer as 0...1, ready to drive a bar or a waveform.
    ///
    /// Runs on the audio thread, so: no allocation, no locks, no Foundation.
    /// `vDSP` does the sum of squares in vectorised form in a single call.
    ///
    /// `nonisolated` is required, not decorative. A `static` member of a
    /// `@MainActor` type inherits that isolation — even one that is pure
    /// arithmetic and touches no state. Calling it from the audio thread without
    /// this keyword is what trapped the process.
    ///
    /// The decibel conversion is what makes the result feel right. Raw amplitude
    /// is linear, but hearing is logarithmic: normal speech sits around 0.05
    /// amplitude and would barely move a linear bar. Mapping −50 dB...0 dB onto
    /// 0...1 puts conversation in the middle of the range, where it belongs.
    private nonisolated static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return 0
        }

        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        let rms = vDSP.rootMeanSquare(samples)

        let floorDB: Float = -50
        let decibels = 20 * log10(max(rms, 1e-7))
        return min(max((decibels - floorDB) / -floorDB, 0), 1)
    }

    // MARK: - Failures

    enum CaptureFailure: Error {
        case alreadyRunning
        case noInputDevice
        case engineFailed(String)
    }
}
