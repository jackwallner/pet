import CloudKit
import SwiftUI
import UserNotifications

@main
struct PetApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var events = EventStore.shared
    @StateObject private var store = StoreService.shared
    @StateObject private var sharing = SharingService.shared

    init() {
        if LaunchOptions.contains("-UITesting") || LaunchOptions.contains("-Onboarding") { AppGroup.defaults.set(false, forKey: "onboarded") }
        ConversionDiagnostics.recordAppOpen()
        RatingAsk.noteLaunch()
        Reminders.register()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(events).environmentObject(store).environmentObject(sharing)
                .tint(Theme.accent)
                .preferredColorScheme(LaunchOptions.value("-Appearance") == "dark" ? .dark : LaunchOptions.value("-Appearance") == "light" ? .light : nil)
                .modifier(DebugTextSize())
                .task {
                    store.didUpdateExpiry = { date in events.setHouseholdExpiry(date) }
                    #if DEBUG
                    if LaunchOptions.contains("-SeedDemo") { events.seedDemo(pro: LaunchOptions.contains("-DemoPro")) }
                    if LaunchOptions.contains("-SimPartner"), let pet = events.pet, let root = events.household?.id {
                        let incoming = EventRecord(petID: pet.id, kind: .meal, author: "Riley", authorID: "simulated-partner")
                        try? SimPartnerRelay(persistence: events.persistence).deliver([incoming], to: root)
                        events.context.refreshAllObjects()
                        events.reload()
                    }
                    #endif
                    await store.start()
                    await sharing.refresh()
                    #if DEBUG
                    await ReminderProbe.askPermissionIfAsked()
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    #if DEBUG
                    if phase == .background { Task { await ReminderProbe.scheduleIfAsked(events: events) } }
                    #endif
                    guard phase == .active else { return }
                    events.reload()
                    Task { await store.refresh(); await sharing.refresh() }
                }
                .onChange(of: events.household?.objectID) { _, _ in Task { await sharing.refresh() } }
                .onOpenURL { url in Task { await sharing.join(url.absoluteString) } }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in SharingService.shared.accept(metadata) }
    }
}
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata { Task { @MainActor in SharingService.shared.accept(metadata) } }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in SharingService.shared.accept(metadata) }
    }
}

final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    // Completion handler form, answered on the main thread. The async form's
    // compiler-made thunk calls UIKit's handler off the main thread, which aborts
    // the app on every notification tap.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let petID = (info["petID"] as? String).flatMap(UUID.init)
        let itemID = (info["itemID"] as? String).flatMap(UUID.init)
        let scheduledAt = (info["scheduledAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        let isMedication = response.notification.request.content.categoryIdentifier == "pet.medication"
        let isDueCompletion = response.actionIdentifier == "MARK_DONE" && response.notification.request.content.categoryIdentifier == "pet.due"
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            defer { done() }
            let store = EventStore.shared
            if let petID { store.select(petID) }
            store.notificationMedicationID = isMedication ? itemID : nil
            if isDueCompletion, let itemID, let scheduledAt,
               let item = store.dueItems.first(where: { $0.id == itemID && !$0.archived }),
               !EventLedger.visible(store.events).contains(where: { $0.dueItemID == itemID && $0.scheduledAt == scheduledAt }) {
                _ = store.log(.due, note: item.name, dueItemID: itemID, scheduledAt: scheduledAt)
            }
            NotificationCenter.default.post(name: .openNow, object: nil)
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
extension Notification.Name { static let openNow = Notification.Name("pet.openNow") }

struct DebugTextSize: ViewModifier {
    func body(content: Content) -> some View {
        if LaunchOptions.contains("-LargeText") { content.dynamicTypeSize(.accessibility3) }
        else { content }
    }
}
