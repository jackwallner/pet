import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var events: EventStore
    @AppStorage("onboarded", store: AppGroup.defaults) private var onboarded = false
    @State private var trial = false
    @State private var name = ""
    @State private var caregiver = ""
    @State private var species = Species.dog
    @State private var joining = false
    private enum Field { case name, pet }
    @FocusState private var field: Field?
    var body: some View {
        NavigationStack {
            if trial {
                PaywallView(source: "onboarding", onboarding: true) { onboarded = true }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(AppConfig.fullName).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 16) {
                            TextField("Your name", text: $caregiver).textContentType(.givenName).focused($field, equals: .name).accessibilityIdentifier("onboarding.name")
                            Divider()
                            TextField("Pet name", text: $name).focused($field, equals: .pet).accessibilityIdentifier("onboarding.pet")
                            SpeciesPicker(selection: $species)
                        }.padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Free").font(.headline)
                            Text("One pet, solo logging, history, reminders and export.").fixedSize(horizontal: false, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Household").font(.headline)
                            Text("Sharing on iPhone with iCloud, extra pets and a sitter sheet.").fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Join a household") { joining = true }.accessibilityIdentifier("onboarding.join")
                    }.padding(20)
                }.onSubmit { field = nil }.scrollDismissesKeyboard(.immediately).background(Theme.background)
                .safeAreaInset(edge: .bottom) {
                    OnboardingFooter(title: "Continue", disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || caregiver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        events.caregiver = caregiver
                        let profile = PetProfile(name: name.trimmingCharacters(in: .whitespacesAndNewlines), species: species, editedBy: caregiver)
                        if events.savePet(profile) { trial = true }
                    }
                }
                .sheet(isPresented: $joining) { NavigationStack { JoinView() } }
            }
        }.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { field = nil }
            }
        }.task { if LaunchOptions.contains("-OnboardingTrial") { trial = true } }
    }
}
