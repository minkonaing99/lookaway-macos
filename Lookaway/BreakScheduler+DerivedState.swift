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
        refreshDerivedState(now: now, blocker: runtimeBlocker(for: now))
    }

    func refreshDerivedState(now: Date, blocker: RuntimeBlocker) {
        refreshCalendarStatus(now: now)
        updateCountdownLabels(now: now, blocker: blocker)
        updateStatusTexts(now: now, blocker: blocker)
        let newClockText = Self.clockFormatter.string(from: nextBreakDate)
        if nextBreakClockText != newClockText { nextBreakClockText = newClockText }
    }

    func updateCountdownLabels(now: Date, blocker: RuntimeBlocker) {
        let remaining: String
        let countdown: String
        let status: String

        if isShowingBreak {
            remaining = "Break now"; countdown = "Break"; status = "Break"
        } else {
            switch blocker {
            case .paused:
                remaining = "Paused"; countdown = "Paused"; status = "Paused"
            case .outsideSchedule:
                remaining = "Off schedule"; countdown = "Off"; status = "Off"
            case .focus:
                remaining = "Focus block"; countdown = "Focus"; status = "Focus"
            case .meeting:
                remaining = "Meeting active"; countdown = "Meeting"; status = "Meeting"
            case .none:
                let secs = max(0, nextBreakDate.timeIntervalSince(now))
                let minutes = max(0, Int(ceil(secs / 60.0)))
                remaining = minutes == 1 ? "1 min" : "\(minutes) min"
                countdown = "\(minutes)m"
                status = secs <= 60 ? "Soon" : "Working"
            }
        }

        if timeRemainingMinutesText != remaining { timeRemainingMinutesText = remaining }
        if menuBarCountdownText != countdown { menuBarCountdownText = countdown }
        if menuBarStatusText != status { menuBarStatusText = status }

        let progress: Double
        if isShowingBreak {
            progress = 1
        } else if case .none = blocker {
            let secs = max(0, nextBreakDate.timeIntervalSince(now))
            progress = Self.quantizedProgress(remaining: secs, interval: currentCycleIntervalSeconds)
        } else {
            progress = 0
        }
        if menuBarProgressFraction != progress { menuBarProgressFraction = progress }
    }

    func updateStatusTexts(now: Date, blocker: RuntimeBlocker) {
        let title: String
        let explanation: String
        let blockerText: String

        switch blocker {
        case .paused:
            title = "Paused"
            explanation = "LookAway is paused because the Mac is locked, sleeping, or you paused reminders manually."
            blockerText = "Paused"
        case .outsideSchedule(let nextStart):
            title = "Outside schedule"
            if let nextStart {
                explanation = "Reminders resume at \(Self.dayTimeFormatter.string(from: nextStart))."
                blockerText = "Outside schedule until \(Self.dayTimeFormatter.string(from: nextStart))"
            } else {
                explanation = "No active work hours are available with the current schedule."
                blockerText = "Outside schedule"
            }
        case .focus(let until):
            title = "Focus block active"
            if let until {
                explanation = "LookAway is holding the next break until your focus block ends at \(Self.clockFormatter.string(from: until))."
                blockerText = "Focus block until \(Self.clockFormatter.string(from: until))"
            } else {
                explanation = "LookAway is holding the next break because focus mode is active."
                blockerText = "Focus block"
            }
        case .meeting(let until, let meetingTitle):
            title = "In a calendar event"
            let meetingLabel = meetingTitle?.isEmpty == false ? meetingTitle! : "Current meeting"
            if let until {
                explanation = "LookAway will wait until \(meetingLabel) ends at \(Self.clockFormatter.string(from: until))."
                blockerText = "Meeting until \(Self.clockFormatter.string(from: until))"
            } else {
                explanation = "LookAway is waiting for the current meeting to finish."
                blockerText = "Meeting active"
            }
        case .none:
            title = isInPreAlert ? "Break soon" : "Working"
            blockerText = "No blocker"
            if isInPreAlert {
                switch preAlertPresentation {
                case .pointerCountdown:
                    explanation = "Countdown is active near the pointer. Break starts at \(nextBreakClockText)."
                case .centerBanner:
                    explanation = "A soft center-screen banner is active. Break starts at \(nextBreakClockText)."
                case .notification:
                    explanation = "A system notification has been sent. Break starts at \(nextBreakClockText)."
                case .screenDim:
                    explanation = "The screen is gently dimming. Break starts at \(nextBreakClockText)."
                }
            } else {
                explanation = "Next coffee reset is scheduled for \(nextBreakClockText)."
            }
        }

        if currentStateTitle != title { currentStateTitle = title }
        if currentStateExplanation != explanation { currentStateExplanation = explanation }
        if currentBlockerText != blockerText { currentBlockerText = blockerText }
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
