import Darwin
import Foundation
import IOKit
import IOKit.ps
import Observation
import SystemConfiguration

// MARK: - Root Snapshot

struct MetricsSnapshot: Codable, Sendable {
    let collectedAt: Date
    let host: String
    let platform: String
    let uptime: String
    let procs: UInt64
    let hardware: HardwareInfo
    let healthScore: Int
    let healthScoreMsg: String

    let cpu: CPUStatus
    let gpu: [GPUStatus]
    let memory: MemoryStatus
    let disks: [DiskStatus]
    let diskIO: DiskIOStatus
    let network: [NetworkStatus]
    let networkHistory: NetworkHistory
    let proxy: ProxyStatus
    let batteries: [BatteryStatus]
    let thermal: ThermalStatus
    let sensors: [SensorReading]
    let bluetooth: [BluetoothDevice]
    let topProcesses: [MoleProcessInfo]

    init(
        collectedAt: Date,
        host: String,
        platform: String,
        uptime: String,
        procs: UInt64,
        hardware: HardwareInfo,
        healthScore: Int,
        healthScoreMsg: String,
        cpu: CPUStatus,
        gpu: [GPUStatus],
        memory: MemoryStatus,
        disks: [DiskStatus],
        diskIO: DiskIOStatus,
        network: [NetworkStatus],
        networkHistory: NetworkHistory,
        proxy: ProxyStatus,
        batteries: [BatteryStatus],
        thermal: ThermalStatus,
        sensors: [SensorReading],
        bluetooth: [BluetoothDevice],
        topProcesses: [MoleProcessInfo]
    ) {
        self.collectedAt = collectedAt
        self.host = host
        self.platform = platform
        self.uptime = uptime
        self.procs = procs
        self.hardware = hardware
        self.healthScore = healthScore
        self.healthScoreMsg = healthScoreMsg
        self.cpu = cpu
        self.gpu = gpu
        self.memory = memory
        self.disks = disks
        self.diskIO = diskIO
        self.network = network
        self.networkHistory = networkHistory
        self.proxy = proxy
        self.batteries = batteries
        self.thermal = thermal
        self.sensors = sensors
        self.bluetooth = bluetooth
        self.topProcesses = topProcesses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collectedAt = try c.decode(Date.self, forKey: .collectedAt)
        host = try c.decode(String.self, forKey: .host)
        platform = try c.decode(String.self, forKey: .platform)
        uptime = try c.decode(String.self, forKey: .uptime)
        procs = try c.decode(UInt64.self, forKey: .procs)
        hardware = try c.decode(HardwareInfo.self, forKey: .hardware)
        healthScore = try c.decode(Int.self, forKey: .healthScore)
        healthScoreMsg = try c.decode(String.self, forKey: .healthScoreMsg)
        cpu = try c.decode(CPUStatus.self, forKey: .cpu)
        memory = try c.decode(MemoryStatus.self, forKey: .memory)
        diskIO = try c.decode(DiskIOStatus.self, forKey: .diskIO)
        networkHistory = try c.decode(NetworkHistory.self, forKey: .networkHistory)
        proxy = try c.decode(ProxyStatus.self, forKey: .proxy)
        thermal = try c.decode(ThermalStatus.self, forKey: .thermal)
        // Go nil slices encode as JSON null — default to empty arrays
        gpu = try c.decodeIfPresent([GPUStatus].self, forKey: .gpu) ?? []
        disks = try c.decodeIfPresent([DiskStatus].self, forKey: .disks) ?? []
        network = try c.decodeIfPresent([NetworkStatus].self, forKey: .network) ?? []
        batteries = try c.decodeIfPresent([BatteryStatus].self, forKey: .batteries) ?? []
        sensors = try c.decodeIfPresent([SensorReading].self, forKey: .sensors) ?? []
        bluetooth = try c.decodeIfPresent([BluetoothDevice].self, forKey: .bluetooth) ?? []
        topProcesses = try c.decodeIfPresent([MoleProcessInfo].self, forKey: .topProcesses) ?? []
    }
}

// MARK: - Hardware

struct HardwareInfo: Codable, Sendable {
    let model: String
    let cpuModel: String
    let totalRAM: String
    let diskSize: String
    let osVersion: String
    let refreshRate: String
}

// MARK: - CPU

struct CPUStatus: Codable, Sendable {
    let usage: Double
    let perCore: [Double]
    let perCoreEstimated: Bool
    let load1: Double
    let load5: Double
    let load15: Double
    let coreCount: Int
    let logicalCPU: Int
    let pCoreCount: Int
    let eCoreCount: Int
}

// MARK: - GPU

struct GPUStatus: Codable, Sendable {
    let name: String
    let usage: Double
    let memoryUsed: Double
    let memoryTotal: Double
    let coreCount: Int
    let note: String
}

// MARK: - Memory

struct MemoryStatus: Codable, Sendable {
    let used: UInt64
    let total: UInt64
    let usedPercent: Double
    let swapUsed: UInt64
    let swapTotal: UInt64
    let cached: UInt64
    let pressure: String
}

// MARK: - Disk

struct DiskStatus: Codable, Sendable {
    let mount: String
    let device: String
    let used: UInt64
    let total: UInt64
    let usedPercent: Double
    let fstype: String
    let external: Bool
}

