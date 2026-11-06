import StoreKit
import SwiftUI

struct NowView: View {
    @EnvironmentObject private var events: EventStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.requestReview) private var requestReview
    @State private var meds = false
    @State private var addPet = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LapseBanner()
                if let pet = events.pet {
                    if events.isSharedLog { SyncLine(sync: events.sync) }
                    if let medication = events.petMedications.first(where: { $0.id == events.notificationMedicationID }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(medication.name, systemImage: "pills").font(.headline)
                            if let dose = NowSummary.lastDose(medication.id, events: events.events) {
                                Text("\(dose.doseStatus?.rawValue ?? "Logged") \(dose.occurredAt.formatted(date: .abbreviated, time: .shortened)) · \(dose.performedBy)")
                            } else { Text("Last dose: Nothing logged") }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("medication.reminderContext")
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                        ForEach(pet.species.kinds) { kind in
                            LogButton(kind: kind, last: NowSummary.last(kind, petID: pet.id, events: events.events)) {
                                if kind == .meds { meds = true }
                                else if events.log(kind) { askForRatingSoon() }
                            }
                        }
                    }
                    if let last = events.lastLogged {
                        HStack(alignment: .firstTextBaseline) {
                            Text(last.action == .log ? "Logged \(last.kind.rawValue.lowercased())" : "Correction saved").font(.subheadline)
                            Spacer()
                            Button("Undo") {
                                if events.correct(last, action: .undo) { events.lastLogged = nil }
                            }.accessibilityIdentifier("log.undo")
                        }.padding().background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                    NextList()
                } else {
                    ContentUnavailableView("Add your pet", systemImage: "pawprint")
                    PrimaryButton(title: "Add a pet") { addPet = true }
                }
            }.padding(20)
        }
        .background(Theme.background)
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
        .sheet(isPresented: $addPet) { NavigationStack { PetEditor(profile: nil) } }
    }
    private func askForRatingSoon() {
        guard !LaunchOptions.contains("-UITesting"), RatingAsk.isDue() else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard !meds, !addPet, RatingAsk.isDue() else { return }
            RatingAsk.markAsked()
            requestReview()
        }
    }
}

private struct LogButton: View {
    let kind: EventKind
    let last: EventRecord?
    let action: () -> Void
    @EnvironmentObject private var events: EventStore
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: kind.symbol).font(.title2).frame(width: 32, height: 32, alignment: .leading).accessibilityHidden(true)
                Text(kind.rawValue).font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 3) {
                    if let last {
                        Text(last.occurredAt, format: .dateTime.hour().minute()).font(.subheadline.monospacedDigit())
                        Text(last.performedBy + (last.doseStatus.map { " · \($0.rawValue)" } ?? "")).font(.footnote)
                    } else { Text("Nothing logged").font(.footnote) }
                }.foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .padding(16).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).disabled(!events.canWrite && kind != .meds)
        .accessibilityIdentifier("log.\(kind.rawValue.lowercased())")
        .accessibilityLabel("\(kind.rawValue). \(last.map { "Last \($0.occurredAt.formatted(date: .omitted, time: .shortened)), \($0.performedBy)" } ?? "Nothing logged")")
    }
}

struct NextList: View {
    @EnvironmentObject private var events: EventStore
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
        if !doses.isEmpty || !due.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Next").font(.title2.weight(.semibold)).padding(.bottom, 12)
                ForEach(doses) { slot in
                    Button { dose = slot } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(slot.medication.name).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 16)
                            Text(slot.at, style: .time).foregroundStyle(.secondary)
                        }.padding(.vertical, 14).contentShape(Rectangle())
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
