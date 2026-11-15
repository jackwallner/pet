import StoreKit
import SwiftUI

struct NowView: View {
    @EnvironmentObject private var events: EventStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.requestReview) private var requestReview
    @State private var meds = false
    @State private var addPet = false
    @State private var editPet = false
    @State private var reminderDose: Medication?
    @State private var tileDose: Medication?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LapseBanner()
                if let pet = events.pet {
                    PetHeader(pet: pet) { editPet = true }
                    if events.isSharedLog { SyncLine(sync: events.sync, store: events.syncStoreID) }
                    if let medication = events.petMedications.first(where: { $0.id == events.notificationMedicationID }) {
                        Button { reminderDose = medication } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(medication.name, systemImage: "pills").font(.headline)
                                    if let dose = NowSummary.lastDose(medication.id, events: events.events) {
                                        Text("\(dose.doseStatus?.rawValue ?? "Logged") \(NowSummary.when(dose.occurredAt)) · \(dose.performedBy)")
                                    } else { Text("Last dose: Nothing logged") }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityElement(children: .combine).accessibilityIdentifier("medication.reminderContext")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(pet.shownLogKinds) { kind in
                            let last = NowSummary.last(kind, petID: pet.id, events: events.events)
                            LogButton(kind: kind, last: last, medication: events.medicationLabel(last)) {
                                // Decided at the tap: a sheet that re-decided live would swap to a dose form mid-edit.
                                if kind == .meds, events.petMedications.count == 1 { tileDose = events.petMedications.first }
                                else if kind == .meds { meds = true }
                                else if events.log(kind) { askForRatingSoon() }
                            }
                        }
                    }
                    NextList(sync: events.sync)
                } else {
                    ContentUnavailableView("Add your pet", systemImage: "pawprint")
                    PrimaryButton(title: "Add a pet") { addPet = true }
                }
            }.padding(20)
        }
        .background(Theme.background)
        .undoBar()
        .navigationTitle(events.pet?.name ?? AppConfig.displayName)
        .toolbar {
            if events.pets.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(events.pets) { pet in Button(pet.name) { events.select(pet.id) } }
                    } label: { Image(systemName: "pawprint") }.accessibilityLabel("Choose pet")
                }
            }
        }
        .sheet(isPresented: $meds) { NavigationStack { MedicationsView().toolbar { ToolbarItem(placement: .cancellationAction) { DismissButton() } } } }
        // One medication: the tile logs it, like every other tile, instead of opening a list of one.
        .sheet(item: $tileDose) { med in NavigationStack { DoseView(medication: med, scheduledAt: events.notificationMedicationID == med.id ? notifiedSlot : nil) } }
        .sheet(item: $reminderDose) { med in NavigationStack { DoseView(medication: med, scheduledAt: notifiedSlot) } }
        .sheet(isPresented: $addPet) { NavigationStack { PetEditor(profile: nil) } }
        .sheet(isPresented: $editPet) { NavigationStack { PetEditor(profile: events.pet) } }
    }
    /// A reminder left in Notification Center can be tapped a day late. Its time is a preset only while it is
    /// near enough to be this dose; otherwise the actual time picks, so a missed slot never takes today's dose.
    private var notifiedSlot: Date? { events.notificationScheduledAt.flatMap { DoseSlots.nearest([$0], to: .now) } }
    private func askForRatingSoon() {
        guard !LaunchOptions.contains("-UITesting"), RatingAsk.isDue() else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard !meds, !addPet, !editPet, reminderDose == nil, tileDose == nil, RatingAsk.isDue() else { return }
            RatingAsk.markAsked()
            requestReview()
        }
    }
}

private struct PetHeader: View {
    let pet: PetProfile
    let action: () -> Void
    @EnvironmentObject private var events: EventStore
    @Environment(\.dynamicTypeSize) private var typeSize
    private var image: UIImage? { events.petPhotos[pet.id] }
    private var age: String? { pet.birthday.flatMap { PetAge.text(birthday: $0) } }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Beside the avatar, large text breaks "12 weeks old" one word per line.
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))) {
                    PetAvatar(image: image, symbol: pet.species.symbol, size: 72)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pet.species.rawValue).font(.headline)
                        if let age { Text(age).font(.subheadline).foregroundStyle(.secondary) }
                        if image == nil && events.canWrite { Text("Add photo").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent) }
                    }.fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityIdentifier("now.pet")
    }
}

private struct LogButton: View {
    let kind: EventKind
    let last: EventRecord?
    var medication: String?
    let action: () -> Void
    @EnvironmentObject private var events: EventStore
    var body: some View {
        // One clock for the tile and its spoken label, so neither keeps saying a bare time past midnight.
        TimelineView(.everyMinute) { time in button(now: time.date) }
    }
    private func button(now: Date) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: kind.symbol).font(.title2).frame(width: 32, height: 32, alignment: .leading).accessibilityHidden(true)
                Text(kind.rawValue).font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 3) {
                    if let last {
                        Text(NowSummary.when(last.occurredAt, now: now)).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(.primary)
                        Text(detail(last)).font(.subheadline).foregroundStyle(.secondary)
                    } else { Text("Nothing logged").font(.subheadline).foregroundStyle(.secondary) }
                }.fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(!events.canWrite && kind != .meds)
        .accessibilityIdentifier("log.\(kind.rawValue.lowercased())")
        .accessibilityLabel("\(kind.rawValue). \(last.map { "Last \(NowSummary.when($0.occurredAt, now: now)), \(detail($0))" } ?? "Nothing logged")")
    }
    private func detail(_ last: EventRecord) -> String {
        ([last.performedBy] + [last.doseStatus?.rawValue, medication].compactMap { $0 }).joined(separator: " · ")
    }
}

