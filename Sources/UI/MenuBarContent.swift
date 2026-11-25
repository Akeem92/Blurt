import SwiftUI

/// The menu that drops down from the menu-bar icon.
///
/// `MenuBarExtra` in its default style renders this as a real `NSMenu`, so the
/// body is a flat list of menu items rather than a laid-out view hierarchy.
struct MenuBarContent: View {
    /// A plain `let`: `@Observable` tracks which properties a view actually reads,
    /// so no property wrapper is needed to get updates. `@Bindable` would only be
    /// required to hand a two-way binding to a control.
    let controller: DictationController

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(controller.state.statusDescription)

        if !controller.lastTranscript.isEmpty {
            Divider()

            // The deliberate way to get at a dictation that could not be
            // inserted. Blurt never puts anything on the clipboard behind your
            // back, so this is how the words are retrieved when pasting failed.
            Button("Copy Last Dictation") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(controller.lastTranscript, forType: .string)
            }
        }

        Divider()

        Button("Settings…") {
            // With LSUIElement the app is not in the Dock and has no windows, so
            // it is not activated by default — the settings window would open
            // behind whatever the user is looking at.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        #if DEBUG
        Divider()
        Button("Cycle State (Debug)") {
            controller.debugCycleState()
        }
        #endif

        Divider()

        Button("Quit Blurt") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
