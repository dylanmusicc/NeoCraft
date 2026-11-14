import Foundation

// MARK: - Neo Studio theme

/// Launcher-wide appearance modes offered in the Studio customizer.
enum NeoThemeMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case frosted
    case oled
    case dynamic
    case biome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frosted: "Frosted Glass"
        case .oled: "Pure OLED Dark"
        case .dynamic: "Time-of-Day Auto"
        case .biome: "Biome-Synced"
        }
    }

    var subtitle: String {
        switch self {
        case .frosted: "Translucent materials over the voxel field."
        case .oled: "True-black backgrounds for OLED panels and focus."
        case .dynamic: "Accent drifts morning gold → noon sky → midnight violet."
        case .biome: "Adopts the accent of the biome at your last world's spawn."
        }
    }

    var symbol: String {
        switch self {
        case .frosted: "square.on.square.dashed"
        case .oled: "circle.lefthalf.filled"
        case .dynamic: "clock.arrow.circlepath"
        case .biome: "map.fill"
        }
    }
}

/// Corner treatment for cards, pills and panels.
enum NeoCornerStyle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case rounded
    case voxel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: "Apple Rounded"
        case .voxel: "Sharp Voxel"
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .rounded: 14
        case .voxel: 5
        }
    }
}

/// Animated wallpaper effects rendered behind the launcher content.
/// Raw values persist in `AppSettings.wallpaperStyle`.
enum WallpaperStyle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case aurora
    case cherryPetals
    case endSky
    case netherEmbers
    case plain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora: "Aurora Bloom"
        case .cherryPetals: "Cherry Petals"
        case .endSky: "End Sky"
        case .netherEmbers: "Nether Embers"
        case .plain: "Flat Gradient"
        }
    }

    var subtitle: String {
        switch self {
        case .aurora: "Soft accent and glow blooms over the voxel field."
        case .cherryPetals: "Petals drifting down like a cherry grove biome."
        case .endSky: "Pale stars and void glow, straight from the End."
        case .netherEmbers: "Embers rising through the dark like a Nether cave."
        case .plain: "Clean flat gradient, no texture or particles."
        }
    }

    var symbol: String {
        switch self {
        case .aurora: "waveform.path"
        case .cherryPetals: "petal"
        case .endSky: "sparkle"
        case .netherEmbers: "flame.fill"
        case .plain: "square"
        }
    }
}

/// Corner radius presets scaling every card radius in the launcher.
enum NeoRadiusPreset: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case compact
    case regular
    case spacious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .spacious: "Spacious"
        }
    }

    /// Multiplier applied to requested corner radii.
    var scale: CGFloat {
        switch self {
        case .compact: 0.72
        case .regular: 1.0
        case .spacious: 1.38
        }
    }
}

/// Curated Apple-inspired accent swatches for the launcher.
enum NeoAccent: String, CaseIterable, Identifiable, Hashable, Sendable {
    case appleBlue = "5B8CFF"
    case emeraldCreeper = "4ADE80"
    case amethystPurple = "A78BFA"
    case sunsetGold = "FBBF24"
    case graphite = "9AA4B2"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .appleBlue: "Apple Blue"
        case .emeraldCreeper: "Emerald Creeper"
        case .amethystPurple: "Amethyst Purple"
        case .sunsetGold: "Sunset Gold"
        case .graphite: "Graphite"
        }
    }
}

/// A curated one-tap theme preset covering accent, glow and surface tint.
struct NeoCuratedTheme: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var symbol: String
    var accentHex: String
    var glowHex: String
    var surfaceHex: String
    /// Preview gradient stops for the Studio picker.
    var previewTop: String
    var previewBottom: String
    var family: String
    /// Suggested theme mode applied alongside the colors (nil = keep current).
    var themeMode: NeoThemeMode? = nil
    /// Suggested wallpaper effect raw value (nil = keep current).
    var wallpaperStyle: String? = nil

    /// Applies the preset to settings (does not touch theme mode unless the
    /// preset carries a suggestion).
    func apply(to settings: inout AppSettings) {
        settings.accentHex = accentHex
        settings.secondaryGlowHex = glowHex
        settings.cardTintHex = surfaceHex
        if let themeMode { settings.themeMode = themeMode }
        if let wallpaperStyle, WallpaperStyle(rawValue: wallpaperStyle) != nil {
            settings.wallpaperStyle = wallpaperStyle
        }
        settings.curatedTheme = id
    }
}

