import AppKit
import ImageIO
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
        backgroundStyle: BreakScheduler.OverlayBackgroundStyle,
        theme: BreakScheduler.OverlayTheme,
        wallpaperBookmark: Data?,
        reduceMotion: Bool,
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
            let wallpaper = backgroundStyle == .wallpaper
                ? wallpaperImage(for: screen, bookmark: wallpaperBookmark)
                : nil
            let view = RestOverlayView(
                restDuration: restDuration,
                style: style,
                dimAmount: dimAmount,
                displayName: displayName,
                customPrompts: customPrompts,
                backgroundStyle: backgroundStyle,
                theme: theme,
                wallpaper: wallpaper,
                reduceMotion: reduceMotion,
                onDismiss: onDismiss,
                onSkip: onSkip
            )

            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // User-chosen image only (security-scoped bookmark, sandbox-safe).
    // nil makes the view fall back to the blue aurora background.
    private func wallpaperImage(for screen: NSScreen, bookmark: Data?) -> NSImage? {
        guard let bookmark else { return nil }
        let maxPixelSize = max(screen.frame.width, screen.frame.height) / 2
        return bookmarkedImage(bookmark, maxPixelSize: maxPixelSize)
    }

    // Bookmark points at a file inside our own container, so no security scope.
    private func bookmarkedImage(_ bookmark: Data, maxPixelSize: CGFloat) -> NSImage? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return decodeThumbnail(url: url, maxPixelSize: maxPixelSize)
    }

    // Decodes a downsampled thumbnail — the 60pt blur destroys detail anyway,
    // so there is no reason to hold a full-resolution 5K bitmap per screen.
    private func decodeThumbnail(url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func hideOverlay() {
        for window in windows {
            window.contentView = nil  // releases NSHostingView + SwiftUI tree immediately
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}
