import Foundation

/// Names the words a speaker changed in a pasted dictation, by aligning the pasted words
/// against the text read back from the field later. Phase A runs it as a dry run; nothing
/// is learned from it yet.
public enum EditPairs {
    public struct Pair: Equatable {
        /// The pasted word, original case, punctuation trimmed.
        public let heard: String
        /// The word now in the field, original case, punctuation trimmed.
        public let meant: String
        /// The two differ only by capital letters.
        public let caseOnly: Bool
        /// Position of `heard` among the pasted words.
        public let wordIndex: Int
        /// `heard` is the first word of the paste or follows `.`, `!`, `?` or a line break.
        public let atSentenceStart: Bool

        public init(heard: String, meant: String, caseOnly: Bool, wordIndex: Int, atSentenceStart: Bool) {
            self.heard = heard
            self.meant = meant
            self.caseOnly = caseOnly
            self.wordIndex = wordIndex
            self.atSentenceStart = atSentenceStart
        }
    }

    public enum Alignment: Equatable {
        /// The paste is there, word for word.
        case unchanged
        /// Same-position word substitutions, with the screen row of the first one.
        case pairs([Pair], line: String)
        /// Gone, rewritten, an insertion or deletion, or too many changes to learn from.
        case different
    }

    /// Learning limits: at most this many substituted words, at least half the words kept,
    /// two or more pasted words. Phase 1's 70% rule for the counts is separate.
    static let maximumPairs = 2
    static let minimumKept = 0.5
    /// In a paste this short, a substitution needs an exact word on each side.
    static let shortPaste = 4
    /// A substitution at the edge of a short paste has only one exact neighbour, so the
    /// two words must also be close (same limit as `LearnFilter`'s distance rule).
    static let edgeDistance = 0.4

    struct Token {
        let original: String
        let lower: String
        let row: Int
        let sentenceStart: Bool
    }

    /// Words of `pasted` against the best stretch of `readBack`. Fewest changes wins; on a
    /// tie the shorter stretch, then the later one (a near match at the bottom of a screen
    /// must not beat an exact older copy).
    public static func align(pasted: String, readBack: String) -> Alignment {
        let pattern = tokens(rows: pasted.components(separatedBy: .newlines), joinRows: false)
        guard !pattern.isEmpty else { return .different }
        let rows = readBack.components(separatedBy: .newlines).map(stripBorders)
        var best: Candidate?
        // Spaced rows first; rows glued together second, so a word split at a terminal
        // row edge can still match. The first variant wins a full tie.
        for joinRows in [false, true] {
            guard let candidate = bestCandidate(pattern: pattern, text: tokens(rows: rows, joinRows: joinRows)),
                best == nil || candidate.isBetter(than: best!)
            else { continue }
            best = candidate
        }
        guard let best else { return .different }
        return result(for: best, pattern: pattern, rows: rows)
    }

    /// The last `limit` UTF-16 units of a screen read after each run of spaces or tabs is
    /// squeezed to one space, so a wide, space-padded terminal does not use up the limit.
    public static func screenTail(_ text: String, limit: Int) -> String {
        var squeezed = ""
        squeezed.reserveCapacity(text.utf8.count)
        var lastWasBlank = false
        for character in text {
            let blank = character == " " || character == "\t"
            if blank && lastWasBlank { continue }
            squeezed.append(character)
            lastWasBlank = blank
        }
        guard squeezed.utf16.count > limit else { return squeezed }
        return String(squeezed.suffix(limit))
    }

    // MARK: Tokens

    private static let trimmed = CharacterSet.punctuationCharacters.union(.symbols)

    private static func isBorder(_ character: Character) -> Bool {
        if character.isWhitespace || character == ">" { return true }
        // Box drawing and block elements: the frame Claude Code draws around its input.
        return character.unicodeScalars.first.map { (0x2500...0x259F).contains($0.value) } ?? false
    }

    static func stripBorders(_ row: String) -> String {
        var characters = Substring(row)
        while let first = characters.first, isBorder(first) { characters.removeFirst() }
        while let last = characters.last, isBorder(last) { characters.removeLast() }
        return String(characters)
    }

    /// Words with original case, punctuation trimmed at both ends. With `joinRows` a word
    /// running off the end of one row continues on the next.
    static func tokens(rows: [String], joinRows: Bool) -> [Token] {
        var result: [Token] = []
        var pending = ""
        var pendingRow = 0
        var previousRaw = ""
        var atRowStart = true

        func flush() {
            defer { pending = "" }
            let word = pending.trimmingCharacters(in: trimmed)
            guard !word.isEmpty else { return }
            let sentenceStart = result.isEmpty || atRowStart || ".!?".contains(previousRaw.last ?? " ")
            result.append(Token(original: word, lower: word.lowercased(), row: pendingRow, sentenceStart: sentenceStart))
            previousRaw = pending
            atRowStart = false
        }

        for (index, row) in rows.enumerated() {
            atRowStart = true
            for character in row {
                if character.isWhitespace {
                    flush()
                } else {
                    if pending.isEmpty { pendingRow = index }
                    pending.append(character)
                }
            }
            if !joinRows { flush() }
        }
        flush()
        return result
    }

