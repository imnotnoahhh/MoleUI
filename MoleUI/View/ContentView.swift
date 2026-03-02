import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case status = "Status"
    case diskAnalyzer = "Disk Analyzer"
    case clean = "Clean"
    case purge = "Purge"
    case installer = "Installers"
    case optimize = "Optimize"
    case uninstall = "Uninstall"
    case settings = "Settings"

    var id: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .status: return "waveform.path.ecg"
        case .diskAnalyzer: return "internaldrive"
        case .clean: return "trash"
        case .purge: return "folder.badge.minus"
        case .installer: return "opticaldiscdrive"
        case .optimize: return "bolt.fill"
        case .uninstall: return "xmark.app"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .status
    @Environment(MetricsModel.self) var metricsModel

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedItem)
        } detail: {
            detailView
        }
        .onAppear {
            metricsModel.start()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .status:
            DashboardView()
        case .diskAnalyzer:
            DiskAnalyzerView()
        case .clean:
            CleanView()
        case .purge:
            PurgeView()
        case .installer:
            InstallerView()
        case .optimize:
            OptimizeView()
        case .uninstall:
            UninstallView()
        case .settings:
            SettingsView()
        case nil:
            Text("Select an item from the sidebar")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
