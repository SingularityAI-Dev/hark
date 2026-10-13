import Foundation

/// Dictation history as one JSON object per line. Text only; no audio is kept.
final class HistoryStore {
    struct Entry: Codable, Identifiable {
        var id = UUID()
        var date: Date
        var raw: String
        var text: String
        var app: String?
        var seconds: Double
    }

    private(set) var entries: [Entry] = []
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
}
