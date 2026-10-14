import AppKit

/// The menu bar glyph: sound bars running into a text cursor, speech becoming text. Drawn in
/// code so there are no image assets. Idle it is a template image, so macOS tints it for
/// light and dark menu bars; while recording it is drawn in red.
enum MenuBarIcon {
    static func image(recording: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            (recording ? NSColor.systemRed : NSColor.black).setFill()

            let bars: [(x: CGFloat, height: CGFloat)] = [(1, 5), (4.5, 10), (8, 14), (11.5, 7)]
            for bar in bars {
                let rect = NSRect(x: bar.x, y: 8 - bar.height / 2, width: 2.2, height: bar.height)
                NSBezierPath(roundedRect: rect, xRadius: 1.1, yRadius: 1.1).fill()
            }

            // Text cursor with small serifs at both ends.
            NSBezierPath(rect: NSRect(x: 16.2, y: 1.5, width: 1.6, height: 13)).fill()
            NSBezierPath(rect: NSRect(x: 14.6, y: 1, width: 4.8, height: 1.4)).fill()
            NSBezierPath(rect: NSRect(x: 14.6, y: 13.6, width: 4.8, height: 1.4)).fill()
            return true
        }
        image.isTemplate = !recording
        image.accessibilityDescription = recording ? "hark, recording" : "hark"
        return image
    }
}
