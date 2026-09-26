import AppKit
import CoreGraphics
import Foundation
import EventKit
import IOKit.ps

extension BreakScheduler {
    func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        let resign = center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setSystemSuspension("session", active: true)
            }
        }
        let active = center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setSystemSuspension("session", active: false)
            }
        }
        let sleep = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setSystemSuspension("sleep", active: true)
            }
        }
        let wake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setSystemSuspension("sleep", active: false)
            }
        }
        let appActivated = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkFrontmostApp()
            }
        }

        workspaceObservers = [resign, active, sleep, wake, appActivated]
    }

    func setSystemSuspension(_ reason: String, active: Bool) {
        guard systemSuspensions.contains(reason) != active else { return }
        systemSuspensions = active ? systemSuspensions.union([reason]) : systemSuspensions.subtracting([reason])
        if active {
            inputDeferralStartedAt = nil
            endWorkSession(at: .now)
            stopTicker()
            clearPreAlertUI()
            webcamMonitor.stopMonitoring()
            // Keep ownership of paused media until the Mac is usable again.
            isShowingBreak = false
            activeBreakID = nil
            activeBreakStartedAt = nil
            activeBreakDeadline = nil
            overlayController.hideOverlay()
            isRunningBreakTest = false
            isShowingTestBreak = false
            savedNextBreakDateForTest = nil
        }
        setAutoPause(reason, active: active)
        guard systemSuspensions.isEmpty else { return }
        expireTimedPause(now: .now)
        mediaPlaybackController.endBreak()
        meetingCacheTimestamp = .distantPast
        refreshWebcamMonitoring()
        checkFrontmostApp()
        checkIdleState()
        scheduleNextBreak(from: .now)
        updateWorkSession(now: .now)
        lastBreakReasonText = "Mac active again; fresh break cycle started"
        startTicker()
    }

    func handleDisplayChange() {
        refreshContextSnapshot()
        presentBreakOverlay()
    }

    func setupSystemObservers() {
        let center = NotificationCenter.default

        let screensChanged = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDisplayChange()
            }
        }

        let lowPowerChanged = center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshContextSnapshot()
            }
        }

        let calendarChanged = center.addObserver(forName: .EKEventStoreChanged, object: eventStore, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.meetingCacheTimestamp = .distantPast
            }
        }
        notificationObservers = [screensChanged, lowPowerChanged, calendarChanged]
    }

    func setAutoPause(_ reason: String, active: Bool) {
        guard autoPauseReasons.contains(reason) != active else { return }
        autoPauseReasons = active ? autoPauseReasons.union([reason]) : autoPauseReasons.subtracting([reason])
        refreshPauseState()
    }

    func refreshPauseState() {
        let wasPaused = isPaused
        let paused = manualPauseEnabled || !autoPauseReasons.isEmpty
        if isPaused != paused { isPaused = paused }
        if isPaused && !isRunningBreakTest {
            inputDeferralStartedAt = nil
            clearPreAlertUI()
        } else if wasPaused && !isPaused && !isShowingBreak && !isRunningBreakTest {
            scheduleNextBreak(from: .now)
            lastBreakReasonText = "Reminders resumed"
            return
        }
        refreshDerivedState(now: .now)
    }

    func refreshContextIfNeeded(_ now: Date) {
        guard now.timeIntervalSince(lastContextRefresh) >= 120 else { return }
        refreshContextSnapshot()
    }

    func refreshContextSnapshot() {
        lastContextRefresh = .now

        let hasExternal = hasExternalDisplayConnected()
        deviceContextText = hasExternal ? "External monitor connected. Break timing stays unchanged." : "Laptop display. Break timing stays unchanged."

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

    func hasExternalDisplayConnected() -> Bool {
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

    func isRunningOnBattery() -> Bool {
        guard let powerSource = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String? else {
            return false
        }
        return powerSource == kIOPSBatteryPowerValue
    }

    // MARK: - App-Aware Pausing

    func checkFrontmostApp() {
        guard appAwarePauseEnabled else {
            setAutoPause("frontmostApp", active: false)
            return
        }
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let shouldPause = !bundleID.isEmpty && pauseAppBundleIDs.contains(bundleID)
        setAutoPause("frontmostApp", active: shouldPause)
    }

    // MARK: - Idle Detection

    func checkIdleState() {
        guard pauseWhenIdle else {
            setAutoPause("idle", active: false)
            return
        }
        let idleSeconds = currentIdleSeconds()
        setAutoPause("idle", active: idleSeconds >= 300)
    }

    func currentIdleSeconds() -> TimeInterval {
        idleSecondsProvider?() ?? secondsSinceLastUserInput()
    }

    private func secondsSinceLastUserInput() -> TimeInterval {
        let mouse = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        let click = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown)
        let key   = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        return min(mouse, min(click, key))
    }

    // MARK: - Webcam Monitoring

    func refreshWebcamMonitoring() {
        if pauseWhenCameraActive {
            webcamMonitor.startMonitoring { [weak self] isActive in
                self?.setAutoPause("webcam", active: isActive)
            }
        } else {
            webcamMonitor.stopMonitoring()
            setAutoPause("webcam", active: false)
        }
    }
}
