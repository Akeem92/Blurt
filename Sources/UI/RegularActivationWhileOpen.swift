import SwiftUI
import AppKit

/// Promotes Blurt from a menu-bar accessory to a regular app for as long as the
/// window carrying this is open.
///
/// An `LSUIElement` app's windows are second-class citizens. The app is never
/// properly active, so clicking anything else sends its windows behind — and
/// with no Dock icon and no ⌘-Tab entry, there is no way to bring one back
/// except by going through the menu bar again. For a settings window that is
/// simply broken behaviour.
///
/// Taking `.regular` for the window's lifetime buys ordinary window semantics:
/// a Dock icon, a place in ⌘-Tab, click-to-restore. `.accessory` comes back the
/// moment the window closes, so the app returns to living only in the menu bar.
///
/// Deliberately opt-in per window: the recording pill in step 2b must do the
/// exact opposite and never take focus at all.
struct RegularActivationWhileOpen: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowWatchingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// An invisible view whose only job is to notice which window it landed in.
///
/// `viewDidMoveToWindow` rather than `onAppear`: SwiftUI's lifecycle says when a
/// *view* appears, which is not the same as when a *window* opens and closes.
private final class WindowWatchingView: NSView {
    private var closeObserver: (any NSObjectProtocol)?
    private var hasClaimed = false

    /// Fires both when the view lands in a window and when it leaves one, so a
    /// single method covers claiming and releasing.
    ///
    /// There is no `deinit` counterpart: in Swift 6 a deinitializer belongs to no
    /// actor, so it may not touch main-actor state, and reaching for
    /// `nonisolated(unsafe)` to get around that would be a promise with nothing
    /// behind it. Releasing here is enough — a view that is deallocated has first
    /// been removed from its window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        release()

        guard let window else { return }

        hasClaimed = true
        ActivationPolicy.promote()

        // Watching the window rather than this view: closing the settings window
        // is the event that matters, and it does not reliably take the view
        // hierarchy down with it.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.release() }
        }
    }

    /// Idempotent on purpose. Both the close notification and the view leaving
    /// its window can arrive for the same window, and demoting twice for one
    /// promotion would strand the app as an accessory with its settings still on
    /// screen.
    private func release() {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        guard hasClaimed else { return }
        hasClaimed = false
        ActivationPolicy.demote()
    }
}

/// Counts how many windows currently want the app to be a regular app, so two
/// open windows don't fight over the policy and the first one closed doesn't
/// demote the app out from under the second.
@MainActor
enum ActivationPolicy {
    private static var claims = 0

    static func promote() {
        claims += 1
        guard claims == 1 else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func demote() {
        claims = max(0, claims - 1)
        guard claims == 0 else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
