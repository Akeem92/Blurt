import SwiftUI

/// The settings window, opened with ⌘, or from the menu.
///
/// The tabs are laid out now and filled in as each step lands, so the shape of
/// the finished app is visible from the first build instead of being guessed at.
struct SettingsView: View {
    let controller: DictationController

    var body: some View {
        TabView {
            Tab("Microphone", systemImage: "mic") {
                MicrophonePane(controller: controller)
            }

            Tab("Shortcut", systemImage: "command") {
                ComingSoonPane(
                    title: "Shortcut",
                    detail: "Pick the key, and choose between hold-to-talk and press-to-toggle.",
                    step: 3
                )
            }

            Tab("Transcription", systemImage: "waveform") {
                ComingSoonPane(
                    title: "Transcription",
                    detail: "Engine and language. Apple SpeechAnalyzer first, others later.",
                    step: 4
                )
            }

            Tab("Cleanup", systemImage: "sparkles") {
                ComingSoonPane(
                    title: "Cleanup",
                    detail: "Punctuation and filler removal, plus optional polishing by Claude.",
                    step: 6
                )
            }

            Tab("Appearance", systemImage: "paintpalette") {
                ComingSoonPane(
                    title: "Appearance",
                    detail: "Accent colour and the look of the recording pill.",
                    step: 7
                )
            }
        }
        .frame(width: 500, height: 360)
        // Keeps the window from vanishing behind other apps. Blurt stays an
        // accessory throughout: no Dock icon, no ⌘-Tab entry.
        .background(KeepsWindowInFront())
    }
}

/// Placeholder for a pane whose step has not been built yet.
private struct ComingSoonPane: View {
    let title: String
    let detail: String
    let step: Int

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title2.weight(.semibold))

            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            Text("Step \(step)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    SettingsView(controller: DictationController())
}
