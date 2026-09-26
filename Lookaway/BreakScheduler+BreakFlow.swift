import CoreGraphics
import Foundation

extension BreakScheduler {
    enum TimedPauseOption: String, CaseIterable, Identifiable {
        case minutes30, hour1, tomorrow
        var id: String { rawValue }
        var title: String {
            switch self {
            case .minutes30: return "30 minutes"
            case .hour1: return "1 hour"
            case .tomorrow: return "Until tomorrow at 9 AM"
            }
        }
    }

    enum LongBreakDuration: Int, CaseIterable, Identifiable {
        case min5 = 5, min10 = 10, min15 = 15
        var id: Int { rawValue }
        var title: String { "\(rawValue) min" }
    }

    static func pauseResumeDate(_ option: TimedPauseOption, now: Date, calendar: Calendar = .current) -> Date? {
        switch option {
        case .minutes30: return now.addingTimeInterval(1800)
        case .hour1: return now.addingTimeInterval(3600)
        case .tomorrow:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
    }

    func pauseReminders(_ option: TimedPauseOption, now: Date = .now) {
        guard let deadline = Self.pauseResumeDate(option, now: now) else { return }
        manualPauseEnabled = true
        manualPauseResumeAt = deadline
        refreshDerivedState(now: now)
    }

    func restoreTimedPause(now: Date) {
        guard let deadline = manualPauseResumeAt else { return }
        if deadline > now {
            manualPauseEnabled = true
            manualPauseResumeAt = deadline
        } else {
            manualPauseEnabled = false
        }
    }

    func expireTimedPause(now: Date) {
        guard let deadline = manualPauseResumeAt, now >= deadline else { return }
        manualPauseEnabled = false
        if !isPaused && !isShowingBreak && !isRunningBreakTest {
            scheduleNextBreak(from: now)
        }
    }

    var manualPauseExplanation: String {
        if let deadline = manualPauseResumeAt {
            return "Manual pause ends \(Self.dayTimeFormatter.string(from: deadline)). Other active pauses must also clear before a fresh work interval starts."
        }
        return "Resume reminders with the pause switch. Automatic pauses must also clear."
    }

    var nextBreakIsLong: Bool {
        longBreaksEnabled && completedShortBreaks >= longBreakEvery
    }

    var nextBreakDuration: TimeInterval {
        nextBreakIsLong ? TimeInterval(longBreakDuration.rawValue * 60) : TimeInterval(restDurationOption.rawValue)
    }

    var longBreakProgressText: String {
        if nextBreakIsLong { return "Next scheduled break: \(longBreakDuration.title) long break." }
        return "\(completedShortBreaks) of \(longBreakEvery) short breaks completed before a \(longBreakDuration.title) long break."
    }

    func recordCycleCompletion() {
        guard longBreaksEnabled, activeBreakCountsTowardCycle, !isShowingTestBreak else { return }
        completedShortBreaks = activeBreakIsLong ? 0 : min(12, completedShortBreaks + 1)
    }

    func shouldDeferBreak(now: Date) -> Bool {
        let gap = inputGapSecondsProvider?() ?? currentInputGapSeconds()
        let dragging = mouseButtonDownProvider?() ?? (
            CGEventSource.buttonState(.hidSystemState, button: .left)
                || CGEventSource.buttonState(.hidSystemState, button: .right)
                || CGEventSource.buttonState(.hidSystemState, button: .center)
        )
        if gap >= 3 && !dragging {
            inputDeferralStartedAt = nil
            return false
        }
        let start = inputDeferralStartedAt ?? now
        inputDeferralStartedAt = start
        return now.timeIntervalSince(start) < 30
    }

    private func currentInputGapSeconds() -> TimeInterval {
        let events: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel
        ]
        return events.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min() ?? 0
    }

    func previewBreakNow() {
        guard !isShowingBreak, systemSuspensions.isEmpty else { return }
        if savedNextBreakDateForTest == nil { savedNextBreakDateForTest = nextBreakDate }
        isRunningBreakTest = false
        isShowingTestBreak = true
        inputDeferralStartedAt = nil
        lastBreakReasonText = "Break preview started"
        showBreak(previewDuration: 10)
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
    }

    func resetBreakFlowSettings() {
        manualPauseEnabled = false
        longBreaksEnabled = false
        longBreakEvery = 4
        longBreakDuration = .min5
        completedShortBreaks = 0
        inputDeferralStartedAt = nil
    }
}
