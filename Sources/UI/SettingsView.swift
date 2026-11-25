import SwiftUI

/// The settings window, opened with ⌘, or from the menu.
///
/// The tabs are laid out now and filled in as each step lands, so the shape of
/// the finished app is visible from the first build instead of being guessed at.
struct SettingsView: View {
    let controller: DictationController
    let preferences: Preferences

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralPane(preferences: preferences)
            }

            Tab("Shortcut", systemImage: "command") {
                ShortcutPane(preferences: preferences)
            }

            Tab("Microphone", systemImage: "mic") {
                MicrophonePane(controller: controller, preferences: preferences)
            }

            Tab("Transcription", systemImage: "waveform") {
                TranscriptionPane(controller: controller, preferences: preferences)
            }

            Tab("Insertion", systemImage: "text.cursor") {
                InsertionPane(controller: controller, preferences: preferences)
            }

            Tab("Cleanup", systemImage: "sparkles") {
                CleanupPane(preferences: preferences)
            }

        }
        .frame(width: 520, height: 420)
        // Keeps the window from vanishing behind other apps. Blurt stays an
        // accessory throughout: no Dock icon, no ⌘-Tab entry.
        .background(KeepsWindowInFront())
    }
}


#Preview {
    let preferences = Preferences(defaults: UserDefaults(suiteName: "preview")!)
    SettingsView(controller: DictationController(preferences: preferences), preferences: preferences)
}
