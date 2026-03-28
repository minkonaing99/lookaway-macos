import Foundation

extension BreakScheduler {
    func startTicker() {
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

    func tick() {
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
        nextBreakDate = base.addingTimeInterval(effectiveIntervalSeconds)
        preAlertTriggeredThisCycle = false
        shownCenterBannerMilestones.removeAll()
        clearPreAlertUI()
        refreshDerivedState(now: base)
    }

    func clearPreAlertUI() {
        isInPreAlert = false
        pointerCountdownController.hide()
        centerPreBreakBannerController.hide()
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

        return max(60, seconds)
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
