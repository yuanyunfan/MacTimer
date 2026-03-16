import XCTest
@testable import MacTimer

final class TaskExecutorTests: XCTestCase {

    func test_shellScript_succeeds() async throws {
        let payload = TaskPayload(command: "echo hello")
        let result = await TaskExecutor.shared.executeShell(payload: payload)
        XCTAssertEqual(result.result, .success)
        XCTAssertNil(result.errorMessage)
    }

    func test_shellScript_fails_onInvalidCommand() async throws {
        let payload = TaskPayload(command: "nonexistent_command_xyz_abc")
        let result = await TaskExecutor.shared.executeShell(payload: payload)
        XCTAssertEqual(result.result, .failure)
        XCTAssertNotNil(result.errorMessage)
    }

    func test_shellScript_timesOut() async throws {
        let payload = TaskPayload(command: "sleep 5")
        let result = await TaskExecutor.shared.executeShell(payload: payload, timeoutSeconds: 1)
        XCTAssertEqual(result.result, .timeout)
    }

    func test_openURL_invalidURL_returnsFailure() async {
        let payload = TaskPayload(urlString: "not a valid url%%%")
        let result = await TaskExecutor.shared.executeOpenURL(payload: payload)
        XCTAssertEqual(result.result, .failure)
    }
}
