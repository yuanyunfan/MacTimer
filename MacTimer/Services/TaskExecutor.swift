import Foundation
import AppKit
import os.log

private let shellAuditLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mactimer", category: "ShellExecution")

struct ExecutionOutcome {
    let result: ExecutionResult
    let errorMessage: String?
    let duration: Double
}

final class TaskExecutor {
    static let shared = TaskExecutor()
    private init() {}

    // MARK: - Shell Command Security (Defense-in-Depth)
    //
    // NOTE: This blocklist is **defense-in-depth only**. The primary security
    // boundary is the mandatory sandbox-exec profile applied to every shell
    // command (see `sandboxProfile`). A denylist can never be exhaustive
    // against a Turing-complete shell; these checks exist to catch obvious
    // mistakes and provide user-friendly early rejection messages.

    /// Allowlist of permitted command base names.
    /// Only commands whose first token (after resolving paths) appears in this
    /// list are allowed to execute. Everything else is rejected.
    static let allowedCommands: Set<String> = [
        // Standard POSIX / macOS utilities considered safe within the sandbox
        "echo", "printf", "cat", "head", "tail", "wc", "sort", "uniq",
        "grep", "egrep", "fgrep", "awk", "sed", "cut", "tr", "tee",
        "ls", "find", "stat", "file", "which", "whereis", "type",
        "date", "cal", "uptime", "uname", "hostname", "whoami", "id",
        "env", "printenv", "export", "set",
        "pwd", "dirname", "basename", "realpath", "readlink",
        "test", "[", "true", "false",
        "sleep", "wait",
        "diff", "comm", "cmp", "md5", "shasum", "sha256sum",
        "bc", "expr", "seq", "jot",
        "touch", "mkdir", "cp", "mv", "ln",
        "tar", "gzip", "gunzip", "bzip2", "xz", "zip", "unzip",
        "open",          // macOS open (sandboxed)
        "say",           // macOS text-to-speech
        "pbcopy", "pbpaste",
        "defaults", "sw_vers", "system_profiler", "sysctl",
        "git", "svn",
        "make", "xcodebuild",
        // NOTE: xcrun is excluded because it can invoke arbitrary toolchain
        // binaries (e.g. `xcrun swift`, `xcrun python3`), bypassing the allowlist.
        // General-purpose scripting interpreters (python3, python, ruby, perl,
        // node, swift) are intentionally excluded — they can execute arbitrary
        // code that bypasses both the allowlist and metacharacter checks.
        "brew",
        "man", "apropos", "info",
        "less", "more",
        "df", "du",
        "top", "ps",  // observe-only within sandbox
        "ping", "traceroute", "dig", "nslookup", "host",  // blocked by sandbox network deny
        "ssh", "scp", "sftp",  // blocked by sandbox network deny
    ]

