import AppKit

@MainActor
final class CenterPreBreakBannerController {
    private var window: NSWindow?
    private weak var textField: NSTextField?
    private var hideWorkItem: DispatchWorkItem?

    func show(message: String) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let window = self.window ?? makeWindow(for: screen)
        let frame = bannerFrame(in: screen.visibleFrame)

        window.setFrame(frame, display: false)
        textField?.stringValue = message
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
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
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: bannerFrame(in: screen.visibleFrame),
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .statusBar
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
        effectView.layer?.cornerRadius = 30
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.05).cgColor
        effectView.layer?.backgroundColor = NSColor(calibratedWhite: 0.14, alpha: 0.86).cgColor
        effectView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
        effectView.layer?.shadowOpacity = 1
        effectView.layer?.shadowRadius = 22
        effectView.layer?.shadowOffset = CGSize(width: 0, height: -6)

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.alignment = .center
        textField.font = .systemFont(ofSize: 20, weight: .semibold)
        textField.textColor = NSColor.white.withAlphaComponent(0.97)
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 2

        effectView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 28),
            textField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -28),
            textField.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 22),
            textField.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -22)
        ])

        window.contentView = effectView
        self.window = window
        self.textField = textField
        return window
    }

    private func bannerFrame(in visibleFrame: NSRect) -> NSRect {
        let width = min(420, visibleFrame.width - 56)
        let height: CGFloat = 96
        return NSRect(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.midY - (height / 2),
            width: width,
            height: height
        )
    }
}
