import AppKit

@MainActor
final class PointerCountdownOverlayController {
    private var window: NSPanel?
    private var label: NSTextField?
    private var trackingTimer: Timer?
    private var currentSeconds: Int?

    deinit {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    func show(secondsRemaining: Int) {
        let value = max(1, secondsRemaining)

        ensureWindow()
        guard let window else { return }

        if currentSeconds != value {
            currentSeconds = value
            updateLabel("\(value)s")
        }
        if !window.isVisible {
            // Snap first frame near cursor before fade-in.
            let initial = targetOrigin(for: window)
            window.setFrameOrigin(initial)
            window.alphaValue = 0
            window.orderFrontRegardless()
            window.animator().alphaValue = 1
        }

        startTrackingIfNeeded()
    }

    func hide() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        currentSeconds = nil

        guard let window, window.isVisible else { return }
        window.animator().alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, let window = self.window else { return }
            if self.currentSeconds == nil {
                window.orderOut(nil)
            }
        }
    }

    private func ensureWindow() {
        guard window == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 132, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.level = .init(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow

        let container = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.58).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor

        let textField = NSTextField(labelWithString: "")
        textField.font = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        textField.textColor = .white
        textField.alignment = .center

        container.addSubview(textField)
        panel.contentView = container

        window = panel
        label = textField
    }

    private func updateLabel(_ text: String) {
        guard let window, let label else { return }

        label.stringValue = text
        label.sizeToFit()

        let paddingX: CGFloat = 7
        let paddingY: CGFloat = 8
        let width = max(56, label.frame.width + (paddingX * 2))
        let height = label.frame.height + (paddingY * 2)

        label.frame = NSRect(x: paddingX, y: paddingY, width: width - (paddingX * 2), height: label.frame.height)
        window.setContentSize(NSSize(width: width, height: height))
    }

    private func startTrackingIfNeeded() {
        guard trackingTimer == nil else { return }

        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickTracking()
            }
        }
        trackingTimer?.tolerance = 0.005
        if let trackingTimer {
            RunLoop.main.add(trackingTimer, forMode: .common)
        }
    }

    private func tickTracking() {
        guard let window, window.isVisible else { return }

        let target = targetOrigin(for: window)
        let current = window.frame.origin

        // Low-pass interpolation for smoother tracking.
        let smoothing: CGFloat = 0.28
        let next = NSPoint(
            x: current.x + (target.x - current.x) * smoothing,
            y: current.y + (target.y - current.y) * smoothing
        )

        window.setFrameOrigin(next)
    }

    private func targetOrigin(for window: NSWindow) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        let size = window.frame.size
        var origin = NSPoint(x: mouse.x + 22, y: mouse.y - size.height - 14)

        origin.x = max(visibleFrame.minX + 8, min(origin.x, visibleFrame.maxX - size.width - 8))
        origin.y = max(visibleFrame.minY + 8, min(origin.y, visibleFrame.maxY - size.height - 8))

        return origin
    }
}
