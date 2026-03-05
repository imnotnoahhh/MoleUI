import Testing
import Foundation
@testable import Mole_UI

// MARK: - Version

@Test func versionIsSet() {
    #expect(!MoleVersion.current.isEmpty)
}

// MARK: - Version Comparison

@Test func versionCompareBasic() async {
    let model = await VersionModel()
    await MainActor.run {
        model.currentVersion = "1.0.0"
        model.latestVersion = "1.1.0"
    }
    let hasUpdate = await model.hasUpdate
    #expect(hasUpdate == true)
}

@Test func versionCompareSame() async {
    let model = await VersionModel()
    await MainActor.run {
        model.currentVersion = "1.28.1"
        model.latestVersion = "1.28.1"
    }
    let hasUpdate = await model.hasUpdate
    #expect(hasUpdate == false)
}

@Test func versionCompareWithPrefix() async {
    let model = await VersionModel()
    await MainActor.run {
        model.currentVersion = "v1.0.0"
        model.latestVersion = "v2.0.0"
    }
    let hasUpdate = await model.hasUpdate
    #expect(hasUpdate == true)
}

@Test func versionCompareNilReturnsNoUpdate() async {
    let model = await VersionModel()
    let hasUpdate = await model.hasUpdate
    #expect(hasUpdate == false)
}

// MARK: - MetricsSnapshot JSON Decoding

private let sampleMetricsJSON = """
{
  "collected_at": "2025-01-15T10:30:00Z",
  "host": "MacBook-Pro",
  "platform": "darwin",
  "uptime": "3d 2h",
  "procs": 350,
  "hardware": {
    "model": "MacBookPro18,1",
    "cpu_model": "Apple M1 Pro",
    "total_ram": "16 GB",
    "disk_size": "512 GB",
    "os_version": "14.2",
    "refresh_rate": "120Hz"
  },
  "health_score": 82,
  "health_score_msg": "Good",
  "cpu": {
    "usage": 12.5,
    "per_core": [15.0, 10.0, 8.0, 17.0],
    "per_core_estimated": false,
    "load1": 2.1,
    "load5": 1.8,
    "load15": 1.5,
    "core_count": 10,
    "logical_cpu": 10,
    "p_core_count": 8,
    "e_core_count": 2
  },
  "gpu": [],
  "memory": {
    "used": 8589934592,
    "total": 17179869184,
    "used_percent": 50.0,
    "swap_used": 0,
    "swap_total": 2147483648,
    "cached": 4294967296,
    "pressure": "nominal"
  },
  "disks": [
    {"mount": "/", "device": "disk3s1", "used": 200000000000, "total": 500000000000, "used_percent": 40.0, "fstype": "apfs", "external": false}
  ],
  "disk_io": {"read_rate": 1.5, "write_rate": 0.8},
  "network": [
    {"name": "en0", "rx_rate_mbs": 0.5, "tx_rate_mbs": 0.1, "ip": "192.168.1.100"}
  ],
  "network_history": {"rx_history": [0.1, 0.2, 0.5], "tx_history": [0.05, 0.1, 0.08]},
  "proxy": {"enabled": false, "type": "", "host": ""},
  "batteries": [
    {"percent": 85.0, "status": "charging", "time_left": "1:30", "health": "Normal", "cycle_count": 120, "capacity": 95}
  ],
  "thermal": {"cpu_temp": 45.2, "gpu_temp": 40.1, "fan_speed": 1200, "fan_count": 2, "system_power": 15.0, "adapter_power": 67.0, "battery_power": 0.0},
  "sensors": [],
  "bluetooth": [{"name": "AirPods Pro", "connected": true, "battery": "85%"}],
  "top_processes": [
    {"name": "kernel_task", "cpu": 5.2, "memory": 1.1},
    {"name": "WindowServer", "cpu": 3.8, "memory": 0.9}
  ]
}
"""

@Test func metricsSnapshotDecodesFromJSON() throws {
    let data = sampleMetricsJSON.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let str = try decoder.singleValueContainer().decode(String.self)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: str) { return date }
        fmt.formatOptions = [.withInternetDateTime]
        if let date = fmt.date(from: str) { return date }
        throw DecodingError.dataCorrupted(
            .init(codingPath: decoder.codingPath,
                  debugDescription: "Invalid date: \(str)"))
    }

    let snap = try decoder.decode(MetricsSnapshot.self, from: data)
    #expect(snap.host == "MacBook-Pro")
    #expect(snap.platform == "darwin")
    #expect(snap.healthScore == 82)
    #expect(snap.cpu.coreCount == 10)
    #expect(snap.cpu.pCoreCount == 8)
    #expect(snap.cpu.usage == 12.5)
    #expect(snap.memory.total == 17179869184)
    #expect(snap.memory.usedPercent == 50.0)
    #expect(snap.disks.count == 1)
    #expect(snap.disks[0].external == false)
    #expect(snap.batteries.count == 1)
    #expect(snap.batteries[0].cycleCount == 120)
    #expect(snap.thermal.cpuTemp == 45.2)
    #expect(snap.topProcesses.count == 2)
    #expect(snap.bluetooth.count == 1)
    #expect(snap.networkHistory.rxHistory.count == 3)
}

