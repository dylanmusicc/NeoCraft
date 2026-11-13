import AppKit
import CoreText
import SwiftUI

// MARK: - Palette

enum NeoPalette {
    /// Studio accent — follows the user's Neo Studio accent choice and the
    /// time-of-day drift in Dynamic mode.
    static var accent: Color { Color(hex: StudioTheme.effectiveAccentHex) }
    static var accentDeep: Color { Color(hex: Self.darken(StudioTheme.effectiveAccentHex, factor: 0.72)) }
    /// Secondary glow from Neo Studio's color mixer.
    static var glow: Color { Color(hex: StudioTheme.glowHex) }
    /// Optional card surface tint ("" → clear).
    static var cardTint: Color {
        let hex = StudioTheme.cardTintHex
        return hex.isEmpty ? .clear : Color(hex: hex)
    }

    static func darken(_ hex: String, factor: Double) -> String {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Int((Double((value >> 16) & 0xFF) * factor).rounded())
        let g = Int((Double((value >> 8) & 0xFF) * factor).rounded())
        let b = Int((Double(value & 0xFF) * factor).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
    static let mint = Color(hex: "4ADE80")
    static let sky = Color(hex: "38BDF8")
    static let violet = Color(hex: "A78BFA")
    static let amber = Color(hex: "FBBF24")
    static let orange = Color(hex: "FB923C")
    static let rose = Color(hex: "FB7185")
    static let danger = Color(hex: "F87171")
    static let ink = Color(hex: "0B1220")
    static let slate = Color(hex: "64748B")

    // Minecraft block tones
    static let grass = Color(hex: "7CBD4B")
    static let grassDeep = Color(hex: "4E7A2E")
    static let dirt = Color(hex: "79553A")
    static let stone = Color(hex: "8C8C8C")
}

// MARK: - Pixel fonts

enum NeoFonts {
    static let pixel = "Silkscreen-Regular"
    static let pixelBold = "Silkscreen-Bold"
    static let display = "PressStart2P-Regular"

    /// Registers the bundled .ttf files with CoreText. Fonts live in
    /// Contents/Resources/Fonts (copied by build.sh); when the binary runs
    /// outside the .app bundle the lookups simply fall back to system fonts.
    static func register() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return
        }
        for file in files where file.lowercased().hasSuffix(".ttf") {
            CTFontManagerRegisterFontsForURL(dir.appendingPathComponent(file) as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func neoPixel(_ size: CGFloat) -> Font {
        .custom(NeoFonts.pixel, size: size)
    }

    static func neoPixelBold(_ size: CGFloat) -> Font {
        .custom(NeoFonts.pixelBold, size: size)
    }

    static func neoDisplay(_ size: CGFloat) -> Font {
        .custom(NeoFonts.display, size: size)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        switch cleaned.count {
        case 3:
            red = Double((value >> 8) & 0xF) / 15
            green = Double((value >> 4) & 0xF) / 15
            blue = Double(value & 0xF) / 15
            alpha = 1
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        default:
            red = 0.5
            green = 0.5
            blue = 0.55
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Background

struct NeoBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Pure OLED Dark renders true black; Frosted and Dynamic keep the
    /// layered gradient look.
    private var oled: Bool {
        StudioTheme.mode == .oled && colorScheme == .dark
    }

    var body: some View {
        ZStack {
            (oled ? Color.black : (colorScheme == .dark ? Color(hex: "080B11") : Color(hex: "F2F5FA")))

            if !oled {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(hex: "0B1422"), Color(hex: "081019"), Color(hex: "0A0E18")]
                        : [Color(hex: "F7FAFF"), Color(hex: "EEF3FB"), Color(hex: "F4F7FD")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            if StudioTheme.wallpaperStyle != .plain {
                VoxelField()
                    .opacity((colorScheme == .dark ? 0.55 : 0.4) * StudioTheme.gridIntensity)
            }

            WallpaperEffectLayer()

            if StudioTheme.wallpaperStyle != .plain {
                WallpaperBlooms()
            }
        }
        .ignoresSafeArea()
    }
}

/// A deterministic scatter of translucent "voxels" in Minecraft block tones
/// (grass, dirt, stone) that gives the app background a subtle in-game feel.
struct VoxelField: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: [Color] {
        colorScheme == .dark
            ? [
                Color(hex: "6FA83F"), Color(hex: "7CBD4B"), Color(hex: "87C95A"),
                Color(hex: "8A5A32"), Color(hex: "79553A"), Color(hex: "6E4B2E"),
                Color(hex: "7D7D7D"), Color(hex: "8C8C8C"), Color(hex: "9AA0A6")
            ]
            : [
                Color(hex: "A8D08A"), Color(hex: "94C46E"), Color(hex: "B98D5F"),
                Color(hex: "A97850"), Color(hex: "C4A284"), Color(hex: "B0B0B0"),
                Color(hex: "C9CDD1")
            ]
    }

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 34
            let cols = Int(ceil(size.width / cell)) + 1
            let rows = Int(ceil(size.height / cell)) + 1
            let alpha: Double = colorScheme == .dark ? 0.16 : 0.11

            for row in 0..<rows {
                for col in 0..<cols {
                    let fill = Self.hash(col, row)
                    guard fill < 0.52 else { continue }

                    let pick = Self.hash(col &+ 91, row &+ 57)
                    let color = palette[Int(pick * CGFloat(palette.count)) % palette.count]
                    let tall = Self.hash(col &+ 33, row &+ 11) < 0.16

                    var rect = CGRect(
                        x: CGFloat(col) * cell + 2,
                        y: CGFloat(row) * cell + 2,
                        width: cell - 4,
                        height: cell - 4
                    )
                    if tall {
                        rect.size.height = cell * 1.9 - 4
                    }

                    context.fill(Path(rect), with: .color(color.opacity(alpha)))
                }
            }
        }
        .blur(radius: 0.8)
    }

    private static func hash(_ x: Int, _ y: Int) -> CGFloat {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return CGFloat(h % 10_000) / 10_000
    }
}

// MARK: - Voxel accents

/// Isometric grass-block cube drawn with Canvas — the NeoCraft brand mark.
/// Three faces in Minecraft block tones: grass top, dirt left, darker dirt
/// right, with a faint top-left light edge like a lit in-game block.
struct VoxelCube: View {
    var size: CGFloat = 40
    /// "grass" (default), "stone", "netherrack", "endstone" or "diamond".
    var variant: String = "grass"

    private var top: Color {
        switch variant {
        case "stone": return Color(hex: "9A9A9A")
        case "netherrack": return Color(hex: "6E2B25")
        case "endstone": return Color(hex: "E3DAA8")
        case "diamond": return Color(hex: "5FE3E0")
        default: return Color(hex: "84CC54")
        }
    }

    private var left: Color {
        switch variant {
        case "stone": return Color(hex: "7C7C7C")
        case "netherrack": return Color(hex: "4A1D1A")
        case "endstone": return Color(hex: "C4B98C")
        case "diamond": return Color(hex: "3FB8B5")
        default: return Color(hex: "79553A")
        }
    }

    private var right: Color {
        switch variant {
        case "stone": return Color(hex: "636363")
        case "netherrack": return Color(hex: "33120F")
        case "endstone": return Color(hex: "A2966E")
        case "diamond": return Color(hex: "2E9693")
        default: return Color(hex: "63452C")
        }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let depth: CGFloat = h * 0.36

            // Top diamond: N, E, S, W (fractions of size).
            let n = CGPoint(x: w * 0.5, y: h * 0.02)
            let e = CGPoint(x: w * 0.98, y: h * 0.27)
            let s = CGPoint(x: w * 0.5, y: h * 0.52)
            let west = CGPoint(x: w * 0.02, y: h * 0.27)
            // Bottom diamond shifted straight down by `depth`.
            let eb = CGPoint(x: e.x, y: e.y + depth)
            let sb = CGPoint(x: s.x, y: s.y + depth)
            let wb = CGPoint(x: west.x, y: west.y + depth)

            func poly(_ pts: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(pts)
                path.closeSubpath()
                return path
            }

            // Left face (W-S-S'-W'), right face (S-E-E'-S'), top last.
            context.fill(poly([west, s, sb, wb]), with: .color(left))
            context.fill(poly([s, e, eb, sb]), with: .color(right))
            context.fill(poly([n, e, s, west]), with: .color(top))

            // Lit top-left edges, like ambient occlusion in-game.
            var edge = Path()
            edge.move(to: n); edge.addLine(to: west)
            edge.move(to: west); edge.addLine(to: wb)
            edge.move(to: n); edge.addLine(to: e)
            context.stroke(edge, with: .color(Color.white.opacity(0.35)),
                           style: StrokeStyle(lineWidth: max(1, w * 0.022), lineCap: .round, lineJoin: .round))

            var shade = Path()
            shade.move(to: e); shade.addLine(to: eb)
            shade.move(to: s); shade.addLine(to: sb)
            shade.move(to: sb); shade.addLine(to: eb)
            shade.move(to: s); shade.addLine(to: e)
            context.stroke(shade, with: .color(Color.black.opacity(0.22)),
                           style: StrokeStyle(lineWidth: max(0.8, w * 0.018), lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A thin pixelated "grass block" strip — green top row over dirt rows —
/// used as a subtle Minecraft signature inside cards and headers.
struct NeoGrassEdge: View {
    var height: CGFloat = 10

    private static func hash(_ x: Int, _ y: Int) -> CGFloat {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return CGFloat(h % 10_000) / 10_000
    }

    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 4
            let cols = Int(ceil(size.width / cell))
            let rows = max(1, Int(ceil(size.height / cell)))
            let grassTop = [Color(hex: "7CBD4B"), Color(hex: "6FAE3F"), Color(hex: "87CE55")]
            let dirt = [Color(hex: "79553A"), Color(hex: "6E4B2E"), Color(hex: "835F42")]

            for row in 0..<rows {
                for col in 0..<cols {
                    let palette = row == 0 ? grassTop : dirt
                    let pick = Int(Self.hash(col, row) * CGFloat(palette.count)) % palette.count
                    let rect = CGRect(
                        x: CGFloat(col) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(Path(rect), with: .color(palette[pick]))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

struct NeoCardModifier: ViewModifier {
    var padding: CGFloat
    var cornerRadius: CGFloat

    /// Neo Studio corner style scales the requested radius; "Sharp Voxel"
    /// clamps everything to a crisp small radius, then the radius preset
    /// multiplies the result.
    private var effectiveRadius: CGFloat {
        let base = StudioTheme.cornerStyle == .voxel ? min(cornerRadius, 6) : cornerRadius
        return base * StudioTheme.radiusPreset.scale
    }

    /// Card material chosen by the Studio glass-blur slider: lower values
    /// pick thinner, more translucent materials.
    private var cardMaterial: Material {
        switch StudioTheme.glassBlur {
        case ..<0.34: .ultraThinMaterial
        case ..<0.67: .thinMaterial
        case ..<0.9: .regularMaterial
        default: .thickMaterial
        }
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
                        .fill(cardMaterial)
                    if StudioTheme.cardTintHex.isEmpty == false {
                        RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
                            .fill(NeoPalette.cardTint.opacity(0.10))
                    }
                }
            }
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: effectiveRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0.04),
                                    Color.black.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
    }
}

/// Sidebar backdrop honoring the Studio translucency slider: lower values
/// pick lighter materials and add an accent wash so glass stays legible.
struct StudioSidebarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let material: Material = {
            switch StudioTheme.sidebarMaterial {
            case ..<0.34: .ultraThinMaterial
            case ..<0.67: .thinMaterial
            default: .regularMaterial
            }
        }()
        ZStack {
            Rectangle().fill(material)
            NeoPalette.accent.opacity(
                colorScheme == .dark
                    ? (1 - StudioTheme.sidebarMaterial) * 0.10
                    : (1 - StudioTheme.sidebarMaterial) * 0.06
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    func neoCard(padding: CGFloat = 18, cornerRadius: CGFloat = 16) -> some View {
        modifier(NeoCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Headers

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: () -> Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VoxelCube(size: 30)
                .shadow(color: NeoPalette.grass.opacity(0.35), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.neoPixelBold(27))
                    .tracking(0.5)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = NeoPalette.accent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.neoPixelBold(12.5))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Pills & badges

struct NeoPill: View {
    var text: String
    var symbol: String?
    var tint: Color = NeoPalette.accent
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.neoPixel(10))
                .tracking(0.3)
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Color.white : tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(filled ? tint : tint.opacity(0.13), in: Capsule())
        .overlay {
            if !filled {
                Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.6)
            }
        }
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 7
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(colorScheme == .dark ? 0.8 : 0.4), radius: 4)
    }
}

// MARK: - Buttons

struct NeoButtonStyle: ButtonStyle {
    enum Kind: Equatable {
        case primary
        case secondary
        case ghost
        case danger
        /// Minecraft-style raised block button (stone grey, dark bevel).
        case block
    }

    var kind: Kind = .secondary
    var tint: Color = NeoPalette.accent
    var compact: Bool = false
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11.5 : 13, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 11 : 15)
            .padding(.vertical, compact ? 6.5 : 8.5)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background {
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .fill(backgroundStyle)
            }
            .overlay {
                if kind == .primary || kind == .danger {
                    // Minecraft-style bevel: lit top edge, dark bottom edge.
                    RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.06),
                                    Color.black.opacity(0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                } else if kind == .block {
                    RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.65),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.38)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                } else if kind == .secondary || kind == .ghost {
                    RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(kind == .ghost ? 0.06 : 0.11), lineWidth: 0.8)
                }
            }
            .shadow(
                color: (kind == .primary || kind == .danger) ? tint.opacity(0.28) : Color.clear,
                radius: 8,
                x: 0,
                y: 3
            )
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger:
            return .white
        case .block:
            return NeoPalette.ink
        case .secondary:
            return .primary
        case .ghost:
            return tint
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        switch kind {
        case .primary:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [tint, tint.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .danger:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [NeoPalette.danger, NeoPalette.danger.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .block:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: "A9A9A9"), Color(hex: "8E8E8E"), Color(hex: "6E6E6E")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .secondary:
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.62))
        case .ghost:
            return AnyShapeStyle(Color.clear)
        }
    }
}

// MARK: - Instance tiles & images

struct InstanceIconTile: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.32), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: color.opacity(0.55), radius: 5, y: 2)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: color.opacity(0.34), radius: 10, x: 0, y: 5)
    }
}

