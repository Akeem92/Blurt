#if DEBUG
import AppKit
import Foundation

/// Headless checks, so behaviour that only shows up once real audio is flowing
/// can be verified without a human clicking anything.
///
/// Run with:
///     Blurt.app/Contents/MacOS/Blurt --selftest-capture
///
/// Must run from inside the app bundle: microphone permission is granted to the
/// bundle's signature, not to a loose binary.
enum SelfTest {
    static var requested: String? {
        CommandLine.arguments.first { $0.hasPrefix("--selftest-") }
    }

    @MainActor
    static func run(_ name: String) async -> Never {
        switch name {
        case "--selftest-capture": await captureTest()
        case "--selftest-record": await recordTest()
        default:
            FileHandle.standardError.write(Data("unknown self-test: \(name)\n".utf8))
            exit(64)
        }
    }

    /// Drives `DictationController` exactly as the Record button does, and checks
    /// that a playable file comes out the other end.
    ///
    /// The capture test above stops at the audio thread. This one covers the rest
    /// of the trip: the state machine, the detached drain loop, and the writer
    /// actor — which is to say every piece a human exercises with one click.
    @MainActor
    private static func recordTest() async -> Never {
        guard MicrophoneAccess.status == .granted else {
            print("FAIL  microphone not granted (status: \(MicrophoneAccess.status))")
            exit(3)
        }

        let controller = DictationController()
        controller.capture.isVoiceProcessingEnabled =
            CommandLine.arguments.contains("--voice-processing")

        await controller.startRecording()
        guard case .recording = controller.state else {
            print("FAIL  did not reach .recording (state: \(controller.state))")
            exit(1)
        }

        try? await Task.sleep(for: .seconds(2))
        controller.stopRecording()

        // Wait for the drain loop to finish and hand back a URL.
        for _ in 0..<50 where controller.lastRecordingURL == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard let url = controller.lastRecordingURL else {
            print("FAIL  recording never completed (state: \(controller.state))")
            exit(1)
        }

        let size = (try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil

        print("      file: \(url.path)")
        print("      bytes: \(size.map(String.init) ?? "unreadable")")
        print("      final state: \(controller.state)")

        // Two seconds of mono 32-bit float at 48 kHz is about 384 KB. Anything
        // near zero means the file was created but nothing reached it.
        guard let size, size > 100_000 else {
            print("FAIL  file is empty or far too small")
            exit(1)
        }

        print("PASS  recorded a playable file end to end")
        exit(0)
    }

    /// Opens the microphone for two seconds and reports what came back.
    ///
    /// The real subject here is the tap closure. An isolation mistake in it does
    /// not fail to compile and does not fail at launch — it traps on the first
    /// buffer, which is to say the first moment anyone speaks.
    @MainActor
    private static func captureTest() async -> Never {
        guard MicrophoneAccess.status == .granted else {
            print("FAIL  microphone not granted (status: \(MicrophoneAccess.status))")
            exit(3)
        }

        let capture = AudioCaptureService()
        capture.isVoiceProcessingEnabled = CommandLine.arguments.contains("--voice-processing")
        let meter = capture.level

        do {
            print("      voice processing: \(capture.isVoiceProcessingEnabled)")
            let buffers = try capture.start()
            print("      capture format:  \(capture.captureFormat.map(String.init(describing:)) ?? "none")")
            print("      delivery format: \(capture.deliveryFormat.map(String.init(describing:)) ?? "none")")

            let counting = Task.detached {
                var count = 0
                for await _ in buffers { count += 1 }
                return count
            }

            // Sampled off the main actor's clock, exactly as the UI does it.
            var peak: Float = 0
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(33))
                peak = max(peak, meter.load())
            }

            capture.stop()
            let count = await counting.value

            print("      buffers: \(count)")
            print(String(format: "      peak level: %.3f", peak))

            guard count > 0 else {
                print("FAIL  audio thread delivered nothing")
                exit(1)
            }
            print("PASS  tap survived \(count) buffers")
            exit(0)
        } catch {
            print("FAIL  could not start capture: \(error)")
            exit(2)
        }
    }
}
#endif