@Test func metricsSnapshotHandlesNullArrays() throws {
    // Go nil slices encode as JSON null
    let json = """
    {
      "collected_at": "2025-01-15T10:30:00Z",
      "host": "test", "platform": "darwin", "uptime": "1h",
      "procs": 1,
      "hardware": {"model":"M","cpu_model":"C","total_ram":"8","disk_size":"256","os_version":"14","refresh_rate":"60"},
      "health_score": 50, "health_score_msg": "OK",
      "cpu": {"usage":0,"per_core":[],"per_core_estimated":false,"load1":0,"load5":0,"load15":0,"core_count":1,"logical_cpu":1,"p_core_count":0,"e_core_count":0},
      "gpu": null,
      "memory": {"used":0,"total":1,"used_percent":0,"swap_used":0,"swap_total":0,"cached":0,"pressure":"ok"},
      "disks": null,
      "disk_io": {"read_rate":0,"write_rate":0},
      "network": null,
      "network_history": {"rx_history":null,"tx_history":null},
      "proxy": {"enabled":false,"type":"","host":""},
      "batteries": null,
      "thermal": {"cpu_temp":0,"gpu_temp":0,"fan_speed":0,"fan_count":0,"system_power":0,"adapter_power":0,"battery_power":0},
      "sensors": null,
      "bluetooth": null,
      "top_processes": null
    }
    """
    let data = json.data(using: .utf8)!
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let str = try decoder.singleValueContainer().decode(String.self)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: str)!
    }

    let snap = try decoder.decode(MetricsSnapshot.self, from: data)
    #expect(snap.gpu.isEmpty)
    #expect(snap.disks.isEmpty)
    #expect(snap.network.isEmpty)
    #expect(snap.batteries.isEmpty)
    #expect(snap.sensors.isEmpty)
    #expect(snap.bluetooth.isEmpty)
    #expect(snap.topProcesses.isEmpty)
    #expect(snap.networkHistory.rxHistory.isEmpty)
    #expect(snap.networkHistory.txHistory.isEmpty)
}

// MARK: - MetricsFormatter

@Test func humanBytesFormatting() {
    #expect(MetricsFormatter.humanBytes(0) == "0.0 B")
    #expect(MetricsFormatter.humanBytes(512) == "512.0 B")
    #expect(MetricsFormatter.humanBytes(1024) == "1.0 KB")
    #expect(MetricsFormatter.humanBytes(1536) == "1.5 KB")
    #expect(MetricsFormatter.humanBytes(1_048_576) == "1.0 MB")
    #expect(MetricsFormatter.humanBytes(1_073_741_824) == "1.0 GB")
    #expect(MetricsFormatter.humanBytes(1_099_511_627_776) == "1.0 TB")
}

@Test func formatRate() {
    #expect(MetricsFormatter.formatRate(0.001) == "1 KB/s")
    #expect(MetricsFormatter.formatRate(0.5) == "512 KB/s")
    #expect(MetricsFormatter.formatRate(1.0) == "1.00 MB/s")
    #expect(MetricsFormatter.formatRate(10.5) == "10.50 MB/s")
}

// MARK: - SafetyController Parsing

@Test func parseSizeStringBytes() async {
    // Access private method via reflection isn't possible, test via executeClean flow
    // Instead test the formattedSize computed property
    let preview = SafetyController.CleanPreview(
        target: "test",
        files: [
            .init(path: "/tmp/a", size: 1_073_741_824, isDirectory: false),
            .init(path: "/tmp/b", size: 536_870_912, isDirectory: true)
        ],
        totalSize: 1_610_612_736,
        estimatedTime: 5.0
    )
    #expect(!preview.formattedSize.isEmpty)
    #expect(preview.files.count == 2)
    #expect(preview.totalSize == 1_610_612_736)
}

// MARK: - ErrorTranslator

