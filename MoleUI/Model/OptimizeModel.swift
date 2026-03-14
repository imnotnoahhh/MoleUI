import Foundation
import Observation

// MARK: - Data

struct HealthReport: Codable, Sendable, Equatable {
    let memoryUsedGb: Double
    let memoryTotalGb: Double
    let diskUsedGb: Double
    let diskTotalGb: Double
    let diskUsedPercent: Double
    let uptimeDays: Double
    let optimizations: [OptimizationTask]

    enum CodingKeys: String, CodingKey {
        case memoryUsedGb = "memory_used_gb"
        case memoryTotalGb = "memory_total_gb"
        case diskUsedGb = "disk_used_gb"
        case diskTotalGb = "disk_total_gb"
        case diskUsedPercent = "disk_used_percent"
        case uptimeDays = "uptime_days"
        case optimizations
    }
}

struct OptimizationTask: Codable, Sendable, Identifiable, Equatable {
    var id: String {
        action
    }

    let category: String
    let name: String
    let description: String
    let action: String
    let safe: Bool
}

// MARK: - Model

@Observable @MainActor
final class OptimizeModel {
    var report: HealthReport?
    var isScanning: Bool = false
    var isOptimizing: Bool = false
    var currentTask: String? // 当前正在执行的任务名称
    var errorMessage: String?
    var lastOutput: String?
    var executionDuration: TimeInterval? // 执行耗时

    /// Flag to indicate if a privileged optimize operation is in progress.
    /// MetricsModel should pause refreshing when this is true to avoid resource contention.
    var isOptimizingWithPrivileges: Bool = false

    private let decoder: JSONDecoder = .init()

    func loadReport() async {
        isScanning = true
        errorMessage = nil
        defer { isScanning = false }

        do {
            let output = try await CLIExecutor.runScript("lib/check/health_json.sh")
            guard let data = output.data(using: .utf8) else {
                errorMessage = "Failed to read health report output"
                return
            }
            report = try decoder.decode(HealthReport.self, from: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Run all optimization tasks at once (matches mole CLI behavior)
    func runOptimize(dryRun: Bool = false) async {
        isOptimizing = true
        lastOutput = nil
        errorMessage = nil
        currentTask = nil
        executionDuration = nil

        let startTime = Date()

        // Set flag to pause metrics refresh during privileged operations
        if !dryRun {
            isOptimizingWithPrivileges = true
        }

        defer {
            isOptimizing = false
            isOptimizingWithPrivileges = false
            executionDuration = Date().timeIntervalSince(startTime)
            // Don't clear currentTask here - let it show the completion message
        }

        do {
            let executor = CLIExecutor()

            executor.onStdout = { [weak self] line in
                Task { @MainActor in
                    self?.parseOutputLine(line)
                }
            }

            if !dryRun {
                currentTask = "Requesting administrator privileges..."
                guard await SudoHelper.requestSudoAccess(
                    reason: "System optimization requires administrator access."
                ) else {
                    throw NSError(
                        domain: "OptimizeModel",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Administrator privileges required"]
                    )
                }
            }

            currentTask = dryRun ? "Previewing optimization plan..." : "Starting optimization tasks..."

            let result = try await executor.executeMole(
                dryRun ? "optimize --dry-run" : "optimize",
                options: .init(
                    timeout: 300,
                    captureStderr: true,
                    parseProgress: false,
                    dryRun: dryRun
                )
            )
            lastOutput = result.stdout
            currentTask = dryRun ? "Preview completed" : "Optimization completed"
        } catch {
            errorMessage = error.localizedDescription
            currentTask = nil // Clear on error
        }
    }

    /// Parse a single line of output to extract current task name
    private func parseOutputLine(_ line: String) {
        // Match task headers like: "➤ DNS & Spotlight Check"
        // ANSI color codes: ESC[1;34m for blue bold
        if line.contains("➤") || line.contains("→") {
            // Remove ANSI codes and extract task name
            // ESC is \u{001B} in Swift
            let cleaned = line.replacingOccurrences(
                of: "\u{001B}\\[[0-9;]*m",
                with: "",
                options: .regularExpression
            )

            // Extract text after arrow
            if let arrowRange = cleaned.range(of: "[➤→]", options: .regularExpression) {
                let taskName = cleaned[arrowRange.upperBound...].trimmingCharacters(in: .whitespaces)
                if !taskName.isEmpty {
                    currentTask = taskName
                }
            }
        }

        // Append to output
        if lastOutput == nil {
            lastOutput = line + "\n"
        } else {
            lastOutput? += line + "\n"
        }
    }
}
