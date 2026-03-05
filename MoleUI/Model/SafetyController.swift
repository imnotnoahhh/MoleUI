import Foundation
import Observation
import SwiftUI

/// Safety control: pre-execution confirmation, preview mode, dry-run, statistics
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

        // Listen to progress
        executor.onProgress = { [weak self] progress, message in
            self?.progress = progress
            self?.progressMessage = message
        }
    }

    convenience init() {
        self.init(executor: CLIExecutor())
    }

    // MARK: - Public Methods

    /// Execute clean operation (with confirmation)
    func executeClean(
        target: String,
        dryRun: Bool = false
    ) async throws {
        // 1. Execute dry-run first to get preview
        let preview = try await getCleanPreview(target: target)

        // 2. If real execution, need user confirmation
        if !dryRun {
            try await requestConfirmation(
                title: "Confirm Clean",
                message: "About to clean \(target), total \(preview.formattedSize)",
                destructive: true,
                preview: preview
            ) {
                // 3. Execute real clean
                try await self.performClean(target: target, dryRun: false)
            }
        } else {
            // Dry-run mode, show preview directly
            lastResult = ExecutionResult(
                success: true,
                message: "Preview mode: will clean \(preview.formattedSize)",
                details: preview.files.map(\.path).joined(separator: "\n"),
                cleanedSize: preview.totalSize,
                duration: 0
            )
        }
    }

    /// Execute optimize operation (with confirmation)
    func executeOptimize(
        target: String
    ) async throws {
        try await requestConfirmation(
            title: "Confirm Optimize",
            message: "About to execute \(target) optimization",
            destructive: false,
            preview: nil
        ) {
            try await self.performOptimize(target: target)
        }
    }

    /// Cancel current operation
    func cancel() {
        executor.cancel()
        isExecuting = false
        progress = 0
        progressMessage = ""
    }

    // MARK: - Private Methods

    /// Get clean preview
    private func getCleanPreview(target: String) async throws -> CleanPreview {
        let startTime = Date()

        let result = try await executor.executeMole(
            "clean --dry-run",
            options: CLIExecutor.ExecutionOptions(
                timeout: 60,
                captureStderr: true,
                parseProgress: false,
                dryRun: false
            )
        )

        // Parse output
        let files = parseCleanOutput(result.stdout)
        let totalSize = files.reduce(0) { $0 + $1.size }
        let duration = Date().timeIntervalSince(startTime)

        return CleanPreview(
            target: target,
            files: files,
            totalSize: totalSize,
            estimatedTime: duration * 2 // Estimate real execution time is 2x dry-run
        )
    }

    /// Execute real clean
    private func performClean(target: String, dryRun: Bool) async throws {
        isExecuting = true
        progress = 0
        progressMessage = "Cleaning..."

        defer {
            isExecuting = false
        }

        let startTime = Date()

        let result = try await executor.executeMole(
            "clean",
            options: CLIExecutor.ExecutionOptions(
                timeout: 600, // 10 minutes
                captureStderr: true,
                parseProgress: true,
                dryRun: false
            )
        )

        let duration = Date().timeIntervalSince(startTime)

        // Parse clean result
        let cleanedSize = parseCleanedSize(result.stdout)

        lastResult = ExecutionResult(
            success: true,
            message: "Clean completed",
            details: result.stdout,
            cleanedSize: cleanedSize,
            duration: duration
        )
    }

    /// Execute optimize
    private func performOptimize(target: String) async throws {
        isExecuting = true
        progress = 0
        progressMessage = "Optimizing..."

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
            message: "Optimize completed",
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

            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    request.onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(request.destructive ? "Confirm Delete" : "Confirm") {
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
