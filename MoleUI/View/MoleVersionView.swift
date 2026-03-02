import SwiftUI

/// Mole 版本信息显示
struct MoleVersionView: View {
    @Environment(VersionModel.self) var versionChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Mole CLI", systemImage: "terminal")
                    .font(.headline)

                Spacer()

                if versionChecker.isChecking {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            // Current version
            HStack {
                Text("Current:")
                    .foregroundColor(.secondary)
                Text(versionChecker.currentVersion ?? "Unknown")
                    .fontWeight(.medium)
            }
            .font(.callout)

            // Latest version
            if let latestVersion = versionChecker.latestVersion {
                HStack {
                    Text("Latest:")
                        .foregroundColor(.secondary)
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
            }

            // Update prompt
            if versionChecker.hasUpdate {
                HStack {
                    Text("Update available")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Spacer()

                    Button("View Release") {
                        if let url = URL(string: "https://github.com/tw93/Mole/releases/latest") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }

            // Check for updates button
            if !versionChecker.isChecking {
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
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .task {
            await versionChecker.loadCurrentVersion()
        }
    }
}
