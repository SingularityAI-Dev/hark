import AppKit
import ApplicationServices
import Foundation
import HarkCore
import os

/// Remembers the text field hark last pasted into and reads it back once per paste, at
/// Return or at the next dictation, whichever comes first. This phase only counts what it
/// finds, per app, in `readback-counts.json`: no text is stored or logged, and nothing is
/// learned. One element, one read per paste, through Accessibility (already granted for the
/// hotkey); no observer is left on the other app.
actor PasteTarget {
    enum Outcome: String, Codable, CaseIterable {
        case noElement, notText, unverified, timeout, gone, unchanged, changed1or2, different, noCount
    }

    enum Trigger { case fn, enter }

    /// The paste being remembered. AXUIElement is a CF type that is safe to pass between
    /// threads; the wrapper says so to the compiler.
    struct Record: @unchecked Sendable {
        var element: AXUIElement
        var pid: pid_t
        var bundleID: String
        /// UTF-16 offset of the caret just after the paste.
        var caret: Int
        var pasted: String
        var time: Date
        /// The recogniser's transcript. Memory only.
        var raw: String
        var historyID: UUID
        /// A Return read has claimed this record and has not finished.
        var readStarted = false
    }

    /// The focused element when Return was pressed, found off the event tap.
    struct Focus: @unchecked Sendable {
        var element: AXUIElement?
    }

    /// The text read back. Never stored or logged.
    struct ReadResult: Sendable {
        let record: Record
        let text: String
    }

    struct Failure: Error, Sendable {
        let outcome: Outcome
    }

    private enum Capture: @unchecked Sendable {
        case record(Record)
        case failed(Outcome, bundleID: String)
    }

    static let maximumAge: TimeInterval = 30 * 60
    /// Wait between Return and the read-back, so the app has finished handling the key.
    /// Changed only from the probe's numbers.
    static let readDelay: Duration = .milliseconds(300)
    /// How much of the end of the field a Return read takes (UTF-16 units).
    static let tailLength = 2000
    private static let textRoles: Set<String> = [
        kAXTextAreaRole as String, kAXTextFieldRole as String, kAXComboBoxRole as String, "AXSearchField",
    ]
    private static let log = Logger(subsystem: "dev.hark.app", category: "readback")

    private var record: Record?
    /// Bumped whenever an Fn read takes the record, so a capture that finishes after the
    /// next dictation has started is dropped instead of being read back by the wrong one.
    private var generation = 0
    private let countsURL = HarkPaths.supportFolder.appendingPathComponent("readback-counts.json")
    private let probeURL = HarkPaths.supportFolder.appendingPathComponent("probe-counts.json")

    var currentGeneration: Int { generation }

    /// Called right after a paste. Waits for the paste to land, then remembers the focused
    /// field if it is a text field holding the pasted text just before the caret.
    nonisolated func capture(pasted: String, raw: String, historyID: UUID, generation: Int) async {
        for attempt in 0..<2 {
            try? await Task.sleep(for: .milliseconds(150))
            let result = Self.inspectFocus(pasted: pasted, raw: raw, historyID: historyID)
            if case .failed(.unverified, _) = result, attempt == 0 { continue }
            await store(result, generation: generation)
            return
        }
    }

    private func store(_ result: Capture, generation: Int) {
        guard generation == self.generation else { return }
        switch result {
        case .record(let record): self.record = record
        case .failed(let outcome, let bundleID):
            record = nil
            count(key: outcome.rawValue, bundleID: bundleID)
        }
    }

    /// The field Accessibility reports as focused, for the Return trigger. Called off the
    /// event tap.
    nonisolated static func focusedElement() -> Focus {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return Focus(element: nil) }
        return Focus(element: (focused as! AXUIElement))
    }

    /// Returns the record to read, or nil when there is nothing to read.
    /// `.fn` (the next dictation starts) takes the record and bumps `generation`.
    /// `.enter` (Return) keeps the record and marks it `readStarted`, and only when the
    /// focused element is the pasted-into field of the frontmost app, so a Return in another
    /// tab or window leaves it alone. A record whose Return read is still running is not
    /// handed out again, so each paste is read once.
    func claim(trigger: Trigger, focused: Focus?) -> Record? {
        if trigger == .fn { generation += 1 }
        guard var current = record else { return nil }
        if Date().timeIntervalSince(current.time) >= Self.maximumAge {
            if trigger == .fn { record = nil }
            return nil
        }
        guard !current.readStarted else { return nil }
        switch trigger {
        case .fn:
            record = nil
            return current
        case .enter:
            guard isTarget(current, focused: focused) else { return nil }
            current.readStarted = true
            record = current
            return current
        }
    }

    /// Like `claim(trigger: .enter)` without marking anything, for the probe.
    func peek(focused: Focus?) -> Record? {
        guard let current = record, !current.readStarted,
            Date().timeIntervalSince(current.time) < Self.maximumAge, isTarget(current, focused: focused)
        else { return nil }
        return current
    }

    private func isTarget(_ record: Record, focused: Focus?) -> Bool {
        guard let element = focused?.element, CFEqual(element, record.element),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == record.pid
        else { return false }
        return true
    }

    /// Reads the field once. A Return read takes the record now; `release` hands it back
    /// when the paste turned out to be unchanged.
    func read(_ record: Record, trigger: Trigger) -> Result<ReadResult, Failure> {
        if trigger == .enter, self.record?.historyID == record.historyID { self.record = nil }
        switch Self.readText(record, trigger: trigger) {
        case .success(let text): return .success(ReadResult(record: record, text: text))
        case .failure(let failure): return .failure(failure)
        }
    }

    /// After a Return read that found the paste present and unchanged (Return was a newline,
    /// as in TextEdit): keep the record so the Fn trigger can still read it. Does nothing if
    /// another paste has been remembered since.
    func release(_ record: Record) {
        guard self.record == nil, Date().timeIntervalSince(record.time) < Self.maximumAge else { return }
        var kept = record
        kept.readStarted = false
        self.record = kept
    }

    // MARK: Probe

    /// Reads the field at each delay after Return without claiming the record and counts
    /// flags only (read ok, length class, changes found, whether the paste is the last thing
    /// on screen, whether the read holds border glyphs) in `probe-counts.json`.
    func probe(_ record: Record, after delays: [Duration]) async {
        var waited = Duration.zero
        for delay in delays {
            try? await Task.sleep(for: delay - waited)
            waited = delay
            let ms = Int(delay.components.seconds * 1000 + delay.components.attoseconds / 1_000_000_000_000_000)
            let prefix = "probe.\(ms)ms."
            switch Self.readText(record, trigger: .enter) {
            case .failure:
                count(key: prefix + "readFail", bundleID: record.bundleID, file: probeURL)
            case .success(let text):
                var flags = ["readOk", text.utf16.count < 500 ? "len.0to500" : "len.500to2000"]
                switch EditDiff.nearCopy(pasted: record.pasted, readBack: text) {
                case .unchanged: flags.append("changes.0")
                case .changed(let changes): flags.append(changes == 1 ? "changes.1" : "changes.2plus")
                case .different: flags.append("changes.2plus")
                }
                if let after = EditDiff.wordsAfterBestStretch(pasted: record.pasted, readBack: text),
                    after < TextCleaner.wordCount(record.pasted)
                { flags.append("lastOnScreen") }
                if text.unicodeScalars.contains(where: { (0x2500...0x259F).contains($0.value) }) { flags.append("borderGlyphs") }
                for flag in flags { count(key: prefix + flag, bundleID: record.bundleID, file: probeURL) }
            }
        }
    }

    // MARK: Accessibility

    private static func inspectFocus(pasted: String, raw: String, historyID: UUID) -> Capture {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return .failed(.noElement, bundleID: frontmostBundleID()) }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.25)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"

        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        guard textRoles.contains(role), subrole != (kAXSecureTextFieldSubrole as String) else {
            return .failed(.notText, bundleID: bundleID)
        }
        guard let caret = selectedLocation(element) else { return .failed(.notText, bundleID: bundleID) }
        let length = pasted.utf16.count
        guard caret >= length,
            let before = try? text(element, location: caret - length, length: length),
            EditDiff.nearCopy(pasted: pasted, readBack: before) == .unchanged
        else { return .failed(.unverified, bundleID: bundleID) }
        return .record(Record(
            element: element, pid: pid, bundleID: bundleID, caret: caret, pasted: pasted, time: Date(),
            raw: raw, historyID: historyID))
    }

    private static func readText(_ record: Record, trigger: Trigger) -> Result<String, Failure> {
        guard NSRunningApplication(processIdentifier: record.pid) != nil else { return .failure(Failure(outcome: .gone)) }
        AXUIElementSetMessagingTimeout(record.element, 0.25)
        var total: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(record.element, kAXNumberOfCharactersAttribute as CFString, &total)
        let count: Int
        if status == .success, let reported = total as? Int {
            count = reported
        } else if status == .invalidUIElement || status == .cannotComplete {
            return .failure(Failure(outcome: outcome(for: status)))
        } else if trigger == .enter {
            // The tail of the field needs the count; slicing the whole value is not used.
            return .failure(Failure(outcome: .noCount))
        } else {
            // Apps that do not report a character count: use the value's length, keeping a
            // timeout or a vanished element distinct from a missing value.
            var value: CFTypeRef?
            let valueStatus = AXUIElementCopyAttributeValue(record.element, kAXValueAttribute as CFString, &value)
            guard valueStatus == .success, let string = value as? String else {
                return .failure(Failure(outcome: outcome(for: valueStatus)))
            }
            count = string.utf16.count
        }
        let start: Int
        let end: Int
        switch trigger {
        case .fn:
            start = max(0, record.caret - record.pasted.utf16.count - 40)
            end = min(count, record.caret + 120)
        case .enter:
            // After Return the app may clear its input box and move the caret, so take the
            // end of the field instead of a window around the old caret.
            start = max(0, count - tailLength)
            end = count
        }
        guard end > start else { return .failure(Failure(outcome: .different)) }
        do {
            return .success(try text(record.element, location: start, length: end - start, allowWholeValue: trigger == .fn))
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(Failure(outcome: .noElement))
        }
    }

    private static func outcome(for status: AXError) -> Outcome {
        switch status {
        case .invalidUIElement: .gone
        case .cannotComplete: .timeout
        default: .noElement
        }
    }

    /// Text in a UTF-16 range, through the parameterised attribute, falling back to slicing
    /// the whole value for apps that do not support it.
    private static func text(_ element: AXUIElement, location: Int, length: Int, allowWholeValue: Bool = true) throws -> String {
        var range = CFRange(location: location, length: length)
        if let value = AXValueCreate(.cfRange, &range) {
            var result: CFTypeRef?
            let status = AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, value, &result)
            if status == .success, let string = result as? String { return string }
            if status == .invalidUIElement || status == .cannotComplete { throw Failure(outcome: outcome(for: status)) }
        }
        guard allowWholeValue else { throw Failure(outcome: .noElement) }
        var whole: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &whole)
        guard status == .success, let string = whole as? String else { throw Failure(outcome: outcome(for: status)) }
        let utf16 = Array(string.utf16)
        let lower = min(max(0, location), utf16.count)
        let upper = min(lower + length, utf16.count)
        return String(decoding: utf16[lower..<upper], as: UTF16.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func selectedLocation(_ element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range.location + range.length
    }

    private static func frontmostBundleID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    }

    // MARK: Counts

    private struct Counts: Codable {
        var since: Date
        var apps: [String: [String: Int]]
    }

    /// Adds one to `key` for the app. Fn reads use the bare outcome names, Return reads the
    /// prefix `enter.`, the dry run `would.` and `reject.`.
    func count(key: String, bundleID: String) {
        count(key: key, bundleID: bundleID, file: countsURL)
    }

    private func count(key: String, bundleID: String, file: URL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var counts = (try? Data(contentsOf: file)).flatMap { try? decoder.decode(Counts.self, from: $0) }
            ?? Counts(since: Date(), apps: [:])
        counts.apps[bundleID, default: [:]][key, default: 0] += 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(counts) { try? data.write(to: file, options: .atomic) }
        if file == countsURL { Self.log.notice("read-back \(bundleID, privacy: .public): \(key, privacy: .public)") }
    }
}
