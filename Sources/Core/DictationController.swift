import Foundation
import Observation

/// Owns the one `RecordingState` the whole app agrees on, and will own the
/// transitions between its states.
///
/// `@MainActor` because every consumer so far is UI. When audio capture arrives
/// it will run off the main actor and hand results back here, and Swift 6's
/// strict concurrency checking will refuse to compile any shortcut around that.
///
/// `@Observable` is the Observation framework: SwiftUI views that read `state`
/// re-render when it changes, with no `@Published`, no `ObservableObject`, and
/// no needless redraws in views that happen to hold the controller but never
/// read the property.
@MainActor
@Observable
final class DictationController {
    /// Read-only from the outside: only this type decides what state the app is in.
    private(set) var state: RecordingState = .idle

    init() {}

    // MARK: - Transitions
    //
    // Deliberately empty for now. Each transition arrives with the piece of
    // machinery that triggers it, so there is no speculative code to keep
    // honest in the meantime:
    //
    //   step 2 — idle → recording → transcribing   (audio capture)
    //   step 3 — the shortcut that starts it
    //   step 4 — transcribing → cleaning           (SpeechAnalyzer)
    //   step 5 — cleaning → inserting → idle       (clipboard delivery)
    //   step 6 — the cleaning stage proper         (rules, then Claude)

    #if DEBUG
    /// Walks through every state so the menu-bar wiring can be eyeballed before
    /// any real machinery exists. Debug builds only.
    func debugCycleState() {
        state = switch state {
        case .idle: .recording(since: .now, level: 0.5)
        case .recording: .transcribing
        case .transcribing: .cleaning(raw: "hello world")
        case .cleaning: .inserting(text: "Hello, world.")
        case .inserting: .failed(.noSpeechDetected)
        case .failed: .idle
        }
    }
    #endif
}
