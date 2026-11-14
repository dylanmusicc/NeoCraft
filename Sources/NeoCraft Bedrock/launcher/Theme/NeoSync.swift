import Foundation
import SwiftUI

/// NeoCraft's Studio appearance, mirrored live. NeoCraft writes its theme into its own
/// defaults under `neoCraft.theme.*` (see `StudioTheme.sync`), and this reads them through
/// that app's defaults domain — so the Bedrock component follows whatever the player picked
/// in Neo Studio, including the dynamic and biome-synced accents, without any IPC. The
/// defaults are polled: NeoCraft and this launcher are separate processes, so a change
/// lands on the next tick.
@MainActor
@Observable
final class NeoSync {
    static let shared = NeoSync()

    /// NeoCraft's bundle identifier — the defaults domain its theme lives in.
    private static let neoCraftDefaults = "com.neocraft.launcher"

    private let defaults: UserDefaults?
    private var timer: Timer?

    /// Bumped whenever a mirrored value changes, so views re-render. `effectiveAccentHex`
    /// reads it to stay observed even when the accent is computed (dynamic/biome modes).
    private(set) var revision = 0

    private(set) var accentHex = "5B8CFF"
    private(set) var glowHex = "A78BFA"
    private(set) var cardTintHex = ""
    private(set) var themeMode = "frosted"
    private(set) var gridIntensity = 1.0
    private(set) var cornerStyle = "rounded"
    private(set) var sidebarMaterial = 0.5
    private(set) var wallpaperStyle = "aurora"
    private(set) var glassBlur = 0.5
    private(set) var cornerRadiusScale: CGFloat = 1
    private(set) var gradientHexes: [String] = []
    /// Launcher-local "Liquid Glass" look: clearer materials and softer
    /// panel edges, inspired by Apple's glass design language.
    private(set) var liquidGlass = false