struct RemoteImage: View {
    var url: URL?
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 13

    var body: some View {
        AsyncImage(
            url: url,
            transaction: Transaction(animation: .easeOut(duration: 0.18))
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                placeholder
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            case .failure:
                placeholder
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [NeoPalette.accent.opacity(0.22), NeoPalette.violet.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(NeoPalette.accent.opacity(0.85))
        }
    }
}

struct AvatarView: View {
    var uuid: String
    var size: CGFloat = 36
    /// Local skin image (offline accounts). When present it replaces the
    /// Crafatar lookup entirely.
    var localImage: NSImage? = nil

    @State private var remoteSkin: NSImage?

    private static let skinCache = NSCache<NSString, NSImage>()

    var body: some View {
        Group {
            if let skin = localImage ?? remoteSkin {
                Image(nsImage: Self.headCrop(skin))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
        .task(id: uuid) { await loadRemoteSkin() }
    }

    /// Fetches the player's raw 64×64 skin from Crafatar so the avatar can
    /// show the real skin face instead of a rendered bust.
    private func loadRemoteSkin() async {
        guard localImage == nil else { return }
        if let cached = Self.skinCache.object(forKey: uuid as NSString) {
            remoteSkin = cached
            return
        }
        guard let encoded = uuid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://crafatar.com/skins/\(encoded)") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let skin = NSImage(data: data) else { return }
            Self.skinCache.setObject(skin, forKey: uuid as NSString)
            remoteSkin = skin
        } catch {
            // Offline/unknown UUIDs simply keep the fallback avatar.
        }
    }

    /// Crops the head front face out of a Minecraft skin PNG and composites
    /// the hat/overlay layer on top. Works for both 64×64 and legacy 64×32
    /// skins — the head front sits at (8,8)–(16,16) and its overlay at
    /// (40,8)–(48,16) in top-left pixel coordinates, identical in both
    /// formats. CGImage cropping keeps the pixel math unambiguous.
    private static func headCrop(_ skin: NSImage) -> NSImage {
        guard let cgImage = skin.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let face = cgImage.cropping(to: CGRect(x: 8, y: 8, width: 8, height: 8)),
              let hat = cgImage.cropping(to: CGRect(x: 40, y: 8, width: 8, height: 8)) else {
            return skin
        }
        // Render at 16×16 so the face stays crisp on Retina displays.
        let scale: CGFloat = 2
        let edge = 8 * Int(scale)
        guard let context = CGContext(
            data: nil, width: edge, height: edge,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return skin }
        let dest = CGRect(x: 0, y: 0, width: edge, height: edge)
        context.interpolationQuality = .none
        context.draw(face, in: dest)
        // Transparent hat pixels leave the base face untouched.
        context.draw(hat, in: dest)
        guard let cropped = context.makeImage() else { return skin }
        return NSImage(cgImage: cropped, size: NSSize(width: 8, height: 8))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [NeoPalette.accent.opacity(0.35), NeoPalette.violet.opacity(0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

struct NeoCard<Content: View>: View {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content.neoCard(padding: padding, cornerRadius: cornerRadius)
    }
}

// MARK: - Loader badges

/// Visual identity for a mod loader. Colors and glyphs are NeoCraft's own
/// take on each loader's brand — extend `ModLoader.badgeHex` when new
/// loaders (NeoForge, OptiFine, …) are supported.
struct LoaderBadge: View {
    var loader: ModLoader
    var size: CGFloat = 22
    var showTitle: Bool = false

    private var color: Color { Color(hex: loader.badgeHex) }

    var body: some View {
        HStack(spacing: showTitle ? 5 : 0) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [color, color.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: loader.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.8)
            }

            if showTitle {
                Text(loader.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Metrics

struct MetricBar: View {
    var title: String
    var value: Double
    var detail: String
    var tint: Color = NeoPalette.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(5, proxy.size.width * min(max(value, 0), 1)))
                }
            }
            .frame(height: 7)
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 0.7)
        }
    }
}

struct MiniStat: View {
    var label: String
    var value: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .bold))
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Activities

struct ActivityRow: View {
    var activity: Activity

