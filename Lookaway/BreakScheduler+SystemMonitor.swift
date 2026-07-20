import AppKit
import CoreGraphics
import Foundation
import IOKit.ps

extension BreakScheduler {
    func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        let resign = center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stopTicker()
                self.clearPreAlertUI()
                self.webcamMonitor.stopMonitoring()
                self.setAutoPause("session", active: self.pauseOnSystemIdle)
            }
        }
        let active = center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.startTicker()
                self.refreshWebcamMonitoring()
                self.setAutoPause("session", active: false)
                self.lastBreakReasonText = "Session resumed"
                self.scheduleNextBreak(from: .now)
            }
        }
        let sleep = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.stopTicker()
                self.clearPreAlertUI()
                self.webcamMonitor.stopMonitoring()
                self.setAutoPause("sleep", active: self.pauseOnSystemIdle)
            }
        }
        let wake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.meetingCacheTimestamp = .distantPast
                self.startTicker()
                self.refreshWebcamMonitoring()
                self.setAutoPause("sleep", active: false)
                self.lastBreakReasonText = "Mac woke from sleep"
                self.scheduleNextBreak(from: .now)
            }
        }
        let appActivated = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkFrontmostApp()
            }
        }

        workspaceObservers = [resign, active, sleep, wake, appActivated]
    }

    func setupSystemObservers() {
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

    func setAutoPause(_ reason: String, active: Bool) {
        if active {
            autoPauseReasons.insert(reason)
        } else {
            autoPauseReasons.remove(reason)
        }
        refreshPauseState()
    }

    func refreshPauseState() {
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

    func refreshContextIfNeeded(_ now: Date) {
        guard now.timeIntervalSince(lastContextRefresh) >= 120 else { return }
        refreshContextSnapshot()
    }

    func refreshContextSnapshot() {
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
