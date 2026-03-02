import Foundation
import Observation

// MARK: - Clean Category

struct CleanCategory: Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String
    let paths: [String]
    let excludePaths: [String]
    let moleCommand: String

    init(
        id: String, name: String, icon: String,
        paths: [String], excludePaths: [String] = [],
        moleCommand: String
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.paths = paths
        self.excludePaths = excludePaths
        self.moleCommand = moleCommand
    }

    private static let home = NSHomeDirectory()

    /// Paths excluded from "System Caches" to avoid double-counting with other categories.
    private static let browserCachePrefixes: [String] = [
        home + "/Library/Caches/com.apple.Safari",
        home + "/Library/Caches/Google",
        home + "/Library/Caches/Firefox",
        home + "/Library/Caches/com.brave.Browser",
        home + "/Library/Caches/com.microsoft.edgemac",
        home + "/Library/Caches/com.operasoftware.Opera",
    ]

    private static let devCachePrefixes: [String] = [
        home + "/Library/Caches/Homebrew",
        home + "/Library/Caches/pip",
        home + "/Library/Caches/CocoaPods",
        home + "/Library/Caches/go-build",
        home + "/Library/Caches/com.apple.dt.Xcode",
        home + "/Library/Caches/com.microsoft.VSCode",
        home + "/Library/Caches/com.sublimetext",
        home + "/Library/Caches/Google/AndroidStudio",
        home + "/Library/Caches/deno",
        // Database / API / debug tools
        home + "/Library/Caches/com.postmanlabs.mac",
        home + "/Library/Caches/com.konghq.insomnia",
        home + "/Library/Caches/com.tinyapp.TablePlus",
        home + "/Library/Caches/com.charlesproxy.charles",
        home + "/Library/Caches/com.proxyman.NSProxy",
        home + "/Library/Caches/com.mongodb.compass",
    ]

    static let allCategories: [CleanCategory] = [
        // MARK: System & App Caches

        CleanCategory(
            id: "system_caches", name: "System Caches", icon: "folder.badge.gearshape",
            paths: [
                // Broad user cache directory
                home + "/Library/Caches",
                // Application Support caches (Discord, Slack, Steam, Teams, etc.)
                home + "/Library/Application Support/discord/Cache",
                home + "/Library/Application Support/legcord/Cache",
                home + "/Library/Application Support/Slack/Cache",
                home + "/Library/Application Support/Microsoft/Teams/Cache",
                home + "/Library/Application Support/Microsoft/Teams/Application Cache",
                home + "/Library/Application Support/Microsoft/Teams/Code Cache",
                home + "/Library/Application Support/Microsoft/Teams/GPUCache",
                home + "/Library/Application Support/Microsoft/Teams/logs",
                home + "/Library/Application Support/Microsoft/Teams/tmp",
                home + "/Library/Application Support/Steam/htmlcache",
                home + "/Library/Application Support/Steam/appcache",
                home + "/Library/Application Support/Steam/depotcache",
                home + "/Library/Application Support/Steam/steamapps/shadercache",
                home + "/Library/Application Support/Steam/logs",
                home + "/Library/Application Support/Battle.net/Cache",
                home + "/Library/Application Support/com.bohemiancoding.sketch3/cache",
                home + "/Library/Application Support/Adobe/Common/Media Cache Files",
                home + "/Library/Application Support/iDingTalk/log",
                home + "/Library/Application Support/iDingTalk/holmeslogs",
                home + "/Library/Application Support/Quark/Cache/videoCache",
                home + "/Library/Application Support/minecraft/logs",
                home + "/Library/Application Support/minecraft/crash-reports",
                home + "/Library/Application Support/minecraft/webcache",
                home + "/Library/Application Support/minecraft/webcache2",
                // Claude / Antigravity / Filo Electron caches
                home + "/Library/Application Support/Claude/Cache",
                home + "/Library/Application Support/Claude/Code Cache",
                home + "/Library/Application Support/Claude/GPUCache",
                home + "/Library/Application Support/Antigravity/Cache",
                home + "/Library/Application Support/Antigravity/Code Cache",
                home + "/Library/Application Support/Antigravity/GPUCache",
                home + "/Library/Application Support/Filo/production/Cache",
                home + "/Library/Application Support/Filo/production/Code Cache",
                home + "/Library/Application Support/Filo/production/GPUCache",
                // Cloud storage caches
                home + "/Library/Application Support/Microsoft/OneDrive/Cache",
                home + "/Library/Application Support/Dropbox/cache",
                // Office container caches
                home + "/Library/Containers/com.microsoft.Word/Data/Library/Caches",
                home + "/Library/Containers/com.microsoft.Excel/Data/Library/Caches",
                home + "/Library/Containers/com.microsoft.Powerpoint/Data/Library/Caches",
                home + "/Library/Containers/com.microsoft.Outlook/Data/Library/Caches",
                // Podcasts temp media
                home + "/Library/Containers/com.apple.podcasts/Data/tmp/StreamedMedia",
                // Mail downloads
                home + "/Library/Mail Downloads",
                home + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
                // Saved application state
                home + "/Library/Saved Application State",
                // Lunar Client
                home + "/.lunarclient/game-cache",
                home + "/.lunarclient/launcher-cache",
                home + "/.lunarclient/logs",
            ],
            excludePaths: browserCachePrefixes + devCachePrefixes,
            moleCommand: "clean caches"
        ),

        // MARK: Browser Caches

        CleanCategory(
            id: "browser_caches", name: "Browser Caches", icon: "globe",
            paths: [
                // ~/Library/Caches browser entries
                home + "/Library/Caches/com.apple.Safari",
                home + "/Library/Caches/Google",
                home + "/Library/Caches/Firefox",
                home + "/Library/Caches/com.brave.Browser",
                home + "/Library/Caches/com.microsoft.edgemac",
                home + "/Library/Caches/com.operasoftware.Opera",
                // Browser profile caches (Application Support)
                home + "/Library/Application Support/Google Chrome/Default/Cache",
                home + "/Library/Application Support/Google Chrome/Default/Code Cache",
                home + "/Library/Application Support/Google Chrome/Default/Service Worker/Cache",
                home + "/Library/Application Support/Google Chrome/Default/GPUCache",
                home + "/Library/Application Support/Google Chrome/Default/DawnGraphiteCache",
                home + "/Library/Application Support/Google Chrome/Default/DawnWebGPUCache",
                home + "/Library/Application Support/Firefox/Profiles",
            ],
            moleCommand: "clean caches"
        ),

        // MARK: Developer Tools

        CleanCategory(
            id: "dev_tools", name: "Developer Tools", icon: "hammer",
            paths: [
                // Xcode & iOS
                home + "/Library/Developer/Xcode/DerivedData",
                home + "/Library/Developer/Xcode/Archives",
                home + "/Library/Developer/Xcode/Products",
                home + "/Library/Developer/Xcode/DocumentationCache",
                home + "/Library/Developer/Xcode/DocumentationIndex",
                home + "/Library/Developer/Xcode/iOS Device Logs",
                home + "/Library/Developer/Xcode/watchOS Device Logs",
                home + "/Library/Developer/Xcode/UserData/IB Support",
                home + "/Library/Developer/CoreSimulator/Caches",
                home + "/Library/Developer/CoreSimulator/Devices",
                home + "/Library/Caches/com.apple.dt.Xcode",
                home + "/Library/Logs/CoreSimulator",
                // npm / pnpm / yarn / bun
                home + "/.npm",
                home + "/.tnpm",
                home + "/Library/pnpm/store",
                home + "/.yarn/cache",
                home + "/.bun/install/cache",
                // Python
                home + "/Library/Caches/pip",
                home + "/.cache/uv",
                home + "/.cache/ruff",
                home + "/.cache/mypy",
                home + "/.cache/poetry",
                home + "/.pyenv/cache",
                home + "/.pytest_cache",
                home + "/.jupyter/runtime",
                home + "/.cache/huggingface",
                home + "/.cache/torch",
                home + "/.cache/tensorflow",
                home + "/.cache/wandb",
                home + "/.conda/pkgs",
                home + "/anaconda3/pkgs",
                // Go / Rust
                home + "/Library/Caches/go-build",
                home + "/.cargo/registry/cache",
                home + "/.cargo/git",
                home + "/.rustup/downloads",
                // JVM: Gradle / Maven / sbt / Ivy
                home + "/.gradle/caches",
                home + "/.gradle/daemon",
                home + "/.m2/repository",
                home + "/.sbt",
                home + "/.ivy2/cache",
                // CocoaPods / SPM
                home + "/Library/Caches/CocoaPods",
                home + "/.cache/swift-package-manager",
                // Docker
                home + "/.docker/buildx/cache",
                // Frontend build tools
                home + "/.cache/typescript",
                home + "/.cache/electron",
                home + "/.cache/node-gyp",
                home + "/.node-gyp",
                home + "/.turbo/cache",
                home + "/.vite/cache",
                home + "/.cache/vite",
                home + "/.cache/webpack",
                home + "/.parcel-cache",
                home + "/.cache/eslint",
                home + "/.cache/prettier",
                // Mobile dev
                home + "/.android/build-cache",
                home + "/.android/cache",
                home + "/Library/Caches/Google/AndroidStudio",
                home + "/.expo",
                // Other languages
                home + "/.bundle/cache", // Ruby
                home + "/.composer/cache", // PHP
                home + "/.nuget/packages", // .NET
                home + "/.cache/bazel",
                home + "/.cache/zig",
                home + "/Library/Caches/deno",
                home + "/.hex/cache", // Elixir
                home + "/.cabal/packages", // Haskell
                home + "/.opam/download-cache", // OCaml
                // Cloud CLIs
                home + "/.kube/cache",
                home + "/.aws/cli/cache",
                home + "/.config/gcloud/logs",
                home + "/.azure/logs",
                home + "/.cache/terraform",
                // CI/CD
                home + "/.cache/pre-commit",
                home + "/.cache/gitlab-runner",
                home + "/.sonar",
                // Editors
                home + "/Library/Application Support/Code/CachedData",
                home + "/Library/Application Support/Code/CachedExtensions",
                home + "/Library/Application Support/Code/Cache",
                home + "/Library/Application Support/Code/logs",
                home + "/Library/Caches/com.microsoft.VSCode",
                home + "/Library/Caches/com.sublimetext",
                // Database / API tools
                home + "/Library/Caches/com.postmanlabs.mac",
                home + "/Library/Caches/com.konghq.insomnia",
                home + "/Library/Caches/com.tinyapp.TablePlus",
                home + "/Library/Caches/com.charlesproxy.charles",
                home + "/Library/Caches/com.proxyman.NSProxy",
                home + "/Library/Caches/com.mongodb.compass",
                // Shell / VCS
                home + "/.oh-my-zsh/cache",
                home + "/.cache/curl",
                home + "/.cache/wget",
            ],
            moleCommand: "clean dev"
        ),

        // MARK: System Logs & Temp

        CleanCategory(
            id: "system_logs", name: "System Logs", icon: "doc.text",
            paths: [
                home + "/Library/Logs",
                // Adobe third-party logs
                "/Library/Logs/Adobe",
                "/Library/Logs/CreativeCloud",
                // Crash reports
                "/Library/Logs/DiagnosticReports",
                // Shell history / temp files
                home + "/.zcompdump",
                home + "/.lesshst",
                home + "/.viminfo.tmp",
                home + "/.wget-hsts",
                home + "/.cacher/logs",
                home + "/.kite/logs",
            ],
            moleCommand: "clean system"
        ),
        CleanCategory(
            id: "homebrew", name: "Homebrew Cache", icon: "mug",
            paths: [home + "/Library/Caches/Homebrew"],
            moleCommand: "clean brew"
        ),
        CleanCategory(
            id: "trash", name: "Trash", icon: "trash",
            paths: [home + "/.Trash"],
            moleCommand: "clean trash"
        ),
    ]
}

