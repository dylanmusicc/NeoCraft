import Foundation

// MARK: - Neo Studio HUD sync

/// Persists a `HUDLayout` into an instance's `config/` directory so the
/// installed HUD mods render the widgets where the user placed them.
enum HUDConfigWriter {
    /// Modrinth slugs Neo Studio ensures before writing configs.
    /// MiniHUD renders the positioned modules, CustomHud provides the
    /// lightweight HUD framework, AppleSkin covers armor/hunger durability
    /// and ImmediatelyFast keeps HUD redraws cheap on the A18.
    static let recommendedMods: [String] = [
        "minihud", "customhud", "appleskin", "immediatelyfast", "modmenu"
    ]

    struct Result: Sendable {
        var filesWritten: [String]
        var modsInstalled: [String]
        var modsMissing: [String]
    }

    /// Canonical document the Neo Studio HUD sync writes — a superset of
    /// the persisted `HUDLayout` with render hints the companion mods can
    /// consume directly.
    struct SyncDocument: Codable, Sendable {
        struct Widget: Codable, Sendable {
            var kind: String
            var x: Double
            var y: Double
            var scale: Double
            var visible: Bool
            var colorHex: String
            var backgroundOpacity: Double
            var fontStyle: String
        }
        var format = "neocraft-hud"
        var version = 2
        var updatedAt: Date
        var widgets: [Widget]
    }

    /// Writes the layout to `config/neocraft_hud.json` (the canonical
    /// Neo Studio document read by HUD companion mods) and a best-effort
    /// `config/minihud.json` so MiniHUD positions its modules at the same
    /// screen coordinates.
    static func write(_ layout: HUDLayout, to instance: GameInstance) throws -> [String] {
        let fileManager = FileManager.default
        let configRoot = instance.gameDirectory.appendingPathComponent("config", isDirectory: true)
        try fileManager.createDirectory(at: configRoot, withIntermediateDirectories: true)

        var written: [String] = []

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        // 1. Canonical Neo Studio HUD document (v2 — superseded on disk by
        //    the v3 document `writeDocument` produces; kept for callers
        //    that only need the legacy shape).
        let document = SyncDocument(
            updatedAt: Date(),
            widgets: layout.widgets.map { widget in
                SyncDocument.Widget(
                    kind: widget.kind.rawValue,
                    x: widget.x,
                    y: widget.y,
                    scale: widget.scale,
                    visible: widget.visible,
                    colorHex: widget.colorHex,
                    backgroundOpacity: widget.backgroundOpacity,
                    fontStyle: widget.fontStyle.rawValue
                )
            }
        )
        let canonical = configRoot.appendingPathComponent("neocraft_hud.json")
        try encoder.encode(document).write(to: canonical, options: .atomic)
        written.append(canonical.path)

        // 2 + 3. Legacy mirrors (neo-hud.json, minihud.json).
        written.append(contentsOf: try writeLegacyMirrors(layout, configRoot: configRoot, encoder: encoder))

        return written
    }

    /// Writes the legacy `neocraft/neo-hud.json` + `minihud.json` mirrors
    /// for a layout. Shared by `write` and `writeDocument`.
    private static func writeLegacyMirrors(
        _ layout: HUDLayout,
        configRoot: URL,
        encoder: JSONEncoder
    ) throws -> [String] {
        let fileManager = FileManager.default
        var written: [String] = []

        // Legacy mirror kept for older installs.
        let legacyDir = configRoot.appendingPathComponent("neocraft", isDirectory: true)
        try fileManager.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyURL = legacyDir.appendingPathComponent("neo-hud.json")
        try encoder.encode(layout).write(to: legacyURL, options: .atomic)
        written.append(legacyURL.path)

        // MiniHUD-compatible module positions.
        if let minihudData = minihudConfig(for: layout), !minihudData.isEmpty {
            let miniURL = configRoot.appendingPathComponent("minihud.json")
            try minihudData.write(to: miniURL, options: .atomic)
            written.append(miniURL.path)
        }

        return written
    }

