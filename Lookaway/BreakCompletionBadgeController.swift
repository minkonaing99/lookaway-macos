import AppKit

@MainActor
final class BreakCompletionBadgeController {
    private var window: NSWindow?
    private var hideWorkItem: DispatchWorkItem?

    func show() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let window = self.window ?? makeWindow(for: screen)
        let frame = badgeFrame(in: screen.frame)

        window.setFrame(frame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1
        }

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        guard let window, window.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak window] in
            window?.orderOut(nil)
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: badgeFrame(in: screen.frame),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true

        let effectView = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .menu
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 22
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.05).cgColor
        effectView.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 0.88).cgColor
        effectView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        effectView.layer?.shadowOpacity = 1
        effectView.layer?.shadowRadius = 16
        effectView.layer?.shadowOffset = CGSize(width: 0, height: -4)

        let label = NSTextField(labelWithString: "✓  Break done")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.95)

        effectView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -22),
            label.centerYAnchor.constraint(equalTo: effectView.centerYAnchor)
        ])

        window.contentView = effectView
        self.window = window
        return window
    }

    private func badgeFrame(in screenFrame: NSRect) -> NSRect {
        let width: CGFloat = 168
        let height: CGFloat = 52
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - 108,
            width: width,
            height: height
        )
    }
}
