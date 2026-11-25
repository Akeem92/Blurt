import SwiftUI

struct CleanupPane: View {
    @Bindable var preferences: Preferences

    @State private var apiKey = ""
    @State private var hasStoredKey = APIKeyStore.hasKey

    var body: some View {
        Form {
            Section("Always on") {
                Toggle("Remove filler sounds", isOn: $preferences.removesFillers)
                Text("\"euh\", \"hum\", \"um\" and the like. Sounds, not words — nobody means to type them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Local typography", isOn: $preferences.appliesLocalTypography)
                Text("In French, the non-breaking space before ; ! ? and : that English-trained models never add. Its absence is the first thing a French reader notices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("These are rules, so they run instantly, cost nothing and work offline. Punctuation itself is already handled during transcription.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Claude") {
                Toggle("Tidy up with Claude", isOn: $preferences.usesClaudeCleanup)
                    .disabled(!hasStoredKey)

                Text("For what no rule can express: applying a spoken correction — \"send it to Marc, no sorry, to Julie\" — and fixing a sentence that came out tangled. Conservative by instruction: it never rewrites your words or changes your register.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("API key") {
                    HStack {
                        if hasStoredKey {
                            Label("Stored in the Keychain", systemImage: "key.fill")
                                .foregroundStyle(.green)
                            Button("Remove") {
                                APIKeyStore.delete()
                                hasStoredKey = false
                                preferences.usesClaudeCleanup = false
                            }
                        } else {
                            SecureField("sk-ant-…", text: $apiKey)
                                .frame(width: 200)
                            Button("Save") {
                                if APIKeyStore.save(apiKey) {
                                    apiKey = ""
                                    hasStoredKey = true
                                }
                            }
                            .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                Text("Your own key, from console.anthropic.com. Only the transcribed text is sent — never the audio — and only while this is switched on. Blurt uses Claude Haiku, which costs a fraction of a cent per dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("If the request is slow or fails, the rule-cleaned text is used instead. A poor connection costs you a little polish, never the dictation.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .onAppear { hasStoredKey = APIKeyStore.hasKey }
    }
}
