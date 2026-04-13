import UserNotifications
import Foundation
import os.log

private let logger = Logger(subsystem: "com.mactimer.MacTimer", category: "NotificationService")

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("权限请求结果: granted=\(granted)")
        } catch {
            logger.error("权限请求失败: \(error)")
        }
        let settings = await center.notificationSettings()
        logger.info("权限状态: \(settings.authorizationStatus.rawValue) (0=未决定 1=拒绝 2=授权 3=临时)")
        logger.info("Alert: \(settings.alertSetting.rawValue) (0=不支持 1=禁用 2=启用)")
    }

    func send(title: String, body: String) async {
        let content = buildContent(title: title, body: body)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        do {
            try await center.add(request)
            logger.info("通知已发送: \(title)")
        } catch {
            logger.error("发送通知失败: \(error)")
        }
    }

    func buildContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        return content
    }

    /// Send an error notification to the user (used by TaskExecutor on failure)
    func sendError(taskName: String, message: String) async {
        await send(title: "MacTimer 任务失败", body: "「\(taskName)」: \(message)")
    }
}
