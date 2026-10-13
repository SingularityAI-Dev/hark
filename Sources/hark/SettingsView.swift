import ServiceManagement
import Speech
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var locales: [String] = []
    @State private var microphones: [(uid: String, name: String)] = []
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
                Text("Hold the key and speak, or tap it once for hands-free and press it again to finish. Esc cancels. Tap Shift to polish. Ctrl+Cmd+V pastes the last result.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Cleanup") {
                Toggle("Always polish with the on-device model", isOn: $settings.alwaysPolish)
                    .disabled(!Refiner.modelAvailable)
                Text(Refiner.modelAvailable
                    ? "Fillers and stutters are always removed instantly. Polishing also fixes self-corrections and punctuation but takes several seconds. Tap Shift while dictating to polish just that one."
                    : "Apple Intelligence is off or unsupported on this Mac, so only the instant cleanup runs.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Dictionary") {
                TextEditor(text: $settings.dictionaryText)
                    .font(.body.monospaced())
                    .frame(height: 110)
                Text("One name or term per line. Used to recognise and spell them correctly.")
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
        .frame(width: 460, height: 560)
        .task {
            microphones = AudioDevices.inputs()
            var ids = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }.sorted()
            if !ids.contains(settings.localeID) { ids.insert(settings.localeID, at: 0) }
            locales = ids
        }
    }
}
