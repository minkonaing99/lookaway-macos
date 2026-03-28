# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LookAway is a macOS menu bar app that runs timed screen break reminders. It uses a 1Hz timer-driven state machine to schedule breaks, show pre-alerts, and display full-screen overlays across all connected displays.

## Build & Run

This is a pure Xcode project — no Swift Package Manager, no Makefile.

```bash
# Build (release)
xcodebuild -project Lookaway.xcodeproj -scheme Lookaway -configuration Release build

# Build (debug)
xcodebuild -project Lookaway.xcodeproj -scheme Lookaway -configuration Debug build

# Run tests
xcodebuild test -project Lookaway.xcodeproj -scheme Lookaway -destination 'platform=macOS'
```

## Architecture

The app is a **SwiftUI + AppKit hybrid** on a single `@MainActor` thread. All state lives in `BreakScheduler` (an observable class); views observe and render it.

### Core Data Flow

```
LookawayApp (@main)
 └── MenuBarExtra → MenuBarContentView    (menu bar dropdown + all preferences UI)
 └── Settings Scene
 └── BreakScheduler (1Hz ticker)
      ├── RestOverlayController              (NSWindow per display, hosts RestOverlayView)
      ├── PointerCountdownOverlayController  (floating label tracking cursor, 30fps)
      ├── CenterPreBreakBannerController     (brief center-screen banner)
      ├── BreakCompletionBadgeController     (floating badge after break completes)
      ├── NotificationManager                (UNUserNotificationCenter wrapper)
      └── WebcamActivityMonitor              (KVO on AVCaptureDevice.isInUseByAnotherApplication)
```

### BreakScheduler (`Lookaway/BreakScheduler.swift`)

The central `@MainActor` observable class. It owns:

- **Tick loop** (`tick()`, 1Hz): evaluates blockers in order (paused → outside schedule → focus block → meeting), then counts down to `nextBreakDate`, triggers pre-alert at ≤30s, calls `showBreak()` at 0s.
- **Soft rescheduling**: blockers <10 min postpone the break to just after they end; blockers ≥10 min restart a fresh cycle.
- **Persistence**: every setting has a `UserDefaults` key under `lookaway.*`; `didSet` observers write immediately — no save button.
- **System integration**: `EKEventStore` for calendar (1-hour cache), `IOKit.ps` for power state, `NSWorkspace` notifications for lock/sleep/app activation, `SMAppService` for launch-at-login, `AVCaptureDevice` KVO for webcam detection.

### Overlay Controllers

- `RestOverlayController` — creates a borderless `NSWindow` at `.screenSaver` level on every `NSScreen`; hosts `RestOverlayView` (SwiftUI).
- `PointerCountdownOverlayController` — floating `NSPanel` with a countdown label that follows the mouse at 30fps using low-pass smoothing (factor 0.28).
- `CenterPreBreakBannerController` — `NSVisualEffectView`-backed banner, fades in/out over 0.3s, auto-dismisses after 1.8s.
- `BreakCompletionBadgeController` — `NSPanel` near top-center of screen, shows "✓ Break done", fades in/out, auto-dismisses after 1.8s.

### Key Constants

| Thing | Value |
|---|---|
| Pre-alert window | 30 seconds |
| Short blocker threshold | 10 minutes |
| Pointer tracking rate | 30fps (33ms) |
| Banner display duration | 1.8s |
| Max focus block windows | 10 |
| Main ticker | 1 second |

### Persistence Keys

All UserDefaults keys are prefixed `lookaway.*` and are defined as string constants in `BreakSchedulerTypes.swift` (`Keys` enum). Two legacy migrations on first load:
- `pointerCountdownEnabled` → new key
- `focusStartHour` / `focusEndHour` / `focusWeekdays` → `focusBlockWindows` JSON array

### Entitlements

The app is sandboxed. Notable entitlements in `Lookaway/Lookaway.entitlements`:
- `com.apple.security.personal-information.calendars` — EventKit access
- `com.apple.security.device.camera` — AVCaptureDevice webcam detection
- `com.apple.security.temporary-exception.shared-preference.read-write: ["Merxy.Lookaway"]` — legacy shared prefs

## Key Files

`BreakScheduler` is split across multiple files:

