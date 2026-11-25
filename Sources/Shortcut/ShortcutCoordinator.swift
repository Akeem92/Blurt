import Foundation
import KeyboardShortcuts
import OSLog

extension KeyboardShortcuts.Name {
    /// The one shortcut Blurt owns. Registered through Carbon's
    /// `RegisterEventHotKey`, which claims the combination exclusively — so the
    /// keystroke never also reaches whatever app is in front.
    static let dictate = Self("dictate", initial: .init(.space, modifiers: [.option]))
}

/// Turns shortcut presses into dictation, according to the chosen mode.
///
/// Sits between the key events and `DictationController` rather than inside it:
/// the state machine should not care whether a dictation was started by a
/// keystroke, a menu item, or a test.
@MainActor
final class ShortcutCoordinator {
    private let controller: DictationController
    private let preferences: Preferences
    private let log = Logger(subsystem: "com.blurt.app", category: "shortcut")

    /// When the current hold began, or nil if the key is not down.
    private var holdStartedAt: Date?

    /// Below this, a press is a slip rather than an intention. Without it, brushing
    /// the shortcut opens and closes the microphone fast enough to leave a
    /// fraction of a second of audio and a transcription attempt over nothing.
    private static let minimumHold = Duration.milliseconds(200)

    init(controller: DictationController, preferences: Preferences) {
        self.controller = controller
        self.preferences = preferences

        KeyboardShortcuts.onKeyDown(for: .dictate) { [weak self] in
            self?.handleKeyDown()
        }
        KeyboardShortcuts.onKeyUp(for: .dictate) { [weak self] in
            self?.handleKeyUp()
        }
    }

    #if DEBUG
    /// Drives the same path a real key press takes, so the activation modes can
    /// be exercised without a physical keyboard.
    func simulatePress() { handleKeyDown() }
    func simulateRelease() { handleKeyUp() }
    #endif

    // MARK: - Events

    private func handleKeyDown() {
        switch preferences.activationMode {
        case .holdToTalk:
            holdStartedAt = .now
            Task { await controller.startRecording() }

        case .toggle:
            if case .recording = controller.state {
                controller.stopRecording()
            } else {
                Task { await controller.startRecording() }
            }
        }
    }

    private func handleKeyUp() {
        guard preferences.activationMode == .holdToTalk, let startedAt = holdStartedAt else {
            return
        }
        holdStartedAt = nil

        let held = Duration.seconds(Date.now.timeIntervalSince(startedAt))
        guard held >= Self.minimumHold else {
            // Too brief to be speech. Let the already-started recording reach a
            // usable length before ending it, rather than cancelling outright —
            // a hold of 180 ms is usually someone who meant to hold longer.
            log.debug("Hold was \(held.description); extending to the minimum")
            Task {
                try? await Task.sleep(for: Self.minimumHold - held)
                controller.stopRecording()
            }
            return
        }

        controller.stopRecording()
    }
}
