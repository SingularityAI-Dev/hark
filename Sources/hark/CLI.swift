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
        hark --refine <text>              full cleanup (rules plus on-device model)
        hark --clean <text>               rule-based cleanup only
        hark --paste <text>               paste into the focused app, then restore the clipboard
        """

    static func run(_ arguments: [String]) async -> Int32 {
        let command = arguments[0]
        let value = arguments.count > 1 ? arguments[1] : nil
        let clock = ContinuousClock()
        let started = clock.now
        func elapsed() -> String {
            let duration = clock.now - started
            return "\(Int(Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)) ms"
        }

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
        case ("--refine", let text?):
            print(await Refiner.refine(text, dictionary: Settings.shared.dictionary, useModel: true))
            FileHandle.standardError.write(Data("refined in \(elapsed())\n".utf8))
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

    private static func doctor() async {
        let settings = Settings.shared
        let resolved = await AppleTranscriber.resolve(settings.locale)
        let installed = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        let resolvedID = resolved.identifier(.bcp47)
        print("language setting:    \(settings.localeID)")
        print("recogniser locale:   \(resolvedID)")
        print("speech model:        \(installed.contains(resolvedID) ? "installed" : "will download on first use")")
        print("cleanup model:       \(Refiner.modelAvailable ? "available" : "unavailable, rule-based cleanup only")")
        print("accessibility:       \(AXIsProcessTrusted() ? "granted" : "not granted")")
        print("microphone:          \(microphoneStatus())")
        print("trigger key:         \(settings.triggerKey.label)")
    }

    private static func microphoneStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "granted"
        case .denied, .restricted: "denied"
        default: "not asked yet"
        }
    }
}
