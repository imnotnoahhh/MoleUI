import SwiftUI

struct OptimizeView: View {
    @Environment(OptimizeModel.self) var service
    @AppStorage("dryRunMode") private var dryRunMode = false
    @AppStorage("autoSelectSafeItems") private var autoSelectSafeItems = true
    @State private var selectedTasks: Set<String> = []
    @State private var showAdvancedTasks = false

    var body: some View {
        VStack(spacing: 0) {
            if dryRunMode {
                dryRunBanner
            }
            Group {
                if service.isScanning && service.report == nil {
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
        .onChange(of: service.report) { oldValue, newValue in
            // Auto-select safe tasks after loading report
            if autoSelectSafeItems, let report = newValue, selectedTasks.isEmpty {
                selectedTasks = Set(report.optimizations.filter { $0.safe }.map(\.action))
            }
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
                await runSelectedTasks()
            }
        } label: {
            let count = selectedTasks.count
            let prefix = dryRunMode ? "Preview" : "Optimize"
            let text = count > 0 ? "\(prefix) All (\(count))" : "\(prefix) All"
            Label(text, systemImage: dryRunMode ? "eye" : "bolt.fill")
        }
        .disabled(service.runningTask != nil || service.report == nil || selectedTasks.isEmpty)
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Report Content

    private func reportContent(_ report: HealthReport) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                systemInfoHeader(report)

                if let output = service.lastOutput {
                    outputCard(output)
                }

                taskList(report.optimizations)
            }
            .padding()
        }
    }

    // MARK: - Output Card

    private func outputCard(_ output: String) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(dryRunMode ? "Preview Output" : "Execution Output", systemImage: "terminal")
                        .font(.headline)
                    Spacer()
                    Button {
                        service.lastOutput = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(stripAnsiCodes(output))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 200)
            }
            .padding(.vertical, 4)
        }
    }

    private func stripAnsiCodes(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
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
        let safeTasks = tasks.filter { $0.safe }
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
        let isSelected = selectedTasks.contains(task.action)
        let isRunning = service.runningTask == task.action
        let isCompleted = service.completedTasks.contains(task.action)
        let isFailed = service.failedTasks.contains(task.action)

        return HStack(spacing: 10) {
            selectionIndicator(
                task: task,
                isSelected: isSelected,
                isRunning: isRunning,
                isCompleted: isCompleted,
                isFailed: isFailed
            )
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

            if isRunning {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text(dryRunMode ? "Preview..." : "Running...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 80)
            } else if isCompleted || isFailed {
                // Show status only, no button
                EmptyView()
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Selection Indicator

    @ViewBuilder
    private func selectionIndicator(
        task: OptimizationTask,
        isSelected: Bool,
        isRunning: Bool,
        isCompleted: Bool,
        isFailed: Bool
    ) -> some View {
        if isRunning {
            ProgressView()
                .controlSize(.small)
        } else if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if isFailed {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        } else {
            Button {
                if isSelected {
                    selectedTasks.remove(task.action)
                } else {
                    selectedTasks.insert(task.action)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.gray)
            }
            .buttonStyle(.plain)
            .disabled(service.runningTask != nil)
        }
    }

    // MARK: - Actions

    private func runSelectedTasks() async {
        guard let report = service.report else { return }
        let tasksToRun = report.optimizations.filter { selectedTasks.contains($0.action) }
        for task in tasksToRun {
            await service.runTask(task, dryRun: dryRunMode)
        }
        selectedTasks.subtract(tasksToRun.map(\.action))
    }
}
