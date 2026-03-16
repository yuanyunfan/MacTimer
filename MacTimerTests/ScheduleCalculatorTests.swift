import XCTest
@testable import MacTimer

final class ScheduleCalculatorTests: XCTestCase {

    func test_interval_nextRunAt_isNowPlusSeconds() {
        let config = ScheduleConfig(
            type: .interval,
            fixedTime: nil,
            interval: IntervalConfig(seconds: 3600, startImmediately: false)
        )
        let now = Date()
        let next = ScheduleCalculator.nextRunAt(schedule: config, after: now)
        let diff = next!.timeIntervalSince(now)
        XCTAssertEqual(diff, 3600, accuracy: 1.0)
    }

    func test_interval_startImmediately_returnsNow() {
        let config = ScheduleConfig(
            type: .interval,
            fixedTime: nil,
            interval: IntervalConfig(seconds: 3600, startImmediately: true)
        )
        let now = Date()
        let next = ScheduleCalculator.nextRunAt(schedule: config, after: now, isFirstRun: true)
        XCTAssertNotNil(next)
        XCTAssertEqual(next!.timeIntervalSince(now), 0, accuracy: 1.0)
    }

    func test_fixedTime_nextRunAt_returnsFutureDate() {
        // Monday 09:00 — find next occurrence from a known date
        // 2026-03-16 is Monday
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let monday = cal.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 8, minute: 0))!
        let config = ScheduleConfig(
            type: .fixedTime,
            fixedTime: FixedTimeConfig(weekdays: [2], hour: 9, minute: 0), // weekday 2 = Tuesday
            interval: nil
        )
        let next = ScheduleCalculator.nextRunAt(schedule: config, after: monday)
        XCTAssertNotNil(next)
        // Should be Tuesday 2026-03-17 09:00
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: next!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 17)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 0)
    }

    func test_fixedTime_nextDay_returnsTomorrow() {
        // If it's already past today's scheduled time, should jump to next week
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        // Monday 10:00 (past 09:00)
        let monday = cal.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 10, minute: 0))!
        let config = ScheduleConfig(
            type: .fixedTime,
            // Tuesday = weekday 2 in ISO (our mapping: 1=Mon…7=Sun)
            // Reference date is Monday 2026-03-16 at 10:00, target weekday [2] = Tuesday
            // Expected next fire: Tuesday 2026-03-17 09:00
            fixedTime: FixedTimeConfig(weekdays: [2], hour: 9, minute: 0),
            interval: nil
        )
        let next = ScheduleCalculator.nextRunAt(schedule: config, after: monday)
        XCTAssertNotNil(next)
        let comps = cal.dateComponents([.day], from: next!)
        // Should be Tuesday 2026-03-17
        XCTAssertEqual(comps.day, 17)
    }

    func test_fixedTime_todayPastTime_returnsNextWeek() {
        // today = Monday 2026-03-16 at 10:00, target weekday Monday (1), fire time 09:00
        // Expected: next Monday 2026-03-23 09:00
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let monday = cal.date(from: DateComponents(year: 2026, month: 3, day: 16, hour: 10, minute: 0))!
        let config = ScheduleConfig(
            type: .fixedTime,
            fixedTime: FixedTimeConfig(weekdays: [1], hour: 9, minute: 0), // weekday 1 = Monday
            interval: nil
        )
        let next = ScheduleCalculator.nextRunAt(schedule: config, after: monday)
        XCTAssertNotNil(next)
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: next!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 3)
        XCTAssertEqual(comps.day, 23)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 0)
    }

    func test_interval_nilConfig_returnsNil() {
        let config = ScheduleConfig(type: .interval, fixedTime: nil, interval: nil)
        let result = ScheduleCalculator.nextRunAt(schedule: config, after: Date())
        XCTAssertNil(result)
    }

    func test_fixedTime_emptyWeekdays_returnsNil() {
        let config = ScheduleConfig(
            type: .fixedTime,
            fixedTime: FixedTimeConfig(weekdays: [], hour: 9, minute: 0),
            interval: nil
        )
        let result = ScheduleCalculator.nextRunAt(schedule: config, after: Date())
        XCTAssertNil(result)
    }

    func test_fixedTime_nilConfig_returnsNil() {
        let config = ScheduleConfig(type: .fixedTime, fixedTime: nil, interval: nil)
        let result = ScheduleCalculator.nextRunAt(schedule: config, after: Date())
        XCTAssertNil(result)
    }
}
