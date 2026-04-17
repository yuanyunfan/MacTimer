import Foundation

struct ScheduleCalculator {
    // covers two full weeks, ensuring every weekday appears at least twice
    private static let maxLookAheadDays = 14

    /// Returns the next Date this schedule should fire after `after`.
    /// `isFirstRun` is used only for interval tasks with startImmediately = true.
    static func nextRunAt(
        schedule: ScheduleConfig,
        after date: Date = Date(),
        isFirstRun: Bool = false
    ) -> Date? {
        switch schedule.type {
        case .once:
            guard let cfg = schedule.once else { return nil }
            return cfg.date > date ? cfg.date : nil

        case .interval:
            guard let cfg = schedule.interval, cfg.seconds >= 60 else { return nil }
            if isFirstRun && cfg.startImmediately {
                return date
            }
            return date.addingTimeInterval(TimeInterval(cfg.seconds))

        case .fixedTime:
            guard let cfg = schedule.fixedTime, !cfg.weekdays.isEmpty else { return nil }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone.current
            // covers two full weeks, ensuring every weekday appears at least twice
            for dayOffset in 0..<ScheduleCalculator.maxLookAheadDays {
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
                // During DST spring-forward, the requested time may not exist.
                // Use nextDate(after:matching:matchingPolicy:) to resolve to
                // the next valid time on that day.
                let fireDate: Date
                if let exact = cal.date(from: comps) {
                    fireDate = exact
                } else {
                    // Start of the candidate day, then find the next matching time
                    let startOfDay = cal.startOfDay(for: candidate)
                    var matchComps = DateComponents()
                    matchComps.hour = cfg.hour
                    matchComps.minute = cfg.minute
                    matchComps.second = 0
                    guard let resolved = cal.nextDate(
                        after: startOfDay,
                        matching: matchComps,
                        matchingPolicy: .nextTimePreservingSmallerComponents
                    ) else { continue }
                    // Ensure the resolved date is still on the same day
                    if cal.isDate(resolved, inSameDayAs: candidate) {
                        fireDate = resolved
                    } else {
                        continue
                    }
                }
                if fireDate > date {
                    return fireDate
                }
            }
            return nil
        }
    }
}