// MARK: - Scan Result

struct CleanScanResult: Identifiable, Sendable {
    let id: String
    let category: CleanCategory
    let totalBytes: UInt64
    let itemCount: Int
}

// MARK: - Model

// MARK: - Clean Service

@Observable @MainActor
final class CleanModel {
    var scanResults: [CleanScanResult] = []
    var isScanning: Bool = false
    var cleaningCategory: String?
    var completedCategories: Set<String> = []
    var errorMessage: String?
    var needsFullDiskAccess: Bool = false
    var lastOutput: String?

    init() {}

    /// Check if the app has Full Disk Access by trying to read ~/.Trash.
    nonisolated static func checkFullDiskAccess() -> Bool {
        let trashURL = URL(fileURLWithPath: NSHomeDirectory() + "/.Trash")
        return (try? FileManager.default.contentsOfDirectory(
            at: trashURL, includingPropertiesForKeys: nil
        )) != nil
    }

    // MARK: - Scan

    func scan() async {
        isScanning = true
        errorMessage = nil
        completedCategories = []
        needsFullDiskAccess = !Self.checkFullDiskAccess()

        let categories = CleanCategory.allCategories
        var results: [CleanScanResult] = []

        for category in categories {
            let result = await scanCategory(category)
            results.append(result)
        }

        scanResults = results
        isScanning = false
    }

