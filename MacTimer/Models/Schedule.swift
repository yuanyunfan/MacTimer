import Foundation

enum ScheduleType: String, Codable, CaseIterable {
    case fixedTime
    case once
    case interval

    var displayName: String {
        switch self {
        case .fixedTime: return "固定时间"
        case .once:      return "提醒一次"
        case .interval:  return "循环间隔"
        }
    }
}

struct FixedTimeConfig: Codable {
    /// 1 = Monday, 7 = Sunday (ISO weekday)
    var weekdays: [Int]   // e.g. [1, 3, 5]
    var hour: Int         // 0–23
    var minute: Int       // 0–59

    init(weekdays: [Int], hour: Int, minute: Int) {
        self.weekdays = weekdays
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.weekdays = try container.decode([Int].self, forKey: .weekdays)
        let rawHour = try container.decode(Int.self, forKey: .hour)
        let rawMinute = try container.decode(Int.self, forKey: .minute)
        self.hour = max(0, min(23, rawHour))
        self.minute = max(0, min(59, rawMinute))
    }
}

struct OnceConfig: Codable {
    var date: Date        // specific date & time to fire once
}

struct IntervalConfig: Codable {
    var seconds: Int      // minimum 60
    var startImmediately: Bool

    init(seconds: Int, startImmediately: Bool) {
        self.seconds = max(60, seconds)
        self.startImmediately = startImmediately
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawSeconds = try container.decode(Int.self, forKey: .seconds)
        self.seconds = max(60, rawSeconds)
        self.startImmediately = try container.decode(Bool.self, forKey: .startImmediately)
    }
}

struct ScheduleConfig: Codable {
    var type: ScheduleType
    var fixedTime: FixedTimeConfig?
    var once: OnceConfig?
    var interval: IntervalConfig?
}
