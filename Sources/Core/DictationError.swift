import Foundation

/// Every way a dictation can fail, as one closed set.
///
/// Closed because the menu, the notification and the settings pane all need to
/// react differently depending on the cause — a denied permission deserves a
/// button to System Settings, a transcription hiccup only deserves a retry.
/// A bare `Error` would push that branching into string matching.
enum DictationError: Error, Equatable {
    /// The user has not granted microphone access, or revoked it.
    case microphonePermissionDenied

    /// Accessibility access is missing, so text cannot reach the frontmost app.
    case accessibilityPermissionDenied

    /// Capture succeeded but held no speech worth transcribing.
    case noSpeechDetected

    /// The transcription engine failed. The payload is for the log, not the user.
    case transcriptionFailed(reason: String)

    /// Cleanup failed. Never fatal: the raw transcript is still usable.
    case cleaningFailed(reason: String)

    /// The text could not be delivered to the frontmost app.
    case insertionFailed(reason: String)
}

extension DictationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Blurt can't reach the microphone"
        case .accessibilityPermissionDenied:
            "Blurt can't type into other apps"
        case .noSpeechDetected:
            "Didn't catch any speech"
        case .transcriptionFailed:
            "Couldn't transcribe that"
        case .cleaningFailed:
            "Couldn't clean up the text"
        case .insertionFailed:
            "Couldn't insert the text"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            "Allow Blurt under Privacy & Security → Microphone in System Settings."
        case .accessibilityPermissionDenied:
            "Allow Blurt under Privacy & Security → Accessibility in System Settings."
        case .noSpeechDetected:
            "Try again, a little closer to the microphone."
        case .transcriptionFailed:
            "Try again. If it keeps happening, switch engines in Settings."
        case .cleaningFailed:
            "The raw transcript was used instead."
        case .insertionFailed:
            "The text was copied to the clipboard instead — paste it with ⌘V."
        }
    }
}