    private func scanCategory(_ category: CleanCategory) async -> CleanScanResult {
        let excludePaths = category.excludePaths
        let result = await Task.detached { () -> (UInt64, Int) in
            var totalBytes: UInt64 = 0
            var itemCount = 0
            let fm = FileManager.default

            for path in category.paths {
                let url = URL(fileURLWithPath: path)
                let (bytes, count) = Self.directorySize(at: url, excludePaths: excludePaths, fm: fm)
                totalBytes += bytes
                itemCount += count
            }
            return (totalBytes, itemCount)
        }.value

        return CleanScanResult(
            id: category.id,
            category: category,
            totalBytes: result.0,
            itemCount: result.1
        )
    }

    // MARK: - Directory Size Helper

    private nonisolated static func directorySize(
        at url: URL,
        excludePaths: [String] = [],
        fm: FileManager = .default
    ) -> (bytes: UInt64, count: Int) {
        var totalBytes: UInt64 = 0
        var itemCount = 0

        guard fm.fileExists(atPath: url.path) else { return (0, 0) }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey],
            options: [] // include hidden files and package descendants
        ) else {
            return (0, 0)
        }

        for case let fileURL as URL in enumerator {
            let filePath = fileURL.path

            // Skip excluded subtrees
            if excludePaths.contains(where: { filePath.hasPrefix($0) }) {
                continue
            }

            guard let values = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey, .isDirectoryKey]
            ) else { continue }

            if values.isDirectory == true { continue }

            // Prefer allocated size (matches `du`), fall back to logical size
            let size = values.totalFileAllocatedSize ?? values.fileSize ?? 0
            totalBytes += UInt64(size)
            itemCount += 1
        }

        return (totalBytes, itemCount)
    }

    // MARK: - Clean

    func clean(category: CleanScanResult, dryRun: Bool) async {
        cleaningCategory = category.id
        errorMessage = nil
        lastOutput = nil

        do {
            if dryRun {
                // Dry run: show what would be cleaned
                let previewText = await generatePreview(category: category)
                lastOutput = previewText
                completedCategories.insert(category.id)
            } else if category.id == "trash" {
                // Trash: use Finder AppleScript (handles permissions correctly)
                _ = try await CLIExecutor.run(
                    "osascript -e 'tell application \"Finder\" to empty trash'"
                )
                completedCategories.insert(category.id)
            } else if category.id == "homebrew" {
                // Homebrew: use brew cleanup
                let output = try await CLIExecutor.run("brew cleanup --prune=all 2>&1 || true")
                lastOutput = output
                completedCategories.insert(category.id)
            } else {
                // Other categories: remove contents of each path directly
                try await cleanPaths(category.category.paths)
                lastOutput = "Cleaned \(category.category.name): \(category.itemCount) items removed"
                completedCategories.insert(category.id)
            }

            // Re-scan to update sizes
            let updated = await scanCategory(category.category)
            if let idx = scanResults.firstIndex(where: { $0.id == category.id }) {
                scanResults[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        cleaningCategory = nil
    }

    private func generatePreview(category: CleanScanResult) async -> String {
        var lines: [String] = []
        lines.append("Preview: \(category.category.name)")
        lines.append("Would clean \(category.itemCount) items (\(MetricsFormatter.humanBytes(category.totalBytes)))")
        lines.append("")
        lines.append("Paths:")
        for path in category.category.paths {
            let fm = FileManager.default
            if fm.fileExists(atPath: path) {
                if let contents = try? fm.contentsOfDirectory(atPath: path) {
                    let count = contents.count
                    lines.append("  • \(path) (\(count) items)")
                } else {
                    lines.append("  • \(path)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Remove the contents of each path (not the directory itself).
    private func cleanPaths(_ paths: [String]) async throws {
        let fm = FileManager.default
        for path in paths {
            guard fm.fileExists(atPath: path) else { continue }
            // Remove contents inside the directory, keep the directory itself
            let cmd = "find \(shellEscape(path)) -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true"
            _ = try await CLIExecutor.run(cmd)
        }
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func cleanSelected(categories: Set<String>, dryRun: Bool) async {
        for result in scanResults where categories.contains(result.id) {
            await clean(category: result, dryRun: dryRun)
        }
    }
}
