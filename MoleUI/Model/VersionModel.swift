import Foundation
import Observation

enum MoleVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

@Observable @MainActor
final class VersionModel {
    private struct ReleaseResponse: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }

    var currentVersion: String?
    var latestVersion: String?
    var updateError: String?
    var isChecking = false

    var hasUpdate: Bool {
        guard let current = currentVersion,
              let latest = latestVersion else { return false }
        return compareVersions(current, latest) == .orderedAscending
    }

    func loadCurrentVersion() async {
        // Read MoleUI version from Info.plist
        currentVersion = MoleVersion.current
    }

    func checkForUpdates() async {
        isChecking = true
        updateError = nil
        defer { isChecking = false }

        // Check MoleUI releases instead of Mole CLI
        guard let url = URL(string: "https://api.github.com/repos/imnotnoahhh/MoleUI/releases/latest") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               !(200 ... 299).contains(httpResponse.statusCode)
            {
                latestVersion = nil
                updateError = "GitHub returned HTTP \(httpResponse.statusCode)."
                return
            }

            let release = try JSONDecoder().decode(ReleaseResponse.self, from: data)
            latestVersion = normalizeVersion(release.tagName)
        } catch {
            latestVersion = nil
            updateError = error.localizedDescription
        }
    }

    private func normalizeVersion(_ version: String) -> String {
        version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
    }

    private func versionParts(for version: String) -> [Int]? {
        let cleaned = normalizeVersion(version)
        let components = cleaned.split(separator: ".")
        guard !components.isEmpty else { return nil }

        let values = components.compactMap { Int($0) }
        return values.count == components.count ? values : nil
    }

    private func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        guard let parts1 = versionParts(for: v1),
              let parts2 = versionParts(for: v2)
        else {
            return .orderedSame
        }

        let maxCount = max(parts1.count, parts2.count)
        for index in 0 ..< maxCount {
            let p1 = index < parts1.count ? parts1[index] : 0
            let p2 = index < parts2.count ? parts2[index] : 0
            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }
        return .orderedSame
    }
}
