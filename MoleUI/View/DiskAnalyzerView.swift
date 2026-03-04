import AppKit
import SwiftUI

struct DiskAnalyzerView: View {
    @Environment(DiskModel.self) var scanner
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false
    @State private var entryToDelete: DirEntry?
    @State private var hoveredEntry: String?

    private var filteredEntries: [DirEntry] {
        if showHiddenFiles {
            return scanner.entries
        }
        return scanner.entries.filter { !$0.name.hasPrefix(".") }
    }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbBar
            contentArea
        }
        .onAppear {
            scanner.scan(directory: scanner.currentPath)
        }
    }

    // MARK: - Breadcrumb Bar

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

            Text(MetricsFormatter.humanBytes(scanner.totalSize))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
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

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if scanner.isScanning {
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

    private var scanningView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            if let prog = scanner.progress {
                Text("Scanning: \(prog.itemsScanned) items")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(prog.currentPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Entry List

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
            Button("Cancel", role: .cancel) { entryToDelete = nil }
            Button("Move to Trash", role: .destructive) {
                guard let entry = entryToDelete else { return }
                entryToDelete = nil
                Task { try? await scanner.deleteEntry(entry) }
            }
        } message: {
            if let entry = entryToDelete {
                Text("'\(entry.name)' (\(MetricsFormatter.humanBytes(entry.sizeBytes))) will be moved to the Trash.")
            }
        }
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: DirEntry, rank _: Int) -> some View {
        let percent = scanner.totalSize > 0
            ? Double(entry.sizeBytes) / Double(scanner.totalSize)
            : 0
        let barColor = Self.barColor(for: percent)
        let isHovered = hoveredEntry == entry.id

        return HStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(isHovered ? 0.06 : 0.03))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(barColor.opacity(isHovered ? 0.35 : 0.2))
                        .frame(width: max(geo.size.width * CGFloat(percent), 4))
                }
            }
            .overlay {
                entryRowContent(entry, percent: percent, barColor: barColor)
            }
        }
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredEntry = hovering ? entry.id : nil
        }
        .onTapGesture {
            if entry.isDirectory {
                scanner.navigateTo(directory: entry.path)
            }
        }
    }

    private func entryRowContent(_ entry: DirEntry, percent: Double, barColor: Color) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(entry.isDirectory ? barColor : .gray)
                .frame(width: 28)

            // Name + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.isDirectory, entry.children > 0 {
                    Text("\(entry.children) items")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 100, alignment: .leading)

            Spacer()

            // Percentage
            Text(String(format: "%.1f%%", percent * 100))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)

            // Size
            Text(MetricsFormatter.humanBytes(entry.sizeBytes))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 80, alignment: .trailing)

            // Actions
            actionButtons(for: entry)
        }
        .padding(.horizontal, 14)
    }

    private func actionButtons(for entry: DirEntry) -> some View {
        HStack(spacing: 4) {
            Button {
                scanner.revealInFinder(entry)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")

            Button {
                entryToDelete = entry
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.borderless)
            .help("Move to Trash")
        }
    }

    // MARK: - Color Helper

    private static func barColor(for percent: Double) -> Color {
        switch percent {
        case 0.50...: .red
        case 0.25...: .orange
        case 0.10...: .yellow
        case 0.03...: .blue
        default: .teal
        }
    }
}
