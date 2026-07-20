import AppKit

@MainActor
enum MenuBarRingIcon {
    // ponytail: 13 possible fractions (quantized twelfths), cache them all —
    // the menu bar label re-renders on every countdown text change and would
    // otherwise redraw an identical NSImage each time.
    private static var cache: [Int: NSImage] = [:]

    static func image(fraction: Double) -> NSImage {
        let step = Int((min(1, max(0, fraction)) * 12).rounded())
        if let cached = cache[step] { return cached }
        let image = draw(fraction: Double(step) / 12)
        cache[step] = image
        return image
    }

    private static func draw(fraction: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.5

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 1.5
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            if fraction > 0 {
                let progress = NSBezierPath()
                let startAngle: CGFloat = 90
                let endAngle = startAngle - CGFloat(fraction) * 360
                progress.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                progress.lineWidth = 3
                progress.lineCapStyle = .round
                NSColor.black.setStroke()
                progress.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
