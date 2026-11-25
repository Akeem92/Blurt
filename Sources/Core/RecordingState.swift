import Foundation

/// Everything that can be true about one dictation, from key press to inserted text.
///
/// Why an enum and not a handful of booleans: these situations are mutually
/// exclusive by nature, and each needs different data attached. Spelling them as
/// `isRecording` / `isTranscribing` / `lastError` would make nonsense states
/// representable — recording *and* transcribing at once, a failure with no error —
/// and nothing in the language would stop us writing one by accident.
///
/// Here those combinations have no spelling at all, so the bug class is designed
/// out rather than tested for. The cost is that every `switch` must handle every
/// case, which is exactly the point: adding a state later makes the compiler walk
/// us through each place that needs to know about it.
enum RecordingState {
    /// Waiting for the shortcut. The only state a new dictation may start from.
    case idle

    /// The microphone is live and audio is being captured.
    ///
    /// The input level is deliberately *not* here. It changes sixty times a
    /// second to animate a waveform, and routing that through the state machine
    /// would mean sixty state changes a second to say "still recording". It lives
    /// in `AudioLevelMeter` instead, on its own clock. States change when
    /// something changes; levels are sampled.
    case recording(since: Date)

    /// Capture is finished; audio is being turned into text.
    case transcribing

    /// A raw transcript exists and is being tidied up.
    case cleaning(raw: String)

    /// Final text is on its way into whichever app has focus.
    case inserting(text: String)

    /// The attempt ended badly and the user needs to know why.
    case failed(DictationError)
}

// MARK: - Derived properties

extension RecordingState {
    /// True while a dictation owns the app. The shortcut must not start another.
    var isActive: Bool {
        switch self {
        case .idle, .failed:
            false
        case .recording, .transcribing, .cleaning, .inserting:
            true
        }
    }

    /// SF Symbol for the menu bar.
    var symbolName: String {
        switch self {
        case .idle: "waveform"
        case .recording: "waveform.circle.fill"
        case .transcribing: "ellipsis.circle"
        case .cleaning: "sparkles"
        case .inserting: "text.cursor"
        case .failed: "exclamationmark.triangle"
        }
    }

    /// One line of plain English for the menu.
    var statusDescription: String {
        switch self {
        case .idle: "Ready"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .cleaning: "Cleaning up…"
        case .inserting: "Inserting…"
        case .failed(let error): error.errorDescription ?? "Something went wrong"
        }
    }
}
