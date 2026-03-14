import Foundation
import Observation
import os.log

// MARK: - Data Models (matching Mole JSON output)

struct MetricsSnapshot: Codable {
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

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case host, platform, uptime, procs, hardware
        case healthScore = "health_score"
        case healthScoreMsg = "health_score_msg"
        case cpu, gpu, memory, disks
        case diskIO = "disk_io"
        case network
        case networkHistory = "network_history"
        case proxy, batteries, thermal, sensors, bluetooth
        case topProcesses = "top_processes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.collectedAt = try container.decode(Date.self, forKey: .collectedAt)
        self.host = try container.decode(String.self, forKey: .host)
        self.platform = try container.decode(String.self, forKey: .platform)
        self.uptime = try container.decode(String.self, forKey: .uptime)
        self.procs = try container.decode(UInt64.self, forKey: .procs)
        self.hardware = try container.decode(HardwareInfo.self, forKey: .hardware)
        self.healthScore = try container.decode(Int.self, forKey: .healthScore)
        self.healthScoreMsg = try container.decode(String.self, forKey: .healthScoreMsg)
        self.cpu = try container.decode(CPUStatus.self, forKey: .cpu)
        self.memory = try container.decode(MemoryStatus.self, forKey: .memory)
        self.diskIO = try container.decode(DiskIOStatus.self, forKey: .diskIO)
        self.networkHistory = try container.decodeIfPresent(NetworkHistory.self, forKey: .networkHistory) ?? .empty
        self.proxy = try container.decode(ProxyStatus.self, forKey: .proxy)
        self.thermal = try container.decode(ThermalStatus.self, forKey: .thermal)

        // Arrays that can be null in JSON
        self.gpu = try container.decodeIfPresent([GPUStatus].self, forKey: .gpu) ?? []
        self.disks = try container.decodeIfPresent([DiskStatus].self, forKey: .disks) ?? []
        self.network = try container.decodeIfPresent([NetworkStatus].self, forKey: .network) ?? []
        self.batteries = try container.decodeIfPresent([BatteryStatus].self, forKey: .batteries) ?? []
        self.sensors = try container.decodeIfPresent([SensorReading].self, forKey: .sensors) ?? []
        self.bluetooth = try container.decodeIfPresent([BluetoothDevice].self, forKey: .bluetooth) ?? []
        self.topProcesses = try container.decodeIfPresent([MoleProcessInfo].self, forKey: .topProcesses) ?? []
    }
}

struct HardwareInfo: Codable {
    let model: String
    let cpuModel: String
    let totalRAM: String
    let diskSize: String
    let osVersion: String
    let refreshRate: String

    enum CodingKeys: String, CodingKey {
        case model
        case cpuModel = "cpu_model"
        case totalRAM = "total_ram"
        case diskSize = "disk_size"
        case osVersion = "os_version"
        case refreshRate = "refresh_rate"
    }
}

struct CPUStatus: Codable {
    let usage: Double
    let perCore: [Double]
    let perCoreEstimated: Bool
    let load1: Double
    let load5: Double
    let load15: Double
    let coreCount: Int
    let logicalCpu: Int
    let pCoreCount: Int
    let eCoreCount: Int

    enum CodingKeys: String, CodingKey {
        case usage
        case perCore = "per_core"
        case perCoreEstimated = "per_core_estimated"
        case load1, load5, load15
        case coreCount = "core_count"
        case logicalCpu = "logical_cpu"
        case pCoreCount = "p_core_count"
        case eCoreCount = "e_core_count"
    }
}

struct GPUStatus: Codable {
    let name: String
    let usage: Double
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let coreCount: Int
    let note: String

    enum CodingKeys: String, CodingKey {
        case name, usage
        case memoryUsed = "memory_used"
        case memoryTotal = "memory_total"
        case coreCount = "core_count"
        case note
    }
}

struct MemoryStatus: Codable {
    let used: UInt64
    let total: UInt64
    let usedPercent: Double
    let swapUsed: UInt64
    let swapTotal: UInt64
    let cached: UInt64
    let pressure: String

    enum CodingKeys: String, CodingKey {
        case used, total
        case usedPercent = "used_percent"
        case swapUsed = "swap_used"
        case swapTotal = "swap_total"
        case cached, pressure
    }
}

struct DiskStatus: Codable {
    let mount: String
    let device: String
    let used: UInt64
    let total: UInt64
    let usedPercent: Double
    let fstype: String
    let external: Bool

    enum CodingKeys: String, CodingKey {
        case mount, device, used, total
        case usedPercent = "used_percent"
        case fstype, external
    }
}

