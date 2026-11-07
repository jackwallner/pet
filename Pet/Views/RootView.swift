import SwiftUI

struct RootView: View {
    @EnvironmentObject private var events: EventStore
    @EnvironmentObject private var sharing: SharingService
    @AppStorage("onboarded", store: AppGroup.defaults) private var onboarded = false
    @State private var tab = 0
    @State private var screenshotSheet: String?
    @State private var routed = false

    var body: some View {
        Group {
            if (!onboarded && !LaunchOptions.contains("-SeedDemo") && !LaunchOptions.contains("-EmptyLog") && !events.awaitingShare) {
                OnboardingView()
            } else if events.awaitingShare {
                NavigationStack {
                    VStack(spacing: 24) {
                        ProgressView()
                        Text("Opening household").font(.title2)
                        Button("Use my log while it opens") { events.awaitingShare = false; events.defaults.set(false, forKey: "pendingShare") }
                    }.padding().navigationTitle(AppConfig.displayName)
                }
            } else {
                TabView(selection: $tab) {
                    NavigationStack { NowView() }.tabItem { Label("Now", systemImage: "square.grid.2x2") }.tag(0)
                    NavigationStack { HistoryView() }.tabItem { Label("History", systemImage: "clock") }.tag(1)
                    NavigationStack { CareView() }.tabItem { Label("Care", systemImage: "calendar") }.tag(2)
                    NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
                }
            }
        }
        .frame(maxWidth: LaunchOptions.contains("-SmallPhone") ? 320 : .infinity)
        .frame(maxWidth: .infinity).background(Theme.background)
        .task {
            guard !routed else { return }
            routed = true
            let route = LaunchOptions.value("-ScreenshotRoute") ?? (LaunchOptions.value("-PaywallSnapshot") != nil ? "paywall" : "now")
            if LaunchOptions.contains("-SeedDemo") {
                while events.pet == nil { try? await Task.sleep(for: .milliseconds(100)) }
            }
            tab = ["history": 1, "care": 2, "settings": 3][route] ?? 0
            if !["now", "history", "care", "settings"].contains(route) { screenshotSheet = route }
        }
        .sheet(item: $screenshotSheet) { route in
            NavigationStack { RouteView(route: route) }
                .frame(maxWidth: LaunchOptions.contains("-SmallPhone") ? 320 : .infinity)
                .frame(maxWidth: .infinity)
        }
        .alert("Could not save", isPresented: Binding(get: { events.error != nil }, set: { if !$0 { events.error = nil } })) {
            Button("OK") { events.error = nil }
        } message: { Text(events.error ?? "") }
        .alert("Household", isPresented: Binding(get: { sharing.error != nil }, set: { if !$0 { sharing.error = nil } })) {
            Button("OK") { sharing.error = nil }
        } message: { Text(sharing.error ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .openNow)) { _ in tab = 0 }
    }
}

extension String: @retroactive Identifiable { public var id: String { self } }

struct RouteView: View {
    let route: String
    @EnvironmentObject private var events: EventStore
    var body: some View {
        Group {
            switch route {
            case "pets": PetsView()
            case "buttons": LogButtonsView()
            case "pet": PetEditor(profile: events.pet)
            case "medications": MedicationsView()
            case "medication": MedicationEditor(medication: events.petMedications.first)
            case "dose":
                if let med = events.petMedications.first { DoseView(medication: med, scheduledAt: nil) }
            case "due": DueEditor(item: events.petDueItems.first)
            case "household": HouseholdView()
            case "join": JoinView()
            case "invite": InviteView(previewURL: URL(string: "https://www.icloud.com/share/example-invitation"))
            case "sitter": SitterView()
            case "correction":
                if let event = events.visibleEvents.first { CorrectionView(event: event) }
            case "paywall": PaywallView(source: "invite", onboarding: false)
            default: NowView()
            }
        }
        .toolbar {
            if ["pets", "buttons", "medications", "household", "sitter"].contains(route) {
                ToolbarItem(placement: .cancellationAction) { DismissButton() }
            }
        }
    }
}
struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Close") { dismiss() } }
}
