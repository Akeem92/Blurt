import SwiftUI

/// Blurt is a menu-bar app: `LSUIElement` is true in Info.plist, so there is no
/// Dock icon and no main window. Everything hangs off the menu-bar item and the
/// settings window.
@main
struct BlurtApp: App {
    /// `@State` on a reference type is how SwiftUI is told to create this once and
    /// keep it alive for the whole app session, rather than on every body re-run.
    @State private var controller = DictationController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(controller: controller)
        } label: {
            // Reading `state` here is what subscribes the menu-bar icon to it:
            // the symbol follows the state machine with no glue code.
            Image(systemName: controller.state.symbolName)
        }

        Settings {
            SettingsView(controller: controller)
        }
    }
}
