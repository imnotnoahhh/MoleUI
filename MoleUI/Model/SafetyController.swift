import Foundation
import Observation
import SwiftUI

/// 安全控制：执行前确认、预览模式、dry-run、统计
@Observable @MainActor
final class SafetyController {
    // MARK: - Types

    struct CleanPreview {
        let target: String
        let files: [FileItem]
        let totalSize: UInt64
        let estimatedTime: TimeInterval

        struct FileItem {
            let path: String
            let size: UInt64
            let isDirectory: Bool
        }

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
        }
    }

    struct ConfirmationRequest: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let destructive: Bool
        let preview: CleanPreview?
        let onConfirm: () async throws -> Void
        let onCancel: () -> Void
    }

    // MARK: - Published Properties

    var currentRequest: ConfirmationRequest?
    var isExecuting = false
    var progress: Double = 0
    var progressMessage: String = ""
    var lastResult: ExecutionResult?

    struct ExecutionResult {
        let success: Bool
        let message: String
        let details: String?
        let cleanedSize: UInt64?
        let duration: TimeInterval
    }

    // MARK: - Dependencies

    private let executor: CLIExecutor

    init(executor: CLIExecutor) {
        self.executor = executor

        // 监听进度
        executor.onProgress = { [weak self] progress, message in
            self?.progress = progress
            self?.progressMessage = message
        }
    }

    convenience init() {
        self.init(executor: CLIExecutor())
    }

    // MARK: - Public Methods

    /// 执行清理操作（带确认）
    func executeClean(
        target: String,
        dryRun: Bool = false
    ) async throws {
        // 1. 先执行 dry-run 获取预览
        let preview = try await getCleanPreview(target: target)

        // 2. 如果是真实执行，需要用户确认
        if !dryRun {
            try await requestConfirmation(
                title: "确认清理",
                message: "即将清理 \(target)，共 \(preview.formattedSize)",
                destructive: true,
                preview: preview
            ) {
                // 3. 执行真实清理
                try await self.performClean(target: target, dryRun: false)
            }
        } else {
            // Dry-run 模式，直接显示预览
            lastResult = ExecutionResult(
                success: true,
                message: "预览模式：将清理 \(preview.formattedSize)",
                details: preview.files.map(\.path).joined(separator: "\n"),
                cleanedSize: preview.totalSize,
                duration: 0
            )
        }
    }

    /// 执行优化操作（带确认）
    func executeOptimize(
        target: String
    ) async throws {
        try await requestConfirmation(
            title: "确认优化",
            message: "即将执行 \(target) 优化",
            destructive: false,
            preview: nil
        ) {
            try await self.performOptimize(target: target)
        }
    }

    /// 取消当前操作
    func cancel() {
        executor.cancel()
        isExecuting = false
        progress = 0
        progressMessage = ""
    }

    // MARK: - Private Methods

    /// 获取清理预览
    private func getCleanPreview(target: String) async throws -> CleanPreview {
        let startTime = Date()

        let result = try await executor.executeMole(
            "clean \(target) --dry-run --json",
            options: CLIExecutor.ExecutionOptions(
                timeout: 60,
                captureStderr: true,
                parseProgress: false,
                dryRun: true
            )
        )

        // 解析输出
        let files = parseCleanOutput(result.stdout)
        let totalSize = files.reduce(0) { $0 + $1.size }
        let duration = Date().timeIntervalSince(startTime)

        return CleanPreview(
            target: target,
            files: files,
            totalSize: totalSize,
            estimatedTime: duration * 2 // 估计实际执行时间是 dry-run 的 2 倍
        )
    }

    /// 执行真实清理
    private func performClean(target: String, dryRun: Bool) async throws {
        isExecuting = true
        progress = 0
        progressMessage = "正在清理..."

        defer {
            isExecuting = false
        }

        let startTime = Date()

        let result = try await executor.executeMole(
            "clean \(target)",
            options: CLIExecutor.ExecutionOptions(
                timeout: 600, // 10 分钟
                captureStderr: true,
                parseProgress: true,
                dryRun: dryRun
            )
        )

        let duration = Date().timeIntervalSince(startTime)

        // 解析清理结果
        let cleanedSize = parseCleanedSize(result.stdout)

        lastResult = ExecutionResult(
            success: true,
            message: "清理完成",
            details: result.stdout,
            cleanedSize: cleanedSize,
            duration: duration
        )
    }

    /// 执行优化
    private func performOptimize(target: String) async throws {
        isExecuting = true
        progress = 0
        progressMessage = "正在优化..."

        defer {
            isExecuting = false
        }

        let startTime = Date()

        let result = try await executor.executeMole(
            "optimize \(target)",
            options: CLIExecutor.ExecutionOptions(
                timeout: 600,
                captureStderr: true,
                parseProgress: true,
                dryRun: false
            )
        )

        let duration = Date().timeIntervalSince(startTime)

        lastResult = ExecutionResult(
            success: true,
            message: "优化完成",
            details: result.stdout,
            cleanedSize: nil,
            duration: duration
        )
    }

    /// 请求用户确认
    private func requestConfirmation(
        title: String,
        message: String,
        destructive: Bool,
        preview: CleanPreview?,
        onConfirm: @escaping () async throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            currentRequest = ConfirmationRequest(
                title: title,
                message: message,
                destructive: destructive,
                preview: preview,
                onConfirm: {
                    self.currentRequest = nil
                    do {
                        try await onConfirm()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                },
                onCancel: {
                    self.currentRequest = nil
                    continuation.resume(throwing: CancellationError())
                }
            )
        }
    }

    // MARK: - Output Parsing

    /// 解析清理输出
    private func parseCleanOutput(_ output: String) -> [CleanPreview.FileItem] {
        var files: [CleanPreview.FileItem] = []

        // 匹配格式: "  - /path/to/file (1.2 MB)"
        let pattern = #"^\s*-\s+(.+?)\s+\((.+?)\)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines)

        let nsString = output as NSString
        let matches = regex?.matches(
            in: output,
            range: NSRange(location: 0, length: nsString.length)
        ) ?? []

        for match in matches where match.numberOfRanges >= 3 {
            let pathRange = match.range(at: 1)
            let sizeRange = match.range(at: 2)

            let path = nsString.substring(with: pathRange)
            let sizeStr = nsString.substring(with: sizeRange)

            let size = parseSizeString(sizeStr)

            files.append(CleanPreview.FileItem(
                path: path,
                size: size,
                isDirectory: path.hasSuffix("/")
            ))
        }

        return files
    }

    /// 解析已清理的大小
    private func parseCleanedSize(_ output: String) -> UInt64? {
        // 匹配格式: "Cleaned: 1.2 GB"
        let pattern = #"Cleaned:\s*(.+)"#
        let regex = try? NSRegularExpression(pattern: pattern)

        let nsString = output as NSString
        if let match = regex?.firstMatch(
            in: output,
            range: NSRange(location: 0, length: nsString.length)
        ) {
            if match.numberOfRanges >= 2 {
                let sizeStr = nsString.substring(with: match.range(at: 1))
                return parseSizeString(sizeStr)
            }
        }

        return nil
    }

    /// 解析大小字符串 (例如: "1.2 GB", "500 MB")
    private func parseSizeString(_ str: String) -> UInt64 {
        let components = str.split(separator: " ")
        guard components.count >= 2,
              let value = Double(components[0])
        else {
            return 0
        }

        let unit = components[1].uppercased()
        let multiplier: Double = switch unit {
        case "B", "BYTES": 1
        case "KB": 1024
        case "MB": 1024 * 1024
        case "GB": 1024 * 1024 * 1024
        case "TB": 1024 * 1024 * 1024 * 1024
        default: 1
        }

        return UInt64(value * multiplier)
    }
}