    private init() {
        defaults = UserDefaults(suiteName: Self.neoCraftDefaults)
        reload()
        // Cheap poll: a handful of defaults reads every two seconds.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    // MARK: Resolved values

    /// The accent NeoCraft renders right now: the dynamic mode's hour table and the biome
    /// mode's synced accent are resolved here exactly like `StudioTheme.effectiveAccentHex`.
    /// A launcher accent override wins over all of them.
    var effectiveAccentHex: String {
        _ = revision
        if let override = LauncherTheme.accentHex, !override.isEmpty {
            return override
        }
        switch themeMode {
        case "dynamic":
            switch Calendar.current.component(.hour, from: Date()) {
            case 6..<11: return "FBBF24"
            case 11..<17: return "38BDF8"
            case 17..<21: return "FB923C"
            default: return "A78BFA"
            }
        case "biome":
            return defaults?.string(forKey: "NeoBiomeAccent").flatMap { $0.isEmpty ? nil : $0 }
                ?? accentHex
        default:
            return accentHex
        }
    }

    var accent: Color { NeoSync.color(effectiveAccentHex) }
    var glow: Color { NeoSync.color(glowHex) }

    /// NeoCraft's `accentDeep`: the accent pulled toward black for gradient ends.
    var accentDeep: Color {
        guard let rgb = NeoSync.rgb(effectiveAccentHex) else { return accent }
        return Color(
            .sRGB,
            red: Double(rgb.0) * 0.72 / 255, green: Double(rgb.1) * 0.72 / 255,
            blue: Double(rgb.2) * 0.72 / 255)
    }

    /// The optional card tint Neo Studio applies to surfaces ("" = none).
    var cardTint: Color? {
        guard let rgb = NeoSync.rgb(cardTintHex) else { return nil }
        return Color(.sRGB, red: Double(rgb.0) / 255, green: Double(rgb.1) / 255, blue: Double(rgb.2) / 255)
    }

    /// Pure-OLED mode paints true black instead of the navy backdrop —
    /// or the launcher's own override when one is set.
    var trueBlack: Bool {
        LauncherTheme.trueBlack ?? (themeMode == "oled")
    }

    /// Neo Studio's radius preset and corner treatment applied to a base radius.
    func radius(_ base: CGFloat) -> CGFloat {
        let scaled = base * cornerRadiusScale
        return cornerStyle == "voxel" ? min(scaled, 5) : scaled
    }

    /// The bloom colours of the wallpaper: the player's custom gradient stops when set,
    /// otherwise the accent and glow pair.
    var bloomColors: [Color] {
        _ = revision
        let custom = gradientHexes.compactMap { NeoSync.rgb($0) }.map {
            Color(.sRGB, red: Double($0.0) / 255, green: Double($0.1) / 255, blue: Double($0.2) / 255)
        }
        return custom.isEmpty ? [accent, glow] : custom
    }

    // MARK: Loading

    func reload() {
        guard let defaults else { return }
        let accent = LauncherTheme.accentHex.flatMap { $0.isEmpty ? nil : $0 }
            ?? defaults.string(forKey: "neoCraft.theme.accentHex") ?? "5B8CFF"
        let next = (
            accent: accent.isEmpty ? "5B8CFF" : accent,
            glow: defaults.string(forKey: "neoCraft.theme.glowHex") ?? "A78BFA",
            tint: defaults.string(forKey: "neoCraft.theme.cardTintHex") ?? "",
            mode: defaults.string(forKey: "neoCraft.theme.mode") ?? "frosted",
            grid: LauncherTheme.gridIntensity
                ?? defaults.object(forKey: "neoCraft.theme.gridIntensity") as? Double ?? 1.0,
            corner: defaults.string(forKey: "neoCraft.theme.cornerStyle") ?? "rounded",
            material: defaults.object(forKey: "neoCraft.theme.sidebarMaterial") as? Double ?? 0.5,
            wallpaper: {
                // Unknown/removed styles (e.g. the old deepDarkPulse)
                // fall back to aurora instead of rendering nothing.
                let raw = LauncherTheme.wallpaperStyle
                    ?? defaults.string(forKey: "neoCraft.theme.wallpaperStyle") ?? "aurora"
                return NeoSync.wallpaperOptions.contains { $0.id == raw } ? raw : "aurora"
            }(),
            glass: defaults.object(forKey: "neoCraft.theme.glassBlur") as? Double ?? 0.5,
            radius: defaults.string(forKey: "neoCraft.theme.cornerRadiusPreset") ?? "regular",
            gradient: (defaults.string(forKey: "neoCraft.theme.gradientHexes") ?? "")
                .split(separator: ",").map(String.init).filter { !$0.isEmpty },
            liquid: LauncherTheme.liquidGlass ?? false,
            beta: NeoCraftFiles.betaEnabled()
        )
        // The dynamic accent also drifts with the hour — poll it into `revision` too.
        let hourBucket = themeMode == "dynamic"
            ? Calendar.current.component(.hour, from: Date()) / 6 : -1
        let changed = next.accent != accentHex || next.glow != glowHex || next.tint != cardTintHex
            || next.mode != themeMode || next.grid != gridIntensity || next.corner != cornerStyle
            || next.material != sidebarMaterial || next.wallpaper != wallpaperStyle
            || next.glass != glassBlur
            || next.radius != radiusKey || next.gradient != gradientHexes || hourBucket != lastHourBucket
            || next.liquid != liquidGlass
            || next.beta != neoCraftBeta
        guard changed else { return }
        lastHourBucket = hourBucket
        accentHex = next.accent
        glowHex = next.glow
        cardTintHex = next.tint
        themeMode = next.mode
        gridIntensity = next.grid
        cornerStyle = next.corner
        sidebarMaterial = next.material
        wallpaperStyle = next.wallpaper
        glassBlur = next.glass
        cornerRadiusScale = switch next.radius {
        case "compact": 0.72
        case "spacious": 1.38
        default: 1.0
        }
        radiusKey = next.radius
        gradientHexes = next.gradient
        liquidGlass = next.liquid
        neoCraftBeta = next.beta
        revision += 1
    }

    private var radiusKey = "regular"
    private var lastHourBucket = -2
    /// NeoCraft's `bedrockEdition` beta flag — gates the synced pages.
    private(set) var neoCraftBeta = false

    // MARK: Launcher-local appearance overrides

    /// The Bedrock component can be styled on its own — Settings →
    /// Appearance and the first-run wizard write these keys into the
    /// launcher's own defaults. Whatever is set wins over the mirrored
    /// NeoCraft theme; "Reset to NeoCraft" clears them.
    enum LauncherTheme {
        static let accentKey = "bedrock.appearance.accentHex"
        static let wallpaperKey = "bedrock.appearance.wallpaperStyle"
        static let blackKey = "bedrock.appearance.trueBlack"
        static let gridKey = "bedrock.appearance.gridIntensity"
        static let liquidKey = "bedrock.appearance.liquidGlass"

        static var accentHex: String? { UserDefaults.standard.string(forKey: accentKey) }
        static var wallpaperStyle: String? { UserDefaults.standard.string(forKey: wallpaperKey) }
        static var trueBlack: Bool? { UserDefaults.standard.object(forKey: blackKey) as? Bool }
        static var liquidGlass: Bool? { UserDefaults.standard.object(forKey: liquidKey) as? Bool }
        static var gridIntensity: Double? {
            UserDefaults.standard.object(forKey: gridKey) as? Double
        }

        static func setAccent(_ hex: String?) {
            UserDefaults.standard.set(hex, forKey: accentKey)
        }

        static func setWallpaper(_ style: String?) {
            UserDefaults.standard.set(style, forKey: wallpaperKey)
        }

        static func setTrueBlack(_ value: Bool?) {
            if let value {
                UserDefaults.standard.set(value, forKey: blackKey)
            } else {
                UserDefaults.standard.removeObject(forKey: blackKey)
            }
        }

        static func setGridIntensity(_ value: Double?) {
            if let value {
                UserDefaults.standard.set(value, forKey: gridKey)
            } else {
                UserDefaults.standard.removeObject(forKey: gridKey)
            }
        }

        static func setLiquidGlass(_ value: Bool?) {
            if let value {
                UserDefaults.standard.set(value, forKey: liquidKey)
            } else {
                UserDefaults.standard.removeObject(forKey: liquidKey)
            }
        }

        static func reset() {
            for key in [accentKey, wallpaperKey, blackKey, gridKey, liquidKey] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Accent swatches offered by the Appearance pickers.
    static let accentPresets = [
        "5B8CFF", "38BDF8", "4ADE80", "2DD4BF",
        "FBBF24", "FB923C", "F472B6", "A78BFA",
    ]

    /// Wallpaper styles the launcher can render — same raw values NeoCraft
    /// writes into `neoCraft.theme.wallpaperStyle`.
    static let wallpaperOptions: [(id: String, title: String, symbol: String)] = [
        ("aurora", "Aurora Bloom", "waveform.path"),
        ("cherryPetals", "Cherry Petals", "petal"),
        ("endSky", "End Sky", "sparkle"),
        ("netherEmbers", "Nether Embers", "flame.fill"),
        ("plain", "Flat Gradient", "square"),
    ]

    static func color(_ hex: String) -> Color {
        guard let rgb = rgb(hex) else { return Color(hex: 0x5B8CFF) }
        return Color(
            .sRGB, red: Double(rgb.0) / 255, green: Double(rgb.1) / 255, blue: Double(rgb.2) / 255)
    }

    private static func rgb(_ hex: String) -> (Int, Int, Int)? {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return (Int(number >> 16 & 0xFF), Int(number >> 8 & 0xFF), Int(number & 0xFF))
    }
}
