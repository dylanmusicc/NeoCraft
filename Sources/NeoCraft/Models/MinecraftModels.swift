import Foundation

struct MinecraftLatestVersions: Codable, Sendable {
    var release: String
    var snapshot: String
}

struct MinecraftVersionManifest: Codable, Sendable {
    var latest: MinecraftLatestVersions
    var versions: [MinecraftVersionSummary]
}

struct MinecraftVersionSummary: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var type: String
    var url: String
    var time: String?
    var releaseTime: String?
    var sha1: String?
    var complianceLevel: Int?

    var isRelease: Bool { type == "release" }
    var isSnapshot: Bool { type == "snapshot" }
}

struct MinecraftVersionDetails: Codable, Identifiable, Sendable {
    var id: String
    var type: String?
    var mainClass: String
    var inheritsFrom: String?
    var assets: String?
    var assetIndex: MinecraftAssetIndexReference?
    var downloads: [String: MinecraftDownloadInfo]?
    var libraries: [MinecraftLibrary]?
    var javaVersion: MinecraftJavaVersion?
    var logging: MinecraftLogging?
    var arguments: MinecraftArguments?
    var minecraftArguments: String?
    var releaseTime: String?
    var time: String?
    var minimumLauncherVersion: Int?

    var allLibraries: [MinecraftLibrary] { libraries ?? [] }
    var clientDownload: MinecraftDownloadInfo? { downloads?["client"] }
    var requiredJavaMajor: Int { javaVersion?.majorVersion ?? 21 }
    var assetIndexName: String? { assetIndex?.id ?? assets }
}

struct MinecraftAssetIndexReference: Codable, Sendable {
    var id: String
    var sha1: String
    var size: Int64?
    var totalSize: Int64?
    var url: String
}

struct MinecraftAssetIndex: Codable, Sendable {
    var objects: [String: MinecraftAssetObject]
    var virtual: Bool?
    var mapToResources: Bool?

    enum CodingKeys: String, CodingKey {
        case objects
        case virtual
        case mapToResources = "map_to_resources"
    }
}

struct MinecraftAssetObject: Codable, Sendable {
    var hash: String
    var size: Int64
}

struct MinecraftDownloadInfo: Codable, Sendable {
    var path: String?
    var sha1: String?
    var size: Int64?
    var url: String
    var id: String?
}

struct MinecraftJavaVersion: Codable, Sendable {
    var component: String?
    var majorVersion: Int
}

struct MinecraftLogging: Codable, Sendable {
    var client: MinecraftLoggingClient?
}

struct MinecraftLoggingClient: Codable, Sendable {
    var argument: String
    var file: MinecraftDownloadInfo
    var type: String?
}

struct MinecraftArguments: Codable, Sendable {
    var game: [MinecraftArgumentValue]?
    var jvm: [MinecraftArgumentValue]?
}

struct MinecraftLibrary: Codable, Sendable {
    var name: String
    var downloads: MinecraftLibraryDownloads?
    var natives: [String: String]?
    var rules: [MinecraftRule]?
    var extract: MinecraftExtractRule?
    var url: String?
    var sha1: String?
    var size: Int64?
}

struct MinecraftLibraryDownloads: Codable, Sendable {
    var artifact: MinecraftDownloadInfo?
    var classifiers: [String: MinecraftDownloadInfo]?
}

struct MinecraftExtractRule: Codable, Sendable {
    var exclude: [String]?
}

struct MinecraftRule: Codable, Sendable {
    var action: String
    var os: MinecraftOSRule?
    var features: [String: Bool]?
}

struct MinecraftOSRule: Codable, Sendable {
    var name: String?
    var arch: String?
    var version: String?
}

struct MinecraftRuleContext: Sendable {
    var osName: String = "osx"
    var osArch: String = "arm64"
    var osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    var features: [String: Bool] = [
        "has_custom_resolution": false,
        "is_demo_user": false,
        "has_quick_plays_support": false,
        "is_quick_play_singleplayer": false,
        "is_quick_play_multiplayer": false,
        "is_quick_play_realms": false
    ]

    static let current: MinecraftRuleContext = {
        var context = MinecraftRuleContext()
        #if arch(arm64)
        context.osArch = "arm64"
        #else
        context.osArch = "x86_64"
        #endif
        return context
    }()
}

