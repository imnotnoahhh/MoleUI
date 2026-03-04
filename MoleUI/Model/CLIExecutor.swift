import Foundation
import os.log

/// 增强版 CLI 执行器：支持超时、进度、取消、错误处理
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

    enum ExecutionError: LocalizedError {
        case timeout
        case cancelled
        case commandNotFound(String)
        case nonZeroExit(Int32, stderr: String)
        case invalidOutput(String)

        var errorDescription: String? {
            switch self {
            case .timeout:
                return "命令执行超时"
            case .cancelled:
                return "操作已取消"
            case let .commandNotFound(cmd):
                return "找不到命令: \(cmd)"
            case let .nonZeroExit(code, stderr):
                return "命令执行失败 (退出码: \(code))\n\(stderr)"
            case let .invalidOutput(msg):
                return "输出解析失败: \(msg)"
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
        guard let molePath = findMoleBinary() else {
            throw ExecutionError.commandNotFound("mole")
        }

        var command = "\(molePath) \(subcommand)"
        if options.dryRun {
            command = "MOLE_DRY_RUN=1 DRY_RUN=true \(command)"
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

                // 启动进程
                do {
                    try proc.run()
                    logger.debug("Process started: PID \(proc.processIdentifier)")
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // 等待进程结束
                proc.waitUntilExit()

                // 取消超时监控
                timeoutTask?.cancel()

                // 收集输出
                Task {
                    let stdout = await stdoutTask.value
                    let stderr = await stderrTask.value
                    let duration = Date().timeIntervalSince(startTime)

                    let result = ExecutionResult(
                        stdout: stdout,
                        stderr: stderr,
                        exitCode: proc.terminationStatus,
                        duration: duration,
                        wasCancelled: false
                    )

                    if proc.terminationStatus != 0 {
                        self.logger.error("Process failed: exit code \(proc.terminationStatus)")
                        continuation.resume(
                            throwing: ExecutionError.nonZeroExit(
                                proc.terminationStatus,
                                stderr: stderr
                            )
                        )
                    } else {
                        self.logger.debug("Process completed successfully in \(duration)s")
                        continuation.resume(returning: result)
                    }
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

    private func findMoleBinary() -> String? {
        let fm = FileManager.default

        // 检查 bundle 内
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("mole/mole").path,
            fm.isExecutableFile(atPath: bundled)
        {
            return bundled
        }

        // 检查系统路径
        let candidates = [
            "/usr/local/bin/mole",
            "/opt/homebrew/bin/mole",
            NSHomeDirectory() + "/.config/mole/mole",
        ]

        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

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
                let filled = bar.filter { $0 == "=" || $0 == ">" }.count
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
        guard let timeout = timeout else { return nil }

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
        return try await run("bash '\(scriptPath)'")
    }

    /// Locate the Mole root directory (containing `lib/`).
    static func findMoleRoot() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("mole") {
            if fm.fileExists(atPath: bundled.appendingPathComponent("lib").path) {
                return bundled
            }
        }
        let candidates = ["/usr/local/bin/mole", "/opt/homebrew/bin/mole",
                          NSHomeDirectory() + "/.config/mole/mole"]
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
                case let .keyNotFound(key, context):
                    logger.error("Key not found: \(key.stringValue) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case let .typeMismatch(type, context):
                    logger.error("Type mismatch: expected \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case let .valueNotFound(type, context):
                    logger.error("Value not found: \(type) at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case let .dataCorrupted(context):
                    logger.error("Data corrupted at path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                    logger.error("Debug description: \(context.debugDescription)")
                @unknown default:
                    logger.error("Unknown decoding error")
                }
            }

            throw ExecutionError.invalidOutput("JSON 解析失败: \(error.localizedDescription)")
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