struct NextList: View {
    @EnvironmentObject private var events: EventStore
    @ObservedObject var sync: CloudSyncState
    @State private var dose: DoseSelection?
    struct DoseSelection: Identifiable {
        let medication: Medication
        let at: Date
        var id: String { "\(medication.id)-\(at)" }
    }
    private var doses: [DoseSelection] {
        events.petMedications.flatMap { med in
            ScheduleEngine.slots(for: med, on: .now, events: events.events).filter(\.pending).map { DoseSelection(medication: med, at: $0.scheduledAt) }
        }.sorted { $0.at < $1.at }
    }
    private var due: [DueOccurrence] {
        events.petDueItems.flatMap { DueEngine.occurrences(for: $0, from: .now, days: 1, events: events.events) }
            .filter { !$0.completed }.sorted { $0.date < $1.date }
    }
    var body: some View {
        // Redrawn on a clock so "not logged" turns into "not logged on this iPhone" the moment the log goes stale.
        TimelineView(.periodic(from: .now, by: 10)) { time in list(now: time.date) }
    }
    @ViewBuilder private func list(now: Date) -> some View {
        let behind = events.isSharedLog && sync.stale(store: events.syncStoreID, at: now)
        if !doses.isEmpty || !due.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Next").font(.title2.weight(.semibold)).padding(.bottom, 12)
                ForEach(doses) { slot in
                    Button { dose = slot } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(slot.medication.name).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 16)
                            // A phone that is behind can only speak for itself, not for a partner's dose.
                            Text(slot.at < now ? "\(slot.at.formatted(date: .omitted, time: .shortened)), not logged\(behind ? " on this iPhone" : "")" : slot.at.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                        }.padding(.vertical, 14).contentShape(Rectangle()).accessibilityElement(children: .combine)
                    }.buttonStyle(.plain)
                    Divider()
                }
                ForEach(due) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                            Text(item.date, style: .time).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { _ = events.log(.due, note: item.name, dueItemID: item.itemID, scheduledAt: item.date) } label: { Image(systemName: "checkmark.circle").font(.title2).frame(minWidth: 44, minHeight: 44) }
                            .disabled(!events.canWrite).accessibilityLabel("Mark \(item.name) done")
                    }.padding(.vertical, 8)
                    Divider()
                }
            }
            .sheet(item: $dose) { slot in NavigationStack { DoseView(medication: slot.medication, scheduledAt: slot.at) } }
        }
    }
}

/// The confirmation and Undo for the latest entry, on every tab a caregiver can log from.
/// The clock, haptic and announcement live once in `UndoClock` so three tabs never speak it three times.
struct UndoBar: ViewModifier {
    @EnvironmentObject private var events: EventStore
    func body(content: Content) -> some View {
        // Pinned, so a log tap is confirmed even when large text pushes the content past the fold.
        content.safeAreaInset(edge: .bottom) {
            if let last = events.lastLogged {
                HStack(alignment: .firstTextBaseline) {
                    Text(UndoCopy.text(last, medication: events.medicationLabel(last))).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Undo") {
                        if events.correct(last, action: .undo) {
                            events.lastLogged = nil
                            AccessibilityNotification.Announcement("Undone").post()
                        }
                    }.font(.headline).frame(minHeight: 44).accessibilityIdentifier("log.undo")
                }.padding(.horizontal).padding(.vertical, 8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    .padding(.horizontal, 20).padding(.bottom, 8)
            }
        }
    }
}

struct UndoClock: ViewModifier {
    @EnvironmentObject private var events: EventStore
    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.success, trigger: events.lastLogged?.id) { _, new in new != nil }
            .task(id: events.lastLogged?.id) {
                guard let last = events.lastLogged else { return }
                // An Undo left up for hours is one stray tap from erasing the last real feeding.
                // The 30 seconds run from the entry, so switching tabs cannot revive it.
                let remaining = 30 - Date.now.timeIntervalSince(last.recordedAt)
                if remaining > 25 { AccessibilityNotification.Announcement(UndoCopy.text(last, medication: events.medicationLabel(last))).post() }
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                guard !Task.isCancelled, events.lastLogged?.id == last.id else { return }
                events.lastLogged = nil
            }
    }
}
extension View {
    func undoBar() -> some View { modifier(UndoBar()) }
}

enum UndoCopy {
    static func text(_ event: EventRecord, medication: String? = nil) -> String {
        guard event.action == .log else { return "Correction saved" }
        switch event.kind {
        case .meds:
            let dose = medication.map { "\($0) dose" } ?? "dose"
            return event.doseStatus == .skipped ? "Logged skipped \(dose)" : "Logged \(dose)"
        case .due: return event.note.isEmpty ? "Marked done" : "\(event.note) done"
        default: return "Logged \(event.kind.rawValue.lowercased())"
        }
    }
}
