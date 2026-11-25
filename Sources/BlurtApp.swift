import SwiftUI

/// Blurt is a menu-bar app: `LSUIElement` is true in Info.plist, so there is no
/// Dock icon and no main window. Everything hangs off the menu-bar item, the
/// settings window, and the floating recording pill.
@main
struct BlurtApp: App {
    /// The app delegate owns the dictation controller, because things that are
    /// not scenes — the recording pill above all — need to reach it too.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: delegate.controller)
        } label: {
            // Reading `state` here is what subscribes the menu-bar icon to it:
            // the symbol follows the state machine with no glue code.
            Image(systemName: delegate.controller.state.symbolName)
        }

        Settings {
            SettingsView(controller: delegate.controller, preferences: delegate.preferences)
        }
    }
}
