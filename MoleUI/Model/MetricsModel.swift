import Foundation
import Observation

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

/// Manages the status-go subprocess and streams MetricsSnapshot updates.
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
    private let maxHistoryPoints = 60 // 2 minutes at 2s interval

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
        // Check bundled binary first (inside .app/Contents/Resources/mole/)
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("mole/status-go") {
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }

        let candidates: [String] = [
            "/usr/local/bin/status-go",
            "/opt/homebrew/bin/status-go",
            NSHomeDirectory() + "/.config/mole/bin/status-go",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - Lifecycle

    func start(interval: Double = 2.0) {
        stop()

        refreshRate = interval

        guard let binary = findBinary() else {
            errorMessage = "status-go binary not found"
            return
        }

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["--json", "--watch", "--interval", String(interval)]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            errorMessage = "Failed to launch status-go: \(error.localizedDescription)"
            return
        }

        process = proc
        isConnected = true
        errorMessage = nil

        startReading(pipe: pipe)
    }

    nonisolated func stop() {
        MainActor.assumeIsolated {
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

        readTask = Task.detached { [weak self] in
            var buffer = Data()
            let newline = UInt8(ascii: "\n")

            while !Task.isCancelled {
                let chunk = fileHandle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)

                while let range = buffer.firstIndex(of: newline) {
                    let line = buffer[buffer.startIndex ..< range]
                    buffer.removeSubrange(buffer.startIndex ... range)

                    guard !line.isEmpty else { continue }

                    do {
                        let snapshot = try decoder.decode(
                            MetricsSnapshot.self, from: Data(line)
                        )
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
                            self.snapshot = snapshot

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
                        // silently skip malformed lines
                    }
                }
            }

            await MainActor.run { [weak self] in
                self?.isConnected = false
            }
        }
    }
}