    /// Builds a MiniHUD JSON document mapping our widget kinds onto
    /// MiniHUD module names with pixel coordinates on a 1920×1080 canvas.
    private static func minihudConfig(for layout: HUDLayout) -> Data? {
        struct Module: Encodable {
            var x: Int
            var y: Int
            var enabled: Bool
        }
        struct Config: Encodable {
            var modules: [String: Module]
        }

        var modules: [String: Module] = [:]
        for widget in layout.widgets where widget.visible {
            // Convert normalized 0…1 canvas coordinates to 1920×1080 pixels.
            let px = Int((widget.x * 1920).rounded())
            let py = Int((widget.y * 1080).rounded())
            let scale = Int((widget.scale * 100).rounded())
            for module in widget.kind.miniHUDModules {
                modules[module] = Module(x: px, y: py, enabled: scale > 0)
            }
        }
        guard !modules.isEmpty else { return nil }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(Config(modules: modules))
    }
}

// MARK: - v3 profile document (neocraft-hud format)

/// Arbitrary option value inside a v3 widget's `options` map.
enum HUDOptionValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .string("")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}

/// The `ui` object of the v3 document — vanilla-HUD tweaks the companion
/// mod applies on top of the widget layer. Every field optional.
struct HUDUITweaks: Codable, Sendable, Equatable {
    struct Section: Codable, Sendable, Equatable {
        var enabled: Bool?
        var scale: Double?
        var opacity: Double?

        init(enabled: Bool? = nil, scale: Double? = nil, opacity: Double? = nil) {
            self.enabled = enabled
            self.scale = scale
            self.opacity = opacity
        }

        private enum CodingKeys: String, CodingKey { case enabled, scale, opacity }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
            scale = try container.decodeIfPresent(Double.self, forKey: .scale)
            opacity = try container.decodeIfPresent(Double.self, forKey: .opacity)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(enabled, forKey: .enabled)
            try container.encodeIfPresent(scale, forKey: .scale)
            try container.encodeIfPresent(opacity, forKey: .opacity)
        }
    }

    var crosshair: Section?
    var hotbar: Section?
    var scoreboard: Section?
    var chat: Section?
    var titleScreen: Section?

    init(
        crosshair: Section? = nil,
        hotbar: Section? = nil,
        scoreboard: Section? = nil,
        chat: Section? = nil,
        titleScreen: Section? = nil
    ) {
        self.crosshair = crosshair
        self.hotbar = hotbar
        self.scoreboard = scoreboard
        self.chat = chat
        self.titleScreen = titleScreen
    }

    private enum CodingKeys: String, CodingKey {
        case crosshair, hotbar, scoreboard, chat, titleScreen
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        crosshair = try container.decodeIfPresent(Section.self, forKey: .crosshair)
        hotbar = try container.decodeIfPresent(Section.self, forKey: .hotbar)
        scoreboard = try container.decodeIfPresent(Section.self, forKey: .scoreboard)
        chat = try container.decodeIfPresent(Section.self, forKey: .chat)
        titleScreen = try container.decodeIfPresent(Section.self, forKey: .titleScreen)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(crosshair, forKey: .crosshair)
        try container.encodeIfPresent(hotbar, forKey: .hotbar)
        try container.encodeIfPresent(scoreboard, forKey: .scoreboard)
        try container.encodeIfPresent(chat, forKey: .chat)
        try container.encodeIfPresent(titleScreen, forKey: .titleScreen)
    }
}

/// One widget inside a v3 profile — carries every field the companion mod
/// understands, including the ones `HUDWidget` cannot represent
/// (`containerStyle`, `textStyle`, `colorMode`, `textColor`, `borderColor`,
/// `options`). `x`/`y` are normalized 0–1 CENTER anchors.
struct HUDConfigWidget: Codable, Sendable, Equatable {
    var id: String?
    var kind: String
    var x: Double
    var y: Double
    var scale: Double
    var visible: Bool
    var containerStyle: String?
    var fontStyle: String?
    var textStyle: String?
    var colorMode: String?
    var textColor: String?
    var accentColor: String?
    var borderColor: String?
    var backgroundOpacity: Double?
    var options: [String: HUDOptionValue]

