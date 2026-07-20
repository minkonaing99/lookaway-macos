import Testing
import Foundation
@testable import Lookaway

// MARK: - tickInterval

@Suite("tickInterval")
struct TickIntervalTests {
    let scheduler = BreakScheduler()

    @Test func thirtySecondsWhenPaused() {
        scheduler.manualPauseEnabled = true
        #expect(scheduler.tickInterval(now: .now) == 30)
    }

    @Test func thirtySecondsWhenShowingBreak() {
        scheduler.isShowingBreak = true
        #expect(scheduler.tickInterval(now: .now) == 30)
    }

    @Test func thirtySecondsWhenFarFromBreak() {
        let now = Date()
        scheduler.nextBreakDate = now.addingTimeInterval(300)
        #expect(scheduler.tickInterval(now: now) == 30)
    }

    @Test func fiveSecondsWhenApproaching() {
        let now = Date()
        scheduler.nextBreakDate = now.addingTimeInterval(100)
        #expect(scheduler.tickInterval(now: now) == 5)
    }

    @Test func oneSecondInPreAlertZone() {
        let now = Date()
        scheduler.nextBreakDate = now.addingTimeInterval(20)
        #expect(scheduler.tickInterval(now: now) == 1)
    }

    @Test func boundaryAt35Seconds() {
        let now = Date()
        scheduler.nextBreakDate = now.addingTimeInterval(35)
        #expect(scheduler.tickInterval(now: now) == 1)
    }

    @Test func boundaryAt120Seconds() {
        let now = Date()
        scheduler.nextBreakDate = now.addingTimeInterval(120)
        #expect(scheduler.tickInterval(now: now) == 5)
    }
}

// MARK: - Ticker lifecycle

@Suite("ticker lifecycle")
struct TickerLifecycleTests {
    @Test func stopClearsActiveFlag() {
        let scheduler = BreakScheduler()
        scheduler.stopTicker()
        #expect(!scheduler.tickerActive)
        #expect(scheduler.ticker == nil)
    }

    @Test func startSetsActiveFlag() {
        let scheduler = BreakScheduler()
        scheduler.stopTicker()
        scheduler.startTicker()
        #expect(scheduler.tickerActive)
        scheduler.stopTicker()
    }

    @Test func doubleStartIsHarmless() {
        let scheduler = BreakScheduler()
        scheduler.startTicker()
        let firstTimer = scheduler.ticker
        scheduler.startTicker()
        #expect(scheduler.ticker === firstTimer)
        scheduler.stopTicker()
    }
}

// MARK: - Idle detection

@Suite("idle detection")
struct IdleDetectionTests {
    @Test func autoPausesWhenIdlePastThreshold() {
        let scheduler = BreakScheduler()
        scheduler.manualPauseEnabled = false
        scheduler.pauseWhenIdle = true
        scheduler.idleSecondsProvider = { 400 }
        scheduler.checkIdleState()
        #expect(scheduler.isPaused)
        scheduler.idleSecondsProvider = { 0 }
        scheduler.checkIdleState()
    }

    @Test func staysActiveWhenRecentInput() {
        let scheduler = BreakScheduler()
        scheduler.manualPauseEnabled = false
        scheduler.pauseWhenIdle = true
        scheduler.idleSecondsProvider = { 10 }
        scheduler.checkIdleState()
        #expect(!scheduler.isPaused)
    }

    @Test func disabledToggleNeverPauses() {
        let scheduler = BreakScheduler()
        scheduler.manualPauseEnabled = false
        scheduler.pauseWhenIdle = false
        scheduler.idleSecondsProvider = { 400 }
        scheduler.checkIdleState()
        #expect(!scheduler.isPaused)
    }

    @Test func resumesAfterActivityReturns() {
        let scheduler = BreakScheduler()
        scheduler.manualPauseEnabled = false
        scheduler.pauseWhenIdle = true
        scheduler.idleSecondsProvider = { 400 }
        scheduler.checkIdleState()
        #expect(scheduler.isPaused)
        scheduler.idleSecondsProvider = { 5 }
        scheduler.checkIdleState()
        #expect(!scheduler.isPaused)
    }
}

// MARK: - Adaptive intervals

@Suite("adaptiveMultiplier")
struct AdaptiveMultiplierTests {
    @Test func heavyActivityShortensInterval() {
        #expect(BreakScheduler.adaptiveMultiplier(activityRatio: 0.9) == 0.85)
        #expect(BreakScheduler.adaptiveMultiplier(activityRatio: 0.8) == 0.85)
    }

    @Test func lightActivityLengthensInterval() {
        #expect(BreakScheduler.adaptiveMultiplier(activityRatio: 0.1) == 1.2)
        #expect(BreakScheduler.adaptiveMultiplier(activityRatio: 0.3) == 1.2)
    }

    @Test func moderateActivityIsNeutral() {
        #expect(BreakScheduler.adaptiveMultiplier(activityRatio: 0.5) == 1.0)
        #expect(BreakScheduler.adaptiveMultiplier(activityRatio: 0.79) == 1.0)
        #expect(BreakScheduler.adaptiveMultiplier(activityRatio: 0.31) == 1.0)
    }
}

@Suite("adaptive effectiveIntervalSeconds")
struct AdaptiveIntervalIntegrationTests {
    private func makeScheduler() -> BreakScheduler {
        let scheduler = BreakScheduler()
        scheduler.selectedSetupPreset = nil
        scheduler.deviceAwareModeEnabled = false
        scheduler.reduceIntensityOnBattery = false
        scheduler.intervalOption = .min25
        return scheduler
    }

