import SwiftUI

struct LogButtonsView: View {
    @EnvironmentObject private var events: EventStore
    private var settings: [LogButtonSetting] { events.pet?.logButtonSettings ?? [] }
    var body: some View {
        List {
            if events.pets.count > 1 {
                Section {
                    Picker("Pet", selection: Binding(get: { events.pet?.id }, set: { if let id = $0 { events.select(id) } })) {
                        ForEach(events.pets) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            Section {
                ForEach(settings) { setting in
                    Toggle(isOn: shown(setting)) { Label(setting.kind.rawValue, systemImage: setting.kind.symbol) }
                        // Now always keeps one button, so it never turns into an empty screen.
                        .disabled(!events.canWrite || (setting.shown && settings.filter(\.shown).count == 1))
                        .accessibilityIdentifier("logButton.\(setting.kind.rawValue)")
                        .moveDisabled(!events.canWrite)
                }
                .onMove { from, to in
                    var moved = settings
                    moved.move(fromOffsets: from, toOffset: to)
                    save(moved)
                }
            }
        }
        .biscuitList().navigationTitle("Log buttons").navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
    }
    private func shown(_ setting: LogButtonSetting) -> Binding<Bool> {
        Binding(get: { setting.shown }, set: { value in
            var changed = settings
            guard let index = changed.firstIndex(where: { $0.kind == setting.kind }) else { return }
            changed[index].shown = value
            save(changed)
        })
    }
    private func save(_ settings: [LogButtonSetting]) {
        guard var pet = events.pet else { return }
        pet.logButtons = settings
        events.savePet(pet)
    }
}
