#if DEBUG
import Foundation
@preconcurrency import UserNotifications

@MainActor
enum ReminderProbe {
    static func askPermissionIfAsked() async {
        guard LaunchOptions.contains("-ReminderProbe") else { return }
        _ = await Reminders.requestPermission()
    }
    // Scheduled on backgrounding so the banner always lands on the Home Screen,
    // however slowly the app launched.
    static func scheduleIfAsked(events: EventStore) async {
        guard LaunchOptions.contains("-ReminderProbe"), let pet = events.pet else { return }
        let content = UNMutableNotificationContent()
        content.title = "Daily tablet"
        content.body = "Open Now to check the last dose and sync time."
        content.categoryIdentifier = "pet.medication"
        content.sound = .default
        content.userInfo = ["route": "now", "petID": pet.id.uuidString, "itemID": events.petMedications.first?.id.uuidString ?? ""]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pet.reminder-probe", content: content, trigger: trigger))
    }
}
#endif