    // MARK: Alignment

    enum Step: Equatable {
        case match(Int)       // text index; the originals may still differ in case
        case substituted(Int)
        case missing
    }

    struct Candidate {
        let cost: Int
        let length: Int
        let end: Int
        let steps: [Step]       // one per pattern word
        let hasInsertion: Bool
        let text: [Token]

        var hasIndel: Bool { hasInsertion || steps.contains(.missing) }

        /// Fewest changes; then substitutions only (a missing word and a substituted one can
        /// tie at the end of a paste, and the substitution is the likelier edit); then the
        /// shorter stretch.
        func isBetter(than other: Candidate) -> Bool {
            if cost != other.cost { return cost < other.cost }
            if hasIndel != other.hasIndel { return !hasIndel }
            return length < other.length
        }
    }

    private static func bestCandidate(pattern: [Token], text: [Token]) -> Candidate? {
        guard !text.isEmpty else { return nil }
        let p = pattern.map(\.lower), t = text.map(\.lower)
        let table = EditDiff.alignmentTable(p, in: t)
        let n = p.count
        guard let cost = table[n].min() else { return nil }
        var best: Candidate?
        for end in 0...t.count where table[n][end] == cost {
            let walked = walkBack(table: table, pattern: p, text: t, end: end)
            let candidate = Candidate(
                cost: cost, length: end - walked.start, end: end, steps: walked.steps,
                hasInsertion: walked.hasInsertion, text: text)
            // Ends ascend, so on a full tie the later one is kept.
            if best == nil || !best!.isBetter(than: candidate) { best = candidate }
        }
        return best
    }

    private static func walkBack(table: [[Int]], pattern: [String], text: [String], end: Int)
        -> (steps: [Step], start: Int, hasInsertion: Bool)
    {
        var i = pattern.count, j = end
        var steps = [Step](repeating: .missing, count: pattern.count)
        var hasInsertion = false
        while i > 0 {
            if j > 0, table[i][j] == table[i - 1][j - 1] + (pattern[i - 1] == text[j - 1] ? 0 : 1) {
                steps[i - 1] = pattern[i - 1] == text[j - 1] ? .match(j - 1) : .substituted(j - 1)
                i -= 1
                j -= 1
            } else if table[i][j] == table[i - 1][j] + 1 {
                steps[i - 1] = .missing
                i -= 1
            } else {
                hasInsertion = true
                j -= 1
            }
        }
        return (steps, j, hasInsertion)
    }

    private static func result(for candidate: Candidate, pattern: [Token], rows: [String]) -> Alignment {
        let n = pattern.count
        guard !candidate.hasInsertion, !candidate.steps.contains(.missing) else { return .different }
        var pairs: [Pair] = []
        var firstRow: Int?
        for (index, step) in candidate.steps.enumerated() {
            let word: Token
            switch step {
            case .match(let j):
                word = candidate.text[j]
                guard word.original != pattern[index].original else { continue }
            case .substituted(let j):
                word = candidate.text[j]
            case .missing:
                continue
            }
            if firstRow == nil { firstRow = word.row }
            pairs.append(Pair(
                heard: pattern[index].original, meant: word.original,
                caseOnly: word.lower == pattern[index].lower, wordIndex: index,
                atSentenceStart: pattern[index].sentenceStart))
        }
        if pairs.isEmpty { return .unchanged }
        guard n >= 2, pairs.count <= maximumPairs, Double(n - pairs.count) >= Double(n) * minimumKept else { return .different }
        if n <= shortPaste, !hasExactNeighbours(candidate: candidate, pairs: pairs, count: n) { return .different }
        let line = firstRow.map { rows.indices.contains($0) ? rows[$0] : "" } ?? ""
        return .pairs(pairs, line: line)
    }

    /// For a paste of `shortPaste` words or fewer: every substituted word has an exact word
    /// on each side that exists, and a substitution at the edge also has to be a close one.
    private static func hasExactNeighbours(candidate: Candidate, pairs: [Pair], count: Int) -> Bool {
        func isExact(_ index: Int) -> Bool {
            if case .match = candidate.steps[index] { return true }
            return false
        }
        for pair in pairs where !pair.caseOnly {
            let index = pair.wordIndex
            if index > 0, !isExact(index - 1) { return false }
            if index < count - 1, !isExact(index + 1) { return false }
            if index == 0 || index == count - 1 {
                let a = pair.heard.lowercased(), b = pair.meant.lowercased()
                if Double(editDistance(a, b)) / Double(max(a.count, b.count)) > edgeDistance { return false }
            }
        }
        return true
    }
}