struct DiskIOStatus: Codable, Sendable {
    let readRate: Double
    let writeRate: Double
}

// MARK: - Network

struct NetworkStatus: Codable, Sendable {
    let name: String
    let rxRateMBs: Double
    let txRateMBs: Double
    let ip: String
}

struct NetworkHistory: Codable, Sendable {
    let rxHistory: [Double]
    let txHistory: [Double]

    init(rxHistory: [Double], txHistory: [Double]) {
        self.rxHistory = rxHistory
        self.txHistory = txHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rxHistory = try c.decodeIfPresent([Double].self, forKey: .rxHistory) ?? []
        txHistory = try c.decodeIfPresent([Double].self, forKey: .txHistory) ?? []
    }
}

// MARK: - Proxy

struct ProxyStatus: Codable, Sendable {
    let enabled: Bool
    let type: String
    let host: String
}

// MARK: - Battery

struct BatteryStatus: Codable, Sendable {
    let percent: Double
    let status: String
    let timeLeft: String
    let health: String
    let cycleCount: Int
    let capacity: Int
}

// MARK: - Thermal

struct ThermalStatus: Codable, Sendable {
    let cpuTemp: Double
    let gpuTemp: Double
    let fanSpeed: Int
    let fanCount: Int
    let systemPower: Double
    let adapterPower: Double
    let batteryPower: Double
}

// MARK: - Sensors & Peripherals

struct SensorReading: Codable, Sendable {
    let label: String
    let value: Double
    let unit: String
    let note: String
}

struct BluetoothDevice: Codable, Sendable {
    let name: String
    let connected: Bool
    let battery: String
}

struct MoleProcessInfo: Codable, Sendable {
    let name: String
    let cpu: Double
    let memory: Double
}

// MARK: - Formatting Helpers

enum MetricsFormatter {
    static func humanBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return index == 0
            ? "\(Int(value)) \(units[index])"
            : String(format: "%.1f %@", value, units[index])
    }

    static func formatRate(_ mbps: Double) -> String {
        if mbps < 0.01 { return "0 B/s" }
        if mbps < 1.0 { return String(format: "%.0f KB/s", mbps * 1024) }
        return String(format: "%.1f MB/s", mbps)
    }

    static func healthEmoji(score: Int) -> String {
        switch score {
        case 75...: return "🟢"
        case 60 ..< 75: return "🟡"
        default: return "🔴"
        }
    }

    static func usageEmoji(percent: Double) -> String {
        switch percent {
        case ..<60: return "🟢"
        case 60 ..< 85: return "🟡"
        default: return "🔴"
        }
    }
}

// MARK: - Model

/// Manages system metrics collection
/// Uses native Swift implementation as fallback when status-go is unavailable
@Observable @MainActor
final class MetricsModel {
    var snapshot: MetricsSnapshot?
    var isConnected = false
    var errorMessage: String?
    var refreshRate: Double = 2.0
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var diskIOReadHistory: [Double] = []
    var diskIOWriteHistory: [Double] = []

