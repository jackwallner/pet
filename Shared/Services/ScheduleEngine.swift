import Foundation

struct DoseSlot: Identifiable, Equatable, Sendable {
    let medicationID: UUID
    let scheduledAt: Date
    let entries: [EventRecord]
    var id: String { "\(medicationID)-\(scheduledAt.timeIntervalSince1970)" }
    var pending: Bool { entries.isEmpty }
}

/// Clock-time placement adapted from elderhub's ScheduleEngine.
enum ScheduleEngine {
    static func date(forMinutes minutes: Int, onDayOf day: Date, calendar: Calendar = .current) -> Date? {
        let startOfDay = calendar.startOfDay(for: day)
        let elapsed = calendar.date(byAdding: .minute, value: minutes, to: startOfDay)
        guard (0..<24 * 60).contains(minutes) else { return elapsed }

        guard let onTheClock = calendar.date(
            bySettingHour: minutes / 60,
            minute: minutes % 60,
            second: 0,
            of: startOfDay,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else { return elapsed }

        let reading = calendar.dateComponents([.hour, .minute], from: onTheClock)
        guard reading.hour == minutes / 60, reading.minute == minutes % 60 else { return elapsed }
        return onTheClock
    }


    static func slots(for medication: Medication, on day: Date, events: [EventRecord], calendar: Calendar = .current) -> [DoseSlot] {
        let start = calendar.startOfDay(for: day)
        guard !medication.archived, !medication.asNeeded,
              start >= calendar.startOfDay(for: medication.startDate),
              medication.endDate.map({ start <= calendar.startOfDay(for: $0) }) ?? true,
              medication.weekdays.isEmpty || medication.weekdays.contains(calendar.component(.weekday, from: day)) else { return [] }
        let live = EventLedger.visible(events)
        return Set(medication.minutes.filter { (0..<1440).contains($0) }).sorted().compactMap { minutes in
            guard let at = date(forMinutes: minutes, onDayOf: day, calendar: calendar) else { return nil }
            let matching = live.filter { $0.medicationID == medication.id && $0.scheduledAt.map { calendar.isDate($0, equalTo: at, toGranularity: .minute) } == true }
            return DoseSlot(medicationID: medication.id, scheduledAt: at, entries: matching)
        }
    }
    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

struct DueOccurrence: Identifiable, Equatable, Sendable {
    let itemID: UUID
    let name: String
    let date: Date
    let completed: Bool
    var id: String { "\(itemID)-\(date.timeIntervalSince1970)" }
}

enum DueEngine {
    static func occurrences(for item: DueItem, from date: Date, days: Int, events: [EventRecord], calendar: Calendar = .current) -> [DueOccurrence] {
        guard !item.archived, item.intervalDays > 0, days > 0 else { return [] }
        let anchor = calendar.startOfDay(for: item.startDate)
        let live = EventLedger.visible(events)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)),
                  let distance = calendar.dateComponents([.day], from: anchor, to: day).day,
                  distance >= 0, distance % item.intervalDays == 0,
                  let at = ScheduleEngine.date(forMinutes: item.minutes, onDayOf: day, calendar: calendar) else { return nil }
            let completed = live.contains { $0.dueItemID == item.id && $0.scheduledAt.map { calendar.isDate($0, equalTo: at, toGranularity: .minute) } == true }
            return DueOccurrence(itemID: item.id, name: item.name, date: at, completed: completed)
        }
    }
}

enum NowSummary {
    static func lastDose(_ medicationID: UUID, events: [EventRecord]) -> EventRecord? {
        EventLedger.visible(events).first { $0.medicationID == medicationID }
    }
    static func last(_ kind: EventKind, petID: UUID, events: [EventRecord]) -> EventRecord? {
        EventLedger.visible(events).first { $0.petID == petID && $0.kind == kind }
    }
}
