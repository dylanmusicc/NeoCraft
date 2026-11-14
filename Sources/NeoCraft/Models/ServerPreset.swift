import Foundation

/// One-click `server.properties` setups for hosted Java servers. Each
/// preset is a curated key set applied on top of the creation defaults —
/// the user can still edit every value afterwards in the dashboard.
enum ServerPreset: String, CaseIterable, Identifiable, Hashable, Sendable {
    case survival
    case creative
    case hardcore
    case minigame
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .survival: "Survival"
        case .creative: "Creative"
        case .hardcore: "Hardcore"
        case .minigame: "Minigame"
        case .custom: "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .survival: "figure.walk"
        case .creative: "hammer.fill"
        case .hardcore: "flame.fill"
        case .minigame: "gamecontroller.fill"
        case .custom: "slider.horizontal.3"
        }
    }

    var detail: String {
        switch self {
        case .survival: "Normal difficulty, survival gamemode, PvP on, 10-chunk view distance."
        case .creative: "Creative gamemode, peaceful-friendly defaults, PvP off, wider view."
        case .hardcore: "Hardcore mode on hard difficulty — one life, no respawn."
        case .minigame: "Adventure gamemode, monsters off, fast respawn-friendly rules."
        case .custom: "Start from NeoCraft's balanced defaults and tune everything yourself."
        }
    }

    /// `server.properties` overrides applied after creation (and whenever
    /// re-applied from the dashboard). Keys not listed keep their values.
    var properties: [String: String] {
        switch self {
        case .survival:
            return [
                "difficulty": "normal",
                "gamemode": "survival",
                "hardcore": "false",
                "pvp": "true",
                "spawn-monsters": "true",
                "view-distance": "10",
                "spawn-protection": "16",
            ]
        case .creative:
            return [
                "difficulty": "normal",
                "gamemode": "creative",
                "hardcore": "false",
                "pvp": "false",
                "spawn-monsters": "true",
                "view-distance": "12",
                "spawn-protection": "0",
            ]
        case .hardcore:
            return [
                "difficulty": "hard",
                "gamemode": "survival",
                "hardcore": "true",
                "pvp": "true",
                "spawn-monsters": "true",
                "view-distance": "10",
                "spawn-protection": "16",
            ]
        case .minigame:
            return [
                "difficulty": "normal",
                "gamemode": "adventure",
                "hardcore": "false",
                "pvp": "true",
                "spawn-monsters": "false",
                "view-distance": "8",
                "spawn-protection": "0",
            ]
        case .custom:
            return [:]
        }
    }

    /// Bedrock `server.properties` equivalents (same key names where BDS
    /// supports them — difficulty/gamemode/pvp exist; hardcore and
    /// spawn-monsters don't).
    var bedrockProperties: [String: String] {
        switch self {
        case .survival:
            return ["difficulty": "normal", "gamemode": "survival", "pvp": "true"]
        case .creative:
            return ["difficulty": "normal", "gamemode": "creative", "pvp": "false"]
        case .hardcore:
            return ["difficulty": "hard", "gamemode": "survival", "pvp": "true"]
        case .minigame:
            return ["difficulty": "normal", "gamemode": "adventure", "pvp": "true"]
        case .custom:
            return [:]
        }
    }
}
