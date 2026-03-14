import SwiftUI

@main
struct MoleApp: App {
    @State private var metricsModel = MetricsModel()
    @State private var cleanModel = CleanModel()
    @State private var optimizeModel = OptimizeModel()
    @State private var purgeModel = PurgeModel()
    @State private var installerModel = InstallerModel()
    @State private var diskModel = DiskModel()
    @State private var appScanModel = AppScanModel()
    @State private var uninstallModel = UninstallModel()
    @State private var safetyController = SafetyController()
    @State private var versionModel = VersionModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(metricsModel)
                .environment(cleanModel)
                .environment(optimizeModel)
                .environment(purgeModel)
                .environment(installerModel)
                .environment(diskModel)
                .environment(appScanModel)
                .environment(uninstallModel)
                .environment(safetyController)
                .environment(versionModel)
                .groupBoxStyle(MolePanelGroupBoxStyle())
                .tint(Color(red: 0.16, green: 0.48, blue: 0.36))
                .frame(minWidth: 980, minHeight: 700)
                .onAppear {
                    // Wire up model references for metrics pause coordination
                    // This must be done after models are initialized
                    metricsModel.cleanModel = cleanModel
                    metricsModel.optimizeModel = optimizeModel
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
    }
}
