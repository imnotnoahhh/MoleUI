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
        self.id = path.path
        self.path = path
        self.name = name
        self.sizeBytes = sizeBytes
        self.source = source
        self.fileExtension = path.pathExtension.lowercased()
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

        do {
            files = try await findInstallersWithMole().sorted { $0.sizeBytes > $1.sizeBytes }
        } catch {
            files = []
            errorMessage = error.localizedDescription
        }
        isScanning = false
    }

    func deleteFile(_ file: InstallerFile) async {
        deletingFile = file.id
        do {
            try await deleteWithMole(file.path.path)
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

    // MARK: - Mole Core Integration

    private func findInstallersWithMole() async throws -> [InstallerFile] {
        guard let root = CLIExecutor.findMoleRoot() else {
            throw CLIExecutor.ExecutionError.commandNotFound("mole")
        }

        let script = """
        set -euo pipefail
        ROOT=\(shellEscape(root.path))
        export MOLE_TEST_MODE=1
        source "$ROOT/bin/installer.sh"
        collect_installers >/dev/null 2>&1 || true
        for i in "${!INSTALLER_PATHS[@]}"; do
          path="${INSTALLER_PATHS[$i]}"
          size="${INSTALLER_SIZES[$i]}"
          source_name="${INSTALLER_SOURCES[$i]}"
          name="$(basename "$path")"
          printf '%s|%s|%s|%s\\n' "$path" "$size" "$source_name" "$name"
        done
        """

        let output = try await CLIExecutor.run("bash -lc \(shellEscape(script))")
        return output
            .split(separator: "\n")
            .compactMap { line -> InstallerFile? in
                let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count >= 4 else { return nil }
                let path = String(parts[0])
                let size = UInt64(parts[1]) ?? 0
                let source = String(parts[2])
                let name = String(parts[3])
                return InstallerFile(
                    path: URL(fileURLWithPath: path),
                    name: name,
                    sizeBytes: size,
                    source: source
                )
            }
    }

    private func deleteWithMole(_ path: String) async throws {
        guard let root = CLIExecutor.findMoleRoot() else {
            throw CLIExecutor.ExecutionError.commandNotFound("mole")
        }
        let script = """
        set -euo pipefail
        ROOT=\(shellEscape(root.path))
        TARGET=\(shellEscape(path))
        source "$ROOT/lib/core/common.sh"
        safe_remove "$TARGET" true >/dev/null
        """
        _ = try await CLIExecutor.run("bash -lc \(shellEscape(script))")
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