enum NeoCuratedThemes {
    static let all: [NeoCuratedTheme] = [
        // Apple Native
        NeoCuratedTheme(id: "sequoia", title: "Sequoia Frosted", symbol: "apple.logo",
                        accentHex: "0A84FF", glowHex: "BF5AF2", surfaceHex: "",
                        previewTop: "3A5A8C", previewBottom: "141C2E", family: "Apple Native"),
        NeoCuratedTheme(id: "oledMidnight", title: "OLED Midnight", symbol: "moon.stars.fill",
                        accentHex: "38BDF8", glowHex: "6366F1", surfaceHex: "",
                        previewTop: "101018", previewBottom: "000000", family: "Apple Native"),
        NeoCuratedTheme(id: "sonoma", title: "Sonoma Daylight", symbol: "sun.max.fill",
                        accentHex: "0A6CFF", glowHex: "FF9F0A", surfaceHex: "F2F5FA",
                        previewTop: "DCE9F7", previewBottom: "F7FAFF", family: "Apple Native"),
        NeoCuratedTheme(id: "graphitePro", title: "Graphite Pro", symbol: "square.grid.3x3.fill",
                        accentHex: "98989D", glowHex: "636366", surfaceHex: "",
                        previewTop: "3A3A3C", previewBottom: "1C1C1E", family: "Apple Native"),
        NeoCuratedTheme(id: "titanium", title: "Space Black", symbol: "circle.hexagongrid.fill",
                        accentHex: "8E8E93", glowHex: "5E5CE6", surfaceHex: "",
                        previewTop: "2C2C2E", previewBottom: "0B0B0D", family: "Apple Native"),
        // Minecraft biomes & dimensions
        NeoCuratedTheme(id: "cherry", title: "Cherry Blossom", symbol: "flower.fill",
                        accentHex: "F472B6", glowHex: "FBCFE8", surfaceHex: "",
                        previewTop: "F7C6D9", previewBottom: "8A4A63", family: "Biomes"),
        NeoCuratedTheme(id: "deepDark", title: "Deep Dark Sculk", symbol: "circle.hexagongrid",
                        accentHex: "22D3EE", glowHex: "67E8F9", surfaceHex: "",
                        previewTop: "123B4A", previewBottom: "0A1420", family: "Biomes"),
        NeoCuratedTheme(id: "nether", title: "Nether Crimson", symbol: "flame.fill",
                        accentHex: "F87171", glowHex: "FB923C", surfaceHex: "",
                        previewTop: "7A2A1E", previewBottom: "2A0E0A", family: "Biomes",
                        wallpaperStyle: "netherEmbers"),
        NeoCuratedTheme(id: "endVoid", title: "End Void Amethyst", symbol: "moon.fill",
                        accentHex: "A78BFA", glowHex: "DDD6FE", surfaceHex: "",
                        previewTop: "3B2A63", previewBottom: "120B24", family: "Biomes",
                        wallpaperStyle: "endSky"),
        NeoCuratedTheme(id: "lushCave", title: "Lush Cave Moss", symbol: "leaf.fill",
                        accentHex: "34D399", glowHex: "A7F3D0", surfaceHex: "",
                        previewTop: "1E5C46", previewBottom: "0B2018", family: "Biomes"),
        NeoCuratedTheme(id: "diamondOre", title: "Diamond Ore", symbol: "diamond.fill",
                        accentHex: "67E8F9", glowHex: "5B8CFF", surfaceHex: "",
                        previewTop: "3B5C7A", previewBottom: "101820", family: "Biomes"),
        NeoCuratedTheme(id: "emerald", title: "Emerald Village", symbol: "building.2.fill",
                        accentHex: "4ADE80", glowHex: "FBBF24", surfaceHex: "",
                        previewTop: "2E6B3A", previewBottom: "0E2418", family: "Biomes"),
        NeoCuratedTheme(id: "sunsetMesa", title: "Sunset Mesa", symbol: "sun.haze.fill",
                        accentHex: "FB923C", glowHex: "F472B6", surfaceHex: "",
                        previewTop: "8A4A3A", previewBottom: "2A1410", family: "Biomes"),
        NeoCuratedTheme(id: "snowyTaiga", title: "Snowy Taiga", symbol: "snowflake",
                        accentHex: "7DD3FC", glowHex: "E0F2FE", surfaceHex: "",
                        previewTop: "5A7A8C", previewBottom: "1A2830", family: "Biomes"),
        NeoCuratedTheme(id: "amethystGeode", title: "Amethyst Geode", symbol: "hexagon.fill",
                        accentHex: "C084FC", glowHex: "F0ABFC", surfaceHex: "",
                        previewTop: "4A3063", previewBottom: "180F28", family: "Biomes"),
        // More biomes & dimensions
        NeoCuratedTheme(id: "copperFoundry", title: "Copper Foundry", symbol: "building.columns.fill",
                        accentHex: "FB923C", glowHex: "FDE68A", surfaceHex: "",
                        previewTop: "8A4A24", previewBottom: "241408", family: "Biomes",
                        themeMode: .frosted, wallpaperStyle: "aurora"),
        NeoCuratedTheme(id: "mangroveBog", title: "Mangrove Bog", symbol: "water.waves",
                        accentHex: "34D399", glowHex: "A7F3D0", surfaceHex: "",
                        previewTop: "14503C", previewBottom: "071A14", family: "Biomes",
                        wallpaperStyle: "cherryPetals"),
        NeoCuratedTheme(id: "bambooJungle", title: "Bamboo Jungle", symbol: "leaf.arrow.circlepath",
                        accentHex: "84CC16", glowHex: "D9F99D", surfaceHex: "",
                        previewTop: "3F6212", previewBottom: "101A06", family: "Biomes"),
        NeoCuratedTheme(id: "mushroomIsland", title: "Mushroom Island", symbol: "cpu",
                        accentHex: "F472B6", glowHex: "FDE68A", surfaceHex: "",
                        previewTop: "6B2D5C", previewBottom: "1C0B18", family: "Biomes",
                        wallpaperStyle: "aurora"),
        NeoCuratedTheme(id: "paleGarden", title: "Pale Garden", symbol: "moon.haze.fill",
                        accentHex: "CBD5E1", glowHex: "A78BFA", surfaceHex: "",
                        previewTop: "3A4454", previewBottom: "0E1219", family: "Biomes",
                        themeMode: .oled, wallpaperStyle: "plain"),
        NeoCuratedTheme(id: "deepslate", title: "Deepslate Depths", symbol: "square.fill.on.square.fill",
                        accentHex: "94A3B8", glowHex: "38BDF8", surfaceHex: "",
                        previewTop: "1E293B", previewBottom: "070B12", family: "Biomes",
                        themeMode: .oled, wallpaperStyle: "plain"),
        NeoCuratedTheme(id: "warpedWoods", title: "Warped Woods", symbol: "scribble.variable",
                        accentHex: "2DD4BF", glowHex: "67E8F9", surfaceHex: "",
                        previewTop: "134E4A", previewBottom: "04110F", family: "Biomes",
                        wallpaperStyle: "endSky")
    ]

