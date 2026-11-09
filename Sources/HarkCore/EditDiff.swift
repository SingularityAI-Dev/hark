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

    /// Edit distance between `pattern` and the closest stretch of `text` (free start and end
    /// in `text`).
    static func bestStretchDistance(_ pattern: [String], in text: [String]) -> Int {
        guard !text.isEmpty else { return pattern.count }
        var previous = [Int](repeating: 0, count: text.count + 1)
        var current = previous
        for i in 1...pattern.count {
            current[0] = i
            for j in 1...text.count {
                let substitution = previous[j - 1] + (pattern[i - 1] == text[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous.min() ?? pattern.count
    }
}
