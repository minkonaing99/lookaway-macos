import Foundation

extension BreakScheduler {
    func toggleWeekday(_ day: Weekday) {
        if activeWeekdays.contains(day.rawValue) {
            activeWeekdays.remove(day.rawValue)
        } else {
            activeWeekdays.insert(day.rawValue)
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
        shownCenterBannerMilestones.removeAll()
        lastBreakReasonText = "Test countdown started"
        nextBreakDate = .now.addingTimeInterval(preAlertPresentation == .centerBanner ? 35 : 10)
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

        // Break completion feedback
        breakCompletionBadgeController.show()
        showBreakCompletionBadge = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.showBreakCompletionBadge = false
        }
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
            Keys.interval, Keys.restDuration, Keys.protocolPreset, Keys.breakStyle,
            Keys.preAlertEnabled, Keys.preAlertPresentation, Keys.pointerCountdownEnabled,
            Keys.dimAmount, Keys.showDisplayLabel, Keys.scheduleEnabled, Keys.scheduleStartHour,
            Keys.scheduleEndHour, Keys.activeWeekdays, Keys.focusBlocksEnabled,
            Keys.focusBlockWindows, Keys.pauseOnSystemIdle, Keys.delayDuringMeetings,
            Keys.onlyAcceptedCalendarEvents, Keys.deviceAwareModeEnabled, Keys.reduceIntensityOnBattery,
            Keys.menuBarMode, Keys.selectedSetupPreset, Keys.dayStats,
            Keys.customPrompts, Keys.appAwarePauseEnabled, Keys.pauseAppBundleIDs, Keys.pauseWhenCameraActive
        ]

        allKeys.forEach { defaults.removeObject(forKey: $0) }

        isApplyingPreset = true
        intervalOption = .min25
        restDurationOption = .sec20
        protocolPreset = .custom
        breakStyle = .eyes
        enablePreAlert = true
        preAlertPresentation = .pointerCountdown
        restOverlayDimAmount = 0.65
        showPerDisplayLabel = true
        scheduleEnabled = false
        scheduleStartHour = 9
        scheduleEndHour = 18
        activeWeekdays = [2, 3, 4, 5, 6]
        focusBlocksEnabled = false
        focusBlockWindows = [FocusBlockWindow(name: "Focus Time", startHour: 10, endHour: 12, weekdays: [2, 3, 4, 5, 6])]
        pauseOnSystemIdle = true
        delayDuringMeetings = false
        onlyAcceptedCalendarEvents = true
        deviceAwareModeEnabled = true
        reduceIntensityOnBattery = true
        menuBarMode = .iconAndMinutes
        selectedSetupPreset = nil
        customPrompts = [:]
        appAwarePauseEnabled = false
        pauseAppBundleIDs = []
        pauseWhenCameraActive = false
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
            preAlertPresentation = .pointerCountdown
            focusBlocksEnabled = false
        case .eyeCare202020:
            intervalOption = .min20
            restDurationOption = .sec20
            protocolPreset = .eyeCare202020
            breakStyle = .eyes
            enablePreAlert = true
            preAlertPresentation = .pointerCountdown
        case .pomodoro:
            intervalOption = .min25
            restDurationOption = .min5
            protocolPreset = .pomodoro
            breakStyle = .stretch
            enablePreAlert = true
            preAlertPresentation = .pointerCountdown
        case .deepWork:
            intervalOption = .min30
            restDurationOption = .sec30
            protocolPreset = .custom
            breakStyle = .stretch
            enablePreAlert = false
            preAlertPresentation = .centerBanner
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

    // MARK: - Custom Prompts

    func updatePrompts(for style: BreakStyle, prompts: [String]) {
        var updated = customPrompts
        updated[style.rawValue] = prompts
        customPrompts = updated
    }

    func resetPrompts(for style: BreakStyle) {
        var updated = customPrompts
        updated.removeValue(forKey: style.rawValue)
        customPrompts = updated
    }

    // MARK: - Focus Block Windows

    func addFocusBlockWindow() {
        let newWindow = FocusBlockWindow(
            name: "Focus Block \(focusBlockWindows.count + 1)",
            startHour: 10, endHour: 12,
            weekdays: [2, 3, 4, 5, 6]
        )
        focusBlockWindows = focusBlockWindows + [newWindow]
    }

    func removeFocusBlockWindow(id: UUID) {
        focusBlockWindows = focusBlockWindows.filter { $0.id != id }
    }

    func updateFocusBlockWindow(_ updated: FocusBlockWindow) {
        focusBlockWindows = focusBlockWindows.map { $0.id == updated.id ? updated : $0 }
    }

    // MARK: - App-Aware Pausing

    func addPauseApp(bundleID: String) {
        guard !pauseAppBundleIDs.contains(bundleID) else { return }
        pauseAppBundleIDs = pauseAppBundleIDs + [bundleID]
    }

    func removePauseApp(bundleID: String) {
        pauseAppBundleIDs = pauseAppBundleIDs.filter { $0 != bundleID }
    }
}
