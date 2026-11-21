import Foundation

/// Where hark keeps its files: `~/Library/Application Support/hark`.
public enum HarkPaths {
    public static var supportFolder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hark", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Words learned from the speaker's edits (Phase B reads and writes it).
    public static var learnedFile: URL { supportFolder.appendingPathComponent("learned.json") }
}
