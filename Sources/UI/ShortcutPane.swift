import SwiftUI
import KeyboardShortcuts

struct ShortcutPane: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section("Shortcut") {
                KeyboardShortcuts.Recorder("Start dictation", name: .dictate)

                Text("Works from any app, and is claimed outright — the keystroke never reaches whatever you are typing into. It keeps working while a password field is focused, which an event-watching shortcut would not.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                Picker("Mode", selection: $preferences.activationMode) {
                    ForEach(ActivationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(preferences.activationMode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ShortcutPane(preferences: Preferences(defaults: UserDefaults(suiteName: "preview")!))
}
