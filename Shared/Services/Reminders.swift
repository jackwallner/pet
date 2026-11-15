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
    /// The "open the app to keep reminders" notice: no dose, no slot, no action.
    var isRenewal = false
    var category: String { isRenewal ? "pet.renewal" : isMedication ? "pet.medication" : "pet.due" }
    var actions: [String] { isMedication || isRenewal ? [] : ["MARK_DONE"] }
}

enum ReminderPlanner {
    static func plan(medications: [Medication], items: [DueItem], events: [EventRecord], phoneID: String,
                     writablePets: Set<UUID>, now: Date, calendar: Calendar = .current) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        let live = EventLedger.visible(events)
        for med in medications where med.remindersEnabled && med.reminderPhoneID == phoneID && writablePets.contains(med.petID) {
            // Requests are one-shot and are only replanned when the app runs, so plan far ahead;
            // the 60-request cap below keeps the total inside iOS's 64.
            for offset in 0..<30 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                for slot in ScheduleEngine.slots(for: med, on: day, live: live, calendar: calendar) where slot.pending && slot.scheduledAt > now {
                    result.append(PlannedReminder(id: "med.\(slot.id)", title: med.name,
                        body: "Open Now to check the last dose and sync time.", date: slot.scheduledAt, isMedication: true, itemID: med.id, petID: med.petID))
                }
            }
        }
        for item in items where item.remindersEnabled && (item.reminderPhoneID ?? phoneID) == phoneID && writablePets.contains(item.petID) {
            for due in DueEngine.occurrences(for: item, from: now, days: 30, events: events, calendar: calendar) where !due.completed && due.date > now {
                result.append(PlannedReminder(id: "due.\(due.id)", title: item.name, body: "Due now", date: due.date,
                                               isMedication: false, itemID: item.id, petID: item.petID))
            }
        }
        return Array(result.sorted { $0.date < $1.date }.prefix(60))
    }
    /// One notice after the final planned medication reminder, when any of this phone's medication schedules
    /// runs past it (the 30-day horizon or the 60-request cap cut it off). Without it, reminders for an
    /// app left unopened stop with no warning.
    static func renewal(after planned: [PlannedReminder], medications: [Medication], phoneID: String, calendar: Calendar = .current) -> PlannedReminder? {
        // Only a medication with reminders actually planned here: opening the app restores those, never
        // reminders this phone cannot plan (a read-only pet, a course starting later).
        let ongoing = medications.filter { med in med.reminderPhoneID == phoneID && planned.contains { $0.isMedication && $0.itemID == med.id } }
        // Measured from the last medication reminder: recurring items planned later must not delay the notice.
        guard let last = planned.last(where: \.isMedication)?.date else { return nil }
        // Some scheduled time after the last planned request means the horizon or the cap cut the schedule off.
        let continues = { (med: Medication) in
            (0...8).contains { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: last) else { return false }
                return ScheduleEngine.slots(for: med, on: day, live: [], calendar: calendar).contains { $0.scheduledAt > last }
            }
        }
        guard let med = ongoing.first(where: continues) else { return nil }
        return PlannedReminder(id: "renewal", title: AppConfig.displayName, body: "Open \(AppConfig.displayName) to keep medication reminders coming.",
                               date: last.addingTimeInterval(60), isMedication: false, itemID: med.id, petID: med.petID, isRenewal: true)
    }
}

@MainActor
enum Reminders {
    private static var generation = 0
    static func register() {
        let done = UNNotificationAction(identifier: "MARK_DONE", title: "Mark done")
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "pet.medication", actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: "pet.due", actions: [done], intentIdentifiers: []),
            UNNotificationCategory(identifier: "pet.renewal", actions: [], intentIdentifiers: [])
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
        let now = Date.now
        let sources = store.reminderSources
        var planned = Array(sources.flatMap { source in
            let writable = Set(source.pets.enumerated().filter { source.access.canWrite(petIndex: $0.offset, at: now) }.map { $0.element.id })
            return ReminderPlanner.plan(medications: source.medications, items: source.dueItems, events: source.events,
                                        phoneID: store.phoneID, writablePets: writable, now: now)
        }.sorted { $0.date < $1.date }.prefix(60))
        if let renewal = ReminderPlanner.renewal(after: planned, medications: sources.flatMap(\.medications), phoneID: store.phoneID) { planned.append(renewal) }
        generation += 1
        let current = generation
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard current == generation else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("med.") || $0.identifier.hasPrefix("due.") || $0.identifier == "renewal" }.map(\.identifier))
            for item in planned {
                // A newer plan replaced this one while it was adding; its removal already ran, so stop here.
                guard current == generation else { return }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                content.categoryIdentifier = item.category
                content.userInfo = item.isRenewal ? ["route": "now"] : ["route": "now", "itemID": item.itemID.uuidString, "petID": item.petID.uuidString, "scheduledAt": item.date.timeIntervalSince1970]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.date.timeIntervalSinceNow), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }
}
