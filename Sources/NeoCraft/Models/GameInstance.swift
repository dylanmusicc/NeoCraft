import Foundation

/// Minecraft edition an instance targets.
enum GameEdition: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case java
    case bedrock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .java: "Java Edition"
        case .bedrock: "Bedrock Edition"
        }
    }

    var shortTitle: String {
        switch self {
        case .java: "Java"
        case .bedrock: "Bedrock"
        }
    }

    var symbol: String {
        switch self {
        case .java: "cup.and.saucer.fill"
        case .bedrock: "gamecontroller.fill"
        }
    }
}

struct GameInstance: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Minecraft edition — Bedrock instances launch through NeoCraft
    /// Bedrock instead of the Java pipeline.
    var edition: GameEdition
    var minecraftVersion: String
    var loader: ModLoader
    var fabricLoaderVersion: String?
    var iconSymbol: String
    /// Minecraft block id (`MinecraftBlockIcon` raw value) used for the
    /// instance's pixel-art icon, e.g. "grass_block".
    var iconBlock: String
    var colorHex: String
    var created: Date
    var lastPlayed: Date?
    var totalPlayTime: TimeInterval
    var memoryMB: Int?
    var neoBoost: Bool
    var javaPath: String?
    var jvmArgs: String
    var gameArgs: String
    var macosInputFix: Bool
    /// Per-instance GUI scale override (0 = auto, nil = use global setting).
    var guiScale: Int?

    init(
        id: UUID = UUID(),
        name: String,
        minecraftVersion: String,
        edition: GameEdition = .java,
        loader: ModLoader = .fabric,
        fabricLoaderVersion: String? = nil,
        iconSymbol: String = "cube.fill",
        iconBlock: String = "grass_block",
        colorHex: String = InstanceStyle.palette[0],
        memoryMB: Int? = nil,
        neoBoost: Bool = true
    ) {
        self.id = id
        self.name = name
        self.edition = edition
        self.minecraftVersion = minecraftVersion
        self.loader = loader
        self.fabricLoaderVersion = fabricLoaderVersion
        self.iconSymbol = iconSymbol
        self.iconBlock = iconBlock
        self.colorHex = colorHex
        self.created = Date()
        self.lastPlayed = nil
        self.totalPlayTime = 0
        self.memoryMB = memoryMB
        self.neoBoost = loader == .fabric ? neoBoost : false
        self.javaPath = nil
        self.jvmArgs = ""
        self.gameArgs = ""
        self.macosInputFix = false
        self.guiScale = nil
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Instance"
        edition = try container.decodeIfPresent(GameEdition.self, forKey: .edition) ?? .java
        minecraftVersion = try container.decodeIfPresent(String.self, forKey: .minecraftVersion) ?? "1.21.1"
        loader = try container.decodeIfPresent(ModLoader.self, forKey: .loader) ?? .vanilla
        fabricLoaderVersion = try container.decodeIfPresent(String.self, forKey: .fabricLoaderVersion)
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol) ?? "cube.fill"
        iconBlock = try container.decodeIfPresent(String.self, forKey: .iconBlock) ?? "grass_block"
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? InstanceStyle.palette[0]
        created = try container.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        lastPlayed = try container.decodeIfPresent(Date.self, forKey: .lastPlayed)
        totalPlayTime = try container.decodeIfPresent(TimeInterval.self, forKey: .totalPlayTime) ?? 0
        memoryMB = try container.decodeIfPresent(Int.self, forKey: .memoryMB)
        neoBoost = try container.decodeIfPresent(Bool.self, forKey: .neoBoost) ?? false
        javaPath = try container.decodeIfPresent(String.self, forKey: .javaPath)
        jvmArgs = try container.decodeIfPresent(String.self, forKey: .jvmArgs) ?? ""
        gameArgs = try container.decodeIfPresent(String.self, forKey: .gameArgs) ?? ""
        macosInputFix = try container.decodeIfPresent(Bool.self, forKey: .macosInputFix) ?? false
        guiScale = try container.decodeIfPresent(Int.self, forKey: .guiScale)
    }

    var directory: URL { AppPaths.instanceDirectory(id) }
    var gameDirectory: URL { AppPaths.gameDirectory(id) }
    var versionLabel: String {
        if edition == .bedrock { return "\(minecraftVersion) · Bedrock" }
        return loader == .fabric ? "\(minecraftVersion) · Fabric" : "\(minecraftVersion) · Vanilla"
    }

    var effectiveMemoryMB: Int {
        memoryMB ?? AppSettings.recommendedMemoryMB
    }
}

enum InstanceStyle {
    static let palette: [String] = [
        "4ADE80", "38BDF8", "A78BFA", "FB923C", "F472B6", "FACC15",
        "2DD4BF", "F87171", "93C5FD", "C084FC"
    ]

    static let symbols: [String] = [
        "cube.fill", "leaf.fill", "flame.fill", "bolt.fill", "moon.stars.fill",
        "gamecontroller.fill", "tree.fill", "diamond.fill", "sparkles", "hare.fill",
        "mountain.2.fill", "drop.fill"
    ]
}

struct InstanceStats: Sendable {
    var modCount: Int = 0
    var resourcePackCount: Int = 0
    var shaderPackCount: Int = 0
    var worldCount: Int = 0
    var diskBytes: Int64 = 0
    var screenshots: [URL] = []
    var boostInstalled: Bool = false
    var gameInstalled: Bool = false
}
