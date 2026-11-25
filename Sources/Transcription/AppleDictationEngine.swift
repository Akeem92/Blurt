import Foundation
import Speech
import AVFoundation
import OSLog

/// Transcription through Apple's on-device speech models.
///
/// Uses `DictationTranscriber` rather than the general-purpose
/// `SpeechTranscriber`. The two share an analyzer but not a purpose: the
/// dictation model is tuned for someone addressing their computer in short
/// bursts, and it alone offers automatic punctuation, spoken punctuation,
/// emoji by name, and a custom vocabulary. For an app whose entire job is short
/// bursts of dictation, that is not a detail.
///
/// Everything happens on this machine. No account, no network once the model is
/// downloaded, nothing leaves the Mac.
struct AppleDictationEngine: TranscriptionEngine {
    var displayName: String { "Apple (on-device)" }

    /// Automatic and spoken punctuation. Worth having on almost always — without
    /// it the transcript is one long unpunctuated run.
    var wantsPunctuation = true

    /// Turns "smiley face" into an emoji. Off by default: delightful when meant,
    /// startling when not.
    var wantsEmoji = false

    private let log = Logger(subsystem: "com.blurt.app", category: "transcription")

    // MARK: - Availability

    func supportedLocales() async -> [Locale] {
        await DictationTranscriber.supportedLocales
    }

    func resolve(_ locale: Locale) async -> Locale? {
        await DictationTranscriber.supportedLocale(equivalentTo: locale)
    }

    func readiness(for locale: Locale) async -> ModelReadiness {
        guard let resolved = await resolve(locale) else { return .unsupported }

        let status = await AssetInventory.status(forModules: [transcriber(for: resolved)])
        switch status {
        case .unsupported: return .unsupported
        case .downloading: return .downloading(nil)
        case .supported: return .needsDownload
        case .installed: return .ready
        @unknown default: return .unsupported
        }
    }

    func prepare(_ locale: Locale, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard let resolved = await resolve(locale) else {
            throw DictationError.languageUnsupported(locale.identifier)
        }

        // Reserving tells the system this app intends to keep using the language,
        // so its assets are not reclaimed. There is a cap on how many a single
        // app may hold, hence doing it per language rather than for all of them.
        try await AssetInventory.reserve(locale: resolved)

        guard let request = try await AssetInventory
            .assetInstallationRequest(supporting: [transcriber(for: resolved)])
        else {
            onProgress(1)
            return  // Already installed.
        }

        // `Progress` is KVO-based, so its updates are bridged into the callback.
        let observation = request.progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
            onProgress(progress.fractionCompleted)
        }
        defer { observation.invalidate() }

        try await request.downloadAndInstall()
        onProgress(1)
    }

    // MARK: - Sessions

    func beginSession(locale: Locale) async throws -> any TranscriptionSession {
        guard let resolved = await resolve(locale) else {
            throw DictationError.languageUnsupported(locale.identifier)
        }
        guard await readiness(for: resolved) == .ready else {
            throw DictationError.modelNotInstalled(resolved.identifier)
        }
        return try await AppleDictationSession(transcriber: transcriber(for: resolved))
    }

    private func transcriber(for locale: Locale) -> DictationTranscriber {
        var transcriptionOptions: Set<DictationTranscriber.TranscriptionOption> = []
        if wantsPunctuation { transcriptionOptions.insert(.punctuation) }
        if wantsEmoji { transcriptionOptions.insert(.emoji) }

        return DictationTranscriber(
            locale: locale,
            // Short form tells the model to expect someone talking to their
            // computer, not a lecture.
            contentHints: [.shortForm],
            transcriptionOptions: transcriptionOptions,
            // Volatile results are the live guess that firms up as more is heard —
            // what makes text appear while you are still speaking.
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }
}

