import SwiftUI
import AppKit

/// Shows and hides the recording pill as the dictation state changes.
///
/// Lives outside `DictationController` on purpose: the state machine should not
/// know that windows exist. It watches, it is not told.
@MainActor
final class RecordingPillPresenter {
    private let controller: DictationController
    private var panel: NSPanel?

    init(controller: DictationController) {
        self.controller = controller
        observeState()
    }

    /// Observation outside SwiftUI, re-armed by hand.
    ///
    /// `withObservationTracking` fires `onChange` exactly once, just *before* the
    /// property changes — hence hopping onto a fresh task to read the new value,
    /// and re-arming for the next change. Forget to re-arm and it silently
    /// watches nothing from then on.
    private func observeState() {
        withObservationTracking {
            _ = controller.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.update()
                self.observeState()
            }
        }
    }

    private func update() {
        switch controller.state {
        case .starting, .recording, .transcribing, .cleaning, .inserting:
            // Stays up past the end of recording: transcription finishes a beat
            // later, and the pill is where the last words land.
            show()
        case .idle, .failed:
            hide()
        }
    }

    // MARK: - Panel

    private func show() {
        guard panel == nil else { return }

        let hosting = NSHostingView(rootView: RecordingPill(controller: controller))
        hosting.frame = CGRect(origin: .zero, size: RecordingPill.Layout.windowSize)

        let panel = NonActivatingPanel(contentRect: hosting.frame)
        panel.contentView = hosting
        panel.setFrameOrigin(Self.restingOrigin(for: RecordingPill.Layout.windowSize))

        // orderFront, never makeKeyAndOrderFront: showing the pill must not take
        // the keyboard away from whatever the user is typing into.
        panel.orderFront(nil)
        self.panel = panel
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Bottom centre of whichever screen the pointer is on — where the user is
    /// already looking, and clear of the menu bar and the Dock.
    private static func restingOrigin(for size: CGSize) -> CGPoint {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .zero }

        return CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 96
        )
    }
}

/// A window that shows itself without ever taking focus.
///
/// This is the single most important property of the pill, and the reason it is
/// a hand-built `NSPanel` rather than a SwiftUI `Window`. Blurt inserts text into
/// whichever app is frontmost. A window that becomes key makes *Blurt* frontmost,
/// so the dictation would have nowhere to land — the app would quietly type into
/// itself.
///
/// Three independent guards, because one is not enough:
/// - `.nonactivatingPanel` stops a click on the panel activating the app.
/// - `canBecomeKey` / `canBecomeMain` return false, so it cannot take the
///   keyboard even if something asks it to.
/// - `ignoresMouseEvents` means clicks pass straight through to the app behind.
///   The pill has nothing to click yet; when it grows a stop button this is the
///   line to revisit, and the first two guards are what will still hold.
private final class NonActivatingPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        // Visible wherever the user happens to be, including over a full-screen
        // app, and not something ⌘-` cycles through.
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        // The capsule draws its own background; the window itself must not.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
