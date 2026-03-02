import Foundation
import Observation

enum MoleVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

@Observable @MainActor
final class VersionModel {
    var currentVersion: String?
    var latestVersion: String?
    var isChecking = false

    var hasUpdate: Bool {
        guard let current = currentVersion,
              let latest = latestVersion else { return false }
        return compareVersions(current, latest) == .orderedAscending
    }

    func loadCurrentVersion() async {
        if let versionFile = Bundle.main.resourceURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".mole-cli-version")
        {
            if let version = try? String(contentsOf: versionFile, encoding: .utf8) {
                currentVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
                return
            }
        }

        if let molePath = findMoleBinary() {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: molePath)
            task.arguments = ["version"]
            let pipe = Pipe()
            task.standardOutput = pipe
            try? task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if let match = output.range(of: #"version\s+(\S+)"#, options: .regularExpression) {
                    let versionStr = output[match]
                        .replacingOccurrences(of: "version", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    currentVersion = versionStr
                }
            }
        }
    }

    func checkForUpdates() async {
        isChecking = true
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/tw93/Mole/releases/latest") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let tagName = json?["tag_name"] as? String {
                let cleaned = tagName.hasPrefix("v") || tagName.hasPrefix("V")
                    ? String(tagName.dropFirst()) : tagName
                latestVersion = cleaned
            }
        } catch {
            print("Failed to check for updates: \(error)")
        }
    }

    private func findMoleBinary() -> String? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("mole/mole").path,
            fm.isExecutableFile(atPath: bundled)
        {
            return bundled
        }
        for path in ["/usr/local/bin/mole", "/opt/homebrew/bin/mole",
                     NSHomeDirectory() + "/.config/mole/mole"]
            where fm.isExecutableFile(atPath: path)
        {
            return path
        }
        return nil
    }

    private func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        let clean1 = v1.hasPrefix("v") || v1.hasPrefix("V") ? String(v1.dropFirst()) : v1
        let clean2 = v2.hasPrefix("v") || v2.hasPrefix("V") ? String(v2.dropFirst()) : v2
        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }
        for (p1, p2) in zip(parts1, parts2) {
            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }
        if parts1.count < parts2.count { return .orderedAscending }
        if parts1.count > parts2.count { return .orderedDescending }
        return .orderedSame
    }
}
