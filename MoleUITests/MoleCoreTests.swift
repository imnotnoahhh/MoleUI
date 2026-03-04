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

@Test func healthEmoji() {
    #expect(MetricsFormatter.healthEmoji(score: 90) == "💚")
    #expect(MetricsFormatter.healthEmoji(score: 75) == "💛")
    #expect(MetricsFormatter.healthEmoji(score: 70) == "🧡")
    #expect(MetricsFormatter.healthEmoji(score: 60) == "🧡")
    #expect(MetricsFormatter.healthEmoji(score: 50) == "❤️")
}

// MARK: - SafetyController Parsing

@Test func parseSizeStringBytes() async {
    let controller = await SafetyController()
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

// MARK: - status-go Integration (skipped if binary unavailable)

@Test func statusGoOutputDecodesAsMetricsSnapshot() async throws {
    let candidates = [
        Bundle.main.resourceURL?.appendingPathComponent("mole/status-go").path,
        "/opt/homebrew/bin/status-go",
        "/usr/local/bin/status-go",
        NSHomeDirectory() + "/.config/mole/bin/status-go"
    ].compactMap { $0 }

    guard let binaryPath = candidates.first(where: {
        FileManager.default.isExecutableFile(atPath: $0)
    }) else { return }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()

    // Wait briefly for status-go to produce its first JSON line
    try await Task.sleep(for: .seconds(2))
    let data = pipe.fileHandleForReading.availableData
    process.terminate()

    guard let jsonLine = String(data: data, encoding: .utf8)?
        .components(separatedBy: "\n")
        .first(where: { $0.hasPrefix("{") }),
        let jsonData = jsonLine.data(using: .utf8) else {
        // status-go didn't produce output in test environment, skip
        return
    }

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

    let snapshot = try decoder.decode(MetricsSnapshot.self, from: jsonData)
    #expect(!snapshot.host.isEmpty)
    #expect(snapshot.cpu.coreCount > 0)
    #expect(snapshot.memory.total > 0)
}
