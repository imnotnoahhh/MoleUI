import SwiftUI

struct InstallerView: View {
    @Environment(InstallerModel.self) var service
    @State private var showConfirmation = false
    @State private var searchText = ""

    private var totalReclaimable: UInt64 {
        service.files.reduce(0) { $0 + $1.sizeBytes }
    }

    private var filteredFiles: [InstallerFile] {
        if searchText.isEmpty { return service.files }
        return service.files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !service.hasFullDiskAccess {
                    permissionBanner
                }
                headerCard
                contentArea
            }
            .padding()
        }
        .task {
            await service.scan()
        }
    }

    // MARK: - Permission Banner

    private var permissionBanner: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.shield")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Full Disk Access Recommended")
                        .fontWeight(.semibold)
                    Text("First scan will request access to multiple directories. Grant Full Disk Access in System Settings for the best experience.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Settings") {
                    service.openSystemPreferences()
                }
                .buttonStyle(.borderedProminent)

                Button("Dismiss") {
                    service.hasFullDiskAccess = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        GroupBox {
            HStack(spacing: 8) {
                Text("Installers")
                    .fontWeight(.bold)
                Text("Reclaimable")
                    .foregroundStyle(.secondary)
                Text(MetricsFormatter.humanBytes(totalReclaimable))
                    .fontWeight(.bold)
                    .foregroundStyle(.orange)

                Spacer()

                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

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
        if service.isScanning, service.files.isEmpty {
            GroupBox {
                VStack(spacing: 8) {
                    ProgressView("Scanning for installers...")
                    Text("Checking Downloads, Desktop, iCloud and more")
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

        if service.files.isEmpty, !service.isScanning {
            GroupBox {
                Text("No installer files found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }
        }

        if !filteredFiles.isEmpty {
            ForEach(filteredFiles) { file in
                fileRow(file)
            }
        }
    }

    // MARK: - File Row

    private func fileRow(_ file: InstallerFile) -> some View {
        let isDeleting = service.deletingFile == file.id
        let isCompleted = service.completedFiles.contains(file.id)

        return GroupBox {
            HStack(spacing: 10) {
                Image(systemName: iconForExtension(file.fileExtension))
                    .frame(width: 20)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(file.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(file.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 160, alignment: .leading)

                Spacer()

                Text(file.fileExtension.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text(MetricsFormatter.humanBytes(file.sizeBytes))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .frame(width: 80, alignment: .trailing)

                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60)
                } else if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 60)
                } else {
                    Button("Trash") {
                        Task { await service.deleteFile(file) }
                    }
                    .disabled(service.deletingFile != nil)
                    .frame(width: 60)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext {
        case "dmg": "opticaldiscdrive"
        case "pkg", "mpkg": "shippingbox"
        case "iso": "opticaldisc"
        case "xip": "doc.zipper"
        case "zip": "doc.zipper"
        default: "doc"
        }
    }
}
