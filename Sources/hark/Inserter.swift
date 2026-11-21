import AppKit
import CoreGraphics

/// Puts text at the cursor of the focused app by pasting it.
///
/// The dictated text deliberately stays on the clipboard afterwards. Restoring the old
/// clipboard after a fixed delay raced with apps that read the pasteboard late (Electron,
/// browsers under load), so they pasted the previous clipboard instead of the dictation.
enum Inserter {
    /// Clipboard managers that honour nspasteboard.org skip entries carrying this type.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// Lets the pasteboard write settle before the paste shortcut is posted.
    private static let settleDelay: TimeInterval = 0.05

    @MainActor
    static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: transientType)

        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
            postPasteShortcut()
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
