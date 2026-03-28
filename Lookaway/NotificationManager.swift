import Foundation
import UserNotifications

@MainActor
final class NotificationManager {
    private static let preAlertIdentifier = "lookaway.preAlert"
    private var isAuthorized = false

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .notDetermined:
                    // Request without sound
                    try? await center.requestAuthorization(options: [.alert, .badge])
                    self.isAuthorized = true
                case .authorized, .provisional, .ephemeral:
                    self.isAuthorized = true
                default:
                    self.isAuthorized = false
                }
            }
        }
    }

    func sendPreAlert(style: BreakScheduler.BreakStyle, secondsRemaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Break in \(secondsRemaining)s"
        content.body = style.title + " is starting soon."
        // No sound — per project constraint
        content.sound = nil

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.preAlertIdentifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func cancelPreAlert() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.preAlertIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.preAlertIdentifier])
    }
}