    static func theme(id: String) -> NeoCuratedTheme? {
        all.first { $0.id == id }
    }
}

/// A `.neotheme` preset file — the full appearance snapshot users can
/// export and share.
struct NeoThemeFile: Codable, Sendable {
    var format = "neotheme"
    var version = 1
    var name: String
    var accentHex: String
    var secondaryGlowHex: String
    var cardTintHex: String
    var themeMode: NeoThemeMode
    var gridIntensity: Double
    var cornerStyle: NeoCornerStyle
    var sidebarMaterial: Double
    /// Optional extended fields — older .neotheme files omit them.
    var wallpaperStyle: String?
    var glassBlur: Double?
    var heroCardStyle: String?
    var gradientHexes: [String]?
    var cornerRadiusPreset: String?
    var dashboardCards: [String]?
    var dashboardWidgetOrder: [String]?

    init(name: String, settings: AppSettings) {
        self.name = name
        accentHex = settings.accentHex
        secondaryGlowHex = settings.secondaryGlowHex
        cardTintHex = settings.cardTintHex
        themeMode = settings.themeMode
        gridIntensity = settings.gridIntensity
        cornerStyle = settings.cornerStyle
        sidebarMaterial = settings.sidebarMaterial
        wallpaperStyle = settings.wallpaperStyle
        glassBlur = settings.glassBlur
        heroCardStyle = settings.heroCardStyle
        gradientHexes = settings.gradientHexes
        cornerRadiusPreset = settings.cornerRadiusPreset
        dashboardCards = settings.dashboardCards
        dashboardWidgetOrder = settings.dashboardWidgetOrder
    }