struct DiskIOStatus: Codable {
    let readRate: Double
    let writeRate: Double

    enum CodingKeys: String, CodingKey {
        case readRate = "read_rate"
        case writeRate = "write_rate"
    }
}

struct NetworkStatus: Codable {
    let name: String
    let rxRateMBs: Double
    let txRateMBs: Double
    let ip: String

    enum CodingKeys: String, CodingKey {
        case name
        case rxRateMBs = "rx_rate_mbs"
        case txRateMBs = "tx_rate_mbs"
        case ip
    }
}

struct NetworkHistory: Codable {
    let rxHistory: [Double]
    let txHistory: [Double]

    enum CodingKeys: String, CodingKey {
        case rxHistory = "rx_history"
        case txHistory = "tx_history"
    }

    static let empty = NetworkHistory(rxHistory: [], txHistory: [])

    init(rxHistory: [Double], txHistory: [Double]) {
        self.rxHistory = rxHistory
        self.txHistory = txHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rxHistory = try container.decodeIfPresent([Double].self, forKey: .rxHistory) ?? []
        self.txHistory = try container.decodeIfPresent([Double].self, forKey: .txHistory) ?? []
    }
}

struct ProxyStatus: Codable {
    let enabled: Bool
    let type: String
    let host: String
}

struct BatteryStatus: Codable {
    let percent: Double
    let status: String
    let timeLeft: String
    let health: String
    let cycleCount: Int
    let capacity: Int

    enum CodingKeys: String, CodingKey {
        case percent, status
        case timeLeft = "time_left"
        case health
        case cycleCount = "cycle_count"
        case capacity
    }
}

struct ThermalStatus: Codable {
    let cpuTemp: Double
    let gpuTemp: Double
    let fanSpeed: Int
    let fanCount: Int
    let systemPower: Double
    let adapterPower: Double
    let batteryPower: Double

    enum CodingKeys: String, CodingKey {
        case cpuTemp = "cpu_temp"
        case gpuTemp = "gpu_temp"
        case fanSpeed = "fan_speed"
        case fanCount = "fan_count"
        case systemPower = "system_power"
        case adapterPower = "adapter_power"
        case batteryPower = "battery_power"
    }
}

struct SensorReading: Codable {
    let name: String
    let value: Double
    let unit: String
}

struct BluetoothDevice: Codable {
    let name: String
    let connected: Bool
}

struct MoleProcessInfo: Codable {
    let name: String
    let cpu: Double
    let memory: Double
}

// MARK: - Formatters

enum MetricsFormatter {
    static func humanBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        return String(format: "%.1f %@", value, units[unitIndex])
    }

    static func formatRate(_ mbps: Double) -> String {
        if mbps < 1.0 {
            String(format: "%.0f KB/s", mbps * 1024)
        } else {
            String(format: "%.2f MB/s", mbps)
        }
    }
}

// MARK: - MetricsModel (JSON-based)

@Observable @MainActor
final class MetricsModel {
    var snapshot: MetricsSnapshot?
    var isConnected = false
    var errorMessage: String?
    var refreshRate: Double = 1.0 // 1 second refresh to match Mole TUI
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var diskIOReadHistory: [Double] = []
    var diskIOWriteHistory: [Double] = []
    var networkRxHistory: [Double] = []
    var networkTxHistory: [Double] = []

    /// Reference to CleanModel to check if privileged operations are in progress
    weak var cleanModel: CleanModel?
    /// Reference to OptimizeModel to check if privileged operations are in progress
    weak var optimizeModel: OptimizeModel?