    private var tint: Color {
        switch activity.state {
        case .running: return NeoPalette.accent
        case .success: return NeoPalette.mint
        case .failure: return NeoPalette.danger
        }
    }

    private var symbol: String {
        switch activity.state {
        case .running: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(activity.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(activity.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Text(activity.detail)
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if activity.state == .running, let progress = activity.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(tint)
                        .scaleEffect(x: 1, y: 0.7, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Controls

struct ThermalModeSelector: View {
    @Binding var selection: ThermalMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ThermalMode.allCases) { mode in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = mode
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selection == mode ? Color.white : tint(for: mode))
                            .frame(width: 24, height: 24)
                            .background(
                                (selection == mode ? Color.white.opacity(0.20) : tint(for: mode).opacity(0.13)),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(mode.title)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            Text(mode.shortTitle + " profile")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .opacity(0.7)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selection == mode ? Color.white : Color.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selection == mode ? tint(for: mode) : Color.primary.opacity(0.04))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                selection == mode ? Color.white.opacity(0.20) : Color.primary.opacity(0.08),
                                lineWidth: 0.8
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func tint(for mode: ThermalMode) -> Color {
        switch mode {
        case .coolQuiet: return NeoPalette.sky
        case .maxPerformance: return NeoPalette.amber
        }
    }
}

struct NeoSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7.5)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.58),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
        }
    }
}

struct NeoToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    configuration.label
                }
                Spacer(minLength: 12)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? NeoPalette.accent : Color.primary.opacity(0.16))
                        .frame(width: 38, height: 22)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 17, height: 17)
                        .padding(2.5)
                        .shadow(color: Color.black.opacity(0.16), radius: 2, y: 1)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state & toast

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(NeoPalette.accent)
                .frame(width: 66, height: 66)
                .background(NeoPalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(spacing: 5) {
                Text(title)
                    .font(.neoPixelBold(17))
                Text(message)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(NeoButtonStyle(kind: .primary))
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }
}

