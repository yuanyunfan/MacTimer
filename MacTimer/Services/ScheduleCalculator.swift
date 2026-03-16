import Foundation

struct ScheduleCalculator {
    /// Returns the next Date this schedule should fire after `after`.
    /// `isFirstRun` is used only for interval tasks with startImmediately = true.
    static func nextRunAt(
        schedule: ScheduleConfig,
        after date: Date = Date(),
        isFirstRun: Bool = false
    ) -> Date? {
        switch schedule.type {
        case .interval:
            guard let cfg = schedule.interval else { return nil }
            if isFirstRun && cfg.startImmediately {
                return date
            }
            return date.addingTimeInterval(TimeInterval(cfg.seconds))

        case .fixedTime:
            guard let cfg = schedule.fixedTime, !cfg.weekdays.isEmpty else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone.current
            // Try to find the next matching weekday within the next 14 days
            for dayOffset in 0..<14 {
                let candidate = cal.date(byAdding: .day, value: dayOffset, to: date)!
                let isoWeekday = cal.component(.weekday, from: candidate)
                // Calendar.weekday: 1=Sunday, 2=Monday … 7=Saturday
                // Our stored weekdays: 1=Monday … 7=Sunday (ISO)
                let isoMapped = isoWeekday == 1 ? 7 : isoWeekday - 1
                guard cfg.weekdays.contains(isoMapped) else { continue }
                // Build candidate fire date
                var comps = cal.dateComponents([.year, .month, .day], from: candidate)
                comps.hour = cfg.hour
                comps.minute = cfg.minute
                comps.second = 0
                guard let fireDate = cal.date(from: comps) else { continue }
                if fireDate > date {
                    return fireDate
                }
            }
            return nil
        }
    }
}
