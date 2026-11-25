import SwiftUI
import AppKit

/// Step 2's proving ground: grant the permission, watch the level, record, then
/// go and listen to what was actually captured.
struct MicrophonePane: View {
    let controller: DictationController

    @State private var permission = MicrophoneAccess.status

    var body: some View {
        Form {
            Section("Permission") {
                LabeledContent("Microphone") {
                    switch permission {
                    case .granted:
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .undetermined:
                        Button("Ask…") {
                            Task {
                                _ = await MicrophoneAccess.request()
                                permission = MicrophoneAccess.status
                            }
                        }
                    case .denied:
                        Button("Open System Settings…") {
                            MicrophoneAccess.openSystemSettings()
                        }
                    }
                }
            }

            Section("Input") {
                // `TimelineView(.animation)` is driven by the display refresh, so
                // the level is *sampled* here rather than pushed from the audio
                // thread. That is the whole point of keeping it out of the state
                // machine: two independent clocks, neither waiting on the other.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !controller.capture.isRunning)) { _ in
                    LevelBar(level: controller.capture.isRunning ? controller.inputLevel : 0)
                }

                Toggle("Voice processing", isOn: voiceProcessingBinding)
                    .disabled(controller.capture.isRunning)
                Text("Echo cancellation and noise reduction, and macOS turns other apps' audio down while you speak. Record once with it and once without, then compare the two files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    recordButton
                    Spacer()
                    if let url = controller.lastRecordingURL {
                        Button("Show Last Recording") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }

                if case .failed(let error) = controller.state {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(error.errorDescription ?? "Something went wrong")
                            if let hint = error.recoverySuggestion {
                                Text(hint).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { permission = MicrophoneAccess.status }
    }

    private var voiceProcessingBinding: Binding<Bool> {
        Binding(
            get: { controller.capture.isVoiceProcessingEnabled },
            set: { controller.capture.isVoiceProcessingEnabled = $0 }
        )
    }

    @ViewBuilder
    private var recordButton: some View {
        if case .recording = controller.state {
            Button("Stop", systemImage: "stop.fill") { controller.stopRecording() }
                .tint(.red)
        } else {
            Button("Record", systemImage: "record.circle") {
                controller.dismissFailure()
                Task { await controller.startRecording() }
            }
            .disabled(permission == .denied)
        }
    }
}

/// A plain level bar. The waveform proper arrives with the recording pill.
private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(level > 0.95 ? Color.red : Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(level))
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 1.0 / 30.0), value: level)
    }
}
