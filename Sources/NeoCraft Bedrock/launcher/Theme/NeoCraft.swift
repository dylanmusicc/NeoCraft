import CoreText
import SwiftUI

/// The pixel fonts of NeoCraft, bundled in Contents/Resources/Fonts by the build. Registering
/// them with CoreText makes the custom fonts resolvable by name; outside the .app bundle the
/// lookups fall back to system fonts.
enum NeoFonts {
    static let pixel = "Silkscreen-Regular"
    static let pixelBold = "Silkscreen-Bold"
    static let display = "PressStart2P-Regular"

    static func register() {
        guard
            let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
            let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return }
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

    /// Silkscreen as the launcher's everyday face — the "Minecraft font"
    /// the player asked for everywhere. `size` is the point size the old
    /// rounded system font used; pixel glyphs run visibly larger, so the
    /// rendered size is scaled down to match.
    static func neoUI(_ size: CGFloat, bold: Bool = false) -> Font {
        let scaled = (size * 0.72 * 2).rounded() / 2
        return bold ? .neoPixelBold(scaled) : .neoPixel(scaled)
    }
}

/// The isometric grass-block cube of NeoCraft's brand mark: a lit top in grass green over dirt
/// faces, with faint edges like a block in the game.
struct VoxelCube: View {
    var size: CGFloat = 40
    /// "grass" (default), "stone", "netherrack", "endstone" or "diamond".
    var variant: String = "grass"

    private var top: Color {
        switch variant {
        case "stone": return Color(hex: 0x9A9A9A)
        case "netherrack": return Color(hex: 0x6E2B25)
        case "endstone": return Color(hex: 0xE3DAA8)
        case "diamond": return Color(hex: 0x5FE3E0)
        default: return Color(hex: 0x84CC54)
        }
    }

    private var left: Color {
        switch variant {
        case "stone": return Color(hex: 0x7C7C7C)
        case "netherrack": return Color(hex: 0x4A1D1A)
        case "endstone": return Color(hex: 0xC4B98C)
        case "diamond": return Color(hex: 0x3FB8B5)
        default: return Color(hex: 0x79553A)
        }
    }

    private var right: Color {
        switch variant {
        case "stone": return Color(hex: 0x636363)
        case "netherrack": return Color(hex: 0x33120F)
        case "endstone": return Color(hex: 0xA2966E)
        case "diamond": return Color(hex: 0x2E9693)
        default: return Color(hex: 0x63452C)
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

/// A deterministic scatter of translucent "voxels" in Minecraft block tones that gives the
/// backdrop a subtle in-game feel, like NeoCraft's own background.
struct VoxelField: View {
    @Environment(\.colorScheme) private var colorScheme

    private var palette: [Color] {
        colorScheme == .dark
            ? [
                Color(hex: 0x6FA83F), Color(hex: 0x7CBD4B), Color(hex: 0x87C95A),
                Color(hex: 0x8A5A32), Color(hex: 0x79553A), Color(hex: 0x6E4B2E),
                Color(hex: 0x7D7D7D), Color(hex: 0x8C8C8C), Color(hex: 0x9AA0A6),
            ]
            : [
                Color(hex: 0xA8D08A), Color(hex: 0x94C46E), Color(hex: 0xB98D5F),
                Color(hex: 0xA97850), Color(hex: 0xC4A284), Color(hex: 0xB0B0B0),
                Color(hex: 0xC9CDD1),
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

/// NeoCraft's backdrop, mirroring Neo Studio: the wallpaper effect, grid
/// intensity, bloom colours and OLED black all follow `NeoSync`, which reads
/// the theme NeoCraft writes. "Aurora Bloom" is the layered default — voxel
/// field under wide accent and glow blooms — like NeoCraft draws it.
struct NeoBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let sync = NeoSync.shared
        ZStack {
            dark
                ? (sync.trueBlack ? Color.black : Color(hex: 0x080B11))
                : Color(hex: 0xF2F5FA)
            LinearGradient(
                colors: dark
                    ? [Color(hex: 0x0B1422), Color(hex: 0x081019), Color(hex: 0x0A0E18)]
                    : [Color(hex: 0xF7FAFF), Color(hex: 0xEEF3FB), Color(hex: 0xF4F7FD)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if sync.wallpaperStyle != "plain" {
                VoxelField()
                    .opacity((dark ? 0.55 : 0.4) * sync.gridIntensity)
            }
            NeoWallpaperFX()
            if sync.wallpaperStyle != "plain" {
                blooms(dark: dark, sync: sync)
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func blooms(dark: Bool, sync: NeoSync) -> some View {
        // Aurora Bloom and the particle styles: the accent and glow pair —
        // or the player's custom gradient stops — blurred wide. Deep Dark
        // Pulse and the animated fields draw their own glow on top.
        let colors = sync.bloomColors
        ForEach(colors.indices, id: \.self) { index in
            Circle()
                .fill(colors[index].opacity(dark ? 0.16 : 0.13))
                .frame(width: index == 0 ? 620 : 520, height: index == 0 ? 620 : 520)
                .blur(radius: 140)
                .offset(
                    x: index == 0 ? 380 : -420,
                    y: index == 0 ? -330 : 400
                )
        }
    }
}
