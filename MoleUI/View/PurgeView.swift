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
        MoleHeroPanel(
            eyebrow: "Projects",
            title: "Purge",
            subtitle: "Clear build artifacts and dependency caches from project directories without turning every repo into a guessing game.",
            symbol: "folder.badge.minus"
        ) {
            VStack(alignment: .trailing, spacing: 10) {
                MoleMetricBadge(
                    title: "Reclaimable",
                    value: MetricsFormatter.humanBytes(totalReclaimable),
                    systemImage: "shippingbox.circle.fill",
                    tint: .orange
                )

                HStack(spacing: 10) {
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
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if service.isScanning, service.targets.isEmpty {
            GroupBox {
                VStack(spacing: 8) {
                    ProgressView("Scanning project directories...")
                        .controlSize(.regular)
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
                        .frame(width: 16, height: 16)
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
        GroupBox("Scan Paths") {
            VStack(alignment: .leading, spacing: 6) {
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
        VStack(spacing: 18) {
            MoleHeroPanel(
                eyebrow: "Projects",
                title: "Edit Scan Paths",
                subtitle: "One path per line. Mole UI merges these with the built-in defaults before each purge scan.",
                symbol: "slider.horizontal.3"
            ) {
                Button("Done") {
                    savePaths()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Add one path per line. Use ~ for home directory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $pathsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 300)
                    .padding(10)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    )

                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Text("Default paths: ~/www, ~/dev, ~/Projects, ~/GitHub, ~/Code, ~/Workspace, ~/Repos, ~/Development")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.78), MoleTheme.parchment.opacity(0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
        }
        .padding(18)
        .frame(width: 680, height: 560)
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
