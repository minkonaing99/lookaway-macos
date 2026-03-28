import Foundation

extension BreakScheduler {
    var timeRemainingText: String {
        timeRemainingMinutesText
    }

    var preferencesSummaryTitle: String {
        "\(intervalOption.title) work cadence"
    }

    var preferencesSummaryText: String {
        [
            "Break for \(restDurationOption.title)",
            scheduleEnabled ? scheduleSummaryText : "All-day reminders",
            delayDuringMeetings ? "Calendar-aware" : "Calendar off",
            focusBlocksEnabled ? focusSummaryText : "No focus blocks"
        ].joined(separator: " • ")
    }

    func refreshDerivedState(now: Date) {
        refreshCalendarStatus(now: now)
        let blocker = runtimeBlocker(for: now)
        updateCountdownLabels(now: now, blocker: blocker)
        updateStatusTexts(now: now, blocker: blocker)
        nextBreakClockText = Self.clockFormatter.string(from: nextBreakDate)
    }

    func updateCountdownLabels(now: Date, blocker: RuntimeBlocker) {
        if isShowingBreak {
            timeRemainingMinutesText = "Break now"
            menuBarCountdownText = "Break"
            menuBarStatusText = "Break"
            return
        }

        switch blocker {
        case .paused:
            timeRemainingMinutesText = "Paused"
            menuBarCountdownText = "Paused"
            menuBarStatusText = "Paused"
            return
        case .outsideSchedule:
            timeRemainingMinutesText = "Off schedule"
            menuBarCountdownText = "Off"
            menuBarStatusText = "Off"
            return
        case .focus:
            timeRemainingMinutesText = "Focus block"
            menuBarCountdownText = "Focus"
            menuBarStatusText = "Focus"
            return
        case .meeting:
            timeRemainingMinutesText = "Meeting active"
            menuBarCountdownText = "Meeting"
            menuBarStatusText = "Meeting"
            return
        case .none:
            break
        }

        let remaining = max(0, nextBreakDate.timeIntervalSince(now))
        let minutes = max(0, Int(ceil(remaining / 60.0)))
        timeRemainingMinutesText = minutes == 1 ? "1 min" : "\(minutes) min"
        menuBarCountdownText = "\(minutes)m"
        menuBarStatusText = remaining <= 60 ? "Soon" : "Working"
    }

    func updateStatusTexts(now: Date, blocker: RuntimeBlocker) {
        switch blocker {
        case .paused:
            currentStateTitle = "Paused"
            currentStateExplanation = "LookAway is paused because the Mac is locked, sleeping, or you paused reminders manually."
            currentBlockerText = "Paused"
        case .outsideSchedule(let nextStart):
            currentStateTitle = "Outside schedule"
            if let nextStart {
                currentStateExplanation = "Reminders resume at \(Self.dayTimeFormatter.string(from: nextStart))."
                currentBlockerText = "Outside schedule until \(Self.dayTimeFormatter.string(from: nextStart))"
            } else {
                currentStateExplanation = "No active work hours are available with the current schedule."
                currentBlockerText = "Outside schedule"
            }
        case .focus(let until):
            currentStateTitle = "Focus block active"
            if let until {
                currentStateExplanation = "LookAway is holding the next break until your focus block ends at \(Self.clockFormatter.string(from: until))."
                currentBlockerText = "Focus block until \(Self.clockFormatter.string(from: until))"
            } else {
                currentStateExplanation = "LookAway is holding the next break because focus mode is active."
                currentBlockerText = "Focus block"
            }
        case .meeting(let until, let title):
            currentStateTitle = "In a calendar event"
            let meetingLabel = title?.isEmpty == false ? title! : "Current meeting"
            if let until {
                currentStateExplanation = "LookAway will wait until \(meetingLabel) ends at \(Self.clockFormatter.string(from: until))."
                currentBlockerText = "Meeting until \(Self.clockFormatter.string(from: until))"
            } else {
                currentStateExplanation = "LookAway is waiting for the current meeting to finish."
                currentBlockerText = "Meeting active"
            }
        case .none:
            currentStateTitle = isInPreAlert ? "Break soon" : "Working"
            if isInPreAlert {
                switch preAlertPresentation {
                case .pointerCountdown:
                    currentStateExplanation = "Countdown is active near the pointer. Break starts at \(nextBreakClockText)."
                case .centerBanner:
                    currentStateExplanation = "A soft center-screen banner is active. Break starts at \(nextBreakClockText)."
                case .notification:
                    currentStateExplanation = "A system notification has been sent. Break starts at \(nextBreakClockText)."
                }
            } else {
                currentStateExplanation = "Next coffee reset is scheduled for \(nextBreakClockText)."
            }
            currentBlockerText = "No blocker"
        }
    }

    var scheduleSummaryText: String {
        guard scheduleEnabled else { return "All-day reminders" }
        let selectedDays = Weekday.allCases
            .filter { activeWeekdays.contains($0.rawValue) }
            .map(\.shortTitle)
            .joined(separator: ", ")
        return "\(Self.hourText(scheduleStartHour)) - \(Self.hourText(scheduleEndHour)) on \(selectedDays)"
    }

    var focusSummaryText: String {
        guard focusBlocksEnabled else { return "No focus blocks" }
        if focusBlockWindows.isEmpty { return "No focus windows configured" }
        if focusBlockWindows.count == 1 {
            let w = focusBlockWindows[0]
            let days = Weekday.allCases
                .filter { w.weekdays.contains($0.rawValue) }
                .map(\.shortTitle)
                .joined(separator: ", ")
            return "\(Self.hourText(w.startHour)) – \(Self.hourText(w.endHour)) on \(days)"
        }
        return "\(focusBlockWindows.count) focus windows active"
    }

    static func hourText(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static let dayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()
}
