import Foundation
import HarkCore

/// Turns a raw transcript into the text to paste. The app and `hark --refine` both call
/// this, so the eval measures the path live dictation uses.
enum Dictation {
    /// `server` is passed in rather than read here so the command line can force Apple's
    /// model (`--device-only`); the app passes `PolishServer.from(snapshot)`.
    static func process(
        raw: String, entryID: UUID, snapshot: DictationSnapshot, server: PolishServer?,
        skip: PolishTrace.Skip?, shiftFlipped: Bool, sink: (@Sendable (PolishTrace) -> Void)?
    ) async -> RefineResult {
        let corrected = TextCleaner.apply(snapshot.corrections, to: raw)
        let cleaned = TextCleaner.clean(corrected)
        return await Refiner.refine(
            cleaned: cleaned, entryID: entryID, dictionary: snapshot.dictionary,
            server: server, skip: skip, shiftFlipped: shiftFlipped, sink: sink)
    }
}

extension Settings {
    /// The settings a dictation runs with, frozen at the moment it finishes.
    var snapshot: DictationSnapshot {
        DictationSnapshot(
            dictionaryText: dictionaryText, correctionsText: correctionsText,
            polishServerURL: polishServerURL, polishServerModel: polishServerModel)
    }
}
