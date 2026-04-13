import Foundation

/// 系统定时任务的来源
enum SystemTaskSource: String, CaseIterable {
    case launchd  = "launchd"
    case crontab  = "crontab"

    var displayName: String {
        switch self {
        case .launchd:  return "LaunchAgent"
        case .crontab:  return "Crontab"
        }
    }

    var iconName: String {
        switch self {
        case .launchd:  return "gearshape.2"
        case .crontab:  return "clock.arrow.2.circlepath"
        }
    }

    var badgeColor: String {
        switch self {
        case .launchd:  return "orange"
        case .crontab:  return "purple"
        }
    }
}

/// 从系统发现的定时任务（只读镜像，纯内存模型）
struct SystemTask: Identifiable, Hashable {
    /// 唯一标识：launchd 用 Label，crontab 用行内容的 hash
    let id: String
    /// 显示名称
    let name: String
    /// 来源
    let source: SystemTaskSource
    /// 执行命令
    let command: String
    /// 调度配置（复用现有 ScheduleConfig）；无法解析时为 nil
    let schedule: ScheduleConfig?
    /// 人类可读的调度描述（用于 schedule 无法映射时的 fallback 展示）
    let scheduleDescription: String
    /// 原始内容（plist XML / crontab 行）
    let rawContent: String
    /// launchd 任务是否已加载运行
    let isLoaded: Bool

    // MARK: - Hashable (ScheduleConfig 不参与比较)
    static func == (lhs: SystemTask, rhs: SystemTask) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
