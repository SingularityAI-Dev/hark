import ServiceManagement
import Speech
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var locales: [String] = []
    @State private var microphones: [(uid: String, name: String)] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var serverKey = Keychain.polishServerKey ?? ""

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Hold to talk", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases) { Text($0.label).tag($0) }
                }
                Picker("Language", selection: $settings.localeID) {
                    ForEach(locales, id: \.self) { id in
                        Text(Locale.current.localizedString(forIdentifier: id) ?? id).tag(id)
                    }
                }
                Picker("Microphone", selection: $settings.inputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(microphones, id: \.uid) { Text($0.name).tag($0.uid) }
                }
                Text("Hold the key and speak, or tap it once for hands-free and press it again to finish. Esc cancels. Tap Shift to switch polish the other way for one dictation. Ctrl+Cmd+V pastes the last result.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Cleanup") {
                Toggle("Polish every dictation with the on-device model", isOn: $settings.alwaysPolish)
                    .disabled(!Refiner.modelAvailable)
                Text(Refiner.modelAvailable
                    ? "Fillers and repeats are always removed instantly. Polishing also drops what you take back (\"wait, sorry, it's the other one\") and half-finished phrases, and fixes punctuation. It adds about a second, more for long dictations. Tap Shift while dictating to switch it for that one."
                    : "Apple Intelligence is off or unsupported on this Mac, so only the instant cleanup runs.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Polish server") {
                TextField("Server URL", text: $settings.polishServerURL, prompt: Text("http://localhost:3001/v1"))
                TextField("Model", text: $settings.polishServerModel, prompt: Text("auto"))
                SecureField("API key", text: $serverKey)
                    .onSubmit { Keychain.polishServerKey = serverKey }
                    .onChange(of: serverKey) { _, key in Keychain.polishServerKey = key }
                Text("Leave the URL empty to polish with Apple's on-device model. With a URL set, every polished dictation is sent to that server; FreeLLMAPI passes it on to free cloud providers.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Dictionary") {
                TextEditor(text: $settings.dictionaryText)
                    .font(.body.monospaced())
                    .frame(height: 110)
                Text("One name or term per line. Used to recognise and spell them correctly.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Corrections") {
                TextEditor(text: $settings.correctionsText)
                    .font(.body.monospaced())
                    .frame(height: 70)
                Text("For words that keep being misheard. One per line, as heard = meant, for example: tasting = testing")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Play sounds", isOn: $settings.soundsEnabled)
                Toggle("Mute other audio while dictating", isOn: $settings.muteWhileDictating)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 820)
        .task {
            microphones = AudioDevices.inputs()
            var ids = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }.sorted()
            if !ids.contains(settings.localeID) { ids.insert(settings.localeID, at: 0) }
            locales = ids
        }
    }
}
