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

    /// `readBack` is a window around the paste that may cut a word in half at either end.
    /// Words are matched in order (longest common subsequence), and only the stretch
    /// between the first and last matched pasted word counts, so neighbouring text and cut
    /// words at the window's edges never register as an edit. (The window starts 40
    /// characters before the paste, so a cut word can only fall inside the paste when the
    /// field itself starts there, and then nothing is cut.)
    public static func nearCopy(pasted: String, readBack: String) -> NearCopy {
        let pastedWords = words(pasted)
        let window = words(readBack)
        guard !pastedWords.isEmpty else { return .different }
        let pairs = longestCommonSubsequence(pastedWords, window)
        guard Double(pairs.count) >= Double(pastedWords.count) * 0.7, let first = pairs.first, let last = pairs.last else {
            return .different
        }
        // Inside the matched stretch, compare the pasted words with the window's words.
        let pastedSpan = Array(pastedWords[first.0...last.0])
        let windowSpan = Array(window[first.1...last.1])
        // Pasted words outside the matched stretch were edited away at the edges.
        let edgeLoss = first.0 + (pastedWords.count - 1 - last.0)
        let changes = editDistance(pastedSpan, windowSpan) + edgeLoss
        switch changes {
        case 0: return .unchanged
        case 1, 2: return .changed(count: changes)
        default: return .different
        }
    }
}
