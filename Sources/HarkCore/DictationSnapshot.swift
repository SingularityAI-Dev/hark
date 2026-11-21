import Foundation

/// The settings one dictation is processed with. The app builds it from Settings; the
/// eval builds it from a JSON file, so results do not change as Settings change.
public struct DictationSnapshot: Codable, Equatable {
    public var dictionary: [String]
    public var correctionsText: String
    public var polishServerURL: String?
    public var polishServerModel: String?

    public init(dictionary: [String], correctionsText: String, polishServerURL: String? = nil, polishServerModel: String? = nil) {
        self.dictionary = dictionary
        self.correctionsText = correctionsText
        self.polishServerURL = polishServerURL
        self.polishServerModel = polishServerModel
    }

    /// One term per line, exactly as the Settings window stores the Dictionary.
    public init(dictionaryText: String, correctionsText: String, polishServerURL: String?, polishServerModel: String?) {
        self.init(
            dictionary: Self.terms(from: dictionaryText), correctionsText: correctionsText,
            polishServerURL: polishServerURL, polishServerModel: polishServerModel)
    }

    public static func terms(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var corrections: [TextCleaner.Correction] { TextCleaner.corrections(from: correctionsText) }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        dictionary = try values.decodeIfPresent([String].self, forKey: .dictionary) ?? []
        correctionsText = try values.decodeIfPresent(String.self, forKey: .correctionsText) ?? ""
        polishServerURL = try values.decodeIfPresent(String.self, forKey: .polishServerURL)
        polishServerModel = try values.decodeIfPresent(String.self, forKey: .polishServerModel)
    }
}
