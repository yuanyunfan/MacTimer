import XCTest
@testable import MacTimer

final class SystemTaskDiscoveryTests: XCTestCase {

    // MARK: - Cron Weekday Parsing

    func testCronWeekdayWildcard() {
        // * → 每天 [1,2,3,4,5,6,7]
        let service = SystemTaskDiscoveryService.shared
        let result = service.testParseCronWeekdays("*")
        XCTAssertEqual(result, [1, 2, 3, 4, 5, 6, 7])
    }

    func testCronWeekdayRange() {
        // 1-5 → 周一到周五
        let service = SystemTaskDiscoveryService.shared
        let result = service.testParseCronWeekdays("1-5")
        XCTAssertEqual(result, [1, 2, 3, 4, 5])
    }

    func testCronWeekdaySunday() {
        // 0 和 7 都是 Sunday → ISO 7
        let service = SystemTaskDiscoveryService.shared
        XCTAssertEqual(service.testParseCronWeekdays("0"), [7])
        XCTAssertEqual(service.testParseCronWeekdays("7"), [7])
    }

    func testCronWeekdayList() {
        // 1,3,5 → 周一、三、五
        let service = SystemTaskDiscoveryService.shared
        let result = service.testParseCronWeekdays("1,3,5")
        XCTAssertEqual(result, [1, 3, 5])
    }

    // MARK: - Cron Schedule Parsing

