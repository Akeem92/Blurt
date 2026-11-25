import SwiftUI

struct InsertionPane: View {
    let controller: DictationController
    @Bindable var preferences: Preferences

    @State private var isTrusted = AccessibilityAccess.isTrusted

    var body: some View {
        Form {
            Section("Permission") {
                LabeledContent("Type into other apps") {
                    if isTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Allow…") {
                            // Shows the system alert the first time, and nothing
                            // at all after that — hence opening Settings too.
                            AccessibilityAccess.requestIfNeeded()
                            AccessibilityAccess.openSystemSettings()
                        }
                    }
                }

                Text(isTrusted
                     ? "Dictated text is typed wherever your cursor is."
                     : "Without this, Blurt can hear you and transcribe, but has nowhere to put the result. The text is left on the clipboard instead, one ⌘V away.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("While you dictate") {
                Toggle("Turn other audio down", isOn: $preferences.ducksOtherAudio)
                Text("The output volume drops while you speak and goes back afterwards, the way macOS does for Siri. Nothing is paused and nothing is started — Blurt cannot tell a paused video from a playing one without asking to record your system audio, which is not a reasonable thing for a dictation app to want. If you change the volume yourself mid-dictation, your choice is kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("How it works") {
                Text("The text goes on the clipboard, ⌘V is pressed for you, and whatever was on the clipboard before is put straight back — images and files included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("The clipboard is the only route that works everywhere: native apps, Electron apps and terminals alike.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !controller.lastTranscript.isEmpty {
                Section("Last dictation") {
                    Text(controller.lastTranscript)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        // The permission is granted in System Settings, not here, so the pane
        // has to notice it changing underneath it.
        .task {
            while !Task.isCancelled {
                isTrusted = AccessibilityAccess.isTrusted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