    init(
        id: String? = nil,
        kind: String,
        x: Double = 0.5,
        y: Double = 0.5,
        scale: Double = 1.0,
        visible: Bool = true,
        containerStyle: String? = nil,
        fontStyle: String? = nil,
        textStyle: String? = nil,
        colorMode: String? = nil,
        textColor: String? = nil,
        accentColor: String? = nil,
        borderColor: String? = nil,
        backgroundOpacity: Double? = nil,
        options: [String: HUDOptionValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.x = x
        self.y = y
        self.scale = scale
        self.visible = visible
        self.containerStyle = containerStyle
        self.fontStyle = fontStyle
        self.textStyle = textStyle
        self.colorMode = colorMode
        self.textColor = textColor
        self.accentColor = accentColor
        self.borderColor = borderColor
        self.backgroundOpacity = backgroundOpacity
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, x, y, scale, visible, containerStyle, fontStyle
        case textStyle, colorMode, textColor, accentColor, borderColor
        case backgroundOpacity, options, colorHex
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Tolerant: `id` may be a string or number depending on writer.
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        x = (try? container.decodeIfPresent(Double.self, forKey: .x)) ?? 0.5
        y = (try? container.decodeIfPresent(Double.self, forKey: .y)) ?? 0.5
        scale = (try? container.decodeIfPresent(Double.self, forKey: .scale)) ?? 1.0
        visible = (try? container.decodeIfPresent(Bool.self, forKey: .visible)) ?? true
        containerStyle = try? container.decodeIfPresent(String.self, forKey: .containerStyle)
        fontStyle = try? container.decodeIfPresent(String.self, forKey: .fontStyle)
        textStyle = try? container.decodeIfPresent(String.self, forKey: .textStyle)
        colorMode = try? container.decodeIfPresent(String.self, forKey: .colorMode)
        textColor = try? container.decodeIfPresent(String.self, forKey: .textColor)
        // v2 documents used `colorHex`; treat it as the accent color.
        accentColor = (try? container.decodeIfPresent(String.self, forKey: .accentColor))
            ?? (try? container.decodeIfPresent(String.self, forKey: .colorHex))
        borderColor = try? container.decodeIfPresent(String.self, forKey: .borderColor)
        backgroundOpacity = try? container.decodeIfPresent(Double.self, forKey: .backgroundOpacity)
        options = (try? container.decodeIfPresent([String: HUDOptionValue].self, forKey: .options)) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(scale, forKey: .scale)
        try container.encode(visible, forKey: .visible)
        try container.encodeIfPresent(containerStyle, forKey: .containerStyle)
        try container.encodeIfPresent(fontStyle, forKey: .fontStyle)
        try container.encodeIfPresent(textStyle, forKey: .textStyle)
        try container.encodeIfPresent(colorMode, forKey: .colorMode)
        try container.encodeIfPresent(textColor, forKey: .textColor)
        try container.encodeIfPresent(accentColor, forKey: .accentColor)
        try container.encodeIfPresent(borderColor, forKey: .borderColor)
        try container.encodeIfPresent(backgroundOpacity, forKey: .backgroundOpacity)
        if !options.isEmpty {
            try container.encode(options, forKey: .options)
        }
    }
}

/// A named widget profile inside the v3 document.
struct HUDConfigProfile: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var widgets: [HUDConfigWidget]

    init(id: String, name: String, widgets: [HUDConfigWidget] = []) {
        self.id = id
        self.name = name
        self.widgets = widgets
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Default"
        widgets = (try? container.decodeIfPresent([HUDConfigWidget].self, forKey: .widgets)) ?? []
    }
}

