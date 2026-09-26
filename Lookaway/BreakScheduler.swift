import AppKit
import Combine
import EventKit
import Foundation
import IOKit.ps

@MainActor
final class BreakScheduler: ObservableObject {
    // MARK: - Published settings

    @Published var intervalOption: IntervalOption {
        didSet {
            persist(intervalOption.rawValue, key: Keys.interval)
            if !isApplyingPreset {
                selectedSetupPreset = nil
                persistSelectedSetupPreset()
                protocolPreset = .custom
            }
            scheduleNextBreak(from: .now)
        }
    }

    @Published var restDurationOption: RestDurationOption {
        didSet {
            persist(restDurationOption.rawValue, key: Keys.restDuration)
            if !isApplyingPreset {
                selectedSetupPreset = nil
                persistSelectedSetupPreset()
                protocolPreset = .custom
            }
        }
    }

    @Published var protocolPreset: BreakProtocolPreset {
        didSet {
            persist(protocolPreset.rawValue, key: Keys.protocolPreset)
            if !isApplyingPreset {
                switch protocolPreset {
                case .eyeCare202020:
                    selectedSetupPreset = .eyeCare202020
                case .pomodoro:
                    selectedSetupPreset = .pomodoro
                case .custom:
                    selectedSetupPreset = nil
                }
                persistSelectedSetupPreset()
            }
            applyProtocolIfNeeded()
            refreshDerivedState(now: .now)
        }
    }

    @Published var breakStyle: BreakStyle {
        didSet {
            persist(breakStyle.rawValue, key: Keys.breakStyle)
            if !isApplyingPreset {
                selectedSetupPreset = nil
                persistSelectedSetupPreset()
                protocolPreset = .custom
            }
        }
    }

    @Published var enablePreAlert: Bool {
        didSet { persist(enablePreAlert, key: Keys.preAlertEnabled) }
    }

    @Published var preAlertPresentation: PreAlertPresentation {
        didSet {
            persist(preAlertPresentation.rawValue, key: Keys.preAlertPresentation)
            if preAlertPresentation == .notification {
                notificationManager.requestAuthorization()
            }
            Task { @MainActor [weak self] in
                self?.clearPreAlertUI()
                self?.refreshDerivedState(now: .now)
            }
        }
    }

    @Published var restOverlayDimAmount: Double {
        didSet { persist(restOverlayDimAmount, key: Keys.dimAmount) }
    }

    @Published var showPerDisplayLabel: Bool {
        didSet { persist(showPerDisplayLabel, key: Keys.showDisplayLabel) }
    }

    @Published var manualPauseEnabled = false {
        didSet {
            manualPauseResumeAt = nil
            inputDeferralStartedAt = nil
            refreshPauseState()
            rearmTicker()
        }
    }

