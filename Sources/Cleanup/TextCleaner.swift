import Foundation

/// Turns a raw transcript into something you would have typed.
///
/// A protocol for the same reason transcription has one: there are two very
/// different ways of doing this. Rules are instant, free and offline but can
/// only do what can be written down as a rule. A model understands what you
/// meant but costs a network round trip. They are meant to be chained, not
/// chosen between.
protocol TextCleaner: Sendable {
    var name: String { get }

    /// Returns the tidied text. Throwing is always recoverable: the caller keeps
    /// whatever it had, so a cleaner that fails costs polish, never words.
    func clean(_ text: String, locale: Locale) async throws -> String
}