    func apply(to settings: inout AppSettings) {
        settings.accentHex = accentHex
        settings.secondaryGlowHex = secondaryGlowHex
        settings.cardTintHex = cardTintHex
        settings.themeMode = themeMode
        settings.gridIntensity = gridIntensity
        settings.cornerStyle = cornerStyle
        settings.sidebarMaterial = sidebarMaterial
        if let wallpaperStyle, WallpaperStyle(rawValue: wallpaperStyle) != nil {
            settings.wallpaperStyle = wallpaperStyle
        }
        if let glassBlur { settings.glassBlur = min(max(glassBlur, 0), 1) }
        if let heroCardStyle, ["compact", "banner", "glass"].contains(heroCardStyle) {
            settings.heroCardStyle = heroCardStyle
        }
        if let gradientHexes { settings.gradientHexes = gradientHexes }
        if let cornerRadiusPreset { settings.cornerRadiusPreset = cornerRadiusPreset }
        if let dashboardCards { settings.dashboardCards = dashboardCards }
        if let dashboardWidgetOrder { settings.dashboardWidgetOrder = dashboardWidgetOrder }
        settings.curatedTheme = ""
    }
}

/// Telemetry cards that can be toggled on the Play dashboard.
enum DashboardCardKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case memory
    case thermal
    case activity
    case flightCheck
    case hardware
    case screenshots
    case boost
    case servers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memory: "Unified Memory gauge"
        case .thermal: "A18 Thermal sensor"
        case .activity: "Recent Activity"
        case .flightCheck: "Flight Check status"
        case .hardware: "Hardware Specs"
        case .screenshots: "Recent Screenshots"
        case .boost: "Neo Boost status"
        case .servers: "Hosted Servers"
        }
    }

    var subtitle: String {
        switch self {
        case .memory: "Live RAM headroom and swap usage."
        case .thermal: "CPU load, thermal pressure and power state."
        case .activity: "Latest downloads, installs and launches."
        case .flightCheck: "Pre-launch mod conflict scan for the selected instance."
        case .hardware: "Chip, memory, model and macOS at a glance."
        case .screenshots: "Newest in-game captures across instances."
        case .boost: "Fabric performance pack status and installer."
        case .servers: "Your hosted Java and Bedrock servers at a glance."
        }
    }

    var symbol: String {
        switch self {
        case .memory: "memorychip"
        case .thermal: "thermometer.medium"
        case .activity: "clock.arrow.circlepath"
        case .flightCheck: "checkmark.shield"
        case .hardware: "desktopcomputer"
        case .screenshots: "photo.stack.fill"
        case .boost: "bolt.fill"
        case .servers: "server.rack"
        }
    }
}

/// Process-wide theme accessor. `AppModel` mirrors the persisted
/// `AppSettings` values into `UserDefaults` so static views (NeoPalette,
/// NeoBackground) can read them without threading the model through
/// every component.
enum StudioTheme {
    private static let accentKey = "neoCraft.theme.accentHex"
    private static let glowKey = "neoCraft.theme.glowHex"
    private static let tintKey = "neoCraft.theme.cardTintHex"
    private static let modeKey = "neoCraft.theme.mode"
    private static let gridKey = "neoCraft.theme.gridIntensity"
    private static let cornerKey = "neoCraft.theme.cornerStyle"
    private static let materialKey = "neoCraft.theme.sidebarMaterial"
    private static let wallpaperKey = "neoCraft.theme.wallpaperStyle"
    private static let glassKey = "neoCraft.theme.glassBlur"
    private static let gradientKey = "neoCraft.theme.gradientHexes"
    private static let radiusKey = "neoCraft.theme.cornerRadiusPreset"

