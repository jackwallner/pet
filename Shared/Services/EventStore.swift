import CloudKit
import Combine
import CoreData
import Foundation

@MainActor
final class EventStore: ObservableObject {
    static let shared = EventStore(persistence: .shared)
    let persistence: Persistence
    let defaults: UserDefaults
    let sync: CloudSyncState
    @Published private(set) var households: [Household] = []
    @Published private(set) var household: Household?
    @Published private(set) var pets: [PetProfile] = []
    @Published private(set) var medications: [Medication] = []
    @Published private(set) var dueItems: [DueItem] = []
    @Published private(set) var events: [EventRecord] = []
    @Published var selectedPetID: UUID?
    @Published var lastLogged: EventRecord?
    @Published var notificationMedicationID: UUID?
    @Published var error: String?
    @Published var awaitingShare = false
    private var observers: [Any] = []
    private var reloadTask: Task<Void, Never>?
    var context: NSManagedObjectContext { persistence.viewContext }
    var phoneID: String { defaults.string(forKey: "phoneID") ?? "" }
    var caregiver: String {
        get { defaults.string(forKey: "caregiver") ?? "You" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "caregiver"); objectWillChange.send() }
    }
    var pet: PetProfile? { pets.first { $0.id == selectedPetID } ?? pets.first }
    var isOwner: Bool { household?.objectID.persistentStore != persistence.sharedStore }
    var access: HouseholdAccess {
        HouseholdAccess(activeUntil: household?.householdActiveUntil, isOwner: isOwner,
                        wasShared: household?.wasShared?.boolValue ?? false)
    }
    var canWrite: Bool {
        guard let pet, let index = pets.firstIndex(where: { $0.id == pet.id }) else { return false }
        return access.canWrite(petIndex: index, at: .now)
    }
    var isSharedLog: Bool { !isOwner || (household?.wasShared?.boolValue ?? false) }
    var visibleEvents: [EventRecord] { EventLedger.visible(events).filter { $0.petID == pet?.id } }
    var petMedications: [Medication] { medications.filter { $0.petID == pet?.id && !$0.archived } }
    var petDueItems: [DueItem] { dueItems.filter { $0.petID == pet?.id && !$0.archived } }

    init(persistence: Persistence, defaults: UserDefaults = AppGroup.defaults) {
        self.persistence = persistence
        self.defaults = defaults
        sync = CloudSyncState(defaults: defaults, cloudEnabled: persistence.cloudKitEnabled)
        if defaults.string(forKey: "phoneID") == nil { defaults.set(UUID().uuidString, forKey: "phoneID") }
        selectedPetID = defaults.string(forKey: "selectedPetID").flatMap(UUID.init)
        reload()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: persistence.container.persistentStoreCoordinator, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        })
        observers.append(center.addObserver(forName: Persistence.storesDidReopen, object: persistence, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        })
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: persistence.container, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event, let ended = event.endDate else { return }
            Task { @MainActor in
                self?.sync.ended(isImport: event.type == .import, isSetup: event.type == .setup, at: ended, succeeded: event.succeeded, error: event.error)
                if event.succeeded { self?.scheduleReload() }
            }
        })
    }

    private func scheduleReload() {
        guard reloadTask == nil else { return }
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reloadTask = nil
            self?.reload()
        }
    }

    func reload() {
        persistence.mergeExternalChanges()
        let request = NSFetchRequest<Household>(entityName: "Household")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let roots = (try? context.fetch(request)) ?? []
        households = roots
        let shared = roots.first { $0.objectID.persistentStore == persistence.sharedStore }
        let selected = defaults.string(forKey: "selectedHouseholdID").flatMap(UUID.init)
        household = roots.first { $0.id == selected } ?? shared ?? roots.first
        if defaults.bool(forKey: "pendingShare"), let shared { household = shared }
        if shared != nil && defaults.bool(forKey: "pendingShare") {
            awaitingShare = false
            defaults.removeObject(forKey: "pendingShare")
            defaults.set(shared?.id?.uuidString, forKey: "selectedHouseholdID")
            Measurements.once("joined_share_at", defaults: defaults)
            defaults.set(true, forKey: "onboarded")
        }
        let current = contents(of: household)
        pets = current.pets
        medications = current.medications
        dueItems = current.dueItems
        events = current.events
        if !pets.contains(where: { $0.id == selectedPetID }) { selectedPetID = pets.first?.id }
        awaitingShare = defaults.bool(forKey: "pendingShare")
        Reminders.schedule(store: self)
    }

    struct HouseholdContents {
        var pets: [PetProfile] = []
        var medications: [Medication] = []
        var dueItems: [DueItem] = []
        var events: [EventRecord] = []
        var access = HouseholdAccess(activeUntil: nil, isOwner: true, wasShared: false)
    }

    func contents(of root: Household?) -> HouseholdContents {
        guard let root else { return HouseholdContents() }
        let records = Array(root.records ?? [])
        // Identity protects transport redelivery only. Independent taps always have independent IDs.
        var byID: [UUID: EventRecord] = [:]
        for record in records where record.category == "event" {
            if let value = record.decode(EventRecord.self) { byID[value.id] = value }
        }
        return HouseholdContents(
            pets: settings(records, category: "pet", type: PetProfile.self).sorted { $0.createdAt < $1.createdAt },
            medications: settings(records, category: "med", type: Medication.self).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            dueItems: settings(records, category: "due", type: DueItem.self).sorted { $0.name < $1.name },
            events: EventLedger.ordered(Array(byID.values)).reversed(),
            access: HouseholdAccess(activeUntil: root.householdActiveUntil, isOwner: root.objectID.persistentStore != persistence.sharedStore,
                                    wasShared: root.wasShared?.boolValue ?? false))
    }

    /// Reminders come from every household on this phone, so viewing one log never silences another's reminder phone.
    var reminderSources: [HouseholdContents] {
        households.map { root in
            guard root == household else { return contents(of: root) }
            return HouseholdContents(pets: pets, medications: medications, dueItems: dueItems, events: events, access: access)
        }
    }

    /// Opens the log that holds a pet, switching household when a reminder belongs to the other one.
    func focus(petID: UUID) {
        if !pets.contains(where: { $0.id == petID }),
           let root = households.first(where: { $0 != household && contents(of: $0).pets.contains { $0.id == petID } }) {
            selectHousehold(root)
        }
        if pets.contains(where: { $0.id == petID }) { select(petID) }
    }

    private func settings<T: Decodable & Identifiable>(_ records: [StoredRecord], category: String, type: T.Type) -> [T] where T.ID == UUID {
        var found: [UUID: T] = [:]
        for record in records.filter({ $0.category == category }).sorted(by: { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }) {
            if let value = record.decode(type) { found[value.id] = value }
        }
        return Array(found.values)
    }

    private func ensureHousehold() -> Household {
        if let household { return household }
        let root = Household(context: context)
        root.id = UUID()
        root.createdAt = .now
        root.wasShared = false
        context.assign(root, to: persistence.privateStore)
        household = root
        return root
    }

    @discardableResult
    private func write<T: Encodable>(id: UUID, category: String, value: T, immutable: Bool = false) -> Bool {
        let root = ensureHousehold()
        guard let payload = try? JSONEncoder().encode(value) else { error = "This entry could not be saved."; return false }
        let existing = root.records?.first { $0.id == id && $0.category == category }
        if immutable && existing != nil { return true }
        let record = existing ?? StoredRecord(context: context)
        record.id = id
        record.category = category
        record.payload = payload
        record.updatedAt = .now
        record.household = root
        if existing == nil, let target = root.objectID.persistentStore { context.assign(record, to: target) }
        guard persistence.save(context) else {
            error = "The log could not be saved. Please try again."
            reload()
            return false
        }
        reload()
        return true
    }

    @discardableResult
    func savePet(_ value: PetProfile) -> Bool {
        let existing = pets.contains { $0.id == value.id }
        guard existing ? canWrite : access.canAddPet(existingCount: pets.count, at: .now) else { error = "Household access is required for another pet."; return false }
        var value = value
        value.editedAt = .now
        value.editedBy = caregiver
        let saved = write(id: value.id, category: "pet", value: value)
        if saved { select(value.id) }
        return saved
    }

    func selectHousehold(_ root: Household) {
        defaults.set(root.id?.uuidString, forKey: "selectedHouseholdID")
        selectedPetID = nil
        lastLogged = nil
        reload()
    }

    func select(_ id: UUID) {
        // The undo bar names an entry of the pet on screen; another pet's entry cannot be undone from here.
        if lastLogged.map({ $0.petID != id }) == true { lastLogged = nil }
        selectedPetID = id
        defaults.set(id.uuidString, forKey: "selectedPetID")
    }

    @discardableResult
    func saveMedication(_ value: Medication) -> Bool {
        guard canWrite, value.petID == pet?.id else { error = "This log is read-only."; return false }
        var value = value
        value.editedAt = .now
        value.editedBy = caregiver
        return write(id: value.id, category: "med", value: value)
    }
    @discardableResult
    func saveDueItem(_ value: DueItem) -> Bool {
        guard canWrite, value.petID == pet?.id else { error = "This log is read-only."; return false }
        var value = value
        value.editedAt = .now
        value.editedBy = caregiver
        return write(id: value.id, category: "due", value: value)
    }

    @discardableResult
    func append(_ event: EventRecord) -> Bool {
        guard canWrite, event.petID == pet?.id else { error = "This log is read-only."; return false }
        if let targetID = event.targetID {
            guard events.contains(where: { $0.id == targetID && $0.petID == event.petID }) else { error = "The original entry is still loading."; return false }
        }
        guard write(id: event.id, category: "event", value: event, immutable: true) else { return false }
        lastLogged = event
        if event.action == .log { Measurements.recordLog(defaults: defaults) }
        return true
    }

    @discardableResult
    func log(_ kind: EventKind, at date: Date = .now, note: String = "", medicationID: UUID? = nil,
             dueItemID: UUID? = nil, scheduledAt: Date? = nil, doseStatus: DoseStatus? = nil) -> Bool {
        guard let pet else { return false }
        return append(EventRecord(petID: pet.id, kind: kind, occurredAt: date, author: caregiver, authorID: phoneID,
                                  medicationID: medicationID, dueItemID: dueItemID, scheduledAt: scheduledAt, doseStatus: doseStatus, note: note))
    }
    @discardableResult
    func correct(_ old: EventRecord, action: EventAction, at date: Date? = nil, note: String? = nil, status: DoseStatus? = nil) -> Bool {
        var source = old
        var restores = false
        if action == .undo {
            let chain = EventLedger.chain(for: old, in: events)
            if let index = chain.firstIndex(where: { $0.id == old.id }),
               let previous = EventLedger.visible(Array(chain.prefix(index))).first {
                source = previous
                restores = true
            }
        }
        return append(EventRecord(petID: old.petID, kind: source.kind, occurredAt: date ?? source.occurredAt,
                           author: caregiver, authorID: phoneID, performedBy: source.performedBy, action: action, targetID: old.id, restoresEntry: restores,
                           medicationID: source.medicationID, dueItemID: source.dueItemID, scheduledAt: source.scheduledAt,
                           doseStatus: status ?? source.doseStatus, note: note ?? source.note))
    }

    func setHouseholdExpiry(_ date: Date?) {
        // An unavailable receipt must never manufacture a fresh subscription or erase its lapse date.
        guard let date else { return }
        // The purchase covers the household this account owns, even while a joined household is on screen.
        let owned = households.filter { $0.objectID.persistentStore != persistence.sharedStore }
        let roots = owned.isEmpty ? (isOwner ? [ensureHousehold()] : []) : owned
        let stale = roots.filter { $0.householdActiveUntil != date }
        guard !stale.isEmpty else { return }
        for root in stale { root.householdActiveUntil = date }
        if !persistence.save(context) { error = "Household status could not be saved." }
        reload()
    }
    func markShared() -> Bool {
        guard isOwner, access.active(at: .now) else { return false }
        household?.wasShared = true
        let saved = persistence.save(context)
        reload()
        return saved
    }

    #if DEBUG
    func seedDemo(pro: Bool) {
        guard pets.isEmpty else { if pro { setHouseholdExpiry(.now.addingTimeInterval(30 * 86400)); _ = markShared() }; return }
        caregiver = "Jack"
        let profile = PetProfile(name: "Milo", birthday: Calendar.current.date(byAdding: .day, value: -84, to: .now), editedBy: caregiver)
        _ = savePet(profile)
        if pro { setHouseholdExpiry(.now.addingTimeInterval(30 * 86400)); _ = markShared() }
        let med = Medication(petID: profile.id, name: "Daily tablet", instructions: "Follow the veterinarian's instructions.",
                             reminderPhoneID: phoneID, reminderPhoneName: "Jack's iPhone", editedBy: caregiver)
        _ = saveMedication(med)
        _ = saveDueItem(DueItem(petID: profile.id, name: "Evening walk", editedBy: caregiver))
        for (index, kind) in [EventKind.meal, .walk, .potty, .meds].enumerated() {
            _ = append(EventRecord(petID: profile.id, kind: kind, occurredAt: .now.addingTimeInterval(Double(-index * 1800 - 900)),
                                   author: index % 2 == 0 ? "Jack" : "Sam", authorID: index % 2 == 0 ? phoneID : "partner",
                                   medicationID: kind == .meds ? med.id : nil,
                                   scheduledAt: kind == .meds ? ScheduleEngine.date(forMinutes: 480, onDayOf: .now) : nil, doseStatus: kind == .meds ? .given : nil))
        }
        lastLogged = nil
    }
    #endif
}
