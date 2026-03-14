import SwiftUI

// MARK: - Reusable Components

struct MoleAnimationView: View {
    @State private var animFrame = 0
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    private static let bodyRight: [[String]] = [
        [
            #"     /\_/\"#,
            #" ___/ o o \"#,
            #"/___   =-= /"#,
            #"\____)-m-m)"#,
        ],
        [
            #"     /\_/\"#,
            #" ___/ o o \"#,
            #"/___   =-= /"#,
            #"\____)mm__)"#,
        ],
        [
            #"     /\_/\"#,
            #" ___/ · · \"#,
            #"/___   =-= /"#,
            #"\___)-m__m)"#,
        ],
        [
            #"     /\_/\"#,
            #" ___/ o o \"#,
            #"/___   =-= /"#,
            #"\____)-mm-)"#,
        ],
    ]

    private static let bodyLeft: [[String]] = [
        [
            #"    /\_/\"#,
            #"   / o o \___"#,
            #"  \ =-=   ___\"#,
            #"  (m-m-(____/"#,
        ],
        [
            #"    /\_/\"#,
            #"   / o o \___"#,
            #"  \ =-=   ___\"#,
            #"  (__mm(____/"#,
        ],
        [
            #"    /\_/\"#,
            #"   / · · \___"#,
            #"  \ =-=   ___\"#,
            #"  (m__m-(___/"#,
        ],
        [
            #"    /\_/\"#,
            #"   / o o \___"#,
            #"  \ =-=   ___\"#,
            #"  (-mm-(____/"#,
        ],
    ]

    var body: some View {
        GeometryReader { geo in
            let charWidth: CGFloat = 7.2
            let moleChars = 15
            let moleWidth = charWidth * CGFloat(moleChars)
            let maxPos = max(Int((geo.size.width - moleWidth) / charWidth), 1)
            let cycleLen = maxPos * 2
            let pos = animFrame % max(cycleLen, 1)
            let movingLeft = pos > maxPos
            let xPos = movingLeft ? (cycleLen - pos) : pos
            let frames = movingLeft ? Self.bodyLeft : Self.bodyRight
            let bodyIdx = animFrame % frames.count
            let lines = frames[bodyIdx]

            Text(lines.joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.7))
                .fixedSize()
                .offset(x: CGFloat(xPos) * charWidth)
        }
        .frame(height: 52)
        .clipped()
        .onReceive(timer) { _ in
            animFrame += 1
        }
    }
}

struct UsageBar: View {
    let percent: Double
    let color: Color
    let autoThreshold: Bool

    init(_ percent: Double, color: Color = .green, autoThreshold: Bool = true) {
        self.percent = percent
        self.color = color
        self.autoThreshold = autoThreshold
    }

    private var barColor: Color {
        guard autoThreshold else { return color }
        if percent >= 85 { return .red }
        if percent >= 60 { return .yellow }
        return color
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.1))
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * min(percent, 100) / 100)
            }
        }
        .frame(height: 14)
        .frame(maxWidth: 160)
    }
}

struct MiniSparklineView: View {
    let data: [Double]
    let color: Color
    let width: Int = 30

