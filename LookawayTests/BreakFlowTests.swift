import Foundation
import Testing
@testable import Lookaway

@Suite("pause, long breaks, onboarding and input gaps", .serialized)
struct BreakFlowTests {
    private func withScheduler(_ body: (BreakScheduler) throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("lookaway.") }
        let s = BreakScheduler(mediaPlaybackController: MediaPlaybackController(snapshot: { nil }, send: { _ in false }))
        s.stopTicker()
        s.scheduleEnabled = false
        s.focusBlocksEnabled = false
        s.delayDuringMeetings = false
        s.appAwarePauseEnabled = false
        s.pauseWhenCameraActive = false
        s.manualPauseEnabled = false
        s.autoPauseReasons = []
        s.idleSecondsProvider = { 10 }
        s.inputGapSecondsProvider = { 10 }
        s.mouseButtonDownProvider = { false }
        s.pauseWhenIdle = false
        s.adaptiveIntervalsEnabled = false
        s.enablePreAlert = false
        s.longBreaksEnabled = false
        s.completedShortBreaks = 0
        s.restDurationOption = .sec20
        s.dayStats = [:]
        defer {
            s.stopTicker()
            s.overlayController.hideOverlay()
            s.breakCompletionBadgeController.hide()
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("lookaway.") { defaults.removeObject(forKey: key) }
            for (key, value) in saved { defaults.set(value, forKey: key) }
        }
        try body(s)
    }

    @Test func timedPauseExpiresWithoutClearingAutomaticPause() {
        withScheduler { s in
            let now = Date()
            s.pauseReminders(.minutes30, now: now)
            #expect(s.manualPauseResumeAt == now.addingTimeInterval(1800))
            #expect(s.isPaused)
            #expect(s.currentStateExplanation.contains("Manual pause ends"))
            s.setAutoPause("webcam", active: true)
            s.expireTimedPause(now: now.addingTimeInterval(1799))
            #expect(s.manualPauseEnabled)
            s.expireTimedPause(now: now.addingTimeInterval(1800))
            #expect(!s.manualPauseEnabled)
            #expect(s.manualPauseResumeAt == nil)
            #expect(s.isPaused)
            s.setAutoPause("webcam", active: false)
            #expect(!s.isPaused)
        }
    }

    @Test func replacingPauseAndEarlyResumeClearOldDeadline() {
        withScheduler { s in
            let now = Date()
            s.pauseReminders(.minutes30, now: now)
            s.pauseReminders(.hour1, now: now)
            #expect(s.manualPauseResumeAt == now.addingTimeInterval(3600))
            #expect(s.tickInterval(now: now.addingTimeInterval(3599)) == 1)
            s.manualPauseEnabled = false
            #expect(s.manualPauseResumeAt == nil)
            #expect(UserDefaults.standard.object(forKey: BreakScheduler.Keys.manualPauseResumeAt) == nil)
        }
    }

    @Test func tomorrowUsesLocalNineAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        let resume = try #require(BreakScheduler.pauseResumeDate(.tomorrow, now: now, calendar: calendar))
        let parts = calendar.dateComponents([.day, .hour], from: resume)
        #expect(parts.day == 8)
        #expect(parts.hour == 9)
        #expect(resume.timeIntervalSince(now) == 20 * 3600)
    }

    @Test func timedPauseRestoresAfterRestart() {
        withScheduler { s in
            let now = Date()
            s.pauseReminders(.hour1, now: now)
            let restored = BreakScheduler(now: now)
            defer { restored.stopTicker() }
            #expect(restored.manualPauseEnabled)
            #expect(restored.manualPauseResumeAt == s.manualPauseResumeAt)
            let expired = BreakScheduler(now: now.addingTimeInterval(3601))
            defer { expired.stopTicker() }
            #expect(!expired.manualPauseEnabled)
            #expect(expired.manualPauseResumeAt == nil)
        }
    }

    @Test func fourCompletedShortBreaksMakeNextBreakLong() {
        withScheduler { s in
            s.longBreaksEnabled = true
            s.longBreakEvery = 4
            s.longBreakDuration = .min5
            for count in 1...4 {
                s.showBreak()
                #expect(s.activeBreakDuration == 20)
                s.dismissBreakCompleted()
                #expect(s.completedShortBreaks == count)
            }
            s.showBreak()
            #expect(s.activeBreakIsLong)
            #expect(s.activeBreakDuration == 300)
            s.skipOnce()
            #expect(s.completedShortBreaks == 4)
            s.showBreak()
            s.dismissBreakCompleted()
            #expect(s.completedShortBreaks == 0)
        }
    }

    @Test func skipsSnoozesAndPreviewsNeverAdvanceCycle() {
        withScheduler { s in
            s.longBreaksEnabled = true
            s.completedShortBreaks = 2
            s.showBreak()
            s.skipOnce()
            s.showBreak()
            s.snooze(minutes: 5)
            let savedDate = s.nextBreakDate
            let completed = s.dayStats.values.reduce(0) { $0 + $1.completed }
            s.previewBreakNow()
            #expect(s.isShowingTestBreak)
            s.dismissBreakCompleted()
            #expect(s.completedShortBreaks == 2)
            #expect(s.nextBreakDate == savedDate)
            #expect(s.dayStats.values.reduce(0) { $0 + $1.completed } == completed)
        }
    }

    @Test func capturedLongDurationSurvivesSettingsChange() {
        withScheduler { s in
            s.longBreaksEnabled = true
            s.completedShortBreaks = s.longBreakEvery
            s.showBreak()
            s.longBreakDuration = .min10
            s.handleDisplayChange()
            #expect(s.activeBreakDuration == 300)
            s.skipOnce()
            #expect(s.nextBreakDuration == 600)
        }
    }

    @Test func typingWaitsForGapButNeverBeyondThirtySeconds() {
        withScheduler { s in
            let now = Date()
            s.nextBreakDate = now
            s.inputGapSecondsProvider = { 0 }
            s.tick(now: now)
            #expect(!s.isShowingBreak)
            #expect(s.currentStateTitle == "Waiting for a pause")
            s.tick(now: now.addingTimeInterval(29))
            #expect(!s.isShowingBreak)
            s.tick(now: now.addingTimeInterval(30))
            #expect(s.isShowingBreak)
            s.skipOnce()
        }
    }

    @Test func inputGapEndsWaitAndDragKeepsWaiting() {
        withScheduler { s in
            let now = Date()
            s.nextBreakDate = now
            s.mouseButtonDownProvider = { true }
            s.tick(now: now)
            #expect(!s.isShowingBreak)
            s.mouseButtonDownProvider = { false }
            s.tick(now: now.addingTimeInterval(3))
            #expect(s.isShowingBreak)
            s.skipOnce()
        }
    }

    @Test func pauseClearsInputWaitAndManualBreakBypassesIt() {
        withScheduler { s in
            let now = Date()
            s.nextBreakDate = now
            s.inputGapSecondsProvider = { 0 }
            s.tick(now: now)
            s.pauseReminders(.minutes30, now: now)
            #expect(s.inputDeferralStartedAt == nil)
            s.triggerBreakNow()
            #expect(s.isShowingBreak)
            s.skipOnce()
        }
    }

    @Test func onboardingCompletionPersistsAndPreviewRestoresPause() {
        withScheduler { s in
            s.hasCompletedOnboarding = false
            s.pauseReminders(.hour1)
            let resume = s.manualPauseResumeAt
            s.previewBreakNow()
            s.skipOnce()
            #expect(s.manualPauseResumeAt == resume)
            s.completeOnboarding()
            #expect(s.hasCompletedOnboarding)
            #expect(UserDefaults.standard.bool(forKey: BreakScheduler.Keys.hasCompletedOnboarding))
        }
    }

    @Test func expiryThroughTickerStartsFreshCycle() {
        withScheduler { s in
            let now = Date()
            s.pauseReminders(.minutes30, now: now)
            let resume = now.addingTimeInterval(1800)
            s.tick(now: resume)
            #expect(!s.manualPauseEnabled)
            #expect(!s.isShowingBreak)
            #expect(s.nextBreakDate == resume.addingTimeInterval(s.effectiveIntervalSeconds))
        }
    }

    @Test func longBreakProgressRestoresAndSleepDoesNotConsumeIt() {
        withScheduler { s in
            s.longBreaksEnabled = true
            s.longBreakEvery = 4
            s.completedShortBreaks = 3
            #expect(s.longBreakProgressText.contains("3 of 4"))
            let restored = BreakScheduler()
            defer { restored.stopTicker() }
            #expect(restored.completedShortBreaks == 3)
            s.completedShortBreaks = 4
            #expect(s.longBreakProgressText.contains("Next scheduled break: 5 min"))
            s.showBreak()
            s.setSystemSuspension("sleep", active: true)
            #expect(s.completedShortBreaks == 4)
            s.setSystemSuspension("sleep", active: false)
            #expect(s.nextBreakIsLong)
        }
    }

    @Test func featureResetClearsPauseAndCycleAndInvalidSavedOptionsUseDefaults() {
        withScheduler { s in
            s.pauseReminders(.hour1)
            s.longBreaksEnabled = true
            s.completedShortBreaks = 4
            s.resetBreakFlowSettings()
            #expect(!s.manualPauseEnabled)
            #expect(s.manualPauseResumeAt == nil)
            #expect(!s.longBreaksEnabled)
            #expect(s.completedShortBreaks == 0)
            UserDefaults.standard.set(-10, forKey: BreakScheduler.Keys.longBreakEvery)
            UserDefaults.standard.set(-10, forKey: BreakScheduler.Keys.longBreakDuration)
            let restored = BreakScheduler()
            defer { restored.stopTicker() }
            #expect(restored.longBreakEvery == 4)
            #expect(restored.longBreakDuration == .min5)
        }
    }

    @Test func nativeInputSamplingHonorsExpiredDeferral() {
        withScheduler { s in
            let now = Date()
            s.inputGapSecondsProvider = nil
            s.mouseButtonDownProvider = nil
            s.inputDeferralStartedAt = now.addingTimeInterval(-31)
            #expect(!s.shouldDeferBreak(now: now))
        }
    }

    @Test func pauseChoicesAndDurationChoicesHaveDistinctAccessibleLabels() {
        let pauses = BreakScheduler.TimedPauseOption.allCases
        #expect(pauses.map(\.title) == ["30 minutes", "1 hour", "Until tomorrow at 9 AM"])
        #expect(Set(pauses.map(\.id)).count == 3)
        let durations = BreakScheduler.LongBreakDuration.allCases
        #expect(durations.map(\.title) == ["5 min", "10 min", "15 min"])
        #expect(Set(durations.map(\.id)).count == 3)
    }
}
