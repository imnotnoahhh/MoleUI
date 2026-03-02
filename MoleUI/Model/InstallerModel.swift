import AppKit
import Foundation
import Observation

// MARK: - Data

struct InstallerFile: Identifiable, Equatable {
    let id: String
    let path: URL
    let name: String
    let sizeBytes: UInt64
    let source: String
    let fileExtension: String

    init(path: URL, name: String, sizeBytes: UInt64, source: String) {
        id = path.path
        self.path = path
        self.name = name
        self.sizeBytes = sizeBytes
        self.source = source
        fileExtension = path.pathExtension.lowercased()
    }
}

enum InstallerConstants {
    static let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "zip"]

    static var scanPaths: [(path: String, label: String)] {
        let home = NSHomeDirectory()
        return [
            ("\(home)/Downloads", "Downloads"),
            ("\(home)/Desktop", "Desktop"),
            ("\(home)/Documents", "Documents"),
            ("\(home)/Public", "Public"),
            ("\(home)/Library/Downloads", "Library"),
            ("/Users/Shared", "Shared"),
            ("/Users/Shared/Downloads", "Shared"),
            ("\(home)/Library/Caches/Homebrew", "Homebrew"),
            ("\(home)/Library/Mobile Documents/com~apple~CloudDocs/Downloads", "iCloud"),
            ("\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads", "Mail"),
            ("\(home)/Library/Application Support/Telegram Desktop", "Telegram"),
            ("\(home)/Downloads/Telegram Desktop", "Telegram"),
        ]
    }

    static let maxScanDepth = 2
}

// MARK: - Model

@Observable @MainActor
final class InstallerModel {
    var files: [InstallerFile] = []
    var isScanning: Bool = false
    var deletingFile: String?
    var completedFiles: Set<String> = []
    var errorMessage: String?

    func scan() async {
        isScanning = true
        errorMessage = nil
        completedFiles = []

        let results = await Task.detached { () -> [InstallerFile] in
            Self.findInstallers()
        }.value

        files = results.sorted { $0.sizeBytes > $1.sizeBytes }
        isScanning = false
    }

    func deleteFile(_ file: InstallerFile) async {
        deletingFile = file.id
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.recycle([file.path]) { _, error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
            completedFiles.insert(file.id)
            files.removeAll { $0.id == file.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        deletingFile = nil
    }

    func deleteSelected(ids: Set<String>) async {
        for file in files where ids.contains(file.id) {
            await deleteFile(file)
        }
    }

    // MARK: - Static Scanner

    private nonisolated static func findInstallers() -> [InstallerFile] {
        let fm = FileManager.default
        let exts = InstallerConstants.extensions
        var results: [InstallerFile] = []
        var seen = Set<String>()

        for (scanPath, label) in InstallerConstants.scanPaths {
            let rootURL = URL(fileURLWithPath: scanPath)
            guard fm.fileExists(atPath: scanPath) else { continue }

            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                let depth = url.pathComponents.count - rootURL.pathComponents.count
                if depth > InstallerConstants.maxScanDepth {
                    enumerator.skipDescendants()
                    continue
                }

                let ext = url.pathExtension.lowercased()
                guard exts.contains(ext) else { continue }

                if let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                   vals.isDirectory == true { continue }

                let canonical = url.resolvingSymlinksInPath().path
                guard !seen.contains(canonical) else { continue }
                seen.insert(canonical)

                let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
                let size = UInt64(vals?.totalFileAllocatedSize ?? vals?.fileSize ?? 0)
                if size == 0 { continue }

                var displayName = url.lastPathComponent
                if label == "Homebrew", let range = displayName.range(
                    of: #"^[0-9a-f]{64}--"#, options: .regularExpression
                ) {
                    displayName = String(displayName[range.upperBound...])
                }

                results.append(InstallerFile(
                    path: url, name: displayName, sizeBytes: size, source: label
                ))
            }
        }
        return results
    }
}
