import AppKit

@MainActor
final class CenterPreBreakBannerController {
    private var window: NSWindow?
    private weak var textField: NSTextField?
    private var hideWorkItem: DispatchWorkItem?
    private var presentationID = UUID()
    private var isHiding = false

    func show(message: String) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        presentationID = UUID()
        isHiding = false
        let window = self.window ?? makeWindow(for: screen)
        let frame = bannerFrame(in: screen.visibleFrame)

        window.setFrame(frame, display: false)
        textField?.stringValue = message
        window.alphaValue = 0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
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

        guard let window, window.isVisible, !isHiding else { return }
        isHiding = true
        let hidingID = presentationID
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.presentationID == hidingID else { return }
                window.orderOut(nil)
                self.isHiding = false
            }
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
        window.hasShadow = true
        window.ignoresMouseEvents = true

        let content = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        let glass = NSGlassEffectView(frame: content.bounds)
        glass.style = .regular
        glass.cornerRadius = 28
        glass.contentView = content

        configureContent(content)
        window.contentView = glass
        self.window = window
        return window
    }

    private func configureContent(_ content: NSView) {
        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.alignment = .left
        textField.font = .systemFont(ofSize: 19, weight: .semibold)
        textField.textColor = .labelColor
        textField.lineBreakMode = .byWordWrapping
        textField.maximumNumberOfLines = 2

        let icon = NSImageView(image: NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil) ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        icon.contentTintColor = .labelColor
        let subtitle = NSTextField(labelWithString: "A moment to rest your eyes")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [textField, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 5
        labels.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(icon)
        content.addSubview(labels)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            icon.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 16),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            labels.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])

        self.textField = textField
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
