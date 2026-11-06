import AppKit
import CloudKit
import CoreData
import Foundation

/// A setup tool, never part of the iPhone app. It uses the real model and an
/// isolated temporary store, and removes every fixture it creates.
@main
@MainActor
struct SchemaMain {
    static let containerID = "iCloud.com.jackwallner.pet"

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { await run() }
        app.run()
    }

    private static func report(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func run() async {
        do {
            let environment = Bundle.main.object(forInfoDictionaryKey: "SchemaCloudKitEnvironment") as? String ?? "Unknown"
            report("PET_CLOUD_ENVIRONMENT: \(environment)")
            if CommandLine.arguments.contains("--initialize-development"), environment != "Development" {
                throw SchemaError.wrongEnvironment
            }
            let cloud = CKContainer(identifier: containerID)
            guard try await cloud.accountStatus() == .available else { throw SchemaError.noAccount }
            let container = try await makeContainer()
            if CommandLine.arguments.contains("--verify-share") {
                try await verifyShare(using: container, cloud: cloud)
                report("PET_SHARE_VERIFIED_AND_FIXTURE_REMOVED")
                exit(EXIT_SUCCESS)
            }
            let dryRun = !CommandLine.arguments.contains("--initialize-development")
            try container.initializeCloudKitSchema(options: dryRun ? [.dryRun, .printSchema] : [.printSchema])
            report(dryRun ? "PET_SCHEMA_VALIDATION_SUCCEEDED" : "PET_SCHEMA_INITIALIZATION_SUCCEEDED")
            exit(EXIT_SUCCESS)
        } catch {
            report("PET_SCHEMA_FAILED: \(error)")
            exit(EXIT_FAILURE)
        }
    }

    /// The owner half of sharing against the signed-in account: a real `CKShare`
    /// on the household zone, opened by the app's own `ShareInvite`. This is also
    /// what creates the `cloudkit.share` record type, which schema initialization
    /// never does and Production needs before any invitation can work.
    private static func verifyShare(using source: NSPersistentCloudKitContainer, cloud: CKContainer) async throws {
        let root = Household(context: source.viewContext)
        root.id = UUID()
        root.createdAt = .now
        root.householdActiveUntil = .now
        root.wasShared = false
        let record = StoredRecord(context: source.viewContext)
        record.id = UUID()
        record.category = "fixture"
        record.payload = Data("{}".utf8)
        record.updatedAt = .now
        record.household = root
        try source.viewContext.save()
        try await waitUntil(timeout: 1500) { source.recordID(for: root.objectID) != nil && source.recordID(for: record.objectID) != nil }
        report("PET_SHARE_STORE_READY")

        guard let store = root.objectID.persistentStore else { throw SchemaError.shareFailed("no store") }
        let saved = try await ShareInvite.prepare(for: [root], title: "Temporary share verification", container: source, database: cloud.privateCloudDatabase)
        let zoneID = saved.recordID.zoneID
        do {
            guard let url = saved.url else { throw SchemaError.shareFailed("no URL") }
            report("PET_SHARE_URL_HOST: \(url.host ?? "none")")
            let live = try await cloud.privateCloudDatabase.record(for: saved.recordID)
            guard (live as? CKShare)?.publicPermission == .readWrite else { throw SchemaError.shareFailed("not read/write") }
            report("PET_SHARE_CLOUD_RECORD_IS_READ_WRITE_LINK")
            let metadata = try await cloud.shareMetadata(for: url)
            guard metadata.share.recordID == saved.recordID else { throw SchemaError.shareFailed("link resolves elsewhere") }
            report("PET_SHARE_LINK_RESOLVES")
            guard ShareInvite.url(in: "Join my log \(url.absoluteString)") == url else { throw SchemaError.shareFailed("pasted text") }
            report("PET_SHARE_PASTED_MESSAGE_PARSES")
        } catch {
            _ = try? await source.purgeObjectsAndRecordsInZone(with: zoneID, in: store)
            throw error
        }
        _ = try await source.purgeObjectsAndRecordsInZone(with: zoneID, in: store)
        report("PET_SHARE_ZONE_PURGED")
    }

    private static func makeContainer() async throws -> NSPersistentCloudKitContainer {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PetSchema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = NSPersistentCloudKitContainer(name: "Pet", managedObjectModel: PetModel.model)
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("schema.sqlite"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    private static func waitUntil(timeout: TimeInterval = 120, _ condition: () async throws -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while Date.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .seconds(2))
        }
        throw SchemaError.timedOut
    }

    enum SchemaError: Error {
        case noAccount, timedOut, wrongEnvironment
        case shareFailed(String)
    }
}
