import XCTest
@testable import MacTimer

final class ScheduleConfigTests: XCTestCase {
    func test_fixedTimeConfig_encodesAndDecodesCorrectly() throws {
        let config = ScheduleConfig(
            type: .fixedTime,
            fixedTime: FixedTimeConfig(weekdays: [1, 3, 5], hour: 9, minute: 0),
            interval: nil
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ScheduleConfig.self, from: data)
        XCTAssertEqual(decoded.type, .fixedTime)
        XCTAssertEqual(decoded.fixedTime?.weekdays, [1, 3, 5])
        XCTAssertEqual(decoded.fixedTime?.hour, 9)
    }

    func test_intervalConfig_encodesAndDecodesCorrectly() throws {
        let config = ScheduleConfig(
            type: .interval,
            fixedTime: nil,
            interval: IntervalConfig(seconds: 3600, startImmediately: false)
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ScheduleConfig.self, from: data)
        XCTAssertEqual(decoded.type, .interval)
        XCTAssertEqual(decoded.interval?.seconds, 3600)
    }
}

final class TaskItemPersistenceTests: XCTestCase {
    var context: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        context = PersistenceController(inMemory: true).container.viewContext
    }

    func test_taskItem_savesAndFetchesPayload() throws {
        let item = TaskItem(context: context)
        item.id = UUID()
        item.name = "Test Task"
        item.isEnabled = true
        item.taskTypeRaw = TaskType.notification.rawValue
        item.createdAt = Date()
        item.payload = TaskPayload(notificationTitle: "Hello", notificationBody: "World")
        item.schedule = ScheduleConfig(
            type: .interval,
            fixedTime: nil,
            interval: IntervalConfig(seconds: 300, startImmediately: false)
        )
        try context.save()

        let fetched = try context.fetch(TaskItem.fetchRequest()).first
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.payload.notificationTitle, "Hello")
        XCTAssertEqual(fetched?.schedule.interval?.seconds, 300)
    }
}