    private var process: Process?
    private var readTask: Task<Void, Never>?
    @ObservationIgnored private var nativeCollector: NativeMetricsCollector?
    private let maxHistoryPoints = 60 // 2 minutes at 2s interval
    private var useNativeImplementation = true // Use native by default since status-go has TTY issues

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fmt.date(from: str) { return date }
            fmt.formatOptions = [.withInternetDateTime]
            if let date = fmt.date(from: str) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Invalid date: \(str)")
            )
        }
        return d
    }()

    init() {}

    deinit {
        stop()
    }

    // MARK: - Binary Discovery

    private func findBinary() -> URL? {
        // In development: check project Resources directory
        #if DEBUG
            let projectPath = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/mole/bin/status-go")
            if FileManager.default.isExecutableFile(atPath: projectPath.path) {
                return projectPath
            }
        #endif

        // In production: check bundled binary (inside .app/Contents/Resources/mole/bin/)
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("mole/bin/status-go")
        {
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }
        return nil
    }

    // MARK: - Lifecycle

    func start(interval: Double = 2.0) {
        stop()

        refreshRate = interval

        // Use native Swift implementation (status-go has TTY issues in GUI apps)
        if useNativeImplementation {
            print("📊 Using native Swift metrics collection")
            let collector = NativeMetricsCollector()
            nativeCollector = collector

            collector.startCollecting(interval: interval) { [weak self] snapshot in
                guard let self = self else { return }
                self.snapshot = snapshot
                self.isConnected = true
                self.errorMessage = nil

                // Update history arrays
                self.cpuHistory.append(snapshot.cpu.usage)
                if self.cpuHistory.count > self.maxHistoryPoints {
                    self.cpuHistory.removeFirst()
                }

                self.memoryHistory.append(snapshot.memory.usedPercent)
                if self.memoryHistory.count > self.maxHistoryPoints {
                    self.memoryHistory.removeFirst()
                }

                self.diskIOReadHistory.append(snapshot.diskIO.readRate)
                if self.diskIOReadHistory.count > self.maxHistoryPoints {
                    self.diskIOReadHistory.removeFirst()
                }

                self.diskIOWriteHistory.append(snapshot.diskIO.writeRate)
                if self.diskIOWriteHistory.count > self.maxHistoryPoints {
                    self.diskIOWriteHistory.removeFirst()
                }
            }
            return
        }

        // Fallback: Try to use status-go (will likely fail due to TTY issues)
        guard let binary = findBinary() else {
            errorMessage = "status-go binary not found"
            print("❌ status-go binary not found")
            return
        }

        print("✅ Found status-go at: \(binary.path)")

        // Use script with TERM=dumb to force JSON output
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        let escapedPath = binary.path.replacingOccurrences(of: "'", with: "'\\''")

        // Set environment to force non-interactive mode
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["COLUMNS"] = "80"
        env["LINES"] = "24"
        proc.environment = env

        proc.arguments = ["-q", "/dev/null", "sh", "-c", "'\(escapedPath)' --json --watch --interval \(interval)"]

        let pipe = Pipe()
        let errorPipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = errorPipe
        proc.standardInput = FileHandle.nullDevice

        do {
            try proc.run()
            print("✅ status-go process started")
        } catch {
            errorMessage = "Failed to launch status-go: \(error.localizedDescription)"
            print("❌ Failed to launch: \(error)")
            return
        }

        process = proc
        isConnected = true
        errorMessage = nil

        // Read stderr in background
        Task.detached {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if !errorData.isEmpty, let errorText = String(data: errorData, encoding: .utf8) {
                print("❌ status-go stderr: \(errorText)")
            }
        }

        startReading(pipe: pipe)
    }

    nonisolated func stop() {
        MainActor.assumeIsolated {
            // Stop native collector
            nativeCollector?.stop()
            nativeCollector = nil

            // Stop status-go process
            readTask?.cancel()
            readTask = nil
            if let proc = process, proc.isRunning {
                proc.terminate()
            }
            process = nil
            isConnected = false
            cpuHistory.removeAll()
            memoryHistory.removeAll()
            diskIOReadHistory.removeAll()
            diskIOWriteHistory.removeAll()
        }
    }

    // MARK: - JSON Stream Reading

    private func startReading(pipe: Pipe) {
        let fileHandle = pipe.fileHandleForReading
        let decoder = self.decoder

        print("📖 Starting to read from status-go...")

        readTask = Task.detached { [weak self] in
            var buffer = Data()
            let newline = UInt8(ascii: "\n")
            var lineCount = 0

            while !Task.isCancelled {
                let chunk = fileHandle.availableData
                if chunk.isEmpty {
                    print("📖 No more data available, stopping")
                    break
                }
                buffer.append(chunk)

                while let range = buffer.firstIndex(of: newline) {
                    let line = buffer[buffer.startIndex ..< range]
                    buffer.removeSubrange(buffer.startIndex ... range)

                    guard !line.isEmpty else { continue }

                    lineCount += 1
                    if lineCount <= 3 {
                        print("📖 Received line \(lineCount): \(String(data: line, encoding: .utf8)?.prefix(100) ?? "invalid")")
                    }

                    do {
                        let snapshot = try decoder.decode(
                            MetricsSnapshot.self, from: Data(line)
                        )
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
                            self.snapshot = snapshot

                            if lineCount <= 3 {
                                print("✅ Successfully decoded snapshot \(lineCount)")
                            }

                            // Update history arrays
                            self.cpuHistory.append(snapshot.cpu.usage)
                            if self.cpuHistory.count > self.maxHistoryPoints {
                                self.cpuHistory.removeFirst()
                            }

                            self.memoryHistory.append(snapshot.memory.usedPercent)
                            if self.memoryHistory.count > self.maxHistoryPoints {
                                self.memoryHistory.removeFirst()
                            }

                            self.diskIOReadHistory.append(snapshot.diskIO.readRate)
                            if self.diskIOReadHistory.count > self.maxHistoryPoints {
                                self.diskIOReadHistory.removeFirst()
                            }

                            self.diskIOWriteHistory.append(snapshot.diskIO.writeRate)
                            if self.diskIOWriteHistory.count > self.maxHistoryPoints {
                                self.diskIOWriteHistory.removeFirst()
                            }
                        }
                    } catch {
                        if lineCount <= 3 {
                            print("❌ Failed to decode line \(lineCount): \(error)")
                        }
                    }
                }
            }

            print("📖 Read task finished")
            await MainActor.run { [weak self] in
                self?.isConnected = false
            }
        }
    }
}

// MARK: - Native Metrics Collector

/// Native Swift implementation of system metrics collection
/// This matches the data structure and behavior of Mole's status-go
///
/// NOTE: This is a fallback implementation when status-go cannot be used.
/// When Mole CLI updates, compare the output of `mo status --json` with this implementation
/// to ensure compatibility.
final class NativeMetricsCollector: @unchecked Sendable {
    private var timer: Timer?
    private var lastDiskIO: (read: UInt64, write: UInt64, time: Date)?
    private var lastNetworkIO: [(name: String, rx: UInt64, tx: UInt64)]?
    private var lastNetworkTime: Date?
    private var rxHistory: [Double] = []
    private var txHistory: [Double] = []
    private let maxHistoryPoints = 60

