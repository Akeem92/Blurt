import Foundation
import Observation
import OSLog

/// Owns the one `RecordingState` the whole app agrees on, and the transitions
/// between its states.
///
/// `@MainActor` because this coordinates UI and audio-engine calls, both of which
/// want one predictable home. Work that must not run here — writing audio to
/// disk, and later transcription — is pushed onto actors that own their own
/// resources, and Swift 6's concurrency checking refuses to compile a shortcut
/// around that.
///
/// `@Observable` is the Observation framework: views that read `state` re-render
/// when it changes, with no `@Published`, no `ObservableObject`, and no redraws
/// in views that hold the controller but never read the property.
@MainActor
@Observable
final class DictationController {
    /// Read-only from the outside: only this type decides what state the app is in.
    private(set) var state: RecordingState = .idle

    /// Where the last finished recording landed. Step 2 only — this is how the
    /// capture gets judged by ear instead of by a moving bar.
    private(set) var lastRecordingURL: URL?

    let capture = AudioCaptureService()

    @ObservationIgnored
    private let preferences: Preferences

    /// Live input level for the waveform. Read at screen rate, never stored in
    /// `state`.
    var inputLevel: Float { capture.level.load() }

    @ObservationIgnored
    private var drainTask: Task<Void, Never>?

    @ObservationIgnored
    private let log = Logger(subsystem: "com.blurt.app", category: "dictation")

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    // MARK: - Transitions

    /// idle → recording
    ///
    /// Guarded on `.idle` rather than on a boolean: a second shortcut press while
    /// a dictation is in flight simply finds the wrong state and does nothing.
    func startRecording() async {
        guard case .idle = state else { return }

        if await !ensureMicrophoneAccess() { return }

        // Applied here rather than when the toggles move: these only take effect
        // at `start()`, so reading them now is also what makes them survive a
        // relaunch without a separate wiring step.
        capture.isVoiceProcessingEnabled = preferences.isVoiceProcessingEnabled
        capture.isAutomaticGainControlEnabled = preferences.isAutomaticGainControlEnabled

        do {
            let buffers = try capture.start()
            // The *delivery* format, not the capture format: buffers arrive mono
            // whatever the input node is configured as.
            guard let format = capture.deliveryFormat else {
                state = .failed(.transcriptionFailed(reason: "No delivery format"))
                return
            }

            let writer = try AudioFileWriter(url: AudioFileWriter.newRecordingURL(), format: format)
            state = .recording(since: .now)

            // `Task.detached`, not plain `Task`. A plain `Task` created inside a
            // `@MainActor` method *inherits* that isolation, so this loop would
            // run on the main actor and wake it for every buffer — around
            // twenty-three times a second, purely to hand work to someone else.
            // Detaching says plainly: this belongs nowhere in particular.
            //
            // The loop ends by itself when `capture.stop()` finishes the stream —
            // no cancellation flag, no "are we still recording" check inside.
            let logger = log
            drainTask = Task.detached {
                for await captured in buffers {
                    do {
                        try await writer.write(captured)
                    } catch {
                        logger.error("Dropped a buffer: \(error.localizedDescription)")
                    }
                }
                await self.finishRecording(savedTo: writer.url)
            }
        } catch {
            log.error("Could not start capture: \(error.localizedDescription)")
            state = .failed(.transcriptionFailed(reason: "\(error)"))
        }
    }

    /// recording → idle, by way of draining whatever is still in the stream.
    func stopRecording() {
        guard case .recording = state else { return }
        capture.stop()
    }

    /// Called once the stream has run dry, so nothing in flight is lost.
    private func finishRecording(savedTo url: URL) {
        drainTask = nil
        lastRecordingURL = url
        // Step 4 turns this into `.transcribing`. For now the trip ends here.
        state = .idle
    }

    // MARK: - Permission

    /// Returns true if the microphone is usable, asking the user if it has never
    /// been asked. Sets `state` to a failure if it is not.
    private func ensureMicrophoneAccess() async -> Bool {
        switch MicrophoneAccess.status {
        case .granted:
            return true
        case .denied:
            state = .failed(.microphonePermissionDenied)
            return false
        case .undetermined:
            if await MicrophoneAccess.request() { return true }
            state = .failed(.microphonePermissionDenied)
            return false
        }
    }

    /// Clears a failure so the next attempt starts from `.idle`.
    func dismissFailure() {
        if case .failed = state { state = .idle }
    }

    #if DEBUG
    /// Walks through every state so the menu-bar wiring can be eyeballed without
    /// a microphone. Debug builds only.
    func debugCycleState() {
        state = switch state {
        case .idle: .recording(since: .now)
        case .recording: .transcribing
        case .transcribing: .cleaning(raw: "hello world")
        case .cleaning: .inserting(text: "Hello, world.")
        case .inserting: .failed(.noSpeechDetected)
        case .failed: .idle
        }
    }
    #endif
}
