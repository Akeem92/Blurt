import SwiftUI
import AppKit

struct GeneralPane: View {
    @Bindable var preferences: Preferences

    @State private var launchesAtLogin = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.isDeniedByUser
    @State private var recordingCount = 0

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Blurt at login", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        LaunchAtLogin.set(enabled)
                        refresh()
                    }

                if needsApproval {
                    Label(
                        "macOS is waiting for your approval under General → Login Items.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("What Blurt keeps") {
                Label("Nothing is written to disk", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)

                Text("Audio goes from the microphone to the transcriber in memory and is gone the moment the dictation ends. The text is held only until the next one, for Copy Last Dictation, and is forgotten when Blurt quits. Nothing is logged, and nothing is kept between launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(preferences.usesClaudeCleanup
                     ? "Cleanup through Claude is on: the transcribed text — never the audio — is sent to Anthropic for tidying. Everything else stays on this Mac."
                     : "Everything happens on this Mac. Nothing leaves it.")
                    .font(.caption)
                    .foregroundStyle(preferences.usesClaudeCleanup ? .orange : .secondary)
            }

            Section("Diagnostics") {
                Toggle("Save recordings to disk", isOn: $preferences.keepsRecordings)
                Text("Off, and worth leaving off. Only useful if transcription ever goes wrong and the captured audio has to be listened to. Recordings are never deleted on their own, so they build up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if recordingCount > 0 {
                    HStack {
                        Text("\(recordingCount) recording\(recordingCount == 1 ? "" : "s") stored")
                            .font(.caption)
                        Spacer()
                        Button("Reveal") {
                            NSWorkspace.shared.open(AudioFileWriter.recordingsDirectory)
                        }
                        Button("Delete All", role: .destructive) {
                            AudioFileWriter.deleteAllRecordings()
                            refresh()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        launchesAtLogin = LaunchAtLogin.isEnabled
        needsApproval = LaunchAtLogin.isDeniedByUser
        recordingCount = AudioFileWriter.storedRecordingCount()
    }
}
