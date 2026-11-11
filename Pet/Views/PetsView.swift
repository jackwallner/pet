import PhotosUI
import SwiftUI

struct PetAvatar: View {
    let image: UIImage?
    let symbol: String
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.14))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: symbol).font(.system(size: size * 0.42)).foregroundStyle(Theme.accent) }
        }
        .frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct PetsView: View {
    @EnvironmentObject private var events: EventStore
    @State private var add = false
    @State private var paywall = false
    @State private var editing: PetProfile?
    var body: some View {
        List {
            ForEach(events.pets) { pet in
                Button { events.select(pet.id); editing = pet } label: {
                    HStack(spacing: 12) {
                        PetAvatar(image: events.petPhotos[pet.id], symbol: pet.species.symbol, size: 44)
                        Text(pet.name).foregroundStyle(.primary)
                        Spacer()
                        if events.pet?.id == pet.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }.padding(.vertical, 4)
                }
                .accessibilityLabel(pet.name)
                .accessibilityAddTraits(events.pet?.id == pet.id ? .isSelected : [])
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var name = ""
    @State private var species = Species.dog
    @State private var birthday = Date.now
    @State private var knownBirthday = false
    @State private var vet = ""
    @State private var vetPhone = ""
    @State private var microchip = ""
    @State private var insurance = ""
    @State private var notes = ""
    @State private var sitters: [SitterContact] = []
    @State private var sitter: SitterContact?
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var jpeg: Data?
    @State private var photoChanged = false
    @State private var loadingPhoto = false
    @State private var photoError: String?
    @State private var loaded = false
    private var readOnly: Bool { profile != nil && !events.canWrite }
    private var phoneURL: URL? { SitterContact.callURL(vetPhone) }
    var body: some View {
        Form {
            Section { photoRow }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            Section {
                TextField("Pet name", text: $name).accessibilityIdentifier("pet.name")
                SpeciesPicker(selection: $species)
                Toggle("Birthday", isOn: $knownBirthday)
                if knownBirthday { DatePicker("Born", selection: $birthday, in: ...Date.now, displayedComponents: .date) }
            }
            Section("Details") {
                detail("Vet", text: $vet, id: "pet.vet")
                HStack {
                    detail("Vet phone", text: $vetPhone, id: "pet.vetPhone").keyboardType(.phonePad)
                    if let phoneURL {
                        Link(destination: phoneURL) { Image(systemName: "phone").frame(minWidth: 44, minHeight: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Call vet").accessibilityIdentifier("pet.call")
                    }
                }
                detail("Microchip", text: $microchip, id: "pet.microchip").autocorrectionDisabled()
                detail("Insurance", text: $insurance, id: "pet.insurance")
                detail("Notes", text: $notes, id: "pet.notes", axis: .vertical)
            }
            sitterSection
            if let profile { Section { EditedLine(author: profile.editedBy, date: profile.editedAt) } }
        }.biscuitList().scrollDismissesKeyboard(.interactively)
        .navigationTitle(profile == nil ? "Add a pet" : "Edit pet").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DismissButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loadingPhoto || readOnly).accessibilityIdentifier("pet.save") }
        }
        .sheet(item: $sitter) { contact in
            NavigationStack {
                SitterContactEditor(contact: contact, isNew: !sitters.contains { $0.id == contact.id }) { updated in
                    if let index = sitters.firstIndex(where: { $0.id == contact.id }) {
                        if let updated { sitters[index] = updated } else { sitters.remove(at: index) }
                    } else if let updated { sitters.append(updated) }
                    commitSitters()
                }
            }
        }
        .onChange(of: photoItem) { _, item in if let item { Task { await load(item) } } }
        .onAppear(perform: fill)
    }
    private var sitterSection: some View {
        Section("Sitters") {
            ForEach(sitters) { contact in
                HStack {
                    Button { sitter = contact } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).foregroundStyle(.primary)
                            if let detail = [contact.phone, contact.note].compactMap({ $0 }).joined(separator: ", ").nilIfEmpty {
                                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(readOnly).accessibilityIdentifier("pet.sitter")
                    if let url = contact.callURL {
                        Link(destination: url) { Image(systemName: "phone").frame(minWidth: 44, minHeight: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Call \(contact.name)").accessibilityIdentifier("pet.sitter.call")
                    }
                }
            }
            .onDelete(perform: readOnly ? nil : { sitters.remove(atOffsets: $0); commitSitters() })
            if !readOnly {
                Button { sitter = SitterContact(name: "") } label: { Label("Add sitter", systemImage: "plus") }
                    .frame(minHeight: 44).accessibilityIdentifier("pet.sitter.add")
            }
        }
    }
    /// A saved pet keeps sitter changes at once, so closing without Save never loses one.
    /// A new pet has nothing to update yet, so its list waits for Save.
    private func commitSitters() {
        guard let profile, var stored = events.pets.first(where: { $0.id == profile.id }) else { return }
        stored.sitters = sitters.isEmpty ? nil : sitters
        events.savePet(stored)
    }
    private var photoRow: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))) {
            PetAvatar(image: image, symbol: species.symbol, size: 96)
                .overlay { if loadingPhoto { ProgressView() } }
            VStack(alignment: .leading, spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text(image == nil ? "Add photo" : "Change photo").font(.body.weight(.semibold)).frame(minHeight: 44)
                }.disabled(readOnly).accessibilityIdentifier("pet.photo")
                if image != nil {
                    Button("Remove photo", role: .destructive) { image = nil; jpeg = nil; photoChanged = true; photoError = nil }
                        .buttonStyle(.borderless).disabled(readOnly).frame(minHeight: 44).accessibilityIdentifier("pet.photo.remove")
                }
                if let photoError { Text(photoError).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    /// The heading stays visible once the field is filled, which a placeholder would not.
    private func detail(_ title: String, text: Binding<String>, id: String, axis: Axis = .horizontal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(title, text: text, prompt: Text(""), axis: axis).accessibilityIdentifier(id)
        }.padding(.vertical, 2)
    }
    private func load(_ item: PhotosPickerItem) async {
        loadingPhoto = true
        defer { loadingPhoto = false; photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let encoded = await Task.detached(operation: { PetPhotoEncoder.jpeg(from: data) }).value,
              let decoded = UIImage(data: encoded) else { photoError = "This photo could not be read."; return }
        image = decoded
        jpeg = encoded
        photoChanged = true
        photoError = nil
    }
    private func fill() {
        guard !loaded else { return }
        loaded = true
        guard let profile else { return }
        name = profile.name
        species = profile.species
        birthday = profile.birthday ?? .now
        knownBirthday = profile.birthday != nil
        vet = profile.vet ?? ""
        vetPhone = profile.vetPhone ?? ""
        microchip = profile.microchip ?? ""
        insurance = profile.insurance ?? ""
        notes = profile.notes ?? ""
        sitters = profile.sitters ?? []
        image = events.petPhotos[profile.id]
    }
    private func save() {
        var pet = profile ?? PetProfile(name: name, editedBy: events.caregiver)
        pet.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pet.species = species
        pet.birthday = knownBirthday ? birthday : nil
        pet.vet = cleaned(vet)
        pet.vetPhone = cleaned(vetPhone)
        pet.microchip = cleaned(microchip)
        pet.insurance = cleaned(insurance)
        pet.notes = cleaned(notes)
        pet.sitters = sitters.isEmpty ? nil : sitters
        guard events.savePet(pet) else { return }
        if photoChanged, !events.savePetPhoto(jpeg, petID: pet.id) { photoError = "This photo could not be saved."; return }
        dismiss()
    }
    private func cleaned(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct SitterContactEditor: View {
    let contact: SitterContact
    let isNew: Bool
    /// Nil removes the contact.
    let done: (SitterContact?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    @State private var note = ""
    @State private var loaded = false
    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name).textContentType(.name).accessibilityIdentifier("sitter.name")
                TextField("Phone", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber).accessibilityIdentifier("sitter.phone")
                TextField("Note", text: $note, axis: .vertical).accessibilityIdentifier("sitter.note")
            }
            if !isNew {
                Section { Button("Remove sitter", role: .destructive) { done(nil); dismiss() }.accessibilityIdentifier("sitter.remove") }
            }
        }.biscuitList()
        .navigationTitle(isNew ? "Add sitter" : "Edit sitter").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { DismissButton() }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("sitter.save") }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = contact.name; phone = contact.phone ?? ""; note = contact.note ?? ""
        }
    }
    private func save() {
        var value = contact
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        done(value)
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
