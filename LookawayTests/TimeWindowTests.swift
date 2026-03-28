import Testing
import Foundation
@testable import Lookaway

// MARK: - isWithinHours

@Suite("isWithinHours")
struct IsWithinHoursTests {
    let scheduler = BreakScheduler()

    // Monday 10:30 — should be inside Mon–Fri 9–18
    @Test func withinStandardWindow() {
        let date = makeDate(weekday: .monday, hour: 10, minute: 30)
        #expect(scheduler.isWithinHours(date, weekdays: weekdays(.monday, .tuesday, .wednesday, .thursday, .friday), startHour: 9, endHour: 18))
    }

    // Saturday 10:30 — should be outside Mon–Fri 9–18
    @Test func outsideWeekendWhenWeekdayOnly() {
        let date = makeDate(weekday: .saturday, hour: 10, minute: 30)
        #expect(!scheduler.isWithinHours(date, weekdays: weekdays(.monday, .tuesday, .wednesday, .thursday, .friday), startHour: 9, endHour: 18))
    }

    // Monday 8:59 — before window start
    @Test func beforeWindowStart() {
        let date = makeDate(weekday: .monday, hour: 8, minute: 59)
        #expect(!scheduler.isWithinHours(date, weekdays: weekdays(.monday), startHour: 9, endHour: 18))
    }

    // Monday 18:00 — at end boundary, should be outside (endHour is exclusive)
    @Test func atWindowEnd() {
        let date = makeDate(weekday: .monday, hour: 18, minute: 0)
        #expect(!scheduler.isWithinHours(date, weekdays: weekdays(.monday), startHour: 9, endHour: 18))
    }

    // Monday 9:00 — at start boundary, should be inside
    @Test func atWindowStart() {
        let date = makeDate(weekday: .monday, hour: 9, minute: 0)
        #expect(scheduler.isWithinHours(date, weekdays: weekdays(.monday), startHour: 9, endHour: 18))
    }

    // startHour == endHour means all-day
    @Test func equalStartEndMeansAllDay() {
        let date = makeDate(weekday: .monday, hour: 3, minute: 0)
        #expect(scheduler.isWithinHours(date, weekdays: weekdays(.monday), startHour: 9, endHour: 9))
    }

    // Empty weekdays set — always false
    @Test func emptyWeekdays() {
        let date = makeDate(weekday: .monday, hour: 10, minute: 0)
        #expect(!scheduler.isWithinHours(date, weekdays: [], startHour: 9, endHour: 18))
    }

    // Overnight window: 22–6, Monday 23:00 — inside
    @Test func overnightWindowWithinOnStartDay() {
        let date = makeDate(weekday: .monday, hour: 23, minute: 0)
        #expect(scheduler.isWithinHours(date, weekdays: weekdays(.monday), startHour: 22, endHour: 6))
    }

    // Overnight window: 22–6, Tuesday 2:00 — inside if Monday is in weekdays (previous day)
    @Test func overnightWindowEarlyHourPreviousDayInSet() {
        let date = makeDate(weekday: .tuesday, hour: 2, minute: 0)
        #expect(scheduler.isWithinHours(date, weekdays: weekdays(.monday), startHour: 22, endHour: 6))
    }

    // Overnight window: 22–6, Tuesday 2:00 — outside if only Tuesday is in weekdays (previous day not in set)
    @Test func overnightWindowEarlyHourPreviousDayNotInSet() {
        let date = makeDate(weekday: .tuesday, hour: 2, minute: 0)
        #expect(!scheduler.isWithinHours(date, weekdays: weekdays(.tuesday), startHour: 22, endHour: 6))
    }
}

// MARK: - nextWindowStart

@Suite("nextWindowStart")
struct NextWindowStartTests {
    let scheduler = BreakScheduler()

