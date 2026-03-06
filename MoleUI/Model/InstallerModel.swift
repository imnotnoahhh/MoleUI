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
            let results = try await findInstallersWithMole()
            files = results.sorted { $0.sizeBytes > $1.sizeBytes }
        } catch {
            files = []
            if let cliError = error as? CLIExecutor.ExecutionError {
                errorMessage = "Failed to scan installers: \(cliError)"
            } else {
                errorMessage = "Failed to scan installers: \(error)"
            }
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
            errorMessage = "Failed to delete file: \(error)"
        }
        deletingFile = nil
    }

    // MARK: - Mole Core Integration

    private func findInstallersWithMole() async throws -> [InstallerFile] {
        guard let root = CLIExecutor.findMoleRoot() else {
            throw CLIExecutor.ExecutionError.commandNotFound("mole")
        }

        // Step 1: Get file paths from Mole with metadata
        let scanScript = """
        set -eo pipefail
        ROOT=\(shellEscape(root.path))
        export MOLE_TEST_MODE=1
        source "$ROOT/bin/installer.sh"

        # Use Mole's scan_all_installers and get_source_display
        scan_all_installers | while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            size=$(stat -f%z "$file" 2>/dev/null || echo 0)
            source=$(get_source_display "$file")
            name=$(basename "$file")
            printf '%s|%s|%s|%s\\n' "$file" "$size" "$source" "$name"
        done
        """

        let executor = CLIExecutor()
        let result = try await executor.execute(
            command: "bash -c \(shellEscape(scanScript))",
            options: CLIExecutor.ExecutionOptions(
                timeout: 30,
                captureStderr: true,
                parseProgress: false,
                dryRun: false
            )
        )

        let output = result.stdout

        // Step 2: Parse the pipe-delimited output
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
        _ = try await CLIExecutor.run("bash -c \(shellEscape(script))")
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
