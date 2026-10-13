import Foundation

/// Rule-based transcript cleanup. Used on its own for short utterances and as the fallback
/// whenever the language model is unavailable or returns something implausible.
public enum TextCleaner {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let fillers = regex(#"(?<![\w'])(?:u+h+m*|u+m+|e+r+m*|h+m+|m+h+m+)(?![\w'])[,.]?\s*"#)
    private static let stutters = regex(#"\b(i|the|a|an|and|to|of|in|it|is|we|you|but|so|my|for|on)(?:\s+\1\b)+"#)
    private static let spaceBeforePunctuation = regex(#"\s+([,.!?;:])"#)
    private static let repeatedCommas = regex(#",(?:\s*,)+"#)
    private static let whitespaceRuns = regex(#"[ \t]+"#)
    private static let leadingJunk = regex(#"^[\s,.;:]+"#)
    private static let sentenceStart = regex(#"(^|[.!?]\s+)([a-z])"#)

    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    public static func clean(_ raw: String) -> String {
        var text = replace(fillers, in: raw, with: "")
        text = replace(stutters, in: text, with: "$1")
        text = replace(whitespaceRuns, in: text, with: " ")
        text = replace(spaceBeforePunctuation, in: text, with: "$1")
        text = replace(repeatedCommas, in: text, with: ",")
        text = replace(leadingJunk, in: text, with: "")
        text = capitaliseSentenceStarts(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitaliseSentenceStarts(_ text: String) -> String {
        var result = text
        let matches = sentenceStart.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 2), in: result) else { continue }
            result.replaceSubrange(range, with: result[range].uppercased())
        }
        return result
    }

    /// A word or phrase the recogniser keeps getting wrong, and what the speaker says.
    public struct Correction: Equatable {
        public let heard: String
        public let meant: String

        public init(heard: String, meant: String) {
            self.heard = heard
            self.meant = meant
        }
    }

    /// Reads one "heard = meant" pair per line and skips anything else.
    public static func corrections(from text: String) -> [Correction] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return Correction(heard: parts[0], meant: parts[1])
        }
    }

    /// Swaps whole words or phrases, matching without regard to case. A match that starts
    /// with a capital keeps one.
    public static func apply(_ corrections: [Correction], to text: String) -> String {
        var result = text
        for correction in corrections {
            let pattern = #"(?<![\w'])"# + NSRegularExpression.escapedPattern(for: correction.heard) + #"(?![\w'])"#
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in expression.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let capitalised = result[range].first?.isUppercase == true
                result.replaceSubrange(
                    range, with: capitalised ? correction.meant.prefix(1).uppercased() + correction.meant.dropFirst() : correction.meant)
            }
        }
        return result
    }

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private static func vocabulary(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") })
            .map(String.init)
    }

    /// Guards against the language model answering the dictation, summarising it away or
    /// padding it. Cleanup removes words and rarely adds any, so the result must be about
    /// the same length or shorter and built almost entirely from the speaker's own words.
    public static func isPlausibleRefinement(original: String, refined: String) -> Bool {
        let before = wordCount(original)
        let after = wordCount(refined)
        guard after > 0 else { return false }
        guard Double(after) >= Double(before) * 0.35, after <= before + max(3, before / 4) else { return false }

        let spoken = Set(vocabulary(original))
        let written = vocabulary(refined)
        guard !written.isEmpty else { return false }
        let kept = written.filter { spoken.contains($0) }.count
        return Double(kept) / Double(written.count) >= 0.75
    }
}
