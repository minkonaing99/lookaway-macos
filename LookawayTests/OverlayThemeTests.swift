import Testing
import Foundation
@testable import Lookaway

@Suite("overlay theme resolution")
struct OverlayThemeResolutionTests {
    @Test func autoMorningIsForest() {
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 8) == .forest)
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 5) == .forest)
    }

    @Test func autoMiddayIsOcean() {
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 13) == .ocean)
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 11) == .ocean)
    }

    @Test func autoEveningIsSunset() {
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 19) == .sunset)
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 17) == .sunset)
    }

    @Test func autoNightIsMidnight() {
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 23) == .midnight)
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 21) == .midnight)
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 2) == .midnight)
        #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: 4) == .midnight)
    }

    @Test func concreteThemesPassThroughUnchanged() {
        for theme in BreakScheduler.OverlayTheme.allCases where theme != .auto {
            #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: theme, hour: 3) == theme)
        }
    }

    @Test func autoNeverResolvesToAuto() {
        for hour in 0..<24 {
            #expect(BreakScheduler.OverlayTheme.resolvedTheme(for: .auto, hour: hour) != .auto)
        }
    }
}

@Suite("wallpaper bookmark persistence")
struct WallpaperBookmarkPersistenceTests {
    @Test func setAndClearRoundTripsThroughDefaults() {
        let scheduler = BreakScheduler()
        let marker = Data([0x01, 0x02, 0x03])

        scheduler.wallpaperBookmark = marker
        #expect(UserDefaults.standard.data(forKey: BreakScheduler.Keys.wallpaperBookmark) == marker)

        scheduler.clearWallpaperImage()
        #expect(scheduler.wallpaperBookmark == nil)
        #expect(UserDefaults.standard.data(forKey: BreakScheduler.Keys.wallpaperBookmark) == nil)
    }

    @Test func loadedFromDefaultsOnInit() {
        let marker = Data([0x0A, 0x0B])
        UserDefaults.standard.set(marker, forKey: BreakScheduler.Keys.wallpaperBookmark)
        let scheduler = BreakScheduler()
        #expect(scheduler.wallpaperBookmark == marker)
        scheduler.wallpaperBookmark = nil
    }
}

@Suite("overlay palettes")
struct OverlayPaletteTests {
    @Test func everyThemeHasFullPalette() {
        for theme in BreakScheduler.OverlayTheme.allCases {
            let palette = theme.palette(hour: 13)
            #expect(palette.gradient.count == 3)
            #expect(palette.blobs.count >= 4)
        }
    }

    @Test func autoPaletteMatchesResolvedTheme() {
        let auto = BreakScheduler.OverlayTheme.auto.palette(hour: 23)
        let midnight = BreakScheduler.OverlayTheme.midnight.palette(hour: 23)
        #expect(auto.gradient == midnight.gradient)
    }
}
