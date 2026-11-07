import SwiftUI

struct PetsView: View {
    @EnvironmentObject private var events: EventStore
    @State private var add = false
    @State private var paywall = false
    @State private var editing: PetProfile?
    var body: some View {
        List {
            ForEach(events.pets) { pet in
                Button { events.select(pet.id); editing = pet } label: {
                    HStack {
                        Label(pet.name, systemImage: pet.species.symbol).foregroundStyle(.primary)
                        Spacer()
                        if events.pet?.id == pet.id { Image(systemName: "checkmark") }
                    }.padding(.vertical, 8)
                }
            }
        }.biscuitList().navigationTitle("Pets").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button {
            if events.access.canAddPet(existingCount: events.pets.count, at: .now) { add = true }
            else if events.isOwner { paywall = true }
        } label: { Image(systemName: "plus") }.accessibilityLabel("Add a pet").disabled(!events.isOwner && !events.access.active(at: .now)) } }
        .sheet(isPresented: $add) { NavigationStack { PetEditor(profile: nil) } }
        .sheet(item: $editing) { pet in NavigationStack { PetEditor(profile: pet) } }
        .sheet(isPresented: $paywall) { NavigationStack { PaywallView(source: "extra_pet", onboarding: false) } }
    }
}

struct SpeciesPicker: View {
    @Binding var selection: Species
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth = 28
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
            ForEach(Species.allCases) { species in
                let selected = species == selection
                Button { selection = species } label: {
                    HStack(spacing: 10) {
                        Image(systemName: species.symbol).frame(width: iconWidth).accessibilityHidden(true)
                        Text(species.rawValue)
                    }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Theme.buttonInk : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(selected ? Theme.accent : Theme.background, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("species.\(species.rawValue)")
            }
        }
    }
}

struct PetEditor: View {
    let profile: PetProfile?
    @EnvironmentObject private var events: EventStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var species = Species.dog
    @State private var birthday = Date.now
    @State private var knownBirthday = false
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                TextField("Pet name", text: $name).accessibilityIdentifier("pet.name")
                SpeciesPicker(selection: $species)
                Toggle("Birthday", isOn: $knownBirthday)
                if knownBirthday { DatePicker("Born", selection: $birthday, in: ...Date.now, displayedComponents: .date) }
            }
            if let profile { Section { EditedLine(author: profile.editedBy, date: profile.editedAt) } }
        }.biscuitList().navigationTitle(profile == nil ? "Add a pet" : "Edit pet").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DismissButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Save") {
                var pet = profile ?? PetProfile(name: name, editedBy: events.caregiver)
                pet.name = name.trimmingCharacters(in: .whitespacesAndNewlines); pet.species = species; pet.birthday = knownBirthday ? birthday : nil
                if events.savePet(pet) { dismiss() }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("pet.save") }
        }
        .onAppear { guard !loaded else { return }; loaded = true; if let profile { name = profile.name; species = profile.species; birthday = profile.birthday ?? .now; knownBirthday = profile.birthday != nil } }
    }
}
