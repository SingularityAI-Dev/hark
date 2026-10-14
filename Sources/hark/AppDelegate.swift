import AVFoundation
import AppKit
import ApplicationServices
import Combine
import HarkCore
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let settings = Settings.shared
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let hotkeys = HotkeyMonitor()
    private let transcriber: Transcriber = AppleTranscriber()
    private let indicator = IndicatorPanel()
    private let history = HistoryStore()
    private let muter = OutputMuter()
    /// Timings and outcomes only, never what was said. Read with:
    /// log show --last 5m --predicate 'subsystem == "dev.hark.app"'
    private let log = Logger(subsystem: "dev.hark.app", category: "dictation")

    /// Start, finish and cancel run strictly one after another, so a quick release can
    /// never reach the transcriber before its start has completed.
    private var pipeline = Task<Void, Never> {}
    private var recording = false
    private var startedAt = Date()
    private var targetApp: String?
    private var settingsWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    private var permissionTimer: Timer?
    private var muteWork: DispatchWorkItem?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setIcon(recording: false)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotkeys.trigger = settings.triggerKey
        hotkeys.onAction = { [weak self] action in self?.handle(action) }
        hotkeys.onPasteLast = { [weak self] in self?.pasteLast() }
        hotkeys.onPolishRequested = { [weak self] in self?.indicator.model.polish = true }
        settings.$triggerKey.sink { [weak self] in self?.hotkeys.trigger = $0 }.store(in: &subscriptions)
        settings.$keepHistoryDays.sink { [weak self] in self?.history.prune(keepingDays: $0) }.store(in: &subscriptions)

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        startHotkeysWhenTrusted()
        Task { await transcriber.prepare(locale: settings.locale) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        unmute()
    }

    /// Opening hark again from Finder or Spotlight while it runs shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboard()
        return false
    }

    // MARK: Permissions

    private func startHotkeysWhenTrusted() {
        if hotkeys.start() { return }
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(prompt)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.hotkeys.start() else { return }
                timer.invalidate()
                self.permissionTimer = nil
            }
        }
    }

    // MARK: Dictation

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pipeline
        pipeline = Task {
            await previous.value
            await work()
        }
    }

    private func handle(_ action: HotkeyStateMachine.Action) {
        switch action {
        case .start:
            targetApp = NSWorkspace.shared.frontmostApplication?.localizedName
            startedAt = Date()
            playSound("Tink")
            setIcon(recording: true)
            indicator.model.polish = settings.alwaysPolish
            indicator.show(.listening)
            muteSoon()
            if settings.alwaysPolish { Refiner.prewarm(dictionary: settings.dictionary) }
            enqueue { [self] in
                do {
                    let model = indicator.model
                    let began = ContinuousClock.now
                    try await transcriber.start(
                        locale: settings.locale, contextualStrings: settings.dictionary,
                        inputDeviceUID: settings.inputDeviceUID.isEmpty ? nil : settings.inputDeviceUID,
                        onLevel: { level in DispatchQueue.main.async { model.level = level } })
                    recording = true
                    log.notice("microphone on after \(Self.milliseconds(since: began)) ms")
                } catch {
                    fail(error)
                }
            }

        case .lock:
            indicator.show(.locked)

        case .finish:
            let spoken = Date().timeIntervalSince(startedAt)
            setIcon(recording: false)
            unmute()
            indicator.show(.processing)
            let polish = settings.alwaysPolish || hotkeys.polishRequested
            enqueue { [self] in
                guard recording else {
                    indicator.hide()
                    return
                }
                recording = false
                do {
                    let began = ContinuousClock.now
                    let raw = try await transcriber.finish()
                    log.notice("transcribed \(raw.count) characters in \(Self.milliseconds(since: began)) ms")
                    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        indicator.flash("Nothing heard", seconds: 1.5)
                        return
                    }
                    let text = await Refiner.refine(
                        TextCleaner.apply(settings.corrections, to: raw),
                        dictionary: settings.dictionary, useModel: polish)
                    guard !text.isEmpty else {
                        indicator.hide()
                        return
                    }
                    Inserter.paste(text)
                    history.append(.init(
                        date: Date(), raw: raw, text: text, app: targetApp,
                        seconds: Date().timeIntervalSince(startedAt), spoken: spoken))
                    playSound("Pop")
                    indicator.hide()
                } catch {
                    fail(error)
                }
            }

        case .cancel:
            setIcon(recording: false)
            unmute()
            indicator.hide()
            enqueue { [self] in
                guard recording else { return }
                recording = false
                await transcriber.cancel()
            }

        case .none:
            break
        }
    }

    private func fail(_ error: Error) {
        recording = false
        setIcon(recording: false)
        unmute()
        log.error("dictation failed: \(String(describing: error), privacy: .public)")
        indicator.flash(error.localizedDescription)
    }

    /// Mutes other audio once the start sound has had time to play.
    private func muteSoon() {
        guard settings.muteWhileDictating else { return }
        let work = DispatchWorkItem { [weak self] in self?.muter.mute() }
        muteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (settings.soundsEnabled ? 0.3 : 0), execute: work)
    }

    private func unmute() {
        muteWork?.cancel()
        muteWork = nil
        muter.restore()
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }

    private func pasteLast() {
        guard let entry = history.latest else { return }
        Inserter.paste(entry.text)
    }

    private func playSound(_ name: String) {
        guard settings.soundsEnabled else { return }
        NSSound(named: name)?.play()
    }

    private func setIcon(recording: Bool) {
        statusItem.button?.image = MenuBarIcon.image(recording: recording)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if hotkeys.isRunning {
            menu.addItem(disabled("Hold \(settings.triggerKey.label) to dictate"))
        } else {
            menu.addItem(item("Grant Accessibility access…", #selector(openAccessibilitySettings)))
        }
        menu.addItem(item("Open hark…", #selector(openDashboard), key: "o"))
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
            menu.addItem(item("Grant Microphone access…", #selector(openMicrophoneSettings)))
        }

        let recent = history.entries.suffix(5).reversed()
        if !recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("Recent (click to copy)"))
            for entry in recent {
                let title = entry.text.count > 60 ? entry.text.prefix(60) + "…" : entry.text
                let menuItem = item(title.replacingOccurrences(of: "\n", with: " "), #selector(copyEntry(_:)))
                menuItem.representedObject = entry.text
                menu.addItem(menuItem)
            }
            menu.addItem(item("Clear history", #selector(clearHistory)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit hark", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = target ?? self
        return menuItem
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    @objc private func copyEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func clearHistory() {
        history.clear()
    }

    @objc private func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private func open(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    @objc private func openDashboard() {
        if dashboardWindow == nil {
            let view = DashboardView(history: history, settings: settings) { [weak self] in self?.openSettings() }
            let hosting = NSHostingController(rootView: view)
            hosting.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "hark"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 1100, height: 760))
            window.center()
            dashboardWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    /// Drops the closed window so its views are freed and idle memory goes back down.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === dashboardWindow else { return }
        DispatchQueue.main.async { [weak self] in
            window.contentViewController = nil
            self?.dashboardWindow = nil
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.title = "hark Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
