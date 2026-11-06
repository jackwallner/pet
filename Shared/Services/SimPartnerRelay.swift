#if DEBUG
import CoreData
import Foundation

/// In-process simulator peer. It saves through a second Core Data context and merges
/// persistent history like an imported change. It measures app behavior, not CloudKit transport.
@MainActor
final class SimPartnerRelay {
    let persistence: Persistence
    init(persistence: Persistence) { self.persistence = persistence }
    func deliver(_ incoming: [EventRecord], to householdID: UUID) throws {
        let context = persistence.newBackgroundContext()
        let persistence = persistence
        try context.performAndWait {
            let request = NSFetchRequest<Household>(entityName: "Household")
            request.predicate = NSPredicate(format: "id == %@", householdID as CVarArg)
            guard let root = try context.fetch(request).first else { return }
            context.transactionAuthor = "NSCloudKitMirroringDelegate.import.simRelay"
            let ids = Set((root.records ?? []).filter { $0.category == "event" }.compactMap(\.id))
            for event in incoming where !ids.contains(event.id) {
                let record = StoredRecord(context: context)
                record.id = event.id; record.category = "event"; record.updatedAt = event.recordedAt
                record.payload = try JSONEncoder().encode(event); record.household = root
                context.assign(record, to: persistence.privateStore)
            }
            try context.save()
        }
    }
}
#endif