    @Published var manualPauseResumeAt: Date? {
        didSet {
            if let manualPauseResumeAt {
                persist(manualPauseResumeAt, key: Keys.manualPauseResumeAt)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.manualPauseResumeAt)
            }
            rearmTicker()
        }
    }

    @Published var longBreaksEnabled: Bool {
        didSet {
            persist(longBreaksEnabled, key: Keys.longBreaksEnabled)
            if !longBreaksEnabled { completedShortBreaks = 0 }
        }
    }
    @Published var longBreakEvery: Int {
        didSet { persist(longBreakEvery, key: Keys.longBreakEvery) }
    }
    @Published var longBreakDuration: LongBreakDuration {
        didSet { persist(longBreakDuration.rawValue, key: Keys.longBreakDuration) }
    }
    @Published var completedShortBreaks: Int {
        didSet { persist(completedShortBreaks, key: Keys.completedShortBreaks) }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { persist(hasCompletedOnboarding, key: Keys.hasCompletedOnboarding) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            persist(launchAtLogin, key: Keys.launchAtLogin)
            do {
                try LaunchAtLoginManager.setEnabled(launchAtLogin)
                settingsError = nil
            } catch {
                settingsError = "Launch at login failed: \(error.localizedDescription)"
            }
        }
    }

    @Published var scheduleEnabled: Bool {
        didSet {
            persist(scheduleEnabled, key: Keys.scheduleEnabled)
            refreshDerivedState(now: .now)
        }
    }

    @Published var scheduleStartHour: Int {
        didSet {
            persist(scheduleStartHour, key: Keys.scheduleStartHour)
            refreshDerivedState(now: .now)
        }
    }

    @Published var scheduleEndHour: Int {
        didSet {
            persist(scheduleEndHour, key: Keys.scheduleEndHour)
            refreshDerivedState(now: .now)
        }
    }

    @Published var activeWeekdays: Set<Int> {
        didSet {
            persist(Array(activeWeekdays).sorted(), key: Keys.activeWeekdays)
            refreshDerivedState(now: .now)
        }
    }

    @Published var focusBlocksEnabled: Bool {
        didSet {
            persist(focusBlocksEnabled, key: Keys.focusBlocksEnabled)
            refreshDerivedState(now: .now)
        }
    }

    @Published var focusBlockWindows: [FocusBlockWindow] {
        didSet {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(focusBlockWindows) {
                UserDefaults.standard.set(data, forKey: Keys.focusBlockWindows)
            }
            refreshDerivedState(now: .now)
        }
    }

    @Published var pauseOnSystemIdle: Bool {
        didSet { persist(pauseOnSystemIdle, key: Keys.pauseOnSystemIdle) }
    }

    @Published var pauseWhenIdle: Bool {
        didSet {
            persist(pauseWhenIdle, key: Keys.pauseWhenIdle)
            if !pauseWhenIdle {
                setAutoPause("idle", active: false)
            } else {
                checkIdleState()
            }
        }
    }

    @Published var delayDuringMeetings: Bool {
        didSet {
            persist(delayDuringMeetings, key: Keys.delayDuringMeetings)
            if delayDuringMeetings, meetingEventsProvider == nil {
                requestCalendarAccessIfNeeded()
            }
            refreshDerivedState(now: .now)
        }
    }

    @Published var onlyAcceptedCalendarEvents: Bool {
        didSet {
            persist(onlyAcceptedCalendarEvents, key: Keys.onlyAcceptedCalendarEvents)
            meetingCacheTimestamp = .distantPast
            refreshDerivedState(now: .now)
        }
    }

    @Published var deviceAwareModeEnabled: Bool {
        didSet {
            persist(deviceAwareModeEnabled, key: Keys.deviceAwareModeEnabled)
            refreshContextSnapshot()
            refreshDerivedState(now: .now)
        }
    }

    @Published var reduceIntensityOnBattery: Bool {
        didSet {
            persist(reduceIntensityOnBattery, key: Keys.reduceIntensityOnBattery)
            refreshContextSnapshot()
            refreshDerivedState(now: .now)
        }
    }

    @Published var menuBarMode: MenuBarMode {
        didSet {
            persist(menuBarMode.rawValue, key: Keys.menuBarMode)
            refreshDerivedState(now: .now)
        }
    }

    @Published var customPrompts: [String: [String]] {
        didSet {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(customPrompts) {
                UserDefaults.standard.set(data, forKey: Keys.customPrompts)
            }
        }
    }

    @Published var appAwarePauseEnabled: Bool {
        didSet {
            persist(appAwarePauseEnabled, key: Keys.appAwarePauseEnabled)
            if !appAwarePauseEnabled {
                setAutoPause("frontmostApp", active: false)
            } else {
                checkFrontmostApp()
            }
        }
    }

    @Published var pauseAppBundleIDs: [String] {
        didSet {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(pauseAppBundleIDs) {
                UserDefaults.standard.set(data, forKey: Keys.pauseAppBundleIDs)
            }
            if appAwarePauseEnabled { checkFrontmostApp() }
        }
    }

    @Published var pauseWhenCameraActive: Bool {
        didSet {
            persist(pauseWhenCameraActive, key: Keys.pauseWhenCameraActive)
            refreshWebcamMonitoring()
        }
    }

    @Published var adaptiveIntervalsEnabled: Bool {
        didSet {
            persist(adaptiveIntervalsEnabled, key: Keys.adaptiveIntervalsEnabled)
            refreshDerivedState(now: .now)
        }
    }

    @Published var overlayBackgroundStyle: OverlayBackgroundStyle {
        didSet { persist(overlayBackgroundStyle.rawValue, key: Keys.overlayBackgroundStyle) }
    }

    @Published var overlayTheme: OverlayTheme {
        didSet { persist(overlayTheme.rawValue, key: Keys.overlayTheme) }
    }

    // Security-scoped bookmark for a user-chosen wallpaper image; nil means
    // use the desktop picture (or the blue fallback if that is unreadable).
    @Published var wallpaperBookmark: Data? {
        didSet {
            if let wallpaperBookmark {
                UserDefaults.standard.set(wallpaperBookmark, forKey: Keys.wallpaperBookmark)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.wallpaperBookmark)
            }
        }
    }

    // MARK: - Published read-only state
    // Note: these are set from extension files, so private(set) cannot be used here.

    @Published var selectedSetupPreset: SetupPreset?
    @Published var nextBreakDate: Date {
        didSet { rearmTicker() }
    }
    @Published var isPaused = false
    @Published var isShowingBreak = false
    @Published var isInPreAlert = false
    @Published var settingsError: String?
    @Published var calendarStatusText = "Calendar not connected"
    @Published var calendarDetailText = "LookAway can delay breaks while you are in active meetings."
    @Published var deviceContextText = "Display context: unknown"
    @Published var powerContextText = "Power context: unknown"
    @Published var extendedStats: ExtendedStatsSnapshot
    @Published var showBreakCompletionBadge = false
    @Published var timeRemainingMinutesText = "0 min"
    @Published var menuBarCountdownText = "0m"
    @Published var menuBarStatusText = "Working"
    @Published var currentStateTitle = "Working"
    @Published var currentStateExplanation = ""
    @Published var nextBreakClockText = "--"
    @Published var currentBlockerText = "No blocker"
    @Published var currentMeetingText = "No active meeting"
    @Published var lastBreakReasonText = "App launched"
    @Published var menuBarProgressFraction: Double = 0

    // MARK: - Private state

    let overlayController = RestOverlayController()
    let mediaPlaybackController: MediaPlaybackController
    let centerPreBreakBannerController = CenterPreBreakBannerController()
    let breakCompletionBadgeController = BreakCompletionBadgeController()
    let notificationManager = NotificationManager()
    let webcamMonitor = WebcamActivityMonitor()
    let eventStore = EKEventStore()
    var ticker: Timer?
    var tickerActive = false
    var isApplyingPreset = false
    var preAlertTriggeredThisCycle = false
    var isRunningBreakTest = false
    var isShowingTestBreak = false
    var savedNextBreakDateForTest: Date?
    var shownCenterBannerMilestones: Set<Int> = []
    var autoPauseReasons: Set<String> = []
    var dayStats: [String: DailyCounters]
    var workspaceObservers: [Any] = []
    var notificationObservers: [Any] = []
    var meetingCacheTimestamp: Date = .distantPast
    var cachedMeetingEvents: [EKEvent] = []
    var lastContextRefresh: Date = .distantPast
    let shortBlockThreshold: TimeInterval = 10 * 60
    var activitySamples: [Bool] = []
    var idleSecondsProvider: (() -> TimeInterval)?
    // Interval captured when the cycle was scheduled, so the menu bar ring
    // denominator stays fixed even if the adaptive multiplier shifts mid-cycle.
    var currentCycleIntervalSeconds: TimeInterval = 0
    var activeBreakID: UUID?
    var activeBreakStartedAt: Date?
    var activeBreakDeadline: Date?
    var activeBreakDuration: TimeInterval = 0
    var activeBreakIsLong = false
    var activeBreakCountsTowardCycle = false
    var activeBreakStyle: BreakStyle = .eyes
    var inputDeferralStartedAt: Date?
    var inputGapSecondsProvider: (() -> TimeInterval)?
    var mouseButtonDownProvider: (() -> Bool)?
    var workSessionStartedAt: Date?
    var lastStatsRefresh: Date = .distantPast
    var systemSuspensions: Set<String> = []
    var meetingEventsProvider: ((Date) -> [EKEvent])?

    // MARK: - Init / deinit

    init(now: Date = .now, mediaPlaybackController: MediaPlaybackController? = nil) {
        self.mediaPlaybackController = mediaPlaybackController ?? MediaPlaybackController()
        let defaults = UserDefaults.standard
        let loadedInterval = IntervalOption(rawValue: defaults.integer(forKey: Keys.interval)) ?? .min25

        manualPauseResumeAt = defaults.object(forKey: Keys.manualPauseResumeAt) as? Date
        longBreaksEnabled = defaults.bool(forKey: Keys.longBreaksEnabled)
        let savedFrequency = defaults.object(forKey: Keys.longBreakEvery) as? Int ?? 4
        longBreakEvery = (2...12).contains(savedFrequency) ? savedFrequency : 4
        longBreakDuration = LongBreakDuration(rawValue: defaults.integer(forKey: Keys.longBreakDuration)) ?? .min5
        completedShortBreaks = min(12, max(0, defaults.integer(forKey: Keys.completedShortBreaks)))
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        intervalOption = loadedInterval
        restDurationOption = RestDurationOption(rawValue: defaults.integer(forKey: Keys.restDuration)) ?? .sec20
        protocolPreset = BreakProtocolPreset(rawValue: defaults.string(forKey: Keys.protocolPreset) ?? "") ?? .custom
        breakStyle = BreakStyle(rawValue: defaults.string(forKey: Keys.breakStyle) ?? "") ?? .eyes
        enablePreAlert = defaults.object(forKey: Keys.preAlertEnabled) as? Bool ?? true
        let savedPreAlertPresentation = defaults.string(forKey: Keys.preAlertPresentation)
        preAlertPresentation = PreAlertPresentation(rawValue: savedPreAlertPresentation ?? "") ?? .centerBanner
        restOverlayDimAmount = defaults.object(forKey: Keys.dimAmount) as? Double ?? 0.65
        showPerDisplayLabel = defaults.object(forKey: Keys.showDisplayLabel) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? LaunchAtLoginManager.isEnabled()
        scheduleEnabled = defaults.object(forKey: Keys.scheduleEnabled) as? Bool ?? false
        scheduleStartHour = defaults.object(forKey: Keys.scheduleStartHour) as? Int ?? 9
        scheduleEndHour = defaults.object(forKey: Keys.scheduleEndHour) as? Int ?? 18
        let savedDays = defaults.array(forKey: Keys.activeWeekdays) as? [Int]
        activeWeekdays = Set(savedDays ?? [2, 3, 4, 5, 6])
        focusBlocksEnabled = defaults.object(forKey: Keys.focusBlocksEnabled) as? Bool ?? false

        // Load focus block windows (with migration from legacy single-window format)
        if let data = defaults.data(forKey: Keys.focusBlockWindows),
           let windows = try? JSONDecoder().decode([FocusBlockWindow].self, from: data) {
            focusBlockWindows = windows
        } else {
            let legacyStart = defaults.object(forKey: Keys.focusStartHour) as? Int ?? 10
            let legacyEnd = defaults.object(forKey: Keys.focusEndHour) as? Int ?? 12
            let legacyDays = Set(defaults.array(forKey: Keys.focusWeekdays) as? [Int] ?? [2, 3, 4, 5, 6])
            focusBlockWindows = [FocusBlockWindow(name: "Focus Time", startHour: legacyStart, endHour: legacyEnd, weekdays: legacyDays)]
        }

        pauseOnSystemIdle = defaults.object(forKey: Keys.pauseOnSystemIdle) as? Bool ?? true
        pauseWhenIdle = defaults.object(forKey: Keys.pauseWhenIdle) as? Bool ?? true
        delayDuringMeetings = defaults.object(forKey: Keys.delayDuringMeetings) as? Bool ?? false
        onlyAcceptedCalendarEvents = defaults.object(forKey: Keys.onlyAcceptedCalendarEvents) as? Bool ?? true
        deviceAwareModeEnabled = defaults.object(forKey: Keys.deviceAwareModeEnabled) as? Bool ?? true
        reduceIntensityOnBattery = defaults.object(forKey: Keys.reduceIntensityOnBattery) as? Bool ?? true
        menuBarMode = MenuBarMode(rawValue: defaults.string(forKey: Keys.menuBarMode) ?? "") ?? .iconAndMinutes
        selectedSetupPreset = SetupPreset(rawValue: defaults.string(forKey: Keys.selectedSetupPreset) ?? "")

        // Custom prompts
        if let data = defaults.data(forKey: Keys.customPrompts),
           let prompts = try? JSONDecoder().decode([String: [String]].self, from: data) {
            customPrompts = prompts
        } else {
            customPrompts = [:]
        }

        // App-aware pausing
        appAwarePauseEnabled = defaults.object(forKey: Keys.appAwarePauseEnabled) as? Bool ?? false
        if let data = defaults.data(forKey: Keys.pauseAppBundleIDs),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            pauseAppBundleIDs = ids
        } else {
            pauseAppBundleIDs = []
        }

        // Webcam detection
        pauseWhenCameraActive = defaults.object(forKey: Keys.pauseWhenCameraActive) as? Bool ?? false

        // Adaptive intervals
        adaptiveIntervalsEnabled = defaults.object(forKey: Keys.adaptiveIntervalsEnabled) as? Bool ?? false

        // Overlay background
        overlayBackgroundStyle = OverlayBackgroundStyle(rawValue: defaults.string(forKey: Keys.overlayBackgroundStyle) ?? "") ?? .aurora
        overlayTheme = OverlayTheme(rawValue: defaults.string(forKey: Keys.overlayTheme) ?? "") ?? .auto
        wallpaperBookmark = defaults.data(forKey: Keys.wallpaperBookmark)

        dayStats = Self.loadStats()
        extendedStats = .empty
        nextBreakDate = now.addingTimeInterval(loadedInterval.seconds)
        currentCycleIntervalSeconds = loadedInterval.seconds

        // Persist migrated focus block windows if not previously saved
        if defaults.data(forKey: Keys.focusBlockWindows) == nil {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(focusBlockWindows) {
                defaults.set(data, forKey: Keys.focusBlockWindows)
            }
        }

        restoreTimedPause(now: now)
        applyProtocolIfNeeded()
        refreshStats()
        refreshContextSnapshot()
        refreshCalendarStatus(now: now)
        refreshDerivedState(now: now)
        updateWorkSession(now: now)
        startTicker()
        setupWorkspaceObservers()
        setupSystemObservers()
        if preAlertPresentation == .notification { notificationManager.requestAuthorization() }
        if pauseWhenCameraActive { webcamMonitor.startMonitoring(onActiveChanged: { [weak self] isActive in
            self?.setAutoPause("webcam", active: isActive)
        }) }
        if appAwarePauseEnabled { checkFrontmostApp() }
    }

    deinit {
        ticker?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

}