| File | Purpose |
|---|---|
| `Lookaway/BreakScheduler.swift` | Class declaration, all `@Published` properties, `init`, `deinit` |
| `Lookaway/BreakSchedulerTypes.swift` | All nested enums/structs (`IntervalOption`, `BreakStyle`, `FocusBlockWindow`, `RuntimeBlocker`, `ExtendedStatsSnapshot`, `DayChartEntry`, etc.), `DailyCounters`, `Keys` constants |
| `Lookaway/BreakScheduler+Actions.swift` | All public action methods (`triggerBreakNow`, `snooze`, `skipOnce`, `applySetupPreset`, `updatePrompts`, `addFocusBlockWindow`, `removeFocusBlockWindow`, `updateFocusBlockWindow`, `addPauseApp`, `removePauseApp`, etc.) |
| `Lookaway/BreakScheduler+Persistence.swift` | `persist(_:key:)`, `persistSelectedSetupPreset()` |
| `Lookaway/BreakScheduler+Scheduling.swift` | `tick()`, `showBreak()`, `scheduleNextBreak()`, effective interval/dim/pre-alert computed vars |
| `Lookaway/BreakScheduler+TimeWindows.swift` | `runtimeBlocker()`, `isWithinHours()`, `softlyRescheduleIfNeeded()`, window start/end helpers; iterates `focusBlockWindows` array |
| `Lookaway/BreakScheduler+Calendar.swift` | EventKit access, `refreshCalendarStatus()`, `currentBlockingMeeting()` |
| `Lookaway/BreakScheduler+Stats.swift` | `recordStat()`, `refreshStats()` (delegates to `computeExtendedStats()`), `loadStats()`, `saveStats()` |
| `Lookaway/BreakScheduler+StatsComputed.swift` | `computeExtendedStats()` — streak, completion rate, best day, chart data |
| `Lookaway/BreakScheduler+SystemMonitor.swift` | Workspace/system observers, pause state, context snapshot, power/display helpers; app-aware pause (`checkFrontmostApp()`), webcam monitoring (`refreshWebcamMonitoring()`) |
| `Lookaway/BreakScheduler+DerivedState.swift` | `refreshDerivedState()`, all UI label updates, summary text, date formatters |
| `Lookaway/LookawayApp.swift` | App entry point; menu bar label/icon computation; `showBreakCompletionBadge` drives checkmark icon |
| `Lookaway/MenuBarContentView.swift` | Menu bar dropdown UI and full preferences interface (Stats, Breaks, Focus, Notifications, etc.) |
| `Lookaway/RestOverlayView.swift` | SwiftUI break overlay (gradient, countdown, prompts); shows `BreathingGuideView` for `.breathing` style |
| `Lookaway/RestOverlayController.swift` | Multi-display NSWindow management for break overlay; passes `customPrompts` through |
| `Lookaway/PointerCountdownOverlayController.swift` | Cursor-tracking pre-alert label |
| `Lookaway/CenterPreBreakBannerController.swift` | Center-screen pre-alert banner |
| `Lookaway/BreakCompletionBadgeController.swift` | Post-break floating badge ("✓ Break done") |
| `Lookaway/BreathingGuideView.swift` | Animated expanding/contracting circle for breathing break style (inhale 4s → hold 4s → exhale 6s) |
| `Lookaway/NotificationManager.swift` | `UNUserNotificationCenter` wrapper for pre-alert notifications (no sound) |
| `Lookaway/WebcamActivityMonitor.swift` | KVO on `AVCaptureDevice.isInUseByAnotherApplication`; triggers auto-pause |
| `Lookaway/StatsDashboardView.swift` | Swift Charts bar chart (completed/skipped/snoozed per day), streak, completion %, best day |
| `Lookaway/CustomPromptsEditorView.swift` | Per-style prompt editor; falls back to `BreakStyle.defaultPrompts` |
| `Lookaway/FocusBlockWindowEditorView.swift` | Per-window focus block editor (name, start/end hour, weekday chips) |
| `Lookaway/AppAwarePauseView.swift` | Configure bundle IDs that trigger auto-pause; "Add from Running Apps" picker |
| `LookawayTests/TimeWindowTests.swift` | Unit tests for schedule/time-window/blocker logic |

## Implemented Features (v2.0.1)

All 8 features from the v2.0.1 milestone are complete:

1. **Stats Dashboard** — `StatsDashboardView` with Swift Charts bar chart, streak, completion rate, best day of week
2. **Custom Break Prompts** — `CustomPromptsEditorView`; per-style prompts stored in `customPrompts: [String: [String]]`; falls back to `BreakStyle.defaultPrompts`
3. **Notification Center Integration** — `NotificationManager` wraps `UNUserNotificationCenter`; `.notification` pre-alert presentation type; no sound
4. **Multiple Focus Block Windows** — `FocusBlockWindow` Codable struct; `focusBlockWindows: [FocusBlockWindow]` replaces old single-window properties; migrates legacy keys on first launch
5. **Guided Breathing Animation** — `BreathingGuideView` with `Task`-driven phase cycle (inhale → hold → exhale); cancelled `onDisappear`
6. **Break Completion Feedback** — `BreakCompletionBadgeController` floating panel + `showBreakCompletionBadge` flips menu bar icon to checkmark for 2s
7. **App-Aware Pausing** — `NSWorkspace.didActivateApplicationNotification` observer; `checkFrontmostApp()` compares against `pauseAppBundleIDs`
8. **Webcam Active Detection** — `WebcamActivityMonitor` KVO on `AVCaptureDevice`; triggers `setAutoPause("webcam", active:)`

## Constraints

- No sound/audio of any kind
- macOS 13.0 minimum deployment
- No external Swift package dependencies — only Apple system frameworks
- All UI mutations on `@MainActor`; async work uses `Task { @MainActor in … }`
- Files stay under 800 lines
- Immutable patterns: structs with value semantics, `let` over `var`

## Platform Notes

- `PBXFileSystemSynchronizedRootGroup` — new `.swift` files dropped into `Lookaway/` are auto-included in the build target; no pbxproj edits needed
- `GENERATE_INFOPLIST_FILE = YES` — privacy strings added via `INFOPLIST_KEY_*` build settings (e.g. `INFOPLIST_KEY_NSCameraUsageDescription`)
