import Foundation

/// 系统定时任务发现服务
/// 扫描 launchd LaunchAgents 和 crontab，生成只读的 SystemTask 列表
@MainActor
final class SystemTaskDiscoveryService: ObservableObject {
    static let shared = SystemTaskDiscoveryService()

    @Published private(set) var tasks: [SystemTask] = []
    @Published private(set) var lastDiscoveryDate: Date?

    private init() {}

    // MARK: - Public

    /// 执行一次完整扫描
    func discover() {
        var discovered: [SystemTask] = []
        discovered.append(contentsOf: discoverLaunchAgents())
        discovered.append(contentsOf: discoverCrontab())
        tasks = discovered
        lastDiscoveryDate = Date()
    }

    // MARK: - LaunchAgents Discovery

    private func discoverLaunchAgents() -> [SystemTask] {
        let agentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: agentsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let plists = files.filter { $0.pathExtension == "plist" }
        return plists.compactMap { parseLaunchdPlist(at: $0) }
    }

    private func parseLaunchdPlist(at url: URL) -> SystemTask? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any] else {
            return nil
        }

        let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent

        // 提取命令
        let command: String
        if let args = plist["ProgramArguments"] as? [String] {
            command = args.joined(separator: " ")
        } else if let program = plist["Program"] as? String {
            command = program
        } else {
            command = "（无命令）"
        }

        // 解析调度配置
        let (schedule, scheduleDesc) = parseLaunchdSchedule(plist)

        // 跳过纯事件驱动型任务（无定时调度，也没有 RunAtLoad）
        let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        if schedule == nil && !runAtLoad {
            return nil
        }

        // 判断是否已加载（通过 launchctl list 检查）
        let isLoaded = checkLaunchdLoaded(label: label)

        // 生成原始内容预览
        let rawContent: String
        if let xmlString = String(data: data, encoding: .utf8) {
            rawContent = xmlString
        } else {
            rawContent = "（二进制 plist，无法预览）"
        }

        var descParts: [String] = []
        if let scheduleDesc { descParts.append(scheduleDesc) }
        if runAtLoad { descParts.append("启动时运行") }
        let finalDesc = descParts.isEmpty ? "事件驱动" : descParts.joined(separator: " + ")

        return SystemTask(
            id: "launchd:\(label)",
            name: label,
            source: .launchd,
            command: command,
            schedule: schedule,
            scheduleDescription: finalDesc,
            rawContent: rawContent,
            isLoaded: isLoaded
        )
    }

    /// 解析 launchd 的 StartInterval / StartCalendarInterval
    private func parseLaunchdSchedule(_ plist: [String: Any]) -> (ScheduleConfig?, String?) {
        // StartInterval → 间隔模式
        if let interval = plist["StartInterval"] as? Int, interval > 0 {
            let config = ScheduleConfig(
                type: .interval,
                fixedTime: nil,
                interval: IntervalConfig(seconds: interval, startImmediately: false)
            )
            return (config, formatInterval(interval))
        }

        // StartCalendarInterval → 固定时间模式
        // 可以是 dict 或 [dict]
        if let calDict = plist["StartCalendarInterval"] as? [String: Any] {
            return parseCalendarInterval(calDict)
        }
        if let calArray = plist["StartCalendarInterval"] as? [[String: Any]],
           let first = calArray.first {
            // 多个调度取第一个展示，描述中标注还有更多
            let (config, desc) = parseCalendarInterval(first)
            let suffix = calArray.count > 1 ? " (共 \(calArray.count) 条规则)" : ""
            return (config, desc.map { $0 + suffix })
        }

        return (nil, nil)
    }

    private func parseCalendarInterval(_ dict: [String: Any]) -> (ScheduleConfig?, String?) {
        let hour   = dict["Hour"]    as? Int
        let minute = dict["Minute"]  as? Int
        let weekday = dict["Weekday"] as? Int   // 0=Sunday, 1=Monday...6=Saturday

        // 至少需要 hour 或 minute 才能构建 FixedTimeConfig
        guard hour != nil || minute != nil else {
            // 有 Day/Month 等字段但无时间，生成描述但不映射
            return (nil, describeLaunchdCalendarDict(dict))
        }

        let h = hour ?? 0
        let m = minute ?? 0

        // 转换 weekday: launchd 用 0=Sunday, 我们用 ISO 1=Monday..7=Sunday
        let isoWeekdays: [Int]
        if let wd = weekday {
            let iso = wd == 0 ? 7 : wd  // 0(Sun) → 7, 1(Mon) → 1, ..., 6(Sat) → 6
            isoWeekdays = [iso]
        } else {
            isoWeekdays = [1, 2, 3, 4, 5, 6, 7]  // 每天
        }

        let config = ScheduleConfig(
            type: .fixedTime,
            fixedTime: FixedTimeConfig(weekdays: isoWeekdays, hour: h, minute: m),
            interval: nil
        )

        return (config, describeLaunchdCalendarDict(dict))
    }

    private func describeLaunchdCalendarDict(_ dict: [String: Any]) -> String {
        var parts: [String] = []
        if let month = dict["Month"] as? Int { parts.append("\(month) 月") }
        if let day   = dict["Day"]   as? Int { parts.append("\(day) 日") }
        if let wd    = dict["Weekday"] as? Int {
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            parts.append("周\(names[safe: wd] ?? "?")")
        }
        let h = dict["Hour"]   as? Int ?? 0
        let m = dict["Minute"] as? Int ?? 0
        parts.append(String(format: "%02d:%02d", h, m))
        return parts.joined(separator: " ")
    }

    /// 检查 launchd job 是否已加载
    private func checkLaunchdLoaded(label: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", label]
        process.standardOutput = FileHandle.nullDevice
        process.standardError  = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Crontab Discovery

    private func discoverCrontab() -> [SystemTask] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/crontab")
        process.arguments = ["-l"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else { return [] }  // 无 crontab

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        let lines = output.components(separatedBy: .newlines)
        return lines.enumerated().compactMap { index, line in
            parseCrontabLine(line, lineNumber: index + 1)
        }
    }

    private func parseCrontabLine(_ line: String, lineNumber: Int) -> SystemTask? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // 跳过空行和注释
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        // 处理环境变量设置行（如 SHELL=/bin/bash, PATH=..., CRON_TZ="America/New York"）
        // Use regex: line starts with a valid identifier followed by '='
        if trimmed.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil {
            return nil
        }

        // 标准 cron 格式: minute hour day month weekday command
        let components = trimmed.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard components.count >= 6 else { return nil }

        let minuteField  = String(components[0])
        let hourField    = String(components[1])
        let dayField     = String(components[2])
        let monthField   = String(components[3])
        let weekdayField = String(components[4])
        let command       = String(components[5])

        // 解析调度
        let (schedule, scheduleDesc) = parseCronSchedule(
            minute: minuteField, hour: hourField,
            day: dayField, month: monthField, weekday: weekdayField
        )

        // 生成可读名称：取命令的最后一个路径组件或前 40 字符
        let name = extractCronTaskName(command)

        // id 用行内容的确定性 hash（DJB2），确保跨进程启动稳定
        let stableHash = trimmed.utf8.reduce(into: UInt64(5381)) { hash, byte in
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        let id = "crontab:\(stableHash)"

        return SystemTask(
            id: id,
            name: name,
            source: .crontab,
            command: command,
            schedule: schedule,
            scheduleDescription: scheduleDesc,
            rawContent: trimmed,
            isLoaded: true  // crontab 任务始终活跃
        )
    }

    /// 解析 cron 5 字段表达式
    private func parseCronSchedule(
        minute: String, hour: String,
        day: String, month: String, weekday: String
    ) -> (ScheduleConfig?, String) {
        // 尝试识别简单的间隔模式: */N
        if let intervalConfig = tryParseAsInterval(minute: minute, hour: hour) {
            let desc = formatInterval(intervalConfig.seconds)
            let config = ScheduleConfig(type: .interval, fixedTime: nil, interval: intervalConfig)
            return (config, desc)
        }

        // 尝试解析为固定时间
        if let fixedConfig = tryParseAsFixedTime(minute: minute, hour: hour, weekday: weekday, day: day, month: month) {
            let config = ScheduleConfig(type: .fixedTime, fixedTime: fixedConfig, interval: nil)
            let desc = describeFixedTime(fixedConfig)
            return (config, desc)
        }

        // 无法映射，生成原始描述
        let desc = "\(minute) \(hour) \(day) \(month) \(weekday)"
        return (nil, desc)
    }

    /// 尝试将 */N 格式解析为间隔
    private func tryParseAsInterval(minute: String, hour: String) -> IntervalConfig? {
        // */N * * * * → 每 N 分钟
        if minute.hasPrefix("*/"), let n = Int(minute.dropFirst(2)),
           hour == "*" {
            return IntervalConfig(seconds: n * 60, startImmediately: false)
        }
        // 0 */N * * * → 每 N 小时
        if minute == "0", hour.hasPrefix("*/"), let n = Int(hour.dropFirst(2)) {
            return IntervalConfig(seconds: n * 3600, startImmediately: false)
        }
        return nil
    }

    /// 尝试解析为固定时间配置
    private func tryParseAsFixedTime(
        minute: String, hour: String, weekday: String,
        day: String, month: String
    ) -> FixedTimeConfig? {
        // 需要具体的 minute 和 hour
        guard let m = Int(minute), let h = Int(hour) else { return nil }
        guard m >= 0 && m <= 59, h >= 0 && h <= 23 else { return nil }

        // 解析 weekday
        let isoWeekdays = parseCronWeekdays(weekday)
        guard !isoWeekdays.isEmpty else { return nil }

        // 如果 day 或 month 不是 *，说明是月/年级别调度，我们的模型不支持
        if day != "*" || month != "*" { return nil }

        return FixedTimeConfig(weekdays: isoWeekdays, hour: h, minute: m)
    }

    /// 解析 cron weekday 字段，返回 ISO weekday 数组
    /// cron: 0/7=Sunday, 1=Monday...6=Saturday
    /// ISO:  1=Monday...7=Sunday
    private func parseCronWeekdays(_ field: String) -> [Int] {
        if field == "*" {
            return [1, 2, 3, 4, 5, 6, 7]
        }

        var result: Set<Int> = []

        for part in field.split(separator: ",") {
            let s = String(part)

            // 范围: 1-5
            if s.contains("-") {
                let bounds = s.split(separator: "-")
                if bounds.count == 2, let lo = Int(bounds[0]), let hi = Int(bounds[1]) {
                    for cronDay in lo...hi {
                        if let iso = cronWeekdayToISO(cronDay) { result.insert(iso) }
                    }
                }
            }
            // 单个数字: 1
            else if let cronDay = Int(s) {
                if let iso = cronWeekdayToISO(cronDay) { result.insert(iso) }
            }
        }

        return result.sorted()
    }

    /// cron weekday → ISO weekday
    private func cronWeekdayToISO(_ cron: Int) -> Int? {
        // cron: 0,7=Sun  1=Mon 2=Tue 3=Wed 4=Thu 5=Fri 6=Sat
        // ISO:  7=Sun    1=Mon 2=Tue 3=Wed 4=Thu 5=Fri 6=Sat
        switch cron {
        case 0, 7: return 7
        case 1...6: return cron
        default: return nil
        }
    }

    // MARK: - Formatting Helpers

    private func formatInterval(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 && minutes > 0 { return "每 \(hours) 小时 \(minutes) 分" }
        if hours > 0 { return "每 \(hours) 小时" }
        if minutes > 0 { return "每 \(minutes) 分钟" }
        return "每 \(seconds) 秒"
    }

    private func describeFixedTime(_ config: FixedTimeConfig) -> String {
        let dayNames = ["一", "二", "三", "四", "五", "六", "日"]
        if config.weekdays.count == 7 {
            return String(format: "每天 %02d:%02d", config.hour, config.minute)
        }
        let days = config.weekdays.map { "周\(dayNames[safe: $0 - 1] ?? "?")" }
            .joined(separator: "、")
        return String(format: "%@ %02d:%02d", days, config.hour, config.minute)
    }

    private func extractCronTaskName(_ command: String) -> String {
        // 取命令中第一个可执行文件的名称
        let firstPart = command.split(separator: " ").first.map(String.init) ?? command
        let lastComponent = (firstPart as NSString).lastPathComponent
        if lastComponent.count <= 40 {
            return lastComponent
        }
        return String(lastComponent.prefix(37)) + "..."
    }

    // MARK: - Test Helpers

    #if DEBUG
    func testParseCronWeekdays(_ field: String) -> [Int] {
        parseCronWeekdays(field)
    }

    func testParseCronSchedule(
        minute: String, hour: String, day: String, month: String, weekday: String
    ) -> (ScheduleConfig?, String) {
        parseCronSchedule(minute: minute, hour: hour, day: day, month: month, weekday: weekday)
    }

    func testParseLaunchdSchedule(_ plist: [String: Any]) -> (ScheduleConfig?, String?) {
        parseLaunchdSchedule(plist)
    }

    func testParseCrontabLine(_ line: String, lineNumber: Int) -> SystemTask? {
        parseCrontabLine(line, lineNumber: lineNumber)
    }

    func testFormatInterval(_ seconds: Int) -> String {
        formatInterval(seconds)
    }
    #endif
}
