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
            // Find mole binary
            guard let moleBinary = CLIExecutor.findMoleBinary() else {
                throw NSError(
                    domain: "OptimizeModel",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot find mole executable"]
                )
            }

            if dryRun {
                // Dry run doesn't need sudo, can show real-time output
                let executor = CLIExecutor()

                // Set up real-time output callback to parse current task
                executor.onStdout = { [weak self] line in
                    Task { @MainActor in
                        self?.parseOutputLine(line)
                    }
                }

                let result = try await executor.executeMole(
                    "optimize --dry-run",
                    options: .init(timeout: 300, captureStderr: true, parseProgress: false, dryRun: true)
                )
                lastOutput = result.stdout
            } else {
                // Normal mode: use osascript (no real-time output, but only asks password once)
                currentTask = "Requesting administrator privileges..."
                let command = "'\(moleBinary.path)' optimize"
                let output = try await SudoHelper.runWithAdmin(command)

                // Parse the complete output to show the last task
                parseCompleteOutput(output)
                lastOutput = output
            }
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

    /// Parse complete output (for sudo execution which returns all at once)
    private func parseCompleteOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)

        // Find all task names and show progress through them
        for line in lines {
            if line.contains("➤") || line.contains("→") {
                let cleaned = line.replacingOccurrences(
                    of: "\u{001B}\\[[0-9;]*m",
                    with: "",
                    options: .regularExpression
                )

                if let arrowRange = cleaned.range(of: "[➤→]", options: .regularExpression) {
                    let taskName = cleaned[arrowRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !taskName.isEmpty {
                        // Update to show the last task (will show "Completed" feeling)
                        currentTask = taskName
                    }
                }
            }
        }

        // If we found tasks, show completion message
        if currentTask != nil {
            currentTask = "Optimization completed"
        }
    }
}
