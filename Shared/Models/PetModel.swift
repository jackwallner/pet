import CoreData
import Foundation

/// Household is the shared zone root. Settings use last writer wins; event payloads are immutable.
enum PetModel {
    nonisolated(unsafe) static let model: NSManagedObjectModel = {
        func attribute(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let item = NSAttributeDescription()
            item.name = name
            item.attributeType = type
            item.isOptional = true
            return item
        }
        let household = NSEntityDescription()
        household.name = "Household"
        household.managedObjectClassName = NSStringFromClass(Household.self)
        let record = NSEntityDescription()
        record.name = "StoredRecord"
        record.managedObjectClassName = NSStringFromClass(StoredRecord.self)
        let records = NSRelationshipDescription()
        records.name = "records"
        records.destinationEntity = record
        records.maxCount = 0
        records.isOptional = true
        records.deleteRule = .nullifyDeleteRule
        let parent = NSRelationshipDescription()
        parent.name = "household"
        parent.destinationEntity = household
        parent.maxCount = 1
        parent.isOptional = true
        parent.deleteRule = .nullifyDeleteRule
        records.inverseRelationship = parent
        parent.inverseRelationship = records
        household.properties = [attribute("id", .UUIDAttributeType), attribute("createdAt", .dateAttributeType),
            attribute("householdActiveUntil", .dateAttributeType), attribute("wasShared", .booleanAttributeType), records]
        record.properties = [attribute("id", .UUIDAttributeType), attribute("category", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType), attribute("updatedAt", .dateAttributeType), parent]
        let model = NSManagedObjectModel()
        model.entities = [household, record]
        return model
    }()
}

@objc(Household)
final class Household: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var createdAt: Date?
    @NSManaged var householdActiveUntil: Date?
    @NSManaged var wasShared: NSNumber?
    @NSManaged var records: Set<StoredRecord>?
}

@objc(StoredRecord)
final class StoredRecord: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var category: String?
    @NSManaged var payload: Data?
    @NSManaged var updatedAt: Date?
    @NSManaged var household: Household?

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        payload.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
