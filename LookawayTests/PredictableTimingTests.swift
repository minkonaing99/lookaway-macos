import Foundation
import Testing
@testable import Lookaway

@Suite("predictable timing")
struct PredictableTimingTests {
    @Test func presetsHonorExplicitAdaptiveTiming() {
        let scheduler = BreakScheduler()
        defer { scheduler.stopTicker() }
        scheduler.applySetupPreset(.eyeCare202020)
        scheduler.adaptiveIntervalsEnabled = true
        scheduler.activitySamples = Array(repeating: true, count: 20)
        #expect(scheduler.effectiveIntervalSeconds == 1200 * 0.85)
    }

    @Test func powerAndDisplaySettingsDoNotChangeCadence() {
        let scheduler = BreakScheduler()
        defer { scheduler.stopTicker() }
        scheduler.intervalOption = .min25
        scheduler.adaptiveIntervalsEnabled = false
        scheduler.deviceAwareModeEnabled = true
        scheduler.reduceIntensityOnBattery = true
        #expect(scheduler.effectiveIntervalSeconds == 1500)
        #expect(scheduler.effectivePreAlertEnabled == scheduler.enablePreAlert)
    }

    @Test func explanationUsesCurrentDeadline() {
        let scheduler = BreakScheduler()
        defer { scheduler.stopTicker() }
        scheduler.nextBreakClockText = "OLD"
        scheduler.nextBreakDate = .now.addingTimeInterval(1200)
        scheduler.refreshDerivedState(now: .now, blocker: .none)
        #expect(scheduler.currentStateExplanation.contains(scheduler.nextBreakClockText))
        #expect(!scheduler.currentStateExplanation.contains("OLD"))
    }
}
