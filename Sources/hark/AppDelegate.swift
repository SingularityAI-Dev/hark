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
    private let pasteTarget = PasteTarget()
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
    /// Dictations finished but not yet pasted. Read-back waits until this is zero, so it
    /// never reads a field while another paste may be landing in it.
    private var inFlight = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setIcon(recording: false)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotkeys.trigger = settings.triggerKey
        hotkeys.onAction = { [weak self] action in self?.handle(action) }
        hotkeys.onPasteLast = { [weak self] in self?.pasteLast() }
        hotkeys.onReturn = { [weak self] in self?.returnPressed() }
        hotkeys.onPolishRequested = { [weak self] in
            guard let self else { return }
            indicator.model.polish = !settings.alwaysPolish
        }
        settings.$triggerKey.sink { [weak self] in self?.hotkeys.trigger = $0 }.store(in: &subscriptions)
        settings.$keepHistoryDays.sink { [weak self] in self?.history.prune(keepingDays: $0) }.store(in: &subscriptions)

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        startHotkeysWhenTrusted()
        Task { await transcriber.prepare(locale: settings.locale) }
        Task { await TraceLog.shared.load() }
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

    /// Return was pressed. Only starts a task: the event tap must never wait on Accessibility.
    private func returnPressed() {
        guard settings.learnFromEdits, inFlight == 0 else { return }
        let target = pasteTarget
        let probing = settings.readbackProbe
        Task.detached { [weak self] in
            let focus = PasteTarget.focusedElement()
            if probing {
                guard let record = await target.peek(focused: focus) else { return }
                await target.probe(record, after: [.milliseconds(100), .milliseconds(300), .milliseconds(600), .milliseconds(1000)])
                return
            }
            guard let record = await target.claim(trigger: .enter, focused: focus) else { return }
            try? await Task.sleep(for: PasteTarget.readDelay)
            let result = await target.read(record, trigger: .enter)
            await self?.learnFromRead(result, record: record, trigger: .enter)
        }
    }

    /// Phase A coordinator: counts what the read-back found and runs the pair finder and the
    /// filter as a dry run. Nothing is stored, applied or shown, and the read text is dropped
    /// when this returns.
    private func learnFromRead(
        _ result: Result<PasteTarget.ReadResult, PasteTarget.Failure>, record: PasteTarget.Record,
        trigger: PasteTarget.Trigger
    ) async {
        let target = pasteTarget
        let prefix = trigger == .enter ? "enter." : ""
        let read: PasteTarget.ReadResult
        switch result {
        case .failure(let failure):
            await target.count(key: prefix + failure.outcome.rawValue, bundleID: record.bundleID)
            return
        case .success(let value):
            read = value
        }
        let outcome: PasteTarget.Outcome
        switch EditDiff.nearCopy(pasted: record.pasted, readBack: read.text) {
        case .unchanged: outcome = .unchanged
        case .changed: outcome = .changed1or2
        case .different: outcome = .different
        }
        // Return in an app where it is a newline: the paste is still there untouched, so keep
        // the record for the Fn trigger and count nothing (one count per paste).
        if trigger == .enter, outcome == .unchanged {
            await target.release(record)
            return
        }
        await target.count(key: prefix + outcome.rawValue, bundleID: record.bundleID)
        guard case .pairs(let pairs, let line) = EditPairs.align(pasted: record.pasted, readBack: read.text) else { return }
        let localeID = settings.localeID
        for pair in pairs {
            let verdict = LearnFilter.judge(
                pair: pair, raw: record.raw, line: line, isWord: { Self.isDictionaryWord($0, localeID: localeID) }, learned: [])
            switch verdict {
            case .learnNow: await target.count(key: "would.learnNow", bundleID: record.bundleID)
            case .waitForSecond: await target.count(key: "would.wait", bundleID: record.bundleID)
            case .reject(let reason): await target.count(key: "reject.\(reason.rawValue)", bundleID: record.bundleID)
            }
        }
    }

    /// True when the spell checker knows `word` in the Settings language.
    private static func isDictionaryWord(_ word: String, localeID: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: localeID, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        ).location == NSNotFound
    }

    private func handle(_ action: HotkeyStateMachine.Action) {
        switch action {
        case .start:
            targetApp = NSWorkspace.shared.frontmostApplication?.localizedName
            // Read the last paste's field back once, unless a paste is still on its way or
            // Return already read it.
            if settings.learnFromEdits, inFlight == 0 {
                let target = pasteTarget
                Task.detached { [weak self] in
                    guard let record = await target.claim(trigger: .fn, focused: nil) else { return }
                    let result = await target.read(record, trigger: .fn)
                    await self?.learnFromRead(result, record: record, trigger: .fn)
                }
            }
            startedAt = Date()
            play(startSound)
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
                    log.notice("microphone on after \(milliseconds(since: began)) ms")
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
            // Shift flips the setting for this one dictation.
            let shiftFlipped = hotkeys.polishRequested
            let polish = settings.alwaysPolish != shiftFlipped
            let skip: PolishTrace.Skip? = polish ? nil : (shiftFlipped ? .shift : .settingOff)
            let snapshot = settings.snapshot
            inFlight += 1
            enqueue { [self] in
                defer { inFlight -= 1 }
                guard recording else {
                    indicator.hide()
                    return
                }
                recording = false
                do {
                    let began = ContinuousClock.now
                    let raw = try await transcriber.finish()
                    let transcribed = milliseconds(since: began)
                    log.notice("transcribed \(raw.count) characters in \(transcribed) ms")
                    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        indicator.flash("Nothing heard", seconds: 1.5)
                        return
                    }
                    let entryID = UUID()
                    var result = await Dictation.process(
                        raw: raw, entryID: entryID, snapshot: snapshot, server: PolishServer.from(snapshot),
                        skip: skip, shiftFlipped: shiftFlipped,
                        sink: { line in Task { await TraceLog.shared.appendLate(line) } })
                    result.trace.transcribeMilliseconds = transcribed
                    guard !result.text.isEmpty else {
                        indicator.hide()
                        return
                    }
                    Inserter.paste(result.text)
                    await TraceLog.shared.append(result.trace)
                    if settings.learnFromEdits {
                        let target = pasteTarget
                        let generation = await target.currentGeneration
                        let pasted = result.text
                        Task.detached {
                            await target.capture(pasted: pasted, raw: raw, historyID: entryID, generation: generation)
                        }
                    }
                    history.append(.init(
                        id: entryID, date: Date(), raw: raw, text: result.text, app: targetApp,
                        seconds: Date().timeIntervalSince(startedAt), spoken: spoken))
                    play(finishSound)
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

    private func pasteLast() {
        guard let entry = history.latest else { return }
        Inserter.paste(entry.text)
    }

    private let startSound = NSSound(data: Chime.wav(Chime.start))
    private let finishSound = NSSound(data: Chime.wav(Chime.finish))

    private func play(_ sound: NSSound?) {
        guard settings.soundsEnabled, let sound else { return }
        sound.stop()
        sound.play()
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
        showInDock()
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    /// Drops the closed window so its views are freed and idle memory goes back down.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if window === dashboardWindow {
                window.contentViewController = nil
                dashboardWindow = nil
            }
            hideFromDockIfNoWindows()
        }
    }

    /// While the hark window or Settings is open the app shows in the Dock and the
    /// Command-Tab switcher; with both closed it goes back to being menu bar only.
    private func showInDock() {
        NSApp.setActivationPolicy(.regular)
    }

    private func hideFromDockIfNoWindows() {
        let open = [dashboardWindow, settingsWindow].contains { $0?.isVisible == true }
        if !open { NSApp.setActivationPolicy(.accessory) }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.title = "hark Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }
        showInDock()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