/// One dictation, from first buffer to final text.
actor AppleDictationSession: TranscriptionSession {
    nonisolated let updates: AsyncStream<TranscriptionUpdate>

    private let analyzer: SpeechAnalyzer
    private let transcriber: DictationTranscriber
    private let converter: BufferConverter
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let publish: AsyncStream<TranscriptionUpdate>.Continuation

    private var resultsTask: Task<Void, Never>?
    private var hasFinished = false

    /// The transcript as it last stood. Held here rather than only returned at
    /// the end, so a session that has to be abandoned still gives up its text.
    private var latestText = ""

    /// Set when the results stream closes of its own accord.
    private var resultsFinished = false

    /// How long to wait for the engine to settle after the last audio.
    ///
    /// Not paranoia: feeding it nothing but silence, it can simply never close
    /// its results stream. Without a bound, the app sits on "Transcribing…" for
    /// good and the shortcut stops responding.
    private static let settleTimeout = Duration.seconds(3)

    init(transcriber: DictationTranscriber) async throws {
        self.transcriber = transcriber

        // The microphone delivers 48 kHz mono; the analyzer wants its own format
        // and will not say so. Feeding it unconverted buffers compiles cleanly,
        // runs happily, and transcribes absolutely nothing — no error, no
        // warning, just silence where the words should be. macOS 27 ships an
        // `AnalyzerInputConverter` that handles this, but relying on it would
        // raise Blurt's floor from macOS 26 to 27, so the conversion is done by
        // hand and the same code runs for everyone.
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw DictationError.transcriptionFailed(reason: "No compatible audio format")
        }
        converter = BufferConverter(outputFormat: analyzerFormat)

        let (inputSequence, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.input = input

        let (updates, publish) = AsyncStream<TranscriptionUpdate>.makeStream()
        self.updates = updates
        self.publish = publish

        analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.start(inputSequence: inputSequence)

        startConsumingResults()
    }

    /// Accumulates results into a single growing transcript.
    ///
    /// Results arrive in two kinds. Final ones are settled text and are appended.
    /// Volatile ones are the model's current guess at the tail and are *replaced*
    /// each time — appending them would repeat every word as it firmed up.
    ///
    /// What gets returned is the whole transcript as it last stood, settled part
    /// and pending part together — not the settled part alone. For a short
    /// dictation the model often never finalises anything: it recognises the
    /// sentence perfectly and leaves every result marked volatile, because
    /// nothing has come along to make it change its mind. Trusting only final
    /// results therefore threw away a perfect transcript and returned an empty
    /// string, which is indistinguishable from having heard nothing.
    private func startConsumingResults() {
        resultsTask = Task { [weak self, transcriber, publish] in
            var settled = AttributedString()
            var pending = AttributedString()

            do {
                for try await result in transcriber.results {
                    if result.isFinal {
                        settled += result.text
                        pending = AttributedString()
                    } else {
                        pending = result.text
                    }

                    let text = String((settled + pending).characters)
                    await self?.remember(text)
                    publish.yield(TranscriptionUpdate(
                        text: text,
                        isSettled: pending.characters.isEmpty
                    ))
                }
            } catch {
                Logger(subsystem: "com.blurt.app", category: "transcription")
                    .error("Results stream failed: \(error.localizedDescription)")
            }

            publish.finish()
            await self?.markResultsFinished()
        }
    }

    private func remember(_ text: String) {
        latestText = text
    }

    private func markResultsFinished() {
        resultsFinished = true
    }

    // MARK: - TranscriptionSession

    func feed(_ buffer: CapturedBuffer) {
        guard !hasFinished else { return }
        do {
            input.yield(AnalyzerInput(buffer: try converter.convert(buffer.buffer)))
        } catch {
            Logger(subsystem: "com.blurt.app", category: "transcription")
                .error("Could not convert a buffer: \(error.localizedDescription)")
        }
    }

    func finish() async throws -> String {
        guard !hasFinished else { return latestText }
        hasFinished = true

        input.finish()

        // Fire and forget, deliberately. `finalizeAndFinishThroughEndOfInput()`
        // normally turns the last volatile guess into a final result and closes
        // the results stream — but given nothing worth finalising, most often
        // silence, it can simply never return. Awaiting it wedges the dictation:
        // the app sits on "Transcribing…", the pill stays up, and the shortcut
        // stops responding with nothing in the logs to show why.
        //
        // Racing it against a sleeping timeout in a task group does *not* fix
        // this, which is the subtler trap. A task group does not exit until
        // every child has finished, and cancelling a call that ignores
        // cancellation changes nothing — so the "timeout" merely adds a second
        // thing to wait for. The only way out is not to await it at all.
        let analyzer = self.analyzer
        Task.detached { try? await analyzer.finalizeAndFinishThroughEndOfInput() }

        // Give the results stream a brief window to deliver anything pending.
        // Nothing here depends on it: `latestText` already holds the transcript
        // as it last stood, so a session that never settles still gives up its
        // words.
        let deadline = ContinuousClock.now.advanced(by: Self.settleTimeout)
        while !resultsFinished, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(40))
        }

        if !resultsFinished {
            Logger(subsystem: "com.blurt.app", category: "transcription")
                .notice("Engine never settled; using the transcript as it stood")
            resultsTask?.cancel()
            publish.finish()
            Task.detached { await analyzer.cancelAndFinishNow() }
        }

        return latestText
    }

    func cancel() async {
        guard !hasFinished else { return }
        hasFinished = true
        input.finish()
        resultsTask?.cancel()
        publish.finish()

        // Detached for the same reason as in `finish()`: tearing the engine down
        // can block, and cancelling must never be the thing that hangs.
        let analyzer = self.analyzer
        Task.detached { await analyzer.cancelAndFinishNow() }
    }
}
