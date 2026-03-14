import SwiftUI

/// Mole UI version information display
struct MoleVersionView: View {
    @Environment(VersionModel.self) var versionChecker
    @Environment(\.colorScheme) private var colorScheme
    let bundledCLIVersion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Version Details", systemImage: "app.badge")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                if versionChecker.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Button {
                        Task {
                            await versionChecker.checkForUpdates()
                        }
                    } label: {
                        Label("Check for Updates", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }
            }

            HStack(spacing: 12) {
                versionChip(
                    title: "Mole UI",
                    value: versionChecker.currentVersion ?? "Unknown",
                    systemImage: "app.badge.fill",
                    tint: .green
                )
                versionChip(
                    title: "Bundled CLI",
                    value: bundledCLIVersion ?? "Unknown",
                    systemImage: "terminal.fill",
                    tint: .blue
                )
            }

            if let latestVersion = versionChecker.latestVersion {
                HStack {
                    Text("Latest release")
                        .foregroundStyle(.secondary)
                    Text(latestVersion)
                        .fontWeight(.medium)

                    if versionChecker.hasUpdate {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .font(.callout)
                if versionChecker.hasUpdate {
                    HStack {
                        Text("Update available")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Spacer()

                        Link("View Release", destination: URL(string: "https://github.com/imnotnoahhh/MoleUI/releases/latest")!)
                            .font(.caption)
                    }
                } else {
                    Text("This build is already on the latest published Mole UI release.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let updateError = versionChecker.updateError {
                Text("Update check failed: \(updateError)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text("Latest release has not been checked yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
        )
        .task {
            await versionChecker.loadCurrentVersion()
        }
    }

    private func versionChip(title: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.22 : 0.12), lineWidth: 1)
        )
    }
}
