import CoreData
import CoreImage
import PDFKit
import XCTest
import UserNotifications

@testable import Pet

@MainActor
final class DomainTests: XCTestCase {
    private var defaults: UserDefaults!
    private var persistence: Persistence!
    private var store: EventStore!
    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "pet.tests.\(UUID())")!
        persistence = Persistence(cloudKit: false, inMemory: true)
        store = EventStore(persistence: persistence, defaults: defaults)
        store.caregiver = "Jack"
        XCTAssertTrue(store.savePet(PetProfile(name: "Milo", editedBy: "Jack")))
    }
    private func event(_ kind: EventKind = .meal, author: String = "Sam", at: Date = .now, medicationID: UUID? = nil, scheduledAt: Date? = nil, status: DoseStatus? = nil) -> EventRecord {
        EventRecord(petID: store.pet!.id, kind: kind, occurredAt: at, author: author, authorID: author, medicationID: medicationID, scheduledAt: scheduledAt, doseStatus: status)
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }
    private func med(minutes: [Int] = [480]) -> Medication {
        Medication(petID: store.pet!.id, name: "Entered medication", minutes: minutes, startDate: day(2026, 1, 1), reminderPhoneID: store.phoneID, reminderPhoneName: "Jack's iPhone", remindersEnabled: true, editedBy: "Jack")
    }

    func testLogEditDeleteUndoAreAllInserts() {
        let original = event()
        XCTAssertTrue(store.append(original))
        XCTAssertTrue(store.correct(original, action: .edit, note: "Corrected"))
        let edit = store.events.first!
        XCTAssertEqual(edit.targetID, original.id)
        XCTAssertEqual(store.visibleEvents.first?.note, "Corrected")
        XCTAssertTrue(store.correct(edit, action: .delete))
        let deleted = store.events.first!
        XCTAssertTrue(store.visibleEvents.isEmpty)
        XCTAssertTrue(store.correct(deleted, action: .undo))
        XCTAssertEqual(store.visibleEvents.first?.note, "Corrected")
        XCTAssertEqual(store.events.count, 4)
        XCTAssertEqual(store.events.first(where: { $0.id == original.id }), original)
        XCTAssertEqual(persistence.viewContext.deletedObjects.count, 0)
        XCTAssertEqual(EventLedger.chain(for: original, in: store.events).count, 4)
    }
    func testUndoLogHidesButRetainsOriginal() {
        let original = event()
        XCTAssertTrue(store.append(original))
        XCTAssertTrue(store.correct(original, action: .undo))
        XCTAssertTrue(store.visibleEvents.isEmpty)
        XCTAssertEqual(store.events.count, 2)
    }
    func testUndoEditRestoresPreviousSnapshot() {
        let original = event()
        XCTAssertTrue(store.append(original))
        XCTAssertTrue(store.correct(original, action: .edit, note: "Changed"))
        XCTAssertTrue(store.correct(store.events.first!, action: .undo))
        XCTAssertEqual(store.visibleEvents.first?.note, "")
        XCTAssertEqual(store.events.count, 3)
    }
    func testIndependentSameTimeEntriesKeepBothNames() {
        let now = Date.now
        XCTAssertTrue(store.append(event(author: "Jack", at: now)))
        XCTAssertTrue(store.append(event(author: "Sam", at: now)))
        XCTAssertEqual(store.visibleEvents.count, 2)
        XCTAssertEqual(Set(store.visibleEvents.map(\.author)), ["Jack", "Sam"])
    }
    func testTransportRedeliveryIsIdempotent() {
        let value = event()
        XCTAssertTrue(store.append(value)); XCTAssertTrue(store.append(value))
        XCTAssertEqual(store.events.count, 1)
    }
    func testMissingCorrectionTargetIsRefused() {
        XCTAssertFalse(store.correct(event(), action: .delete))
        XCTAssertTrue(store.events.isEmpty)
    }
    func testConcurrentCorrectionsAreDeterministicAndRetained() {
        let original = event()
        let time = Date.now.addingTimeInterval(5)
        let a = EventRecord(petID: original.petID, kind: .meal, recordedAt: time, author: "Jack", authorID: "1", action: .edit, targetID: original.id, note: "A")
        let b = EventRecord(petID: original.petID, kind: .meal, recordedAt: time, author: "Sam", authorID: "2", action: .delete, targetID: original.id)
        XCTAssertEqual(EventLedger.visible([original, a, b]), EventLedger.visible([b, a, original]))
        XCTAssertEqual(EventLedger.chain(for: original, in: [b, a, original]).count, 3)
    }
    func testFreeTierAllowsOnePetAndAllLogging() {
        XCTAssertFalse(store.savePet(PetProfile(name: "Second", editedBy: "Jack")))
        for kind in Species.dog.kinds { XCTAssertTrue(store.log(kind)) }
        XCTAssertEqual(store.visibleEvents.count, 4)
    }
    func testEverySpeciesHasFourButtonsIncludingMealAndMeds() {
        XCTAssertEqual(Species.allCases.count, 8)
        for species in Species.allCases {
            XCTAssertEqual(Set(species.kinds).count, 4, species.rawValue)
            XCTAssertTrue(species.kinds.contains(.meal), species.rawValue)
            XCTAssertTrue(species.kinds.contains(.meds), species.rawValue)
        }
    }
    func testNewSpeciesRoundTripsAndExistingStoredPetsStillDecode() throws {
        let fish = PetProfile(name: "Bubbles", species: .fish, editedBy: "Jack")
        let decoded = try JSONDecoder().decode(PetProfile.self, from: JSONEncoder().encode(fish))
        XCTAssertEqual(decoded.species, .fish)
        XCTAssertEqual(Species(rawValue: "Dog"), .dog)
        XCTAssertEqual(Species(rawValue: "Cat"), .cat)
    }
    func testPaidExtraPetThenLapsePreservesViewAndFirstPetLogging() {
        store.setHouseholdExpiry(.now.addingTimeInterval(86400))
        XCTAssertTrue(store.savePet(PetProfile(name: "Luna", species: .cat, editedBy: "Jack")))
        let second = store.pet!.id
        store.setHouseholdExpiry(.now.addingTimeInterval(-1))
        XCTAssertEqual(store.pets.count, 2)
        XCTAssertEqual(store.pet?.id, second)
        XCTAssertFalse(store.log(.meal))
        store.select(store.pets[0].id)
        XCTAssertTrue(store.log(.meal))
        XCTAssertEqual(store.pets.count, 2)
    }
    func testLapseBoundaryAndRenewal() {
        let expiry = Date(timeIntervalSince1970: 100000)
        let owner = HouseholdAccess(activeUntil: expiry, isOwner: true, wasShared: true)
        let joiner = HouseholdAccess(activeUntil: expiry, isOwner: false, wasShared: true)
        XCTAssertTrue(joiner.canWrite(petIndex: 1, at: expiry.addingTimeInterval(HouseholdAccess.grace - 1)))
        XCTAssertFalse(joiner.canWrite(petIndex: 0, at: expiry.addingTimeInterval(HouseholdAccess.grace)))
        XCTAssertTrue(joiner.lapsed(at: expiry))
        XCTAssertTrue(owner.canWrite(petIndex: 0, at: expiry))
        XCTAssertFalse(owner.canWrite(petIndex: 1, at: expiry))
        XCTAssertTrue(joiner.canAddPet(existingCount: 1, at: expiry.addingTimeInterval(-1)))
        let renewed = HouseholdAccess(activeUntil: expiry.addingTimeInterval(60 * 86400), isOwner: false, wasShared: true)
        XCTAssertTrue(renewed.canWrite(petIndex: 10, at: expiry.addingTimeInterval(30 * 86400)))
    }
    func testUnknownReceiptPreservesExpiry() {
        let expiry = Date.now.addingTimeInterval(-86400)
        store.setHouseholdExpiry(expiry)
        store.setHouseholdExpiry(nil)
        XCTAssertEqual(store.household?.householdActiveUntil, expiry)
    }
    func testJoinerCannotRewriteOwnersExpiry() throws {
        let root = Household(context: persistence.viewContext)
        root.id = UUID(); root.createdAt = .distantPast; root.householdActiveUntil = .now.addingTimeInterval(-86400)
        persistence.viewContext.assign(root, to: persistence.sharedStore)
        XCTAssertTrue(persistence.save(persistence.viewContext))
        store.reload()
        let before = store.household?.householdActiveUntil
        XCTAssertFalse(store.isOwner)
        store.setHouseholdExpiry(.now.addingTimeInterval(86400))
        XCTAssertEqual(store.household?.householdActiveUntil, before)
    }
    private func joinSharedHousehold(activeUntil: Date? = nil) -> Household {
        let shared = Household(context: persistence.viewContext)
        shared.id = UUID(); shared.createdAt = .now; shared.householdActiveUntil = activeUntil
        persistence.viewContext.assign(shared, to: persistence.sharedStore)
        XCTAssertTrue(persistence.save(persistence.viewContext))
        defaults.set(true, forKey: "pendingShare")
        store.reload()
        return shared
    }
    func testRenewalReachesOwnedHouseholdWhileJoinedOneIsOnScreen() {
        let own = store.household!
        let shared = joinSharedHousehold(activeUntil: .now.addingTimeInterval(-86400))
        XCTAssertFalse(store.isOwner)
        let renewal = Date.now.addingTimeInterval(30 * 86400)
        store.setHouseholdExpiry(renewal)
        XCTAssertEqual(own.householdActiveUntil, renewal)
        XCTAssertNotEqual(shared.householdActiveUntil, renewal)
    }
    func testUnknownReceiptCreatesNoHousehold() {
        let fresh = EventStore(persistence: Persistence(cloudKit: false, inMemory: true), defaults: UserDefaults(suiteName: "pet.tests.\(UUID())")!)
        fresh.setHouseholdExpiry(nil)
        XCTAssertNil(fresh.household)
        XCTAssertTrue(fresh.households.isEmpty)
    }
    func testViewingJoinedHouseholdKeepsOwnMedicationReminders() {
        let milo = store.pet!.id
        XCTAssertTrue(store.saveMedication(med()))
        _ = joinSharedHousehold(activeUntil: .now.addingTimeInterval(86400))
        XCTAssertFalse(store.isOwner)
        XCTAssertTrue(store.medications.isEmpty)
        let now = day(2026, 11, 6)
        let planned = store.reminderSources.flatMap { source in
            ReminderPlanner.plan(medications: source.medications, items: source.dueItems, events: source.events, phoneID: store.phoneID,
                                 writablePets: Set(source.pets.enumerated().filter { source.access.canWrite(petIndex: $0.offset, at: now) }.map(\.element.id)),
                                 now: now, calendar: calendar)
        }
        XCTAssertEqual(planned.count, 7)
        store.focus(petID: milo)
        XCTAssertTrue(store.isOwner)
        XCTAssertEqual(store.pet?.id, milo)
    }
    func testDueReminderStaysOnThePhoneThatSetIt() {
        let now = day(2026, 11, 6)
        var item = DueItem(petID: store.pet!.id, name: "Walk", startDate: now, remindersEnabled: true, reminderPhoneID: "phone-a", editedBy: "Jack")
        let plan = { (phone: String) in ReminderPlanner.plan(medications: [], items: [item], events: [], phoneID: phone, writablePets: [item.petID], now: now, calendar: self.calendar) }
        XCTAssertFalse(plan("phone-a").isEmpty)
        XCTAssertTrue(plan("phone-b").isEmpty)
        item.reminderPhoneID = nil
        XCTAssertFalse(plan("phone-b").isEmpty)
    }
    func testSwitchingPetDropsTheOtherPetsUndo() {
        store.setHouseholdExpiry(.now.addingTimeInterval(86400))
        let milo = store.pet!.id
        XCTAssertTrue(store.savePet(PetProfile(name: "Luna", species: .cat, editedBy: "Jack")))
        XCTAssertTrue(store.log(.meal))
        XCTAssertNotNil(store.lastLogged)
        store.select(milo)
        XCTAssertNil(store.lastLogged)
    }
    func testScheduleUsesEnteredTimesAndMatchesGivenAndSkipped() {
        let medication = med(minutes: [480, 1200])
        let today = day(2026, 11, 6)
        let slots = ScheduleEngine.slots(for: medication, on: today, events: [], calendar: calendar)
        XCTAssertEqual(slots.count, 2)
        let given = event(.meds, medicationID: medication.id, scheduledAt: slots[0].scheduledAt, status: .given)
        let skipped = event(.meds, medicationID: medication.id, scheduledAt: slots[1].scheduledAt, status: .skipped)
        let updated = ScheduleEngine.slots(for: medication, on: today, events: [given, skipped], calendar: calendar)
        XCTAssertTrue(updated.allSatisfy { !$0.pending })
        XCTAssertEqual(updated[1].entries.first?.doseStatus, .skipped)
    }
    func testTwoDosesAtSameSlotRemainAttributed() {
        let medication = med()
        let today = day(2026, 11, 6)
        let slot = ScheduleEngine.slots(for: medication, on: today, events: [], calendar: calendar)[0]
        let events = [event(.meds, author: "Jack", medicationID: medication.id, scheduledAt: slot.scheduledAt, status: .given), event(.meds, author: "Sam", medicationID: medication.id, scheduledAt: slot.scheduledAt, status: .given)]
        XCTAssertEqual(ScheduleEngine.slots(for: medication, on: today, events: events, calendar: calendar)[0].entries.count, 2)
    }
    func testAsNeededWeekdaysStartAndEndDates() {
        var medication = med()
        medication.weekdays = [2]
        XCTAssertTrue(ScheduleEngine.slots(for: medication, on: day(2026, 11, 3), events: [], calendar: calendar).isEmpty)
        XCTAssertEqual(ScheduleEngine.slots(for: medication, on: day(2026, 11, 2), events: [], calendar: calendar).count, 1)
        medication.startDate = day(2026, 12, 1)
        XCTAssertTrue(ScheduleEngine.slots(for: medication, on: day(2026, 11, 2), events: [], calendar: calendar).isEmpty)
        medication.startDate = day(2026, 1, 1); medication.endDate = day(2026, 10, 1)
        XCTAssertTrue(ScheduleEngine.slots(for: medication, on: day(2026, 11, 2), events: [], calendar: calendar).isEmpty)
        medication.endDate = nil; medication.asNeeded = true
        XCTAssertTrue(ScheduleEngine.slots(for: medication, on: day(2026, 11, 2), events: [], calendar: calendar).isEmpty)
    }
    func testDSTClockTimesAndSkippedHourSlots() {
        for date in [day(2026, 3, 8), day(2026, 11, 1)] {
            let slots = ScheduleEngine.slots(for: med(minutes: [480, 1200]), on: date, events: [], calendar: calendar)
            XCTAssertEqual(slots.map { calendar.component(.hour, from: $0.scheduledAt) }, [8, 20])
        }
        let slots = ScheduleEngine.slots(for: med(minutes: [120, 150]), on: day(2026, 3, 8), events: [], calendar: calendar)
        XCTAssertEqual(Set(slots.map(\.scheduledAt)).count, 2)
    }
    func testCorrectingDoseToDeletedMakesSlotPendingAgain() {
        let medication = med()
        let slot = ScheduleEngine.slots(for: medication, on: .now, events: [], calendar: calendar)[0]
        let original = event(.meds, medicationID: medication.id, scheduledAt: slot.scheduledAt, status: .given)
        XCTAssertTrue(store.append(original)); XCTAssertTrue(store.correct(original, action: .delete))
        XCTAssertTrue(ScheduleEngine.slots(for: medication, on: .now, events: store.events, calendar: calendar)[0].pending)
    }
    func testDueEngineUsesCalendarDaysAndCompletion() {
        let date = day(2026, 11, 1)
        let item = DueItem(petID: store.pet!.id, name: "Walk", minutes: 480, intervalDays: 2, startDate: date, editedBy: "Jack")
        let due = DueEngine.occurrences(for: item, from: date, days: 5, events: [], calendar: calendar)
        XCTAssertEqual(due.count, 3)
        XCTAssertEqual(due.map { calendar.component(.hour, from: $0.date) }, [8, 8, 8])
        let completed = EventRecord(petID: item.petID, kind: .due, author: "Sam", authorID: "2", dueItemID: item.id, scheduledAt: due[0].date)
        XCTAssertTrue(DueEngine.occurrences(for: item, from: date, days: 1, events: [completed], calendar: calendar)[0].completed)
    }
    func testOnlyReminderPhoneGetsMedicationNotificationsAndNoDoneAction() {
        let medication = med()
        let now = day(2026, 11, 6)
        let own = ReminderPlanner.plan(medications: [medication], items: [], events: [], phoneID: store.phoneID, writablePets: [store.pet!.id], now: now, calendar: calendar)
        XCTAssertEqual(own.count, 7)
        XCTAssertTrue(own.allSatisfy { $0.isMedication && $0.actions.isEmpty && $0.category == "pet.medication" && $0.body.contains("sync time") })
        XCTAssertTrue(ReminderPlanner.plan(medications: [medication], items: [], events: [], phoneID: "other", writablePets: [store.pet!.id], now: now, calendar: calendar).isEmpty)
    }
    func testReadOnlyStopsRemindersButDueItemsHaveDone() {
        let medication = med()
        let now = day(2026, 11, 6)
        let item = DueItem(petID: store.pet!.id, name: "Walk", startDate: now, remindersEnabled: true, editedBy: "Jack")
        XCTAssertTrue(ReminderPlanner.plan(medications: [medication], items: [item], events: [], phoneID: store.phoneID, writablePets: [], now: now).isEmpty)
        let due = ReminderPlanner.plan(medications: [], items: [item], events: [], phoneID: store.phoneID, writablePets: [item.petID], now: now)
        XCTAssertFalse(due.isEmpty)
        XCTAssertEqual(due.first?.actions, ["MARK_DONE"])
    }
    func testMedicationReminderUsesThatMedicationsLastDose() {
        let a = UUID(), b = UUID()
        let earlier = event(.meds, at: Date.now.addingTimeInterval(-600), medicationID: a, status: .given)
        let later = event(.meds, at: .now, medicationID: b, status: .given)
        XCTAssertEqual(NowSummary.lastDose(a, events: [earlier, later])?.id, earlier.id)
        XCTAssertEqual(NowSummary.lastDose(b, events: [earlier, later])?.id, later.id)
    }
    func testStaleDisconnectedAndOldImport() {
        let now = Date.now
        XCTAssertTrue(SyncFreshness.isStale(lastSuccess: now, connected: false, now: now))
        XCTAssertTrue(SyncFreshness.isStale(lastSuccess: nil, connected: true, now: now))
        XCTAssertTrue(SyncFreshness.isStale(lastSuccess: now.addingTimeInterval(-301), connected: true, now: now))
        XCTAssertFalse(SyncFreshness.isStale(lastSuccess: now, connected: true, now: now))
    }
    func testOnlySuccessfulImportAdvancesSyncTime() {
        let sync = CloudSyncState(defaults: defaults, cloudEnabled: true)
        let now = Date.now
        sync.ended(isImport: false, isSetup: false, at: now, succeeded: true, error: nil)
        XCTAssertNil(sync.lastSynced)
        sync.ended(isImport: true, isSetup: false, at: now, succeeded: false, error: NSError(domain: "test", code: 1))
        XCTAssertNil(sync.lastSynced)
        sync.ended(isImport: true, isSetup: false, at: now, succeeded: true, error: nil)
        XCTAssertEqual(sync.lastSynced, now)
    }
    func testExportContainsEveryCorrectionAndEscapesCSV() {
        let original = EventRecord(petID: store.pet!.id, kind: .meal, author: "Jack", authorID: "1", note: "A, \"quoted\"\nline")
        XCTAssertTrue(store.append(original)); XCTAssertTrue(store.correct(original, action: .delete))
        let csv = LogExport.csv(pets: store.pets, medications: [], events: store.events)
        XCTAssertTrue(csv.contains("\"A, \"\"quoted\"\"\nline\""))
        XCTAssertTrue(csv.contains(original.id.uuidString)); XCTAssertTrue(csv.contains("\"delete\""))
        XCTAssertTrue(csv.contains("target_id"))
    }
    func testSitterSnapshotAndOnePagePDF() throws {
        XCTAssertTrue(store.log(.meal))
        let snapshot = SitterSnapshot.build(pet: store.pet!, medications: [med()], dueItems: [], events: store.events, lastSync: nil)
        XCTAssertTrue(snapshot.lines.contains(where: { $0.contains("snapshot") }))
        XCTAssertTrue(snapshot.lines.contains(AppConfig.disclaimer))
        XCTAssertTrue(snapshot.lines.contains(where: { $0.contains("Reminder phone:") }))
        let data = try SitterPDF.data(snapshot)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("Milo") == true)
        XCTAssertTrue(pdf.string?.contains("Jack") == true)
    }
    func testOversizedSitterSheetFailsExplicitly() {
        let snapshot = SitterSnapshot(title: "Sheet", lines: Array(repeating: String(repeating: "long ", count: 60), count: 100))
        XCTAssertThrowsError(try SitterPDF.data(snapshot))
    }
    func testQRAndLinkParser() throws {
        let url = try XCTUnwrap(ShareInvite.url(in: "Join https://www.icloud.com/share/test-code today"))
        XCTAssertNil(ShareInvite.url(in: "https://evilicloud.com/share/test-code"))
        let cg = try XCTUnwrap(ShareInvite.qrCode(for: url))
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        let codes = detector.features(in: CIImage(cgImage: cg)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertEqual(codes.first, url.absoluteString)
    }
    func testCorrectorDoesNotReplacePersonWhoPerformedCare() {
        let original = event(author: "Sam")
        XCTAssertTrue(store.append(original))
        store.caregiver = "Jack"
        XCTAssertTrue(store.correct(original, action: .edit, note: "Time corrected"))
        XCTAssertEqual(store.visibleEvents.first?.performedBy, "Sam")
        XCTAssertEqual(store.visibleEvents.first?.author, "Jack")
    }
    func testJoiningPreservesAccessToOriginalLocalLog() {
        XCTAssertTrue(store.log(.meal))
        let original = store.household!
        let shared = Household(context: persistence.viewContext)
        shared.id = UUID(); shared.createdAt = .now
        persistence.viewContext.assign(shared, to: persistence.sharedStore)
        XCTAssertTrue(persistence.save(persistence.viewContext))
        defaults.set(true, forKey: "pendingShare")
        store.reload()
        XCTAssertFalse(store.isOwner)
        XCTAssertEqual(store.households.count, 2)
        store.selectHousehold(original)
        XCTAssertTrue(store.isOwner)
        XCTAssertEqual(store.pet?.name, "Milo")
        XCTAssertEqual(store.events.count, 1)
    }
    func testVersionLabelIncludesBuild() {
        XCTAssertEqual(AppConfig.versionLabel(info: ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "3"]), "1.0.0 (3)")
        XCTAssertEqual(AppConfig.versionLabel(info: ["CFBundleShortVersionString": "1.0.0"]), "1.0.0")
    }

    func testSettingsShowLastEditor() {
        var pet = store.pet!
        pet.name = "Updated"
        store.caregiver = "Sam"
        XCTAssertTrue(store.savePet(pet))
        XCTAssertEqual(store.pet?.editedBy, "Sam")
    }
    func testSaveFailureRollsBackAndReportsError() {
        let failure = Persistence(cloudKit: false, inMemory: true, saveOperation: { _ in throw NSError(domain: "save", code: 1) })
        let failingStore = EventStore(persistence: failure, defaults: defaults)
        XCTAssertFalse(failingStore.savePet(PetProfile(name: "Milo", editedBy: "Jack")))
        XCTAssertNotNil(failingStore.error)
        XCTAssertTrue(failingStore.pets.isEmpty)
    }
    func testStoreOpenFailureUsesReadOnlyStandIn() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("blocked".utf8).write(to: file)
        let closed = Persistence(cloudKit: false, directory: file.appendingPathComponent("unavailable"))
        XCTAssertTrue(closed.isStandingIn)
        let blocked = EventStore(persistence: closed, defaults: defaults)
        XCTAssertFalse(blocked.savePet(PetProfile(name: "Milo", editedBy: "Jack")))
        XCTAssertNotNil(blocked.error)
    }
    func testRegisteredMedicationCategoryHasNoCompletionAction() async {
        Reminders.register()
        let categories = await UNUserNotificationCenter.current().notificationCategories()
        XCTAssertEqual(categories.first { $0.identifier == "pet.medication" }?.actions.count, 0)
        XCTAssertEqual(categories.first { $0.identifier == "pet.due" }?.actions.map(\.identifier), ["MARK_DONE"])
    }
    func testOutOfOrderCorrectionWaitsForOriginal() {
        let original = event()
        let correction = EventRecord(petID: original.petID, kind: .meal, author: "Sam", authorID: "2", action: .edit, targetID: original.id, note: "Corrected")
        XCTAssertTrue(EventLedger.visible([correction]).isEmpty)
        XCTAssertEqual(EventLedger.visible([correction, original]).count, 1)
    }
    func testTwoPersonImport20EntriesOfflineCatchupAndRedelivery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let disk = Persistence(cloudKit: false, directory: directory)
        let phone = EventStore(persistence: disk, defaults: defaults)
        XCTAssertTrue(phone.savePet(PetProfile(name: "Milo", editedBy: "Jack")))
        let id = phone.pet!.id
        let incoming = (0..<20).map { index in EventRecord(petID: id, kind: .meal, author: index % 2 == 0 ? "Sam" : "Jack", authorID: "peer-\(index % 2)") }
        let relay = SimPartnerRelay(persistence: disk)
        try relay.deliver(incoming, to: phone.household!.id!)
        phone.reload()
        XCTAssertEqual(phone.events.count, 20)
        XCTAssertEqual(Set(phone.events.map(\.author)), ["Jack", "Sam"])
        try relay.deliver(incoming, to: phone.household!.id!)
        phone.reload()
        XCTAssertEqual(phone.events.count, 20)
        XCTAssertTrue(phone.log(.walk))
        let second = EventStore(persistence: disk, defaults: defaults)
        XCTAssertEqual(second.events.count, 21)
    }
    func testMeasurementContractCountsDatesAndSafeSurfacesOnly() {
        ConversionDiagnostics.defaultsOverride = defaults
        defer { ConversionDiagnostics.defaultsOverride = nil }
        ConversionDiagnostics.recordAppOpen()
        ConversionDiagnostics.recordPitchView(impressionID: "pet_invite")
        let first = day(2026, 11, 1)
        Measurements.recordLog(at: first, defaults: defaults, calendar: calendar)
        Measurements.recordLog(at: day(2026, 11, 7), defaults: defaults, calendar: calendar)
        for key in ["invite_tapped_at", "invite_sent_at", "joined_share_at"] { Measurements.once(key, at: first, defaults: defaults) }
        Measurements.trialSource("invite", defaults: defaults)
        Measurements.trialSource("pet name", defaults: defaults)
        ConversionDiagnostics.recordConversion(plan: AppConfig.yearly, startedTrial: true, offeringID: AppConfig.offering)
        let attributes = Measurements.attributes(defaults: defaults)
        for key in ["pitch_views_total", "pitch_views_invite", "pitch_last", "pitch_first_seen", "days_since_first_pitch", "days_since_install", "opens_before_first_pitch", "converted_surface", "converted_at", "pitch_views_at_convert", "days_to_convert", "converted_plan", "converted_with_trial", "converted_offering", "offering_id"] + Measurements.dateKeys { XCTAssertNotNil(attributes[key], key) }
        XCTAssertEqual(attributes["trial_source"], "invite")
        XCTAssertEqual(attributes["logs_count"], "2")
        XCTAssertFalse(attributes.values.contains("Milo"))
    }

    func testRatingAskStartsOnSecondLaunchAndRespectsCooldown() throws {
        let suite = "rating-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date.now
        RatingAsk.noteLaunch(defaults: defaults)
        XCTAssertFalse(RatingAsk.isDue(at: now, defaults: defaults))
        RatingAsk.noteLaunch(defaults: defaults)
        XCTAssertTrue(RatingAsk.isDue(at: now, defaults: defaults))
        RatingAsk.markAsked(at: now, defaults: defaults)
        XCTAssertFalse(RatingAsk.isDue(at: now.addingTimeInterval(RatingAsk.cooldown - 1), defaults: defaults))
        XCTAssertTrue(RatingAsk.isDue(at: now.addingTimeInterval(RatingAsk.cooldown), defaults: defaults))
        RatingAsk.markWroteReview(defaults: defaults)
        XCTAssertFalse(RatingAsk.isDue(at: now.addingTimeInterval(RatingAsk.cooldown * 2), defaults: defaults))
    }

    func testSuggestionDraftTargetsThisAppAndStatusesReadPlainly() throws {
        let draft = FeedbackDraft(installID: "install-1", name: "Jack", text: "Add a chart", context: ["channel": "testflight"], screenshot: nil)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        XCTAssertEqual(body["app"] as? String, "pet")
        XCTAssertEqual(body["install_id"] as? String, "install-1")
        let item = { (status: String, build: String?) in FeedbackItem(id: 1, createdAt: .now, text: "x", status: status, reply: nil, build: build) }
        XCTAssertEqual(item("new", nil).statusLabel, "Received")
        XCTAssertEqual(item("working", nil).statusLabel, "Being built")
        XCTAssertEqual(item("shipped", "7").statusLabel, "In TestFlight build 7")
        XCTAssertEqual(FeedbackService.installID, FeedbackService.installID)
    }
}