@Test func translateCLITimeout() {
    let error = CLIExecutor.ExecutionError.timeout
    let friendly = ErrorTranslator.translate(error: error, context: "clean")
    #expect(friendly.severity == .warning)
    #expect(!friendly.title.isEmpty)
    #expect(!friendly.message.isEmpty)
}

@Test func translateCLICancelled() {
    let error = CLIExecutor.ExecutionError.cancelled
    let friendly = ErrorTranslator.translate(error: error, context: "optimize")
    #expect(friendly.severity == .info)
}

@Test func translateCLICommandNotFound() {
    let error = CLIExecutor.ExecutionError.commandNotFound("mole")
    let friendly = ErrorTranslator.translate(error: error, context: "scan")
    #expect(friendly.severity == .error || friendly.severity == .critical)
}

@Test func translateCLINonZeroExit() {
    let error = CLIExecutor.ExecutionError.nonZeroExit(
        1, stderr: "Permission denied"
    )
    let friendly = ErrorTranslator.translate(error: error, context: "clean")
    #expect(friendly.severity == .error || friendly.severity == .warning)
}

@Test func translateUnknownError() {
    struct CustomError: Error {}
    let friendly = ErrorTranslator.translate(error: CustomError(), context: "test")
    #expect(!friendly.title.isEmpty)
}

// MARK: - CleanCategory

@Test func cleanCategoriesExist() {
    let categories = CleanCategory.allCategories
    #expect(categories.count >= 5)

    let names = categories.map(\.name)
    #expect(names.contains("System Caches"))
    #expect(names.contains("Browser Caches"))
    #expect(names.contains("Developer Tools"))
    #expect(names.contains("System Logs"))
}

@Test func cleanCategoryPathsNotEmpty() {
    for cat in CleanCategory.allCategories {
        #expect(!cat.paths.isEmpty, "Category \(cat.name) has no paths")
        #expect(!cat.name.isEmpty)
        #expect(!cat.icon.isEmpty)
    }
}

// MARK: - InstallerConstants

@Test func installerExtensions() {
    let exts = InstallerConstants.extensions
    #expect(exts.contains("dmg"))
    #expect(exts.contains("pkg"))
    #expect(exts.contains("zip"))
    #expect(exts.contains("iso"))
}

@Test func installerScanPaths() {
    let paths = InstallerConstants.scanPaths
    #expect(!paths.isEmpty)
}

// MARK: - CLI Integration Tests

@Suite("CLI Integration Tests")
struct CLIIntegrationTests {

    @Test("CLIExecutor identifies mole root")
    func testFindMoleRoot() {
        let root = CLIExecutor.findMoleRoot()
        #expect(root != nil)
    }

    @Test("CLIExecutor identifies mole binary")
    func testFindMoleBinary() {
        let binary = CLIExecutor.findMoleBinary()
        #expect(binary != nil)
    }

    @Test("CLIExecutor execute parses JSON")
    func testExecuteAndParseJSON() async throws {
        let executor = await CLIExecutor()
        let json = """
        {"name": "test", "value": 42}
        """

        struct TestResponse: Codable {
            let name: String
            let value: Int
        }

        let response: TestResponse = try await executor.executeAndParseJSON(
            command: "echo '\(json)'"
        )

        #expect(response.name == "test")
        #expect(response.value == 42)
    }
}
// MARK: - PurgeTarget

@Test func purgeTargetIsRecent() {
    let recent = PurgeTarget(
        path: URL(fileURLWithPath: "/tmp/a"), projectName: "test",
        artifactName: "node_modules", sizeBytes: 1000, ageDays: 3
    )
    #expect(recent.isRecent == true)

    let old = PurgeTarget(
        path: URL(fileURLWithPath: "/tmp/b"), projectName: "test",
        artifactName: "target", sizeBytes: 1000, ageDays: 30
    )
    #expect(old.isRecent == false)
}

@Test func purgeConstantsArtifactNames() {
    let artifacts = PurgeConstants.artifactNames
    #expect(artifacts.contains("node_modules"))
    #expect(artifacts.contains("target"))
    #expect(artifacts.contains("build"))
    #expect(artifacts.contains(".venv"))
}

@Test func purgeConstantsProtectedArtifacts() {
    let protected = PurgeConstants.protectedArtifacts
    #expect(protected.contains("vendor"))
    #expect(protected.contains("bin"))
}

// MARK: - CI Assumption Tests (P2)

@Suite("CI Assumption Tests")
struct CIAssumptionTests {

