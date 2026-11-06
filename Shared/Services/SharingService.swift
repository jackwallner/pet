import CloudKit
import Combine
import CoreData
import Foundation

@MainActor
final class SharingService: ObservableObject {
    static let shared = SharingService(events: .shared)
    @Published var share: CKShare?
    @Published var error: String?
    @Published var busy = false
    private var shareHouseholdID: NSManagedObjectID?
    private var refreshGeneration = 0
    let events: EventStore
    var container: NSPersistentCloudKitContainer { events.persistence.container }
    var available: Bool { events.persistence.cloudKitEnabled }
    var inviteURL: URL? { share?.publicPermission == .readWrite ? share?.url : nil }
    init(events: EventStore) { self.events = events }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        guard available, let root = events.household else { share = nil; shareHouseholdID = nil; return }
        let id = root.objectID
        if shareHouseholdID != id { share = nil; shareHouseholdID = id }
        let container = container
        let result = await Task.detached { try? container.fetchShares(matching: [id])[id] }.value
        guard generation == refreshGeneration, events.household?.objectID == id else { return }
        share = result
    }

    func prepareInvite() async {
        guard events.isOwner, events.access.active(at: .now) else { return }
        guard available, let root = events.household else { error = "Sharing needs iCloud. Your log is saved on this iPhone."; return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let ck = CKContainer(identifier: AppGroup.cloudKitContainerID)
            guard try await ck.accountStatus() == .available else { error = "Sign in to iCloud in Settings to share."; return }
            let id = root.objectID
            let container = container
            let deadline = Date.now.addingTimeInterval(150)
            while Date.now < deadline {
                let record = await Task.detached { container.recordID(for: id) }.value
                if record != nil { break }
                try await Task.sleep(for: .milliseconds(500))
            }
            let exported = await Task.detached { container.recordID(for: id) }.value
            guard exported != nil else { error = "iCloud is still preparing the log. Try again in a moment."; return }
            guard events.household?.objectID == id, events.access.active(at: .now) else { return }
            let prepared = try await ShareInvite.prepare(for: [root], title: "\(AppConfig.displayName) household", container: container, database: ck.privateCloudDatabase)
            guard events.household?.objectID == id else { return }
            shareHouseholdID = id
            share = prepared
            _ = events.markShared()
        } catch { self.error = "The invitation could not be prepared. Check iCloud and try again." }
    }

    func join(_ text: String) async {
        guard let url = ShareInvite.url(in: text) else { error = "Paste a complete iCloud invitation link."; return }
        guard available else { error = "Sign in to iCloud in Settings to join a household."; return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let ck = CKContainer(identifier: AppGroup.cloudKitContainerID)
            let metadata = try await ck.shareMetadata(for: url)
            try await acceptMetadata(metadata)
        } catch { self.error = "The invitation could not be opened. Check iCloud or request a new link." }
    }
    func accept(_ metadata: CKShare.Metadata) {
        Task {
            do { try await acceptMetadata(metadata) }
            catch { self.error = "The invitation could not be accepted. Please try again." }
        }
    }
    private func acceptMetadata(_ metadata: CKShare.Metadata) async throws {
        guard available, metadata.participantRole != .owner else { error = "Open this invitation on the joining iPhone."; return }
        _ = try await container.acceptShareInvitations(from: [metadata], into: events.persistence.sharedStore)
        events.defaults.set(true, forKey: "pendingShare")
        events.awaitingShare = true
        share = metadata.share
        events.reload()
    }
    func persist(_ updated: CKShare, stopped: Bool) async {
        guard let root = events.household, let store = root.objectID.persistentStore else { return }
        do {
            if stopped, !events.isOwner {
                _ = try await container.purgeObjectsAndRecordsInZone(with: updated.recordID.zoneID, in: store)
            } else if !stopped {
                _ = try await container.persistUpdatedShare(updated, in: store)
            }
            share = stopped ? nil : updated
            events.reload()
        } catch { self.error = "Sharing changes could not be saved. Please try again." }
    }
}
