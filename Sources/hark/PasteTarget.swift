import AppKit
import ApplicationServices
import Foundation
import HarkCore
import os

/// Remembers the text field hark last pasted into, and at the next dictation reads it back
/// once to see whether the speaker edited the paste. This phase only counts what it finds,
/// per app, in `readback-counts.json`: no text is stored or logged, and nothing is learned.
/// One element, one read per dictation, through Accessibility (already granted for the
/// hotkey); no observer is left on the other app.
actor PasteTarget {
    enum Outcome: String, Codable, CaseIterable {
        case noElement, notText, unverified, timeout, gone, unchanged, changed1or2, different
    }

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
    }

    private enum Capture: @unchecked Sendable {
        case record(Record)
        case failed(Outcome, bundleID: String)
    }

    static let maximumAge: TimeInterval = 30 * 60
    private static let textRoles: Set<String> = [
        kAXTextAreaRole as String, kAXTextFieldRole as String, kAXComboBoxRole as String, "AXSearchField",
    ]
    private static let log = Logger(subsystem: "dev.hark.app", category: "readback")

    private var record: Record?
    /// Bumped whenever a read-back takes the record, so a capture that finishes after the
    /// next dictation has started is dropped instead of being read back by the wrong one.
    private var generation = 0
    private let countsURL = HarkPaths.supportFolder.appendingPathComponent("readback-counts.json")

    var currentGeneration: Int { generation }

    /// Called right after a paste. Waits for the paste to land, then remembers the focused
    /// field if it is a text field holding the pasted text just before the caret.
    nonisolated func capture(pasted: String, generation: Int) async {
        for attempt in 0..<2 {
            try? await Task.sleep(for: .milliseconds(150))
            let result = Self.inspectFocus(pasted: pasted)
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
            count(outcome, bundleID: bundleID)
        }
    }

    /// Called when the next dictation starts. Takes the remembered paste, reads the field
    /// once, and counts the result.
    func readBackAndCount() {
        generation += 1
        guard let record else { return }
        self.record = nil
        guard Date().timeIntervalSince(record.time) < Self.maximumAge else { return }
        switch Self.read(record) {
        case .success(let window):
            switch EditDiff.nearCopy(pasted: record.pasted, readBack: window) {
            case .unchanged: count(.unchanged, bundleID: record.bundleID)
            case .changed: count(.changed1or2, bundleID: record.bundleID)
            case .different: count(.different, bundleID: record.bundleID)
            }
        case .failure(let failure):
            count(failure.outcome, bundleID: record.bundleID)
        }
    }

    // MARK: Accessibility

    private struct Failure: Error {
        let outcome: Outcome
    }

    private static func inspectFocus(pasted: String) -> Capture {
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
        return .record(Record(element: element, pid: pid, bundleID: bundleID, caret: caret, pasted: pasted, time: Date()))
    }

    private static func read(_ record: Record) -> Result<String, Failure> {
        guard NSRunningApplication(processIdentifier: record.pid) != nil else { return .failure(Failure(outcome: .gone)) }
        AXUIElementSetMessagingTimeout(record.element, 0.25)
        var total: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(record.element, kAXNumberOfCharactersAttribute as CFString, &total)
        let count: Int
        if status == .success, let reported = total as? Int {
            count = reported
        } else if status == .invalidUIElement || status == .cannotComplete {
            return .failure(Failure(outcome: outcome(for: status)))
        } else if let value = string(record.element, kAXValueAttribute) {
            count = value.utf16.count  // apps that do not report a character count
        } else {
            return .failure(Failure(outcome: .noElement))
        }
        let start = max(0, record.caret - record.pasted.utf16.count - 40)
        let end = min(count, record.caret + 120)
        guard end > start else { return .failure(Failure(outcome: .different)) }
        do {
            return .success(try text(record.element, location: start, length: end - start))
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
    private static func text(_ element: AXUIElement, location: Int, length: Int) throws -> String {
        var range = CFRange(location: location, length: length)
        if let value = AXValueCreate(.cfRange, &range) {
            var result: CFTypeRef?
            let status = AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, value, &result)
            if status == .success, let string = result as? String { return string }
            if status == .invalidUIElement || status == .cannotComplete { throw Failure(outcome: outcome(for: status)) }
        }
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

    private func count(_ outcome: Outcome, bundleID: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var counts = (try? Data(contentsOf: countsURL)).flatMap { try? decoder.decode(Counts.self, from: $0) }
            ?? Counts(since: Date(), apps: [:])
        counts.apps[bundleID, default: [:]][outcome.rawValue, default: 0] += 1
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(counts) { try? data.write(to: countsURL, options: .atomic) }
        Self.log.notice("read-back \(bundleID, privacy: .public): \(outcome.rawValue, privacy: .public)")
    }
}
