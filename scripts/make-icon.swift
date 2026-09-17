import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size
    let inset = s * 0.06
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.28, alpha: 1),
        NSColor(calibratedRed: 0.22, green: 0.16, blue: 0.55, alpha: 1),
        NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.85, alpha: 1),
    ])!.draw(in: squircle, angle: 90)

    squircle.addClip()

    let sunCenter = NSPoint(x: s * 0.5, y: s * 0.62)
    let glow = NSGradient(colors: [
        NSColor(calibratedRed: 1, green: 0.92, blue: 0.65, alpha: 0.95),
        NSColor(calibratedRed: 1, green: 0.75, blue: 0.35, alpha: 0.35),
        NSColor.clear,
    ])!
    glow.draw(fromCenter: sunCenter, radius: 0, toCenter: sunCenter, radius: s * 0.34, options: [])

    let sunR = s * 0.10
    NSColor(calibratedRed: 1, green: 0.95, blue: 0.80, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: sunCenter.x - sunR, y: sunCenter.y - sunR, width: 2 * sunR, height: 2 * sunR)).fill()

    let dW = s * 0.56, dH = s * 0.34
    let dRect = NSRect(x: (s - dW) / 2, y: s * 0.16, width: dW, height: dH)
    let frame = NSBezierPath(roundedRect: dRect, xRadius: s * 0.045, yRadius: s * 0.045)
    NSColor.white.withAlphaComponent(0.95).setStroke()
    frame.lineWidth = s * 0.035
    frame.stroke()

    let screenRect = dRect.insetBy(dx: s * 0.035, dy: s * 0.035)
    NSGradient(colors: [
        NSColor(calibratedRed: 1, green: 0.85, blue: 0.50, alpha: 0.85),
        NSColor(calibratedRed: 0.60, green: 0.45, blue: 0.95, alpha: 0.6),
    ])!.draw(in: NSBezierPath(roundedRect: screenRect, xRadius: s * 0.02, yRadius: s * 0.02), angle: -70)

    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.44, y: s * 0.105, width: s * 0.12, height: s * 0.035),
                 xRadius: s * 0.015, yRadius: s * 0.015).fill()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, _ px: Int, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name))
}

let master = draw(size: 1024)
for (px, name) in [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
                   (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"),
                   (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")] {
    savePNG(master, px, "\(name).png")
}
print("iconset em \(out.path)")
