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
        guard meetingEventsProvider != nil || EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        if date < meetingCacheTimestamp || date.timeIntervalSince(meetingCacheTimestamp) >= 300 {
            cachedMeetingEvents = meetingEventsProvider?(date) ?? fetchMeetingEvents(at: date)
            meetingCacheTimestamp = date
        }
        return cachedMeetingEvents.filter { event in
            guard !event.isAllDay, event.startDate <= date, event.endDate > date,
                  event.availability != .free, event.status != .canceled else { return false }
            return !onlyAcceptedCalendarEvents || event.status == .confirmed || event.status == .none
        }.min { $0.endDate < $1.endDate }
    }

    private func fetchMeetingEvents(at date: Date) -> [EKEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: date.addingTimeInterval(-300),
            end: date.addingTimeInterval(8 * 60 * 60), calendars: nil
        )
        return eventStore.events(matching: predicate)
    }
}
