import SwiftUI

// MARK: - Neo Studio wallpaper effects
//
// `WallpaperEffectLayer` renders the animated/atmospheric layer selected in
// Neo Studio (`AppSettings.wallpaperStyle`) behind all launcher content.
// Everything here is Canvas/TimelineView-based and capped at a handful of
// dozen primitives so it stays cheap on the A18.

/// Dispatches to the effect matching `StudioTheme.wallpaperStyle`.
struct WallpaperEffectLayer: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch StudioTheme.wallpaperStyle {
        case .plain, .aurora:
            EmptyView()
        case .cherryPetals:
            CherryPetalsField()
        case .endSky:
            EndSkyField()
        case .netherEmbers:
            NetherEmbersField()
        }
    }
}

/// Ambient accent/glow blooms. When the user picked custom gradient colors
/// in Neo Studio (`gradientHexes`), up to three blooms use those stops
/// instead of the single accent + glow pair.
struct WallpaperBlooms: View {
    @Environment(\.colorScheme) private var colorScheme

    private var stops: [Color] {
        let custom = StudioTheme.gradientHexes
        if custom.count >= 2 {
            return custom.prefix(3).map { Color(hex: $0) }
        }
        return [NeoPalette.accent, NeoPalette.glow]
    }

    /// Per-bloom placement so multi-stop gradients spread across the canvas.
    private var placements: [(x: CGFloat, y: CGFloat, size: CGFloat)] {
        switch stops.count {
        case 1:
            return [(380, -330, 620)]
        case 2:
            return [(380, -330, 620), (-420, 400, 520)]
        default:
            return [(380, -330, 620), (-420, 400, 520), (120, 260, 460)]
        }
    }

    var body: some View {
        let dark = colorScheme == .dark
        ForEach(stops.indices, id: \.self) { index in
            let placement = placements[min(index, placements.count - 1)]
            Circle()
                .fill(stops[index].opacity(dark ? 0.16 : 0.13))
                .frame(width: placement.size, height: placement.size)
                .blur(radius: 140)
                .offset(x: placement.x, y: placement.y)
        }
    }
}

// MARK: - Cherry petals

