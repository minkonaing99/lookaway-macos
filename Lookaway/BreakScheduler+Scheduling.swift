import Foundation

extension BreakScheduler {
    func startTicker() {
        guard !tickerActive else { return }
        tickerActive = true
        scheduleNextTick()
    }

    func stopTicker() {
        tickerActive = false
        ticker?.invalidate()
        ticker = nil
    }

    private func scheduleNextTick() {
        guard tickerActive else { return }
        let interval = tickInterval()
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.tickerActive else { return }
                self.ticker = nil
                self.tick()
                self.scheduleNextTick()
            }
        }
        t.tolerance = max(0.2, interval * 0.1)
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func tickInterval(now: Date = .now) -> TimeInterval {
        guard !isPaused, !isShowingBreak else { return 30 }
        let remaining = nextBreakDate.timeIntervalSince(now)
        if remaining <= 35 { return 1 }
        if remaining <= 120 { return 5 }
        return 30
    }

    func tick() {
        let now = Date()
        refreshContextIfNeeded(now)
        checkIdleState()
        if adaptiveIntervalsEnabled, !isPaused, !isShowingBreak {
            recordActivitySample()
        }

        // When paused and not actively showing a break or running a test,
        // there is nothing useful to compute each second.
        guard !isPaused || isRunningBreakTest || isShowingBreak else { return }

        let bypassGuards = isRunningBreakTest || isShowingTestBreak

        guard !isShowingBreak else {
            clearPreAlertUI()
            return
        }

        let blocker = bypassGuards ? RuntimeBlocker.none : runtimeBlocker(for: now)
        refreshDerivedState(now: now, blocker: blocker)

        if case .none = blocker {
        } else {
            clearPreAlertUI()
            softlyRescheduleIfNeeded(for: blocker, now: now)
            return
        }

        let remaining = nextBreakDate.timeIntervalSince(now)
        if (effectivePreAlertEnabled || isRunningBreakTest), remaining <= 30, remaining > 0 {
            let isFirstPreAlertTick = !preAlertTriggeredThisCycle
            if isFirstPreAlertTick {
                preAlertTriggeredThisCycle = true
            }
            isInPreAlert = true

            switch preAlertPresentation {
            case .pointerCountdown:
                pointerCountdownController.show(secondsRemaining: Int(ceil(remaining)))
                centerPreBreakBannerController.hide()
            case .centerBanner:
                pointerCountdownController.hide()
                showCenterBannerIfNeeded(secondsRemaining: Int(ceil(remaining)))
            case .notification:
                pointerCountdownController.hide()
                centerPreBreakBannerController.hide()
                if isFirstPreAlertTick {
                    notificationManager.sendPreAlert(style: breakStyle, secondsRemaining: Int(ceil(remaining)))
                }
            case .screenDim:
                pointerCountdownController.hide()
                centerPreBreakBannerController.hide()
                dimPreAlertController.show(secondsRemaining: remaining)
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

    func showBreak() {
        clearPreAlertUI()
        isShowingBreak = true
        refreshDerivedState(now: .now)
        let prompts = customPrompts[breakStyle.rawValue]
        overlayController.showOverlay(
            restDuration: restDurationOption.rawValue,
            style: breakStyle,
            dimAmount: effectiveDimAmount,
            showDisplayLabel: showPerDisplayLabel,
            customPrompts: prompts,
            backgroundStyle: overlayBackgroundStyle,
            theme: overlayTheme,
            wallpaperBookmark: wallpaperBookmark,
            reduceMotion: shouldLowerIntensityForPower,
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

    func scheduleNextBreak(from base: Date) {
        let interval = effectiveIntervalSeconds
        currentCycleIntervalSeconds = interval
        nextBreakDate = base.addingTimeInterval(interval)
        preAlertTriggeredThisCycle = false
        shownCenterBannerMilestones.removeAll()
        clearPreAlertUI()
        refreshDerivedState(now: base)
    }

    func clearPreAlertUI() {
        isInPreAlert = false
        pointerCountdownController.hide()
        centerPreBreakBannerController.hide()
        dimPreAlertController.hide()
        notificationManager.cancelPreAlert()
    }

    func showCenterBannerIfNeeded(secondsRemaining: Int) {
        let milestones = [30, 5]

        for milestone in milestones where secondsRemaining <= milestone && !shownCenterBannerMilestones.contains(milestone) {
            shownCenterBannerMilestones.insert(milestone)
            let unit = milestone == 1 ? "second" : "seconds"
            centerPreBreakBannerController.show(message: "Break in \(milestone) \(unit)")
            break
        }
    }

    func finishBreakTest() {
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

    func applyProtocolIfNeeded() {
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

    var effectiveIntervalSeconds: TimeInterval {
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

        seconds *= adaptiveActivityMultiplier

        return max(60, seconds)
    }

    // MARK: - Adaptive intervals

    func recordActivitySample() {
        var samples = activitySamples
        samples.append(currentIdleSeconds() < 60)
        if samples.count > 40 {
            samples.removeFirst(samples.count - 40)
        }
        activitySamples = samples
    }

    var adaptiveActivityMultiplier: Double {
        guard adaptiveIntervalsEnabled, activitySamples.count >= 10 else { return 1.0 }
        let activeCount = activitySamples.filter { $0 }.count
        let ratio = Double(activeCount) / Double(activitySamples.count)
        return Self.adaptiveMultiplier(activityRatio: ratio)
    }

    static func adaptiveMultiplier(activityRatio: Double) -> Double {
        if activityRatio >= 0.8 { return 0.85 }
        if activityRatio <= 0.3 { return 1.2 }
        return 1.0
    }

    // MARK: - Menu bar progress

    static func quantizedProgress(remaining: TimeInterval, interval: TimeInterval) -> Double {
        guard interval > 0 else { return 0 }
        let fraction = min(1, max(0, 1 - remaining / interval))
        return (fraction * 12).rounded() / 12
    }

    var effectivePreAlertEnabled: Bool {
        enablePreAlert && !shouldLowerIntensityForPower
    }

    var effectiveDimAmount: Double {
        guard shouldLowerIntensityForPower else { return restOverlayDimAmount }
        return max(0.35, restOverlayDimAmount - 0.18)
    }

    var shouldLowerIntensityForPower: Bool {
        guard reduceIntensityOnBattery else { return false }
        return isRunningOnBattery() || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
