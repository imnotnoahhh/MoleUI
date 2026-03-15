import Foundation
import Observation

// MARK: - Clean Category

struct CleanCategory: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let paths: [String]
    let excludePaths: [String]
    let moleCommand: String
    let safe: Bool // Safe to clean without user concern

    init(
        id: String, name: String, icon: String,
        paths: [String], excludePaths: [String] = [],
        moleCommand: String,
        safe: Bool = true // Default to safe
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.paths = paths
        self.excludePaths = excludePaths
        self.moleCommand = moleCommand
        self.safe = safe
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
            moleCommand: "clean dev",
            safe: false // May contain important build artifacts
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

struct CleanScanResult: Identifiable, Equatable {
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
    var lastOutput: String?
    var lastCleanedBytes: UInt64? // Track actual cleaned size

    /// Flag to indicate if a privileged clean operation is in progress.
    /// MetricsModel should pause refreshing when this is true to avoid resource contention.
    var isCleaningWithPrivileges: Bool = false

    init() {}

    // MARK: - Scan

    func scan() async {
        isScanning = true
        errorMessage = nil
        completedCategories = []

        // No longer calculate sizes - just show categories
        let categories = CleanCategory.allCategories
        scanResults = categories.map { category in
            CleanScanResult(
                id: category.id,
                category: category,
                totalBytes: 0,
                itemCount: 0
            )
        }

        isScanning = false
    }

    // MARK: - Clean

    func clean(category: CleanScanResult, dryRun: Bool) async {
        cleaningCategory = category.id
        errorMessage = nil
        lastOutput = nil

        do {
            // Execute the exact Mole subcommand mapped for this clean category.
            let subcommand = category.category.moleCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !subcommand.isEmpty else {
                throw CLIExecutor.ExecutionError.invalidOutput("Missing clean subcommand")
            }
            let output = try await CLIExecutor.runMole(subcommand, dryRun: dryRun)
            lastOutput = output
            completedCategories.insert(category.id)

            // No need to re-scan - we don't show sizes anymore
        } catch {
            errorMessage = error.localizedDescription
        }

        cleaningCategory = nil
    }

    /// Clean all categories at once using mole clean command
    func cleanAll(dryRun: Bool) async {
        cleaningCategory = "all"
        errorMessage = nil
        lastOutput = nil
        lastCleanedBytes = nil

        // Set flag to pause metrics refresh during privileged operations
        if !dryRun {
            isCleaningWithPrivileges = true
        }

        defer {
            cleaningCategory = nil
            isCleaningWithPrivileges = false
        }

        do {
            let output: String
            if dryRun {
                // Dry run doesn't need sudo
                output = try await CLIExecutor.runMole("clean --dry-run", dryRun: true)
            } else {
                // Normal mode: use sudo
                guard let moleBinary = CLIExecutor.findMoleBinary() else {
                    throw NSError(
                        domain: "CleanModel",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Cannot find mole executable"]
                    )
                }
                let command = "'\(moleBinary.path)' clean"
                output = try await SudoHelper.runWithAdmin(command)
            }

            lastOutput = output

            // Parse output to extract cleaned size
            if let cleanedBytes = parseCleanedSize(from: output) {
                lastCleanedBytes = cleanedBytes
            }

            // Mark all categories as completed
            completedCategories = Set(scanResults.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Parse cleaned size from mole clean output
    private func parseCleanedSize(from output: String) -> UInt64? {
        // Look for patterns like:
        // "Space freed: 147KB"
        // "Space freed: 1.2MB"
        // "Space freed: 0.00GB" (when size is very small)
        // Strategy: Don't strip ANSI codes (causes data loss)
        // Instead: Find "Space freed" line, extract all number+unit pairs, take the last one

        let lines = output.components(separatedBy: .newlines)

        for line in lines where line.contains("Space freed") {
            // Find all number+unit combinations in this line
            let pattern = #"([\d.]+)(KB|MB|GB)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))

            // Take the last match (the actual freed size, not ANSI code numbers)
            if let lastMatch = matches.last,
               let sizeRange = Range(lastMatch.range(at: 1), in: line),
               let unitRange = Range(lastMatch.range(at: 2), in: line),
               let size = Double(line[sizeRange])
            {
                let unit = String(line[unitRange]).uppercased()

                return switch unit {
                case "KB":
                    UInt64(size * 1024)
                case "MB":
                    UInt64(size * 1024 * 1024)
                case "GB":
                    UInt64(size * 1024 * 1024 * 1024)
                default:
                    UInt64(0)
                }
            }
        }

        // Check if system was already clean
        if output.contains("already clean") || output.contains("no additional space freed") {
            return 0
        }

        return nil
    }

    private func generatePreview(category: CleanScanResult) -> String {
        var lines: [String] = []
        lines.append("Preview: \(category.category.name)")
        lines.append("Would clean \(category.itemCount) items (\(MetricsFormatter.humanBytes(category.totalBytes)))")
        lines.append("")
        lines.append("Paths:")
        for path in category.category.paths where FileManager.default.fileExists(atPath: path) {
            lines.append("  • \(path)")
        }
        return lines.joined(separator: "\n")
    }

    /// Clean all selected categories sequentially through Mole CLI.
    func cleanSelected(categories: Set<String>, dryRun: Bool) async {
        guard !categories.isEmpty else { return }
        let selected = scanResults.filter { categories.contains($0.id) }
        for category in selected {
            await clean(category: category, dryRun: dryRun)
        }
    }

    // MARK: - Mole Core Scan

    private func scanCategoryWithMoleCore(_ category: CleanCategory) async throws -> (bytes: UInt64, count: Int) {
        let subcommand = category.moleCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subcommand.isEmpty else {
            return (bytes: 0, count: 0)
        }

        guard let root = CLIExecutor.findMoleRoot() else {
            return (bytes: 0, count: 0)
        }

        // We use Mole's core functions to compute sizes accurately without hanging the UI
        let pathsList = category.paths.map { shellEscape($0) }.joined(separator: " ")
        _ = category.excludePaths.map { shellEscape($0) }.joined(separator: " ")

        let script = """
        set -euo pipefail
        ROOT=\(shellEscape(root.path))
        source "$ROOT/lib/core/common.sh"

        total_kb=0
        total_files=0

        # Check an array of paths and sum them using Mole's get_path_size_kb
        check_paths() {
            local search_paths=("$@")
            for path in "${search_paths[@]}"; do
                if [[ -e "$path" ]]; then
                    # Get size in KB
                    size_kb=$(get_path_size_kb "$path" 2>/dev/null || echo 0)
                    if [[ "$size_kb" =~ ^[0-9]+$ && "$size_kb" -gt 0 ]]; then
                        total_kb=$((total_kb + size_kb))
                    fi
                    
                    # Estimate file count simply
                    if [[ -d "$path" ]]; then
                        files=$(find "$path" -type f 2>/dev/null | wc -l || echo 0)
                        # Remove leading whitespace from wc
                        files=$(echo "$files" | tr -d ' ')
                    else
                        files=1
                    fi
                    
                    if [[ "$files" =~ ^[0-9]+$ && "$files" -gt 0 ]]; then
                        total_files=$((total_files + files))
                    fi
                fi
            done
        }

        # Only process if we have paths
        if [[ -n "\(pathsList)" ]]; then
           eval "scan_paths=(\(pathsList))"
           check_paths "${scan_paths[@]}"
        fi

        # Output result
        echo "$total_kb|$total_files"
        """

        let output = try await CLIExecutor.run("bash -lc \(shellEscape(script))")
        let lines = output.split(separator: "\n").map { String($0) }

        for line in lines {
            let parts = line.split(separator: "|")
            if parts.count == 2, let kb = UInt64(parts[0]), let count = Int(parts[1]) {
                return (bytes: kb * 1024, count: count)
            }
        }

        return (bytes: 0, count: 0)
    }

    private func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
