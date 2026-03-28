import AppKit
import SwiftUI

@MainActor
final class RestOverlayController {
    private var windows: [NSWindow] = []

    func showOverlay(
        restDuration: Int,
        style: BreakScheduler.BreakStyle,
        dimAmount: Double,
        showDisplayLabel: Bool,
        customPrompts: [String]?,
        onDismiss: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        hideOverlay()

        let screens = NSScreen.screens
        for screen in screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.hasShadow = false

            let displayName = showDisplayLabel ? (screen.localizedName) : nil
            let view = RestOverlayView(
                restDuration: restDuration,
                style: style,
                dimAmount: dimAmount,
                displayName: displayName,
                customPrompts: customPrompts,
                onDismiss: onDismiss,
                onSkip: onSkip
            )

            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func hideOverlay() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
