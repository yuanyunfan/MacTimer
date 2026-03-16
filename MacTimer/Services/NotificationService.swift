import UserNotifications
import Foundation

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("NotificationService: permission request failed: \(error)")
        }
    }

    func send(title: String, body: String) async {
        let content = buildContent(title: title, body: body)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        let center = UNUserNotificationCenter.current()
        do {
            try await center.add(request)
        } catch {
            print("NotificationService: failed to send notification: \(error)")
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
