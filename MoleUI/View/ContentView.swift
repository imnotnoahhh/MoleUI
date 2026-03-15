import AppKit
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
        case .status: "waveform.path.ecg"
        case .diskAnalyzer: "internaldrive"
        case .clean: "trash"
        case .purge: "folder.badge.minus"
        case .installer: "opticaldiscdrive"
        case .optimize: "bolt.fill"
        case .uninstall: "xmark.app"
        case .settings: "gear"
        }
    }
}

enum MoleTheme {
    static let pine = Color(red: 0.15, green: 0.39, blue: 0.31)
    static let pineDeep = Color(red: 0.10, green: 0.24, blue: 0.20)
    static let moss = Color(red: 0.35, green: 0.57, blue: 0.41)
    static let meadow = Color.accentColor.opacity(0.16)
    static let parchment = Color(nsColor: .windowBackgroundColor)
    static let sand = Color(nsColor: .underPageBackgroundColor)
    static let ember = Color(red: 0.82, green: 0.39, blue: 0.27)
    static let sky = Color(red: 0.31, green: 0.53, blue: 0.73)
    static let ink = Color.primary
    static let line = Color.primary.opacity(0.10)
}

struct MolePanelGroupBoxStyle: GroupBoxStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(MoleTheme.ink)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.20))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MoleTheme.line, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.06), radius: 18, y: 8)
    }
}

struct MoleSectionHeader: View {
    let title: String
    let subtitle: String?
    let symbol: String

    init(title: String, subtitle: String? = nil, symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MoleTheme.pine)
                .frame(width: 30, height: 30)
                .background(MoleTheme.meadow.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(MoleTheme.ink)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct MoleMetricBadge: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = MoleTheme.pine

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(MoleTheme.ink)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
    }
}

struct MoleSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MoleTheme.line, lineWidth: 1)
        )
    }
}

struct MoleLoadingState: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .progressViewStyle(.circular)

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(MoleTheme.ink)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MoleHeroPanel<Accessory: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    private let accessory: Accessory

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        symbol: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accessory = accessory()
    }

    init(
        eyebrow: String,
        title: String,
        subtitle: String,
        symbol: String
    ) where Accessory == EmptyView {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accessory = EmptyView()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(MoleTheme.pine)
                    Capsule()
                        .fill(MoleTheme.meadow)
                        .frame(width: 28, height: 6)
                }

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(MoleTheme.pineDeep)
                        .frame(width: 44, height: 44)
                        .background(
                            LinearGradient(
                                colors: [MoleTheme.sand, MoleTheme.meadow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(MoleTheme.ink)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 12)

            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            ZStack {
                LinearGradient(
                    colors: [
                        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.22),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(MoleTheme.line, lineWidth: 1)
            }
            .allowsHitTesting(false) // Allow clicks to pass through
        }
        .shadow(color: MoleTheme.pine.opacity(0.08), radius: 22, y: 10)
    }
}

struct MoleDetailBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                Circle()
                    .fill(MoleTheme.sand.opacity(colorScheme == .dark ? 0.22 : 0.55))
                    .frame(width: 360)
                    .blur(radius: 80)
                    .offset(x: 260, y: -220)

                Circle()
                    .fill(MoleTheme.meadow.opacity(colorScheme == .dark ? 0.18 : 0.30))
                    .frame(width: 280)
                    .blur(radius: 70)
                    .offset(x: -300, y: 180)
            }
            .ignoresSafeArea()
        )
    }
}

extension View {
    func moleDetailBackground() -> some View {
        modifier(MoleDetailBackgroundModifier())
    }
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .status

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selectedItem)
                .frame(width: 242)

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .moleDetailBackground()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            VStack(spacing: 16) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .font(.system(size: 34))
                    .foregroundStyle(MoleTheme.pine)
                Text("Pick a workspace lane from the sidebar")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Status, cleanup, uninstall, and privacy tools all live there.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
