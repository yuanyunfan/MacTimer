import XCTest
import CoreData
@testable import MacTimer

@MainActor
final class SchedulerServiceTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    func test_enabledTasks_areScheduledOnStart() {
        let task = makeTask(isEnabled: true, intervalSeconds: 3600)
        try! context.save()

        let service = SchedulerService(context: context)
        service.start()

        XCTAssertNotNil(task.nextRunAt)
        XCTAssertFalse(service.activeTimers.isEmpty)
    }

    func test_disabledTasks_areNotScheduled() {
        let _ = makeTask(isEnabled: false, intervalSeconds: 3600)
        try! context.save()

        let service = SchedulerService(context: context)
        service.start()

        XCTAssertTrue(service.activeTimers.isEmpty)
    }

    func test_rescheduleTask_updatesNextRunAt() {
        let task = makeTask(isEnabled: true, intervalSeconds: 3600)
        try! context.save()

        let service = SchedulerService(context: context)
        service.reschedule(task: task)

        XCTAssertNotNil(task.nextRunAt)
    }

    func test_lastFailedTaskName_nilOnInit() {
        let service = SchedulerService(context: context)
        XCTAssertNil(service.lastFailedTaskName)
    }

    func test_lastFailedTaskName_isSetAfterFailure() async {
        let service = SchedulerService(context: context)
        service.simulateFailure(taskName: "测试任务")
        XCTAssertEqual(service.lastFailedTaskName, "测试任务")
    }

    // MARK: Helpers
    private func makeTask(isEnabled: Bool, intervalSeconds: Int) -> TaskItem {
        let item = TaskItem(context: context)
        item.id = UUID()
        item.name = "Test Task"
        item.isEnabled = isEnabled
        item.taskTypeRaw = TaskType.notification.rawValue
        item.createdAt = Date()
        item.payload = TaskPayload(notificationTitle: "T", notificationBody: "B")
        item.schedule = ScheduleConfig(
            type: .interval,
            fixedTime: nil,
            interval: IntervalConfig(seconds: intervalSeconds, startImmediately: false)
        )
        return item
    }
}
