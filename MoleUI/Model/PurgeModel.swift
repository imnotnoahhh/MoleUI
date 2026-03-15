import Foundation
import Observation

// MARK: - Data

struct PurgeTarget: Identifiable, Equatable {
    let id: String
    let path: URL
    let projectName: String
    let artifactName: String
    let sizeBytes: UInt64
    let ageDays: Int
    var isRecent: Bool {
        ageDays < 7
    }

    init(path: URL, projectName: String, artifactName: String, sizeBytes: UInt64, ageDays: Int) {
        self.id = path.path
        self.path = path
        self.projectName = projectName
        self.artifactName = artifactName
        self.sizeBytes = sizeBytes
        self.ageDays = ageDays
    }
}

enum PurgeConstants {
    static let artifactNames: [String] = [
        "node_modules", "target", "build", "dist", "venv", ".venv",
        ".pytest_cache", ".mypy_cache", ".tox", ".nox", ".ruff_cache",
        ".gradle", "__pycache__", ".next", ".nuxt", ".output", "vendor",
        "bin", "obj", ".turbo", ".parcel-cache", ".dart_tool",
        ".zig-cache", "zig-out", ".angular", ".svelte-kit", ".astro",
        "coverage", "DerivedData", "Pods", ".cxx", ".expo", ".build",
    ]

    static let protectedArtifacts: Set<String> = ["vendor", "bin"]

    static let projectIndicators: Set<String> = [
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml",
        "requirements.txt", "pom.xml", "build.gradle", "Gemfile",
        "composer.json", "pubspec.yaml", "Makefile", "build.zig", ".git",
    ]

    static let dotnetIndicators: Set<String> = [".csproj", ".fsproj", ".vbproj"]

    static var defaultScanPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/www", "\(home)/dev", "\(home)/Projects",
            "\(home)/GitHub", "\(home)/Code", "\(home)/Workspace",
            "\(home)/Repos", "\(home)/Development",
        ]
    }

    static var customScanPaths: [String] {
        // Use Application Support directory instead of ~/.config/mole
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return [] }

        let configPath = appSupport.appendingPathComponent("MoleUI/purge_paths").path
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return [] }
        let home = NSHomeDirectory()
        return content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.hasPrefix("~/") ? home + $0.dropFirst(1) : $0 }
    }

    static var allScanPaths: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for p in defaultScanPaths + customScanPaths where seen.insert(p).inserted {
            result.append(p)
        }
        return result
    }

    static let minAgeDays = 7
    static let maxScanDepth = 6
}

// MARK: - Model

@Observable @MainActor
final class PurgeModel {
    var targets: [PurgeTarget] = []
    var isScanning: Bool = false
    var cleaningTarget: String?
    var completedTargets: Set<String> = []
    var errorMessage: String?

    func scan() async {
        isScanning = true
        errorMessage = nil
        completedTargets = []

        do {
            targets = try await scanWithMole().sorted { $0.sizeBytes > $1.sizeBytes }
        } catch {
            errorMessage = error.localizedDescription
            targets = []
        }
        isScanning = false
    }

    func deleteTarget(_ target: PurgeTarget) async {
        cleaningTarget = target.id
        do {
            try await deleteWithMole(target.path.path)
            completedTargets.insert(target.id)
            targets.removeAll { $0.id == target.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        cleaningTarget = nil
    }

    private func scanWithMole() async throws -> [PurgeTarget] {
        guard let root = CLIExecutor.findMoleRoot() else {
            throw CLIExecutor.ExecutionError.commandNotFound("mole")
        }

        // Sync MoleUI's custom paths to Mole Core's config location
        do {
            try syncCustomPathsToMoleConfig()
        } catch {
            // Silently fail - will fall back to default paths
        }

        let script = """
        set -euo pipefail
        ROOT=\(shellEscape(root.path))
        export XDG_CACHE_HOME="${TMPDIR:-/tmp}/moleui-cache"
        mkdir -p "$XDG_CACHE_HOME/mole"
        source "$ROOT/lib/core/common.sh"
        source "$ROOT/lib/clean/purge_shared.sh"
        source "$ROOT/lib/clean/project.sh"
        tmp=$(mktemp)
        for search in "${PURGE_SEARCH_PATHS[@]}"; do
          scan_purge_targets "$search" "$tmp"
        done
        while IFS= read -r path; do
          [[ -z "$path" || ! -d "$path" ]] && continue
          size_kb=$(get_path_size_kb "$path" 2>/dev/null || echo 0)
          [[ "$size_kb" =~ ^[0-9]+$ ]] || size_kb=0
          [[ "$size_kb" -le 0 ]] && continue
          mtime=$(get_file_mtime "$path" 2>/dev/null || echo 0)
          now=$(get_epoch_seconds)
          if [[ "$mtime" =~ ^[0-9]+$ && "$mtime" -gt 0 ]]; then
            age_days=$(((now - mtime) / 86400))
          else
            age_days=9999
          fi
          [[ "$age_days" -lt 0 ]] && age_days=0
          project_name=$(basename "$(dirname "$path")")
          artifact_name=$(basename "$path")
          printf '%s|%s|%s|%s|%s\\n' "$path" "$size_kb" "$age_days" "$project_name" "$artifact_name"
        done < "$tmp"
        rm -f "$tmp"
        """

        let output = try await CLIExecutor.run("bash -lc \(shellEscape(script))")
        return output
            .split(separator: "\n")
            .compactMap { line -> PurgeTarget? in
                let parts = line.split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count >= 5 else { return nil }
                let path = String(parts[0])
                let sizeKB = UInt64(parts[1]) ?? 0
                let ageDays = Int(parts[2]) ?? 0
                let projectName = String(parts[3])
                let artifactName = String(parts[4])
                return PurgeTarget(
                    path: URL(fileURLWithPath: path),
                    projectName: projectName,
                    artifactName: artifactName,
                    sizeBytes: sizeKB * 1024,
                    ageDays: ageDays
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

    private func syncCustomPathsToMoleConfig() throws {
        // Read from MoleUI's config
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        let moleUIConfig = appSupport.appendingPathComponent("MoleUI/purge_paths")
        let moleUIContent = (try? String(contentsOf: moleUIConfig, encoding: .utf8)) ?? ""

        // Write to Mole Core's config location
        let moleConfigDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/mole")
        let moleConfig = moleConfigDir.appendingPathComponent("purge_paths")

        try FileManager.default.createDirectory(at: moleConfigDir, withIntermediateDirectories: true)
        try moleUIContent.write(to: moleConfig, atomically: true, encoding: .utf8)
    }
}
