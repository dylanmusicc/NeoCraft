import Foundation

/// Persists the Neo Studio "In-Game UI" theme into an instance's `config/`
/// directory as `neocraft_ui.json` — the document the `neocraft-ui` Fabric
/// companion mod reads (and hot-reloads) to skin the title, pause, death
/// and options screens and to render the in-game NeoCraft menu.
enum UIConfigWriter {

    /// The on-disk document. Field names mirror `NeoCraftUITheme` but use
    /// the `screens` map the mod expects. The `launcher*` fields mirror
    /// the launcher's Studio theme so the in-game NeoCraft menu always
    /// matches the launcher chrome.
    struct Document: Codable, Sendable {
        var format = "neocraft-ui"
        var version = 1
        var updatedAt: Date
        var enabled: Bool
        var fullRedesign: Bool
        var accentColor: String
        var tintColor: String
        var tintOpacity: Double
        var screens: [String: Bool]
        /// Launcher's Studio accent (hex with '#') — the in-game menu
        /// chrome follows this so it stays in sync with the launcher.
        var launcherAccent: String?
        /// Launcher's secondary glow used for ambient blooms.
        var launcherGlow: String?
        /// Launcher's theme mode raw value (frosted/oled/dynamic/biome).
        var themeMode: String?
        /// Launcher's corner style raw value (rounded/voxel).
        var cornerStyle: String?
        /// Launcher's wallpaper effect raw value.
        var wallpaperStyle: String?
    }

    static func document(from theme: NeoCraftUITheme, launcher settings: AppSettings) -> Document {
        // The in-game accent follows the launcher accent unless the user
        // picked a dedicated in-game accent in Studio → In-Game UI.
        let accent = theme.followLauncherAccent ? settings.accentHex : theme.accentHex
        let tint = theme.tintHex.isEmpty ? accent : theme.tintHex
        return Document(
            updatedAt: Date(),
            enabled: theme.enabled,
            fullRedesign: theme.fullRedesign,
            accentColor: "#" + accent,
            tintColor: "#" + tint,
            tintOpacity: theme.tintOpacity,
            screens: [
                "title": theme.screenTitle,
                "pause": theme.screenPause,
                "death": theme.screenDeath,
                "options": theme.screenOptions,
            ],
            launcherAccent: "#" + settings.accentHex,
            launcherGlow: "#" + settings.secondaryGlowHex,
            themeMode: settings.themeMode.rawValue,
            cornerStyle: settings.cornerStyle.rawValue,
            wallpaperStyle: settings.wallpaperStyle
        )
    }

    /// Writes `config/neocraft_ui.json` for the instance. Returns the
    /// written file URL.
    @discardableResult
    static func write(_ theme: NeoCraftUITheme, launcher settings: AppSettings, to instance: GameInstance) throws -> URL {
        let fileManager = FileManager.default
        let configRoot = instance.gameDirectory.appendingPathComponent("config", isDirectory: true)
        try fileManager.createDirectory(at: configRoot, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let url = configRoot.appendingPathComponent("neocraft_ui.json")
        try encoder.encode(document(from: theme, launcher: settings)).write(to: url, options: .atomic)
        return url
    }

    /// Best-effort write used on every Fabric launch — failures are
    /// swallowed because a missing config just means vanilla screens.
    static func writeQuietly(_ theme: NeoCraftUITheme, launcher settings: AppSettings, to instance: GameInstance) {
        _ = try? write(theme, launcher: settings, to: instance)
    }
}
