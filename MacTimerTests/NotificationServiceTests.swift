import XCTest
import UserNotifications
@testable import MacTimer

final class NotificationServiceTests: XCTestCase {
    func test_sendNotification_doesNotThrow() async {
        // Since we can't grant permissions in unit tests, just verify it doesn't crash
        await NotificationService.shared.send(title: "Test", body: "Body")
        // No assertion needed — test passes if no crash
    }

    func test_scheduleNotification_buildsCorrectContent() {
        let content = NotificationService.shared.buildContent(title: "Reminder", body: "Do it")
        XCTAssertEqual(content.title, "Reminder")
        XCTAssertEqual(content.body, "Do it")
        XCTAssertEqual(content.sound, .default)
    }
}
