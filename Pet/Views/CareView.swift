import SwiftUI

struct CareView: View {
    @EnvironmentObject private var events: EventStore
    @State private var newDue = false
    @State private var selectedDue: DueItem?
    var body: some View {
        List {
            Section {
                NavigationLink { MedicationsView() } label: { Label("Medications", systemImage: "pills") }
                    .accessibilityIdentifier("care.medications")
            }
            Section("Recurring items") {
                ForEach(events.petDueItems) { item in
                    Button { selectedDue = item } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name).foregroundStyle(.primary)
                            Text("\(time(item.minutes)), \(item.intervalDays == 1 ? "every day" : "every \(item.intervalDays) days")").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Add a recurring item") { newDue = true }.disabled(!events.canWrite)
                    .accessibilityIdentifier("care.addDue")
            }
        }.biscuitList().navigationTitle("Care")
        .sheet(isPresented: $newDue) { NavigationStack { DueEditor(item: nil) } }
        .sheet(item: $selectedDue) { item in NavigationStack { DueEditor(item: item) } }
    }
    private func time(_ minutes: Int) -> String { ScheduleEngine.date(forMinutes: minutes, onDayOf: .now)?.formatted(date: .omitted, time: .shortened) ?? "" }
}

struct MedicationsView: View {
    @EnvironmentObject private var events: EventStore
    @State private var add = false
    @State private var editing: Medication?
    @State private var dose: Medication?
    var body: some View {
        List {
            if events.isSharedLog { Section { SyncLine(sync: events.sync) } }
            if events.petMedications.isEmpty { ContentUnavailableView("Medications", systemImage: "pills") }
            ForEach(events.petMedications) { med in
                Section {
                    Button { dose = med } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(med.name).font(.headline).foregroundStyle(.primary)
                            if let last = events.visibleEvents.first(where: { $0.medicationID == med.id }) {
                                Text("\(last.doseStatus?.rawValue ?? "Logged") \(last.occurredAt.formatted(date: .abbreviated, time: .shortened)) · \(last.performedBy)")
                                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            } else { Text("Nothing logged").font(.subheadline).foregroundStyle(.secondary) }
                            Text("Reminder phone: \(med.reminderPhoneName)").font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("medication.dose")
                    Button("Edit medication") { editing = med }.disabled(!events.canWrite)
                }
            }
        }.biscuitList().navigationTitle("Medications").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { add = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add medication").accessibilityIdentifier("medication.add").disabled(!events.canWrite) } }
        .sheet(isPresented: $add) { NavigationStack { MedicationEditor(medication: nil) } }
        .sheet(item: $editing) { med in NavigationStack { MedicationEditor(medication: med) } }
        .sheet(item: $dose) { med in NavigationStack { DoseView(medication: med, scheduledAt: pendingTime(med)) } }
    }
    private func pendingTime(_ med: Medication) -> Date? {
        let pending = ScheduleEngine.slots(for: med, on: .now, events: events.events).filter(\.pending)
        return pending.last(where: { $0.scheduledAt <= .now })?.scheduledAt ?? pending.first?.scheduledAt
    }
}

struct DoseView: View {
    let medication: Medication
    let scheduledAt: Date?
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var status = DoseStatus.given
    @State private var at = Date.now
    @State private var note = ""
    var body: some View {
        Form {
            Section {
                if events.isSharedLog { SyncLine(sync: events.sync) }
                if let last = events.visibleEvents.first(where: { $0.medicationID == medication.id }) {
                    LabeledContent("Last dose") { Text("\(last.doseStatus?.rawValue ?? "Logged"), \(last.occurredAt.formatted(date: .abbreviated, time: .shortened)) · \(last.performedBy)") }
                } else { Text("Last dose: Nothing logged") }
            }
            Section {
                Picker("Status", selection: $status) { ForEach(DoseStatus.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                DatePicker("Actual time", selection: $at, in: ...Date.now)
                if let scheduledAt { LabeledContent("Scheduled", value: scheduledAt.formatted(date: .abbreviated, time: .shortened)) }
                TextField("Note", text: $note, axis: .vertical)
            }
            if !medication.instructions.isEmpty { Section("Your instructions") { Text(medication.instructions) } }
            Section {
                Button(status == .given ? "Log given" : "Log skipped") {
                    if events.log(.meds, at: at, note: note, medicationID: medication.id, scheduledAt: scheduledAt, doseStatus: status) { dismiss() }
                }.disabled(!events.canWrite).accessibilityIdentifier("dose.save")
            }
        }.biscuitList().navigationTitle(medication.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { DismissButton() } }
    }
}

struct MedicationEditor: View {
    let medication: Medication?
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var instructions = ""
    @State private var times: [Int] = [480]
    @State private var weekdays: Set<Int> = []
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var hasEnd = false
    @State private var asNeeded = false
    @State private var reminders = false
    @State private var phoneID = ""
    @State private var phoneName = ""
    @State private var permissionDenied = false
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                TextField("Medication name", text: $name).accessibilityIdentifier("medication.name")
                TextField("Veterinarian's instructions", text: $instructions, axis: .vertical)
            }
            Section("Schedule") {
                Toggle("As needed", isOn: $asNeeded)
                if !asNeeded {
                    ForEach(times.indices, id: \.self) { index in
                        HStack {
                            DatePicker("Time \(index + 1)", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                            if times.count > 1 { Button(role: .destructive) { times.remove(at: index) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove time \(index + 1)") }
                        }
                    }
                    if times.count < 8 { Button("Add a time") { times.append((times.last ?? 420) + 60 >= 1440 ? 0 : (times.last ?? 420) + 60) } }
                    NavigationLink {
                        List(1...7, id: \.self) { day in
                            Button { if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) } } label: {
                                HStack { Text(Calendar.current.weekdaySymbols[day - 1]); Spacer(); if weekdays.contains(day) { Image(systemName: "checkmark") } }
                            }
                        }.navigationTitle("Days").biscuitList()
                    } label: { LabeledContent("Days", value: weekdays.isEmpty || weekdays.count == 7 ? "Every day" : weekdays.sorted().map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")) }
                    DatePicker("Starts", selection: $start, displayedComponents: .date)
                    Toggle("End date", isOn: $hasEnd)
                    if hasEnd { DatePicker("Ends", selection: $end, in: start..., displayedComponents: .date) }
                }
            }
            if !asNeeded {
                Section("Reminder phone") {
                    Text(phoneName)
                    if phoneID != events.phoneID { Button("Use this iPhone") { phoneID = events.phoneID; phoneName = "\(events.caregiver)'s iPhone" } }
                    Toggle("Reminders", isOn: $reminders).disabled(phoneID != events.phoneID)
                    if permissionDenied { Button("Open notification settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } }
                }
            }
            if let medication {
                Section { EditedLine(author: medication.editedBy, date: medication.editedAt) }
                Section { Button("Archive medication", role: .destructive) { var value = medication; value.archived = true; if events.saveMedication(value) { dismiss() } } }
            }
        }.biscuitList().navigationTitle(medication == nil ? "Add medication" : "Edit medication").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DismissButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !events.canWrite).accessibilityIdentifier("medication.save") }
        }
        .task { permissionDenied = await Reminders.isDenied() }
        .onAppear {
            guard !loaded else { return }; loaded = true
            if let med = medication {
                name = med.name; instructions = med.instructions; times = med.minutes; weekdays = Set(med.weekdays)
                start = med.startDate; end = med.endDate ?? max(.now, start); hasEnd = med.endDate != nil
                asNeeded = med.asNeeded; reminders = med.remindersEnabled; phoneID = med.reminderPhoneID; phoneName = med.reminderPhoneName
            } else { phoneID = events.phoneID; phoneName = "\(events.caregiver)'s iPhone" }
        }
    }
    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(get: { ScheduleEngine.date(forMinutes: times.indices.contains(index) ? times[index] : 480, onDayOf: .now) ?? .now }, set: { if times.indices.contains(index) { times[index] = ScheduleEngine.minutes(from: $0) } })
    }
    private func save() async {
        guard let pet = events.pet else { return }
        if reminders && phoneID == events.phoneID && !LaunchOptions.contains("-UITesting") {
            permissionDenied = !(await Reminders.requestPermission())
        }
        let value = Medication(id: medication?.id ?? UUID(), petID: pet.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                               instructions: instructions, minutes: Array(Set(times)).sorted(), weekdays: weekdays.sorted(), startDate: start,
                               endDate: hasEnd ? end : nil, asNeeded: asNeeded, reminderPhoneID: phoneID, reminderPhoneName: phoneName,
                               remindersEnabled: reminders && !asNeeded, editedBy: events.caregiver)
        if events.saveMedication(value) { dismiss() }
    }
}

struct DueEditor: View {
    let item: DueItem?
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var at = Date.now
    @State private var start = Date.now
    @State private var interval = 1
    @State private var reminders = false
    @State private var loaded = false
    @State private var permissionDenied = false
    var body: some View {
        Form {
            Section {
                TextField("Item name", text: $name).accessibilityIdentifier("due.name")
                DatePicker("Time", selection: $at, displayedComponents: .hourAndMinute)
                Stepper(interval == 1 ? "Every day" : "Every \(interval) days", value: $interval, in: 1...365)
                DatePicker("Starts", selection: $start, displayedComponents: .date)
                Toggle("Remind on this iPhone", isOn: $reminders)
                if permissionDenied { Button("Open notification settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } }
            }
            if let item {
                Section { EditedLine(author: item.editedBy, date: item.editedAt) }
                Section { Button("Archive item", role: .destructive) { var value = item; value.archived = true; if events.saveDueItem(value) { dismiss() } } }
            }
        }.biscuitList().navigationTitle(item == nil ? "Add recurring item" : "Edit recurring item").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DismissButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !events.canWrite).accessibilityIdentifier("due.save") }
        }
        .task { permissionDenied = await Reminders.isDenied() }
        .onAppear {
            guard !loaded else { return }; loaded = true
            if let item { name = item.name; at = ScheduleEngine.date(forMinutes: item.minutes, onDayOf: .now) ?? .now; interval = item.intervalDays; start = item.startDate; reminders = item.remindersEnabled && (item.reminderPhoneID ?? events.phoneID) == events.phoneID }
        }
    }
    private func save() async {
        guard let pet = events.pet else { return }
        if reminders && !LaunchOptions.contains("-UITesting") { _ = await Reminders.requestPermission() }
        // Another phone's reminder stays with it unless this phone takes it over.
        let elsewhere = item.flatMap { $0.remindersEnabled ? $0.reminderPhoneID : nil }.flatMap { $0 == events.phoneID ? nil : $0 }
        let value = DueItem(id: item?.id ?? UUID(), petID: pet.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), minutes: ScheduleEngine.minutes(from: at), intervalDays: interval, startDate: start, remindersEnabled: reminders || elsewhere != nil, reminderPhoneID: reminders ? events.phoneID : elsewhere, editedBy: events.caregiver)
        if events.saveDueItem(value) { dismiss() }
    }
}
