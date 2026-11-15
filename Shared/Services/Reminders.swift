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
    /// `petNames` is filled only for a household with more than one pet, so the lock screen says whose reminder it is.
    static func plan(medications: [Medication], items: [DueItem], events: [EventRecord], phoneID: String,
                     writablePets: Set<UUID>, petNames: [UUID: String] = [:], now: Date, calendar: Calendar = .current) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        let live = EventLedger.visible(events)
        func title(_ name: String, pet: UUID) -> String { petNames[pet].map { "\($0): \(name)" } ?? name }
        // A lapsed household's read-only pet still needs its medication: the reminder only opens Now, which
        // shows the last dose. Recurring items carry Mark done, which a read-only log would refuse.
        for med in medications where med.remindersEnabled && med.reminderPhoneID == phoneID {
            // Requests are one-shot and are only replanned when the app runs, so plan far ahead;
            // the 60-request cap below keeps the total inside iOS's 64.
            for offset in 0..<30 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                for slot in ScheduleEngine.slots(for: med, on: day, live: live, calendar: calendar) where slot.pending && slot.scheduledAt > now {
                    result.append(PlannedReminder(id: "med.\(slot.id)", title: title(med.name, pet: med.petID),
                        body: "Open Now to check the last dose and sync time.", date: slot.scheduledAt, isMedication: true, itemID: med.id, petID: med.petID))
                }
            }
        }
        for item in items where item.remindersEnabled && (item.reminderPhoneID ?? phoneID) == phoneID && writablePets.contains(item.petID) {
            for due in DueEngine.occurrences(for: item, from: now, days: 30, events: events, calendar: calendar) where !due.completed && due.date > now {
                result.append(PlannedReminder(id: "due.\(due.id)", title: title(item.name, pet: item.petID), body: "Due now", date: due.date,
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
        // reminders this phone cannot plan (a course starting later).
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
    /// The replacement under way, so a background run can wait for it before iOS suspends the app.
    private(set) static var replacing: Task<Void, Never>?
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
            let names = source.pets.count > 1 ? Dictionary(source.pets.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }) : [:]
            return ReminderPlanner.plan(medications: source.medications, items: source.dueItems, events: source.events,
                                        phoneID: store.phoneID, writablePets: writable, petNames: names, now: now)
        }.sorted { $0.date < $1.date }.prefix(60))
        if let renewal = ReminderPlanner.renewal(after: planned, medications: sources.flatMap(\.medications), phoneID: store.phoneID) { planned.append(renewal) }
        generation += 1
        let current = generation
        replacing = Task {
            let center = UNUserNotificationCenter.current()
            // Adding a request under an existing identifier replaces it, so the new plan goes in first and
            // only obsolete requests are removed last. Cut off part way, the old plan still covers what is left.
            @MainActor func add() async -> Bool {
                for item in planned {
                    // A newer plan took over; it adds and prunes everything itself.
                    guard current == generation else { return false }
                    // Resumed hours after a suspension, a time already gone would fire at once alongside the others.
                    guard item.date > .now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = item.title
                    content.body = item.body
                    content.sound = .default
                    content.categoryIdentifier = item.category
                    content.userInfo = item.isRenewal ? ["route": "now"] : ["route": "now", "itemID": item.itemID.uuidString, "petID": item.petID.uuidString, "scheduledAt": item.date.timeIntervalSince1970]
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.date.timeIntervalSinceNow), repeats: false)
                    try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
                }
                return true
            }
            guard await add() else { return }
            let kept = Set(planned.map(\.id))
            let pending = await center.pendingNotificationRequests()
            guard current == generation else { return }
            let obsolete = pending.map(\.identifier).filter { id in (id.hasPrefix("med.") || id.hasPrefix("due.") || id == "renewal") && !kept.contains(id) }
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
            // Old and new together can pass iOS's 64-request limit, which drops the latest. Now there is room.
            if !obsolete.isEmpty && pending.count >= 64 { _ = await add() }
        }
    }
}