// MARK: - SwiftUI View

struct SafetyConfirmationView: View {
    let request: SafetyController.ConfirmationRequest

    var body: some View {
        VStack(spacing: 20) {
            // 标题
            Text(request.title)
                .font(.headline)

            // 消息
            Text(request.message)
                .font(.body)

            // 预览
            if let preview = request.preview {
                PreviewSection(preview: preview)
            }

            // 按钮
            HStack(spacing: 12) {
                Button("取消") {
                    request.onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(request.destructive ? "确认删除" : "确认") {
                    Task {
                        try? await request.onConfirm()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(request.destructive ? .red : .blue)
            }
        }
        .padding()
        .frame(width: 500)
    }
}

struct PreviewSection: View {
    let preview: SafetyController.CleanPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("预览", systemImage: "eye")
                    .font(.subheadline)
                Spacer()
                Text(preview.formattedSize)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(preview.files.prefix(10), id: \.path) { file in
                        HStack {
                            Image(systemName: file.isDirectory ? "folder" : "doc")
                                .foregroundColor(.secondary)
                            Text(file.path)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(
                                fromByteCount: Int64(file.size),
                                countStyle: .file
                            ))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }

                    if preview.files.count > 10 {
                        Text("... 还有 \(preview.files.count - 10) 个文件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 150)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}
