import AppKit
import SwiftUI

struct PurgeView: View {
    @Environment(PurgeModel.self) var service
    @State private var showPathsEditor = false

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
        .sheet(isPresented: $showPathsEditor) {
            PurgePathsEditorView()
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
                    showPathsEditor = true
                } label: {
                    Label("Edit Paths", systemImage: "slider.horizontal.3")
                }

                Button {
                    Task { await service.scan() }
                } label: {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(service.isScanning)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if service.isScanning, service.targets.isEmpty {
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

        if service.targets.isEmpty, !service.isScanning {
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
        let isCleaning = service.cleaningTarget == target.id
        let isCompleted = service.completedTargets.contains(target.id)

        return GroupBox {
            HStack(spacing: 10) {
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
        case "node_modules": "shippingbox"
        case "target", "build", "dist", ".output", "zig-out", "obj", ".build":
            "hammer"
        case "venv", ".venv", ".tox", ".nox":
            "terminal"
        case "DerivedData": "xcode"
        case "Pods": "puzzlepiece"
        case ".gradle": "gearshape.2"
        case "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache":
            "memorychip"
        case ".next", ".nuxt", ".angular", ".svelte-kit", ".astro":
            "globe"
        case "coverage": "chart.bar"
        default: "folder"
        }
    }

    // MARK: - Paths

    private var scanPathsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("Scan Paths", systemImage: "folder.badge.gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Default paths plus ~/Library/Application Support/MoleUI/purge_paths are used.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Purge Paths Editor

struct PurgePathsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pathsText: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Scan Paths")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    savePaths()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Editor
            VStack(alignment: .leading, spacing: 8) {
                Text("Add one path per line. Use ~ for home directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $pathsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 300)
                    .border(Color.secondary.opacity(0.2))

                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Text("Default paths: ~/www, ~/dev, ~/Projects, ~/GitHub, ~/Code, ~/Workspace, ~/Repos, ~/Development")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .onAppear {
            loadPaths()
        }
    }

    private func loadPaths() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        let configPath = appSupport.appendingPathComponent("MoleUI/purge_paths")
        pathsText = (try? String(contentsOf: configPath, encoding: .utf8)) ?? ""
    }

    private func savePaths() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            errorMessage = "Failed to access Application Support directory"
            return
        }

        let moleUIDir = appSupport.appendingPathComponent("MoleUI")
        let configPath = moleUIDir.appendingPathComponent("purge_paths")

        do {
            try FileManager.default.createDirectory(at: moleUIDir, withIntermediateDirectories: true)
            try pathsText.write(to: configPath, atomically: true, encoding: .utf8)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