    static func sync(_ settings: AppSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.accentHex, forKey: accentKey)
        defaults.set(settings.secondaryGlowHex, forKey: glowKey)
        defaults.set(settings.cardTintHex, forKey: tintKey)
        defaults.set(settings.themeMode.rawValue, forKey: modeKey)
        defaults.set(settings.gridIntensity, forKey: gridKey)
        defaults.set(settings.cornerStyle.rawValue, forKey: cornerKey)
        defaults.set(settings.sidebarMaterial, forKey: materialKey)
        defaults.set(settings.wallpaperStyle, forKey: wallpaperKey)
        defaults.set(settings.glassBlur, forKey: glassKey)
        defaults.set(settings.gradientHexes.joined(separator: ","), forKey: gradientKey)
        defaults.set(settings.cornerRadiusPreset, forKey: radiusKey)
        defaults.set(settings.appLanguage, forKey: L10n.overrideKey)
    }

    static var accentHex: String {
        guard let defaults = UserDefaults.standard.object(forKey: accentKey) as? String,
              !defaults.isEmpty else {
            return NeoAccent.appleBlue.rawValue
        }
        return defaults
    }

    /// Secondary glow used for ambient background blooms and gradients.
    static var glowHex: String {
        guard let value = UserDefaults.standard.string(forKey: glowKey),
              !value.isEmpty else {
            return NeoAccent.amethystPurple.rawValue
        }
        return value
    }

    /// Optional card surface tint ("" = neutral material).
    static var cardTintHex: String {
        UserDefaults.standard.string(forKey: tintKey) ?? ""
    }

    static var cornerStyle: NeoCornerStyle {
        guard let raw = UserDefaults.standard.string(forKey: cornerKey),
              let style = NeoCornerStyle(rawValue: raw) else {
            return .rounded
        }
        return style
    }

    /// Sidebar translucency 0…1 (1 = fully opaque material).
    static var sidebarMaterial: Double {
        let value = UserDefaults.standard.double(forKey: materialKey)
        return value > 0 ? min(value, 1) : 0.5
    }

    static var mode: NeoThemeMode {
        guard let raw = UserDefaults.standard.string(forKey: modeKey),
              let mode = NeoThemeMode(rawValue: raw) else {
            return .frosted
        }
        return mode
    }

    static var gridIntensity: Double {
        let value = UserDefaults.standard.double(forKey: gridKey)
        return value > 0 ? value : 1.0
    }

    /// Wallpaper effect raw value (see `WallpaperStyle`).
    static var wallpaperStyle: WallpaperStyle {
        guard let raw = UserDefaults.standard.string(forKey: wallpaperKey),
              let style = WallpaperStyle(rawValue: raw) else {
            return .aurora
        }
        return style
    }

    /// Glass blur intensity 0…1 for cards and panels.
    static var glassBlur: Double {
        guard let value = UserDefaults.standard.object(forKey: glassKey) as? Double else {
            return 0.5
        }
        return min(max(value, 0), 1)
    }

    /// Custom multi-stop bloom colors ("" entries filtered out).
    static var gradientHexes: [String] {
        (UserDefaults.standard.string(forKey: gradientKey) ?? "")
            .split(separator: ",")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    /// Radius preset scaling all card corner radii.
    static var radiusPreset: NeoRadiusPreset {
        guard let raw = UserDefaults.standard.string(forKey: radiusKey),
              let preset = NeoRadiusPreset(rawValue: raw) else {
            return .regular
        }
        return preset
    }

    /// The accent actually rendered right now. Dynamic mode blends between
    /// morning gold, noon sky and midnight violet by the local hour;
    /// Biome mode adopts the accent of the biome at the last world's spawn.
    static var effectiveAccentHex: String {
        switch mode {
        case .dynamic:
            let hour = Calendar.current.component(.hour, from: Date())
            if (6..<11).contains(hour) {
                return "FBBF24"   // morning gold
            } else if (11..<17).contains(hour) {
                return "38BDF8"   // noon sky
            } else if (17..<21).contains(hour) {
                return "FB923C"   // sunset ember
            }
            return "A78BFA"       // midnight ender violet
        case .biome:
            return biomeSyncedAccent()
        case .frosted, .oled:
            return accentHex
        }
    }

    // MARK: Biome-synced accent

    /// UserDefaults key holding the computed biome accent.
    static let biomeAccentKey = "NeoBiomeAccent"

    /// Accent derived from the biome at the spawn point of the most
    /// recently played world. `AppModel` recomputes it on refresh and
    /// mirrors the value into `UserDefaults`, so this stays a cheap,
    /// nonisolated read safe for every render pass.
    static func biomeSyncedAccent() -> String {
        guard let hex = UserDefaults.standard.string(forKey: biomeAccentKey),
              !hex.isEmpty else { return accentHex }
        return hex
    }

    /// Recomputes the biome accent from the newest world across all
    /// instances and stores it in `UserDefaults`. MainActor-only because
    /// it walks the instance list and touches `level.dat` files.
    @MainActor
    static func refreshBiomeAccent() {
        var bestWorld: WorldInfo?
        var bestPlayed = Date.distantPast
        for instance in AppModel.shared.instances {
            for world in WorldBackupService.worlds(in: instance) {
                let played = world.lastPlayed ?? .distantPast
                if played > bestPlayed {
                    bestPlayed = played
                    bestWorld = world
                }
            }
        }
        guard let bestWorld, let seed = bestWorld.seed else {
            UserDefaults.standard.removeObject(forKey: biomeAccentKey)
            return
        }
        let field = BiomeField(seed: seed)
        let biome = field.biome(
            atX: bestWorld.spawnX ?? 0,
            z: bestWorld.spawnZ ?? 0
        )
        UserDefaults.standard.set(biome.accentHex, forKey: biomeAccentKey)
    }
}