/// The v3 `neocraft-hud` document: `{format, version:3, updatedAt,
/// activeProfile, profiles[], ui{}}`. Tolerantly decodes legacy v2 files
/// (flat top-level `widgets` array → wrapped into a "default" profile).
struct HUDConfigDocument: Codable, Sendable, Equatable {
    var format: String
    var version: Int
    var updatedAt: Date
    var activeProfile: String
    var profiles: [HUDConfigProfile]
    var ui: HUDUITweaks?

    static let defaultProfileID = "default"

    init(
        format: String = "neocraft-hud",
        version: Int = 3,
        updatedAt: Date = Date(),
        activeProfile: String = HUDConfigDocument.defaultProfileID,
        profiles: [HUDConfigProfile] = [],
        ui: HUDUITweaks? = nil
    ) {
        self.format = format
        self.version = version
        self.updatedAt = updatedAt
        self.activeProfile = activeProfile
        self.profiles = profiles
        self.ui = ui
    }

    private enum CodingKeys: String, CodingKey {
        case format, version, updatedAt, activeProfile, profiles, ui, widgets
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? container.decodeIfPresent(String.self, forKey: .format)) ?? "neocraft-hud"
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? 3
        updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
        activeProfile = (try? container.decodeIfPresent(String.self, forKey: .activeProfile))
            ?? HUDConfigDocument.defaultProfileID
        ui = try? container.decodeIfPresent(HUDUITweaks.self, forKey: .ui)

        if let profiles = try? container.decodeIfPresent([HUDConfigProfile].self, forKey: .profiles),
           !profiles.isEmpty {
            self.profiles = profiles
        } else if let legacyWidgets = try? container.decodeIfPresent(
            [HUDConfigWidget].self, forKey: .widgets
        ) {
            // Legacy v2: flat widgets array → single default profile.
            self.profiles = [HUDConfigProfile(
                id: HUDConfigDocument.defaultProfileID,
                name: "Default Apple",
                widgets: legacyWidgets
            )]
        } else {
            self.profiles = []
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(format, forKey: .format)
        try container.encode(version, forKey: .version)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(activeProfile, forKey: .activeProfile)
        try container.encode(profiles, forKey: .profiles)
        try container.encodeIfPresent(ui, forKey: .ui)
    }

    /// The profile the launcher considers active: `activeProfile` when it
    /// exists, otherwise the first profile.
    var active: HUDConfigProfile? {
        profiles.first { $0.id == activeProfile } ?? profiles.first
    }
}

// MARK: - v3 document IO

extension HUDConfigWriter {