    @Test func heavySamplesShortenInterval() {
        let scheduler = makeScheduler()
        scheduler.adaptiveIntervalsEnabled = true
        scheduler.activitySamples = Array(repeating: true, count: 20)
        #expect(scheduler.effectiveIntervalSeconds == 25 * 60 * 0.85)
        scheduler.adaptiveIntervalsEnabled = false
    }

    @Test func lightSamplesLengthenInterval() {
        let scheduler = makeScheduler()
        scheduler.adaptiveIntervalsEnabled = true
        scheduler.activitySamples = Array(repeating: false, count: 20)
        #expect(scheduler.effectiveIntervalSeconds == 25 * 60 * 1.2)
        scheduler.adaptiveIntervalsEnabled = false
    }

    @Test func tooFewSamplesStayNeutral() {
        let scheduler = makeScheduler()
        scheduler.adaptiveIntervalsEnabled = true
        scheduler.activitySamples = Array(repeating: true, count: 5)
        #expect(scheduler.effectiveIntervalSeconds == 25 * 60)
        scheduler.adaptiveIntervalsEnabled = false
    }

    @Test func disabledToggleStaysNeutral() {
        let scheduler = makeScheduler()
        scheduler.adaptiveIntervalsEnabled = false
        scheduler.activitySamples = Array(repeating: true, count: 20)
        #expect(scheduler.effectiveIntervalSeconds == 25 * 60)
    }

    @Test func sampleWindowIsCapped() {
        let scheduler = makeScheduler()
        scheduler.activitySamples = []
        scheduler.idleSecondsProvider = { 0 }
        for _ in 0..<50 {
            scheduler.recordActivitySample()
        }
        #expect(scheduler.activitySamples.count == 40)
        #expect(scheduler.activitySamples.allSatisfy { $0 })
    }
}

// MARK: - Stats pruning

@Suite("stats pruning")
struct StatsPruningTests {
    @Test func saveStatsCapsAt400NewestDays() {
        let scheduler = BreakScheduler()
        let original = scheduler.dayStats

        var seeded: [String: BreakScheduler.DailyCounters] = [:]
        for i in 0..<450 {
            seeded[String(format: "day-%04d", i)] = BreakScheduler.DailyCounters(completed: 1, skipped: 0, snoozed: 0)
        }
        scheduler.dayStats = seeded
        scheduler.saveStats()

        #expect(scheduler.dayStats.count == 400)
        #expect(scheduler.dayStats["day-0449"] != nil)
        #expect(scheduler.dayStats["day-0049"] == nil)

        scheduler.dayStats = original
        scheduler.saveStats()
    }

    @Test func saveStatsLeavesSmallHistoriesAlone() {
        let scheduler = BreakScheduler()
        let original = scheduler.dayStats

        scheduler.dayStats = ["day-0001": BreakScheduler.DailyCounters(completed: 2, skipped: 0, snoozed: 0)]
        scheduler.saveStats()
        #expect(scheduler.dayStats.count == 1)

        scheduler.dayStats = original
        scheduler.saveStats()
    }
}

// MARK: - Menu bar ring icon cache

@Suite("menu bar ring icon")
struct MenuBarRingIconTests {
    @Test func sameFractionReturnsCachedInstance() {
        #expect(MenuBarRingIcon.image(fraction: 0.5) === MenuBarRingIcon.image(fraction: 0.5))
    }

    @Test func outOfRangeFractionsClampToCachedEnds() {
        #expect(MenuBarRingIcon.image(fraction: 2.0) === MenuBarRingIcon.image(fraction: 1.0))
        #expect(MenuBarRingIcon.image(fraction: -1.0) === MenuBarRingIcon.image(fraction: 0.0))
    }
}

// MARK: - Dim pre-alert

@Suite("dimAlpha")
struct DimAlphaTests {
    @Test func zeroAtWindowStart() {
        #expect(DimPreAlertOverlayController.dimAlpha(secondsRemaining: 30) == 0)
    }

    @Test func maxAtBreakTime() {
        #expect(DimPreAlertOverlayController.dimAlpha(secondsRemaining: 0) == DimPreAlertOverlayController.maxDimAlpha)
    }

    @Test func midwayIsHalf() {
        let alpha = DimPreAlertOverlayController.dimAlpha(secondsRemaining: 15)
        #expect(abs(alpha - DimPreAlertOverlayController.maxDimAlpha / 2) < 0.0001)
    }

    @Test func clampsOutOfRangeInputs() {
        #expect(DimPreAlertOverlayController.dimAlpha(secondsRemaining: 60) == 0)
        #expect(DimPreAlertOverlayController.dimAlpha(secondsRemaining: -5) == DimPreAlertOverlayController.maxDimAlpha)
    }
}

// MARK: - Menu bar progress ring

@Suite("quantizedProgress")
struct QuantizedProgressTests {
    @Test func zeroAtCycleStart() {
        #expect(BreakScheduler.quantizedProgress(remaining: 1500, interval: 1500) == 0)
    }

    @Test func fullAtBreakTime() {
        #expect(BreakScheduler.quantizedProgress(remaining: 0, interval: 1500) == 1)
    }

    @Test func midCycleIsHalf() {
        #expect(BreakScheduler.quantizedProgress(remaining: 750, interval: 1500) == 0.5)
    }

    @Test func quantizedToTwelfths() {
        let value = BreakScheduler.quantizedProgress(remaining: 1400, interval: 1500)
        #expect(value == (value * 12).rounded() / 12)
    }

    @Test func zeroIntervalIsSafe() {
        #expect(BreakScheduler.quantizedProgress(remaining: 100, interval: 0) == 0)
    }

    @Test func clampsNegativeRemaining() {
        #expect(BreakScheduler.quantizedProgress(remaining: -20, interval: 1500) == 1)
    }
}
