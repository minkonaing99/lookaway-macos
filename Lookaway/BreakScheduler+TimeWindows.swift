import EventKit
import Foundation

extension BreakScheduler {
    func runtimeBlocker(for date: Date) -> RuntimeBlocker {
        if isPaused && !isRunningBreakTest {
            return .paused
        }
        if scheduleEnabled, !isWithinSchedule(date) {
            return .outsideSchedule(nextStart: nextScheduleStart(after: date))
        }
        if focusBlocksEnabled, isWithinFocusBlock(date) {
            return .focus(until: currentFocusBlockEnd(for: date))
        }
        if delayDuringMeetings, let event = currentBlockingMeeting(at: date) {
            return .meeting(until: event.endDate, title: event.title)
        }
        return .none
    }

    func softlyRescheduleIfNeeded(for blocker: RuntimeBlocker, now: Date) {
        guard now >= nextBreakDate else { return }

        switch blocker {
        case .paused:
            return
        case .outsideSchedule(let nextStart):
            guard let nextStart else { return }
            let newBase = nextStart
            let target = newBase.addingTimeInterval(effectiveIntervalSeconds)
            if abs(target.timeIntervalSince(nextBreakDate)) > 1 {
                nextBreakDate = target
                preAlertTriggeredThisCycle = false
                lastBreakReasonText = "Restarted cycle after schedule gap"
                refreshDerivedState(now: now)
            }
        case .focus(let until):
            guard let until else { return }
            let delay = max(0, until.timeIntervalSince(now))
            let target = delay <= shortBlockThreshold ? until.addingTimeInterval(60) : until.addingTimeInterval(effectiveIntervalSeconds)
            if abs(target.timeIntervalSince(nextBreakDate)) > 1 {
                nextBreakDate = target
                preAlertTriggeredThisCycle = false
                lastBreakReasonText = delay <= shortBlockThreshold ? "Postponed break until focus block ended" : "Restarted cycle after long focus block"
                refreshDerivedState(now: now)
            }
        case .meeting(let until, _):
            guard let until else { return }
            let delay = max(0, until.timeIntervalSince(now))
            let target = delay <= shortBlockThreshold ? until.addingTimeInterval(60) : until.addingTimeInterval(effectiveIntervalSeconds)
            if abs(target.timeIntervalSince(nextBreakDate)) > 1 {
                nextBreakDate = target
                preAlertTriggeredThisCycle = false
                lastBreakReasonText = delay <= shortBlockThreshold ? "Postponed break until meeting ended" : "Restarted cycle after long meeting"
                refreshDerivedState(now: now)
            }
        case .none:
            return
        }
    }

    func isWithinSchedule(_ date: Date) -> Bool {
        isWithinHours(date, weekdays: activeWeekdays, startHour: scheduleStartHour, endHour: scheduleEndHour)
    }

    func isWithinFocusBlock(_ date: Date) -> Bool {
        focusBlockWindows.contains { window in
            isWithinHours(date, weekdays: window.weekdays, startHour: window.startHour, endHour: window.endHour)
        }
    }

    func isWithinHours(_ date: Date, weekdays: Set<Int>, startHour: Int, endHour: Int) -> Bool {
        guard !weekdays.isEmpty else { return false }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        if startHour == endHour { return true }

        if startHour < endHour {
            guard weekdays.contains(weekday) else { return false }
            return hour >= startHour && hour < endHour
        }

        if hour >= startHour {
            return weekdays.contains(weekday)
        }

        guard hour < endHour else { return false }
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
        let previousWeekday = calendar.component(.weekday, from: previousDay)
        return weekdays.contains(previousWeekday)
    }

    func nextScheduleStart(after date: Date) -> Date? {
        guard scheduleEnabled, !activeWeekdays.isEmpty else { return nil }
        return nextWindowStart(after: date, weekdays: activeWeekdays, startHour: scheduleStartHour)
    }

    func currentFocusBlockEnd(for date: Date) -> Date? {
        for window in focusBlockWindows {
            if isWithinHours(date, weekdays: window.weekdays, startHour: window.startHour, endHour: window.endHour) {
                return currentWindowEnd(containing: date, weekdays: window.weekdays, startHour: window.startHour, endHour: window.endHour)
            }
        }
        return nil
    }

    func nextWindowStart(after date: Date, weekdays: Set<Int>, startHour: Int) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            guard weekdays.contains(weekday) else { continue }

            guard let candidate = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day) else { continue }
            if candidate > date {
                return candidate
            }
        }
        return nil
    }

    func currentWindowEnd(containing date: Date, weekdays: Set<Int>, startHour: Int, endHour: Int) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        if startHour == endHour {
            return calendar.date(byAdding: .day, value: 1, to: startOfDay)
        }

        if startHour < endHour {
            let weekday = calendar.component(.weekday, from: date)
            guard weekdays.contains(weekday) else { return nil }
            return calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: startOfDay)
        }

        let hour = calendar.component(.hour, from: date)
        if hour >= startHour {
            let weekday = calendar.component(.weekday, from: date)
            guard weekdays.contains(weekday) else { return nil }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
            return calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: nextDay)
        }

        guard hour < endHour else { return nil }
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return nil }
        let previousWeekday = calendar.component(.weekday, from: previousDay)
        guard weekdays.contains(previousWeekday) else { return nil }
        return calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: startOfDay)
    }
}