    private var updateTask: Task<Void, Never>?
    private let maxHistoryPoints = 120 // 4 minutes at 2s interval (matches Mole)
    private let logger = Logger(subsystem: "com.qinfuyao.MoleUI", category: "MetricsModel")
    private var lastFetchTime: Date?
    private let minFetchInterval: TimeInterval = 0.5 // Minimum 500ms between fetches
    private var isPaused = false // Track pause state to avoid repeated logging

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
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid date: \(str)"
                )
            )
        }
        return d
    }()

    init() {}

    // Note: No deinit needed - Task will be automatically cancelled when the object is deallocated

    func start() {
        guard !isConnected else {
            logger.warning("Already connected")
            return
        }

        logger.info("Starting metrics collection (JSON mode)")
        isConnected = true
        errorMessage = nil

        updateTask = Task {
            while !Task.isCancelled, isConnected {
                let cycleStart = Date()

                // Skip metrics fetch if privileged operations are in progress
                // This avoids resource contention between mole status and mole clean/optimize
                let cleaningFlag = cleanModel?.isCleaningWithPrivileges ?? false
                let optimizingFlag = optimizeModel?.isOptimizingWithPrivileges ?? false
                let shouldSkip = cleaningFlag || optimizingFlag

                if shouldSkip {
                    // Only log when transitioning to paused state
                    if !isPaused {
                        logger.info("⏸️ Pausing metrics refresh (cleaning: \(cleaningFlag), optimizing: \(optimizingFlag))")
                        isPaused = true
                    }
                } else {
                    // Log when resuming
                    if isPaused {
                        logger.info("▶️ Resuming metrics refresh")
                        isPaused = false
                    }
                }

                if !shouldSkip {
                    do {
                        try await fetchMetrics()
                    } catch {
                        logger.error("Failed to fetch metrics: \(error.localizedDescription)")
                        errorMessage = error.localizedDescription
                        isConnected = false
                    }
                }

                let elapsed = Date().timeIntervalSince(cycleStart)
                let remaining = max(0.1, refreshRate - elapsed)
                try? await Task.sleep(for: .seconds(remaining))
            }
        }
    }

    func stop() {
        logger.info("Stopping metrics collection")
        isConnected = false
        updateTask?.cancel()
        updateTask = nil
    }

    func networkHistoryForDisplay(from snapshotHistory: NetworkHistory) -> NetworkHistory {
        let rx = networkRxHistory.isEmpty ? snapshotHistory.rxHistory : networkRxHistory
        let tx = networkTxHistory.isEmpty ? snapshotHistory.txHistory : networkTxHistory
        return NetworkHistory(rxHistory: rx, txHistory: tx)
    }

    // MARK: - Private Methods

    private func fetchMetrics() async throws {
        // Throttle requests
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < minFetchInterval
        {
            logger.debug("Throttling fetch request")
            return
        }

        let startTime = Date()

        guard let binary = CLIExecutor.findMoleBinary() else {
            throw NSError(
                domain: "MetricsModel",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot find mole executable"]
            )
        }

        // Execute status-go --json
        let executor = CLIExecutor()

        // Use quotes to handle paths with spaces
        let command = shellEscape(binary.path) + " status --json"

        let newSnapshot: MetricsSnapshot = try await executor.executeAndParseJSON(
            command: command,
            options: CLIExecutor.ExecutionOptions(
                timeout: 10,
                captureStderr: true,
                parseProgress: false,
                dryRun: false
            ),
            decoder: decoder
        )

        // Update snapshot
        snapshot = newSnapshot
        lastFetchTime = Date()

        // Update history
        updateHistory(newSnapshot)
        let duration = Date().timeIntervalSince(startTime)
        logger.debug("Metrics updated in \(String(format: "%.3f", duration))s")
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func updateHistory(_ snap: MetricsSnapshot) {
        // CPU history
        cpuHistory.append(snap.cpu.usage)
        if cpuHistory.count > maxHistoryPoints {
            cpuHistory.removeFirst()
        }

        // Memory history
        memoryHistory.append(snap.memory.usedPercent)
        if memoryHistory.count > maxHistoryPoints {
            memoryHistory.removeFirst()
        }

        // Disk IO history
        diskIOReadHistory.append(snap.diskIO.readRate)
        if diskIOReadHistory.count > maxHistoryPoints {
            diskIOReadHistory.removeFirst()
        }

        diskIOWriteHistory.append(snap.diskIO.writeRate)
        if diskIOWriteHistory.count > maxHistoryPoints {
            diskIOWriteHistory.removeFirst()
        }

        // Network history: prefer current totals; fallback to last sample from core history.
        let totalRx = snap.network.reduce(0.0) { $0 + $1.rxRateMBs }
        let totalTx = snap.network.reduce(0.0) { $0 + $1.txRateMBs }
        let rxSample = (!snap.network.isEmpty || totalRx > 0) ? totalRx : snap.networkHistory.rxHistory.last
        let txSample = (!snap.network.isEmpty || totalTx > 0) ? totalTx : snap.networkHistory.txHistory.last

        // swiftformat:disable:next redundantSelf
        logger.debug("Network update - RX: \(totalRx), TX: \(totalTx), History size: \(self.networkRxHistory.count)")

        if let rxSample {
            networkRxHistory.append(rxSample)
            if networkRxHistory.count > maxHistoryPoints {
                networkRxHistory.removeFirst()
            }
        }

        if let txSample {
            networkTxHistory.append(txSample)
            if networkTxHistory.count > maxHistoryPoints {
                networkTxHistory.removeFirst()
            }
        }
    }
}
