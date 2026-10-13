import CoreGraphics
import Foundation
import HarkCore

enum TriggerKey: String, CaseIterable, Identifiable {
    case fn, rightOption, rightCommand

    var id: String { rawValue }

    var keyCode: CGKeyCode {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .rightCommand: 54
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .fn: .maskSecondaryFn
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        }
    }

    var label: String {
        switch self {
        case .fn: "Fn (Globe)"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    @Published var triggerKey: TriggerKey { didSet { defaults.set(triggerKey.rawValue, forKey: "triggerKey") } }
    @Published var localeID: String { didSet { defaults.set(localeID, forKey: "localeID") } }
    /// Run the on-device model on every dictation, not only when Shift is added.
    @Published var alwaysPolish: Bool { didSet { defaults.set(alwaysPolish, forKey: "alwaysPolish") } }
    @Published var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") } }
    @Published var muteWhileDictating: Bool { didSet { defaults.set(muteWhileDictating, forKey: "muteWhileDictating") } }
    /// Empty means the system default input.
    @Published var inputDeviceUID: String { didSet { defaults.set(inputDeviceUID, forKey: "inputDeviceUID") } }
    @Published var dictionaryText: String { didSet { defaults.set(dictionaryText, forKey: "dictionaryText") } }
    @Published var correctionsText: String { didSet { defaults.set(correctionsText, forKey: "correctionsText") } }

    private init() {
        defaults.register(defaults: ["soundsEnabled": true, "muteWhileDictating": true])
        triggerKey = TriggerKey(rawValue: defaults.string(forKey: "triggerKey") ?? "") ?? .fn
        localeID = defaults.string(forKey: "localeID") ?? Self.defaultLocaleID()
        alwaysPolish = defaults.bool(forKey: "alwaysPolish")
        soundsEnabled = defaults.bool(forKey: "soundsEnabled")
        muteWhileDictating = defaults.bool(forKey: "muteWhileDictating")
        inputDeviceUID = defaults.string(forKey: "inputDeviceUID") ?? ""
        dictionaryText = defaults.string(forKey: "dictionaryText") ?? ""
        correctionsText = defaults.string(forKey: "correctionsText") ?? ""
    }

    var locale: Locale { Locale(identifier: localeID) }

    /// One term per line in the settings window.
    var dictionary: [String] {
        dictionaryText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// One "heard = meant" pair per line in the settings window.
    var corrections: [TextCleaner.Correction] { TextCleaner.corrections(from: correctionsText) }

    /// The system language with the system region, so a South African Mac set to US English
    /// still gets the en-ZA recogniser.
    static func defaultLocaleID() -> String {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier ?? "US"
        return "\(language)-\(region)"
    }
}
