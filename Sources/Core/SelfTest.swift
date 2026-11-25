#if DEBUG
import AppKit
import AVFoundation
import Accelerate
import Foundation
import KeyboardShortcuts
import Speech
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
        case "--selftest-shortcut": await shortcutTest()
        case "--selftest-transcribe": await transcribeTest()
        case "--selftest-clipboard": await clipboardTest()
        case "--selftest-media": await mediaTest()
        default:
            FileHandle.standardError.write(Data("unknown self-test: \(name)\n".utf8))
            exit(64)
        }
    }

    /// Checks that Blurt can tell whether anything is actually playing.
    ///
    /// Only the detection half. Pressing play/pause is not tested here on
    /// purpose: a test that mashes the media key would stop whatever the person
    /// running it happens to be listening to.
    ///
    /// Detection is the half that matters anyway. Get it wrong in one direction
    /// and a dictation started in silence begins playing music nobody asked for;
    /// get it wrong in the other and the pause never happens.
    @MainActor
    private static func mediaTest() async -> Never {
        var failures: [String] = []

        let quiet = MediaPlayback.isAnythingPlaying()
        print("      with nothing started by this test: \(quiet ? "something is playing" : "silent")")
        if quiet {
            print("      note: something on this Mac is already playing, so the silent case cannot be checked")
        }

        // Something deliberately quiet, since whoever is running this may be
        // wearing headphones.
        let player = Process()
        player.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        player.arguments = ["-v", "0.02", "/System/Library/Sounds/Submarine.aiff"]
        do { try player.run() } catch {
            print("FAIL  could not start a test sound: \(error)")
            exit(2)
        }

        // CoreAudio needs a moment to notice a process has started output.
        var detected = false
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if MediaPlayback.isAnythingPlaying() { detected = true; break }
        }
        print("      while a sound is playing: \(detected ? "detected" : "NOT detected")")
        if !detected { failures.append("playback was not detected while audio was running") }

        player.terminate()
        player.waitUntilExit()

        var wentQuiet = false
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(100))
            if !MediaPlayback.isAnythingPlaying() { wentQuiet = true; break }
        }
        print("      after it stopped: \(wentQuiet ? "silent again" : "still reported as playing")")
        if !wentQuiet, !quiet {
            failures.append("playback was still reported after the sound stopped")
        }

        guard failures.isEmpty else {
            for failure in failures { print("FAIL  \(failure)") }
            exit(1)
        }
        print("PASS  playback detection follows what is actually playing")
        exit(0)
    }

    /// Checks that borrowing the clipboard gives it back.
    ///
    /// The clipboard belongs to the user. Replacing a copied image with a
    /// sentence and never restoring it is the kind of damage an app does once
    /// and is never forgiven for, so the round trip is tested rather than
    /// assumed — including a non-text item, which is where a naive
    /// save-the-string implementation quietly fails.
    @MainActor
    private static func clipboardTest() async -> Never {
        let pasteboard = NSPasteboard.general
        var failures: [String] = []

        // A string and a PNG together, as a real clipboard often is.
        let marker = "blurt-selftest-\(UUID().uuidString)"
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
        image.unlockFocus()

        pasteboard.clearContents()
        pasteboard.setString(marker, forType: .string)
        pasteboard.writeObjects([image])

        let typesBefore = Set(pasteboard.types ?? [])
        print("      before: \(typesBefore.count) types, string = \(pasteboard.string(forType: .string) == nil ? "none" : "present")")

        // Two paths, one requirement. With permission, the clipboard is borrowed
        // and given back. Without it, the clipboard is never touched at all —
        // leaving the dictation on it would destroy whatever the user had
        // copied, which may be the only copy of it anywhere.
        let inserter = ClipboardInserter()
        let dictated = "a sentence that should not survive on the clipboard"
        do {
            try await inserter.insert(dictated)
            print("      insertion succeeded (accessibility granted)")
        } catch {
            print("      insertion refused: \(error) — clipboard must still be restored")
        }

        // Restoration happens after the paste window, so give it a moment.
        try? await Task.sleep(for: .milliseconds(400))

        let typesAfter = Set(pasteboard.types ?? [])
        let stringAfter = pasteboard.string(forType: .string)
        print("      after:  \(typesAfter.count) types, string = \(stringAfter ?? "none")")

        if stringAfter == dictated {
            failures.append("the dictated text was left on the clipboard")
        }
        if stringAfter != marker {
            failures.append("the original string was not restored (got \(stringAfter ?? "nothing"))")
        }
        if !typesBefore.subtracting(typesAfter).isEmpty {
            failures.append("lost representations: \(typesBefore.subtracting(typesAfter).map(\.rawValue).joined(separator: ", "))")
        }

        pasteboard.clearContents()

        guard failures.isEmpty else {
            for failure in failures { print("FAIL  \(failure)") }
            exit(1)
        }
        print("PASS  the clipboard was borrowed and given back intact")
        exit(0)
    }

    /// Transcribes synthesised speech and checks the words come back.
    ///
    /// The reason this exists: handing `SpeechAnalyzer` buffers in the wrong
    /// audio format produces no error, no warning and no text. The failure is
    /// indistinguishable from a microphone that heard nothing, and the
    /// conversion that avoids it is written by hand here. Feeding it a sentence
    /// whose words are known in advance is the only way to tell "the conversion
    /// is right" from "the room was quiet".
    ///
    ///     --selftest-transcribe [--locale fr-FR] [--say "some sentence"]
    @MainActor
    private static func transcribeTest() async -> Never {
        let localeID = value(after: "--locale") ?? "en-US"
        let sentence = value(after: "--say") ?? "the quick brown fox jumps over the lazy dog"
        let locale = Locale(identifier: localeID)

        var engine = AppleDictationEngine()
        engine.wantsPunctuation = false  // Keeps the comparison to words alone.

        guard let resolved = await engine.resolve(locale) else {
            print("FAIL  \(localeID) is not supported. Available: \(await engine.supportedLocales().map(\.identifier).sorted().joined(separator: ", "))")
            exit(1)
        }
        print("      locale: \(localeID) → \(resolved.identifier)")
        print("      readiness: \(await engine.readiness(for: resolved))")

        if await engine.readiness(for: resolved) != .ready {
            print("      downloading the model…")
            do {
                try await engine.prepare(resolved) { fraction in
                    if fraction == 1 { print("      download complete") }
                }
            } catch {
                print("FAIL  model download: \(error)")
                exit(2)
            }
            print("      readiness now: \(await engine.readiness(for: resolved))")
        }

        guard let spoken = synthesise(sentence, locale: resolved) else {
            print("FAIL  could not synthesise speech")
            exit(2)
        }
        print("      spoken: \"\(sentence)\"")

        // Diagnostics, because an empty transcript has several possible causes
        // and they are indistinguishable from the outside.
        let totalFrames = spoken.reduce(0) { $0 + Int($1.buffer.frameLength) }
        let sourceFormat = spoken[0].buffer.format
        var peak: Float = 0
        for chunk in spoken {
            if let data = chunk.buffer.floatChannelData {
                peak = max(peak, vDSP.maximumMagnitude(
                    UnsafeBufferPointer(start: data[0], count: Int(chunk.buffer.frameLength))
                ))
            }
        }
        print("      synthesised: \(spoken.count) chunks, \(totalFrames) frames, peak \(String(format: "%.3f", peak))")
        print("      source format:   \(sourceFormat)")

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [DictationTranscriber(locale: resolved, preset: .progressiveShortDictation)]
        )
        print("      analyzer format: \(analyzerFormat.map(String.init(describing:)) ?? "none")")

        guard peak > 0.001 else {
            print("FAIL  the synthesised audio is silent — `say` produced nothing usable")
            exit(2)
        }

        do {
            // Where the time actually goes, phase by phase. The two that the
            // user feels are the wait before the pill appears and the wait after
            // letting go of the key.
            let beginStart = ContinuousClock.now
            let session = try await engine.beginSession(locale: resolved)
            let beginDuration = ContinuousClock.now - beginStart
            print("      ⏱  beginSession: \(milliseconds(beginDuration)) ms")

            // Watch every update, so an empty final result can be told apart
            // from a model that never said anything at all.
            let watching = Task {
                var count = 0
                for await update in session.updates {
                    count += 1
                    print("      update \(count) [\(update.isSettled ? "final" : "volatile")]: \"\(update.text)\"")
                }
                if count == 0 { print("      (no updates were ever published)") }
            }

            // Fed in small chunks, as the microphone would, rather than in one
            // lump — streaming is the path that actually runs in the app.
            let feedStart = ContinuousClock.now
            for chunk in spoken {
                await session.feed(chunk)
            }
            print("      ⏱  feeding \(spoken.count) chunks: \(milliseconds(ContinuousClock.now - feedStart)) ms")

            let finishStart = ContinuousClock.now
            let heard = try await session.finish()
            let finishDuration = ContinuousClock.now - finishStart
            print("      ⏱  finish (key release → text): \(milliseconds(finishDuration)) ms")
            _ = await watching.result
            print("      heard:  \"\(heard)\"")

            let expected = Set(words(of: sentence))
            let got = Set(words(of: heard))
            let matched = expected.intersection(got)
            let ratio = Double(matched.count) / Double(max(expected.count, 1))
            print(String(format: "      matched %d/%d words (%.0f%%)", matched.count, expected.count, ratio * 100))

            if !expected.subtracting(got).isEmpty {
                print("      missed: \(expected.subtracting(got).sorted().joined(separator: ", "))")
            }

            // Synthesised speech is not a human, so an exact match is the wrong
            // bar. Most words coming back is enough to prove the audio reached
            // the model in a format it could use — which is the whole question.
            guard ratio >= 0.6 else {
                print("FAIL  too few words came back — the audio is probably reaching the model in the wrong format")
                exit(1)
            }
            print("PASS  transcription produced the expected words")
            exit(0)
        } catch {
            print("FAIL  \(error)")
            exit(1)
        }
    }

    /// Milliseconds, rounded, for readable timing output.
    private static func milliseconds(_ duration: Duration) -> Int {
        Int((Double(duration.components.seconds) * 1000)
            + (Double(duration.components.attoseconds) / 1e15))
    }

    private static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func words(of text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    /// Speaks a sentence with `say` and reads it back as capture buffers.
    private static func synthesise(_ sentence: String, locale: Locale) -> [CapturedBuffer]? {
        let url = URL.temporaryDirectory.appending(path: "blurt-selftest-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        var arguments = ["-o", url.path, "--data-format=LEF32@48000", sentence]
        if let voice = voiceName(for: locale) {
            arguments.insert(contentsOf: ["-v", voice], at: 0)
        }
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
        } catch {
            return nil
        }

        guard
            let file = try? AVAudioFile(forReading: url),
            let mono = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 1)
        else { return nil }

        var chunks: [CapturedBuffer] = []
        let framesPerChunk: AVAudioFrameCount = 2048

        while file.framePosition < file.length {
            guard let scratch = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: framesPerChunk
            ) else { break }

            do { try file.read(into: scratch, frameCount: framesPerChunk) } catch { break }
            guard scratch.frameLength > 0 else { break }

            if let captured = CapturedBuffer(copyingChannel0Of: scratch, as: mono) {
                chunks.append(captured)
            }
        }
        return chunks.isEmpty ? nil : chunks
    }

    private static func voiceName(for locale: Locale) -> String? {
        switch locale.language.languageCode?.identifier {
        case "fr": "Thomas"
        default: nil
        }
    }

    /// Exercises both activation modes through the coordinator.
    ///
    /// The interesting case is a hold shorter than the minimum: brushing the
    /// shortcut must not leave a fraction of a second of audio and a
    /// transcription attempt over nothing.
    @MainActor
    private static func shortcutTest() async -> Never {
        guard MicrophoneAccess.status == .granted else {
            print("FAIL  microphone not granted")
            exit(3)
        }

        // An isolated defaults suite, so running the tests never disturbs real
        // settings.
        let suite = "com.blurt.app.selftest"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: UserDefaults(suiteName: suite)!)
        let controller = DictationController(preferences: preferences)
        let coordinator = ShortcutCoordinator(controller: controller, preferences: preferences)

        print("      registered shortcut: \(KeyboardShortcuts.getShortcut(for: .dictate)?.description ?? "none")")

        var failures: [String] = []

        /// Runs one scenario and reports how long the recording actually lasted,
        /// measured from the first press to the file appearing.
        func run(_ label: String, _ body: () async -> Void) async -> Double? {
            let previous = controller.lastRecordingURL
            let started = Date.now
            await body()

            // Waits for the whole trip, transcription included — not just for the
            // audio file to appear. The next scenario starts by pressing the
            // shortcut, and a press that lands while the previous dictation is
            // still being transcribed is correctly ignored.
            var settled = false
            for _ in 0..<160 {
                if controller.lastRecordingURL != previous, !controller.state.isActive {
                    settled = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard controller.lastRecordingURL != previous else {
                failures.append("\(label): no recording was produced (state: \(controller.state))")
                return nil
            }

            let elapsed = Date.now.timeIntervalSince(started)
            print(String(
                format: "      %-20s %.2f s  →  %@%@",
                (label as NSString).utf8String!,
                elapsed,
                "\(controller.state)",
                settled ? "" : "  [TIMED OUT waiting to settle]"
            ))
            if !settled { failures.append("\(label): never settled") }
            return elapsed
        }

        // Held comfortably: should last about as long as the key was down.
        preferences.activationMode = .holdToTalk
        if let elapsed = await run("hold 800 ms", {
            coordinator.simulatePress()
            try? await Task.sleep(for: .milliseconds(800))
            coordinator.simulateRelease()
        }), elapsed < 0.7 {
            failures.append("hold 800 ms ended after only \(elapsed) s")
        }

        // Brushed: the minimum-hold rule should stretch this to a usable length
        // rather than leaving a sliver of audio behind.
        if let elapsed = await run("brush 40 ms", {
            coordinator.simulatePress()
            try? await Task.sleep(for: .milliseconds(40))
            coordinator.simulateRelease()
        }), elapsed < 0.18 {
            failures.append("brush produced only \(elapsed) s — minimum hold was not applied")
        }

        // Toggle: two presses, and the release in between must be ignored.
        preferences.activationMode = .toggle
        if let elapsed = await run("toggle 700 ms", {
            coordinator.simulatePress()
            coordinator.simulateRelease()
            try? await Task.sleep(for: .milliseconds(700))
            coordinator.simulatePress()
        }), elapsed < 0.6 {
            failures.append("toggle ended after only \(elapsed) s — the release was not ignored")
        }

        // The last scenario's transcription may still be finishing.
        for _ in 0..<60 where controller.state.isActive {
            try? await Task.sleep(for: .milliseconds(50))
        }

        // Nobody speaks during an automated run, so "no speech detected" is the
        // correct outcome rather than a failure. What this checks is that the
        // trip ends somewhere settled and not stuck mid-flight.
        switch controller.state {
        case .idle, .failed(.noSpeechDetected):
            break
        default:
            failures.append("ended in \(controller.state) rather than settled")
        }

        UserDefaults.standard.removePersistentDomain(forName: suite)

        guard failures.isEmpty else {
            for failure in failures { print("FAIL  \(failure)") }
            exit(1)
        }
        print("PASS  both activation modes behave")
        exit(0)
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

        let controller = DictationController(preferences: Preferences())
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

        // The question is not whether focus moved — the person running this may
        // well switch apps mid-test — but whether it moved *to Blurt*. That is
        // the failure that would leave a dictation with nowhere to land.
        var failures: [String] = []
        let ownBundleID = Bundle.main.bundleIdentifier ?? "com.blurt.app"
        if during == ownBundleID { failures.append("the pill brought Blurt to the front") }
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

        let controller = DictationController(preferences: Preferences())
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
        print("      state once the file appeared: \(controller.state)")

        // How long the rest of the trip takes, transcription included. Silence is
        // the awkward case: the engine has nothing to report and may not say so.
        let settleStart = Date.now
        for _ in 0..<200 where controller.state.isActive {
            try? await Task.sleep(for: .milliseconds(50))
        }
        print(String(
            format: "      settled after %.2f s in state %@",
            Date.now.timeIntervalSince(settleStart),
            "\(controller.state)"
        ))

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
