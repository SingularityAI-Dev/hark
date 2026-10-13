import AppKit
import CoreGraphics

/// Puts text at the cursor of the focused app by pasting it, then restores the clipboard.
enum Inserter {
    /// Clipboard managers that honour nspasteboard.org skip entries carrying this type.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let restoreDelay: TimeInterval = 0.6

    @MainActor
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: transientType)
        let ours = pasteboard.changeCount
        postPasteShortcut()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            // If something else copied in the meantime, that newer content wins.
            guard pasteboard.changeCount == ours else { return }
            pasteboard.clearContents()
            let items = saved.map { entries in
                let item = NSPasteboardItem()
                for (type, data) in entries { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
    }

    private static func postPasteShortcut() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            // Explicit flags, so a trigger key that is still held does not leak into the paste.
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
