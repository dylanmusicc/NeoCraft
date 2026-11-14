import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case play
    case instances
    case servers
    case joinServer
    case dashboard
    case studio
    case mods
    case screenshots
    case account
    case settings

    var id: String { rawValue }

    var title: String { L10n.t("nav.\(rawValue).title") }

    var symbol: String {
        switch self {
        case .play: "play.circle.fill"
        case .instances: "square.stack.3d.up.fill"
        case .servers: "server.rack"
        case .joinServer: "globe"
        case .dashboard: "gauge.with.dots.needle.33percent"
        case .studio: "paintbrush.pointed.fill"
        case .mods: "shippingbox.fill"
        case .screenshots: "photo.stack.fill"
        case .account: "person.crop.circle.fill"
        case .settings: "gearshape.fill"
        }
    }

    var subtitle: String { L10n.t("nav.\(rawValue).subtitle") }
}

enum ThermalMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case coolQuiet
    case maxPerformance

    var id: String { rawValue }

    var title: String { L10n.t("thermal.\(rawValue).title") }

    var shortTitle: String {
        switch self {
        case .coolQuiet: L10n.t("thermal.coolQuiet.short")
        case .maxPerformance: L10n.t("thermal.maxPerformance.short")
        }
    }

    var subtitle: String { L10n.t("thermal.\(rawValue).subtitle") }

    var symbol: String {
        switch self {
        case .coolQuiet: "snowflake"
        case .maxPerformance: "bolt.fill"
        }
    }
}

enum GarbageCollector: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case g1
    case zgc

    var id: String { rawValue }

    var title: String { L10n.t("gc.\(rawValue).title") }

    var subtitle: String { L10n.t("gc.\(rawValue).subtitle") }
}

enum ModLoader: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case vanilla
    case fabric

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vanilla: "Vanilla"
        case .fabric: "Fabric"
        }
    }

    var symbol: String {
        switch self {
        case .vanilla: "cube.fill"
        case .fabric: "square.stack.3d.up.fill"
        }
    }

    /// Brand-ish accent used by `LoaderBadge` and loader pickers.
    var badgeHex: String {
        switch self {
        case .vanilla: "7CBD4B"   // grass green
        case .fabric: "38BDF8"    // fabric blue
        }
    }

    var modrinthName: String {
        switch self {
        case .vanilla: "minecraft"
        case .fabric: "fabric"
        }
    }
}

/// Opt-in beta features. Everything here is experimental, off by default
/// and may change or break between releases.
struct BetaFeatures: Codable, Equatable, Sendable {
    /// Neo Studio in-game HUD: companion mod auto-install on Fabric
    /// instances, launch-time config sync and the Studio apply flow.
    var inGameHUD = false
    /// Neo Studio in-game UI theme (`neocraft-ui` mod): accent tints and
    /// the optional full redesign on title/pause/death screens.
    var inGameUI = false
    /// Seed & biome radar for worlds (minimap + seed tools in backups and
    /// the instance detail hub).
    var worldRadar = false
    /// Custom JVM and game arguments in the instance editor.
    var customLaunchArgs = false
    /// Bedrock edition picker in the instance editor. Bedrock runs through
    /// the NeoCraft Bedrock component bundled inside NeoCraft.app.
    var bedrockEdition = false
    /// Bedrock Dedicated Server hosting (Windows BDS through Wine). Off by
    /// default so Bedrock gameplay doesn't come with server tooling —
    /// enable it independently in Settings → Beta Features.
    var bedrockServers = false

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inGameHUD = try container.decodeIfPresent(Bool.self, forKey: .inGameHUD) ?? false
        inGameUI = try container.decodeIfPresent(Bool.self, forKey: .inGameUI) ?? false
        worldRadar = try container.decodeIfPresent(Bool.self, forKey: .worldRadar) ?? false
        customLaunchArgs = try container.decodeIfPresent(Bool.self, forKey: .customLaunchArgs) ?? false
        bedrockEdition = try container.decodeIfPresent(Bool.self, forKey: .bedrockEdition) ?? false
        bedrockServers = try container.decodeIfPresent(Bool.self, forKey: .bedrockServers) ?? false
    }
}

