import Foundation
@preconcurrency import UserNotifications

struct PlannedReminder: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let body: String
    let date: Date
    let isMedication: Bool
    let itemID: UUID
    let petID: UUID
    var category: String { isMedication ? "pet.medication" : "pet.due" }
    var actions: [String] { isMedication ? [] : ["MARK_DONE"] }
}

enum ReminderPlanner {
    static func plan(medications: [Medication], items: [DueItem], events: [EventRecord], phoneID: String,
                     writablePets: Set<UUID>, now: Date, calendar: Calendar = .current) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        for med in medications where med.remindersEnabled && med.reminderPhoneID == phoneID && writablePets.contains(med.petID) {
            for offset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                for slot in ScheduleEngine.slots(for: med, on: day, events: events, calendar: calendar) where slot.pending && slot.scheduledAt > now {
                    result.append(PlannedReminder(id: "med.\(slot.id)", title: med.name,
                        body: "Open Now to check the last dose and sync time.", date: slot.scheduledAt, isMedication: true, itemID: med.id, petID: med.petID))
                }
            }
        }
        for item in items where item.remindersEnabled && writablePets.contains(item.petID) {
            for due in DueEngine.occurrences(for: item, from: now, days: 30, events: events, calendar: calendar) where !due.completed && due.date > now {
                result.append(PlannedReminder(id: "due.\(due.id)", title: item.name, body: "Due now", date: due.date,
                                               isMedication: false, itemID: item.id, petID: item.petID))
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(60))
    }
}

@MainActor
enum Reminders {
    private static var generation = 0
    static func register() {
        let done = UNNotificationAction(identifier: "MARK_DONE", title: "Mark done")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "pet.medication", actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: "pet.due", actions: [done], intentIdentifiers: [])
        ])
    }
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }
    static func schedule(store: EventStore) {
        guard !LaunchOptions.contains("-UITesting") else { return }
        let writable = Set(store.pets.enumerated().filter { store.access.canWrite(petIndex: $0.offset, at: .now) }.map { $0.element.id })
        let planned = ReminderPlanner.plan(medications: store.medications, items: store.dueItems, events: store.events,
                                          phoneID: store.phoneID, writablePets: writable, now: .now)
        generation += 1
        let current = generation
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard current == generation else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("med.") || $0.identifier.hasPrefix("due.") }.map(\.identifier))
            for item in planned {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                content.categoryIdentifier = item.category
                content.userInfo = ["route": "now", "itemID": item.itemID.uuidString, "petID": item.petID.uuidString, "scheduledAt": item.date.timeIntervalSince1970]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.date.timeIntervalSinceNow), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }
}
