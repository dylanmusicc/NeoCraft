import SwiftUI

/// NeoCraft's button: a rounded face — the accent gradient for the main action, a light wash for
/// the rest — with a bevel edge, a soft glow on the accent and a press that sinks it a little.
struct PixelButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary, danger

        fileprivate var accent: Color {
            switch self {
            case .primary: Palette.accent
            case .secondary: Color.white
            case .danger: Palette.negative
            }
        }

        fileprivate var isAccent: Bool { self != .secondary }
    }

    var kind = Kind.secondary
    var size: CGFloat = 13
    var minHeight: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, kind: kind, size: size, minHeight: minHeight)
    }

    private struct Face: View {
        let configuration: Configuration
        let kind: Kind
        let size: CGFloat
        let minHeight: CGFloat?
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let corner = NeoSync.shared.radius(10)
            let accent = kind.accent
            let face: AnyShapeStyle =
                kind.isAccent
                ? AnyShapeStyle(
                    LinearGradient(
                        colors: [accent, accent.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                : AnyShapeStyle(
                    Color(nsColor: .controlBackgroundColor).opacity(isEnabled ? 0.62 : 0.4))
            configuration.label
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    isEnabled
                        ? (kind.isAccent ? Color.white : Palette.text)
                        : Palette.disabledText)
                .lineLimit(1)
                // As tall as an icon in a button, so that a row of buttons lines up.
                .frame(minHeight: size + 5)
                .padding(.horizontal, size * 1.15)
                .padding(.vertical, size * 0.65)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(face))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            kind.isAccent
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.55), Color.white.opacity(0.06),
                                            Color.black.opacity(0.30),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                : AnyShapeStyle(Color.primary.opacity(0.11)),
                            lineWidth: kind.isAccent ? 1 : 0.8
                        )
                }
                .shadow(
                    color: kind.isAccent && isEnabled ? accent.opacity(0.28) : .clear,
                    radius: 8, x: 0, y: 3
                )
                .scaleEffect(configuration.isPressed && isEnabled ? 0.965 : 1)
                .opacity(configuration.isPressed && isEnabled ? 0.92 : 1)
                .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
                .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }
}

extension ButtonStyle where Self == PixelButtonStyle {
    static func pixel(
        _ kind: PixelButtonStyle.Kind = .secondary, size: CGFloat = 13, minHeight: CGFloat? = nil
    ) -> PixelButtonStyle {
        PixelButtonStyle(kind: kind, size: size, minHeight: minHeight)
    }
}