/// Pink petals drifting down with a gentle horizontal sway.
struct CherryPetalsField: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = 22
                let alpha = (colorScheme == .dark ? 0.30 : 0.22) * StudioTheme.gridIntensity
                guard alpha > 0.01 else { return }

                for i in 0..<count {
                    let seed = Double((i &* 40503) % 100000) / 100000.0
                    let fallSpeed = 14.0 + seed * 22.0
                    let span = Double(size.height) + 60
                    let rawY = (t * fallSpeed + seed * span * 11)
                        .truncatingRemainder(dividingBy: span)
                    let y = CGFloat(rawY) - 30
                    let sway = sin(t * (0.4 + seed) + seed * 12) * (18 + seed * 30)
                    let rawX = (seed * 2.3).truncatingRemainder(dividingBy: 1.0)
                    let x = CGFloat(rawX) * size.width + CGFloat(sway)
                    let petal = CGFloat(4 + seed * 5)
                    let spin = t * (0.6 + seed) + seed * 20

                    // Petal built around the origin, then rotated and placed.
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: -petal))
                    path.addQuadCurve(
                        to: CGPoint(x: petal, y: 0),
                        control: CGPoint(x: petal * 0.7, y: -petal * 0.6)
                    )
                    path.addQuadCurve(
                        to: CGPoint(x: 0, y: petal),
                        control: CGPoint(x: petal * 0.25, y: petal * 0.5)
                    )
                    path.addQuadCurve(
                        to: CGPoint(x: -petal, y: 0),
                        control: CGPoint(x: -petal * 0.7, y: petal * 0.6)
                    )
                    path.addQuadCurve(
                        to: CGPoint(x: 0, y: -petal),
                        control: CGPoint(x: -petal * 0.25, y: -petal * 0.5)
                    )
                    path.closeSubpath()

                    // Rotate about the petal center, then translate into place.
                    let petalPath = path.applying(
                        CGAffineTransform(rotationAngle: CGFloat(sin(spin) * 0.9))
                            .translatedBy(x: x, y: y)
                    )
                    let shade = colorScheme == .dark ? 1.0 : 0.85
                    context.fill(
                        petalPath,
                        with: .color(Color(hex: "F9A8D4").opacity(alpha * shade))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - End sky

/// Pale End-dimension starfield: tiny stars twinkling over a deep violet
/// void, with a few brighter "end rod" sparks drifting slowly.
struct EndSkyField: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Void glow — the End's signature pale-violet ambience.
            RadialGradient(
                colors: [
                    Color(hex: "4C3A78").opacity(colorScheme == .dark ? 0.35 : 0.22),
                    Color(hex: "1B1436").opacity(colorScheme == .dark ? 0.30 : 0.14),
                    .clear
                ],
                center: UnitPoint(x: 0.72, y: 0.18),
                startRadius: 10,
                endRadius: 620
            )

            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                Canvas { context, size in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let count = 110
                    let alpha = (colorScheme == .dark ? 0.75 : 0.5) * StudioTheme.gridIntensity
                    guard alpha > 0.02 else { return }

                    for i in 0..<count {
                        let seed = Double((i &* 2246822519) % 100000) / 100000.0
                        let x = CGFloat(seed * 2.13).truncatingRemainder(dividingBy: 1.0) * size.width
                        let ySeed = Double((i &* 3266489917) % 100000) / 100000.0
                        let y = CGFloat(ySeed * 1.71).truncatingRemainder(dividingBy: 1.0) * size.height
                        // Slow twinkle; a few stars are steady "bright" ones.
                        let bright = seed > 0.86
                        let twinkle = bright ? 1.0 : 0.45 + 0.55 * sin(t * (0.4 + seed * 1.6) + seed * 40)
                        let radius = bright ? 1.6 + seed * 1.2 : 0.7 + seed * 0.9
                        let color = bright
                            ? Color(hex: "E9E4FF")
                            : Color(hex: "B9A8E8")
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(color.opacity(alpha * twinkle))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Nether embers

/// Glowing embers drifting upward through the dark, like a soul campfire
/// or lava glow seen through cave darkness.
struct NetherEmbersField: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let count = 20
                let alpha = (colorScheme == .dark ? 0.55 : 0.35) * StudioTheme.gridIntensity
                guard alpha > 0.01 else { return }

                for i in 0..<count {
                    let seed = Double((i &* 1103515245) % 100000) / 100000.0
                    let rise = 22.0 + seed * 30.0               // pt/s upward drift
                    let swayAmp = 10.0 + seed * 26.0
                    let swaySpeed = 0.5 + seed * 0.9
                    let span = Double(size.height) + 80
                    let rawY = (t * rise + seed * span * 5)
                        .truncatingRemainder(dividingBy: span)
                    let y = size.height + 40 - CGFloat(rawY)
                    let sway = sin(t * swaySpeed + seed * 20) * swayAmp
                    let rawX = (seed * 1.9).truncatingRemainder(dividingBy: 1.0)
                    let x = CGFloat(rawX) * size.width + CGFloat(sway)

                    // Flicker: each ember pulses like a tiny flame.
                    let flicker = 0.55 + 0.45 * sin(t * (3.0 + seed * 4.0) + seed * 30)
                    let radius = CGFloat(1.4 + seed * 2.6) * (0.7 + 0.3 * flicker)
                    let heat = seed
                    let color = heat > 0.66
                        ? Color(hex: "FB923C")
                        : (heat > 0.33 ? Color(hex: "F87171") : Color(hex: "FBBF24"))

                    // Soft glow dot + brighter core.
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius * 2.6, y: y - radius * 2.6,
                                               width: radius * 5.2, height: radius * 5.2)),
                        with: .color(color.opacity(alpha * 0.20 * flicker))
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(color.opacity(alpha * flicker))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
