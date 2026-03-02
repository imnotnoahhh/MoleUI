import AppKit
import SwiftUI

struct PurgeView: View {
    @Environment(PurgeModel.self) var service
    @State private var selectedTargets: Set<String> = []
    @State private var showConfirmation = false

    private var totalReclaimable: UInt64 {
        service.targets.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCard
                contentArea
            }
            .padding()
        }
        .task {
            await service.scan()
        }
        .alert("Confirm Purge", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Purge", role: .destructive) {
                Task { await service.deleteSelected(ids: selectedTargets) }
            }
        } message: {
            Text("Delete \(selectedTargets.count) build artifact directories? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        GroupBox {
            HStack(spacing: 8) {
                Text("Purge")
                    .fontWeight(.bold)
                Text("Reclaimable")
                    .foregroundStyle(.secondary)
                Text(MetricsFormatter.humanBytes(totalReclaimable))
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)

                Spacer()

                Button {
                    openPurgePathsConfig()
                } label: {
                    Label("Edit Paths", systemImage: "slider.horizontal.3")
                }

                Button {
                    selectedTargets = Set(service.targets.filter { !$0.isRecent }.map(\.id))
                } label: {
                    Label("Select Stale", systemImage: "clock.badge.checkmark")
                }
                .disabled(service.isScanning || service.targets.isEmpty)

                Button {
                    Task { await service.scan() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(service.isScanning)

                Button {
                    showConfirmation = true
                } label: {
                    Label("Purge Selected", systemImage: "trash")
                }
                .disabled(selectedTargets.isEmpty || service.isScanning || service.cleaningTarget != nil)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if service.isScanning && service.targets.isEmpty {
            GroupBox {
                VStack(spacing: 8) {
                    ProgressView("Scanning project directories...")
                    Text("Looking for build artifacts")
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

        if service.targets.isEmpty && !service.isScanning {
            GroupBox {
                Text("No build artifacts found in scan paths.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }

        scanPathsCard

        if !service.targets.isEmpty {
            ForEach(service.targets) { target in
                targetRow(target)
            }
        }
    }

    // MARK: - Target Row

    private func targetRow(_ target: PurgeTarget) -> some View {
        let isSelected = selectedTargets.contains(target.id)
        let isCleaning = service.cleaningTarget == target.id
        let isCompleted = service.completedTargets.contains(target.id)

        return GroupBox {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { isSelected },
                    set: { on in
                        if on { selectedTargets.insert(target.id) } else { selectedTargets.remove(target.id) }
                    }
                )) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()

                Image(systemName: iconForArtifact(target.artifactName))
                    .frame(width: 20)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(target.projectName)
                        .fontWeight(.medium)
                    Text(target.artifactName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 160, alignment: .leading)

                Spacer()

                if target.isRecent {
                    Text("< 7d")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Text("\(target.ageDays)d ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(MetricsFormatter.humanBytes(target.sizeBytes))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .frame(width: 80, alignment: .trailing)

                if isCleaning {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60)
                } else if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 60)
                } else {
                    Button("Purge") {
                        Task { await service.deleteTarget(target) }
                    }
                    .disabled(service.cleaningTarget != nil)
                    .frame(width: 60)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func iconForArtifact(_ name: String) -> String {
        switch name {
        case "node_modules": return "shippingbox"
        case "target", "build", "dist", ".output", "zig-out", "obj", ".build":
            return "hammer"
        case "venv", ".venv", ".tox", ".nox":
            return "terminal"
        case "DerivedData": return "xcode"
        case "Pods": return "puzzlepiece"
        case ".gradle": return "gearshape.2"
        case "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache":
            return "memorychip"
        case ".next", ".nuxt", ".angular", ".svelte-kit", ".astro":
            return "globe"
        case "coverage": return "chart.bar"
        default: return "folder"
        }
    }

    // MARK: - Paths

    private var scanPathsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("Scan Paths", systemImage: "folder.badge.gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Default paths plus ~/.config/mole/purge_paths are used, same as CLI.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private func openPurgePathsConfig() {
        let configDir = NSHomeDirectory() + "/.config/mole"
        let configPath = configDir + "/purge_paths"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: configPath) {
            try? "".write(toFile: configPath, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: configPath))
    }
}
