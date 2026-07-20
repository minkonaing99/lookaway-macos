import AppKit

@MainActor
final class DimPreAlertOverlayController {
    private var windows: [NSWindow] = []

    static let maxDimAlpha: Double = 0.35
    static let rampSeconds: Double = 30

    static func dimAlpha(secondsRemaining: Double) -> Double {
        let progress = min(1, max(0, (rampSeconds - secondsRemaining) / rampSeconds))
        return progress * maxDimAlpha
    }

    func show(secondsRemaining: Double) {
        let screens = NSScreen.screens
        let screensChanged = windows.count != screens.count
            || zip(windows, screens).contains { $0.frame != $1.frame }
        if screensChanged {
            windows.forEach { $0.orderOut(nil) }
            windows = screens.map(makeWindow(for:))
        }
        let alpha = Self.dimAlpha(secondsRemaining: secondsRemaining)
        for window in windows {
            window.alphaValue = alpha
            window.orderFrontRegardless()
        }
    }

    func hide() {
        guard !windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows = []
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .black
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        return window
    }
}
