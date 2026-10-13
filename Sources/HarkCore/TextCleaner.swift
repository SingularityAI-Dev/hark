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
