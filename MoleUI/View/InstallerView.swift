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
                headerCard
                contentArea
            }
            .padding()
        }
        .task {
            await service.scan()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        MoleHeroPanel(
            eyebrow: "Files",
            title: "Installers",
            subtitle: "Find forgotten `.dmg`, `.pkg`, `.xip`, and archive downloads before they quietly eat your SSD.",
            symbol: "shippingbox.fill"
        ) {
            VStack(alignment: .trailing, spacing: 10) {
                MoleMetricBadge(
                    title: "Reclaimable",
                    value: MetricsFormatter.humanBytes(totalReclaimable),
                    systemImage: "tray.full.fill",
                    tint: .orange
                )

                HStack(spacing: 10) {
                    MoleSearchField(prompt: "Search installers", text: $searchText)
                        .frame(width: 190)

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
        if service.isScanning, service.files.isEmpty {
            GroupBox {
                VStack(spacing: 8) {
                    ProgressView("Scanning for installers...")
                        .controlSize(.regular)
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
                    .background(MoleTheme.sky.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(MetricsFormatter.humanBytes(file.sizeBytes))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .frame(width: 80, alignment: .trailing)

                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
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
