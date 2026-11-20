import Foundation

/// Compares the text hark pasted with what the target field holds later, to tell whether
/// the speaker edited a word or two. Phase 1 only classifies; learning comes later.
public enum EditDiff {
    public enum NearCopy: Equatable {
        /// The pasted words are all there, unchanged.
        case unchanged
        /// The pasted text is still there with one or two words substituted, inserted or deleted.
        case changed(count: Int)
        /// The text is gone, rewritten, or changed in three or more places.
        case different
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map {
            $0.trimmingCharacters(in: .punctuationCharacters).lowercased()
        }.filter { !$0.isEmpty }
    }

    /// `readBack` is a window around the paste that also holds neighbouring text (often the
    /// previous dictation) and may cut a word in half at either end. The pasted words are
    /// aligned against the best-matching stretch of the window, which may start and end
    /// anywhere at no cost, so neighbouring words never register as an edit. Each word
    /// substituted, inserted or deleted inside that stretch is one change.
    public static func nearCopy(pasted: String, readBack: String) -> NearCopy {
        let pastedWords = words(pasted)
        let window = words(readBack)
        guard !pastedWords.isEmpty else { return .different }
        let changes = bestStretchDistance(pastedWords, in: window)
        // Under 70% of the pasted words kept, or three or more changes, is not an edit of
        // this paste.
        guard changes < 3, Double(pastedWords.count - changes) >= Double(pastedWords.count) * 0.7 else {
            return .different
        }
        return changes == 0 ? .unchanged : .changed(count: changes)
    }

    /// How many words of `readBack` follow the best-matching stretch (the later stretch wins
    /// a tie), or nil when either text has no words. Zero or a few means the paste is the last
    /// thing on screen; many means something was typed or drawn after it.
    public static func wordsAfterBestStretch(pasted: String, readBack: String) -> Int? {
        let pattern = words(pasted), text = words(readBack)
        guard !pattern.isEmpty, !text.isEmpty else { return nil }
        let row = alignmentTable(pattern, in: text)[pattern.count]
        guard let best = row.min(), let end = row.lastIndex(of: best) else { return nil }
        return text.count - end
    }

    /// Full alignment table of `pattern` against `text`, free start and end in `text`:
    /// `table[i][j]` is the fewest changes to match the first `i` pattern words against a
    /// stretch of `text` that ends after word `j`. Row 0 is all zeros (the stretch may start
    /// anywhere); column 0 holds `i` (every pattern word missing).
    internal static func alignmentTable(_ pattern: [String], in text: [String]) -> [[Int]] {
        var table = [[Int]](repeating: [Int](repeating: 0, count: text.count + 1), count: pattern.count + 1)
        for i in 0..<pattern.count + 1 { table[i][0] = i }
        guard !pattern.isEmpty, !text.isEmpty else { return table }
        for i in 1...pattern.count {
            for j in 1...text.count {
                let substitution = table[i - 1][j - 1] + (pattern[i - 1] == text[j - 1] ? 0 : 1)
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, substitution)
            }
        }
        return table
    }

    /// Edit distance between `pattern` and the closest stretch of `text` (free start and end
    /// in `text`): the minimum of the table's last row.
    static func bestStretchDistance(_ pattern: [String], in text: [String]) -> Int {
        guard !text.isEmpty else { return pattern.count }
        return alignmentTable(pattern, in: text)[pattern.count].min() ?? pattern.count
    }
}