    func testCronIntervalMinutes() {
        // */15 * * * * → 每 15 分钟
        let service = SystemTaskDiscoveryService.shared
        let (config, desc) = service.testParseCronSchedule(
            minute: "*/15", hour: "*", day: "*", month: "*", weekday: "*"
        )
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.type, .interval)
        XCTAssertEqual(config?.interval?.seconds, 900)
        XCTAssertEqual(desc, "每 15 分钟")
    }

    func testCronIntervalHours() {
        // 0 */2 * * * → 每 2 小时
        let service = SystemTaskDiscoveryService.shared
        let (config, desc) = service.testParseCronSchedule(
            minute: "0", hour: "*/2", day: "*", month: "*", weekday: "*"
        )
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.type, .interval)
        XCTAssertEqual(config?.interval?.seconds, 7200)
        XCTAssertEqual(desc, "每 2 小时")
    }

    func testCronFixedTimeWeekdays() {
        // 30 9 * * 1-5 → 周一到五 09:30
        let service = SystemTaskDiscoveryService.shared
        let (config, _) = service.testParseCronSchedule(
            minute: "30", hour: "9", day: "*", month: "*", weekday: "1-5"
        )
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.type, .fixedTime)
        XCTAssertEqual(config?.fixedTime?.hour, 9)
        XCTAssertEqual(config?.fixedTime?.minute, 30)
        XCTAssertEqual(config?.fixedTime?.weekdays, [1, 2, 3, 4, 5])
    }

    func testCronFixedTimeEveryDay() {
        // 0 8 * * * → 每天 08:00
        let service = SystemTaskDiscoveryService.shared
        let (config, _) = service.testParseCronSchedule(
            minute: "0", hour: "8", day: "*", month: "*", weekday: "*"
        )
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.type, .fixedTime)
        XCTAssertEqual(config?.fixedTime?.weekdays, [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(config?.fixedTime?.hour, 8)
        XCTAssertEqual(config?.fixedTime?.minute, 0)
    }

    func testCronMonthDayNotSupported() {
        // 0 9 15 * * → 每月15日，FixedTimeConfig 不支持
        let service = SystemTaskDiscoveryService.shared
        let (config, desc) = service.testParseCronSchedule(
            minute: "0", hour: "9", day: "15", month: "*", weekday: "*"
        )
        XCTAssertNil(config)
        XCTAssertEqual(desc, "0 9 15 * *")  // fallback 原始描述
    }

    func testCronComplexExpressionFallback() {
        // 0,30 * * * * → 无法简单映射
        let service = SystemTaskDiscoveryService.shared
        let (config, desc) = service.testParseCronSchedule(
            minute: "0,30", hour: "*", day: "*", month: "*", weekday: "*"
        )
        XCTAssertNil(config)
        XCTAssertEqual(desc, "0,30 * * * *")
    }

    // MARK: - Launchd Schedule Parsing

    func testLaunchdStartInterval() {
        let plist: [String: Any] = [
            "Label": "com.test.job",
            "ProgramArguments": ["/usr/bin/true"],
            "StartInterval": 3600,
        ]
        let service = SystemTaskDiscoveryService.shared
        let (config, desc) = service.testParseLaunchdSchedule(plist)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.type, .interval)
        XCTAssertEqual(config?.interval?.seconds, 3600)
        XCTAssertEqual(desc, "每 1 小时")
    }

    func testLaunchdCalendarInterval() {
        let plist: [String: Any] = [
            "Label": "com.test.job",
            "ProgramArguments": ["/usr/bin/true"],
            "StartCalendarInterval": [
                "Hour": 9,
                "Minute": 30,
                "Weekday": 1,  // Monday in launchd
            ] as [String : Any],
        ]
        let service = SystemTaskDiscoveryService.shared
        let (config, _) = service.testParseLaunchdSchedule(plist)
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.type, .fixedTime)
        XCTAssertEqual(config?.fixedTime?.hour, 9)
        XCTAssertEqual(config?.fixedTime?.minute, 30)
        XCTAssertEqual(config?.fixedTime?.weekdays, [1])  // ISO Monday = 1
    }

    func testLaunchdCalendarIntervalSunday() {
        let plist: [String: Any] = [
            "Label": "com.test.sunday",
            "StartCalendarInterval": [
                "Hour": 10,
                "Minute": 0,
                "Weekday": 0,  // Sunday in launchd
            ] as [String : Any],
        ]
        let service = SystemTaskDiscoveryService.shared
        let (config, _) = service.testParseLaunchdSchedule(plist)
        XCTAssertEqual(config?.fixedTime?.weekdays, [7])  // ISO Sunday = 7
    }

    func testLaunchdCalendarIntervalNoWeekday() {
        // 没有 Weekday → 每天
        let plist: [String: Any] = [
            "Label": "com.test.daily",
            "StartCalendarInterval": [
                "Hour": 8,
                "Minute": 0,
            ] as [String : Any],
        ]
        let service = SystemTaskDiscoveryService.shared
        let (config, _) = service.testParseLaunchdSchedule(plist)
        XCTAssertEqual(config?.fixedTime?.weekdays, [1, 2, 3, 4, 5, 6, 7])
    }

    func testLaunchdNoSchedule() {
        // 纯事件驱动，无调度
        let plist: [String: Any] = [
            "Label": "com.test.eventonly",
            "ProgramArguments": ["/usr/bin/true"],
            "WatchPaths": ["/tmp/trigger"],
        ]
        let service = SystemTaskDiscoveryService.shared
        let (config, desc) = service.testParseLaunchdSchedule(plist)
        XCTAssertNil(config)
        XCTAssertNil(desc)
    }

    // MARK: - Crontab Line Parsing

    func testCrontabLineComment() {
        let service = SystemTaskDiscoveryService.shared
        let result = service.testParseCrontabLine("# this is a comment", lineNumber: 1)
        XCTAssertNil(result)
    }

    func testCrontabLineEmpty() {
        let service = SystemTaskDiscoveryService.shared
        XCTAssertNil(service.testParseCrontabLine("", lineNumber: 1))
        XCTAssertNil(service.testParseCrontabLine("   ", lineNumber: 1))
    }

    func testCrontabLineEnvVar() {
        let service = SystemTaskDiscoveryService.shared
        XCTAssertNil(service.testParseCrontabLine("SHELL=/bin/bash", lineNumber: 1))
        XCTAssertNil(service.testParseCrontabLine("PATH=/usr/bin:/usr/local/bin", lineNumber: 1))
    }

    func testCrontabLineValid() {
        let service = SystemTaskDiscoveryService.shared
        let result = service.testParseCrontabLine("0 9 * * 1-5 /usr/local/bin/backup.sh", lineNumber: 1)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.source, .crontab)
        XCTAssertEqual(result?.command, "/usr/local/bin/backup.sh")
        XCTAssertEqual(result?.name, "backup.sh")
        XCTAssertTrue(result?.isLoaded ?? false)
    }

    func testCrontabLineTooFewFields() {
        let service = SystemTaskDiscoveryService.shared
        XCTAssertNil(service.testParseCrontabLine("0 9 * * *", lineNumber: 1))
    }

    // MARK: - Format Helpers

    func testFormatInterval() {
        let service = SystemTaskDiscoveryService.shared
        XCTAssertEqual(service.testFormatInterval(60), "每 1 分钟")
        XCTAssertEqual(service.testFormatInterval(3600), "每 1 小时")
        XCTAssertEqual(service.testFormatInterval(5400), "每 1 小时 30 分")
        XCTAssertEqual(service.testFormatInterval(30), "每 30 秒")
    }

    // MARK: - SystemTask Model

    func testSystemTaskEquality() {
        let task1 = SystemTask(
            id: "test:1", name: "Test", source: .launchd,
            command: "/usr/bin/true", schedule: nil,
            scheduleDescription: "每天", rawContent: "", isLoaded: true
        )
        let task2 = SystemTask(
            id: "test:1", name: "Different Name", source: .crontab,
            command: "/usr/bin/false", schedule: nil,
            scheduleDescription: "不同", rawContent: "xxx", isLoaded: false
        )
        // 同 id → 相等
        XCTAssertEqual(task1, task2)
    }

    func testSystemTaskInequality() {
        let task1 = SystemTask(
            id: "test:1", name: "Test", source: .launchd,
            command: "/usr/bin/true", schedule: nil,
            scheduleDescription: "每天", rawContent: "", isLoaded: true
        )
        let task2 = SystemTask(
            id: "test:2", name: "Test", source: .launchd,
            command: "/usr/bin/true", schedule: nil,
            scheduleDescription: "每天", rawContent: "", isLoaded: true
        )
        XCTAssertNotEqual(task1, task2)
    }
}
