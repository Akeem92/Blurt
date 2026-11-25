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

    /// Where the last finished recording landed, so the capture can be judged by
    /// ear rather than by a moving bar.
    private(set) var lastRecordingURL: URL?

    /// The transcript as it is being spoken, for the pill to show. Cleared when a
    /// new dictation begins.
    private(set) var liveTranscript = ""

    /// The finished text of the last dictation.
    private(set) var lastTranscript = ""

    /// Built fresh each time so it always carries the current settings. A struct,
    /// so this costs nothing — and there is no stale copy to keep in step with
    /// the preferences.
    var engine: any TranscriptionEngine {
        var engine = AppleDictationEngine()
        engine.wantsPunctuation = preferences.isPunctuationEnabled
        engine.wantsEmoji = preferences.isEmojiEnabled
        return engine
    }

    let capture = AudioCaptureService()

    @ObservationIgnored
    private let preferences: Preferences

    /// Live input level for the waveform. Read at screen rate, never stored in
    /// `state`.
    var inputLevel: Float { capture.level.load() }

    @ObservationIgnored
    private var drainTask: Task<Void, Never>?

    @ObservationIgnored
    private var transcriptTask: Task<Void, Never>?

    @ObservationIgnored
    private var session: (any TranscriptionSession)?

    /// Set when a stop arrives during `.starting`, honoured as soon as the
    /// microphone is actually live.
    @ObservationIgnored
    private var stopRequested = false

    @ObservationIgnored
    private let log = Logger(subsystem: "com.blurt.app", category: "dictation")

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    // MARK: - Transitions

    /// idle or failed → recording
    ///
    /// Guarded on the state rather than on a boolean: a second shortcut press
    /// while a dictation is in flight simply finds the wrong state and does
    /// nothing.
    ///
    /// `.failed` starts a new dictation just as `.idle` does. A failure is a
    /// resting state with an explanation attached, not a latch — treating it as
    /// one meant that after a dictation caught no speech, the next press of the
    /// shortcut did nothing at all, with no clue as to why.
    func startRecording() async {
        switch state {
        case .idle, .failed: break
        case .starting, .recording, .transcribing, .cleaning, .inserting: return
        }

        stopRequested = false
        state = .starting

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

            // Transcription starts with the recording, not after it. By the time
            // the key is released the model has already heard almost everything,
            // so the wait at the end is a fraction of a second rather than
            // something proportional to how long the sentence was.
            let session = try await engine.beginSession(locale: preferences.transcriptionLocale)
            self.session = session

            liveTranscript = ""
            state = .recording(since: .now)

            // A stop that arrived while all this was being set up. Honoured now
            // that there is something to stop.
            if stopRequested {
                stopRequested = false
                capture.stop()
            }

            transcriptTask = Task { [weak self] in
                for await update in session.updates {
                    self?.liveTranscript = update.text
                }
            }

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
                    await session.feed(captured)
                    do {
                        try await writer.write(captured)
                    } catch {
                        logger.error("Dropped a buffer: \(error.localizedDescription)")
                    }
                }
                await self.finishRecording(savedTo: writer.url)
            }
        } catch {
            log.error("Could not start dictation: \(error.localizedDescription)")
            capture.stop()
            state = .failed((error as? DictationError) ?? .transcriptionFailed(reason: "\(error)"))
        }
    }

    /// recording → transcribing, by way of draining whatever is still in flight.
    func stopRecording() {
        switch state {
        case .recording:
            capture.stop()

        case .starting:
            // The key came up before the microphone was open. Remembering the
            // request is what stops a quick tap leaving the microphone running
            // for good — the alternative, silently ignoring it, is how that bug
            // happened in the first place.
            stopRequested = true

        case .idle, .transcribing, .cleaning, .inserting, .failed:
            break
        }
    }

    /// Called once the audio stream has run dry, so no words are lost to a buffer
    /// that was still in transit when the key came up.
    private func finishRecording(savedTo url: URL) async {
        drainTask = nil
        lastRecordingURL = url

        guard let session else {
            state = .idle
            return
        }
        self.session = nil

        state = .transcribing

        do {
            let text = try await session.finish()
            transcriptTask?.cancel()
            transcriptTask = nil

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                state = .failed(.noSpeechDetected)
                return
            }

            lastTranscript = trimmed
            liveTranscript = trimmed
            // Step 5 carries this into `.inserting`, step 6 cleans it on the way.
            state = .idle
        } catch {
            log.error("Transcription failed: \(error.localizedDescription)")
            transcriptTask?.cancel()
            transcriptTask = nil
            state = .failed(.transcriptionFailed(reason: "\(error)"))
        }
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
        case .idle: .starting
        case .starting: .recording(since: .now)
        case .recording: .transcribing
        case .transcribing: .cleaning(raw: "hello world")
        case .cleaning: .inserting(text: "Hello, world.")
        case .inserting: .failed(.noSpeechDetected)
        case .failed: .idle
        }
    }
    #endif
}