    // Tuesday 10:00, next Mon–Fri 9:00 start → Wednesday 9:00
    @Test func nextStartIsNextDay() {
        let now = makeDate(weekday: .tuesday, hour: 10, minute: 0)
        let result = scheduler.nextWindowStart(after: now, weekdays: weekdays(.monday, .tuesday, .wednesday, .thursday, .friday), startHour: 9)
        let expected = makeDate(weekday: .wednesday, hour: 9, minute: 0)
        #expect(result == expected)
    }

    // Friday 10:00, next Mon–Fri 9:00 start → Monday 9:00 (next week)
    @Test func nextStartSkipsWeekend() {
        let now = makeDate(weekday: .friday, hour: 10, minute: 0)
        let result = scheduler.nextWindowStart(after: now, weekdays: weekdays(.monday, .tuesday, .wednesday, .thursday, .friday), startHour: 9)
        let expected = makeDate(weekday: .monday, hour: 9, minute: 0, weeksAhead: 1)
        #expect(result == expected)
    }

    // Empty weekdays → nil
    @Test func emptyWeekdaysReturnsNil() {
        let now = makeDate(weekday: .monday, hour: 10, minute: 0)
        #expect(scheduler.nextWindowStart(after: now, weekdays: [], startHour: 9) == nil)
    }

    // Monday 8:00, window starts 9:00 same day → same-day result
    @Test func nextStartSameDayBeforeWindow() {
        let now = makeDate(weekday: .monday, hour: 8, minute: 0)
        let result = scheduler.nextWindowStart(after: now, weekdays: weekdays(.monday), startHour: 9)
        let expected = makeDate(weekday: .monday, hour: 9, minute: 0)
        #expect(result == expected)
    }
}

// MARK: - currentWindowEnd

@Suite("currentWindowEnd")
struct CurrentWindowEndTests {
    let scheduler = BreakScheduler()

    // Monday 10:00, window 9–18 → end is Monday 18:00
    @Test func endIsSameDay() {
        let date = makeDate(weekday: .monday, hour: 10, minute: 0)
        let result = scheduler.currentWindowEnd(containing: date, weekdays: weekdays(.monday), startHour: 9, endHour: 18)
        let expected = makeDate(weekday: .monday, hour: 18, minute: 0)
        #expect(result == expected)
    }

    // Saturday 10:00, window Mon–Fri 9–18 → nil (not in any window)
    @Test func returnsNilWhenOutsideWeekdays() {
        let date = makeDate(weekday: .saturday, hour: 10, minute: 0)
        let result = scheduler.currentWindowEnd(containing: date, weekdays: weekdays(.monday, .tuesday, .wednesday, .thursday, .friday), startHour: 9, endHour: 18)
        #expect(result == nil)
    }

    // Overnight Monday 23:00 in Mon 22–6 window → end is Tuesday 6:00
    @Test func overnightWindowEndIsNextDay() {
        let date = makeDate(weekday: .monday, hour: 23, minute: 0)
        let result = scheduler.currentWindowEnd(containing: date, weekdays: weekdays(.monday), startHour: 22, endHour: 6)
        let expected = makeDate(weekday: .tuesday, hour: 6, minute: 0)
        #expect(result == expected)
    }
}

// MARK: - runtimeBlocker

@Suite("runtimeBlocker")
struct RuntimeBlockerTests {
    var scheduler: BreakScheduler!

    init() {
        scheduler = BreakScheduler()
        // Reset to a known state
        scheduler.scheduleEnabled = false
        scheduler.focusBlocksEnabled = false
        scheduler.delayDuringMeetings = false
        scheduler.manualPauseEnabled = false
    }

    @Test func noneWhenAllDisabled() {
        let now = makeDate(weekday: .monday, hour: 10, minute: 0)
        if case .none = scheduler.runtimeBlocker(for: now) {
            // pass
        } else {
            #expect(Bool(false), "Expected .none blocker")
        }
    }

