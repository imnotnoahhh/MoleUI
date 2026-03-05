import SwiftUI

enum AppSortOrder: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case lastUsed = "Last Used"
}

struct UninstallView: View {
    @Environment(AppScanModel.self) var scanService
    @Environment(UninstallModel.self) var uninstallService

    @State private var searchText = ""
    @State private var sortOrder: AppSortOrder = .size
    @State private var appToUninstall: AppInfo?
    @State private var relatedFilesCount = 0
    @State private var showConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            content
        }
        .onAppear {
            scanService.scan()
        }
        .alert("Uninstall App", isPresented: $showConfirmation, presenting: appToUninstall) { app in
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                performUninstall(app)
            }
        } message: { app in
            Text("Move \"\(app.name)\" and \(relatedFilesCount) related file\(relatedFilesCount == 1 ? "" : "s") to Trash?")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 240)

            Picker("Sort", selection: $sortOrder) {
                ForEach(AppSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Spacer()

            // Cache status
            if let lastScan = scanService.lastScanTime {
                Text("Scanned \(relativeTime(from: lastScan))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                scanService.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(scanService.isScanning)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if scanService.isScanning {
            VStack {
                Spacer()
                ProgressView("Scanning /Applications...")
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if uninstallService.isUninstalling {
            VStack {
                Spacer()
                ProgressView("Moving to Trash...")
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredApps.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            appList
        }

        if let error = uninstallService.errorMessage {
            GroupBox {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            .padding()
        }
    }

    // MARK: - App List

    private var appList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredApps) { app in
                    appRow(app)
                }
            }
            .padding()
        }
    }

    // MARK: - App Row

    private func appRow(_ app: AppInfo) -> some View {
        let wasUninstalled = uninstallService.uninstalledApps.contains(app.id)

        return GroupBox {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(app.name)
                            .fontWeight(.medium)
                        if let version = app.version {
                            Text(version)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)

                    if let bundleId = app.bundleIdentifier {
                        Text(bundleId)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(MetricsFormatter.humanBytes(app.sizeBytes))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 70, alignment: .trailing)

                Text(relativeDate(app.lastUsed))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)

                if wasUninstalled {
                    Text("Removed")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(width: 80)
                } else {
                    Button("Uninstall") {
                        appToUninstall = app
                        relatedFilesCount = uninstallService.findRelatedFiles(for: app).count
                        showConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .frame(width: 80)
                }
            }
            .padding(.vertical, 2)
        }
        .opacity(wasUninstalled ? 0.5 : 1.0)
    }

    // MARK: - Filtering & Sorting

    private var filteredApps: [AppInfo] {
        var apps = scanService.apps

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            apps = apps.filter { $0.name.lowercased().contains(query) }
        }

        switch sortOrder {
        case .name:
            apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            apps.sort { $0.sizeBytes > $1.sizeBytes }
        case .lastUsed:
            apps.sort { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        }

        return apps
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "just now"
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

    // MARK: - Actions

    private func performUninstall(_ app: AppInfo) {
        let related = uninstallService.findRelatedFiles(for: app)
        Task {
            do {
                try await uninstallService.uninstall(app: app, relatedFiles: related)
            } catch {
                uninstallService.errorMessage = "Failed to uninstall \(app.name): \(error.localizedDescription)"
            }
        }
    }
}
