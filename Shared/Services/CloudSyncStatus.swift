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
    @Published private(set) var lastSynced: Date?
    @Published private(set) var connected = true
    @Published private(set) var problem: String?
    let cloudEnabled: Bool
    private let defaults: UserDefaults
    private let monitor = NWPathMonitor()
    init(defaults: UserDefaults, cloudEnabled: Bool) {
        self.defaults = defaults
        self.cloudEnabled = cloudEnabled
        lastSynced = defaults.object(forKey: "lastCloudSync") as? Date
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.connected = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "pet.reachability"))
    }
    func ended(isImport: Bool, isSetup: Bool, at date: Date, succeeded: Bool, error: Error?) {
        guard succeeded else { problem = "Sync needs attention"; return }
        guard !isSetup else { return }
        problem = nil
        // Downloads prove freshness. An upload alone cannot acknowledge a partner's entries.
        if isImport {
            lastSynced = date
            defaults.set(date, forKey: "lastCloudSync")
        }
    }
    func stale(at now: Date) -> Bool {
        !cloudEnabled || problem != nil || SyncFreshness.isStale(lastSuccess: lastSynced, connected: connected, now: now)
    }
}
