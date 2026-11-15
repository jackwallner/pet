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
        slots(for: medication, on: day, live: EventLedger.visible(events), calendar: calendar)
    }
    /// `live` is the already-resolved ledger, so a planner walking many days resolves it once.
    static func slots(for medication: Medication, on day: Date, live: [EventRecord], calendar: Calendar = .current) -> [DoseSlot] {
        let start = calendar.startOfDay(for: day)
        guard !medication.archived, !medication.asNeeded,
              start >= calendar.startOfDay(for: medication.startDate),
              medication.endDate.map({ start <= calendar.startOfDay(for: $0) }) ?? true,
              medication.weekdays.isEmpty || medication.weekdays.contains(calendar.component(.weekday, from: day)) else { return [] }
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
    /// "6:00 PM, every 30 days, next Nov 20". A long interval needs its next date to be followable.
    static func summary(_ item: DueItem, events: [EventRecord], now: Date = .now, calendar: Calendar = .current) -> String {
        let time = ScheduleEngine.date(forMinutes: item.minutes, onDayOf: now, calendar: calendar)?.formatted(date: .omitted, time: .shortened) ?? ""
        let start = calendar.startOfDay(for: item.startDate)
        if start > calendar.startOfDay(for: now) {
            return "\(time), \(item.intervalDays == 1 ? "every day" : "every \(item.intervalDays) days"), starts \(item.startDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
        guard item.intervalDays > 1 else { return "\(time), every day" }
        let next = occurrences(for: item, from: now, days: item.intervalDays + 1, events: events, calendar: calendar).first { !$0.completed }
        return "\(time), every \(item.intervalDays) days" + (next.map { ", next \($0.date.formatted(.dateTime.month(.abbreviated).day()))" } ?? "")
    }

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

/// Which scheduled time a dose belongs to. Chosen from the actual time, never from today alone, so
/// a dose given at 12:30 AM for last night's 10 PM does not close today's 8 AM reminder.
enum DoseSlots {
    static let window: TimeInterval = 6 * 3600
    /// Open scheduled times within six hours either side of the actual time, so an early morning dose can
    /// still close its 8 AM slot.
    static func candidates(for medication: Medication, actual: Date, preset: Date?, events: [EventRecord], calendar: Calendar = .current) -> [Date] {
        let days = [-1, 0, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: actual) }
        let live = EventLedger.visible(events)
        // Also every open time earlier the same day, so a dose given hours late can still be filed to its slot.
        var result = days.flatMap { ScheduleEngine.slots(for: medication, on: $0, live: live, calendar: calendar) }
            .filter { $0.pending && (abs($0.scheduledAt.timeIntervalSince(actual)) <= window
                || (calendar.isDate($0.scheduledAt, inSameDayAs: actual) && $0.scheduledAt <= actual)) }.map(\.scheduledAt)
        // A tapped time stays offered only while it is open: a partner's synced dose closes it.
        if let preset, !result.contains(preset),
           ScheduleEngine.slots(for: medication, on: preset, live: live, calendar: calendar).contains(where: { $0.pending && $0.scheduledAt == preset }) {
            result.append(preset)
        }
        return result.sorted()
    }
    /// The open time closest to the actual time: up to six hours late or two hours early. Anything else
    /// is unscheduled unless the person picks it.
    static func nearest(_ candidates: [Date], to actual: Date) -> Date? {
        candidates.filter { $0.timeIntervalSince(actual) <= 2 * 3600 && actual.timeIntervalSince($0) <= window }
            .min { abs($0.timeIntervalSince(actual)) < abs($1.timeIntervalSince(actual)) }
    }
    /// The automatic pick. A once-a-day medication given late the same day belongs to that day's dose.
    static func auto(for medication: Medication, candidates: [Date], actual: Date, calendar: Calendar = .current) -> Date? {
        if let near = nearest(candidates, to: actual) { return near }
        guard Set(medication.minutes).count == 1 else { return nil }
        return candidates.last { calendar.isDate($0, inSameDayAs: actual) && $0 <= actual }
    }
}

enum NowSummary {
    /// "8:15 AM" today, "Yesterday 8:15 AM", "Mon 8:15 AM" this week, then "Nov 3, 8:15 AM".
    /// A bare time on Now would let yesterday's meal pass for today's.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 1 { return "Yesterday \(time)" }
        if (2..<7).contains(days) { return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)" }
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            return date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
    static func lastDose(_ medicationID: UUID, events: [EventRecord]) -> EventRecord? {
        EventLedger.visible(events).first { $0.medicationID == medicationID }
    }
    static func last(_ kind: EventKind, petID: UUID, events: [EventRecord]) -> EventRecord? {
        EventLedger.visible(events).first { $0.petID == petID && $0.kind == kind }
    }
}