    /// Loads and decodes `config/neocraft_hud.json` as a v3 document.
    /// Returns nil when the file is missing or unreadable.
    static func loadDocument(at configFile: URL) -> HUDConfigDocument? {
        guard let data = try? Data(contentsOf: configFile), !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HUDConfigDocument.self, from: data)
    }

    /// Extracts the active profile's widgets as a `HUDLayout`.
    ///
    /// Limitation: `HUDWidget` (owned by StudioTheme) can only carry
    /// `kind/x/y/scale/visible/colorHex/backgroundOpacity/fontStyle`, so
    /// `containerStyle`, `textStyle`, `colorMode`, `textColor`,
    /// `borderColor` and `options` are dropped here — they survive in the
    /// on-disk document but not in the launcher's in-memory layout.
    /// Widgets whose `kind` isn't a known `HUDWidgetKind` are skipped.
    static func loadLayout(from configFile: URL) -> HUDLayout? {
        guard let document = loadDocument(at: configFile),
              let profile = document.active else { return nil }
        let widgets = profile.widgets.compactMap { widget -> HUDWidget? in
            guard let kind = HUDWidgetKind(rawValue: widget.kind) else { return nil }
            let hex = (widget.accentColor ?? widget.textColor ?? "5B8CFF")
                .replacingOccurrences(of: "#", with: "")
            let fontStyle: HUDFontStyle = widget.fontStyle == "minecraft" ? .minecraft : .apple
            return HUDWidget(
                id: widget.id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                kind: kind,
                x: widget.x,
                y: widget.y,
                scale: widget.scale,
                visible: widget.visible,
                colorHex: hex,
                backgroundOpacity: widget.backgroundOpacity ?? 0.45,
                fontStyle: fontStyle
            )
        }
        guard !widgets.isEmpty else { return nil }
        return HUDLayout(widgets: widgets)
    }

    /// Writes a v3 `HUDConfigDocument` to `config/neocraft_hud.json` and
    /// refreshes the legacy `neo-hud.json`/`minihud.json` mirrors from the
    /// document's active profile. Returns the written file paths.
    static func writeDocument(_ doc: HUDConfigDocument, to instance: GameInstance) throws -> [String] {
        let fileManager = FileManager.default
        let configRoot = instance.gameDirectory.appendingPathComponent("config", isDirectory: true)
        try fileManager.createDirectory(at: configRoot, withIntermediateDirectories: true)

        var written: [String] = []

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let canonical = configRoot.appendingPathComponent("neocraft_hud.json")
        try encoder.encode(doc).write(to: canonical, options: .atomic)
        written.append(canonical.path)

        // Keep the legacy mirrors in sync with the active profile.
        if let layout = layout(from: doc) {
            written.append(contentsOf: try writeLegacyMirrors(
                layout, configRoot: configRoot, encoder: encoder
            ))
        }

        return written
    }

    /// Converts the launcher's `HUDLayout` into a v3 document with a
    /// single "default" profile named "Default Apple". `x`/`y` stay
    /// normalized 0–1 and are treated as CENTER anchors by the mod,
    /// consistent with `HUDWidget` semantics.
    static func document(from layout: HUDLayout, ui: HUDUITweaks? = nil) -> HUDConfigDocument {
        let widgets = layout.widgets.map { widget in
            HUDConfigWidget(
                id: widget.id.uuidString,
                kind: widget.kind.rawValue,
                x: widget.x,
                y: widget.y,
                scale: widget.scale,
                visible: widget.visible,
                containerStyle: "applePill",
                fontStyle: widget.fontStyle.rawValue,
                textStyle: "regular",
                colorMode: "static",
                textColor: "#FFFFFF",
                accentColor: "#" + widget.colorHex,
                borderColor: nil,
                backgroundOpacity: widget.backgroundOpacity,
                options: [:]
            )
        }
        return HUDConfigDocument(
            updatedAt: Date(),
            activeProfile: HUDConfigDocument.defaultProfileID,
            profiles: [
                HUDConfigProfile(
                    id: HUDConfigDocument.defaultProfileID,
                    name: "Default Apple",
                    widgets: widgets
                )
            ],
            ui: ui
        )
    }

    /// `HUDLayout` view of a document's active profile — same mapping as
    /// `loadLayout(from:)` but without touching disk.
    private static func layout(from doc: HUDConfigDocument) -> HUDLayout? {
        guard let profile = doc.active else { return nil }
        let widgets = profile.widgets.compactMap { widget -> HUDWidget? in
            guard let kind = HUDWidgetKind(rawValue: widget.kind) else { return nil }
            let hex = (widget.accentColor ?? widget.textColor ?? "5B8CFF")
                .replacingOccurrences(of: "#", with: "")
            let fontStyle: HUDFontStyle = widget.fontStyle == "minecraft" ? .minecraft : .apple
            return HUDWidget(
                id: widget.id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                kind: kind,
                x: widget.x,
                y: widget.y,
                scale: widget.scale,
                visible: widget.visible,
                colorHex: hex,
                backgroundOpacity: widget.backgroundOpacity ?? 0.45,
                fontStyle: fontStyle
            )
        }
        guard !widgets.isEmpty else { return nil }
        return HUDLayout(widgets: widgets)
    }
}