extension MinecraftRule {
    func matches(_ context: MinecraftRuleContext) -> Bool {
        if let os {
            if let name = os.name, name.caseInsensitiveCompare(context.osName) != .orderedSame {
                return false
            }
            if let arch = os.arch {
                let normalized = arch == "x86" ? "x86_64" : arch
                if normalized.caseInsensitiveCompare(context.osArch) != .orderedSame {
                    return false
                }
            }
            if let version = os.version {
                let pattern = version.hasPrefix("^") ? version : "^" + NSRegularExpression.escapedPattern(for: version)
                if let regex = try? NSRegularExpression(pattern: pattern),
                   regex.firstMatch(in: context.osVersion, range: NSRange(context.osVersion.startIndex..., in: context.osVersion)) == nil {
                    return false
                }
            }
        }
        if let features {
            for (key, expected) in features {
                let actual = context.features[key] ?? false
                if actual != expected {
                    return false
                }
            }
        }
        return true
    }
}

extension Array where Element == MinecraftRule {
    func allows(_ context: MinecraftRuleContext = .current) -> Bool {
        guard !isEmpty else { return true }
        var allowed = false
        for rule in self where rule.matches(context) {
            allowed = rule.action == "allow"
        }
        return allowed
    }
}

enum MinecraftArgumentValue: Codable, Sendable {
    case string(String)
    case conditional(rules: [MinecraftRule], value: [String])

    enum CodingKeys: String, CodingKey {
        case rules
        case value
    }

    init(from decoder: any Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let string = try? single.decode(String.self) {
            self = .string(string)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rules = try container.decodeIfPresent([MinecraftRule].self, forKey: .rules) ?? []
        let values = try container.decode(ArgumentStringArray.self, forKey: .value).values
        self = .conditional(rules: rules, value: values)
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .string(let string):
            var container = encoder.singleValueContainer()
            try container.encode(string)
        case .conditional(let rules, let value):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rules, forKey: .rules)
            try container.encode(value, forKey: .value)
        }
    }

    func resolvedValues(context: MinecraftRuleContext) -> [String] {
        switch self {
        case .string(let string):
            return [string]
        case .conditional(let rules, let value):
            return rules.allows(context) ? value : []
        }
    }
}

struct ArgumentStringArray: Codable, Sendable {
    var values: [String]

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let values = try? container.decode([String].self) {
            self.values = values
        } else {
            self.values = [try container.decode(String.self)]
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

extension MinecraftVersionDetails {
    func resolvedGameArguments(context: MinecraftRuleContext = .current) -> [String] {
        if let gameArguments = arguments?.game, !gameArguments.isEmpty {
            return gameArguments.flatMap { $0.resolvedValues(context: context) }
        }
        if let legacy = minecraftArguments, !legacy.isEmpty {
            return CommandLineSplitter.split(legacy)
        }
        return []
    }
}

enum CommandLineSplitter {
    static func split(_ string: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escaping = false

        for character in string {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            switch character {
            case "\\" where inDouble:
                escaping = true
            case "\"" where !inSingle:
                inDouble.toggle()
            case "'" where !inDouble:
                inSingle.toggle()
            case " " where !inSingle && !inDouble:
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            default:
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

struct FabricLoaderReference: Codable, Sendable {
    var version: String
    var stable: Bool?
}

struct FabricLoaderInfo: Codable, Sendable {
    var loader: FabricLoaderReference
}

struct FabricIntermediary: Codable, Sendable {
    var version: String
}

struct PatchNoteEntry: Codable, Identifiable, Sendable {
    var title: String
    var version: String
    var type: String
    var image: PatchNoteImage?
    var contentPath: String?
    var id: String
    var date: String
    var shortText: String?

    enum CodingKeys: String, CodingKey {
        case title, version, type, image, contentPath, id, date, shortText
    }
}

struct PatchNoteImage: Codable, Sendable {
    var title: String?
    var url: String?
}

struct PatchNoteDetail: Codable, Sendable {
    var title: String
    var version: String?
    var type: String?
    var body: String?
    var image: PatchNoteImage?
    var date: String?
}

struct PatchNotesFile: Codable, Sendable {
    var version: Int?
    var entries: [PatchNoteEntry]
}
