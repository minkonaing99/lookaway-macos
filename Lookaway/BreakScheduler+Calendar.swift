import EventKit
import Foundation

extension BreakScheduler {
    func requestCalendarAccessIfNeeded(forcePromptIfPossible: Bool = false) {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            calendarStatusText = "Connected"
            calendarDetailText = currentMeetingText == "No active meeting" ? "LookAway can delay breaks during active meetings." : currentMeetingText
        case .writeOnly:
            calendarStatusText = "Write-only access"
            calendarDetailText = "Meeting detection needs full calendar access."
        case .denied, .restricted:
            calendarStatusText = "Access denied"
            calendarDetailText = "Enable Calendars access in System Settings > Privacy & Security > Calendars."
        case .notDetermined:
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let granted = try await self.eventStore.requestFullAccessToEvents()
                    self.calendarStatusText = granted ? "Connected" : "Access denied"
                    self.refreshCalendarStatus(now: .now)
                    self.refreshDerivedState(now: .now)
                } catch {
                    self.calendarStatusText = "Request failed"
                    self.calendarDetailText = error.localizedDescription
                }
            }
        @unknown default:
            calendarStatusText = "Unknown status"
            calendarDetailText = "Calendar authorization returned an unknown state."
        }

        if forcePromptIfPossible, status == .fullAccess {
            refreshCalendarStatus(now: .now)
        }
    }

    func refreshCalendarStatus(now: Date) {
        let status = EKEventStore.authorizationStatus(for: .event)
        var newStatus = ""
        var newMeeting = ""
        var newDetail = ""

        switch status {
        case .fullAccess:
            newStatus = "Connected"
            if let event = currentBlockingMeeting(at: now) {
                newMeeting = "In meeting until \(Self.clockFormatter.string(from: event.endDate))"
                let title = event.title?.isEmpty == false ? event.title! : "Current event"
                newDetail = "\(title) ends at \(Self.clockFormatter.string(from: event.endDate))."
            } else {
                newMeeting = "No active meeting"
                newDetail = "LookAway can delay breaks during active meetings."
            }
        case .writeOnly:
            newStatus = "Write-only access"
            newMeeting = "Meeting detection unavailable"
            newDetail = "Grant full access to let LookAway skip breaks during events."
        case .denied, .restricted:
            newStatus = "Access denied"
            newMeeting = "Meeting detection unavailable"
            newDetail = "Enable access in System Settings > Privacy & Security > Calendars."
        case .notDetermined:
            newStatus = "Calendar not connected"
            newMeeting = "No active meeting"
            newDetail = "Request access to let LookAway avoid interrupting meetings."
        @unknown default:
            newStatus = "Unknown status"
            newMeeting = "Meeting detection unavailable"
            newDetail = "Calendar authorization returned an unknown state."
        }

        if calendarStatusText != newStatus { calendarStatusText = newStatus }
        if currentMeetingText != newMeeting { currentMeetingText = newMeeting }
        if calendarDetailText != newDetail { calendarDetailText = newDetail }
    }

    func currentBlockingMeeting(at date: Date) -> EKEvent? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }

        if date.timeIntervalSince(meetingCacheTimestamp) < 300 {
            return cachedMeetingEvent
        }

        let lookBack: TimeInterval = 5 * 60
        let lookAhead: TimeInterval = 8 * 60 * 60
        let start = date.addingTimeInterval(-lookBack)
        let end = date.addingTimeInterval(lookAhead)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)

        var matchingEvents: [EKEvent] = []
        for event in events {
            guard !event.isAllDay else { continue }
            guard event.startDate <= date, event.endDate > date else { continue }
            guard event.availability != .free else { continue }
            if onlyAcceptedCalendarEvents {
                guard event.status != .canceled else { continue }
                guard event.status == .confirmed || event.status == .none else { continue }
            }
            matchingEvents.append(event)
        }

        cachedMeetingEvent = matchingEvents.sorted { $0.endDate < $1.endDate }.first

        meetingCacheTimestamp = date
        return cachedMeetingEvent
    }
}
