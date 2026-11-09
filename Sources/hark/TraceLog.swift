import Foundation
import HarkCore

/// Writes and reads `polish.jsonl`, one trace line per dictation plus late lines from
/// server requests that finished after the paste. The only writer of that file, so late
/// lines cannot race a history clear. Holds timings and outcomes only.
actor TraceLog {
    static let shared = TraceLog()

    private let fileURL = HarkPaths.supportFolder.appendingPathComponent("polish.jsonl")
    private var knownIDs: Set<UUID> = []
    /// Late lines that arrived before their dictation's main line; written right after it.
    private var pending: [PolishTrace] = []
    private var loaded = false
    private let encoder = JSONEncoder()

    /// Reads the ids already in the file, so late lines can be matched to their dictation.
    func load() {
        guard !loaded else { return }
        loaded = true
        knownIDs = Set(readAll().map(\.entryID))
    }

    func append(_ trace: PolishTrace) {
        load()
        knownIDs.insert(trace.entryID)
        write(trace)
        let waiting = pending.filter { $0.entryID == trace.entryID }
        pending.removeAll { $0.entryID == trace.entryID }
        waiting.forEach(write)
    }

    /// Written once the dictation's main line exists. A late answer can arrive before the
    /// main line (the race decides, then the paste writes it), so it waits in a buffer of
    /// at most 20; one whose entry is never written, or was deleted, is never written.
    func appendLate(_ trace: PolishTrace) {
        load()
        if knownIDs.contains(trace.entryID) {
            write(trace)
        } else {
            pending.append(trace)
            if pending.count > 20 { pending.removeFirst(pending.count - 20) }
        }
    }

    func traces(for id: UUID) -> [PolishTrace] {
        readAll().filter { $0.entryID == id }
    }

    func remove(ids: Set<UUID>) {
        load()
        knownIDs.subtract(ids)
        pending.removeAll { ids.contains($0.entryID) }
        rewrite { !ids.contains($0) }
    }

    func keep(ids: Set<UUID>) {
        load()
        knownIDs.formIntersection(ids)
        pending.removeAll { !ids.contains($0.entryID) }
        rewrite { ids.contains($0) }
    }

    func removeAll() {
        knownIDs = []
        pending = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ trace: PolishTrace) {
        guard var line = try? encoder.encode(trace) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    private func readAll() -> [PolishTrace] {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return contents.split(separator: "\n").compactMap { try? decoder.decode(PolishTrace.self, from: Data($0.utf8)) }
    }

    /// Keeps lines whose entry id passes `keep`, byte for byte; a line that cannot be
    /// decoded (a partial write, or a newer format) is kept rather than deleted.
    private func rewrite(keep: (UUID) -> Bool) {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        var data = Data()
        for line in contents.split(separator: "\n") {
            if let trace = try? decoder.decode(PolishTrace.self, from: Data(line.utf8)), !keep(trace.entryID) { continue }
            data.append(Data(line.utf8))
            data.append(0x0A)
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
