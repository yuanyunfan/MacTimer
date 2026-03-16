import CoreData
import Foundation

enum ExecutionResult: String, Codable {
    case success
    case failure
    case timeout
}

@objc(ExecutionLogItem)
public class ExecutionLogItem: NSManagedObject {}

extension ExecutionLogItem {
    @NSManaged public var id: UUID
    @NSManaged public var taskID: UUID
    @NSManaged public var executedAt: Date
    @NSManaged public var resultRaw: String
    @NSManaged public var errorMessage: String?
    @NSManaged public var duration: Double

    var result: ExecutionResult {
        get { ExecutionResult(rawValue: resultRaw) ?? .failure }
        set { resultRaw = newValue.rawValue }
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ExecutionLogItem> {
        return NSFetchRequest<ExecutionLogItem>(entityName: "ExecutionLogItem")
    }
}
