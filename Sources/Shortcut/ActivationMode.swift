import Foundation

/// How the shortcut starts and ends a dictation.
enum ActivationMode: String, CaseIterable, Identifiable, Sendable {
    /// Press and hold to speak, release to finish. Like a walkie-talkie.
    ///
    /// The better fit for short dictations — there is no way to leave the
    /// microphone open by accident, because letting go always ends it.
    case holdToTalk

    /// Press once to start, press again to stop.
    ///
    /// The better fit for long ones, and the only workable mode if holding a
    /// chord while speaking is uncomfortable.
    case toggle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdToTalk: "Hold to talk"
        case .toggle: "Press to start and stop"
        }
    }

    var detail: String {
        switch self {
        case .holdToTalk: "Hold the shortcut while you speak, release when you're done."
        case .toggle: "Press once to start listening, press again to finish."
        }
    }
}
