import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let context = result.container.viewContext
        // Insert sample TaskItem for previews
        let task = TaskItem(context: context)
        task.id = UUID()
        task.name = "早晨提醒"
        task.isEnabled = true
        task.taskTypeRaw = TaskType.notification.rawValue
        task.payload = TaskPayload(notificationTitle: "早晨提醒", notificationBody: "该起床了！")
        task.schedule = ScheduleConfig(
            type: .fixedTime,
            fixedTime: FixedTimeConfig(weekdays: [1, 2, 3, 4, 5], hour: 9, minute: 0),
            interval: nil
        )
        task.createdAt = Date()
        try? context.save()
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MacTimer")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error { fatalError("CoreData load error: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
