import Foundation

/// Where hark keeps its files: `~/Library/Application Support/hark`.
public enum HarkPaths {
    public static var supportFolder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hark", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
