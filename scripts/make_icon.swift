import AppKit

// LookAway app icon: rounded squircle, blue-teal aurora gradient, glowing smile.
// All geometry in 1024-space (y-up); rendered natively at each size.

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

func drawIcon() {
    guard NSGraphicsContext.current?.cgContext != nil else { return }

    // — Rounded squircle filling most of the canvas —
    let squircleRect = NSRect(x: 32, y: 32, width: 960, height: 960)
    let squircle = NSBezierPath(roundedRect: squircleRect, xRadius: 360, yRadius: 360)

    // Soft drop shadow behind the squircle (Apple bakes one into icons)
    NSGraphicsContext.current?.saveGraphicsState()
    let iconShadow = NSShadow()
    iconShadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    iconShadow.shadowBlurRadius = 28
    iconShadow.shadowOffset = NSSize(width: 0, height: -12)
    iconShadow.set()
    color(0.16, 0.45, 0.60).setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // — Aurora background, clipped to squircle —
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()

    // Diagonal teal (top-left) to blue (bottom-right) base gradient
    NSGradient(colors: [
        color(0.17, 0.56, 0.58),
        color(0.20, 0.48, 0.70),
        color(0.24, 0.44, 0.80)
    ])!.draw(in: squircleRect, angle: -70)

    func blob(_ c: NSColor, center: NSPoint, radius: CGFloat) {
        NSGradient(colors: [c, c.withAlphaComponent(0)])!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
    }
    blob(color(0.15, 0.63, 0.55, 0.50), center: NSPoint(x: 280, y: 760), radius: 380)
    blob(color(0.55, 0.72, 0.78, 0.32), center: NSPoint(x: 760, y: 800), radius: 300)
    blob(color(0.28, 0.48, 0.86, 0.40), center: NSPoint(x: 790, y: 240), radius: 380)
    blob(color(0.52, 0.62, 0.88, 0.28), center: NSPoint(x: 230, y: 230), radius: 300)

    // — Glowing white smile face —
    let white = color(1, 1, 1)
    let glow = NSShadow()
    glow.shadowColor = NSColor.white.withAlphaComponent(0.85)
    glow.shadowBlurRadius = 26
    glow.shadowOffset = .zero

    // Draw the glow layer twice for a soft neon bloom, then a crisp top pass
    for pass in 0..<2 {
        if pass == 0 { glow.set() } else {
            let none = NSShadow(); none.shadowColor = nil; none.set()
        }

        white.setStroke()

        // Smile: wide upward arc
        let smile = NSBezierPath()
        smile.lineWidth = 40
        smile.lineCapStyle = .round
        smile.move(to: NSPoint(x: 316, y: 470))
        smile.curve(to: NSPoint(x: 708, y: 470),
                    controlPoint1: NSPoint(x: 400, y: 356),
                    controlPoint2: NSPoint(x: 624, y: 356))
        smile.stroke()

        // Three short strokes above, fanning outward like relaxed lashes
        let ticks: [(NSPoint, NSPoint)] = [
            (NSPoint(x: 430, y: 560), NSPoint(x: 418, y: 636)),   // left, leans out
            (NSPoint(x: 512, y: 566), NSPoint(x: 512, y: 646)),   // center, vertical
            (NSPoint(x: 594, y: 560), NSPoint(x: 606, y: 636))    // right, leans out
        ]
        for (a, b) in ticks {
            let tick = NSBezierPath()
            tick.lineWidth = 30
            tick.lineCapStyle = .round
            tick.move(to: a)
            tick.line(to: b)
            tick.stroke()
        }
    }

    NSGraphicsContext.current?.restoreGraphicsState()
}

func render(pixels: Int, filename: String) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("context failed for \(pixels)px")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon()
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed for \(pixels)px")
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(filename)
    try! png.write(to: url)
    print("wrote \(filename) (\(pixels)px)")
}

let files: [(Int, String)] = [
    (16, "appicon-16.png"), (32, "appicon-16@2x.png"),
    (32, "appicon-32.png"), (64, "appicon-32@2x.png"),
    (128, "appicon-128.png"), (256, "appicon-128@2x.png"),
    (256, "appicon-256.png"), (512, "appicon-256@2x.png"),
    (512, "appicon-512.png"), (1024, "appicon-1024.png")
]
for (pixels, name) in files {
    render(pixels: pixels, filename: name)
}
