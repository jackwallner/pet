import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var events: EventStore
    @State private var selected: EventRecord?
    @State private var add = false
    @State private var showAll = false
    @State private var search = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var shown: [EventRecord] {
        let entries = showAll ? events.events.filter { $0.petID == events.pet?.id } : events.visibleEvents
        return query.isEmpty ? entries : entries.filter(matches)
    }
    var body: some View {
        List {
            if events.pet != nil {
                Section { Toggle("Correction history", isOn: $showAll).accessibilityIdentifier("history.corrections") }
            }
            if shown.isEmpty {
                if query.isEmpty { ContentUnavailableView("Your log starts here", systemImage: "clock") }
                else { ContentUnavailableView.search(text: query) }
            }
            ForEach(shown) { event in
                Button { selected = event } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        // Side by side at large text sizes breaks "Meal" mid-word.
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))) {
                            Label(eventTitle(event), systemImage: event.kind.symbol).foregroundStyle(.primary)
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Text(event.occurredAt, format: .dateTime.hour().minute()).foregroundStyle(.secondary)
                        }
                        Text("\(event.performedBy) · \(event.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !event.note.isEmpty { Text(event.note).font(.subheadline).foregroundStyle(.secondary) }
                        if event.action != .log { Text(event.action.rawValue.capitalized).font(.footnote).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("history.entry")
            }
        }
        .biscuitList().navigationTitle("History")
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Activity, person, note")
        .toolbar {
            if events.pet != nil { ToolbarItem(placement: .topBarTrailing) { Button { add = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add an earlier entry").disabled(!events.canWrite) } }
        }
        .sheet(item: $selected) { event in NavigationStack { CorrectionView(event: event) } }
        .sheet(isPresented: $add) { NavigationStack { EarlierEntryView() } }
    }
    private func matches(_ event: EventRecord) -> Bool {
        [eventTitle(event), event.kind.rawValue, event.performedBy, event.note].contains { $0.localizedStandardContains(query) }
    }
    private func eventTitle(_ event: EventRecord) -> String {
        if let id = event.medicationID, let med = events.medications.first(where: { $0.id == id }) {
            return "\(med.name)\(event.doseStatus.map { " · \($0.rawValue)" } ?? "")"
        }
        return event.kind == .due ? event.note : event.kind.rawValue
    }
}

struct CorrectionView: View {
    let event: EventRecord
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var at = Date.now
    @State private var note = ""
    @State private var status = DoseStatus.given
    @State private var confirmDelete = false
    var body: some View {
        Form {
            Section {
                DatePicker("Actual time", selection: $at, in: ...Date.now)
                if event.medicationID != nil { Picker("Status", selection: $status) { ForEach(DoseStatus.allCases) { Text($0.rawValue).tag($0) } } }
                TextField("Note", text: $note, axis: .vertical)
            }
            Section {
                Button("Save correction") {
                    if events.correct(event, action: .edit, at: at, note: note, status: event.medicationID == nil ? nil : status) { dismiss() }
                }.disabled(!events.canWrite).accessibilityIdentifier("correction.save")
                Button("Delete entry", role: .destructive) { confirmDelete = true }.disabled(!events.canWrite).accessibilityIdentifier("correction.delete")
            }
            Section("Correction history") {
                ForEach(EventLedger.chain(for: event, in: events.events)) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(item.action.rawValue.capitalized) · \(item.author)")
                        Text(item.recordedAt, format: .dateTime.month().day().hour().minute()).font(.footnote).foregroundStyle(.secondary)
                        if !item.note.isEmpty { Text(item.note).font(.subheadline) }
                    }
                }
            }
        }
        .biscuitList().navigationTitle("Correct entry").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { DismissButton() } }
        .onAppear { at = event.occurredAt; note = event.note; status = event.doseStatus ?? .given }
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete entry", role: .destructive) { if events.correct(event, action: .delete) { dismiss() } }
        } message: { Text("The original and this correction stay in history and export.") }
    }
}

struct EarlierEntryView: View {
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var kind = EventKind.meal
    @State private var at = Date.now
    @State private var note = ""
    private var kinds: [EventKind] {
        guard let pet = events.pet else { return [] }
        let shown = pet.shownLogKinds.filter { $0 != .meds }
        return shown.isEmpty ? pet.species.kinds.filter { $0 != .meds } : shown
    }
    var body: some View {
        Form {
            Picker("Activity", selection: $kind) { ForEach(kinds) { Text($0.rawValue).tag($0) } }
            DatePicker("Actual time", selection: $at, in: ...Date.now)
            TextField("Note", text: $note, axis: .vertical)
        }.biscuitList().navigationTitle("Earlier entry").navigationBarTitleDisplayMode(.inline)
        .onAppear { if !kinds.contains(kind), let first = kinds.first { kind = first } }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DismissButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { if events.log(kind, at: at, note: note) { dismiss() } }.disabled(!events.canWrite) }
        }
    }
}