/// In-game UI theme consumed by the `neocraft-ui` Fabric companion mod via
/// `config/neocraft_ui.json`. Edited in Neo Studio → In-Game UI.
struct NeoCraftUITheme: Codable, Equatable, Sendable {
    /// Master switch for the whole NeoCraft UI mod.
    var enabled = true
    /// Full NeoCraft redesign (gradient backdrop + wordmark) instead of
    /// just accent tints.
    var fullRedesign = false
    /// Accent hex without '#'.
    var accentHex = NeoAccent.prismarine.rawValue
    /// When true the in-game accent mirrors the launcher's Studio accent
    /// (`settings.accentHex`) so both UIs always match.
    var followLauncherAccent = true
    /// Screen tint hex without '#' applied as overlay. Empty = follow
    /// the effective accent color.
    var tintHex = ""
    /// Tint overlay opacity 0…1.
    var tintOpacity = 0.14
    /// Per-screen toggles (raw screen ids).
    var screenTitle = true
    var screenPause = true
    var screenDeath = true
    var screenOptions = false

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        fullRedesign = try container.decodeIfPresent(Bool.self, forKey: .fullRedesign) ?? false
        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? NeoAccent.prismarine.rawValue
        followLauncherAccent = try container.decodeIfPresent(Bool.self, forKey: .followLauncherAccent) ?? true
        tintHex = try container.decodeIfPresent(String.self, forKey: .tintHex) ?? ""
        tintOpacity = try container.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? 0.14
        screenTitle = try container.decodeIfPresent(Bool.self, forKey: .screenTitle) ?? true
        screenPause = try container.decodeIfPresent(Bool.self, forKey: .screenPause) ?? true
        screenDeath = try container.decodeIfPresent(Bool.self, forKey: .screenDeath) ?? true
        screenOptions = try container.decodeIfPresent(Bool.self, forKey: .screenOptions) ?? false
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var maxMemoryMB: Int = 4608
    var minMemoryMB: Int = 1024
    var thermalMode: ThermalMode = .coolQuiet
    var garbageCollector: GarbageCollector = .g1
    var selectedJavaPath: String?
    var showSnapshots: Bool = false
    var downloadConcurrency: Int = 8
    var openConsoleOnLaunch: Bool = false
    var lastSelectedInstanceID: UUID?
    var uiSoundsEnabled: Bool = true
    /// UI sound playback volume 0…1.
    var uiSoundVolume: Double = 0.35
    var backupToiCloud: Bool = false
    var guiScale: Int = 0
    var adaptivePerformance: Bool = false

    // MARK: Neo Studio customization

    /// Selected accent hex (without '#'). Mirrored into `StudioTheme`.
    var accentHex = NeoAccent.prismarine.rawValue
    /// Secondary glow hex used for ambient background blooms.
    var secondaryGlowHex = NeoAccent.amethystPurple.rawValue
    /// Optional card surface tint hex ("" = neutral material).
    var cardTintHex = ""
    var themeMode = NeoThemeMode.frosted
    /// Multiplier for the voxel background grid opacity (0.1…1.0).
    var gridIntensity = 1.0
    /// Raw values of `AppSection` hidden from the sidebar.
    var hiddenSections: [String] = []
    /// Raw values of `AppSection` defining sidebar order; missing = appended.
    var sidebarOrder: [String] = []
    /// Dashboard card raw values enabled on the Play screen.
    var dashboardCards: [String] = DashboardCardKind.allCases.map(\.rawValue)
    var hudLayout = HUDLayout()
    /// NeoCraft UI theme for the in-game screens mod (`neocraft_ui.json`).
    var uiTheme = NeoCraftUITheme()
    /// Active curated theme preset id ("" = custom mix).
    var curatedTheme = ""
    /// Corner treatment for cards and panels.
    var cornerStyle = NeoCornerStyle.rounded
    /// Sidebar translucency 0…1.
    var sidebarMaterial = 0.5
    /// Wallpaper effect raw value (see `WallpaperStyle` in StudioTheme).
    var wallpaperStyle = "aurora"
    /// Glass blur intensity 0…1 applied to cards and panels.
    var glassBlur = 0.5
    /// Play screen hero card style raw value: compact | banner | glass.
    var heroCardStyle = "glass"
    /// Play dashboard widget order (raw `DashboardCardKind` values);
    /// empty = default order. Hidden cards stay in `dashboardCards`.
    var dashboardWidgetOrder: [String] = []
    /// Multi-stop background bloom colors (2–3 hex strings, "" entries
    /// ignored). Empty = use accent + secondary glow blooms.
    var gradientHexes: [String] = []
    /// Corner radius preset raw value: compact | regular | spacious.
    var cornerRadiusPreset = "regular"
    /// UI language override: "system" or a `L10n` language code.
    var appLanguage = "system"
    /// Render-distance override in chunks; 0 = automatic per thermal profile.
    var renderDistanceChunks = 0
    /// Experimental features toggled in Settings → Beta Features.
    var betaFeatures = BetaFeatures()
    /// Edition preselected for newly created instances (set during onboarding).
    var preferredEdition = GameEdition.java

