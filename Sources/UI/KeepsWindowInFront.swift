import SwiftUI
import AppKit

/// Keeps the window carrying this above other apps' windows, for as long as it
/// is open.
///
/// The problem it solves: an `LSUIElement` app is never properly active, so
/// clicking any other app sends its windows behind — and with no Dock icon and
/// no ⌘-Tab entry there is nothing to click to bring one back. The settings
/// window would simply vanish.
///
/// Raising the window's level fixes that without Blurt pretending to be an
/// ordinary app. No Dock icon appears, no ⌘-Tab entry appears, and the window
/// stays where you left it. The price is that it sits above whatever you do next
/// until you close it, which for a settings window you opened on purpose is the
/// bargain worth making.
///
/// Deliberately opt-in per window. The recording pill in step 2b also floats,
/// but must additionally never take focus — a window that takes focus makes the
/// app meant to receive the dictated text stop being frontmost.
struct KeepsWindowInFront: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowConfiguringView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// An invisible view whose only job is to configure the window it lands in.
///
/// `viewDidMoveToWindow` rather than `onAppear`: SwiftUI reports when a *view*
/// appears, which is not the same moment a *window* exists to be configured.
private final class WindowConfiguringView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }

        // Above normal windows, below the menu bar and system alerts.
        window.level = .floating

        // Without this an accessory app's window is ordered out the moment the
        // app deactivates — which is the disappearance being fixed here.
        window.hidesOnDeactivate = false

        // Follow the user across Spaces rather than yanking them back to the
        // Space the window was opened in.
        window.collectionBehavior.insert(.moveToActiveSpace)
    }
}
