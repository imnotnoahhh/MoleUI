import SwiftUI

struct OptimizeView: View {
    @Environment(OptimizeModel.self) var service
    @AppStorage("dryRunMode") private var dryRunMode = false
    @State private var showAdvancedTasks = false
    @State private var showRawOutput = false

    var body: some View {
        VStack(spacing: 0) {
            if dryRunMode {
                dryRunBanner
            }
            Group {
                if service.isScanning, service.report == nil {
                    ProgressView("Scanning system health...")
                } else if let error = service.errorMessage, service.report == nil {
                    ContentUnavailableView(
                        "Health Check Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let report = service.report {
                    reportContent(report)
                } else {
                    ContentUnavailableView(
                        "No Report",
                        systemImage: "heart.text.square",
                        description: Text("Click Refresh to scan system health.")
                    )
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                toolbarButtons
            }
        }
        .task {
            await service.loadReport()
        }
    }

    private var dryRunBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.caption2)
            Text("DRY RUN")
                .font(.system(size: 11, weight: .semibold))
            Text("— preview only, no files will be deleted")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarButtons: some View {
        Button {
            Task { await service.loadReport() }
        } label: {
            Label("Scan", systemImage: "arrow.clockwise")
        }
        .disabled(service.isScanning)

        Button {
            Task {
                await service.runOptimize(dryRun: dryRunMode)
            }
        } label: {
            let prefix = dryRunMode ? "Preview" : "Optimize"
            Label("\(prefix) All", systemImage: dryRunMode ? "eye" : "bolt.fill")
        }
        .disabled(service.isOptimizing || service.report == nil)
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Report Content

    private func reportContent(_ report: HealthReport) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                systemInfoHeader(report)

                taskList(report.optimizations)

                // Show optimizing status
                if service.isOptimizing {
                    optimizingStatusCard
                }

                // Show result summary after completion
                if let output = service.lastOutput, !service.isOptimizing {
                    resultSummaryCard(output)
                }
            }
            .padding()
        }
    }

    // MARK: - Optimizing Status Card

    private var optimizingStatusCard: some View {
        GroupBox {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)

                VStack(alignment: .leading, spacing: 4) {
                    Text(dryRunMode ? "Previewing..." : "Optimizing...")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let currentTask = service.currentTask {
                        Text(currentTask)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Starting optimization tasks...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Output Card

    private func resultSummaryCard(_ output: String) -> some View {
        let summary = parseOutputSummary(output)

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dryRunMode ? "Preview Completed" : "Optimization Completed")
                            .font(.headline)
                        if let duration = service.executionDuration {
                            Text(String(format: "Completed in %.1f seconds", duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        service.lastOutput = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                // Statistics
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(summary.completedCount)")
                            .font(.title2.bold())
                            .foregroundStyle(.green)
                        Text("Tasks Completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if summary.skippedCount > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(summary.skippedCount)")
                                .font(.title2.bold())
                                .foregroundStyle(.orange)
                            Text("Tasks Skipped")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                }

                // Skipped tasks details
                if !summary.skippedTasks.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Skipped Tasks", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)

                        ForEach(summary.skippedTasks, id: \.self) { task in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.orange)
                                    .padding(.top, 6)
                                Text(task)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // System status
                if !summary.systemStatus.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("System Status", systemImage: "info.circle")
                            .font(.subheadline.bold())

                        ForEach(summary.systemStatus.prefix(3), id: \.self) { status in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                                    .padding(.top, 4)
                                Text(status)
                                    .font(.caption)
                            }
                        }
                    }
                }

                // Warnings
                if !summary.warnings.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Suggestions", systemImage: "lightbulb")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)

                        ForEach(summary.warnings, id: \.self) { warning in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                    .padding(.top, 4)
                                Text(warning)
                                    .font(.caption)
                            }
                        }
                    }
                }

                // Show raw output button
                if !dryRunMode {
                    Divider()
                    Button {
                        showRawOutput = true
                    } label: {
                        Label("View Detailed Log", systemImage: "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showRawOutput) {
            rawOutputSheet(output)
        }
    }

    private func rawOutputSheet(_ output: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Detailed Execution Log")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    showRawOutput = false
                }
            }
            .padding()

            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(stripAnsiCodes(output))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 700, height: 500)
    }

    private func stripAnsiCodes(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }

    // MARK: - Output Parsing

    struct OutputSummary {
        var duration: String?
        var completedCount: Int = 0
        var skippedCount: Int = 0
        var skippedTasks: [String] = []
        var systemStatus: [String] = []
        var warnings: [String] = []
    }

    private func parseOutputSummary(_ output: String) -> OutputSummary {
        var summary = OutputSummary()
        let cleaned = stripAnsiCodes(output)
        let lines = cleaned.components(separatedBy: .newlines)

        var completedTasks = 0
        var skippedTasks = 0
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Count completed tasks (✓)
            if trimmed.contains("✓"), !trimmed.contains("System"), !trimmed.contains("Security") {
                completedTasks += 1
            }

            // Count skipped tasks (◎)
            if trimmed.contains("◎") {
                skippedTasks += 1
                // Extract skip reason
                if trimmed.contains("Close these apps") {
                    summary.skippedTasks.append("Database Optimization: Close Safari first")
                } else if trimmed.contains("Skipped font cache") {
                    summary.skippedTasks.append("Font Cache Rebuild: Close browsers first")
                } else if trimmed.contains("available") {
                    let parts = trimmed.components(separatedBy: "◎")
                    if parts.count > 1 {
                        summary.warnings.append(parts[1].trimmingCharacters(in: .whitespaces))
                    }
                }
            }

            // Extract system status
            if trimmed.hasPrefix("➤ System Health") {
                currentSection = "health"
            } else if trimmed.hasPrefix("➤ Security Status") {
                currentSection = "security"
            } else if trimmed.hasPrefix("➤") {
                currentSection = ""
            }

            if currentSection == "health", trimmed.contains("✓") {
                let parts = trimmed.components(separatedBy: "✓")
                if parts.count > 1 {
                    let status = parts[1].trimmingCharacters(in: .whitespaces)
                    if !status.isEmpty, !status.contains("System Health") {
                        summary.systemStatus.append(status)
                    }
                }
            }

            // Extract final summary
            if trimmed.contains("Applied"), trimmed.contains("optimizations") {
                if let match = trimmed.range(of: "Applied ([0-9]+)", options: .regularExpression) {
                    let numStr = trimmed[match].replacingOccurrences(of: "Applied ", with: "")
                    if let num = Int(numStr) {
                        summary.completedCount = num
                    }
                }
            }
        }

        // If no final summary found, use counted tasks
        if summary.completedCount == 0 {
            summary.completedCount = completedTasks
        }
        summary.skippedCount = skippedTasks

        // Estimate duration (rough calculation based on task count)
        let estimatedSeconds = summary.completedCount * 2
        if estimatedSeconds > 0 {
            summary.duration = "\(estimatedSeconds) seconds"
        }

        return summary
    }

    // MARK: - System Info Header

    private func systemInfoHeader(_ report: HealthReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("System Health", systemImage: "heart.text.square")
                        .font(.headline)
                }
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memory").font(.headline)
                        Text(String(
                            format: "%.1f / %.1f GB",
                            report.memoryUsedGb,
                            report.memoryTotalGb
                        ))
                        .font(.system(.caption, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Disk").font(.headline)
                        Text(String(
                            format: "%.1f / %.1f GB (%.0f%%)",
                            report.diskUsedGb,
                            report.diskTotalGb,
                            report.diskUsedPercent
                        ))
                        .font(.system(.caption, design: .monospaced))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Uptime").font(.headline)
                        Text(String(format: "%.1f days", report.uptimeDays))
                            .font(.system(.caption, design: .monospaced))
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Task List

    private func taskList(_ tasks: [OptimizationTask]) -> some View {
        let safeTasks = tasks.filter(\.safe)
        let advancedTasks = tasks.filter { !$0.safe }

        return GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                Label("Optimizations", systemImage: "bolt.fill")
                    .font(.headline)
                    .padding(.bottom, 8)

                // Safe tasks (always visible)
                ForEach(safeTasks) { task in
                    taskRow(task)
                    if task.id != safeTasks.last?.id || !advancedTasks.isEmpty {
                        Divider()
                    }
                }

                // Advanced tasks (collapsible)
                if !advancedTasks.isEmpty {
                    DisclosureGroup(
                        isExpanded: $showAdvancedTasks,
                        content: {
                            VStack(spacing: 0) {
                                ForEach(advancedTasks) { task in
                                    taskRow(task)
                                    if task.id != advancedTasks.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.top, 8)
                        },
                        label: {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("Advanced Tasks")
                                    .fontWeight(.medium)
                                Text("(\(advancedTasks.count) tasks)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    )
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Task Row

    private func taskRow(_ task: OptimizationTask) -> some View {
        HStack(spacing: 10) {
            // Icon indicator (read-only, no checkbox)
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(task.safe ? .green : .orange)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(task.name)
                        .fontWeight(.bold)
                    if task.safe {
                        Text("safe")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.green.opacity(0.1), in: Capsule())
                    }
                }
                Text(task.description)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}