    static let recommendedMemoryMB = 4608
    static let memoryRange: ClosedRange<Int> = 1024...6144

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxMemoryMB = try container.decodeIfPresent(Int.self, forKey: .maxMemoryMB) ?? 4608
        minMemoryMB = try container.decodeIfPresent(Int.self, forKey: .minMemoryMB) ?? 1024
        thermalMode = try container.decodeIfPresent(ThermalMode.self, forKey: .thermalMode) ?? .coolQuiet
        garbageCollector = try container.decodeIfPresent(GarbageCollector.self, forKey: .garbageCollector) ?? .g1
        selectedJavaPath = try container.decodeIfPresent(String.self, forKey: .selectedJavaPath)
        showSnapshots = try container.decodeIfPresent(Bool.self, forKey: .showSnapshots) ?? false
        downloadConcurrency = try container.decodeIfPresent(Int.self, forKey: .downloadConcurrency) ?? 8
        openConsoleOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .openConsoleOnLaunch) ?? false
        lastSelectedInstanceID = try container.decodeIfPresent(UUID.self, forKey: .lastSelectedInstanceID)
        uiSoundsEnabled = try container.decodeIfPresent(Bool.self, forKey: .uiSoundsEnabled) ?? true
        uiSoundVolume = try container.decodeIfPresent(Double.self, forKey: .uiSoundVolume) ?? 0.35
        backupToiCloud = try container.decodeIfPresent(Bool.self, forKey: .backupToiCloud) ?? false
        guiScale = try container.decodeIfPresent(Int.self, forKey: .guiScale) ?? 0
        adaptivePerformance = try container.decodeIfPresent(Bool.self, forKey: .adaptivePerformance) ?? false
        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? NeoAccent.prismarine.rawValue
        secondaryGlowHex = try container.decodeIfPresent(String.self, forKey: .secondaryGlowHex) ?? NeoAccent.amethystPurple.rawValue
        cardTintHex = try container.decodeIfPresent(String.self, forKey: .cardTintHex) ?? ""
        themeMode = try container.decodeIfPresent(NeoThemeMode.self, forKey: .themeMode) ?? .frosted
        gridIntensity = try container.decodeIfPresent(Double.self, forKey: .gridIntensity) ?? 1.0
        hiddenSections = try container.decodeIfPresent([String].self, forKey: .hiddenSections) ?? []
        sidebarOrder = try container.decodeIfPresent([String].self, forKey: .sidebarOrder) ?? []
        dashboardCards = try container.decodeIfPresent([String].self, forKey: .dashboardCards) ?? DashboardCardKind.allCases.map(\.rawValue)
        hudLayout = try container.decodeIfPresent(HUDLayout.self, forKey: .hudLayout) ?? HUDLayout()
        uiTheme = try container.decodeIfPresent(NeoCraftUITheme.self, forKey: .uiTheme) ?? NeoCraftUITheme()
        curatedTheme = try container.decodeIfPresent(String.self, forKey: .curatedTheme) ?? ""
        cornerStyle = try container.decodeIfPresent(NeoCornerStyle.self, forKey: .cornerStyle) ?? .rounded
        sidebarMaterial = try container.decodeIfPresent(Double.self, forKey: .sidebarMaterial) ?? 0.5
        wallpaperStyle = try container.decodeIfPresent(String.self, forKey: .wallpaperStyle) ?? "aurora"
        glassBlur = try container.decodeIfPresent(Double.self, forKey: .glassBlur) ?? 0.5
        heroCardStyle = try container.decodeIfPresent(String.self, forKey: .heroCardStyle) ?? "glass"
        dashboardWidgetOrder = try container.decodeIfPresent([String].self, forKey: .dashboardWidgetOrder) ?? []
        gradientHexes = try container.decodeIfPresent([String].self, forKey: .gradientHexes) ?? []
        cornerRadiusPreset = try container.decodeIfPresent(String.self, forKey: .cornerRadiusPreset) ?? "regular"
        appLanguage = try container.decodeIfPresent(String.self, forKey: .appLanguage) ?? "system"
        renderDistanceChunks = try container.decodeIfPresent(Int.self, forKey: .renderDistanceChunks) ?? 0
        betaFeatures = try container.decodeIfPresent(BetaFeatures.self, forKey: .betaFeatures) ?? BetaFeatures()
        preferredEdition = try container.decodeIfPresent(GameEdition.self, forKey: .preferredEdition) ?? .java
    }
}

extension AppSettings {
    /// Dashboard widgets in their effective display order: the persisted
    /// `dashboardWidgetOrder` filtered to valid+enabled kinds, then any
    /// remaining enabled kinds appended in declaration order.
    var orderedDashboardKinds: [DashboardCardKind] {
        let enabled = Set(dashboardCards.compactMap(DashboardCardKind.init(rawValue:)))
        var result: [DashboardCardKind] = []
        for raw in dashboardWidgetOrder {
            if let kind = DashboardCardKind(rawValue: raw),
               enabled.contains(kind), !result.contains(kind) {
                result.append(kind)
            }
        }
        for kind in DashboardCardKind.allCases
        where enabled.contains(kind) && !result.contains(kind) {
            result.append(kind)
        }
        return result
    }
}
