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
    var errorMessage: String?

    // Cache
    private var cachedApps: [AppInfo] = []
    private var cacheTimestamp: Date?
    private var cachedModificationDate: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    var lastScanTime: Date? {
        cacheTimestamp
    }

    init() {}

    func scan() {
        // Check if cache is valid
        if !cachedApps.isEmpty,
           let cacheTime = cacheTimestamp,
           let cachedModDate = cachedModificationDate
        {
            let cacheAge = Date().timeIntervalSince(cacheTime)
            let isCacheValid = cacheAge < cacheValidityDuration

            // Check if /Applications directory has been modified
            let applicationsPath = "/Applications"
            if let currentModDate = try? FileManager.default.attributesOfItem(atPath: applicationsPath)[.modificationDate] as? Date {
                let isDirectoryUnmodified = cachedModDate == currentModDate

                if isCacheValid, isDirectoryUnmodified {
                    // Use cached data
                    apps = cachedApps
                    return
                }
            }
        }

        // Cache miss or invalid - perform scan
        performScan()
    }

    private func performScan() {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        apps = []

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let scanned = try performScanSync()
                let applicationsPath = "/Applications"
                let modDate = try? FileManager.default.attributesOfItem(atPath: applicationsPath)[.modificationDate] as? Date

                await MainActor.run {
                    self.apps = scanned
                    self.cachedApps = scanned
                    self.cacheTimestamp = Date()
                    self.cachedModificationDate = modDate
                    self.isScanning = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isScanning = false
                }
            }
        }
    }

    /// Manually refresh (clear cache and rescan)
    func refresh() {
        cachedApps = []
        cacheTimestamp = nil
        cachedModificationDate = nil
        performScan()
    }

    private nonisolated func performScanSync() throws -> [AppInfo] {
        guard let root = CLIExecutor.findMoleRoot() else { return [] }
        let command = """
        bash -lc \(shellEscape("""
        set -euo pipefail
        export MOLE_TEST_MODE=1
        ROOT=\(shellEscape(root.path))
        tmp_script=$(mktemp "${TMPDIR:-/tmp}/mole-uninstall-nomain.XXXXXX")
        awk '$0 != "main \\\"$@\\\""' "$ROOT/bin/uninstall.sh" | sed "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\\"$ROOT/bin\\"|" > "$tmp_script"
        source "$tmp_script"
        apps_file=$(scan_applications)
        cat "$apps_file"
        rm -f "$apps_file" "$tmp_script"
        """))
        """

        let output = try runSync(command: command)
        var results: [AppInfo] = []

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 7 else { continue }
            let epoch = TimeInterval(parts[0]) ?? 0
            let path = String(parts[1])
            let displayName = String(parts[2])
            let bundleIdRaw = String(parts[3])
            let sizeKB = UInt64(parts[6]) ?? 0
            let appURL = URL(fileURLWithPath: path)

            guard FileManager.default.fileExists(atPath: path) else { continue }
            let bundle = Bundle(url: appURL)
            let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String
            let icon = NSWorkspace.shared.icon(forFile: path)
            let bundleId = (bundleIdRaw.isEmpty || bundleIdRaw == "unknown") ? bundle?.bundleIdentifier : bundleIdRaw
            let lastUsed = epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil

            results.append(AppInfo(
                name: displayName,
                bundleIdentifier: bundleId,
                version: version,
                sizeBytes: sizeKB * 1024,
                icon: icon,
                path: appURL,
                lastUsed: lastUsed
            ))
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private nonisolated func runSync(command: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-lc", command]
        let out = Pipe()
        proc.standardOutput = out
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Error"
            throw NSError(domain: "AppScanError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Scan failed (\(proc.terminationStatus)): \(errStr)"])
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private nonisolated func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
        guard let root = CLIExecutor.findMoleRoot() else { return [] }
        let bundleID = app.bundleIdentifier ?? "unknown"
        let script = """
        set -euo pipefail
        export MOLE_TEST_MODE=1
        ROOT=\(shellEscape(root.path))
        BUNDLE_ID=\(shellEscape(bundleID))
        APP_NAME=\(shellEscape(app.name))
        source "$ROOT/lib/core/common.sh"
        source "$ROOT/lib/core/app_protection.sh"
        find_app_files "$BUNDLE_ID" "$APP_NAME" || true
        find_app_system_files "$BUNDLE_ID" "$APP_NAME" || true
        """
        let output = (try? runSync("bash -lc \(shellEscape(script))")) ?? ""
        var seen = Set<String>()
        return output
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .map { URL(fileURLWithPath: $0) }
    }

    func uninstall(app: AppInfo, relatedFiles: [URL]) async throws {
        isUninstalling = true
        errorMessage = nil
        defer { isUninstalling = false }

        _ = relatedFiles // related files are resolved by Mole core during batch uninstall.
        guard let root = CLIExecutor.findMoleRoot() else {
            throw CLIExecutor.ExecutionError.commandNotFound("mole")
        }
        let bundleID = app.bundleIdentifier ?? "unknown"
        let selected = "0|\(app.path.path)|\(app.name)|\(bundleID)|0|Unknown|0"
        let script = """
        set -euo pipefail
        export MOLE_TEST_MODE=1
        ROOT=\(shellEscape(root.path))
        APP_ENTRY=\(shellEscape(selected))
        tmp_script=$(mktemp "${TMPDIR:-/tmp}/mole-uninstall-nomain.XXXXXX")
        awk '$0 != "main \\"$@\\"" {print}' "$ROOT/bin/uninstall.sh" | sed "s|^SCRIPT_DIR=.*|SCRIPT_DIR=\\"$ROOT/bin\\"|" > "$tmp_script"
        source "$tmp_script"
        selected_apps=("$APP_ENTRY")
        printf '\\n' | batch_uninstall_applications
        rm -f "$tmp_script"
        """
        _ = try await CLIExecutor.run("bash -lc \(shellEscape(script))")

        uninstalledApps.insert(app.id)
    }

    private nonisolated func runSync(_ command: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-lc", command]
        let out = Pipe()
        proc.standardOutput = out
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown Error"
            throw NSError(domain: "UninstallError", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Command failed (\(proc.terminationStatus)): \(errStr)"])
        }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private nonisolated func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