    var body: some View {
        // 32-level visualization using repeated standard block characters
        // Levels 0-31 mapped to combinations of blocks
        let blocks: [String] = [
            "▁", "▁", "▂", "▂",
            "▂", "▃", "▃", "▃",
            "▄", "▄", "▄", "▅",
            "▅", "▅", "▆", "▆",
            "▆", "▇", "▇", "▇",
            "▇", "█", "█", "█",
            "█", "█", "█", "█",
            "█", "█", "█", "█",
        ]
        let recent = Array(data.suffix(width))
        let padded = Array(repeating: 0.0, count: max(0, width - recent.count)) + recent
        let maxVal = padded.max().flatMap { $0 > 0 ? $0 : nil } ?? 1
        let sparkline: String = padded.map { val in
            // Always show baseline (▁), even when there's traffic
            if val <= 0 { return blocks[0] }
            let idx = Int((val / maxVal) * Double(blocks.count - 1))
            return blocks[max(1, min(idx, blocks.count - 1))]
        }.joined()

        Text(sparkline)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(color)
            .fixedSize()
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(MetricsModel.self) var service

    var body: some View {
        Group {
            if let snap = service.snapshot {
                ScrollView {
                    VStack(spacing: 16) {
                        headerBar(snap)
                        MoleAnimationView()
                        equalHeightRow {
                            cpuCard(snap.cpu, thermal: snap.thermal)
                            memoryCard(snap.memory)
                        }
                        equalHeightRow {
                            diskCard(snap.disks, io: snap.diskIO)
                            powerCard(snap.batteries, thermal: snap.thermal)
                        }
                        equalHeightRow {
                            processCard(snap.topProcesses)
                            networkCard(
                                snap.network,
                                history: service.networkHistoryForDisplay(from: snap.networkHistory),
                                proxy: snap.proxy
                            )
                        }
                    }
                    .padding()
                }
            } else if let error = service.errorMessage {
                ContentUnavailableView(
                    "Connection Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                MoleLoadingState(title: "Loading system metrics...")
            }
        }
        .task {
            // Start metrics collection when Dashboard appears
            service.start()
        }
        .onDisappear {
            // Stop metrics collection when Dashboard disappears
            service.stop()
        }
    }

    // MARK: - Header

    private func equalHeightRow(
        @ViewBuilder content: () -> TupleView<(some View, some View)>
    ) -> some View {
        let views = content()
        return HStack(alignment: .top, spacing: 12) {
            views.value.0.frame(maxHeight: .infinity, alignment: .top)
            views.value.1.frame(maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func headerBar(_ snap: MetricsSnapshot) -> some View {
        let hw = snap.hardware

        return MoleHeroPanel(
            eyebrow: "Monitor",
            title: "Status",
            subtitle: "\(hw.model) · \(hw.cpuModel) · \(hw.totalRAM)/\(hw.diskSize) · \(hw.osVersion)",
            symbol: "waveform.path.ecg"
        ) {
            VStack(alignment: .trailing, spacing: 10) {
                MoleMetricBadge(
                    title: "Health",
                    value: "\(snap.healthScore)",
                    systemImage: "heart.circle.fill",
                    tint: snap.healthScore >= 75 ? .green : snap.healthScore >= 60 ? .orange : .red
                )
                MoleMetricBadge(
                    title: "Uptime",
                    value: snap.uptime,
                    systemImage: "clock.arrow.circlepath",
                    tint: MoleTheme.sky
                )
            }
        }
    }

    // MARK: - CPU

    private func cpuCard(_ cpu: CPUStatus, thermal: ThermalStatus) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("CPU", systemImage: "cpu").font(.headline)
                HStack {
                    Text("Total").frame(width: 50, alignment: .leading)
                    UsageBar(cpu.usage)
                    Text(String(format: "%.1f%% @ %.1f°C", cpu.usage, thermal.cpuTemp))
                        .monospacedDigit()
                }
                let topCores = Array(cpu.perCore.enumerated())
                    .sorted { $0.element > $1.element }.prefix(3)
                ForEach(Array(topCores), id: \.offset) { idx, val in
                    HStack {
                        Text("Core\(idx + 1)").frame(width: 50, alignment: .leading)
                        UsageBar(val)
                        Text(String(format: "%.1f%%", val)).monospacedDigit()
                    }
                }
                HStack {
                    Text("Load")
                    Text(String(format: "%.2f / %.2f / %.2f", cpu.load1, cpu.load5, cpu.load15))
                    if cpu.pCoreCount > 0 {
                        Text("\(cpu.pCoreCount)P+\(cpu.eCoreCount)E")
                    }
                }
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Memory

    private func memoryCard(_ mem: MemoryStatus) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("Memory", systemImage: "memorychip").font(.headline)
                HStack {
                    Text("Used").frame(width: 50, alignment: .leading)
                    UsageBar(mem.usedPercent, color: .yellow)
                    Text(String(format: "%.1f%%", mem.usedPercent)).monospacedDigit()
                }
                HStack {
                    Text("Free").frame(width: 50, alignment: .leading)
                    UsageBar(100 - mem.usedPercent, color: .green)
                    Text(String(format: "%.1f%%", 100 - mem.usedPercent)).monospacedDigit()
                }
                HStack {
                    Text("Total")
                    Text("\(MetricsFormatter.humanBytes(mem.used)) / \(MetricsFormatter.humanBytes(mem.total))")
                }
                HStack {
                    Text("Cached \(MetricsFormatter.humanBytes(mem.cached))")
                    Spacer()
                    Text("Avail \(MetricsFormatter.humanBytes(mem.total - mem.used))")
                }
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Disk

    private func diskCard(_ disks: [DiskStatus], io: DiskIOStatus) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("Disk", systemImage: "internaldrive").font(.headline)
                ForEach(disks.prefix(4), id: \.mount) { d in
                    let label = d.external ? "EXTR" : "INTR"
                    HStack {
                        Text(label).frame(width: 40, alignment: .leading)
                        UsageBar(d.usedPercent)
                        Text(String(format: "%.0f%%", d.usedPercent))
                            .monospacedDigit()
                            .frame(width: 35, alignment: .trailing)
                        Text("\(MetricsFormatter.humanBytes(d.used))/\(MetricsFormatter.humanBytes(d.total))")
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .trailing)
                    }
                }
                HStack {
                    Text("Read")
                    Text(MetricsFormatter.formatRate(io.readRate))
                    Spacer()
                    Text("Write")
                    Text(MetricsFormatter.formatRate(io.writeRate))
                }
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Power

    private func powerCard(_ batteries: [BatteryStatus], thermal: ThermalStatus) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("Power", systemImage: "battery.75percent").font(.headline)
                if let bat = batteries.first {
                    HStack {
                        Text("Level").frame(width: 50, alignment: .leading)
                        UsageBar(bat.percent, color: .green, autoThreshold: false)
                        Text(String(format: "%.0f%%", bat.percent)).monospacedDigit()
                    }
                    HStack {
                        Text(bat.status.capitalized)
                            .foregroundStyle(bat.status.lowercased() == "charging" ? .green : .secondary)
                        if thermal.adapterPower > 0 {
                            Text(String(format: "· %.0fW Adapter ⚡", thermal.adapterPower))
                        }
                    }
                    HStack {
                        Text("\(bat.health) · \(bat.cycleCount) cycles · \(String(format: "%.1f°C", thermal.cpuTemp))")
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text("No battery").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Processes

    private func processCard(_ procs: [MoleProcessInfo]) -> some View {
        let items = Array(procs.prefix(5))
        return GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("Processes", systemImage: "list.bullet").font(.headline)
                ForEach(items.indices, id: \.self) { i in
                    HStack {
                        Text(items[i].name)
                            .lineLimit(1)
                            .frame(width: 110, alignment: .leading)
                        UsageBar(items[i].cpu, color: .green)
                        Text(String(format: "%.1f%%", items[i].cpu))
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Network

    private func networkCard(
        _ nets: [NetworkStatus],
        history: NetworkHistory,
        proxy: ProxyStatus
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("Network", systemImage: "network").font(.headline)
                HStack {
                    Text("Down").frame(width: 40, alignment: .leading)
                    MiniSparklineView(data: history.rxHistory, color: .green)
                    Spacer()
                    let totalRx = nets.reduce(0.0) { $0 + $1.rxRateMBs }
                    Text(MetricsFormatter.formatRate(totalRx)).monospacedDigit()
                }
                HStack {
                    Text("Up").frame(width: 40, alignment: .leading)
                    MiniSparklineView(data: history.txHistory, color: .cyan)
                    Spacer()
                    let totalTx = nets.reduce(0.0) { $0 + $1.txRateMBs }
                    Text(MetricsFormatter.formatRate(totalTx)).monospacedDigit()
                }
                // Show proxy and IP on same line
                HStack(spacing: 4) {
                    if proxy.enabled {
                        Text("Proxy \(proxy.type) · \(proxy.host)")
                            .foregroundStyle(.secondary)
                    }
                    if let primaryNet = nets.first(where: { !$0.ip.isEmpty }) {
                        if proxy.enabled {
                            Text("·")
                                .foregroundStyle(.secondary)
                        }
                        Text(primaryNet.ip)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
            .padding(.vertical, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }
}
