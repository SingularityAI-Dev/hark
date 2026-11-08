/// Levenshtein distance between two sequences: insertions, deletions and substitutions
/// each cost one.
public func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        current[0] = i
        for j in 1...b.count {
            let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
            current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
        }
        swap(&previous, &current)
    }
    return previous[b.count]
}

public func editDistance(_ a: String, _ b: String) -> Int {
    editDistance(Array(a), Array(b))
}

/// The index pairs of a longest common subsequence of `a` and `b`, in order.
public func longestCommonSubsequence<T: Equatable>(_ a: [T], _ b: [T]) -> [(Int, Int)] {
    guard !a.isEmpty, !b.isEmpty else { return [] }
    var lengths = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
        for j in stride(from: b.count - 1, through: 0, by: -1) {
            lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
        }
    }
    var pairs: [(Int, Int)] = []
    var i = 0
    var j = 0
    while i < a.count, j < b.count {
        if a[i] == b[j] {
            pairs.append((i, j))
            i += 1
            j += 1
        } else if lengths[i + 1][j] >= lengths[i][j + 1] {
            i += 1
        } else {
            j += 1
        }
    }
    return pairs
}
