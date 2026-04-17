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
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.weekdays = try container.decode([Int].self, forKey: .weekdays).filter { (1...7).contains($0) }
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

    /// Returns a validation error message if the type doesn't match the populated config, nil if valid.
    func validationError() -> String? {
        switch type {
        case .once:
            if once == nil { return "Schedule type is .once but once config is nil" }
        case .fixedTime:
            if fixedTime == nil { return "Schedule type is .fixedTime but fixedTime config is nil" }
            if let cfg = fixedTime, cfg.weekdays.isEmpty { return "fixedTime config has no weekdays" }
        case .interval:
            if interval == nil { return "Schedule type is .interval but interval config is nil" }
            if let cfg = interval, cfg.seconds < 60 { return "interval config seconds must be >= 60" }
        }
        return nil
    }

    /// Whether this config is internally consistent.
    var isValid: Bool { validationError() == nil }
}
