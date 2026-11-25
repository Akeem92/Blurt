import SwiftUI

struct TranscriptionPane: View {
    let controller: DictationController
    @Bindable var preferences: Preferences

    @State private var locales: [Locale] = []
    @State private var readiness: ModelReadiness = .needsDownload
    @State private var downloadProgress: Double?
    @State private var downloadError: String?

    var body: some View {
        Form {
            Section("Language") {
                Picker("Dictate in", selection: $preferences.transcriptionLanguage) {
                    ForEach(locales, id: \.identifier) { locale in
                        Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
                            .tag(locale.identifier(.bcp47))
                    }
                }
                .disabled(locales.isEmpty)

                Text("One language at a time: the model cannot switch mid-sentence. Pick the one you actually dictate in, which is not always the language your Mac is set to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                LabeledContent("Status") { statusLabel }

                if readiness == .needsDownload, downloadProgress == nil {
                    Button("Download…") { download() }
                }

                if let progress = downloadProgress, progress < 1 {
                    ProgressView(value: progress)
                }

                if let downloadError {
                    Text(downloadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Downloaded once, then everything happens on this Mac — no account, no server, and it works offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Text") {
                Toggle("Punctuation", isOn: $preferences.isPunctuationEnabled)
                Text("Adds punctuation for you, and understands it spoken aloud — saying \"comma\" types one. Without this the transcript is one unbroken run of words.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Emoji", isOn: $preferences.isEmojiEnabled)
                Text("Turns \"smiley face\" into 🙂.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: preferences.transcriptionLanguage) { await refresh() }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch readiness {
        case .ready:
            Label("Ready, works offline", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsDownload:
            Label("Not downloaded", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .downloading:
            Label("Downloading…", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .unsupported:
            Label("Not available for this language", systemImage: "xmark.circle")
                .foregroundStyle(.orange)
        }
    }

    private func refresh() async {
        let engine = controller.engine
        if locales.isEmpty {
            locales = await engine.supportedLocales().sorted {
                ($0.localizedString(forIdentifier: $0.identifier) ?? $0.identifier)
                    < ($1.localizedString(forIdentifier: $1.identifier) ?? $1.identifier)
            }
        }
        readiness = await engine.readiness(for: preferences.transcriptionLocale)
        downloadProgress = nil
        downloadError = nil
    }

    private func download() {
        let engine = controller.engine
        let locale = preferences.transcriptionLocale
        downloadProgress = 0
        downloadError = nil

        Task {
            do {
                try await engine.prepare(locale) { fraction in
                    Task { @MainActor in downloadProgress = fraction }
                }
                await refresh()
            } catch {
                downloadError = error.localizedDescription
                downloadProgress = nil
            }
        }
    }
}
