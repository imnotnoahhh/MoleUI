import AppKit
import SwiftUI

struct CleanView: View {
    @Environment(CleanModel.self) var service
    @Environment(SafetyController.self) var safety
    @State private var selectedCategories: Set<String> = []
    @State private var showConfirmation = false
    @State private var showError = false
    @State private var currentError: ErrorTranslator.UserFriendlyError?
    @AppStorage("dryRunMode") private var dryRunMode = false
    @AppStorage("confirmBeforeClean") private var confirmBeforeClean = true

    private var totalReclaimable: UInt64 {
        service.scanResults.reduce(0) { $0 + $1.totalBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            if dryRunMode {
                dryRunBanner
            }

            // 进度显示（新增）
            if safety.isExecuting {
                progressBanner
            }

            ScrollView {
                VStack(spacing: 12) {
                    headerCard

                    // 结果显示（新增）
                    if let result = safety.lastResult {
                        resultCard(result)
                    }

                    if let output = service.lastOutput {
                        outputCard(output)
                    }

                    contentArea
                }
                .padding()
            }
        }
        .task {
            await service.scan()
        }
        .alert(dryRunMode ? "Confirm Preview" : "Confirm Clean", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(dryRunMode ? "Preview" : "Clean", role: dryRunMode ? .none : .destructive) {
                Task { await service.cleanSelected(categories: selectedCategories, dryRun: dryRunMode) }
            }
        } message: {
            if dryRunMode {
                Text("Preview \(selectedCategories.count) selected categories? No files will be deleted.")
            } else {
                Text("Clean \(selectedCategories.count) selected categories? This cannot be undone.")
            }
        }
        .sheet(item: Bindable(safety).currentRequest) { request in
            SafetyConfirmationView(request: request)
        }
        .sheet(isPresented: $showError) {
            if let error = currentError {
                ErrorView(
                    error: error,
                    onDismiss: { showError = false },
                    onRetry: nil
                )
            }
        }
    }

    // MARK: - Progress Banner (新增)

    private var progressBanner: some View {
        GroupBox {
            HStack(spacing: 12) {
                ProgressView(value: safety.progress)
                    .frame(width: 200)

                VStack(alignment: .leading, spacing: 2) {
                    Text(safety.progressMessage)
                        .font(.caption)
                    Text("\(Int(safety.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("取消") {
                    safety.cancel()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: - Result Card (新增)

    private func resultCard(_ result: SafetyController.ExecutionResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                        .font(.title3)

                    Text(result.message)
                        .font(.headline)

                    Spacer()

                    Button {
                        safety.lastResult = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if let cleanedSize = result.cleanedSize {
                    HStack {
                        Text("释放空间:")
                            .foregroundStyle(.secondary)
                        Text(MetricsFormatter.humanBytes(cleanedSize))
                            .fontWeight(.semibold)
                    }
                    .font(.callout)
                }

                HStack {
                    Text("耗时:")
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f 秒", result.duration))
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
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

    // MARK: - Header

    private var headerCard: some View {
        GroupBox {
            HStack(spacing: 8) {
                Text("Clean")
                    .fontWeight(.bold)
                Text("Reclaimable")
                    .foregroundStyle(.secondary)
                Text(MetricsFormatter.humanBytes(totalReclaimable))
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)

                Spacer()

                Button {
                    Task { await service.scan() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(service.isScanning)

                Button {
                    if confirmBeforeClean {
                        showConfirmation = true
                    } else {
                        Task { await service.cleanSelected(categories: selectedCategories, dryRun: dryRunMode) }
                    }
                } label: {
                    let text = dryRunMode ? "Preview Selected" : "Clean Selected"
                    let icon = dryRunMode ? "eye" : "trash"
                    Label(text, systemImage: icon)
                }
                .disabled(selectedCategories.isEmpty || service.isScanning || service.cleaningCategory != nil)
            }
            .padding(.vertical, 2)
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

                ScrollView(.vertical, showsIndicators: true) {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .frame(maxHeight: 200)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if service.needsFullDiskAccess {
            GroupBox {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Disk Access Required")
                            .fontWeight(.medium)
                        Text("Some directories (Trash, browser caches) are protected. Grant Full Disk Access to get accurate scan results.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }

        if service.isScanning && service.scanResults.isEmpty {
            GroupBox {
                VStack(spacing: 8) {
                    ProgressView("Scanning...")
                    Text("Calculating directory sizes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        } else if let error = service.errorMessage {
            GroupBox {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }

        if !service.scanResults.isEmpty {
            ForEach(service.scanResults) { result in
                categoryRow(result)
            }
        }
    }

    // MARK: - Category Row

    private func categoryRow(_ result: CleanScanResult) -> some View {
        let isSelected = selectedCategories.contains(result.id)
        let isCleaning = service.cleaningCategory == result.id
        let isCompleted = service.completedCategories.contains(result.id)

        return GroupBox {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { isSelected },
                    set: { on in
                        if on { selectedCategories.insert(result.id) } else { selectedCategories.remove(result.id) }
                    }
                )) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()

                Image(systemName: result.category.icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)

                Text(result.category.name)
                    .frame(width: 130, alignment: .leading)

                Spacer()

                Text("\(result.itemCount) items")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text(MetricsFormatter.humanBytes(result.totalBytes))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .frame(width: 80, alignment: .trailing)

                if isCleaning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text(dryRunMode ? "Preview..." : "Cleaning...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 70)
                } else if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 70)
                } else {
                    Button(dryRunMode ? "Preview" : "Clean") {
                        Task { await service.clean(category: result, dryRun: dryRunMode) }
                    }
                    .disabled(service.cleaningCategory != nil && !isCleaning)
                    .frame(width: 70)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