private extension RadarBiome {
    /// Accent hex adopted when Biome-Synced theme mode is active.
    var accentHex: String {
        switch self {
        case .ocean, .river: "4A8FE8"
        case .beach, .desert: "E0C878"
        case .plains: "7FBF5A"
        case .forest, .birchForest: "34D399"
        case .darkForest: "2DD4BF"
        case .snow, .iceSpikes: "7DD3FC"
        case .badlands: "FB923C"
        case .cherryGrove: "F472B6"
        case .deepDark: "22D3EE"
        case .mountains: "9AA4B2"
        }
    }
}

// MARK: - In-game HUD layout (Neo Studio)

/// Font styling for in-game HUD widgets.
enum HUDFontStyle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case apple
    case minecraft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple Pill"
        case .minecraft: "Minecraft Font"
        }
    }
}

/// The kinds of Apple-inspired HUD widgets the Studio editor can place.
enum HUDWidgetKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case fpsPill
    case coordsCompass
    case netherCoords
    case armorDurability
    case potionEffects
    case keystrokes
    case pingTPS
    case clocks
    case dayLight
    case speedometer
    case statusPills
    case minimap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fpsPill: "FPS & Frame-Time"
        case .coordsCompass: "Biome & Direction Compass"
        case .netherCoords: "Coordinates & Nether/Overworld"
        case .armorDurability: "Armor & Durability Bars"
        case .potionEffects: "Potion Effects Timer"
        case .keystrokes: "Keystrokes & CPS"
        case .pingTPS: "Server Ping & TPS"
        case .clocks: "Game & Mac Clock"
        case .dayLight: "Day Counter & Light"
        case .speedometer: "Speedometer (B/s)"
        case .statusPills: "Sprint / Sneak Status"
        case .minimap: "Mini-Map Corner"
        }
    }

    var symbol: String {
        switch self {
        case .fpsPill: "speedometer"
        case .coordsCompass: "safari.fill"
        case .netherCoords: "location.north.line.fill"
        case .armorDurability: "shield.fill"
        case .potionEffects: "testtube.2"
        case .keystrokes: "keyboard"
        case .pingTPS: "antenna.radiowaves.left.and.right"
        case .clocks: "clock.fill"
        case .dayLight: "sun.max.fill"
        case .speedometer: "gauge.with.dots.needle.67percent"
        case .statusPills: "figure.run"
        case .minimap: "map.fill"
        }
    }

    /// MiniHUD module names this widget maps to when syncing configs.
    var miniHUDModules: [String] {
        switch self {
        case .fpsPill: ["FPS", "TPS"]
        case .coordsCompass: ["Direction", "Biome"]
        case .netherCoords: ["Position"]
        case .armorDurability: ["Armor", "ItemDurability"]
        case .potionEffects: ["StatusEffects"]
        case .keystrokes: ["Keybinds"]
        case .pingTPS: ["Ping"]
        case .clocks: ["Clock"]
        case .dayLight: ["LightLevel", "Day"]
        case .speedometer: ["Speed"]
        case .statusPills: ["Sprint"]
        case .minimap: []
        }
    }
}

