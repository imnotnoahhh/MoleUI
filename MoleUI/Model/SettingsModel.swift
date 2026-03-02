import Foundation
import Observation

@Observable @MainActor
final class SettingsModel {
    var whitelistItems: [String] = []

    private let configDir: URL
    private let filePath: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".config/mole")
        filePath = configDir.appendingPathComponent("whitelist")
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            whitelistItems = []
            return
        }
        do {
            let content = try String(contentsOf: filePath, encoding: .utf8)
            whitelistItems = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            whitelistItems = []
        }
    }

    func addToWhitelist(path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !whitelistItems.contains(trimmed) else { return }
        whitelistItems.append(trimmed)
        save()
    }

    func removeFromWhitelist(path: String) {
        whitelistItems.removeAll { $0 == path }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: configDir,
                withIntermediateDirectories: true
            )
            let content = whitelistItems.joined(separator: "\n") + "\n"
            try content.write(to: filePath, atomically: true, encoding: .utf8)
        } catch {
            // Silently fail
        }
    }
}
