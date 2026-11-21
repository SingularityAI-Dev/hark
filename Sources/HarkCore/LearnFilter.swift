import Foundation

/// Why a changed word was not learned. One reason per rule, tested in this order.
public enum LearnReason: String, CaseIterable, Codable {
    case code, tooShort, notLetters, notInRaw, tooFar, caseOnly, rewording, tombstoned, chain
}

/// Decides whether a (heard, meant) pair is a recogniser mistake worth learning.
/// Phase A runs it as a dry run that only feeds counts.
public enum LearnFilter {
    public enum Verdict: Equatable {
        case learnNow
        case waitForSecond
        case reject(LearnReason)
    }

    static let shellWords: Set<String> = [
        "git", "cd", "ls", "npm", "swift", "make", "sudo", "brew", "python", "uv", "cat", "rm",
        "mv", "cp", "curl", "ssh", "docker",
    ]
    static let maximumDistance = 0.4

    /// `raw` is the recogniser's transcript, `line` the screen row the pair was found on and
    /// `isWord` asks the spell checker. `learned` is the stored list for the tombstone and
    /// chain rules; Phase A passes `[]`.
    public static func judge(
        pair: EditPairs.Pair, raw: String, line: String,
        isWord: (String) -> Bool, learned: [LearnedEntry]
    ) -> Verdict {
        let heard = pair.heard, meant = pair.meant
        let heardLower = heard.lowercased(), meantLower = meant.lowercased()
        func known(_ word: String) -> Bool { isWord(word) || isWord(word.lowercased()) }

        // 0. Code.
        if isCodeLine(line) || isCodeWord(heard) || isCodeWord(meant) { return .reject(.code) }
        // 1. Both words are real-looking words.
        if heard.count < 3 || meant.count < 3 { return .reject(.tooShort) }
        if !isLetters(heard) || !isLetters(meant) { return .reject(.notLetters) }
        // 2. The recogniser said it.
        guard words(in: raw).contains(heardLower) else { return .reject(.notInRaw) }
        // 3. Close enough to be a mishearing.
        let distance = Double(editDistance(heardLower, meantLower)) / Double(max(heardLower.count, meantLower.count))
        if distance > maximumDistance { return .reject(.tooFar) }
        // 4. Capitals only.
        if pair.caseOnly || heardLower == meantLower { return .reject(.caseOnly) }
        // 5. Two dictionary words are a rewording, not a mishearing.
        if known(heard), known(meant) { return .reject(.rewording) }
        // 7. Removed by the speaker before.
        if learned.contains(where: {
            $0.state == .removed && $0.heard.lowercased() == heardLower && $0.meant == meant
        }) { return .reject(.tombstoned) }
        // 8. Would feed another entry.
        if learned.contains(where: {
            $0.state == .active && ($0.meant.lowercased() == heardLower || $0.heard.lowercased() == meantLower)
        }) { return .reject(.chain) }
        // 6. First or second sighting.
        let meantIsCapitalisedNonWord = meant.first?.isUppercase == true && !known(meant)
        let heardIsCapitalised = heard.first?.isUppercase == true
        if !known(heard) || (meantIsCapitalisedNonWord && !heardIsCapitalised && !pair.atSentenceStart) {
            return .learnNow
        }
        return .waitForSecond
    }

    // MARK: Rules

    /// A shell command or a line starting with `$`. "Make sure Bryne gets the forms" starts
    /// with a shell word but has no second signal, so it is not code.
    static func isCodeLine(_ line: String) -> Bool {
        var text = Substring(line.trimmingCharacters(in: .whitespaces))
        if text.hasPrefix("$") { return true }
        while let first = text.first, first == ">" || first == "%" || first.isWhitespace { text.removeFirst() }
        let parts = text.split(whereSeparator: { $0.isWhitespace })
        guard let first = parts.first, shellWords.contains(first.lowercased()) else { return false }
        return parts.dropFirst().contains { part in
            guard let lead = part.first else { return false }
            return "-_/$~".contains(lead) || part.contains("/")
        }
    }

    /// A path, a snake_case or dotted name, a flag, a backtick or brineCase.
    static func isCodeWord(_ word: String) -> Bool {
        if word.contains(where: { "/_.`".contains($0) }) || word.hasPrefix("-") { return true }
        guard word.first?.isLowercase == true else { return false }
        return word.dropFirst().contains { $0.isUppercase }
    }

    static func isLetters(_ word: String) -> Bool {
        word.allSatisfy { $0.isLetter || $0 == "'" || $0 == "\u{2019}" }
    }

    /// The raw transcript's words, lowercase, punctuation trimmed.
    static func words(in text: String) -> Set<String> {
        Set(text.split(whereSeparator: { $0.isWhitespace }).map {
            $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)).lowercased()
        }.filter { !$0.isEmpty })
    }
}
