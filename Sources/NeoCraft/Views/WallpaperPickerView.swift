import SwiftUI

/// Horizontal picker for the animated wallpaper effects offered in Neo
/// Studio. Selection persists via `AppSettings.wallpaperStyle`.
struct WallpaperPickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(WallpaperStyle.allCases) { style in
                    wallpaperCard(style)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func wallpaperCard(_ style: WallpaperStyle) -> some View {
        let selected = model.settings.wallpaperStyle == style.rawValue
        return Button {
            model.settings.wallpaperStyle = style.rawValue
            model.showToast("Wallpaper: \(style.title)")
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(wallpaperPreview(style))
                        .frame(width: 96, height: 58)
                    // Miniature effect hint.
                    Image(systemName: style.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .padding(8)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            selected ? Color.white.opacity(0.7) : Color.primary.opacity(0.12),
                            lineWidth: selected ? 2 : 1
                        )
                }
                Text(style.title)
                    .font(.neoCaption)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 96, alignment: .leading)
                Text(style.subtitle)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .frame(width: 96, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func wallpaperPreview(_ style: WallpaperStyle) -> AnyShapeStyle {
        let accent = Color(hex: StudioTheme.effectiveAccentHex)
        let glow = NeoPalette.glow
        switch style {
        case .plain:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hex: "F2F5FA"), Color(hex: "DDE6F2")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .aurora:
            return AnyShapeStyle(LinearGradient(
                colors: [accent.opacity(0.85), glow.opacity(0.7), Color(hex: "0B1220")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .cherryPetals:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hex: "F7C6D9"), Color(hex: "7A3550"), Color(hex: "24101C")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .endSky:
            return AnyShapeStyle(RadialGradient(
                colors: [Color(hex: "4C3A78"), Color(hex: "1B1436"), Color(hex: "0B0817")],
                center: UnitPoint(x: 0.72, y: 0.18),
                startRadius: 4,
                endRadius: 110
            ))
        case .netherEmbers:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hex: "3A1410"), Color(hex: "1A0806"), Color(hex: "050202")],
                startPoint: .bottom, endPoint: .top
            ))
        }
    }
}
