import SwiftUI

struct InstallerView: View {
    @Environment(InstallerModel.self) var service
    @State private var selectedFiles: Set<String> = []
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
        .alert("Confirm Delete", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                Task { await service.deleteSelected(ids: selectedFiles) }
            }
        } message: {
            Text("Move \(selectedFiles.count) installer files to Trash?")
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

                Button {
                    showConfirmation = true
                } label: {
                    Label("Trash Selected", systemImage: "trash")
                }
                .disabled(selectedFiles.isEmpty || service.isScanning || service.deletingFile != nil)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if service.isScanning && service.files.isEmpty {
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

        if service.files.isEmpty && !service.isScanning {
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
        let isSelected = selectedFiles.contains(file.id)
        let isDeleting = service.deletingFile == file.id
        let isCompleted = service.completedFiles.contains(file.id)

        return GroupBox {
            HStack(spacing: 10) {
                Toggle(isOn: Binding(
                    get: { isSelected },
                    set: { on in
                        if on { selectedFiles.insert(file.id) } else { selectedFiles.remove(file.id) }
                    }
                )) {
                    EmptyView()
                }
                .toggleStyle(.checkbox)
                .labelsHidden()

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
        case "dmg": return "opticaldiscdrive"
        case "pkg", "mpkg": return "shippingbox"
        case "iso": return "opticaldisc"
        case "xip": return "doc.zipper"
        case "zip": return "doc.zipper"
        default: return "doc"
        }
    }
}
