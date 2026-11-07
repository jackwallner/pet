import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var store: StoreService
    @State private var name = ""
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var suggesting = false
    @State private var suggestions: [FeedbackItem] = []
    var body: some View {
        List {
            if events.households.count > 1 {
                Section("Logs") {
                    ForEach(events.households, id: \.objectID) { root in
                        Button { events.selectHousehold(root) } label: {
                            HStack {
                                Text(root.objectID.persistentStore == events.persistence.sharedStore ? "Joined household" : "My household")
                                Spacer()
                                if root == events.household { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            Section {
                TextField("Your name", text: $name)
                    .onSubmit { if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { events.caregiver = name } }
                    .onChange(of: name) { _, value in if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { events.caregiver = value } }
                NavigationLink { PetsView() } label: { Label("Pets", systemImage: "pawprint") }.accessibilityIdentifier("settings.pets")
                NavigationLink { HouseholdView() } label: { Label("Household", systemImage: "person.2") }.accessibilityIdentifier("settings.household")
            }
            Section {
                NavigationLink { SitterView() } label: { Label("Sitter sheet", systemImage: "doc") }.accessibilityIdentifier("settings.sitter")
                Button { do { exportURL = try LogExport.file(pets: events.pets, medications: events.medications, events: events.events) } catch { exportError = "The export could not be created. Please try again." } } label: { Label("Export log", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("settings.export")
            }
            if events.isSharedLog { Section { SyncLine(sync: events.sync) } }
            if Distribution.isTestFlight {
                Section("Suggestions") {
                    Button("Suggest a change") { suggesting = true }.accessibilityIdentifier("settings.suggest")
                    ForEach(suggestions) { SuggestionRow(item: $0) }
                }
            }
            Section {
                Link("Rate \(AppConfig.displayName)", destination: AppConfig.reviewURL)
                    .simultaneousGesture(TapGesture().onEnded { RatingAsk.markWroteReview() })
                if !Distribution.isTestFlight {
                    Link("Send Feedback", destination: URL(string: "mailto:jackwallner@gmail.com?subject=\(AppConfig.displayName)%20feedback")!)
                }
                Link("Support", destination: AppConfig.supportURL)
                Link("Privacy", destination: AppConfig.privacyURL)
                Link("Terms", destination: AppConfig.termsURL)
            }
            Section { Text(AppConfig.disclaimer).font(.footnote).foregroundStyle(.secondary); LabeledContent("Version", value: AppConfig.versionLabel()) }
        }.biscuitList().navigationTitle("Settings").onAppear { name = events.caregiver }
        .task {
            guard Distribution.isTestFlight,
                  let items = try? await FeedbackService.current.mine(installID: FeedbackService.installID), !items.isEmpty else { return }
            suggestions = items
        }
        .sheet(isPresented: $suggesting) { FeedbackView { suggestions.insert($0, at: 0) } }
        .sheet(item: $exportURL) { url in ActivitySheet(items: [url]) }
        .alert("Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) { Button("OK") { exportError = nil } } message: { Text(exportError ?? "") }
    }
}
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    var completed: ((Bool) -> Void)? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, success, _, _ in completed?(success) }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
