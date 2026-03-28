import SwiftUI

@main
struct LookawayApp: App {
    @StateObject private var scheduler = BreakScheduler()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(scheduler: scheduler)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesContentView(scheduler: scheduler)
                .frame(minWidth: 860, minHeight: 660)
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        let symbol = menuBarSymbolName

        switch scheduler.menuBarMode {
        case .iconOnly:
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
        case .iconAndMinutes:
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                Text(menuBarMinutesText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        case .iconAndStatus:
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                Text(menuBarStatusLabel)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
    }

    private var menuBarSymbolName: String {
        if scheduler.showBreakCompletionBadge {
            return "checkmark.circle.fill"
        }

        let title = scheduler.currentStateTitle

        if title == "Paused" {
            return "pause.circle.fill"
        }
        if title == "Outside schedule" {
            return "moon.zzz.fill"
        }
        if title == "Focus block active" {
            return "moon.stars.fill"
        }
        if title == "In a calendar event" {
            return "calendar.badge.clock"
        }
        if title == "Break soon" {
            return "bell.badge.fill"
        }
        return "cup.and.saucer.fill"
    }

    private var menuBarMinutesText: String {
        switch scheduler.currentStateTitle {
        case "Paused":
            return "Pause"
        case "Outside schedule":
            return "Off"
        case "Focus block active":
            return "Focus"
        case "In a calendar event":
            return "Meet"
        case "Break soon":
            return scheduler.menuBarCountdownText
        default:
            return scheduler.menuBarCountdownText
        }
    }

    private var menuBarStatusLabel: String {
        switch scheduler.currentStateTitle {
        case "Paused":
            return "Paused"
        case "Outside schedule":
            return "Off Hours"
        case "Focus block active":
            return "Focus"
        case "In a calendar event":
            return "Meeting"
        case "Break soon":
            return "Break Soon"
        default:
            return scheduler.menuBarStatusText
        }
    }
}
