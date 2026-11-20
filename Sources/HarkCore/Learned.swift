import Foundation

/// One word hark has seen the speaker fix. Stored in `learned.json`; Phase A only defines
/// and tests it, Phase B wires it in.
public struct LearnedEntry: Codable, Equatable, Identifiable {
    public enum State: String, Codable { case active, pending, removed }

    public var id: UUID
    public var heard: String
    public var meant: String
    public var state: State
    public var sightings: Int
    public var firstSeen: Date
    public var lastSeen: Date
    public var app: String
    public var historyIDs: [UUID]
    /// The heard form was a dictionary word when it was learned (for the report script).
    public var heardIsWord: Bool

    public init(
        id: UUID = UUID(), heard: String, meant: String, state: State, sightings: Int = 1,
        firstSeen: Date = Date(), lastSeen: Date = Date(), app: String = "", historyIDs: [UUID] = [],
        heardIsWord: Bool = false
    ) {
        self.id = id
        self.heard = heard
        self.meant = meant
        self.state = state
        self.sightings = sightings
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.app = app
        self.historyIDs = historyIDs
        self.heardIsWord = heardIsWord
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        heard = try c.decode(String.self, forKey: .heard)
        meant = try c.decode(String.self, forKey: .meant)
        state = try c.decode(State.self, forKey: .state)
        sightings = try c.decodeIfPresent(Int.self, forKey: .sightings) ?? 1
        firstSeen = try c.decode(Date.self, forKey: .firstSeen)
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
        historyIDs = try c.decodeIfPresent([UUID].self, forKey: .historyIDs) ?? []
        heardIsWord = try c.decodeIfPresent(Bool.self, forKey: .heardIsWord) ?? false
    }
}

/// An active entry as `Learned.apply` uses it.
public struct LearnedRule: Codable, Equatable {
    public let id: UUID
    public let heard: String
    public let meant: String

    public init(id: UUID, heard: String, meant: String) {
        self.id = id
        self.heard = heard
        self.meant = meant
    }
}

public enum LearnedFile {
    public static let maximumActive = 200
    public static let pendingLifetime: TimeInterval = 30 * 24 * 3600

    public enum Sighting: Equatable {
        case created(LearnedEntry.State)
        case counted
        case promoted
        /// The same history ID was already counted.
        case duplicate
        /// The pair was removed by the speaker.
        case blocked
    }

    private struct Document: Codable {
        var version: Int
        var entries: [LearnedEntry]
    }

    private static func coders() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    /// A missing or corrupt file is an empty list.
    public static func load(_ url: URL) -> [LearnedEntry] {
        guard let data = try? Data(contentsOf: url),
            let document = try? coders().1.decode(Document.self, from: data)
        else { return [] }
        return document.entries
    }

    public static func save(_ entries: [LearnedEntry], to url: URL) throws {
        let data = try coders().0.encode(Document(version: 1, entries: entries))
        try data.write(to: url, options: .atomic)
    }

    /// Adds one sighting of a (heard, meant) pair. A first sighting is `active` when
    /// `learnNow` and `pending` otherwise; a second sighting with a new history ID promotes
    /// a pending entry. A history ID already counted changes nothing, so two triggers for
    /// one paste never make two sightings.
    @discardableResult
    public static func recordSighting(
        heard: String, meant: String, app: String, historyID: UUID, learnNow: Bool,
        heardIsWord: Bool = false, now: Date = Date(), in entries: inout [LearnedEntry]
    ) -> Sighting {
        if let index = entries.firstIndex(where: { matches($0, heard: heard, meant: meant) }) {
            if entries[index].state == .removed { return .blocked }
            if entries[index].historyIDs.contains(historyID) { return .duplicate }
            entries[index].sightings += 1
            entries[index].lastSeen = now
            entries[index].historyIDs.append(historyID)
            if entries[index].state == .pending {
                entries[index].state = .active
                return .promoted
            }
            return .counted
        }
        let state: LearnedEntry.State = learnNow ? .active : .pending
        entries.append(LearnedEntry(
            heard: heard, meant: meant, state: state, firstSeen: now, lastSeen: now, app: app,
            historyIDs: [historyID], heardIsWord: heardIsWord))
        return .created(state)
    }

    /// Turns an entry into a tombstone, keyed on its exact (heard, meant) pair.
    public static func markRemoved(id: UUID, in entries: inout [LearnedEntry]) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].state = .removed
    }

    public static func active(_ entries: [LearnedEntry]) -> [LearnedEntry] {
        entries.filter { $0.state == .active }
    }

    /// Drops pending entries not seen for 30 days and keeps the 200 most recently seen
    /// active ones. Tombstones stay.
    public static func pruned(_ entries: [LearnedEntry], now: Date = Date()) -> [LearnedEntry] {
        var kept = entries.filter { $0.state != .pending || now.timeIntervalSince($0.lastSeen) < pendingLifetime }
        let active = kept.filter { $0.state == .active }
        if active.count > maximumActive {
            let drop = Set(active.sorted { $0.lastSeen < $1.lastSeen }.prefix(active.count - maximumActive).map(\.id))
            kept.removeAll { drop.contains($0.id) }
        }
        return kept
    }

    static func matches(_ entry: LearnedEntry, heard: String, meant: String) -> Bool {
        entry.heard.lowercased() == heard.lowercased() && entry.meant == meant
    }
}

public enum Learned {
    /// The speaker's own Corrections first, so a hand-written one wins for the same word,
    /// then the learned rules in order, through one `TextCleaner.apply` call. `appliedIDs`
    /// holds the rules that changed the text.
    public static func apply(
        _ rules: [LearnedRule], corrections: [TextCleaner.Correction], to text: String
    ) -> (text: String, appliedIDs: [UUID]) {
        let all = corrections + rules.map { TextCleaner.Correction(heard: $0.heard, meant: $0.meant) }
        var current = TextCleaner.apply(corrections, to: text)
        var applied: [UUID] = []
        for rule in rules {
            let next = TextCleaner.apply([.init(heard: rule.heard, meant: rule.meant)], to: current)
            if next != current { applied.append(rule.id) }
            current = next
        }
        return (TextCleaner.apply(all, to: text), applied)
    }
}
