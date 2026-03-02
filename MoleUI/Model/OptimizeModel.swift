import Foundation
import Observation

// MARK: - Data

struct HealthReport: Codable, Sendable {
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

struct OptimizationTask: Codable, Sendable, Identifiable {
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
    var runningTask: String?
    var completedTasks: Set<String> = []
    var failedTasks: Set<String> = []
    var errorMessage: String?
    var lastOutput: String?

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

    func runTask(_ task: OptimizationTask, dryRun: Bool = false) async {
        runningTask = task.action
        lastOutput = nil

        do {
            let command = dryRun ? "optimize --dry-run \(task.action)" : "optimize \(task.action)"
            let output = try await CLIExecutor.runMole(command, dryRun: dryRun)
            lastOutput = output
            completedTasks.insert(task.action)
        } catch {
            failedTasks.insert(task.action)
            errorMessage = error.localizedDescription
        }
        runningTask = nil
    }

    func runAllSafe(dryRun: Bool = false) async {
        guard let tasks = report?.optimizations.filter({ $0.safe }) else { return }
        for task in tasks {
            if failedTasks.contains(task.action) || completedTasks.contains(task.action) {
                continue
            }
            await runTask(task, dryRun: dryRun)
        }
    }
}
