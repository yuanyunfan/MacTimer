import CoreData
import Foundation

@objc(TaskItem)
public class TaskItem: NSManagedObject {}

extension TaskItem {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var isEnabled: Bool
    @NSManaged public var taskTypeRaw: String
    @NSManaged public var taskPayloadJSON: String
    @NSManaged public var scheduleJSON: String
    @NSManaged public var lastRunAt: Date?
    @NSManaged public var nextRunAt: Date?
    @NSManaged public var createdAt: Date

    var taskType: TaskType {
        get { TaskType(rawValue: taskTypeRaw) ?? .notification }
        set { taskTypeRaw = newValue.rawValue }
    }

    var payload: TaskPayload {
        get {
            let data = taskPayloadJSON.data(using: .utf8) ?? Data()
            return (try? JSONDecoder().decode(TaskPayload.self, from: data)) ?? TaskPayload()
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data()
            taskPayloadJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    var schedule: ScheduleConfig {
        get {
            let data = scheduleJSON.data(using: .utf8) ?? Data()
            return (try? JSONDecoder().decode(ScheduleConfig.self, from: data))
                ?? ScheduleConfig(type: .interval, fixedTime: nil,
                                  interval: IntervalConfig(seconds: 3600, startImmediately: false))
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data()
            scheduleJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<TaskItem> {
        return NSFetchRequest<TaskItem>(entityName: "TaskItem")
    }
}
