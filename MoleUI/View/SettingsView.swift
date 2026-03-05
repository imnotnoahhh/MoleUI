import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            Form {
                aboutSection
                cliOnlySection
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            // Mole UI version checker
            MoleVersionView()
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            // MoleUI App Version
            HStack {
                Text("MoleUI Version")
                Spacer()
                Text(MoleVersion.current)
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .monospaced))
            }

            // Bundled Mole CLI Version
            HStack {
                Text("Bundled Mole CLI")
                Spacer()
                if let cliVersion = readMoleCLIVersion() {
                    Text(cliVersion)
                        .foregroundStyle(.secondary)
                        .font(.system(.caption, design: .monospaced))
                } else {
                    Text("Unknown")
                        .foregroundStyle(.secondary)
                        .font(.system(.caption, design: .monospaced))
                }
            }

            HStack {
                Text("GitHub")
                Spacer()
                Text("https://github.com/imnotnoahhh/MoleUI")
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        } header: {
            Label("About", systemImage: "info.circle")
                .font(.headline)
        }
    }

    // MARK: - CLI-Only Features

    private var cliOnlySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                cliFeatureRow("mo touchid", "Configure Touch ID for sudo authentication")
                cliFeatureRow("mo completion", "Generate shell completion scripts (bash/zsh/fish)")
                cliFeatureRow("mo update", "Self-update Mole to the latest version")
                cliFeatureRow("mo remove", "Uninstall Mole from the system")
            }
        } header: {
            Label("CLI-Only Features", systemImage: "terminal")
                .font(.headline)
        } footer: {
            Text("These features require terminal access and are not available in the GUI.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func cliFeatureRow(_ command: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func readMoleCLIVersion() -> String? {
        // Read from .mole-cli-version file in app bundle resources
        if let versionFile = Bundle.main.url(forResource: ".mole-cli-version", withExtension: nil),
           let version = try? String(contentsOf: versionFile, encoding: .utf8)
        {
            return version.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