    @Test func pausedWhenManuallyPaused() {
        scheduler.manualPauseEnabled = true
        let now = makeDate(weekday: .monday, hour: 10, minute: 0)
        if case .paused = scheduler.runtimeBlocker(for: now) {
            // pass
        } else {
            #expect(Bool(false), "Expected .paused blocker")
        }
    }

    @Test func outsideScheduleWhenScheduleEnabledAndOutside() {
        scheduler.scheduleEnabled = true
        scheduler.scheduleStartHour = 9
        scheduler.scheduleEndHour = 18
        scheduler.activeWeekdays = weekdays(.monday, .tuesday, .wednesday, .thursday, .friday)
        // Saturday is outside the schedule
        let saturday = makeDate(weekday: .saturday, hour: 10, minute: 0)
        if case .outsideSchedule = scheduler.runtimeBlocker(for: saturday) {
            // pass
        } else {
            #expect(Bool(false), "Expected .outsideSchedule blocker")
        }
    }

    @Test func focusWhenInsideFocusBlock() {
        scheduler.focusBlocksEnabled = true
        scheduler.focusBlockWindows = [
            BreakScheduler.FocusBlockWindow(name: "Focus Time", startHour: 10, endHour: 12, weekdays: weekdays(.monday))
        ]
        let monday10h30 = makeDate(weekday: .monday, hour: 10, minute: 30)
        if case .focus = scheduler.runtimeBlocker(for: monday10h30) {
            // pass
        } else {
            #expect(Bool(false), "Expected .focus blocker")
        }
    }

    // Pause takes priority over schedule
    @Test func pausePriorityOverSchedule() {
        scheduler.manualPauseEnabled = true
        scheduler.scheduleEnabled = true
        scheduler.scheduleStartHour = 9
        scheduler.scheduleEndHour = 18
        scheduler.activeWeekdays = weekdays(.monday, .tuesday, .wednesday, .thursday, .friday)
        let saturday = makeDate(weekday: .saturday, hour: 10, minute: 0)
        if case .paused = scheduler.runtimeBlocker(for: saturday) {
            // pass
        } else {
            #expect(Bool(false), "Expected .paused to win over .outsideSchedule")
        }
    }
}

// MARK: - effectiveIntervalSeconds

@Suite("effectiveIntervalSeconds")
struct EffectiveIntervalTests {
    @Test func returnsBaseIntervalWithNoModifiers() {
        let scheduler = BreakScheduler()
        scheduler.intervalOption = .min25
        scheduler.deviceAwareModeEnabled = false
        scheduler.reduceIntensityOnBattery = false
        // selectedSetupPreset must be nil for device-aware to apply; but preset=nil + no modifiers
        scheduler.selectedSetupPreset = nil
        #expect(scheduler.effectiveIntervalSeconds == 25 * 60)
    }

    @Test func presetBypassesDeviceAware() {
        let scheduler = BreakScheduler()
        scheduler.intervalOption = .min25
        scheduler.deviceAwareModeEnabled = true
        // Forcing a preset means device-aware is ignored
        scheduler.selectedSetupPreset = .pomodoro
        // Without real hardware we can't confirm the display check, but preset path returns base value
        #expect(scheduler.effectiveIntervalSeconds == 25 * 60)
    }
}

// MARK: - Helpers

private func makeDate(weekday: BreakScheduler.Weekday, hour: Int, minute: Int, weeksAhead: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US")
    // Find the next occurrence of this weekday from a fixed reference (2026-01-05 = Monday)
    let reference = DateComponents(calendar: calendar, year: 2026, month: 1, day: 5).date!
    let targetWeekday = weekday.rawValue // 1=Sun, 2=Mon, …
    let refWeekday = calendar.component(.weekday, from: reference)
    var delta = targetWeekday - refWeekday
    if delta < 0 { delta += 7 }
    delta += weeksAhead * 7
    let targetDay = calendar.date(byAdding: .day, value: delta, to: reference)!
    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay)!
}

private func weekdays(_ days: BreakScheduler.Weekday...) -> Set<Int> {
    Set(days.map(\.rawValue))
}
