import SwiftUI

extension View {
    func panel() -> some View {
        padding(16)
            .frame(maxWidth: 720, alignment: .leading)
            .panelBackground()
    }

    /// A panel's fill, border and shadow — NeoCraft's card: a thin material
    /// with its gradient edge, for content that lays itself out.
    /// The card material Neo Studio's glass-blur slider picks — the same
    /// thresholds as `NeoCardModifier.cardMaterial`.
    private var panelMaterial: Material {
        switch NeoSync.shared.glassBlur {
        case ..<0.34: .ultraThinMaterial
        case ..<0.67: .thinMaterial
        case ..<0.9: .regularMaterial
        default: .thickMaterial
        }
    }

    func panelBackground(opacity: Double = 0.92) -> some View {
        background {
            ZStack {
                if let tint = NeoSync.shared.cardTint {
                    RoundedRectangle(cornerRadius: NeoSync.shared.radius(16), style: .continuous)
                        .fill(tint.opacity(0.08))
                }
                RoundedRectangle(cornerRadius: NeoSync.shared.radius(16), style: .continuous)
                    .fill(panelMaterial)
                    .opacity(opacity)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: NeoSync.shared.radius(16), style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22), Color.white.opacity(0.04),
                            Color.black.opacity(0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
    }
}

struct PanelSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TitleText(title, size: 14)
            content.toggleStyle(.pixel)
        }
        .panel()
    }
}

struct RowLabel: View {
    let title: Text
    let detail: Text

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey) {
        self.title = Text(title)
        self.detail = Text(detail)
    }

    init(verbatim title: String, detail: String) {
        self.title = Text(verbatim: title)
        self.detail = Text(verbatim: detail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
                .font(.neoPixelBold(12))
                .foregroundStyle(Palette.text)
            detail
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
