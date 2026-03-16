import Foundation

enum ScheduleType: String, Codable, CaseIterable {
    case fixedTime
    case interval

    var displayName: String {
        switch self {
        case .fixedTime: return "固定时间"
        case .interval:  return "循环间隔"
        }
    }
}

struct FixedTimeConfig: Codable {
    /// 1 = Monday, 7 = Sunday (ISO weekday)
    var weekdays: [Int]   // e.g. [1, 3, 5]
    var hour: Int         // 0–23
    var minute: Int       // 0–59
}

struct IntervalConfig: Codable {
    var seconds: Int      // minimum 60
    var startImmediately: Bool
}

struct ScheduleConfig: Codable {
    var type: ScheduleType
    var fixedTime: FixedTimeConfig?
    var interval: IntervalConfig?
}
