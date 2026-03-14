import AppKit
import SwiftUI

struct DiskAnalyzerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(DiskModel.self) var scanner
    @State private var hasInitialScan = false
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false
    @State private var entryToDelete: DirEntry?
    @State private var pendingPermissionDirectory: URL?
    @State private var needsFullDiskAccessPrompt = false
    @State private var fullDiskAccessStatus = FullDiskAccessHelper.status()

    private var filteredEntries: [DirEntry] {
        let entries = showHiddenFiles
            ? scanner.entries
            : scanner.entries.filter { !$0.name.hasPrefix(".") }

        // Limit to first 100 entries for performance
        return Array(entries.prefix(100))
    }

    var body: some View {
        VStack(spacing: 16) {
            MoleHeroPanel(
                eyebrow: "Storage",
                title: "Disk Analyzer",
                subtitle: "Inspect the current folder visually, then drill in only where the size story looks suspicious.",
                symbol: "internaldrive"
            ) {
                VStack(alignment: .trailing, spacing: 10) {
                    MoleMetricBadge(
                        title: "Current Path",
                        value: scanner.currentPath.lastPathComponent,
                        systemImage: "folder.fill",
                        tint: MoleTheme.sky
                    )
                    MoleMetricBadge(
                        title: "Visible Size",
                        value: MetricsFormatter.humanBytes(scanner.totalSize),
                        systemImage: "externaldrive.fill.badge.timemachine",
                        tint: .orange
                    )
                }
            }

            VStack(spacing: 0) {
                breadcrumbBar
                contentArea
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(MoleTheme.line, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 18, y: 8)
        }
        .padding(16)
        .onAppear {
            refreshFullDiskAccessStatus()
            if !hasInitialScan {
                requestScan(directory: scanner.currentPath)
            }
        }
    }

    private var breadcrumbBar: some View {
        HStack(spacing: 8) {
            Button {
                scanner.navigateBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(scanner.pathStack.isEmpty)
            .buttonStyle(.borderless)

            Button {
                scanner.navigateToRoot()
            } label: {
                Image(systemName: "house.fill")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.borderless)

            breadcrumbPath

            Spacer()

            if let lastScan = scanner.lastScanTime {
                Text(relativeTime(from: lastScan))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                scanner.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.borderless)
            .disabled(scanner.isScanning)

            Text(MetricsFormatter.humanBytes(scanner.totalSize))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var breadcrumbPath: some View {
        HStack(spacing: 3) {
            let allPaths = scanner.pathStack + [scanner.currentPath]
            ForEach(Array(allPaths.enumerated()), id: \.offset) { index, url in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                if index < allPaths.count - 1 {
                    Button(url.lastPathComponent) {
                        scanner.navigateToBreadcrumb(index: index)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                } else {
                    Text(url.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if needsFullDiskAccessPrompt {
            fullDiskAccessPrompt
        } else if scanner.isScanning {
            scanningView
        } else if let error = scanner.errorMessage {
            ContentUnavailableView(
                "Scan Error",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if filteredEntries.isEmpty {
            ContentUnavailableView(
                "Empty Directory",
                systemImage: "folder",
                description: Text("No items found")
            )
        } else {
            entryList
        }
    }

    private var fullDiskAccessPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34))
                .foregroundStyle(.orange)

            Text("Full Disk Access Recommended")
                .font(.system(size: 20, weight: .semibold))

            Text(fullDiskAccessPromptDetail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Button {
                    FullDiskAccessHelper.openSystemSettings()
                } label: {
                    Label("Open Full Disk Access", systemImage: "lock.open.display")
                }
                .buttonStyle(.borderedProminent)

                Button("Check Again") {
                    retryPendingScan()
                }

                Button("Scan Anyway") {
                    continuePendingScan()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var scanningView: some View {
        let title = scanner.progress.map { "Scanning: \($0.itemsScanned) items" } ?? "Scanning..."
        let subtitle = scanner.progress?.currentPath

        return MoleLoadingState(title: title, subtitle: subtitle)
            .padding(24)
    }

    private var entryList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                    entryRow(entry, rank: index)
                }
            }
            .padding(16)
        }
        .alert(
            "Move to Trash?",
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                entryToDelete = nil
            }
            Button("Move to Trash", role: .destructive) {
                guard let entry = entryToDelete else { return }
                entryToDelete = nil
                Task {
                    do {
                        try await scanner.deleteEntry(entry)
                    } catch {
                        scanner.errorMessage = error.localizedDescription
                    }
                }
            }
        } message: {
            if let entry = entryToDelete {
                Text("'\(entry.name)' (\(MetricsFormatter.humanBytes(entry.sizeBytes))) will be moved to the Trash.")
            }
        }
    }

    private func entryRow(_ entry: DirEntry, rank _: Int) -> some View {
        let percent = scanner.totalSize > 0
            ? Double(entry.sizeBytes) / Double(scanner.totalSize)
            : 0
        let barColor = Self.barColor(for: percent)

        return Button {
            if entry.isDirectory {
                scanner.navigateTo(directory: entry.path)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(entry.isDirectory ? barColor : .gray)
                    .frame(width: 28)

                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 100, alignment: .leading)

                Spacer()

                Text(String(format: "%.1f%%", percent * 100))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)

                Text(MetricsFormatter.humanBytes(entry.sizeBytes))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(width: 80, alignment: .trailing)

                HStack(spacing: 4) {
                    Button {
                        scanner.revealInFinder(entry)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)

                    Button {
                        entryToDelete = entry
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
                .frame(width: 60)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(barColor.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private static func barColor(for percent: Double) -> Color {
        switch percent {
        case 0.50...: .red
        case 0.25...: .orange
        case 0.10...: .yellow
        case 0.03...: .blue
        default: .teal
        }
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    private func requestScan(directory: URL, bypassPermissionGate: Bool = false) {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let isHomeRoot = directory.standardizedFileURL == home
        let accessStatus = refreshFullDiskAccessStatus()

        if isHomeRoot, !bypassPermissionGate, accessStatus != .granted {
            pendingPermissionDirectory = directory
            needsFullDiskAccessPrompt = true
            return
        }

        pendingPermissionDirectory = nil
        needsFullDiskAccessPrompt = false
        scanner.scan(directory: directory)
        hasInitialScan = true
    }

    private func retryPendingScan() {
        guard let directory = pendingPermissionDirectory else { return }
        if refreshFullDiskAccessStatus() == .granted {
            continuePendingScan()
        } else {
            requestScan(directory: directory)
        }
    }

    private func continuePendingScan() {
        guard let directory = pendingPermissionDirectory else { return }
        requestScan(directory: directory, bypassPermissionGate: true)
    }

    private var fullDiskAccessPromptDetail: String {
        switch fullDiskAccessStatus {
        case .granted:
            "Mole UI now appears to have Full Disk Access. You can continue the Home-folder scan."
        case .notGranted:
            "Scanning your Home folder without Full Disk Access causes macOS to interrupt the scan with separate folder prompts. Enable it first for a cleaner disk scan."
        case .unknown:
            "Mole UI could not positively verify Full Disk Access yet. If you just enabled it, click Check Again once before continuing."
        }
    }

    @discardableResult
    private func refreshFullDiskAccessStatus() -> FullDiskAccessStatus {
        let status = FullDiskAccessHelper.status()
        fullDiskAccessStatus = status
        return status
    }
}
