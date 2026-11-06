import Foundation

enum Species: String, Codable, CaseIterable, Identifiable, Sendable {
    case dog = "Dog", cat = "Cat"
    var id: String { rawValue }
    var kinds: [EventKind] { self == .dog ? [.potty, .meal, .walk, .meds] : [.meal, .litter, .meds, .play] }
}

enum EventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case potty = "Potty", meal = "Meal", walk = "Walk", meds = "Meds", litter = "Litter", play = "Play", due = "Due item"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .potty: "drop"
        case .meal: "fork.knife"
        case .walk: "figure.walk"
        case .meds: "pills"
        case .litter: "tray"
        case .play: "tennisball"
        case .due: "checkmark.circle"
        }
    }
}

struct PetProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var species: Species = .dog
    var birthday: Date?
    var createdAt = Date.now
    var editedAt = Date.now
    var editedBy: String
}

struct Medication: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var petID: UUID
    var name: String
    var instructions: String = ""
    var minutes: [Int] = [480]
    var weekdays: [Int] = []
    var startDate = Date.now
    var endDate: Date?
    var asNeeded = false
    var archived = false
    var reminderPhoneID: String
    var reminderPhoneName: String
    var remindersEnabled = false
    var editedAt = Date.now
    var editedBy: String
}

struct DueItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var petID: UUID
    var name: String
    var minutes: Int = 1080
    var intervalDays: Int = 1
    var startDate = Date.now
    var remindersEnabled = false
    /// The phone that set "Remind on this iPhone". Nil only in entries saved before it existed.
    var reminderPhoneID: String? = nil
    var archived = false
    var editedAt = Date.now
    var editedBy: String
}

enum EventAction: String, Codable, Sendable { case log, edit, delete, undo }
enum DoseStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case given = "Given", skipped = "Skipped"
    var id: String { rawValue }
}

struct EventRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let petID: UUID
    let kind: EventKind
    let occurredAt: Date
    let recordedAt: Date
    let author: String
    let performedBy: String
    let authorID: String
    let action: EventAction
    let restoresEntry: Bool
    let targetID: UUID?
    let medicationID: UUID?
    let dueItemID: UUID?
    let scheduledAt: Date?
    let doseStatus: DoseStatus?
    let note: String

    init(id: UUID = UUID(), petID: UUID, kind: EventKind, occurredAt: Date = .now,
         recordedAt: Date = .now, author: String, authorID: String, performedBy: String? = nil,
         action: EventAction = .log, targetID: UUID? = nil, restoresEntry: Bool = false, medicationID: UUID? = nil,
         dueItemID: UUID? = nil, scheduledAt: Date? = nil, doseStatus: DoseStatus? = nil, note: String = "") {
        self.id = id
        self.petID = petID
        self.kind = kind
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.performedBy = performedBy ?? author
        self.author = author
        self.authorID = authorID
        self.action = action
        self.restoresEntry = restoresEntry
        self.targetID = targetID
        self.medicationID = medicationID
        self.dueItemID = dueItemID
        self.scheduledAt = scheduledAt
        self.doseStatus = doseStatus
        self.note = note
    }
}

struct HouseholdAccess: Equatable, Sendable {
    let activeUntil: Date?
    let isOwner: Bool
    let wasShared: Bool
    static let grace: TimeInterval = 14 * 24 * 60 * 60
    func active(at now: Date) -> Bool { activeUntil.map { $0 > now } ?? false }
    func lapsed(at now: Date) -> Bool { (wasShared || activeUntil != nil) && !active(at: now) }
    func canWrite(petIndex: Int, at now: Date) -> Bool {
        if active(at: now) { return true }
        if isOwner { return petIndex == 0 }
        guard let activeUntil else { return false }
        return now < activeUntil.addingTimeInterval(Self.grace)
    }
    func canAddPet(existingCount: Int, at now: Date) -> Bool {
        active(at: now) || (isOwner && existingCount == 0)
    }
    var readOnlyFrom: Date? { activeUntil?.addingTimeInterval(Self.grace) }
}

/// Corrections form a directed tree. The newest leaf determines the visible state,
/// while every branch remains available in history and export.
enum EventLedger {
    static func ordered(_ events: [EventRecord]) -> [EventRecord] {
        events.sorted { a, b in
            a.recordedAt == b.recordedAt ? a.id.uuidString < b.id.uuidString : a.recordedAt < b.recordedAt
        }
    }
    private static func roots(_ events: [EventRecord]) -> [UUID: UUID] {
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var cache: [UUID: UUID] = [:]
        for event in events {
            var cursor = event
            var path: [UUID] = []
            var seen: Set<UUID> = []
            while cache[cursor.id] == nil, let target = cursor.targetID, let previous = byID[target], !seen.contains(target) {
                seen.insert(cursor.id)
                path.append(cursor.id)
                cursor = previous
            }
            let root = cache[cursor.id] ?? cursor.id
            cache[cursor.id] = root
            for id in path { cache[id] = root }
        }
        return cache
    }
    static func rootID(of event: EventRecord, in events: [EventRecord]) -> UUID {
        roots(events)[event.id] ?? event.id
    }
    static func visible(_ events: [EventRecord]) -> [EventRecord] {
        let roots = roots(events)
        let originals = Set(events.filter { $0.action == .log && $0.targetID == nil }.map(\.id))
        var current: [UUID: EventRecord] = [:]
        for event in ordered(events) {
            let root = roots[event.id] ?? event.id
            guard originals.contains(root) else { continue }
            current[root] = event
        }
        return current.values.filter { $0.action == .log || $0.action == .edit || ($0.action == .undo && $0.restoresEntry) }
            .sorted { $0.occurredAt == $1.occurredAt ? $0.id.uuidString < $1.id.uuidString : $0.occurredAt > $1.occurredAt }
    }
    static func chain(for event: EventRecord, in events: [EventRecord]) -> [EventRecord] {
        let mapping = roots(events)
        let root = mapping[event.id] ?? event.id
        return ordered(events.filter { mapping[$0.id] == root })
    }
}
