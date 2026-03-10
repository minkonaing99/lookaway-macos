import AppKit
import SwiftUI

struct PreferencesWindowChromeConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.attach(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                context.coordinator.attach(to: window)
            }
        }
    }

    final class Coordinator {
        private weak var window: NSWindow?

        func attach(to window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            configure(window)
        }

        private func configure(_ window: NSWindow) {
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = false
        }
    }
}
