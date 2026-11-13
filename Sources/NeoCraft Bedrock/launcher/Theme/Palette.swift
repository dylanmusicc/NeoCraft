import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// A colour that follows the Mac's appearance like NeoCraft's own
    /// surfaces: `light` in light mode, `dark` in dark mode.
    init(appearance light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private func rgba(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

/// The colours of NeoCraft's interface: the deep navy of its backdrop, the light accents of its
/// cards, and the tones of its Minecraft block marks. Surfaces and text follow the Mac's
/// appearance — the dark values are NeoCraft's dark theme, the light values its light theme.
enum Palette {
    /// The darkest ink, for outlines and labels on coloured faces.
    static let ink = Color(hex: 0x05080F)
    /// Neo Studio's Pure OLED mode paints true black; otherwise NeoCraft's navy.
    static var background: Color {
        Color(appearance: rgba(0xF2F5FA), dark: NeoSync.shared.trueBlack ? .black : rgba(0x080B11))
    }
    static let sidebar = Color(appearance: rgba(0xE9EEF7), dark: rgba(0x0C1322))
    /// The face of a card: a light wash over the backdrop's gradient.
    static let panel = Color(
        appearance: NSColor.white.withAlphaComponent(0.62),
        dark: NSColor.white.withAlphaComponent(0.07))
    /// A sunken slot inside a card.
    static let slot = Color(
        appearance: NSColor.black.withAlphaComponent(0.05),
        dark: NSColor.white.withAlphaComponent(0.05))
    /// Floating layers — menus and dialogs — nearly opaque over the window.
    static let popup = Color(appearance: .white, dark: rgba(0x101A30))
    static let text = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let disabledText = Color(nsColor: .tertiaryLabelColor)
    /// NeoCraft's accent — whatever Neo Studio has it set to right now.
    static var accent: Color { NeoSync.shared.accent }
    /// The accent darkened for gradients, like NeoCraft's `accentDeep`.
    static var accentDeep: Color { NeoSync.shared.accentDeep }
    /// NeoCraft's secondary glow — Neo Studio's glow colour.
    static var glow: Color { NeoSync.shared.glow }
    /// The green of its voxel mark.
    static let green = Color(hex: 0x7CBD4B)
    static let positive = Color(hex: 0x4ADE80)
    static let warning = Color(hex: 0xFBBF24)
    static let negative = Color(hex: 0xF87171)
    // NeoCraft's NeoPalette accents, for dashboard cards and pills.
    static let mint = Color(hex: 0x4ADE80)
    static let sky = Color(hex: 0x38BDF8)
    static let amber = Color(hex: 0xFBBF24)
    static let rose = Color(hex: 0xFB7185)
    static let slate = Color(hex: 0x64748B)
}