    func startCollecting(interval: TimeInterval, callback: @escaping @MainActor (MetricsSnapshot) -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let snapshot = self.collectSnapshot()
                callback(snapshot)
            }
        }
        // Collect first snapshot immediately
        Task { @MainActor in
            let snapshot = self.collectSnapshot()
            callback(snapshot)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func collectSnapshot() -> MetricsSnapshot {
        let networks = getNetworkStatus()
        let cpu = getCPUStatus()
        let memory = getMemoryStatus()
        let disks = getDiskStatus()
        let thermal = getThermalStatus()

        // Update network history
        let totalRx = networks.reduce(0.0) { $0 + $1.rxRateMBs }
        let totalTx = networks.reduce(0.0) { $0 + $1.txRateMBs }

        rxHistory.append(totalRx)
        if rxHistory.count > maxHistoryPoints {
            rxHistory.removeFirst()
        }

        txHistory.append(totalTx)
        if txHistory.count > maxHistoryPoints {
            txHistory.removeFirst()
        }

        // Calculate health score
        let (healthScore, healthMsg) = calculateHealthScore(
            cpu: cpu,
            memory: memory,
            disks: disks,
            thermal: thermal
        )

        return MetricsSnapshot(
            collectedAt: Date(),
            host: getHostname(),
            platform: getPlatform(),
            uptime: getUptime(),
            procs: getProcessCount(),
            hardware: getHardwareInfo(),
            healthScore: healthScore,
            healthScoreMsg: healthMsg,
            cpu: cpu,
            gpu: getGPUStatus(),
            memory: memory,
            disks: disks,
            diskIO: getDiskIOStatus(),
            network: networks,
            networkHistory: NetworkHistory(rxHistory: rxHistory, txHistory: txHistory),
            proxy: getProxyStatus(),
            batteries: getBatteryStatus(),
            thermal: thermal,
            sensors: [],
            bluetooth: [],
            topProcesses: getTopProcesses()
        )
    }

    private func calculateHealthScore(
        cpu: CPUStatus,
        memory: MemoryStatus,
        disks: [DiskStatus],
        thermal: ThermalStatus
    ) -> (Int, String) {
        var score = 100

        // CPU usage penalty (more aggressive)
        if cpu.usage > 90 {
            score -= 20
        } else if cpu.usage > 80 {
            score -= 10
        } else if cpu.usage > 60 {
            score -= 5
        }

        // CPU load average penalty
        let loadPerCore = cpu.load1 / Double(cpu.coreCount)
        if loadPerCore > 1.5 {
            score -= 10
        } else if loadPerCore > 1.0 {
            score -= 5
        }

        // Memory pressure penalty (more aggressive)
        if memory.usedPercent > 90 {
            score -= 20
        } else if memory.usedPercent > 80 {
            score -= 10
        } else if memory.usedPercent > 70 {
            score -= 5
        }

        // Disk usage penalty
        let maxDiskUsage = disks.map(\.usedPercent).max() ?? 0
        if maxDiskUsage > 95 {
            score -= 15
        } else if maxDiskUsage > 85 {
            score -= 8
        } else if maxDiskUsage > 75 {
            score -= 3
        }

        // Temperature penalty
        if thermal.cpuTemp > 80 {
            score -= 15
        } else if thermal.cpuTemp > 70 {
            score -= 8
        } else if thermal.cpuTemp > 60 {
            score -= 3
        }

        // Don't show message, just empty string
        return (max(score, 0), "")
    }

    // MARK: - System Info

    private func getHostname() -> String {
        ProcessInfo.processInfo.hostName
    }

    private func getPlatform() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private func getUptime() -> String {
        let uptime = ProcessInfo.processInfo.systemUptime
        let days = Int(uptime / 86400)
        let hours = Int((uptime.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((uptime.truncatingRemainder(dividingBy: 3600)) / 60)

        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func getProcessCount() -> UInt64 {
        var count: Int32 = 0
        var size = MemoryLayout<kinfo_proc>.stride * 1000
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: 1000)

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        if sysctl(&mib, 4, &procs, &size, nil, 0) == 0 {
            count = Int32(size / MemoryLayout<kinfo_proc>.stride)
        }
        return UInt64(count)
    }

    private func getHardwareInfo() -> HardwareInfo {
        // Get machine model name (e.g., "MacBook Pro")
        let modelIdentifier = sysctlString("hw.model") ?? "Unknown"
        let modelName = getMachineName(identifier: modelIdentifier)

        // Get CPU model
        let cpuModel = sysctlString("machdep.cpu.brand_string") ?? "Unknown"

        // Get total RAM
        let totalRAM = sysctlUInt64("hw.memsize")

        // Get total disk size - sum all internal disks
        var diskSize: UInt64 = 0
        let fileManager = FileManager.default
        if let volumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeTotalCapacityKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
            ],
            options: [.skipHiddenVolumes]
        ) {
            for volume in volumes {
                if let values = try? volume.resourceValues(forKeys: [
                    .volumeTotalCapacityKey,
                    .volumeIsRemovableKey,
                    .volumeIsEjectableKey,
                ]),
                    let capacity = values.volumeTotalCapacity
                {
                    // Only count internal disks
                    let isRemovable = values.volumeIsRemovable ?? false
                    let isEjectable = values.volumeIsEjectable ?? false
                    if !isRemovable && !isEjectable {
                        diskSize = max(diskSize, UInt64(capacity))
                    }
                }
            }
        }

        // Get GPU core count for Apple Silicon
        var gpuCores = 0
        if cpuModel.contains("Apple") {
            // Try to get GPU core count from IORegistry
            let matching = IOServiceMatching("AGXAccelerator")
            var iterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }
                let service = IOIteratorNext(iterator)
                if service != 0 {
                    defer { IOObjectRelease(service) }
                    var properties: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let props = properties?.takeRetainedValue() as? [String: Any],
                       let cores = props["gpu-core-count"] as? Int
                    {
                        gpuCores = cores
                    }
                }
            }
        }

        let cpuModelWithGPU = gpuCores > 0 ? "\(cpuModel), \(gpuCores)GPU" : cpuModel

        // Get macOS version
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "macOS \(version.majorVersion).\(version.minorVersion)"

        return HardwareInfo(
            model: modelName,
            cpuModel: cpuModelWithGPU,
            totalRAM: formatBytes(totalRAM),
            diskSize: formatBytes(diskSize),
            osVersion: osVersion,
            refreshRate: "60Hz"
        )
    }

    private func getMachineName(identifier: String) -> String {
        // Map hardware identifiers to simple marketing names
        if identifier.hasPrefix("MacBookAir") || identifier.contains(",") && identifier.hasPrefix("Mac") {
            // Determine the product line
            if identifier.hasPrefix("Mac14,2") || identifier.hasPrefix("Mac14,15") || identifier.hasPrefix("Mac15,12") {
                return "MacBook Air"
            } else if identifier.hasPrefix("Mac14,7") || identifier.hasPrefix("Mac14,5") || identifier.hasPrefix("Mac14,6") ||
                identifier.hasPrefix("Mac14,9") || identifier.hasPrefix("Mac14,10") ||
                identifier.hasPrefix("Mac15,") || identifier.hasPrefix("Mac16,")
            {
                return "MacBook Pro"
            } else if identifier.hasPrefix("Mac13,") {
                return "Mac mini"
            } else if identifier.hasPrefix("Mac14,13") || identifier.hasPrefix("Mac14,14") {
                return "Mac Studio"
            } else if identifier.hasPrefix("Mac15,") && identifier.contains("Mac15,4") {
                return "iMac"
            }
        }

        // Fallback: try to extract product name
        if identifier.contains("MacBook") {
            if identifier.contains("Air") {
                return "MacBook Air"
            } else if identifier.contains("Pro") {
                return "MacBook Pro"
            }
            return "MacBook"
        } else if identifier.contains("iMac") {
            return "iMac"
        } else if identifier.contains("Mac") {
            if identifier.contains("mini") {
                return "Mac mini"
            } else if identifier.contains("Studio") {
                return "Mac Studio"
            } else if identifier.contains("Pro") {
                return "Mac Pro"
            }
        }

        return identifier
    }

    // MARK: - CPU

    private func getCPUStatus() -> CPUStatus {
        let (usage, perCore) = getCPUUsage()
        let loadAvg = getLoadAverage()
        let coreCount = ProcessInfo.processInfo.processorCount
        let (pCores, eCores) = detectPECores()

        return CPUStatus(
            usage: usage,
            perCore: perCore,
            perCoreEstimated: false,
            load1: loadAvg.0,
            load5: loadAvg.1,
            load15: loadAvg.2,
            coreCount: coreCount,
            logicalCPU: coreCount,
            pCoreCount: pCores,
            eCoreCount: eCores
        )
    }

    private func detectPECores() -> (pCores: Int, eCores: Int) {
        // Try to detect P/E cores using sysctl
        var perfCores = 0
        var effCores = 0
        var size = MemoryLayout<Int>.size

        // Try hw.perflevel0.physicalcpu (Performance cores)
        if sysctlbyname("hw.perflevel0.physicalcpu", &perfCores, &size, nil, 0) == 0 {
            // Try hw.perflevel1.physicalcpu (Efficiency cores)
            sysctlbyname("hw.perflevel1.physicalcpu", &effCores, &size, nil, 0)
            return (perfCores, effCores)
        }

        // Fallback: check CPU brand for Apple Silicon
        if let cpuBrand = sysctlString("machdep.cpu.brand_string"),
           cpuBrand.contains("Apple")
        {
            // Estimate based on total core count for common Apple Silicon chips
            let totalCores = ProcessInfo.processInfo.processorCount
            switch totalCores {
            case 8: return (4, 4) // M1
            case 10: return (8, 2) // M1 Pro
            case 12: return (8, 4) // M2 Pro
            case 16: return (12, 4) // M1 Max / M2 Max
            default: return (0, 0)
            }
        }

        return (0, 0)
    }

    private func getCPUUsage() -> (Double, [Double]) {
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return (0.0, [])
        }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: cpuInfo),
                vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var perCore: [Double] = []

        for i in 0 ..< Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user = UInt64(cpuInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt64(cpuInfo[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(cpuInfo[offset + Int(CPU_STATE_IDLE)])

            totalUser += user
            totalSystem += system
            totalIdle += idle

            let coreTotal = user + system + idle
            let coreUsage = coreTotal > 0 ? Double(user + system) / Double(coreTotal) * 100.0 : 0.0
            perCore.append(coreUsage)
        }

        let total = totalUser + totalSystem + totalIdle
        let overallUsage = total > 0 ? Double(totalUser + totalSystem) / Double(total) * 100.0 : 0.0

        return (overallUsage, perCore)
    }

    private func getLoadAverage() -> (Double, Double, Double) {
        var loadAvg = [Double](repeating: 0, count: 3)
        getloadavg(&loadAvg, 3)
        return (loadAvg[0], loadAvg[1], loadAvg[2])
    }

    // MARK: - GPU

    private func getGPUStatus() -> [GPUStatus] {
        // GPU monitoring not yet implemented - requires IOKit AGXAccelerator service
        return []
    }

    // MARK: - Memory

    private func getMemoryStatus() -> MemoryStatus {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return MemoryStatus(
                used: 0,
                total: 0,
                usedPercent: 0,
                swapUsed: 0,
                swapTotal: 0,
                cached: 0,
                pressure: "normal"
            )
        }

        var pageSize = 0
        var size = MemoryLayout<Int>.size
        sysctlbyname("hw.pagesize", &pageSize, &size, nil, 0)
        let pageSizeUInt64 = UInt64(pageSize)

        let total = sysctlUInt64("hw.memsize")
        let active = UInt64(stats.active_count) * pageSizeUInt64
        let inactive = UInt64(stats.inactive_count) * pageSizeUInt64
        let wired = UInt64(stats.wire_count) * pageSizeUInt64
        let compressed = UInt64(stats.compressor_page_count) * pageSizeUInt64

        let used = active + wired + compressed
        let usedPercent = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0.0

        return MemoryStatus(
            used: used,
            total: total,
            usedPercent: usedPercent,
            swapUsed: 0, // Swap info not yet implemented
            swapTotal: 0,
            cached: inactive,
            pressure: usedPercent > 85 ? "high" : usedPercent > 60 ? "moderate" : "normal"
        )
    }

    // MARK: - Disk

    private func getDiskStatus() -> [DiskStatus] {
        var disks: [DiskStatus] = []
        let fileManager = FileManager.default

        // Don't skip hidden volumes - we want to see iOS Simulator volumes
        guard let mountedVolumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
                .volumeIsLocalKey,
                .volumeIsInternalKey,
            ],
            options: []
        ) else {
            return []
        }

        for volume in mountedVolumes {
            // Skip system volumes
            let path = volume.path
            if path.hasPrefix("/System/Volumes/") ||
                path == "/private/var/vm" ||
                path.hasPrefix("/Volumes/com.apple.")
            {
                continue
            }

            guard let values = try? volume.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey,
                .volumeNameKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey,
                .volumeIsLocalKey,
                .volumeIsInternalKey,
            ]) else {
                continue
            }

            guard let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity
            else {
                continue
            }

            // Skip very small volumes (< 100 MB) - likely DMG images
            // But keep volumes >= 1 GB even if they're ejectable (like iOS Simulator volumes)
            let isLargeVolume = total >= 1_000_000_000 // 1 GB
            if !isLargeVolume, total < 100_000_000 {
                continue
            }

            let used = UInt64(total - available)
            let usedPercent = total > 0 ? (Double(used) / Double(total)) * 100.0 : 0.0

            // Detect if disk is external
            let isRemovable = values.volumeIsRemovable ?? false
            let isEjectable = values.volumeIsEjectable ?? false
            let isLocal = values.volumeIsLocal ?? true
            let isInternal = values.volumeIsInternal ?? false

            // External = (removable OR ejectable) AND local AND not internal
            // But treat large ejectable volumes (like iOS Simulator) as external
            let isExternal = (isRemovable || isEjectable) && isLocal && !isInternal

            // Skip root volume if it's internal (we only want to show it once)
            if path == "/", !isExternal {
                disks.append(DiskStatus(
                    mount: path,
                    device: values.volumeName ?? "Unknown",
                    used: used,
                    total: UInt64(total),
                    usedPercent: usedPercent,
                    fstype: "apfs",
                    external: false
                ))
            } else if isExternal {
                // Show all external volumes
                disks.append(DiskStatus(
                    mount: path,
                    device: values.volumeName ?? "Unknown",
                    used: used,
                    total: UInt64(total),
                    usedPercent: usedPercent,
                    fstype: "apfs",
                    external: true
                ))
            }
        }

        return disks
    }

    private func getDiskIOStatus() -> DiskIOStatus {
        var stats = [io_iterator_t](repeating: 0, count: 1)
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &stats[0]) == KERN_SUCCESS else {
            return DiskIOStatus(readRate: 0, writeRate: 0)
        }

        defer {
            IOObjectRelease(stats[0])
        }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0

        var drive = IOIteratorNext(stats[0])
        while drive != 0 {
            defer {
                IOObjectRelease(drive)
                drive = IOIteratorNext(stats[0])
            }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(drive, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any],
                  let statistics = props["Statistics"] as? [String: Any]
            else {
                continue
            }

            if let bytesRead = statistics["Bytes (Read)"] as? UInt64 {
                totalRead += bytesRead
            }
            if let bytesWritten = statistics["Bytes (Write)"] as? UInt64 {
                totalWrite += bytesWritten
            }
        }

        let now = Date()
        var readRate: Double = 0
        var writeRate: Double = 0

        if let last = lastDiskIO {
            let timeDiff = now.timeIntervalSince(last.time)
            if timeDiff > 0 {
                readRate = Double(totalRead - last.read) / timeDiff / 1_048_576 // MB/s
                writeRate = Double(totalWrite - last.write) / timeDiff / 1_048_576 // MB/s
            }
        }

        lastDiskIO = (read: totalRead, write: totalWrite, time: now)

        return DiskIOStatus(readRate: max(0, readRate), writeRate: max(0, writeRate))
    }

    // MARK: - Network

    private func getNetworkStatus() -> [NetworkStatus] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }

        var interfaces: [String: (rx: UInt64, tx: UInt64, ip: String)] = [:]

        var addr = firstAddr
        while true {
            let name = String(cString: addr.pointee.ifa_name)

            // Get IP address
            if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr.pointee.ifa_addr, socklen_t(addr.pointee.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let ip = hostname.withUnsafeBufferPointer { buffer in
                    let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                    return String(bytes: bytes, encoding: .utf8) ?? ""
                }

                if interfaces[name] == nil {
                    interfaces[name] = (rx: 0, tx: 0, ip: ip)
                } else {
                    interfaces[name]?.ip = ip
                }
            }

            // Get network statistics
            if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                let data = unsafeBitCast(addr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                let rx = UInt64(data.pointee.ifi_ibytes)
                let tx = UInt64(data.pointee.ifi_obytes)

                if let existing = interfaces[name] {
                    // Keep existing IP if we have one
                    interfaces[name] = (rx: rx, tx: tx, ip: existing.ip)
                } else {
                    interfaces[name] = (rx: rx, tx: tx, ip: "")
                }
            }

            guard let next = addr.pointee.ifa_next else { break }
            addr = next
        }

        let now = Date()
        var networkStatuses: [NetworkStatus] = []

        for (name, stats) in interfaces {
            // Skip loopback and inactive interfaces
            guard !name.hasPrefix("lo"), stats.rx > 0 else { continue }

            var rxRate: Double = 0
            var txRate: Double = 0

            if let lastTime = lastNetworkTime,
               let lastStats = lastNetworkIO?.first(where: { $0.name == name })
            {
                let timeDiff = now.timeIntervalSince(lastTime)
                if timeDiff > 0 {
                    rxRate = Double(stats.rx - lastStats.rx) / timeDiff / 1_048_576 // MB/s
                    txRate = Double(stats.tx - lastStats.tx) / timeDiff / 1_048_576 // MB/s
                }
            }

            networkStatuses.append(NetworkStatus(
                name: name,
                rxRateMBs: max(0, rxRate),
                txRateMBs: max(0, txRate),
                ip: stats.ip
            ))
        }

        lastNetworkIO = interfaces.map { (name: $0.key, rx: $0.value.rx, tx: $0.value.tx) }
        lastNetworkTime = now

        return networkStatuses.sorted { $0.name < $1.name }
    }

    private func getProxyStatus() -> ProxyStatus {
        guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return ProxyStatus(enabled: false, type: "", host: "")
        }

        // Check HTTP proxy
        if let httpEnabled = proxySettings["HTTPEnable"] as? Int, httpEnabled == 1,
           let httpHost = proxySettings["HTTPProxy"] as? String,
           let httpPort = proxySettings["HTTPPort"] as? Int
        {
            return ProxyStatus(enabled: true, type: "HTTP", host: "\(httpHost):\(httpPort)")
        }

        // Check HTTPS proxy
        if let httpsEnabled = proxySettings["HTTPSEnable"] as? Int, httpsEnabled == 1,
           let httpsHost = proxySettings["HTTPSProxy"] as? String,
           let httpsPort = proxySettings["HTTPSPort"] as? Int
        {
            return ProxyStatus(enabled: true, type: "HTTPS", host: "\(httpsHost):\(httpsPort)")
        }

        // Check SOCKS proxy
        if let socksEnabled = proxySettings["SOCKSEnable"] as? Int, socksEnabled == 1,
           let socksHost = proxySettings["SOCKSProxy"] as? String,
           let socksPort = proxySettings["SOCKSPort"] as? Int
        {
            return ProxyStatus(enabled: true, type: "SOCKS", host: "\(socksHost):\(socksPort)")
        }

        return ProxyStatus(enabled: false, type: "", host: "")
    }

    // MARK: - Battery

    private func getBatteryStatus() -> [BatteryStatus] {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return []
        }

        var batteries: [BatteryStatus] = []

        // Get cycle count from IORegistry (not available in IOPSCopyPowerSourcesInfo)
        var cycleCount = 0
        let matching = IOServiceMatching("AppleSmartBattery")
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }
            let service = IOIteratorNext(iterator)
            if service != 0 {
                defer { IOObjectRelease(service) }
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let props = properties?.takeRetainedValue() as? [String: Any],
                   let cycles = props["CycleCount"] as? Int
                {
                    cycleCount = cycles
                }
            }
        }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            // Check if it's a battery (not AC power)
            guard let type = info[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType
            else {
                continue
            }

            let currentCapacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCapacity = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = maxCapacity > 0 ? Double(currentCapacity) / Double(maxCapacity) * 100.0 : 0.0

            let isCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            let isCharged = info[kIOPSIsChargedKey] as? Bool ?? false
            let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int ?? -1
            let timeToFull = info[kIOPSTimeToFullChargeKey] as? Int ?? -1

            var status = "Unknown"
            var timeLeft = ""

            if isCharged {
                status = "Charged"
                timeLeft = "Fully charged"
            } else if isCharging {
                status = "Charging"
                if timeToFull > 0 {
                    let hours = timeToFull / 60
                    let minutes = timeToFull % 60
                    timeLeft = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                } else {
                    timeLeft = "Calculating..."
                }
            } else {
                status = "Discharging"
                if timeToEmpty > 0 {
                    let hours = timeToEmpty / 60
                    let minutes = timeToEmpty % 60
                    timeLeft = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                } else {
                    timeLeft = "Calculating..."
                }
            }

            let designCapacity = info["DesignCapacity"] as? Int ?? 0

            // Calculate health percentage
            let healthPercent = designCapacity > 0 ? Int(Double(maxCapacity) / Double(designCapacity) * 100) : 100

            // Determine health status based on percentage
            let health: String
            if healthPercent >= 80 {
                health = "Normal"
            } else if healthPercent >= 60 {
                health = "Fair"
            } else {
                health = "Poor"
            }

            batteries.append(BatteryStatus(
                percent: percent,
                status: status,
                timeLeft: timeLeft,
                health: health,
                cycleCount: cycleCount,
                capacity: maxCapacity
            ))
        }

        return batteries
    }

    // MARK: - Thermal

    private func getThermalStatus() -> ThermalStatus {
        var cpuTemp: Double = 0
        var adapterPower: Double = 0
        var batteryPower: Double = 0
        var systemPower: Double = 0

        // Get power information from IOPMPowerSource
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        {
            for source in sources {
                if let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    // Get adapter power (in watts)
                    if let power = info["Adapter Power"] as? Double {
                        adapterPower = power
                    } else if let power = info[kIOPSPowerAdapterWattsKey] as? Double {
                        adapterPower = power
                    }

                    // Get battery power draw
                    if let current = info["InstantAmperage"] as? Double,
                       let voltage = info["Voltage"] as? Double
                    {
                        batteryPower = abs(current * voltage / 1000.0) // Convert to watts
                    }
                }
            }
        }

        systemPower = adapterPower > 0 ? adapterPower : batteryPower

        // Try to get temperature from IOHWSensor
        let matching = IOServiceMatching("AppleSMC")
        var iterator: io_iterator_t = 0

        if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }

            let service = IOIteratorNext(iterator)
            if service != 0 {
                defer { IOObjectRelease(service) }

                // Try to get properties
                var properties: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   properties?.takeRetainedValue() is [String: Any]
                {
                    // Look for temperature-related keys
                    // This is a simplified approach - actual SMC reading is more complex
                }
            }
        }

        // Fallback: try to estimate from CPU usage (very rough approximation)
        // Typical idle temp: 30-40°C, under load: 60-80°C
        // This is just a placeholder until proper SMC reading is implemented
        let cpuUsage = getCPUUsage().0
        cpuTemp = 30.0 + (cpuUsage / 100.0) * 30.0 // Rough estimate

        return ThermalStatus(
            cpuTemp: cpuTemp,
            gpuTemp: 0,
            fanSpeed: 0,
            fanCount: 0,
            systemPower: systemPower,
            adapterPower: adapterPower,
            batteryPower: batteryPower
        )
    }

    // MARK: - Processes

    private func getTopProcesses() -> [MoleProcessInfo] {
        // Use ps command to get process information
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-arcwwwxo", "pid,pcpu,pmem,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            var processes: [MoleProcessInfo] = []
            let lines = output.components(separatedBy: .newlines)

            for line in lines.dropFirst() { // Skip header
                let parts = line.trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }

                guard parts.count >= 4 else { continue }

                let cpu = Double(parts[1]) ?? 0
                let memory = Double(parts[2]) ?? 0
                let name = parts[3...].joined(separator: " ")

                // Skip very low usage processes
                guard cpu > 0.1 || memory > 0.1 else { continue }

                processes.append(MoleProcessInfo(
                    name: name,
                    cpu: cpu,
                    memory: memory
                ))
            }

            // Sort by CPU usage and take top 10
            return processes
                .sorted { $0.cpu > $1.cpu }
                .prefix(10)
                .map { $0 }

        } catch {
            return []
        }
    }

    // MARK: - Helpers

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return nil
        }
        return value.withUnsafeBufferPointer { buffer in
            let bytes = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
            return String(bytes: bytes, encoding: .utf8) ?? ""
        }
    }

    private func sysctlUInt64(_ name: String) -> UInt64 {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname(name, &value, &size, nil, 0)
        return value
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        MetricsFormatter.humanBytes(bytes)
    }
}
