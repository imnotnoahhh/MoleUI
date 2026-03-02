import SwiftUI

struct SettingsView: View {
    @Environment(SettingsModel.self) var whitelist
    @AppStorage("confirmBeforeClean") private var confirmBeforeClean = true
    @AppStorage("dryRunMode") private var dryRunMode = false
    @AppStorage("showHiddenFiles") private var showHiddenFiles = false

    var body: some View {
        ScrollView {
            Form {
                whitelistSection
                preferencesSection
                aboutSection
                cliOnlySection
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    // MARK: - Whitelist

    private var whitelistSection: some View {
        Section {
            if whitelist.whitelistItems.isEmpty {
                Text("No whitelisted paths")
                    .foregroundStyle(.secondary)
                    .font(.system(.caption, design: .monospaced))
            } else {
                ForEach(whitelist.whitelistItems, id: \.self) { path in
                    HStack {
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            whitelist.removeFromWhitelist(path: path)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                addPath()
            } label: {
                Label("Add Path", systemImage: "plus.circle")
            }
        } header: {
            Label("Whitelist", systemImage: "shield.checkered")
                .font(.headline)
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        Section {
            Toggle("Confirm before cleaning", isOn: $confirmBeforeClean)
            Toggle("Dry run mode", isOn: $dryRunMode)
            Toggle("Show hidden files in Disk Analyzer", isOn: $showHiddenFiles)
        } header: {
            Label("Preferences", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            // Mole UI version checker
            MoleVersionView()
            Divider()

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

    private func addPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory to whitelist"
        if panel.runModal() == .OK, let url = panel.url {
            whitelist.addToWhitelist(path: url.path)
        }
    }

    private func readMoleCLIVersion() -> String? {
        // Try reading from .mole-cli-version file
        if let versionFile = Bundle.main.resourceURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".mole-cli-version"),
            let version = try? String(contentsOf: versionFile, encoding: .utf8)
        {
            return version.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
