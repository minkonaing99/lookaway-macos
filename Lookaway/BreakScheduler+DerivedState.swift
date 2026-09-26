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
        let newClockText = Self.clockFormatter.string(from: nextBreakDate)
        if nextBreakClockText != newClockText { nextBreakClockText = newClockText }
        updateCountdownLabels(now: now, blocker: blocker)
        updateStatusTexts(now: now, blocker: blocker)
        updateWorkSession(now: now)
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
            explanation = manualPauseEnabled
                ? manualPauseExplanation
                : "Reminders resume automatically when these conditions clear."
            blockerText = pauseReasonText
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
            title = inputDeferralStartedAt != nil ? "Waiting for a pause" : (isInPreAlert ? "Break soon" : "Working")
            blockerText = inputDeferralStartedAt != nil ? "Finishing your input" : "No blocker"
            if let start = inputDeferralStartedAt {
                let remaining = max(0, Int(ceil(30 - now.timeIntervalSince(start))))
                explanation = "Waiting for a 3-second input gap. Break starts within \(remaining) seconds."
            } else if isInPreAlert {
                switch preAlertPresentation {
                case .centerBanner:
                    explanation = "A soft center-screen banner is active. Break starts at \(nextBreakClockText)."
                case .notification:
                    explanation = "A system notification has been sent. Break starts at \(nextBreakClockText)."
                }
            } else {
                explanation = "Next break is scheduled for \(nextBreakClockText)."
            }
        }

        if isShowingBreak {
            currentStateTitle = activeBreakIsLong ? "Taking a long break" : "Taking a break"
            currentStateExplanation = "Your next work cycle starts when this break ends."
            currentBlockerText = "Break in progress"
            return
        }
        if currentStateTitle != title { currentStateTitle = title }
        if currentStateExplanation != explanation { currentStateExplanation = explanation }
        if currentBlockerText != blockerText { currentBlockerText = blockerText }
    }

    var pauseReasonText: String {
        let reasons = [
            ("sleep", "Mac sleeping"), ("session", "Mac locked"),
            ("idle", "No recent activity"), ("frontmostApp", "An excluded app is active"),
            ("webcam", "Camera in use")
        ].compactMap { autoPauseReasons.contains($0.0) ? $0.1 : nil }
        return ((manualPauseEnabled ? ["Paused manually"] : []) + reasons).joined(separator: "; ")
    }

    var showsNextBreakTime: Bool {
        !isShowingBreak && (currentStateTitle == "Working" || currentStateTitle == "Break soon")
    }

    var showsCalendarAttention: Bool {
        delayDuringMeetings && calendarStatusText != "Connected"
    }

    var cadenceExplanation: String {
        let current = String(format: "%.1f", currentCycleIntervalSeconds / 60)
        let next = String(format: "%.1f", effectiveIntervalSeconds / 60)
        if adaptiveIntervalsEnabled {
            return "Current cycle: \(current) min. Next cycle estimate: \(next) min. Activity adjusts each new cycle from 15% shorter to 20% longer. The current deadline stays fixed."
        }
        return "New cycles: \(intervalOption.title). Current cycle: \(current) min. Power and displays never change break timing."
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
