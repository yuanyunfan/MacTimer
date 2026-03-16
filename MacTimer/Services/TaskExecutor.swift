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

        do {
            try process.run()
        } catch {
            return ExecutionOutcome(result: .failure, errorMessage: error.localizedDescription, duration: 0)
        }

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
                if process.isRunning { process.terminate() }
                resume(with: false)
            }

            DispatchQueue.global().async {
                process.waitUntilExit()
                resume(with: process.terminationStatus == 0)
            }
        }

        let duration = Date().timeIntervalSince(start)
        if !finished && process.terminationReason == .uncaughtSignal {
            return ExecutionOutcome(result: .timeout,
                                   errorMessage: "执行超时（超过 \(Int(timeoutSeconds)) 秒）",
                                   duration: duration)
        }
        if process.terminationStatus != 0 {
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "未知错误"
            return ExecutionOutcome(result: .failure, errorMessage: output, duration: duration)
        }
        return ExecutionOutcome(result: .success, errorMessage: nil, duration: duration)
    }

    func executeOpenURL(payload: TaskPayload) async -> ExecutionOutcome {
        guard let urlString = payload.urlString,
              let url = URL(string: urlString),
              url.scheme != nil else {
            return ExecutionOutcome(result: .failure, errorMessage: "无效的 URL: \(payload.urlString ?? "")", duration: 0)
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
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
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
