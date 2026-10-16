// Draws the app icon and writes Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(
        starting: NSColor(red: 0.36, green: 0.42, blue: 0.98, alpha: 1),
        ending: NSColor(red: 0.16, green: 0.12, blue: 0.52, alpha: 1))!.draw(in: shape, angle: -90)

    // Five level bars, the same shape the listening pill uses.
    let heights: [CGFloat] = [200, 340, 480, 340, 200]
    let barWidth: CGFloat = 70, gap: CGFloat = 46
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = (1024 - total) / 2
    NSColor.white.setFill()
    for height in heights {
        let bar = NSRect(x: x * s, y: (512 - height / 2) * s, width: barWidth * s, height: height * s)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2 * s, yRadius: barWidth / 2 * s).fill()
        x += barWidth + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(size)x\(size).png"))
    try render(size * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
