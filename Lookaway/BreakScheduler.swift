import AppKit
import Combine
import EventKit
import Foundation
import IOKit.ps

@MainActor
final class BreakScheduler: ObservableObject {
    enum IntervalOption: Int, CaseIterable, Identifiable {
        case min20 = 20
        case min25 = 25
        case min30 = 30

        var id: Int { rawValue }
        var title: String { "\(rawValue) min" }
        var seconds: TimeInterval { TimeInterval(rawValue * 60) }
    }

    enum RestDurationOption: Int, CaseIterable, Identifiable {
        case sec10 = 10
        case sec20 = 20
        case sec30 = 30
        case min5 = 300

        var id: Int { rawValue }
        var title: String {
            rawValue >= 60 ? "\(rawValue / 60) min" : "\(rawValue) sec"
        }
    }

    enum BreakProtocolPreset: String, CaseIterable, Identifiable {
        case eyeCare202020
        case pomodoro
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .eyeCare202020: return "20-20-20"
            case .pomodoro: return "Pomodoro"
            case .custom: return "Custom"
            }
        }
    }

    enum SetupPreset: String, CaseIterable, Identifiable {
        case gentle
        case eyeCare202020
        case pomodoro
        case deepWork

        var id: String { rawValue }

        var title: String {
            switch self {
            case .gentle: return "Gentle"
            case .eyeCare202020: return "20-20-20"
            case .pomodoro: return "Pomodoro"
            case .deepWork: return "Deep Work"
            }
        }

        var subtitle: String {
            switch self {
            case .gentle: return "30 min work, 20 sec reset"
            case .eyeCare202020: return "20 min work, 20 sec eye rest"
            case .pomodoro: return "25 min focus, 5 min reset"
            case .deepWork: return "30 min deep work, 30 sec stretch"
            }
        }
    }

    enum BreakStyle: String, CaseIterable, Identifiable {
        case eyes
        case breathing
        case stretch
        case blink
        case hydration

        var id: String { rawValue }

        var title: String {
            switch self {
            case .eyes: return "Coffee Reset"
            case .breathing: return "Breathing"
            case .stretch: return "Stretch"
            case .blink: return "Blink"
            case .hydration: return "Hydration"
            }
        }
    }

    enum Weekday: Int, CaseIterable, Identifiable {
        case sunday = 1
        case monday = 2
        case tuesday = 3
        case wednesday = 4
        case thursday = 5
        case friday = 6
        case saturday = 7

        var id: Int { rawValue }

        var shortTitle: String {
            switch self {
            case .sunday: return "Sun"
            case .monday: return "Mon"
            case .tuesday: return "Tue"
            case .wednesday: return "Wed"
            case .thursday: return "Thu"
            case .friday: return "Fri"
            case .saturday: return "Sat"
            }
        }
    }

    enum MenuBarMode: String, CaseIterable, Identifiable {
        case iconOnly
        case iconAndMinutes
        case iconAndStatus

        var id: String { rawValue }

        var title: String {
            switch self {
            case .iconOnly: return "Icon only"
            case .iconAndMinutes: return "Icon + minutes"
            case .iconAndStatus: return "Icon + status"
            }
        }
    }

    struct StatsSnapshot {
        let dailyCompleted: Int
        let dailySkipped: Int
        let dailySnoozed: Int
        let weeklyCompleted: Int
        let weeklySkipped: Int
        let weeklySnoozed: Int
    }

    private struct DailyCounters: Codable {
        var completed: Int = 0
        var skipped: Int = 0
        var snoozed: Int = 0
    }

    private enum RuntimeBlocker {
        case none
        case paused
        case outsideSchedule(nextStart: Date?)
        case focus(until: Date?)
        case meeting(until: Date?, title: String?)
    }

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

    @Published var showPointerCountdown: Bool {
        didSet {
            persist(showPointerCountdown, key: Keys.pointerCountdownEnabled)
            if !showPointerCountdown {
                pointerCountdownController.hide()
            }
            refreshDerivedState(now: .now)
        }
    }

    @Published var restOverlayDimAmount: Double {
        didSet { persist(restOverlayDimAmount, key: Keys.dimAmount) }
    }

    @Published var showPerDisplayLabel: Bool {
        didSet { persist(showPerDisplayLabel, key: Keys.showDisplayLabel) }
    }

    @Published var manualPauseEnabled = false {
        didSet { refreshPauseState() }
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

    @Published var focusStartHour: Int {
        didSet {
            persist(focusStartHour, key: Keys.focusStartHour)
            refreshDerivedState(now: .now)
        }
    }

    @Published var focusEndHour: Int {
        didSet {
            persist(focusEndHour, key: Keys.focusEndHour)
            refreshDerivedState(now: .now)
        }
    }

    @Published var focusWeekdays: Set<Int> {
        didSet {
            persist(Array(focusWeekdays).sorted(), key: Keys.focusWeekdays)
            refreshDerivedState(now: .now)
        }
    }

    @Published var pauseOnSystemIdle: Bool {
        didSet { persist(pauseOnSystemIdle, key: Keys.pauseOnSystemIdle) }
    }

    @Published var delayDuringMeetings: Bool {
        didSet {
            persist(delayDuringMeetings, key: Keys.delayDuringMeetings)
            if delayDuringMeetings {
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

    @Published private(set) var selectedSetupPreset: SetupPreset?

    @Published private(set) var nextBreakDate: Date
    @Published private(set) var isPaused = false
    @Published private(set) var isShowingBreak = false
    @Published private(set) var isInPreAlert = false
    @Published private(set) var settingsError: String?
    @Published private(set) var calendarStatusText = "Calendar not connected"
    @Published private(set) var calendarDetailText = "LookAway can delay breaks while you are in active meetings."
    @Published private(set) var deviceContextText = "Display context: unknown"
    @Published private(set) var powerContextText = "Power context: unknown"
    @Published private(set) var stats: StatsSnapshot
    @Published private(set) var timeRemainingMinutesText = "0 min"
    @Published private(set) var menuBarCountdownText = "0m"
    @Published private(set) var menuBarStatusText = "Working"
    @Published private(set) var currentStateTitle = "Working"
    @Published private(set) var currentStateExplanation = ""
    @Published private(set) var nextBreakClockText = "--"
    @Published private(set) var currentBlockerText = "No blocker"
    @Published private(set) var currentMeetingText = "No active meeting"
    @Published private(set) var lastBreakReasonText = "App launched"

    private let overlayController = RestOverlayController()
    private let pointerCountdownController = PointerCountdownOverlayController()
    private let eventStore = EKEventStore()
    private var ticker: Timer?
    private var isApplyingPreset = false
    private var preAlertTriggeredThisCycle = false
    private var isRunningBreakTest = false
    private var isShowingTestBreak = false
    private var savedNextBreakDateForTest: Date?
    private var autoPauseReasons: Set<String> = []
    private var dayStats: [String: DailyCounters]
    private var workspaceObservers: [Any] = []
    private var notificationObservers: [Any] = []
    private var meetingCacheTimestamp: Date = .distantPast
    private var cachedMeetingEvent: EKEvent?
    private var lastContextRefresh: Date = .distantPast
    private let shortBlockThreshold: TimeInterval = 10 * 60

    private enum Keys {
        static let interval = "lookaway.interval"
        static let restDuration = "lookaway.restDuration"
        static let protocolPreset = "lookaway.protocolPreset"
        static let breakStyle = "lookaway.breakStyle"
        static let preAlertEnabled = "lookaway.preAlert"
        static let pointerCountdownEnabled = "lookaway.pointerCountdownEnabled"
        static let dimAmount = "lookaway.dimAmount"
        static let showDisplayLabel = "lookaway.displayLabel"
        static let launchAtLogin = "lookaway.launchAtLogin"
        static let scheduleEnabled = "lookaway.scheduleEnabled"
        static let scheduleStartHour = "lookaway.scheduleStartHour"
        static let scheduleEndHour = "lookaway.scheduleEndHour"
        static let activeWeekdays = "lookaway.activeWeekdays"
        static let focusBlocksEnabled = "lookaway.focusBlocksEnabled"
        static let focusStartHour = "lookaway.focusStartHour"
        static let focusEndHour = "lookaway.focusEndHour"
        static let focusWeekdays = "lookaway.focusWeekdays"
        static let pauseOnSystemIdle = "lookaway.pauseOnSystemIdle"
        static let delayDuringMeetings = "lookaway.delayDuringMeetings"
        static let onlyAcceptedCalendarEvents = "lookaway.onlyAcceptedCalendarEvents"
        static let deviceAwareModeEnabled = "lookaway.deviceAwareModeEnabled"
        static let reduceIntensityOnBattery = "lookaway.reduceIntensityOnBattery"
        static let menuBarMode = "lookaway.menuBarMode"
        static let selectedSetupPreset = "lookaway.selectedSetupPreset"
        static let dayStats = "lookaway.dayStats"
    }

    init(now: Date = .now) {
        let defaults = UserDefaults.standard
        let loadedInterval = IntervalOption(rawValue: defaults.integer(forKey: Keys.interval)) ?? .min25

        intervalOption = loadedInterval
        restDurationOption = RestDurationOption(rawValue: defaults.integer(forKey: Keys.restDuration)) ?? .sec20
        protocolPreset = BreakProtocolPreset(rawValue: defaults.string(forKey: Keys.protocolPreset) ?? "") ?? .custom
        breakStyle = BreakStyle(rawValue: defaults.string(forKey: Keys.breakStyle) ?? "") ?? .eyes
        enablePreAlert = defaults.object(forKey: Keys.preAlertEnabled) as? Bool ?? true
        showPointerCountdown = defaults.object(forKey: Keys.pointerCountdownEnabled) as? Bool ?? true
        restOverlayDimAmount = defaults.object(forKey: Keys.dimAmount) as? Double ?? 0.65
        showPerDisplayLabel = defaults.object(forKey: Keys.showDisplayLabel) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? LaunchAtLoginManager.isEnabled()
        scheduleEnabled = defaults.object(forKey: Keys.scheduleEnabled) as? Bool ?? false
        scheduleStartHour = defaults.object(forKey: Keys.scheduleStartHour) as? Int ?? 9
        scheduleEndHour = defaults.object(forKey: Keys.scheduleEndHour) as? Int ?? 18
        let savedDays = defaults.array(forKey: Keys.activeWeekdays) as? [Int]
        activeWeekdays = Set(savedDays ?? [2, 3, 4, 5, 6])
        focusBlocksEnabled = defaults.object(forKey: Keys.focusBlocksEnabled) as? Bool ?? false
        focusStartHour = defaults.object(forKey: Keys.focusStartHour) as? Int ?? 10
        focusEndHour = defaults.object(forKey: Keys.focusEndHour) as? Int ?? 12
        let savedFocusDays = defaults.array(forKey: Keys.focusWeekdays) as? [Int]
        focusWeekdays = Set(savedFocusDays ?? [2, 3, 4, 5, 6])
        pauseOnSystemIdle = defaults.object(forKey: Keys.pauseOnSystemIdle) as? Bool ?? true
        delayDuringMeetings = defaults.object(forKey: Keys.delayDuringMeetings) as? Bool ?? false
        onlyAcceptedCalendarEvents = defaults.object(forKey: Keys.onlyAcceptedCalendarEvents) as? Bool ?? true
        deviceAwareModeEnabled = defaults.object(forKey: Keys.deviceAwareModeEnabled) as? Bool ?? true
        reduceIntensityOnBattery = defaults.object(forKey: Keys.reduceIntensityOnBattery) as? Bool ?? true
        menuBarMode = MenuBarMode(rawValue: defaults.string(forKey: Keys.menuBarMode) ?? "") ?? .iconAndMinutes
        selectedSetupPreset = SetupPreset(rawValue: defaults.string(forKey: Keys.selectedSetupPreset) ?? "")

        dayStats = Self.loadStats()
        stats = StatsSnapshot(dailyCompleted: 0, dailySkipped: 0, dailySnoozed: 0, weeklyCompleted: 0, weeklySkipped: 0, weeklySnoozed: 0)
        nextBreakDate = now.addingTimeInterval(loadedInterval.seconds)

        applyProtocolIfNeeded()
        refreshStats()
        refreshContextSnapshot()
        refreshCalendarStatus(now: now)
        refreshDerivedState(now: now)
        startTicker()
        setupWorkspaceObservers()
        setupSystemObservers()
        if delayDuringMeetings { requestCalendarAccessIfNeeded() }
    }

    deinit {
        ticker?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func toggleWeekday(_ day: Weekday) {
        if activeWeekdays.contains(day.rawValue) {
            activeWeekdays.remove(day.rawValue)
        } else {
            activeWeekdays.insert(day.rawValue)
        }
    }

    func toggleFocusWeekday(_ day: Weekday) {
        if focusWeekdays.contains(day.rawValue) {
            focusWeekdays.remove(day.rawValue)
        } else {
            focusWeekdays.insert(day.rawValue)
        }
    }

    func pauseOrResume() {
        manualPauseEnabled.toggle()
    }

    func triggerBreakNow() {
        lastBreakReasonText = "Break started manually"
        showBreak()
    }

    func runBreakTest() {
        guard !isShowingBreak else { return }

        if savedNextBreakDateForTest == nil {
            savedNextBreakDateForTest = nextBreakDate
        }

        isRunningBreakTest = true
        isShowingTestBreak = false
        preAlertTriggeredThisCycle = false
        lastBreakReasonText = "Test countdown started"
        nextBreakDate = .now.addingTimeInterval(10)
        refreshDerivedState(now: .now)
    }

    func snooze(minutes: Int) {
        if isShowingBreak {
            overlayController.hideOverlay()
            isShowingBreak = false
            recordStat(\.snoozed)
        }

        nextBreakDate = .now.addingTimeInterval(TimeInterval(minutes * 60))
        preAlertTriggeredThisCycle = false
        lastBreakReasonText = "Break snoozed by \(minutes) min"
        refreshDerivedState(now: .now)
        refreshStats()
    }

    func skipOnce() {
        if isShowingBreak {
            overlayController.hideOverlay()
            isShowingBreak = false
        }

        if isShowingTestBreak {
            isShowingTestBreak = false
            finishBreakTest()
            return
        }

        recordStat(\.skipped)
        lastBreakReasonText = "Break skipped"
        scheduleNextBreak(from: .now)
        refreshStats()
    }

    func dismissBreakCompleted() {
        guard isShowingBreak else { return }
        isShowingBreak = false
        overlayController.hideOverlay()

        if isShowingTestBreak {
            isShowingTestBreak = false
            finishBreakTest()
            return
        }

        recordStat(\.completed)
        lastBreakReasonText = "Break completed"
        scheduleNextBreak(from: .now)
        refreshStats()
    }

    func clearStatsHistory() {
        dayStats = [:]
        UserDefaults.standard.removeObject(forKey: Keys.dayStats)
        refreshStats()
        lastBreakReasonText = "Local stats cleared"
    }

    func resetAllLocalData() {
        let defaults = UserDefaults.standard
        let allKeys = [
            Keys.interval,
            Keys.restDuration,
            Keys.protocolPreset,
            Keys.breakStyle,
            Keys.preAlertEnabled,
            Keys.pointerCountdownEnabled,
            Keys.dimAmount,
            Keys.showDisplayLabel,
            Keys.scheduleEnabled,
            Keys.scheduleStartHour,
            Keys.scheduleEndHour,
            Keys.activeWeekdays,
            Keys.focusBlocksEnabled,
            Keys.focusStartHour,
            Keys.focusEndHour,
            Keys.focusWeekdays,
            Keys.pauseOnSystemIdle,
            Keys.delayDuringMeetings,
            Keys.onlyAcceptedCalendarEvents,
            Keys.deviceAwareModeEnabled,
            Keys.reduceIntensityOnBattery,
            Keys.menuBarMode,
            Keys.selectedSetupPreset,
            Keys.dayStats
        ]

        allKeys.forEach { defaults.removeObject(forKey: $0) }

        isApplyingPreset = true
        intervalOption = .min25
        restDurationOption = .sec20
        protocolPreset = .custom
        breakStyle = .eyes
        enablePreAlert = true
        showPointerCountdown = true
        restOverlayDimAmount = 0.65
        showPerDisplayLabel = true
        scheduleEnabled = false
        scheduleStartHour = 9
        scheduleEndHour = 18
        activeWeekdays = [2, 3, 4, 5, 6]
        focusBlocksEnabled = false
        focusStartHour = 10
        focusEndHour = 12
        focusWeekdays = [2, 3, 4, 5, 6]
        pauseOnSystemIdle = true
        delayDuringMeetings = false
        onlyAcceptedCalendarEvents = true
        deviceAwareModeEnabled = true
        reduceIntensityOnBattery = true
        menuBarMode = .iconAndMinutes
        selectedSetupPreset = nil
        isApplyingPreset = false

        isRunningBreakTest = false
        isShowingTestBreak = false
        savedNextBreakDateForTest = nil
        dayStats = [:]
        refreshStats()
        refreshContextSnapshot()
        scheduleNextBreak(from: .now)
        settingsError = nil
        refreshCalendarStatus(now: .now)
        lastBreakReasonText = "All local data reset"
    }

    func applySetupPreset(_ preset: SetupPreset) {
        isApplyingPreset = true
        switch preset {
        case .gentle:
            intervalOption = .min30
            restDurationOption = .sec20
            protocolPreset = .custom
            breakStyle = .eyes
            enablePreAlert = true
            showPointerCountdown = true
            focusBlocksEnabled = false
        case .eyeCare202020:
            intervalOption = .min20
            restDurationOption = .sec20
            protocolPreset = .eyeCare202020
            breakStyle = .eyes
            enablePreAlert = true
            showPointerCountdown = true
        case .pomodoro:
            intervalOption = .min25
            restDurationOption = .min5
            protocolPreset = .pomodoro
            breakStyle = .stretch
            enablePreAlert = true
            showPointerCountdown = true
        case .deepWork:
            intervalOption = .min30
            restDurationOption = .sec30
            protocolPreset = .custom
            breakStyle = .stretch
            enablePreAlert = false
            showPointerCountdown = false
            focusBlocksEnabled = true
        }
        isApplyingPreset = false
        selectedSetupPreset = preset
        persistSelectedSetupPreset()
        lastBreakReasonText = "Applied \(preset.title) preset"
        scheduleNextBreak(from: .now)
    }

    func requestCalendarAccessManually() {
        requestCalendarAccessIfNeeded(forcePromptIfPossible: true)
    }

    func refreshCalendarAccessStatus() {
        meetingCacheTimestamp = .distantPast
        refreshCalendarStatus(now: .now)
        refreshDerivedState(now: .now)
    }

    var timeRemainingText: String {
        timeRemainingMinutesText
    }

    var preferencesSummaryTitle: String {
        "\(intervalOption.title) work cadence"
    }

    var preferencesSummaryText: String {
        [
            "Break for \(restDurationOption.title)",
            scheduleEnabled ? scheduleSummaryText : "All-day reminders",
            delayDuringMeetings ? "Calendar-aware" : "Calendar off",
            focusBlocksEnabled ? focusSummaryText : "No focus blocks"
        ].joined(separator: " • ")
    }

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        ticker?.tolerance = 0.2
        if let ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
    }

    private func tick() {
        let now = Date()
        refreshContextIfNeeded(now)
        refreshDerivedState(now: now)

        let bypassGuards = isRunningBreakTest || isShowingTestBreak
        guard !isShowingBreak else {
            clearPreAlertUI()
            return
        }

        let blocker = bypassGuards ? RuntimeBlocker.none : runtimeBlocker(for: now)
        if case .none = blocker {
        } else {
            clearPreAlertUI()
            softlyRescheduleIfNeeded(for: blocker, now: now)
            return
        }

        let remaining = nextBreakDate.timeIntervalSince(now)
        if (effectivePreAlertEnabled || isRunningBreakTest), remaining <= 30, remaining > 0 {
            if !preAlertTriggeredThisCycle {
                preAlertTriggeredThisCycle = true
                NSSound.beep()
            }
            isInPreAlert = true
            if showPointerCountdown || isRunningBreakTest {
                pointerCountdownController.show(secondsRemaining: Int(ceil(remaining)))
            } else {
                pointerCountdownController.hide()
            }
        } else {
            clearPreAlertUI()
        }

        if now >= nextBreakDate {
            if isRunningBreakTest {
                isRunningBreakTest = false
                isShowingTestBreak = true
                lastBreakReasonText = "Test overlay started"
                showBreak()
                return
            }

            lastBreakReasonText = "Scheduled break started"
            showBreak()
        }
    }

    private func showBreak() {
        clearPreAlertUI()
        isShowingBreak = true
        refreshDerivedState(now: .now)
        overlayController.showOverlay(
            restDuration: restDurationOption.rawValue,
            style: breakStyle,
            dimAmount: effectiveDimAmount,
            showDisplayLabel: showPerDisplayLabel,
            onDismiss: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.dismissBreakCompleted()
                }
            },
            onSkip: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.skipOnce()
                }
            }
        )
    }

    private func scheduleNextBreak(from base: Date) {
        nextBreakDate = base.addingTimeInterval(effectiveIntervalSeconds)
        preAlertTriggeredThisCycle = false
        clearPreAlertUI()
        refreshDerivedState(now: base)
    }

    private func refreshDerivedState(now: Date) {
        refreshCalendarStatus(now: now)
        let blocker = runtimeBlocker(for: now)
        updateCountdownLabels(now: now, blocker: blocker)
        updateStatusTexts(now: now, blocker: blocker)
        nextBreakClockText = Self.clockFormatter.string(from: nextBreakDate)
    }

    private func updateCountdownLabels(now: Date, blocker: RuntimeBlocker) {
        if isShowingBreak {
            timeRemainingMinutesText = "Break now"
            menuBarCountdownText = "Break"
            menuBarStatusText = "Break"
            return
        }

        switch blocker {
        case .paused:
            timeRemainingMinutesText = "Paused"
            menuBarCountdownText = "Paused"
            menuBarStatusText = "Paused"
            return
        case .outsideSchedule:
            timeRemainingMinutesText = "Off schedule"
            menuBarCountdownText = "Off"
            menuBarStatusText = "Off"
            return
        case .focus:
            timeRemainingMinutesText = "Focus block"
            menuBarCountdownText = "Focus"
            menuBarStatusText = "Focus"
            return
        case .meeting:
            timeRemainingMinutesText = "Meeting active"
            menuBarCountdownText = "Meeting"
            menuBarStatusText = "Meeting"
            return
        case .none:
            break
        }

        let remaining = max(0, nextBreakDate.timeIntervalSince(now))
        let minutes = max(0, Int(ceil(remaining / 60.0)))
        timeRemainingMinutesText = minutes == 1 ? "1 min" : "\(minutes) min"
        menuBarCountdownText = "\(minutes)m"
        menuBarStatusText = remaining <= 60 ? "Soon" : "Working"
    }

    private func updateStatusTexts(now: Date, blocker: RuntimeBlocker) {
        switch blocker {
        case .paused:
            currentStateTitle = "Paused"
            currentStateExplanation = "LookAway is paused because the Mac is locked, sleeping, or you paused reminders manually."
            currentBlockerText = "Paused"
        case .outsideSchedule(let nextStart):
            currentStateTitle = "Outside schedule"
            if let nextStart {
                currentStateExplanation = "Reminders resume at \(Self.dayTimeFormatter.string(from: nextStart))."
                currentBlockerText = "Outside schedule until \(Self.dayTimeFormatter.string(from: nextStart))"
            } else {
                currentStateExplanation = "No active work hours are available with the current schedule."
                currentBlockerText = "Outside schedule"
            }
        case .focus(let until):
            currentStateTitle = "Focus block active"
            if let until {
                currentStateExplanation = "LookAway is holding the next break until your focus block ends at \(Self.clockFormatter.string(from: until))."
                currentBlockerText = "Focus block until \(Self.clockFormatter.string(from: until))"
            } else {
                currentStateExplanation = "LookAway is holding the next break because focus mode is active."
                currentBlockerText = "Focus block"
            }
        case .meeting(let until, let title):
            currentStateTitle = "In a calendar event"
            let meetingLabel = title?.isEmpty == false ? title! : "Current meeting"
            if let until {
                currentStateExplanation = "LookAway will wait until \(meetingLabel) ends at \(Self.clockFormatter.string(from: until))."
                currentBlockerText = "Meeting until \(Self.clockFormatter.string(from: until))"
            } else {
                currentStateExplanation = "LookAway is waiting for the current meeting to finish."
                currentBlockerText = "Meeting active"
            }
        case .none:
            currentStateTitle = isInPreAlert ? "Break soon" : "Working"
            if isInPreAlert {
                currentStateExplanation = "Countdown is active near the pointer. Break starts at \(nextBreakClockText)."
            } else {
                currentStateExplanation = "Next coffee reset is scheduled for \(nextBreakClockText)."
            }
            currentBlockerText = "No blocker"
        }
    }

    private func clearPreAlertUI() {
        isInPreAlert = false
        pointerCountdownController.hide()
    }

    private func finishBreakTest() {
        isRunningBreakTest = false
        preAlertTriggeredThisCycle = false
        clearPreAlertUI()

        if let saved = savedNextBreakDateForTest, saved > .now {
            nextBreakDate = saved
            refreshDerivedState(now: .now)
        } else {
            scheduleNextBreak(from: .now)
        }

        savedNextBreakDateForTest = nil
        lastBreakReasonText = "Test countdown finished"
    }

    private func applyProtocolIfNeeded() {
        guard !isApplyingPreset else { return }
        guard protocolPreset != .custom else { return }

        isApplyingPreset = true
        switch protocolPreset {
        case .eyeCare202020:
            intervalOption = .min20
            restDurationOption = .sec20
            breakStyle = .eyes
        case .pomodoro:
            intervalOption = .min25
            restDurationOption = .min5
            breakStyle = .stretch
        case .custom:
            break
        }
        isApplyingPreset = false
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        let resign = center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setAutoPause("session", active: self.pauseOnSystemIdle)
            }
        }
        let active = center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.setAutoPause("session", active: false)
                self?.lastBreakReasonText = "Session resumed"
                self?.scheduleNextBreak(from: .now)
            }
        }
        let sleep = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setAutoPause("sleep", active: self.pauseOnSystemIdle)
            }
        }
        let wake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.setAutoPause("sleep", active: false)
                self?.lastBreakReasonText = "Mac woke from sleep"
                self?.scheduleNextBreak(from: .now)
            }
        }

        workspaceObservers = [resign, active, sleep, wake]
    }

    private func setupSystemObservers() {
        let center = NotificationCenter.default

        let screensChanged = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshContextSnapshot()
            }
        }

        let lowPowerChanged = center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshContextSnapshot()
            }
        }

        notificationObservers = [screensChanged, lowPowerChanged]
    }

    private func setAutoPause(_ reason: String, active: Bool) {
        if active {
            autoPauseReasons.insert(reason)
        } else {
            autoPauseReasons.remove(reason)
        }
        refreshPauseState()
    }

    private func refreshPauseState() {
        let wasPaused = isPaused
        isPaused = manualPauseEnabled || !autoPauseReasons.isEmpty
        if isPaused && !isRunningBreakTest {
            clearPreAlertUI()
        } else if wasPaused && !isPaused && !isShowingBreak && !isRunningBreakTest {
            scheduleNextBreak(from: .now)
            lastBreakReasonText = "Reminders resumed"
            return
        }
        refreshDerivedState(now: .now)
    }

    private func refreshContextIfNeeded(_ now: Date) {
        guard now.timeIntervalSince(lastContextRefresh) >= 15 else { return }
        refreshContextSnapshot()
    }

    private func refreshContextSnapshot() {
        lastContextRefresh = .now

        let hasExternal = hasExternalDisplayConnected()
        if deviceAwareModeEnabled {
            deviceContextText = hasExternal ? "Display: external monitor connected, using slightly faster reminders." : "Display: laptop-only mode."
        } else {
            deviceContextText = hasExternal ? "Display: external monitor connected." : "Display: laptop-only mode."
        }

        let onBattery = isRunningOnBattery()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if onBattery || lowPower {
            if reduceIntensityOnBattery {
                powerContextText = "Power: battery or low power mode, reducing intensity."
            } else {
                powerContextText = "Power: battery or low power mode."
            }
        } else {
            powerContextText = "Power: plugged in, normal intensity."
        }
    }

    private var effectiveIntervalSeconds: TimeInterval {
        if selectedSetupPreset != nil {
            return intervalOption.seconds
        }

        var seconds = intervalOption.seconds

        if deviceAwareModeEnabled, hasExternalDisplayConnected() {
            seconds *= 0.9
        }

        if shouldLowerIntensityForPower {
            seconds *= 1.25
        }

        return max(60, seconds)
    }

    private var effectivePreAlertEnabled: Bool {
        enablePreAlert && !shouldLowerIntensityForPower
    }

    private var effectiveDimAmount: Double {
        guard shouldLowerIntensityForPower else { return restOverlayDimAmount }
        return max(0.35, restOverlayDimAmount - 0.18)
    }

    private var shouldLowerIntensityForPower: Bool {
        guard reduceIntensityOnBattery else { return false }
        return isRunningOnBattery() || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func hasExternalDisplayConnected() -> Bool {
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = CGDirectDisplayID(screenNumber.uint32Value)
            if CGDisplayIsBuiltin(displayID) == 0 {
                return true
            }
        }
        return false
    }

    private func isRunningOnBattery() -> Bool {
        guard let powerSource = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String? else {
            return false
        }
        return powerSource == kIOPSBatteryPowerValue
    }

    private func runtimeBlocker(for date: Date) -> RuntimeBlocker {
        if isPaused && !isRunningBreakTest {
            return .paused
        }
        if scheduleEnabled, !isWithinSchedule(date) {
            return .outsideSchedule(nextStart: nextScheduleStart(after: date))
        }
        if focusBlocksEnabled, isWithinFocusBlock(date) {
            return .focus(until: currentFocusBlockEnd(for: date))
        }
        if delayDuringMeetings, let event = currentBlockingMeeting(at: date) {
            return .meeting(until: event.endDate, title: event.title)
        }
        return .none
    }

    private func softlyRescheduleIfNeeded(for blocker: RuntimeBlocker, now: Date) {
        guard now >= nextBreakDate else { return }

        switch blocker {
        case .paused:
            return
        case .outsideSchedule(let nextStart):
            guard let nextStart else { return }
            let newBase = nextStart
            let target = newBase.addingTimeInterval(effectiveIntervalSeconds)
            if abs(target.timeIntervalSince(nextBreakDate)) > 1 {
                nextBreakDate = target
                preAlertTriggeredThisCycle = false
                lastBreakReasonText = "Restarted cycle after schedule gap"
                refreshDerivedState(now: now)
            }
        case .focus(let until):
            guard let until else { return }
            let delay = max(0, until.timeIntervalSince(now))
            let target = delay <= shortBlockThreshold ? until.addingTimeInterval(60) : until.addingTimeInterval(effectiveIntervalSeconds)
            if abs(target.timeIntervalSince(nextBreakDate)) > 1 {
                nextBreakDate = target
                preAlertTriggeredThisCycle = false
                lastBreakReasonText = delay <= shortBlockThreshold ? "Postponed break until focus block ended" : "Restarted cycle after long focus block"
                refreshDerivedState(now: now)
            }
        case .meeting(let until, _):
            guard let until else { return }
            let delay = max(0, until.timeIntervalSince(now))
            let target = delay <= shortBlockThreshold ? until.addingTimeInterval(60) : until.addingTimeInterval(effectiveIntervalSeconds)
            if abs(target.timeIntervalSince(nextBreakDate)) > 1 {
                nextBreakDate = target
                preAlertTriggeredThisCycle = false
                lastBreakReasonText = delay <= shortBlockThreshold ? "Postponed break until meeting ended" : "Restarted cycle after long meeting"
                refreshDerivedState(now: now)
            }
        case .none:
            return
        }
    }

    private func isWithinSchedule(_ date: Date) -> Bool {
        isWithinHours(date, weekdays: activeWeekdays, startHour: scheduleStartHour, endHour: scheduleEndHour)
    }

    private func isWithinFocusBlock(_ date: Date) -> Bool {
        isWithinHours(date, weekdays: focusWeekdays, startHour: focusStartHour, endHour: focusEndHour)
    }

    private func isWithinHours(_ date: Date, weekdays: Set<Int>, startHour: Int, endHour: Int) -> Bool {
        guard !weekdays.isEmpty else { return false }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        if startHour == endHour { return true }

        if startHour < endHour {
            guard weekdays.contains(weekday) else { return false }
            return hour >= startHour && hour < endHour
        }

        if hour >= startHour {
            return weekdays.contains(weekday)
        }

        guard hour < endHour else { return false }
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
        let previousWeekday = calendar.component(.weekday, from: previousDay)
        return weekdays.contains(previousWeekday)
    }

    private func nextScheduleStart(after date: Date) -> Date? {
        guard scheduleEnabled, !activeWeekdays.isEmpty else { return nil }
        return nextWindowStart(after: date, weekdays: activeWeekdays, startHour: scheduleStartHour)
    }

    private func currentFocusBlockEnd(for date: Date) -> Date? {
        currentWindowEnd(containing: date, weekdays: focusWeekdays, startHour: focusStartHour, endHour: focusEndHour)
    }

    private func nextWindowStart(after date: Date, weekdays: Set<Int>, startHour: Int) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard weekdays.contains(weekday) else { continue }

            guard let candidate = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day) else { continue }
            if candidate > date {
                return candidate
            }
        }
        return nil
    }

    private func currentWindowEnd(containing date: Date, weekdays: Set<Int>, startHour: Int, endHour: Int) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        if startHour == endHour {
            return calendar.date(byAdding: .day, value: 1, to: startOfDay)
        }

        if startHour < endHour {
            let weekday = calendar.component(.weekday, from: date)
            guard weekdays.contains(weekday) else { return nil }
            return calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: startOfDay)
        }

        let hour = calendar.component(.hour, from: date)
        if hour >= startHour {
            let weekday = calendar.component(.weekday, from: date)
            guard weekdays.contains(weekday) else { return nil }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
            return calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: nextDay)
        }

        guard hour < endHour else { return nil }
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        let previousWeekday = calendar.component(.weekday, from: previousDay)
        guard weekdays.contains(previousWeekday) else { return nil }
        return calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: startOfDay)
    }

    private func requestCalendarAccessIfNeeded(forcePromptIfPossible: Bool = false) {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            calendarStatusText = "Connected"
            calendarDetailText = currentMeetingText == "No active meeting" ? "LookAway can delay breaks during active meetings." : currentMeetingText
        case .writeOnly:
            calendarStatusText = "Write-only access"
            calendarDetailText = "Meeting detection needs full calendar access."
        case .denied, .restricted:
            calendarStatusText = "Access denied"
            calendarDetailText = "Enable Calendars access in System Settings > Privacy & Security > Calendars."
        case .notDetermined:
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let granted = try await self.eventStore.requestFullAccessToEvents()
                    self.calendarStatusText = granted ? "Connected" : "Access denied"
                    self.refreshCalendarStatus(now: .now)
                    self.refreshDerivedState(now: .now)
                } catch {
                    self.calendarStatusText = "Request failed"
                    self.calendarDetailText = error.localizedDescription
                }
            }
        @unknown default:
            calendarStatusText = "Unknown status"
            calendarDetailText = "Calendar authorization returned an unknown state."
        }

        if forcePromptIfPossible, status == .fullAccess {
            refreshCalendarStatus(now: .now)
        }
    }

    private func refreshCalendarStatus(now: Date) {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            if let event = currentBlockingMeeting(at: now) {
                calendarStatusText = "Connected"
                currentMeetingText = "In meeting until \(Self.clockFormatter.string(from: event.endDate))"
                let title = event.title?.isEmpty == false ? event.title! : "Current event"
                calendarDetailText = "\(title) ends at \(Self.clockFormatter.string(from: event.endDate))."
            } else {
                calendarStatusText = "Connected"
                currentMeetingText = "No active meeting"
                calendarDetailText = "LookAway can delay breaks during active meetings."
            }
        case .writeOnly:
            calendarStatusText = "Write-only access"
            currentMeetingText = "Meeting detection unavailable"
            calendarDetailText = "Grant full access to let LookAway skip breaks during events."
        case .denied, .restricted:
            calendarStatusText = "Access denied"
            currentMeetingText = "Meeting detection unavailable"
            calendarDetailText = "Enable access in System Settings > Privacy & Security > Calendars."
        case .notDetermined:
            calendarStatusText = "Calendar not connected"
            currentMeetingText = "No active meeting"
            calendarDetailText = "Request access to let LookAway avoid interrupting meetings."
        @unknown default:
            calendarStatusText = "Unknown status"
            currentMeetingText = "Meeting detection unavailable"
            calendarDetailText = "Calendar authorization returned an unknown state."
        }
    }

    private func currentBlockingMeeting(at date: Date) -> EKEvent? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }

        if date.timeIntervalSince(meetingCacheTimestamp) < 30 {
            return cachedMeetingEvent
        }

        let lookBack: TimeInterval = 5 * 60
        let lookAhead: TimeInterval = 8 * 60 * 60
        let start = date.addingTimeInterval(-lookBack)
        let end = date.addingTimeInterval(lookAhead)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)

        var matchingEvents: [EKEvent] = []
        for event in events {
            guard !event.isAllDay else { continue }
            guard event.startDate <= date, event.endDate > date else { continue }
            guard event.availability != .free else { continue }
            if onlyAcceptedCalendarEvents {
                guard event.status != .canceled else { continue }
                guard event.status == .confirmed || event.status == .none else { continue }
            }
            matchingEvents.append(event)
        }

        cachedMeetingEvent = matchingEvents.sorted { $0.endDate < $1.endDate }.first

        meetingCacheTimestamp = date
        return cachedMeetingEvent
    }

    private func recordStat(_ keyPath: WritableKeyPath<DailyCounters, Int>) {
        let key = Self.dayKey(for: .now)
        var counters = dayStats[key] ?? DailyCounters()
        counters[keyPath: keyPath] += 1
        dayStats[key] = counters
        saveStats()
    }

    private func refreshStats() {
        let todayKey = Self.dayKey(for: .now)
        let today = dayStats[todayKey] ?? DailyCounters()

        var weeklyCompleted = 0
        var weeklySkipped = 0
        var weeklySnoozed = 0
        let calendar = Calendar.current

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            let key = Self.dayKey(for: day)
            let counters = dayStats[key] ?? DailyCounters()
            weeklyCompleted += counters.completed
            weeklySkipped += counters.skipped
            weeklySnoozed += counters.snoozed
        }

        stats = StatsSnapshot(
            dailyCompleted: today.completed,
            dailySkipped: today.skipped,
            dailySnoozed: today.snoozed,
            weeklyCompleted: weeklyCompleted,
            weeklySkipped: weeklySkipped,
            weeklySnoozed: weeklySnoozed
        )
    }

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func loadStats() -> [String: DailyCounters] {
        guard let data = UserDefaults.standard.data(forKey: Keys.dayStats) else { return [:] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([String: DailyCounters].self, from: data)) ?? [:]
    }

    private func saveStats() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(dayStats) else { return }
        UserDefaults.standard.set(data, forKey: Keys.dayStats)
    }

    private func persist<T>(_ value: T, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistSelectedSetupPreset() {
        if let selectedSetupPreset {
            UserDefaults.standard.set(selectedSetupPreset.rawValue, forKey: Keys.selectedSetupPreset)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.selectedSetupPreset)
        }
    }

    private var scheduleSummaryText: String {
        guard scheduleEnabled else { return "All-day reminders" }
        let selectedDays = Weekday.allCases
            .filter { activeWeekdays.contains($0.rawValue) }
            .map(\.shortTitle)
            .joined(separator: ", ")
        return "\(Self.hourText(scheduleStartHour)) - \(Self.hourText(scheduleEndHour)) on \(selectedDays)"
    }

    private var focusSummaryText: String {
        guard focusBlocksEnabled else { return "No focus blocks" }
        let selectedDays = Weekday.allCases
            .filter { focusWeekdays.contains($0.rawValue) }
            .map(\.shortTitle)
            .joined(separator: ", ")
        return "\(Self.hourText(focusStartHour)) - \(Self.hourText(focusEndHour)) on \(selectedDays)"
    }

    static func hourText(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()
}