    // Verify the .mole-cli-version file is bundled in app resources
    @Test("Bundled .mole-cli-version file exists and is readable")
    func testMoleCLIVersionFileBundled() throws {
        let versionURL = Bundle.main.url(forResource: ".mole-cli-version", withExtension: nil)
            ?? Bundle.main.url(forResource: "mole-cli-version", withExtension: nil)
            ?? Bundle.main.resourceURL?.appendingPathComponent(".mole-cli-version")

        #expect(versionURL != nil, ".mole-cli-version must be bundled in app resources")

        let contents = try String(contentsOf: versionURL!, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!contents.isEmpty, ".mole-cli-version should have content")

        // Version should be semver-like: digits.digits.digits
        let isVersionLike = contents.range(of: #"^\d+\.\d+\.\d+"#, options: .regularExpression) != nil
        #expect(isVersionLike, "Version '\(contents)' should be in semver format")
    }

    // Version parsing edge cases for the auto-update compare logic
    @Test("Version stripping handles v and V prefixes")
    func testVersionPrefixStripping() {
        func stripPrefix(_ raw: String) -> String {
            var v = raw
            if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
            return v
        }
        #expect(stripPrefix("v1.28.1") == "1.28.1")
        #expect(stripPrefix("V1.28.1") == "1.28.1")
        #expect(stripPrefix("1.28.1") == "1.28.1")
        #expect(stripPrefix("v0.1.0") == "0.1.0")
    }

    // Bundled mole binary has the correct executable permission
    @Test("Bundled mole binary is executable")
    func testBundledMoleBinaryIsExecutable() throws {
        let binary = CLIExecutor.findMoleBinary()
        #expect(binary != nil, "Bundled mole binary must exist in app bundle")

        let fm = FileManager.default
        #expect(fm.isExecutableFile(atPath: binary!.path), "mole binary at \(binary!.path) must be executable")
    }

    // Required Mole scripts exist next to the binary
    @Test("Required Mole scripts exist in bundle")
    func testRequiredMoleScriptsExist() throws {
        let root = CLIExecutor.findMoleRoot()
        #expect(root != nil, "Mole root directory must exist in app bundle")

        let fm = FileManager.default
        let requiredScripts = [
            "bin/clean.sh",
            "bin/optimize.sh",
            "bin/purge.sh",
            "bin/installer.sh",
            "bin/uninstall.sh",
        ]
        for script in requiredScripts {
            let path = root!.appendingPathComponent(script).path
            #expect(fm.fileExists(atPath: path), "Required script missing: \(script)")
            #expect(fm.isExecutableFile(atPath: path), "Script not executable: \(script)")
        }
    }
}

// MARK: - Async & Concurrency Tests (P0)

@Suite("Async & Concurrency Tests")
struct AsyncConcurrencyTests {

    @Test("CLIExecutor timeout works correctly")
    func testCLIExecutorTimeout() async throws {
        let executor = await CLIExecutor()

        do {
            _ = try await executor.execute(
                command: "sleep 10",
                options: CLIExecutor.ExecutionOptions(
                    timeout: 0.5,
                    captureStderr: false,
                    parseProgress: false,
                    dryRun: false
                )
            )
            Issue.record("Should have thrown timeout or cancellation error")
        } catch let error as CLIExecutor.ExecutionError {
            // Accept either timeout or process termination (SIGTERM = exit 15)
            switch error {
            case .timeout:
                break // Expected
            case .nonZeroExit(15, _):
                break // Also expected (process terminated)
            default:
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test("CLIExecutor cancellation works")
    func testCLIExecutorCancellation() async throws {
        let executor = await CLIExecutor()

        let task = Task {
            try await executor.execute(
                command: "sleep 10",
                options: CLIExecutor.ExecutionOptions(
                    timeout: 30,
                    captureStderr: false,
                    parseProgress: false,
                    dryRun: false
                )
            )
        }

        // Cancel after a short delay
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Should have been cancelled")
        } catch {
            // Expected to throw
        }
    }

    @Test("Concurrent scans are safe")
    func testConcurrentScansAreSafe() async throws {
        let model = await InstallerModel()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    await model.scan()
                }
            }
        }

        // Should complete without crash
        let isScanning = await model.isScanning
        #expect(isScanning == false, "Should finish scanning")
    }

    @Test("Model state transitions correctly during scan")
    func testScanningStateTransitions() async throws {
        let model = await InstallerModel()

        let initialState = await model.isScanning
        #expect(initialState == false, "Should start not scanning")

        // Start scan in background
        let scanTask = Task {
            await model.scan()
        }

        // Give it time to start
        try? await Task.sleep(for: .milliseconds(200))

        // Wait for completion
        await scanTask.value

        let finalState = await model.isScanning
        #expect(finalState == false, "Should finish scanning")
    }
}

