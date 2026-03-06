import Foundation
import os.log

/// Enhanced CLI executor: supports timeout, progress, cancellation, error handling
@MainActor
final class CLIExecutor {
    // MARK: - Types

    struct ExecutionResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        let duration: TimeInterval
        let wasCancelled: Bool
    }

    struct ExecutionOptions {
        let timeout: TimeInterval?
        let captureStderr: Bool
        let parseProgress: Bool
        let dryRun: Bool

        static let `default` = ExecutionOptions(
            timeout: 300, // 5 分钟
            captureStderr: true,
            parseProgress: true,
            dryRun: false
        )
    }

    enum ExecutionError: LocalizedError, Equatable {
        case timeout
        case cancelled
        case commandNotFound(String)
        case nonZeroExit(Int32, stderr: String)
        case invalidOutput(String)

        var errorDescription: String? {
            switch self {
            case .timeout:
                "Execution timeout"
            case .cancelled:
                "Operation cancelled"
            case .commandNotFound(let cmd):
                "Command not found: \(cmd)"
            case .nonZeroExit(let code, let stderr):
                "Command failed (exit code: \(code))\n\(stderr)"
            case .invalidOutput(let msg):
                "Output parsing failed: \(msg)"
            }
        }

        static func == (lhs: ExecutionError, rhs: ExecutionError) -> Bool {
            switch (lhs, rhs) {
            case (.timeout, .timeout):
                true
            case (.cancelled, .cancelled):
                true
            case (.commandNotFound(let a), .commandNotFound(let b)):
                a == b
            case (.nonZeroExit(let a1, let a2), .nonZeroExit(let b1, let b2)):
                a1 == b1 && a2 == b2
            case (.invalidOutput(let a), .invalidOutput(let b)):
                a == b
            default:
                false
            }
        }
    }

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.qinfuyao.MoleUI", category: "CLIExecutor")
    private var currentTask: Task<ExecutionResult, Error>?
    private var process: Process?

    // 进度回调
    var onProgress: ((Double, String) -> Void)?
    var onStdout: ((String) -> Void)?
    var onStderr: ((String) -> Void)?

    // MARK: - Public Methods

    /// 执行 Mole 命令
    func executeMole(
        _ subcommand: String,
        options: ExecutionOptions = .default
    ) async throws -> ExecutionResult {
        guard let molePath = Self.findMoleBinary()?.path else {
            throw ExecutionError.commandNotFound("mole")
        }

        guard let moleRoot = Self.findMoleRoot() else {
            throw ExecutionError.commandNotFound("mole root")
        }

        // Set working directory to mole root and execute
        // This ensures SCRIPT_DIR is correctly resolved in mole scripts
        // Quote the path to handle spaces in "Mole UI.app"
        var command = "cd '\(moleRoot.path)' && '\(molePath)' \(subcommand)"
        let forceDryRun = options.dryRun || ProcessInfo.processInfo.arguments.contains("UI_TESTING")
        if forceDryRun {
            command = "cd '\(moleRoot.path)' && MOLE_DRY_RUN=1 DRY_RUN=true '\(molePath)' \(subcommand)"
        }

        return try await execute(
            command: command,
            options: options
        )
    }

    /// 执行任意 shell 命令
    func execute(
        command: String,
        options: ExecutionOptions = .default
    ) async throws -> ExecutionResult {
        let startTime = Date()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = ["-c", command]

                // Set environment variables - Process doesn't inherit by default
                var env = ProcessInfo.processInfo.environment
                env["HOME"] = NSHomeDirectory()
                env["USER"] = NSUserName()
                env["SHELL"] = "/bin/bash"
                proc.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                proc.standardOutput = stdoutPipe
                proc.standardError = options.captureStderr ? stderrPipe : FileHandle.nullDevice

                self.process = proc

                // 启动输出读取
                let stdoutTask = startReadingOutput(
                    pipe: stdoutPipe,
                    isStderr: false,
                    parseProgress: options.parseProgress
                )

                let stderrTask = options.captureStderr
                    ? startReadingOutput(pipe: stderrPipe, isStderr: true, parseProgress: false)
                    : Task { "" }

                // 启动超时检测
                let timeoutTask = startTimeoutMonitor(timeout: options.timeout)

                proc.terminationHandler = { [weak self] process in
                    guard let self else { return }

                    // 取消超时监控
                    timeoutTask?.cancel()

                    // 在 Task 中处理输出，因为 handleReadingOutput 是异步的
                    Task { @MainActor in
                        let stdout = await stdoutTask.value
                        let stderr = await stderrTask.value
                        let duration = Date().timeIntervalSince(startTime)

                        let result = ExecutionResult(
                            stdout: stdout,
                            stderr: stderr,
                            exitCode: process.terminationStatus,
                            duration: duration,
                            wasCancelled: false
                        )

                        if process.terminationStatus != 0 {
                            self.logger.error("Process failed: exit code \(process.terminationStatus)")
                            continuation.resume(
                                throwing: ExecutionError.nonZeroExit(
                                    process.terminationStatus,
                                    stderr: stderr
                                )
                            )
                        } else {
                            self.logger.debug("Process completed successfully in \(duration)s")
                            continuation.resume(returning: result)
                        }

                        // 清理引用以避免泄露
                        if self.process === process {
                            self.process = nil
                        }
                    }
                }

                // 启动进程
                do {
                    try proc.run()
                    logger.debug("Process started: PID \(proc.processIdentifier)")
                } catch {
                    timeoutTask?.cancel()
                    continuation.resume(throwing: error)
                    return
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.cancel()
            }
        }
    }

    /// 取消当前执行
    func cancel() {
        logger.info("Cancelling execution")

        if let proc = process, proc.isRunning {
            // 优雅关闭
            proc.terminate()

            // 等待 1 秒
            Task {
                try? await Task.sleep(for: .seconds(1))
                if proc.isRunning {
                    logger.warning("Process didn't terminate, using SIGKILL")
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }

        currentTask?.cancel()
        process = nil
    }

    // MARK: - Private Methods

    /// 读取输出流
    private func startReadingOutput(
        pipe: Pipe,
        isStderr: Bool,
        parseProgress: Bool
    ) -> Task<String, Never> {
        Task.detached {
            let handle = pipe.fileHandleForReading
            var buffer = Data()
            var output = ""

            while !Task.isCancelled {
                let chunk = handle.availableData
                if chunk.isEmpty { break }

                buffer.append(chunk)

                // 按行处理
                let newline = UInt8(ascii: "\n")
                while let range = buffer.firstIndex(of: newline) {
                    let line = buffer[buffer.startIndex ..< range]
                    buffer.removeSubrange(buffer.startIndex ... range)

                    guard let lineStr = String(data: Data(line), encoding: .utf8) else {
                        continue
                    }

                    output += lineStr + "\n"

                    // 回调
                    await MainActor.run {
                        if isStderr {
                            self.onStderr?(lineStr)
                        } else {
                            self.onStdout?(lineStr)

                            // 解析进度
                            if parseProgress {
                                self.parseProgressLine(lineStr)
                            }
                        }
                    }
                }
            }

            // Flush trailing bytes when output doesn't end with a newline.
            if !buffer.isEmpty, let tail = String(data: buffer, encoding: .utf8) {
                output += tail
                await MainActor.run {
                    if isStderr {
                        self.onStderr?(tail)
                    } else {
                        self.onStdout?(tail)
                        if parseProgress {
                            self.parseProgressLine(tail)
                        }
                    }
                }
            }

            return output
        }
    }

    /// 解析进度信息
    private func parseProgressLine(_ line: String) {
        // 匹配常见的进度格式
        // 例如: "Progress: 45%"
        //      "Scanning... 123/456"
        //      "[=====>    ] 50%"

        // 百分比格式
        if let match = line.range(of: #"(\d+)%"#, options: .regularExpression) {
            let percentStr = line[match].dropLast() // 去掉 %
            if let percent = Double(percentStr) {
                onProgress?(percent / 100.0, line)
                return
            }
        }

        // 分数格式 (123/456)
        if let match = line.range(of: #"(\d+)/(\d+)"#, options: .regularExpression) {
            let parts = line[match].split(separator: "/")
            if parts.count == 2,
               let current = Double(parts[0]),
               let total = Double(parts[1]),
               total > 0
            {
                onProgress?(current / total, line)
                return
            }
        }

        // 进度条格式 [=====>    ]
        if line.contains("["), line.contains("]") {
            if let start = line.firstIndex(of: "["),
               let end = line.firstIndex(of: "]")
            {
                let bar = line[line.index(after: start) ..< end]
                let filled = bar.count(where: { $0 == "=" || $0 == ">" })
                let total = bar.count
                if total > 0 {
                    onProgress?(Double(filled) / Double(total), line)
                    return
                }
            }
        }
    }

    /// 超时监控
    private func startTimeoutMonitor(timeout: TimeInterval?) -> Task<Void, Never>? {
        guard let timeout else { return nil }

        return Task {
            try? await Task.sleep(for: .seconds(timeout))

            if !Task.isCancelled {
                await MainActor.run {
                    self.logger.error("Execution timeout after \(timeout)s")
                    self.cancel()
                }
            }
        }
    }
}

// MARK: - Static Convenience (replaces ShellService)

extension CLIExecutor {
    /// Run a shell command, return stdout.
    @MainActor
    static func run(_ command: String) async throws -> String {
        let executor = CLIExecutor()
        let result = try await executor.execute(command: command, options: .init(
            timeout: 300, captureStderr: true, parseProgress: false, dryRun: false
        ))
        return result.stdout
    }

    /// Run a Mole subcommand.
    @MainActor
    static func runMole(_ subcommand: String, dryRun: Bool = false) async throws -> String {
        let executor = CLIExecutor()
        let result = try await executor.executeMole(subcommand, options: .init(
            timeout: 300, captureStderr: true, parseProgress: false, dryRun: dryRun
        ))
        return result.stdout
    }

    /// Run a Mole script by relative path.
    @MainActor
    static func runScript(_ relativePath: String) async throws -> String {
        guard let root = findMoleRoot() else {
            throw ExecutionError.commandNotFound("mole")
        }
        let scriptPath = root.appendingPathComponent(relativePath).path
        // Set SCRIPT_DIR environment variable to help scripts locate dependencies
        let moleRootPath = root.path
        return try await run("cd '\(moleRootPath)' && SCRIPT_DIR='\(moleRootPath)' bash '\(scriptPath)'")
    }

    /// Locate the Mole executable binary.
    nonisolated static func findMoleBinary() -> URL? {
        guard let root = findMoleRoot() else { return nil }
        let binaryPath = root.appendingPathComponent("mole")
        return FileManager.default.fileExists(atPath: binaryPath.path) ? binaryPath : nil
    }

    /// Locate the Mole root directory (containing `lib/`).
    nonisolated static func findMoleRoot() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("mole") {
            if fm.fileExists(atPath: bundled.appendingPathComponent("lib").path) {
                return bundled
            }
        }
        let candidates = [
            "/usr/local/bin/mole",
            "/opt/homebrew/bin/mole",
            NSHomeDirectory() + "/.config/mole/mole",
        ]
        for path in candidates {
            guard fm.isExecutableFile(atPath: path) else { continue }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            let parent = resolved.deletingLastPathComponent()
            if fm.fileExists(atPath: parent.appendingPathComponent("lib").path) { return parent }
            let libexec = parent.deletingLastPathComponent().appendingPathComponent("libexec")
            if fm.fileExists(atPath: libexec.appendingPathComponent("lib").path) { return libexec }
        }
        return nil
    }
}