    /// Returns a rejection reason if the command is blocked, or nil if allowed.
    static func validateCommand(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject empty commands
        if trimmed.isEmpty {
            return "命令为空"
        }

        // Reject commands containing newlines (can chain commands in zsh -c).
        // Check the ORIGINAL command, not trimmed, because trimming strips
        // leading/trailing newlines that would still reach the shell.
        if command.contains("\n") || command.contains("\r") {
            return "命令被安全策略拒绝：包含不允许的 shell 元字符 - 换行符（命令链接）"
        }

        // Normalize for pattern matching: collapse whitespace, lowercase
        let normalized = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()

        // --- Reject shell metacharacters that enable command chaining/substitution ---
        // Check these BEFORE the allowlist so chained commands cannot bypass validation.
        let shellMetacharacters: [(pattern: String, description: String)] = [
            (#";"#, "分号（命令链接）"),
            (#"\|"#, "管道符"),
            (#"&&"#, "逻辑与（命令链接）"),
            (#"\|\|"#, "逻辑或（命令链接）"),
            (#"\$\("#, "命令替换 $()"),
            (#"`"#, "反引号命令替换"),
            (#"\$\{"#, "变量展开 ${}"),
            (#">\("#, "进程替换 >()"),
            (#"<\("#, "进程替换 <()"),
        ]

        for (pattern, description) in shellMetacharacters {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return "命令被安全策略拒绝：包含不允许的 shell 元字符 - \(description)"
            }
        }

        // --- Allowlist check ---
        // Extract the base command name (first token, stripped of any path prefix).
        let firstToken = normalized.components(separatedBy: " ").first ?? ""
        let baseName = (firstToken as NSString).lastPathComponent

        if !allowedCommands.contains(baseName) {
            return "命令被安全策略拒绝：不允许执行 \(baseName)（仅允许白名单中的命令）"
        }

        // --- Additional regex-based checks (defense-in-depth) ---
        // Even for allowed commands, block obviously dangerous argument patterns.
        let blockedRegexPatterns: [(pattern: String, description: String)] = [
            // rm with recursive + force targeting root or home
            (#"rm\s+.*-\w*r\w*f\w*.*(/\s|/\"|/$|~)"#, "递归删除根目录或主目录"),
            (#"rm\s+.*-\w*f\w*r\w*.*(/\s|/\"|/$|~)"#, "递归删除根目录或主目录"),
            // Piping anything to a shell interpreter (full or short path)
            (#"\|[^|]*\b(sh|bash|zsh|fish|csh|tcsh|dash|ksh)\b"#, "通过管道将内容传递给 shell"),
            (#"\|\s*(/\w+)*/?(sh|bash|zsh)\b"#, "通过管道将内容传递给 shell"),
            // Reverse shell patterns
            (#"/dev/tcp/"#, "可能的反向 shell"),
            (#"bash\s+-i\s+>&"#, "可能的反向 shell"),
            // Base64 decode piped to shell (obfuscation attempt)
            (#"base64\s+(-d|--decode).*\|\s*\S*(sh|bash|zsh)"#, "通过 base64 解码执行命令"),
            // eval with command substitution or backticks
            (#"eval\s+.*(\$\(|`)"#, "eval 执行动态命令"),
            // source from process substitution or /dev/stdin
            (#"source\s+(/dev/stdin|<\()"#, "从标准输入 source 脚本"),
            // mkfs (format filesystem)
            (#"\bmkfs\b"#, "格式化文件系统"),
            // dd with if= (raw disk write)
            (#"\bdd\b.*\bif="#, "原始磁盘写入"),
            // fork bomb
            (#":\(\)\s*\{"#, "fork bomb"),
            // overwrite disk devices
            (#">\s*/dev/(sd|disk|nvme)"#, "覆盖磁盘设备"),
            // chmod 777 on root
            (#"chmod\s+.*777\s+/"#, "开放根目录权限"),
        ]

        for (pattern, description) in blockedRegexPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) != nil {
                return "命令被安全策略拒绝：\(description)"
            }
        }

        return nil
    }

    /// Sandbox profile that restricts file-system writes and network access.
    /// The command can read most paths and write only to a per-execution
    /// unique subdirectory under /tmp to prevent privilege escalation via /tmp.
    static func sandboxProfile(tmpDir: String) -> String {
        """
        (version 1)
        (deny default)
        (allow process-exec (literal "/bin/zsh") (literal "/bin/bash") (literal "/usr/bin/env"))
        (allow process-fork)
        (allow signal (target self))
        (allow sysctl-read)
        (allow mach-lookup
            (global-name "com.apple.bsd.dirhelper")
            (global-name "com.apple.system.logger")
            (global-name "com.apple.system.opendirectoryd.libinfo")
            (global-name "com.apple.CoreServices.coreservicesd")
            (global-name "com.apple.SecurityServer")
        )
        (allow ipc-posix*)
        (allow file-read*
            (subpath "/usr/lib")
            (subpath "/usr/share")
            (subpath "/usr/bin")
            (subpath "/bin")
            (subpath "/sbin")
            (subpath "/usr/sbin")
            (subpath "/System")
            (subpath "\(tmpDir)")
            (subpath "/dev")
        )
        (deny file-read*
            (subpath "/Users")
            (regex #"/.ssh"#)
            (regex #"/\\.gnupg"#)
            (regex #"/Keychains"#)
            (regex #"/credentials"#)
            (regex #"/\\.aws"#)
            (regex #"/\\.docker"#)
            (regex #"/\\.kube"#)
        )
        (allow file-write*
            (subpath "\(tmpDir)")
            (literal "/dev/null")
            (literal "/dev/zero")
            (literal "/dev/random")
            (literal "/dev/urandom")
        )
        (deny file-write*
            (subpath "/System")
            (subpath "/usr")
            (subpath "/bin")
            (subpath "/sbin")
        )
        (deny network*)
        """
    }

    /// Creates a per-execution temporary directory with restrictive permissions (owner-only).
    /// Returns the path to the created directory.
    static func createSandboxTmpDir() throws -> String {
        let baseDir = NSTemporaryDirectory()
            .appending("com.mactimer.sandbox/")
        let uniqueDir = baseDir.appending(UUID().uuidString)
        try FileManager.default.createDirectory(
            atPath: uniqueDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return uniqueDir
    }

    /// Removes the per-execution temporary directory.
    static func removeSandboxTmpDir(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

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

        // Security: validate command against blocklist
        if let rejection = Self.validateCommand(command) {
            shellAuditLog.error("Shell command BLOCKED: \(command, privacy: .public) — \(rejection, privacy: .public)")
            return ExecutionOutcome(result: .failure, errorMessage: rejection, duration: 0)
        }

        // Audit: log every command that will be executed
        shellAuditLog.info("Shell command executing: \(command, privacy: .public)")

        let start = Date()

        // Create a per-execution temporary directory with restrictive permissions
        let sandboxTmpDir: String
        do {
            sandboxTmpDir = try Self.createSandboxTmpDir()
        } catch {
            return ExecutionOutcome(result: .failure, errorMessage: "无法创建沙箱临时目录: \(error.localizedDescription)", duration: 0)
        }
        defer { Self.removeSandboxTmpDir(sandboxTmpDir) }

        let process = Process()

        // Always run the command inside a sandbox using sandbox-exec
        let profile = Self.sandboxProfile(tmpDir: sandboxTmpDir)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        let sanitizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        process.arguments = ["-p", profile, "/bin/zsh", "-c", sanitizedCommand]

        // Provide a minimal environment to avoid leaking sensitive variables
        let fullEnv = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]
        let allowedKeys = ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "USER", "LOGNAME", "SHELL"]
        for key in allowedKeys {
            if let value = fullEnv[key] {
                env[key] = value
            }
        }
        env["TMPDIR"] = sandboxTmpDir
        process.environment = env

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
            var didCloseHandle = false

            func closeHandleOnce() {
                lock.lock()
                guard !didCloseHandle else { lock.unlock(); return }
                didCloseHandle = true
                lock.unlock()
                pipe.fileHandleForReading.readabilityHandler = nil
                try? pipe.fileHandleForReading.close()
            }

            func resume(with value: Bool) {
                lock.lock()
                guard !didResume else { lock.unlock(); return }
                didResume = true
                lock.unlock()
                continuation.resume(returning: value)
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                if process.isRunning {
                    process.terminate() // SIGTERM

                    // Escalate: if process survives SIGTERM, send SIGKILL after a grace period.
                    let pid = process.processIdentifier
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if process.isRunning {
                            kill(pid, SIGKILL)
                        }
                    }

                    // Close the pipe's read end exactly once to prevent FD leak.
                    closeHandleOnce()

                    // Protect timedOut write under outputLock to avoid data race
                    // with the read that occurs after waitUntilExit() returns.
                    outputLock.lock(); timedOut = true; outputLock.unlock()

                    // Only resume from the timeout path when we actually killed
                    // the process. For natural exits, let waitUntilExit handle it.
                    resume(with: false)
                } else {
                    // Process already exited before timeout fired (e.g. quick exit
                    // with no output). Ensure handler is cleared and FD is closed
                    // to prevent resource leaks if the EOF was missed.
                    closeHandleOnce()
                    // Do NOT resume here — let the waitUntilExit path provide the
                    // correct exit status so error info is not lost.
                }
            }

            DispatchQueue.global().async {
                process.waitUntilExit()
                // Ensure handler is cleared and FD is closed once the process exits,
                // regardless of whether it was a normal exit or a timeout kill.
                closeHandleOnce()
                resume(with: process.terminationStatus == 0)
            }
        }

        let duration = Date().timeIntervalSince(start)
        // Read timedOut under outputLock to avoid data race with the timeout closure.
        outputLock.lock(); let didTimeout = timedOut; outputLock.unlock()
        if didTimeout {
            shellAuditLog.warning("Shell command TIMEOUT after \(Int(timeoutSeconds))s: \(command, privacy: .public)")
            return ExecutionOutcome(result: .timeout,
                                   errorMessage: "执行超时（超过 \(Int(timeoutSeconds)) 秒）",
                                   duration: duration)
        }
        if !finished {
            outputLock.lock()
            let output = String(data: outputData, encoding: .utf8) ?? "未知错误"
            outputLock.unlock()
            shellAuditLog.warning("Shell command FAILED: \(command, privacy: .public)")
            return ExecutionOutcome(result: .failure, errorMessage: output, duration: duration)
        }
        shellAuditLog.info("Shell command SUCCEEDED in \(String(format: "%.2f", duration))s: \(command, privacy: .public)")
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
