import Foundation
import HarkCore

/// Dictation history as one JSON object per line. Text only; no audio is kept.
final class HistoryStore: ObservableObject {
    struct Entry: Codable, Identifiable {
        var id = UUID()
        var date: Date
        var raw: String
        var text: String
        var app: String?
        /// Key down to paste, including transcription and cleanup.
        var seconds: Double
        /// Key down to the finishing key press. Missing from entries written before it existed.
        var spoken: Double?

        var record: DictationRecord {
            DictationRecord(date: date, words: TextCleaner.wordCount(text), seconds: spoken ?? seconds)
        }
    }

    @Published private(set) var entries: [Entry] = []
    private let fileURL: URL
    private let encoder = JSONEncoder()

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hark", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("history.jsonl")
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
            entries = contents.split(separator: "\n").compactMap {
                try? decoder.decode(Entry.self, from: Data($0.utf8))
            }
        }
    }

    var latest: Entry? { entries.last }

    func append(_ entry: Entry) {
        entries.append(entry)
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: fileURL)
        }
    }

    func clear() {
        entries = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    func remove(_ id: Entry.ID) {
        entries.removeAll { $0.id == id }
        rewrite()
    }

    /// Drops entries older than `days`; 0 keeps everything.
    func prune(keepingDays days: Int, now: Date = Date()) {
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else { return }
        let kept = entries.filter { $0.date >= cutoff }
        guard kept.count < entries.count else { return }
        entries = kept
        rewrite()
    }

    private func rewrite() {
        var data = Data()
        for entry in entries {
            guard let line = try? encoder.encode(entry) else { continue }
            data.append(line)
            data.append(0x0A)
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