struct ToastView: View {
    var message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NeoPalette.mint)
            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(2)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 6)
    }
}

// MARK: - Markdown

struct MarkdownText: View {
    var markdown: String
    var baseSize: CGFloat = 12.5

    var body: some View {
        let cleaned = MarkdownSanitizer.clean(markdown)
        if let attributed = try? AttributedString(
            markdown: cleaned,
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: true,
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            Text(attributed)
                .font(.system(size: baseSize, weight: .regular, design: .rounded))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(cleaned)
                .font(.system(size: baseSize, weight: .regular, design: .rounded))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Modrinth and patch notes mix Markdown with embedded HTML. `AttributedString`
/// only understands Markdown, so normalise the common HTML constructs into
/// plain text first instead of leaking tags into the UI.
enum MarkdownSanitizer {
    static func clean(_ raw: String) -> String {
        var text = raw

        // HTML comments
        text = text.replacingOccurrences(
            of: "<!--.*?-->",
            with: "",
            options: [.regularExpression]
        )

        // Images: drop remote images, keep any useful alt text.
        text = text.replacingOccurrences(
            of: "<img[^>]*alt=\"([^\"]*)\"[^>]*>",
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<img[^>]*>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "!\\[[^\\]]*\\]\\([^\\)]*\\)",
            with: "",
            options: [.regularExpression]
        )

        // Block level elements become line breaks.
        text = text.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "</?(p|div|center|section|article|header|footer|h[1-6]|tr|table|blockquote)[^>]*>",
            with: "\n\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<li[^>]*>",
            with: "\n• ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "</li>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<hr[^>]*>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )

        // Links: keep the visible label.
        text = text.replacingOccurrences(
            of: "<a[^>]*>(.*?)</a>",
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )

        // Any remaining tag.
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: [.regularExpression]
        )

        // Common entities.
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…")
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(
            of: "&#(\\d+);",
            with: "",
            options: [.regularExpression]
        )

        // Tidy whitespace so removed blocks don't leave gaps.
        text = text.replacingOccurrences(
            of: "[ \\t]+\\n",
            with: "\n",
            options: [.regularExpression]
        )
        text = text.replacingOccurrences(
            of: "\\n{3,}",
            with: "\n\n",
            options: [.regularExpression]
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Misc

struct InfoRow: View {
    var label: String
    var value: String
    var symbol: String?
    var tint: Color = NeoPalette.accent

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 17)
            }
            Text(label)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct NeoDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

struct LoadingStateView: View {
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text(message)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
    }
}

// MARK: - Compatibility shims for newer views

extension Font {
    static var neoBody: Font { .system(size: 12, weight: .regular, design: .rounded) }
    static var neoCaption: Font { .system(size: 10, weight: .medium, design: .rounded) }
    static var neoTitle: Font { .system(size: 20, weight: .bold, design: .rounded) }
    static var neoHeadline: Font { .system(size: 14, weight: .semibold, design: .rounded) }
    static var neoButton: Font { .system(size: 12.5, weight: .bold, design: .rounded) }
    static var neoBadge: Font { .system(size: 8.5, weight: .bold, design: .rounded) }
}

extension Color {
    static var neoAccent: Color { NeoPalette.accent }
    static var neoGrass: Color { NeoPalette.grass }
    static var neoDanger: Color { NeoPalette.danger }
    static var neoCardBackground: Color { Color.primary.opacity(0.05) }
    static var neoCardStroke: Color { Color.primary.opacity(0.12) }
}

/// Small capsule badge used across the new feature views.
struct NeoBadge: View {
    var text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.neoBadge)
            .foregroundStyle(color == .secondary ? Color.secondary : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                (color == .secondary ? Color.primary.opacity(0.08) : color.opacity(0.16)),
                in: Capsule()
            )
    }
}