/// One placeable HUD widget. `x`/`y` are normalized coordinates (0…1)
/// within the 16:9 gameplay canvas, `scale` is a 0.6…1.6 multiplier.
struct HUDWidget: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var kind: HUDWidgetKind
    var x: Double
    var y: Double
    var scale: Double
    var visible: Bool
    var colorHex: String
    /// Pill background opacity 0…1 (0 = fully transparent).
    var backgroundOpacity: Double
    var fontStyle: HUDFontStyle

    init(
        id: UUID = UUID(),
        kind: HUDWidgetKind,
        x: Double,
        y: Double,
        scale: Double = 1.0,
        visible: Bool = true,
        colorHex: String = "5B8CFF",
        backgroundOpacity: Double = 0.45,
        fontStyle: HUDFontStyle = .apple
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.scale = scale
        self.visible = visible
        self.colorHex = colorHex
        self.backgroundOpacity = backgroundOpacity
        self.fontStyle = fontStyle
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(HUDWidgetKind.self, forKey: .kind)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.5
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.0
        visible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? "5B8CFF"
        backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.45
        fontStyle = try container.decodeIfPresent(HUDFontStyle.self, forKey: .fontStyle) ?? .apple
    }

    static let defaults: [HUDWidget] = [
        HUDWidget(kind: .fpsPill, x: 0.03, y: 0.04, scale: 1.0, colorHex: "4ADE80"),
        HUDWidget(kind: .coordsCompass, x: 0.97, y: 0.04, scale: 1.0, colorHex: "5B8CFF"),
        HUDWidget(kind: .netherCoords, x: 0.03, y: 0.10, scale: 0.9, colorHex: "38BDF8"),
        HUDWidget(kind: .armorDurability, x: 0.5, y: 0.93, scale: 1.0, colorHex: "FB923C"),
        HUDWidget(kind: .potionEffects, x: 0.97, y: 0.30, scale: 0.9, colorHex: "A78BFA"),
        HUDWidget(kind: .keystrokes, x: 0.03, y: 0.72, scale: 1.0, colorHex: "A78BFA"),
        HUDWidget(kind: .pingTPS, x: 0.97, y: 0.36, scale: 0.9, colorHex: "FBBF24"),
        HUDWidget(kind: .clocks, x: 0.5, y: 0.05, scale: 0.9, colorHex: "E2E8F0"),
        HUDWidget(kind: .dayLight, x: 0.5, y: 0.10, scale: 0.85, colorHex: "FBBF24"),
        HUDWidget(kind: .speedometer, x: 0.85, y: 0.93, scale: 0.9, colorHex: "38BDF8"),
        HUDWidget(kind: .statusPills, x: 0.15, y: 0.93, scale: 0.9, colorHex: "4ADE80"),
        HUDWidget(kind: .minimap, x: 0.90, y: 0.72, scale: 1.0, colorHex: "38BDF8")
    ]
}

/// The complete in-game HUD arrangement persisted per launcher (applied
/// per-instance on demand).
struct HUDLayout: Codable, Equatable, Sendable {
    var widgets: [HUDWidget]

    init(widgets: [HUDWidget] = HUDWidget.defaults) {
        self.widgets = widgets
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        widgets = try container.decodeIfPresent([HUDWidget].self, forKey: .widgets) ?? HUDWidget.defaults
    }

    func widget(_ kind: HUDWidgetKind) -> HUDWidget? {
        widgets.first { $0.kind == kind }
    }
}
