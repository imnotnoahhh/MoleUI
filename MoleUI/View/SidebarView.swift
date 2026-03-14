import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                brandHeader

                sidebarSection("Monitor", items: [.status, .diskAnalyzer])
                sidebarSection("Cleanup", items: [.clean, .purge, .installer, .optimize, .uninstall])
                sidebarSection("App", items: [.settings])
            }
            .padding(.horizontal, 14)
            .padding(.top, 50)
            .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.bar)
    }

    private var brandHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(MoleTheme.pine)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mole UI")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MoleTheme.ink)

                Text("System care for macOS")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private func sidebarSection(_ title: String, items: [SidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(MoleTheme.pine)
                .padding(.horizontal, 4)

            VStack(spacing: 4) {
                ForEach(items) { item in
                    sidebarRow(item)
                }
            }
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = selection == item

        return Button {
            selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : MoleTheme.pine)
                    .frame(width: 24, height: 24)

                Text(item.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : MoleTheme.ink)

                Spacer(minLength: 6)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [MoleTheme.pine, MoleTheme.moss],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(.thinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.20) : MoleTheme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
