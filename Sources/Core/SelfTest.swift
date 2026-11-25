#if DEBUG
import AppKit
import AVFoundation
import Accelerate
import Foundation
import Synchronization

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
        case "--selftest-channels": await channelsTest()
        case "--selftest-pill": await pillTest()
        default:
            FileHandle.standardError.write(Data("unknown self-test: \(name)\n".utf8))
            exit(64)
        }
    }

    /// Checks that showing the recording pill does not take focus from whatever
    /// app the user is actually working in.
    ///
    /// This is the one property the pill must never lose. Blurt types into the
    /// frontmost app; a pill that becomes key makes *Blurt* frontmost, and the
    /// dictation ends up with nowhere to land. Run this from a terminal, which
    /// stays frontmost throughout since Blurt is an accessory app.
    @MainActor
    private static func pillTest() async -> Never {
        guard MicrophoneAccess.status == .granted else {
            print("FAIL  microphone not granted")
            exit(3)
        }

        func frontmost() -> String {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        }

        let before = frontmost()
        print("      frontmost before: \(before)")

        let controller = DictationController()
        let presenter = RecordingPillPresenter(controller: controller)
        _ = presenter  // held for the duration of the test

        await controller.startRecording()
        try? await Task.sleep(for: .milliseconds(600))

        let panels = NSApp.windows.filter { $0 is NSPanel && $0.isVisible }
        let during = frontmost()
        print("      frontmost while recording: \(during)")
        print("      visible panels: \(panels.count)")

        guard let pill = panels.first else {
            print("FAIL  pill never appeared")
            exit(1)
        }
        print("      pill frame: \(pill.frame)")
        print("      canBecomeKey: \(pill.canBecomeKey)   isKeyWindow: \(pill.isKeyWindow)")

        var failures: [String] = []
        if during != before { failures.append("focus moved from \(before) to \(during)") }
        if pill.canBecomeKey { failures.append("pill can become key window") }
        if pill.isKeyWindow { failures.append("pill took the keyboard") }

        controller.stopRecording()
        for _ in 0..<50 where controller.lastRecordingURL == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(300))

        let stillVisible = NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.count
        print("      visible panels after stop: \(stillVisible)")
        if stillVisible > 0 { failures.append("pill stayed on screen after recording ended") }

        guard failures.isEmpty else {
            for failure in failures { print("FAIL  \(failure)") }
            exit(1)
        }
        print("PASS  pill shown and hidden without taking focus")
        exit(0)
    }

    /// Measures each channel the input node delivers, separately.
    ///
    /// Turning voice processing on takes the input node from one channel to
    /// three, and nothing in the API says which is which. The rest of the app
    /// assumes channel 0 carries the processed microphone — this is how that
    /// assumption gets checked rather than believed.
    ///
    /// Play something through the speakers while this runs: the echo-canceller
    /// reference channels should carry that sound loudly, and the microphone
    /// channel should have had it removed.
    @MainActor
    private static func channelsTest() async -> Never {
        guard MicrophoneAccess.status == .granted else {
            print("FAIL  microphone not granted")
            exit(3)
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let wantsVoiceProcessing = CommandLine.arguments.contains("--voice-processing")

        do {
            try input.setVoiceProcessingEnabled(wantsVoiceProcessing)
        } catch {
            print("FAIL  could not set voice processing: \(error)")
            exit(2)
        }

        print("      voice processing: \(input.isVoiceProcessingEnabled)")
        print("      automatic gain control: \(input.isVoiceProcessingAGCEnabled)")
        print("      inputFormat  (hardware):   \(input.inputFormat(forBus: 0))")
        print("      outputFormat (after node): \(input.outputFormat(forBus: 0))")

        // nil means "whatever this node outputs", which is the only format the
        // tap is actually guaranteed to receive.
        let format = input.outputFormat(forBus: 0)
        let channels = Int(format.channelCount)

        if input.isVoiceProcessingEnabled, CommandLine.arguments.contains("--no-agc") {
            input.isVoiceProcessingAGCEnabled = false
            print("      automatic gain control forced off")
        }

        let stats = ChannelStats(channelCount: channels)
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { @Sendable buffer, _ in
            stats.observe(buffer)
        }

        engine.prepare()
        do { try engine.start() } catch {
            print("FAIL  engine: \(error)")
            exit(2)
        }

        try? await Task.sleep(for: .seconds(4))

        input.removeTap(onBus: 0)
        engine.stop()

        // Identical statistics across channels would mean they carry identical
        // data; raw samples settle it beyond doubt.
        if let samples = stats.sampleDump() {
            print("      first samples per channel:")
            for (index, values) in samples.enumerated() {
                print("        ch\(index): " + values.map { String(format: "%+.5f", $0) }.joined(separator: "  "))
            }
        }

        for (index, measurement) in stats.snapshot().enumerated() {
            print(String(
                format: "      channel %d   peak %.4f   rms %.4f   %@",
                index, measurement.peak, measurement.rms,
                measurement.peak < 0.0005 ? "(silent)" : ""
            ))
        }
        exit(0)
    }

    /// Per-channel loudness, gathered from the audio thread.
    ///
    /// A `Mutex` rather than the lock-free atomic the production meter uses:
    /// this is a diagnostic accumulating an array, not a value on the hot path,
    /// and clarity matters more here than shaving a lock.
    private final class ChannelStats: Sendable {
        struct Measurement { var peak: Float = 0; var rms: Float = 0; var blocks: Int = 0 }

        private let storage: Mutex<[Measurement]>
        private let samples = Mutex<[[Float]]?>(nil)

        init(channelCount: Int) {
            storage = Mutex(Array(repeating: Measurement(), count: channelCount))
        }

        /// A few raw samples from one mid-stream buffer, captured once.
        func sampleDump() -> [[Float]]? { samples.withLock { $0 } }

        func observe(_ buffer: AVAudioPCMBuffer) {
            guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let frames = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)

            samples.withLock { stored in
                guard stored == nil, frames > 600 else { return }
                stored = (0..<channelCount).map { channel in
                    (500..<505).map { data[channel][$0] }
                }
            }

            storage.withLock { measurements in
                // The buffer the tap actually receives, not the format that was
                // requested — the two can differ, which is the whole point here.
                let available = min(measurements.count, Int(buffer.format.channelCount))
                for channel in 0..<available {
                    let samples = UnsafeBufferPointer(start: data[channel], count: frames)
                    measurements[channel].peak = max(
                        measurements[channel].peak,
                        vDSP.maximumMagnitude(samples)
                    )
                    measurements[channel].rms += vDSP.rootMeanSquare(samples)
                    measurements[channel].blocks += 1
                }
            }
        }

        func snapshot() -> [Measurement] {
            storage.withLock { measurements in
                measurements.map {
                    var averaged = $0
                    if $0.blocks > 0 { averaged.rms = $0.rms / Float($0.blocks) }
                    return averaged
                }
            }
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
