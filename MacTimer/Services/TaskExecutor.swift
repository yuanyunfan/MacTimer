import Foundation
import AppKit

struct ExecutionOutcome {
    let result: ExecutionResult
    let errorMessage: String?
    let duration: Double
}

final class TaskExecutor {
    static let shared = TaskExecutor()
    private init() {}

    func execute(task: TaskItem, taskName: String) async -> ExecutionOutcome {
        switch task.taskType {
        case .shellScript:
            return await executeShell(payload: task.payload)
        case .openURL:
            return await executeOpenURL(payload: task.payload)
        case .openApp:
            return await executeOpenApp(payload: task.payload)
        case .notification:
            return await executeNotification(payload: task.payload)
        }
    }

    func executeShell(payload: TaskPayload, timeoutSeconds: Double = 30.0) async -> ExecutionOutcome {
        guard let command = payload.command, !command.isEmpty else {
            return ExecutionOutcome(result: .failure, errorMessage: "命令为空", duration: 0)
        }
        let start = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // C1 / I1: 用 readabilityHandler 异步消费 pipe，防止输出 >64KB 时写端阻塞
        var outputData = Data()
        let outputLock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF：停止监听，释放 FD
                pipe.fileHandleForReading.readabilityHandler = nil
            } else {
                outputLock.lock()
                outputData.append(chunk)
                outputLock.unlock()
            }
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return ExecutionOutcome(result: .failure, errorMessage: error.localizedDescription, duration: 0)
        }

        // C2: 独立标志，仅在超时路径设置，避免快速失败被误判为 timeout
        var timedOut = false

        let finished = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let lock = NSLock()
            var didResume = false

            func resume(with value: Bool) {
                lock.lock()
                guard !didResume else { lock.unlock(); return }
                didResume = true
                lock.unlock()
                continuation.resume(returning: value)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                if process.isRunning {
                    // Clear the readabilityHandler immediately so it stops firing
                    // even if the process doesn't exit cleanly after SIGTERM.
                    pipe.fileHandleForReading.readabilityHandler = nil

                    process.terminate() // SIGTERM

                    // Escalate: if process survives SIGTERM, send SIGKILL after a grace period.
                    let pid = process.processIdentifier
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            kill(pid, SIGKILL)
                        }
                    }

                    // Protect timedOut write under outputLock to avoid data race
                    // with the read that occurs after waitUntilExit() returns.
                    outputLock.lock(); timedOut = true; outputLock.unlock()
                }
                resume(with: false)
            }

            DispatchQueue.global().async {
                process.waitUntilExit()
                // Ensure handler is cleared and FD is closed once the process exits,
                // regardless of whether it was a normal exit or a timeout kill.
                pipe.fileHandleForReading.readabilityHandler = nil
                try? pipe.fileHandleForReading.close()
                resume(with: process.terminationStatus == 0)
            }
        }

        let duration = Date().timeIntervalSince(start)
        // Read timedOut under outputLock to avoid data race with the timeout closure.
        outputLock.lock(); let didTimeout = timedOut; outputLock.unlock()
        if didTimeout {
            return ExecutionOutcome(result: .timeout,
                                   errorMessage: "执行超时（超过 \(Int(timeoutSeconds)) 秒）",
                                   duration: duration)
        }
        if !finished {
            outputLock.lock()
            let output = String(data: outputData, encoding: .utf8) ?? "未知错误"
            outputLock.unlock()
            return ExecutionOutcome(result: .failure, errorMessage: output, duration: duration)
        }
        return ExecutionOutcome(result: .success, errorMessage: nil, duration: duration)
    }

    /// Allowed URL schemes for the openURL task type.
    /// This whitelist is enforced at execution time to prevent malicious schemes
    /// (e.g. file://, ssh://) injected via CoreData from being opened.
    private static let allowedURLSchemes: Set<String> = ["http", "https"]

    func executeOpenURL(payload: TaskPayload) async -> ExecutionOutcome {
        guard let urlString = payload.urlString,
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              Self.allowedURLSchemes.contains(scheme) else {
            return ExecutionOutcome(result: .failure, errorMessage: "无效的 URL（仅支持 http/https）: \(payload.urlString ?? "")", duration: 0)
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        return ExecutionOutcome(result: opened ? .success : .failure,
                                errorMessage: opened ? nil : "无法打开 URL",
                                duration: 0)
    }

    func executeOpenApp(payload: TaskPayload) async -> ExecutionOutcome {
        guard let bundleID = payload.bundleID, !bundleID.isEmpty else {
            return ExecutionOutcome(result: .failure, errorMessage: "未指定 App", duration: 0)
        }
        // I2: NSWorkspace API 必须在主线程调用
        guard let appURL = await MainActor.run(body: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }) else {
            return ExecutionOutcome(result: .failure,
                                   errorMessage: "找不到 App (Bundle ID: \(bundleID))，请确认 App 已安装",
                                   duration: 0)
        }
        do {
            let config = NSWorkspace.OpenConfiguration()
            try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return ExecutionOutcome(result: .success, errorMessage: nil, duration: 0)
        } catch {
            return ExecutionOutcome(result: .failure, errorMessage: error.localizedDescription, duration: 0)
        }
    }

    func executeNotification(payload: TaskPayload) async -> ExecutionOutcome {
        let title = payload.notificationTitle ?? "MacTimer 提醒"
        let body = payload.notificationBody ?? ""
        await NotificationService.shared.send(title: title, body: body)
        return ExecutionOutcome(result: .success, errorMessage: nil, duration: 0)
    }
}