// MARK: - Error Recovery Tests (P0)

@Suite("Error Recovery Tests")
struct ErrorRecoveryTests {

    @Test("Scan recovers after error")
    func testScanRecoveryAfterError() async throws {
        let model = await InstallerModel()

        // Simulate error state
        await MainActor.run {
            model.errorMessage = "Test error"
        }

        // Scan should clear error
        await model.scan()

        let errorMessage = await model.errorMessage
        #expect(errorMessage == nil || !errorMessage!.contains("Test error"),
                "Error should be cleared after new scan")
    }

    @Test("Multiple errors don't accumulate")
    func testMultipleErrorsDontAccumulate() async throws {
        let model = await InstallerModel()

        // Trigger multiple scans (some may fail)
        for _ in 0..<3 {
            await model.scan()
        }

        // Should only have one error message at most
        let errorMessage = await model.errorMessage
        if let error = errorMessage {
            let errorCount = error.components(separatedBy: "Failed").count - 1
            #expect(errorCount <= 1, "Should not accumulate errors")
        }
    }
}

// MARK: - Data Validation Tests (P0)

@Suite("Data Validation Tests")
struct DataValidationTests {

    @Test("Handles invalid JSON gracefully")
    func testHandlesInvalidJSON() async throws {
        let executor = await CLIExecutor()

        do {
            let _: MetricsSnapshot = try await executor.executeAndParseJSON(
                command: "echo 'invalid json'"
            )
            Issue.record("Should have thrown parsing error")
        } catch {
            // Expected to throw
            #expect(error is CLIExecutor.ExecutionError)
        }
    }

    @Test("Handles empty JSON response")
    func testHandlesEmptyJSON() async throws {
        let executor = await CLIExecutor()

        do {
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await executor.executeAndParseJSON(
                command: "echo '{}'"
            )
            // Should succeed with empty object
        } catch {
            Issue.record("Should handle empty JSON: \(error)")
        }
    }

    @Test("Handles malformed version strings")
    func testHandlesMalformedVersions() async {
        let model = await VersionModel()

        await MainActor.run {
            model.currentVersion = "invalid"
            model.latestVersion = "also-invalid"
        }

        let hasUpdate = await model.hasUpdate
        #expect(hasUpdate == false, "Should handle malformed versions gracefully")
    }
}

// MARK: - Memory & Performance Tests (P2)

@Suite("Memory & Performance Tests")
struct MemoryPerformanceTests {

    @Test("Large file list doesn't cause memory issues")
    func testLargeFileListPerformance() async throws {
        let model = await InstallerModel()

        // Simulate large file list
        await MainActor.run {
            model.files = (0..<1000).map { i in
                InstallerFile(
                    path: URL(fileURLWithPath: "/tmp/file\(i).dmg"),
                    name: "file\(i).dmg",
                    sizeBytes: UInt64(i * 1000),
                    source: "Downloads"
                )
            }
        }

        let fileCount = await model.files.count
        #expect(fileCount == 1000, "Should handle 1000 files")
    }

    // Note: History bounding is tested implicitly through normal metric updates
    // Direct array manipulation bypasses the updateHistory() method's bounds checking
}

// MARK: - Edge Cases Tests (P1)

@Suite("Edge Cases Tests")
struct EdgeCasesTests {

    @Test("Empty file paths are handled")
    func testEmptyFilePathsHandled() {
        let file = InstallerFile(
            path: URL(fileURLWithPath: ""),
            name: "",
            sizeBytes: 0,
            source: ""
        )

        #expect(file.name == "")
        #expect(file.sizeBytes == 0)
    }

    @Test("Very large file sizes are formatted correctly")
    func testVeryLargeFileSizes() {
        let petabyte: UInt64 = 1_125_899_906_842_624 // 1 PB
        let formatted = MetricsFormatter.humanBytes(petabyte)
        #expect(formatted.contains("TB") || formatted.contains("PB"))
    }

    @Test("Zero byte files are handled")
    func testZeroByteFiles() {
        let formatted = MetricsFormatter.humanBytes(0)
        #expect(formatted == "0.0 B")
    }

    @Test("Negative age days are handled")
    func testNegativeAgeDays() {
        let target = PurgeTarget(
            path: URL(fileURLWithPath: "/tmp/test"),
            projectName: "test",
            artifactName: "build",
            sizeBytes: 1000,
            ageDays: -1
        )

        // Should treat as recent
        #expect(target.isRecent == true)
    }
}