// MARK: - 结构化输出解析

extension CLIExecutor {
    /// 解析 JSON 输出
    func executeAndParseJSON<T: Decodable>(
        command: String,
        options: ExecutionOptions = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let result = try await execute(command: command, options: options)

        guard let data = result.stdout.data(using: .utf8) else {
            throw ExecutionError.invalidOutput("无法转换为 UTF-8")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("JSON decode failed: \(error.localizedDescription)")
            logger.error("Raw JSON size: \(data.count) bytes")

            // Log detailed error information
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    logger.error("Key not found: \(key.stringValue) at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    logger.error("Type mismatch: expected \(type) at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    logger.error("Value not found: \(type) at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                case .dataCorrupted(let context):
                    logger.error("Data corrupted at path: \(context.codingPath.map(\.stringValue).joined(separator: "."))")
                    logger.error("Debug description: \(context.debugDescription)")
                @unknown default:
                    logger.error("Unknown decoding error")
                }
            }

            throw ExecutionError.invalidOutput("JSON parsing failed: \(error.localizedDescription)")
        }
    }

    /// 解析表格输出（用于 mole 的输出）
    func parseTableOutput(_ output: String) -> [[String: String]] {
        var results: [[String: String]] = []
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        guard lines.count >= 2 else { return [] }

        // 第一行是表头
        let headers = lines[0]
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { String($0) }

        // 后续行是数据
        for line in lines.dropFirst() {
            let values = line
                .split(separator: " ", omittingEmptySubsequences: true)
                .map { String($0) }

            if values.count == headers.count {
                var row: [String: String] = [:]
                for (header, value) in zip(headers, values) {
                    row[header] = value
                }
                results.append(row)
            }
        }

        return results
    }
}
