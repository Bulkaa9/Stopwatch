// Generates Resources/AppIcon.icns: dark macOS-style rounded square with a white stopwatch.
// Usage: swiftc tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon Resources/AppIcon.icns
import AppKit

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)

    // Apple's icon grid: 824×824 rounded square centered on a 1024 canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(white: 0.20, alpha: 1), ending: NSColor(white: 0.06, alpha: 1))!
        .draw(in: shape, angle: -90)

    NSColor.white.withAlphaComponent(0.10).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
    rim.lineWidth = 4
    rim.stroke()

    drawStopwatch()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// White stopwatch drawn from vector shapes so it stays sharp at every size.
/// The whole glyph (ring + top button) is centered on the 1024 canvas.
func drawStopwatch() {
    let stroke: CGFloat = 54
    let radius: CGFloat = 250                 // ring centerline
    let outer = radius + stroke / 2
    let stemHeight: CGFloat = 34
    let capSize = NSSize(width: 150, height: 54)

    // Center the glyph's full height (ring bottom to button top) on the canvas.
    let glyphHeight = outer * 2 + stemHeight + capSize.height
    let center = NSPoint(x: 512, y: 512 - glyphHeight / 2 + outer)

    NSColor.white.set()

    // Scale the glyph around the canvas center to leave breathing room inside the tile.
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let fit = NSAffineTransform()
    fit.translateX(by: 512, yBy: 512)
    fit.scale(by: 0.86)
    fit.translateX(by: -512, yBy: -512)
    fit.concat()

    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
    ring.lineWidth = stroke
    ring.stroke()

    // Stem and top button.
    let stemWidth: CGFloat = 50
    NSBezierPath(rect: NSRect(x: center.x - stemWidth / 2, y: center.y + outer - 4,
                              width: stemWidth, height: stemHeight + 8)).fill()
    let cap = NSRect(x: center.x - capSize.width / 2, y: center.y + outer + stemHeight,
                     width: capSize.width, height: capSize.height)
    NSBezierPath(roundedRect: cap, xRadius: capSize.height / 2, yRadius: capSize.height / 2).fill()

    // Side button at the top-right, pointing outward at 45°.
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: -45)
    transform.concat()
    let side = NSRect(x: -36, y: outer - 6, width: 72, height: 58)
    NSBezierPath(roundedRect: side, xRadius: 18, yRadius: 18).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Hand pointing to 12 o'clock, with a center dot.
    let hand = NSBezierPath()
    hand.move(to: center)
    hand.line(to: NSPoint(x: center.x, y: center.y + radius * 0.62))
    hand.lineWidth = 46
    hand.lineCapStyle = .round
    hand.stroke()
    NSBezierPath(ovalIn: NSRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84)).fill()
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote \(output.path)" : "iconutil failed")
