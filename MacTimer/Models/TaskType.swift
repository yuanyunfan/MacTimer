import Foundation

enum TaskType: String, Codable, CaseIterable {
    case shellScript
    case openURL
    case openApp
    case notification

    var displayName: String {
        switch self {
        case .shellScript:   return "Shell 脚本"
        case .openURL:       return "打开 URL"
        case .openApp:       return "打开 App"
        case .notification:  return "发送通知"
        }
    }
}

enum ExecutionResult: String, Codable {
    case success
    case failure
    case timeout
}

extension TaskType {
    var iconName: String {
        switch self {
        case .shellScript:  return "terminal"
        case .openURL:      return "link"
        case .openApp:      return "app.badge"
        case .notification: return "bell"
        }
    }
}

// Payload stored alongside TaskType
struct TaskPayload: Codable {
    // shellScript
    var command: String?
    // openURL
    var urlString: String?
    // openApp
    var bundleID: String?
    var appDisplayName: String?   // for display only
    // notification
    var notificationTitle: String?
    var notificationBody: String?
}
