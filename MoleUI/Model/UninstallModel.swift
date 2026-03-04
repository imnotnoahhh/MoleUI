import AppKit
import Foundation
import Observation

struct AppInfo: Identifiable, @unchecked Sendable {
    let id: String // bundle path
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let sizeBytes: UInt64
    let icon: NSImage
    let path: URL
    let lastUsed: Date?

    init(
        name: String, bundleIdentifier: String?, version: String?,
        sizeBytes: UInt64, icon: NSImage, path: URL, lastUsed: Date?
    ) {
        self.id = path.path
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.sizeBytes = sizeBytes
        self.icon = icon
        self.path = path
        self.lastUsed = lastUsed
    }
}

// MARK: - App Scanner

@Observable @MainActor
final class AppScanModel {
    var apps: [AppInfo] = []
    var isScanning: Bool = false

    init() {}

    func scan() {
        isScanning = true
        apps = []

        Task.detached { [weak self] in
            guard let self else { return }
            let scanned = performScan()
            await MainActor.run {
                self.apps = scanned
                self.isScanning = false
            }
        }
    }

    private nonisolated func performScan() -> [AppInfo] {
        let fm = FileManager.default
        let appsURL = URL(fileURLWithPath: "/Applications")

        guard let contents = try? fm.contentsOfDirectory(
            at: appsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [AppInfo] = []

        for url in contents where url.pathExtension == "app" {
            guard let bundle = Bundle(url: url),
                  let infoPlist = bundle.infoDictionary
            else {
                continue
            }

            let name = infoPlist["CFBundleName"] as? String
                ?? infoPlist["CFBundleDisplayName"] as? String
                ?? url.deletingPathExtension().lastPathComponent

            let bundleId = infoPlist["CFBundleIdentifier"] as? String
            let version = infoPlist["CFBundleShortVersionString"] as? String

            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let size = bundleSize(at: url)
            let lastUsed = lastUsedDate(for: url.path)

            let info = AppInfo(
                name: name,
                bundleIdentifier: bundleId,
                version: version,
                sizeBytes: size,
                icon: icon,
                path: url,
                lastUsed: lastUsed
            )
            results.append(info)
        }

        results.sort { $0.sizeBytes > $1.sizeBytes }
        return results
    }

    private nonisolated func bundleSize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    private nonisolated func lastUsedDate(for path: String) -> Date? {
        let url = URL(fileURLWithPath: path)

        // 1. Try Spotlight kMDItemLastUsedDate (most accurate when available)
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        {
            return date
        }

        // 2. Try content modification date from Spotlight
        if let item = MDItemCreateWithURL(nil, url as CFURL),
           let date = MDItemCopyAttribute(item, kMDItemContentModificationDate) as? Date
        {
            return date
        }

        // 3. Fall back to file system contentAccessDate or contentModificationDate
        let fm = FileManager.default
        if let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey]) {
            return values.contentAccessDate ?? values.contentModificationDate
        }

        // 4. Last resort: Info.plist modification date
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        if let attrs = try? fm.attributesOfItem(atPath: plistURL.path),
           let date = attrs[.modificationDate] as? Date
        {
            return date
        }

        return nil
    }
}

// MARK: - Uninstaller

@Observable @MainActor
final class UninstallModel {
    var isUninstalling: Bool = false
    var uninstalledApps: Set<String> = []
    var errorMessage: String?

    init() {}

    func findRelatedFiles(for app: AppInfo) -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        var related: [URL] = []

        let name = app.name
        let bundleId = app.bundleIdentifier

        // ~/Library/Application Support/{name or bundleId}
        if let bundleId {
            let path = library.appendingPathComponent("Application Support/\(bundleId)")
            if fm.fileExists(atPath: path.path) { related.append(path) }
        }
        let appSupportName = library.appendingPathComponent("Application Support/\(name)")
        if fm.fileExists(atPath: appSupportName.path) { related.append(appSupportName) }

        // ~/Library/Caches/{bundleId}
        if let bundleId {
            let path = library.appendingPathComponent("Caches/\(bundleId)")
            if fm.fileExists(atPath: path.path) { related.append(path) }
        }

        // ~/Library/Preferences/{bundleId}.plist
        if let bundleId {
            let path = library.appendingPathComponent("Preferences/\(bundleId).plist")
            if fm.fileExists(atPath: path.path) { related.append(path) }
        }

        // ~/Library/Logs/{name or bundleId}
        if let bundleId {
            let path = library.appendingPathComponent("Logs/\(bundleId)")
            if fm.fileExists(atPath: path.path) { related.append(path) }
        }
        let logsName = library.appendingPathComponent("Logs/\(name)")
        if fm.fileExists(atPath: logsName.path) { related.append(logsName) }

        // ~/Library/Saved Application State/{bundleId}.savedState
        if let bundleId {
            let path = library.appendingPathComponent("Saved Application State/\(bundleId).savedState")
            if fm.fileExists(atPath: path.path) { related.append(path) }
        }

        // ~/Library/Containers/{bundleId}
        if let bundleId {
            let path = library.appendingPathComponent("Containers/\(bundleId)")
            if fm.fileExists(atPath: path.path) { related.append(path) }
        }

        // ~/Library/Group Containers/*{bundleId}*
        if let bundleId {
            let groupDir = library.appendingPathComponent("Group Containers")
            if let items = try? fm.contentsOfDirectory(atPath: groupDir.path) {
                for item in items where item.contains(bundleId) {
                    related.append(groupDir.appendingPathComponent(item))
                }
            }
        }

        return related
    }

    func uninstall(app: AppInfo, relatedFiles: [URL]) async throws {
        isUninstalling = true
        errorMessage = nil
        defer { isUninstalling = false }

        let allURLs = [app.path] + relatedFiles

        // Use NSWorkspace.recycle to move to Trash (safer than rm)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle(allURLs) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        uninstalledApps.insert(app.id)
    }
}
