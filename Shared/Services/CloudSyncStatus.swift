import Combine
import Foundation
import Network

struct SyncFreshness {
    static func isStale(lastSuccess: Date?, connected: Bool, now: Date) -> Bool {
        guard connected, let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) > 5 * 60
    }
}

@MainActor
final class CloudSyncState: ObservableObject {
    /// Last successful download per persistent store. A phone can hold its own log and a joined one,
    /// and only the shown household's store says whether that household is current.
    @Published private(set) var lastSyncedByStore: [String: Date] = [:]
    @Published private(set) var connected = true
    /// Failed operations, keyed by store and kind, so a successful upload never clears a failed download.
    @Published private(set) var failures: Set<String> = []
    /// False until this process mirrors to iCloud. Turns true without a relaunch when someone signs in to iCloud.
    @Published private(set) var cloudEnabled: Bool
    private var demoSynced = false
    private let defaults: UserDefaults
    private let monitor = NWPathMonitor()
    private static let key = "lastCloudSyncByStore"
    /// Persisted so a relaunch never turns an unresolved failure back into "Updated".
    private static let failuresKey = "cloudSyncFailures"
    init(defaults: UserDefaults, cloudEnabled: Bool) {
        self.defaults = defaults
        self.cloudEnabled = cloudEnabled
        lastSyncedByStore = defaults.dictionary(forKey: Self.key)?.compactMapValues { $0 as? Date } ?? [:]
        failures = Set(defaults.stringArray(forKey: Self.failuresKey) ?? [])
        // Builds before per-store tracking kept one date for every log. It cannot say which log it vouched for,
        // so it is dropped rather than credited to the wrong one.
        defaults.removeObject(forKey: "lastCloudSync")
        #if DEBUG
        // Store screenshots run without an iCloud account; show a recent download instead of the stale banner.
        if LaunchOptions.contains("-DemoSynced") { demoSynced = true }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.connected = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "pet.reachability"))
    }
    /// Store files open local-only while the rest of the app mirrors (one would not start with iCloud).
    @Published private(set) var unmirrored: Set<String> = []
    func setMirroring(enabled: Bool, unmirrored stores: Set<String>) {
        if cloudEnabled != enabled { cloudEnabled = enabled }
        if unmirrored != stores { unmirrored = stores }
    }
    /// Whether this log can receive a partner's entries at all. A saved download date proves nothing otherwise.
    func mirrors(store: String?) -> Bool { cloudEnabled && !(store.map(unmirrored.contains) ?? false) }
    func ended(store: String, isImport: Bool, isSetup: Bool, at date: Date, succeeded: Bool, error: Error?) {
        let operation = "\(store).\(isSetup ? "setup" : isImport ? "import" : "export")"
        guard succeeded else { failures.insert(operation); defaults.set(Array(failures), forKey: Self.failuresKey); return }
        if failures.remove(operation) != nil { defaults.set(Array(failures), forKey: Self.failuresKey) }
        // Downloads prove freshness. An upload alone cannot acknowledge a partner's entries.
        if isImport && !isSetup {
            lastSyncedByStore[store] = date
            defaults.set(lastSyncedByStore, forKey: Self.key)
        }
    }
    /// When the app last came to the foreground. CloudKit downloads after activation, so for a short
    /// while a quiet log is being checked rather than known to be behind.
    @Published private(set) var activatedAt = Date.now
    func activated(at date: Date = .now) { activatedAt = date }
    func checking(store: String?, at now: Date) -> Bool {
        mirrors(store: store) && connected && !problem(store: store) && lastSynced(store: store) != nil && now.timeIntervalSince(activatedAt) < 30
    }
    func lastSynced(store: String?) -> Date? {
        if demoSynced { return .now.addingTimeInterval(-60) }
        return store.flatMap { lastSyncedByStore[$0] }
    }
    func problem(store: String?) -> Bool {
        guard let store else { return false }
        return failures.contains { $0.hasPrefix(store + ".") }
    }
    func stale(store: String?, at now: Date) -> Bool {
        if demoSynced { return false }
        return !mirrors(store: store) || problem(store: store) || SyncFreshness.isStale(lastSuccess: lastSynced(store: store), connected: connected, now: now)
    }
}
