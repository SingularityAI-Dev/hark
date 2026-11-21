import AVFoundation
import ApplicationServices
import Foundation
import HarkCore
import Speech

/// Command-line checks, so the speech and cleanup paths can be measured without a
/// microphone or a keyboard.
enum CLI {
    static let usage = """
        hark                              run the menu bar app
        hark --doctor                     report what this Mac supports
        hark --transcribe-file <audio>    transcribe a file with the configured language
        hark --stream-file <audio>        the same, through the path live dictation uses
        hark --refine [--settings <file>] [--device-only] <text>
                                          full cleanup, the path live dictation uses; prints
                                          the text, and a "trace:" JSON line to stderr
        hark --clean <text>               rule-based cleanup only
        hark --paste <text>               paste into the focused app, then restore the clipboard
        """

    /// The command, then `--key value` options and bare flags in any order, then one
    /// positional value (text or a path).
    struct Arguments {
        var command: String
        var value: String?
        var options: [String: String] = [:]
        var flags: Set<String> = []

        static let valueOptions: Set<String> = ["--settings"]
        static let knownFlags: Set<String> = ["--device-only"]

        init?(_ arguments: [String]) {
            guard let first = arguments.first else { return nil }
            command = first
            var rest = arguments.dropFirst()[...]
            var positional: [String] = []
            while let token = rest.popFirst() {
                if Self.valueOptions.contains(token) {
                    guard let next = rest.popFirst() else { return nil }
                    options[token] = next
                } else if Self.knownFlags.contains(token) {
                    flags.insert(token)
                } else if token.hasPrefix("--") {
                    return nil  // an unknown option
                } else {
                    positional.append(token)
                }
            }
            value = positional.isEmpty ? nil : positional.joined(separator: " ")
        }
    }

    static func run(_ arguments: [String]) async -> Int32 {
        guard let parsed = Arguments(arguments) else {
            print(usage)
            return 2
        }
        let command = parsed.command
        let value = parsed.value
        let clock = ContinuousClock()
        var started = clock.now
        func elapsed() -> String { "\(milliseconds(of: clock.now - started)) ms" }

        switch (command, value) {
        case ("--doctor", _):
            await doctor()
            return 0
        case ("--transcribe-file", let path?):
            do {
                let text = try await AppleTranscriber.transcribe(
                    file: URL(fileURLWithPath: path), locale: Settings.shared.locale)
                print(text)
                FileHandle.standardError.write(Data("transcribed in \(elapsed())\n".utf8))
                return 0
            } catch {
                FileHandle.standardError.write(Data("transcription failed: \(error.localizedDescription)\n".utf8))
                return 1
            }
        case ("--stream-file", let path?):
            do {
                let text = try await AppleTranscriber.transcribeAsLive(
                    file: URL(fileURLWithPath: path), locale: Settings.shared.locale,
                    contextualStrings: Settings.shared.dictionary)
                print(text)
                FileHandle.standardError.write(Data("streamed in \(elapsed())\n".utf8))
                return 0
            } catch {
                FileHandle.standardError.write(Data("streaming failed: \(error.localizedDescription)\n".utf8))
                return 1
            }
        case ("--refine", let text?):
            let snapshot: DictationSnapshot
            if let path = parsed.options["--settings"] {
                guard let data = FileManager.default.contents(atPath: path),
                    let decoded = try? JSONDecoder().decode(DictationSnapshot.self, from: data)
                else {
                    FileHandle.standardError.write(Data("could not read settings file \(path)\n".utf8))
                    return 1
                }
                snapshot = decoded
            } else {
                snapshot = appSnapshot()
            }
            // Like the app, which warms Apple's model while the user speaks: warm it, then
            // time only the polish itself.
            Refiner.prewarm(dictionary: snapshot.dictionary)
            try? await Task.sleep(for: .seconds(2))
            started = clock.now
            let server = parsed.flags.contains("--device-only") ? nil : PolishServer.from(snapshot)
            // No sink: the command line never writes the app's trace file.
            let result = await Dictation.process(
                raw: text, entryID: UUID(), snapshot: snapshot, server: server,
                skip: nil, shiftFlipped: false, sink: nil)
            print(result.text)
            FileHandle.standardError.write(Data("refined in \(elapsed())\n".utf8))
            if let json = try? JSONEncoder().encode(result.trace) {
                FileHandle.standardError.write(Data("trace: ".utf8) + json + Data("\n".utf8))
            }
            return 0
        case ("--chimes", let folder?):
            // Writes the start and finish sounds as WAV files, to listen with afplay.
            let directory = URL(fileURLWithPath: folder)
            try? Chime.wav(Chime.start).write(to: directory.appendingPathComponent("hark-start.wav"))
            try? Chime.wav(Chime.finish).write(to: directory.appendingPathComponent("hark-finish.wav"))
            print(directory.appendingPathComponent("hark-start.wav").path)
            print(directory.appendingPathComponent("hark-finish.wav").path)
            return 0
        case ("--clean", let text?):
            print(TextCleaner.clean(text))
            return 0
        case ("--paste", let text?):
            await MainActor.run { Inserter.paste(text) }
            // Stay alive long enough for the clipboard to be restored.
            try? await Task.sleep(for: .seconds(1))
            return 0
        default:
            print(usage)
            return command == "--help" ? 0 : 2
        }
    }

    /// The app's own settings. A plain executable's standard defaults are not the app's, so
    /// read the app's domain by name.
    private static func appSnapshot() -> DictationSnapshot {
        let defaults = UserDefaults(suiteName: "dev.hark.app") ?? .standard
        return DictationSnapshot(
            dictionaryText: defaults.string(forKey: "dictionaryText") ?? "",
            correctionsText: defaults.string(forKey: "correctionsText") ?? "",
            polishServerURL: defaults.string(forKey: "polishServerURL"),
            polishServerModel: defaults.string(forKey: "polishServerModel"))
    }

    private static func doctor() async {
        let settings = Settings.shared
        let resolved = await AppleTranscriber.resolve(settings.locale)
        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        let resolvedID = resolved.identifier(.bcp47)
        print("language setting:    \(settings.localeID)")
        print("recogniser locale:   \(resolvedID)")
        print("speech model:        \(installed.contains(resolvedID) ? "installed" : "will download on first use")")
        print("cleanup model:       \(Refiner.modelAvailable(server: PolishServer.from(appSnapshot())) ? "available" : "unavailable, rule-based cleanup only")")
        print("accessibility:       \(AXIsProcessTrusted() ? "granted" : "not granted")")
        print("microphone:          \(microphoneStatus())")
        print("trigger key:         \(settings.triggerKey.label)")
        print("mute other audio:    \(OutputMuter.isSupported ? "supported on this output" : "not supported on this output")")
    }

    private static func microphoneStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "granted"
        case .denied, .restricted: "denied"
        default: "not asked yet"
        }
    }
}
