import Foundation

/// The transcript as it currently stands.
///
/// `text` is always the *whole* transcript, not a fragment, so a consumer can
/// display it directly without stitching anything together.
struct TranscriptionUpdate: Sendable {
    let text: String

    /// False while the tail of `text` is still a guess the model may revise.
    let isSettled: Bool

    /// Other readings the recogniser considered for this stretch of audio.
    ///
    /// Empty unless asked for. Where it earns its place is the homophone: the
    /// recogniser hears something ambiguous and picks the more common phrasing,
    /// and the alternative it set aside is the one that actually makes sense.
    /// Knowing what else was heard is what lets that be settled by meaning
    /// rather than guessed at.
    var alternatives: [String] = []
}

/// Whether a language can be transcribed on this machine right now.
enum ModelReadiness: Sendable, Equatable {
    /// The engine cannot transcribe this language at all.
    case unsupported
    /// Supported, but the model has to be fetched first.
    case needsDownload
    /// Being fetched. 0...1, or nil when the engine cannot say.
    case downloading(Double?)
    /// Ready to use, offline included.
    case ready
}

/// One transcription in progress.
///
/// Streaming rather than "hand me audio, give me text": the audio arrives a
/// buffer at a time while the user is still speaking, and the transcript is
/// almost complete by the moment they stop. An engine that can only work in one
/// batch still fits — it accumulates in `feed` and does the work in `finish`.
protocol TranscriptionSession: Sendable {
    /// The transcript as it evolves. Finishes when `finish()` or `cancel()` is called.
    nonisolated var updates: AsyncStream<TranscriptionUpdate> { get }

    /// Hands over one slice of audio. Must not block the caller.
    func feed(_ buffer: CapturedBuffer) async

    /// Stops accepting audio, waits for the engine to settle, returns the final text.
    func finish() async throws -> String

    /// Abandons the session. No text, no error.
    func cancel() async
}

/// A way of turning speech into text.
///
/// The seam that lets Apple's engine be swapped for Parakeet or Whisper later
/// without the rest of the app noticing. Everything specific to one engine —
/// model downloads, supported languages, audio format — lives behind it.
protocol TranscriptionEngine: Sendable {
    /// Shown in Settings.
    var displayName: String { get }

    /// Languages this engine can handle, whether or not they are downloaded.
    func supportedLocales() async -> [Locale]

    /// Resolves a requested language to one the engine actually offers.
    ///
    /// Exact `Locale` equality is the wrong test: asking for `fr` when the engine
    /// has `fr-FR` should succeed rather than silently fall back to English.
    func resolve(_ locale: Locale) async -> Locale?

    func readiness(for locale: Locale) async -> ModelReadiness

    /// Downloads whatever is missing. Reports 0...1 as it goes.
    func prepare(_ locale: Locale, onProgress: @escaping @Sendable (Double) -> Void) async throws

    func beginSession(locale: Locale) async throws -> any TranscriptionSession
}
