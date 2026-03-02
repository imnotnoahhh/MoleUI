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
        id = path.path
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
        let configPath = NSHomeDirectory() + "/.config/mole/purge_paths"
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

        let results = await Task.detached { () -> [PurgeTarget] in
            Self.findArtifacts()
        }.value

        targets = results.sorted { $0.sizeBytes > $1.sizeBytes }
        isScanning = false
    }

    func deleteTarget(_ target: PurgeTarget) async {
        cleaningTarget = target.id
        do {
            _ = try await CLIExecutor.run("rm -rf \(shellEscape(target.path.path))")
            completedTargets.insert(target.id)
            targets.removeAll { $0.id == target.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        cleaningTarget = nil
    }

    func deleteSelected(ids: Set<String>) async {
        for target in targets where ids.contains(target.id) {
            await deleteTarget(target)
        }
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private nonisolated static func findArtifacts() -> [PurgeTarget] {
        let fm = FileManager.default
        let artifactSet = Set(PurgeConstants.artifactNames)
        var results: [PurgeTarget] = []
        let now = Date()

        for scanPath in PurgeConstants.allScanPaths {
            let rootURL = URL(fileURLWithPath: scanPath)
            guard fm.fileExists(atPath: scanPath) else { continue }

            guard let enumerator = fm.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: []
            ) else { continue }

            for case let url as URL in enumerator {
                guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey]) else { continue }
                guard vals.isDirectory == true else { continue }

                let name = url.lastPathComponent

                if name == ".git" || name == "Library" || name == ".Trash" || name == "Applications" {
                    enumerator.skipDescendants()
                    continue
                }

                let relComponents = url.pathComponents.count - rootURL.pathComponents.count
                if relComponents > PurgeConstants.maxScanDepth {
                    enumerator.skipDescendants()
                    continue
                }

                guard artifactSet.contains(name) else { continue }
                enumerator.skipDescendants()

                if PurgeConstants.protectedArtifacts.contains(name) {
                    let parent = url.deletingLastPathComponent()
                    if name == "vendor" {
                        if !fm.fileExists(atPath: parent.appendingPathComponent("composer.json").path) {
                            continue
                        }
                    } else if name == "bin" {
                        let siblings = (try? fm.contentsOfDirectory(atPath: parent.path)) ?? []
                        let hasDotnet = siblings.contains { file in PurgeConstants.dotnetIndicators.contains(where: { ext in file.hasSuffix(ext) }) }
                        if !hasDotnet { continue }
                    }
                }

                let parentPath = url.deletingLastPathComponent()
                let parentContents = (try? fm.contentsOfDirectory(atPath: parentPath.path)) ?? []
                let hasIndicator = parentContents.contains { PurgeConstants.projectIndicators.contains($0) }
                if !hasIndicator { continue }

                let size = directorySize(at: url, fm: fm)
                if size == 0 { continue }

                let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
                let ageDays = max(0, Int(now.timeIntervalSince(modDate) / 86400))

                results.append(PurgeTarget(
                    path: url, projectName: parentPath.lastPathComponent,
                    artifactName: name, sizeBytes: size, ageDays: ageDays
                ))
            }
        }
        return results
    }

    private nonisolated static func directorySize(at url: URL, fm: FileManager) -> UInt64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
            ) else { continue }
            total += UInt64(vals.totalFileAllocatedSize ?? vals.fileSize ?? 0)
        }
        return total
    }
}
