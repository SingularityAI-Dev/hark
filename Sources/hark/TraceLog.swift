import Foundation
import HarkCore

/// Writes and reads `polish.jsonl`, one trace line per dictation plus late lines from
/// server requests that finished after the paste. The only writer of that file, so late
/// lines cannot race a history clear. Holds timings and outcomes only.
actor TraceLog {
    static let shared = TraceLog()

    private let fileURL = HarkPaths.supportFolder.appendingPathComponent("polish.jsonl")
    private var knownIDs: Set<UUID> = []
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
    }

    /// Dropped unless the dictation's main line exists, so a late answer for a deleted
    /// entry leaves nothing behind.
    func appendLate(_ trace: PolishTrace) {
        load()
        guard knownIDs.contains(trace.entryID) else { return }
        write(trace)
    }

    func traces(for id: UUID) -> [PolishTrace] {
        readAll().filter { $0.entryID == id }
    }

    func remove(ids: Set<UUID>) {
        load()
        knownIDs.subtract(ids)
        rewrite(readAll().filter { !ids.contains($0.entryID) })
    }

    func keep(ids: Set<UUID>) {
        load()
        knownIDs.formIntersection(ids)
        rewrite(readAll().filter { ids.contains($0.entryID) })
    }

    func removeAll() {
        knownIDs = []
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

    private func rewrite(_ traces: [PolishTrace]) {
        var data = Data()
        for trace in traces {
            guard let line = try? encoder.encode(trace) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
