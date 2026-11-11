import Foundation

enum Species: String, Codable, CaseIterable, Identifiable, Sendable {
    case dog = "Dog", cat = "Cat", rabbit = "Rabbit", smallPet = "Small pet", bird = "Bird", fish = "Fish", reptile = "Reptile", other = "Other"
    var id: String { rawValue }
    var kinds: [EventKind] {
        switch self {
        case .dog: [.potty, .meal, .walk, .meds]
        case .cat, .rabbit: [.meal, .litter, .meds, .play]
        case .smallPet, .bird, .other: [.meal, .cleaning, .meds, .play]
        case .fish, .reptile: [.meal, .water, .cleaning, .meds]
        }
    }
    /// A type added by a newer build reads as Other, so the pet never disappears from an older phone.
    init(from decoder: Decoder) throws {
        self = Species(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
    var symbol: String {
        switch self {
        case .dog: "dog"
        case .cat: "cat"
        case .rabbit: "hare"
        case .smallPet: "pawprint"
        case .bird: "bird"
        case .fish: "fish"
        case .reptile: "lizard"
        case .other: "ellipsis.circle"
        }
    }
}

enum EventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case potty = "Potty", meal = "Meal", walk = "Walk", meds = "Meds", litter = "Litter", play = "Play", cleaning = "Cleaning", water = "Water", due = "Due item", other = "Other activity"
    var id: String { rawValue }
    /// The activities that can be a button on Now.
    static let loggable: [EventKind] = [.potty, .meal, .walk, .meds, .litter, .play, .cleaning, .water]
    /// An activity added by a newer build stays in the log on an older phone.
    init(from decoder: Decoder) throws {
        self = EventKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
    var symbol: String {
        switch self {
        case .potty: "drop"
        case .meal: "fork.knife"
        case .walk: "figure.walk"
        case .meds: "pills"
        case .litter: "tray"
        case .play: "tennisball"
        case .cleaning: "sparkles"
        case .water: "water.waves"
        case .due: "checkmark.circle"
        case .other: "circle"
        }
    }
}

struct PetProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// The buttons were chosen for the old animal, so a new species starts from its own.
    var species: Species = .dog { didSet { if species != oldValue { logButtons = nil } } }
    var birthday: Date?
    var createdAt = Date.now
    var editedAt = Date.now
    var editedBy: String
    // Optional, because a required key would make every pet saved before it exist fail to decode.
    var vet: String?
    var vetPhone: String?
    var microchip: String?
    var insurance: String?
    var notes: String?
    /// People who could look after the pet. Nil until the first one is added.
    var sitters: [SitterContact]?
    /// Nil until someone customizes the buttons, so the species defaults apply.
    var logButtons: [LogButtonSetting]?

    /// Every activity in display order, with the ones not on Now marked hidden.
    var logButtonSettings: [LogButtonSetting] {
        guard let logButtons else {
            let rest = EventKind.loggable.filter { !species.kinds.contains($0) }
            return species.kinds.map { LogButtonSetting(kind: $0, shown: true) } + rest.map { LogButtonSetting(kind: $0, shown: false) }
        }
        var seen = Set<EventKind>()
        let saved = logButtons.filter { EventKind.loggable.contains($0.kind) && seen.insert($0.kind).inserted }
        return saved + EventKind.loggable.filter { !seen.contains($0) }.map { LogButtonSetting(kind: $0, shown: false) }
    }
    var shownLogKinds: [EventKind] { logButtonSettings.filter(\.shown).map(\.kind) }
}

struct LogButtonSetting: Codable, Identifiable, Equatable, Sendable {
    let kind: EventKind
    var shown: Bool
    var id: String { kind.id }
}

struct SitterContact: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var phone: String?
    var note: String?
    /// Nil when the number has too few digits to dial.
    var callURL: URL? { SitterContact.callURL(phone) }
    static func callURL(_ phone: String?) -> URL? {
        let digits = (phone ?? "").filter { $0.isNumber || $0 == "+" }
        return digits.count < 3 ? nil : URL(string: "tel:\(digits)")
    }
}

/// One pet's photo, in its own record so saving a pet's name never rewrites the image.
/// The id is the pet's. A nil image means the photo was removed, and the newest record wins.
struct PetPhoto: Codable, Identifiable, Equatable, Sendable {
    static let category = "petPhoto"
    let id: UUID
    let jpeg: Data?
    var editedAt = Date.now
    let editedBy: String
}

enum PetAge {
    static func text(birthday: Date, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard birthday <= now else { return nil }
        let from = calendar.startOfDay(for: birthday), to = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        if days == 0 { return "Born today" }
        if days < 14 { return old(days, "day") }
        if days < 112 { return old(days / 7, "week") }
        let parts = calendar.dateComponents([.year, .month], from: from, to: to)
        let months = (parts.year ?? 0) * 12 + (parts.month ?? 0)
        return months < 24 ? old(months, "month") : old(months / 12, "year")
    }
    private static func old(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s") old" }
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
