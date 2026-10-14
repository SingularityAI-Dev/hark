import Foundation

/// Rule-based transcript cleanup. Used on its own for short utterances and as the fallback
/// whenever the language model is unavailable or returns something implausible.
public enum TextCleaner {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let fillers = regex(#"(?<![\w'])(?:u+h+m*|u+m+|e+r+m*|h+m+|m+h+m+|a+h+)(?![\w'])[,.]?\s*"#)
    /// The same two to four words said twice in a row, as in "I'm going to I'm going to".
    private static let repeatedPhrases = regex(#"\b((?:[\w']+\s+){1,3}[\w']+)\s+\1\b"#)
    /// "you know" set off by commas is always filler.
    private static let youKnowAside = regex(#",\s*you know\s*,"#)
    private static let youKnow = regex(#"\byou know\b[,]?\s*"#)
    /// Words before or after "you know" that make it part of the sentence: "do you know
    /// where", "you know the answer", "if you know what I mean".
    private static let youKnowKeptAfter: Set<String> = ["do", "did", "don't", "didn't", "if", "as", "what", "how", "would", "will", "and", "that", "whether", "because"]
    private static let youKnowKeptBefore: Set<String> = [
        "what", "how", "that", "if", "where", "when", "why", "who", "whether", "the", "a", "an",
        "him", "her", "them", "it", "about", "this", "those", "these", "me", "us", "everything", "nothing",
    ]
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
        for _ in 0..<3 { text = replace(repeatedPhrases, in: text, with: "$1") }
        text = replace(youKnowAside, in: text, with: " ")
        text = removeFillerYouKnow(text)
        text = replace(whitespaceRuns, in: text, with: " ")
        text = replace(spaceBeforePunctuation, in: text, with: "$1")
        text = replace(repeatedCommas, in: text, with: ",")
        text = replace(leadingJunk, in: text, with: "")
        text = capitaliseSentenceStarts(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeFillerYouKnow(_ text: String) -> String {
        var result = text
        for match in youKnow.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let before = result[..<range.lowerBound].split(whereSeparator: { $0.isWhitespace }).last.map { $0.lowercased() }
            let after = result[range.upperBound...].split(whereSeparator: { $0.isWhitespace }).first.map {
                $0.lowercased().trimmingCharacters(in: .punctuationCharacters)
            }
            if let before, youKnowKeptAfter.contains(before) { continue }
            if let after, youKnowKeptBefore.contains(after) { continue }
            if before == nil { continue }  // "You know the..." opening a sentence is usually meant.
            result.replaceSubrange(range, with: "")
        }
        return result
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

    private static let correctionCues: Set<String> = ["wait", "sorry", "no", "actually", "mean", "scratch", "rather", "correction"]

    private static func takesSomethingBack(_ text: String) -> Bool {
        vocabulary(text).contains { correctionCues.contains($0) }
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
        // Taking things back ("wait, sorry, it's the other one") can legitimately shrink a
        // dictation to a fraction of its length; without that, a big shrink is a summary.
        let shrinkLimit = takesSomethingBack(original) ? 0.15 : 0.35
        guard Double(after) >= Double(before) * shrinkLimit, after <= before + max(3, before / 4) else { return false }

        let spoken = Set(vocabulary(original))
        let written = vocabulary(refined)
        guard !written.isEmpty else { return false }
        let kept = written.filter { spoken.contains($0) }.count
        return Double(kept) / Double(written.count) >= 0.75
    }
}
