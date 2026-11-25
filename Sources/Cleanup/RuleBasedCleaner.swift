import Foundation

/// The tidying that can be written down as rules.
///
/// Instant, free, offline, and always runs — including when the Claude pass is
/// off, unavailable, or too slow. Everything here is deliberately safe enough
/// to apply without anyone reviewing it.
struct RuleBasedCleaner: TextCleaner {
    var name: String { "Rules" }

    var removesFillers = true
    var appliesFrenchTypography = true
    var fixesCapitalisation = true

    /// Sounds, not words. Kept conservative on purpose: "ben" and "bah" are
    /// fillers in French but also a name and a word, and silently deleting
    /// either is worse than leaving a "euh" in.
    static let fillers = [
        "euh", "euhh", "heu", "hum", "humm", "hmm", "mmh",
        "um", "uhm", "uh", "erm", "ahem",
    ]

    func clean(_ text: String, locale: Locale) async throws -> String {
        var result = text

        if removesFillers {
            result = Self.removingFillers(from: result)
        }
        // Before typography, not after: this squeezes stray spaces out, and the
        // French rules then put very specific ones back in.
        result = Self.normalisingWhitespace(in: result)

        if appliesFrenchTypography, locale.language.languageCode?.identifier == "fr" {
            result = Self.applyingFrenchTypography(to: result)
        }
        if fixesCapitalisation {
            result = Self.capitalisingFirstLetter(of: result)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rules

    /// Drops filler sounds, along with a comma the transcriber hung on them.
    ///
    /// Word boundaries matter here: a naive search would hollow out "heureux"
    /// looking for "heu".
    private static func removingFillers(from text: String) -> String {
        var result = text
        for filler in fillers {
            // Optional leading separator, the word itself, then any comma and
            // space that trailed it.
            let pattern = "(?i)(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: filler))(?![\\p{L}\\p{N}])\\s*,?\\s*"
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            result = expression.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        return result
    }

    private static func normalisingWhitespace(in text: String) -> String {
        var result = text

        // Runs of whitespace become one space.
        result = result.replacingOccurrences(
            of: "[ \\t]+", with: " ", options: .regularExpression
        )
        // Every space before punctuation goes, including the ones French wants.
        // Stripping first and letting the typography rule put back exactly what
        // the language asks for is what makes this idempotent: a rule that only
        // ever inserts drifts a little further on each pass.
        result = result.replacingOccurrences(
            of: "[ \\u00A0\\u202F]+([,.…;:!?\\)\\]])", with: "$1", options: .regularExpression
        )
        // One space after it, when a word follows directly.
        result = result.replacingOccurrences(
            of: "([,.;:!?])(?=\\p{L})", with: "$1 ", options: .regularExpression
        )
        return result
    }

    /// French puts a space before `; ! ? :` and inside `« »`, and English does
    /// not — so a model trained mostly on English never adds them, and their
    /// absence is the first thing a French reader notices.
    ///
    /// The spaces are non-breaking, so the punctuation cannot be orphaned at the
    /// start of a line: a narrow one before `; ! ?` and a full one before `:`,
    /// which is the convention the Imprimerie nationale sets.
    private static func applyingFrenchTypography(to text: String) -> String {
        let narrowNoBreak = "\u{202F}"
        let noBreak = "\u{00A0}"
        var result = text

        // Note the escape form: ICU wants ` `, four hex digits and no
        // braces. Swift's own `\u{00A0}` spelling reaches the regex engine as
        // literal characters, the pattern fails to compile, and
        // `replacingOccurrences` then silently returns the string untouched —
        // a rule that looks present and does nothing.
        result = result.replacingOccurrences(
            of: "[ \\u00A0\\u202F]*([;!?])", with: "\(narrowNoBreak)$1", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "[ \\u00A0\\u202F]*:", with: "\(noBreak):", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "«[ \\u00A0\\u202F]*", with: "«\(noBreak)", options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "[ \\u00A0\\u202F]*»", with: "\(noBreak)»", options: .regularExpression
        )
        return result
    }

    private static func capitalisingFirstLetter(of text: String) -> String {
        guard let first = text.firstIndex(where: { !$0.isWhitespace }) else { return text }
        guard text[first].isLowercase else { return text }
        return text.replacingCharacters(
            in: first...first,
            with: String(text[first]).uppercased()
        )
    }
}
