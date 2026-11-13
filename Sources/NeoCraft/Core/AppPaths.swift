import Foundation

enum AppPaths {
    static let applicationSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("NeoCraft", isDirectory: true)
    }()

    static var root: URL { applicationSupport }
    static var shared: URL { root.appendingPathComponent("shared", isDirectory: true) }
    static var libraries: URL { shared.appendingPathComponent("libraries", isDirectory: true) }
    static var assets: URL { shared.appendingPathComponent("assets", isDirectory: true) }
    static var assetObjects: URL { assets.appendingPathComponent("objects", isDirectory: true) }
    static var assetIndexes: URL { assets.appendingPathComponent("indexes", isDirectory: true) }
    static var assetVirtual: URL { assets.appendingPathComponent("virtual", isDirectory: true) }
    static var logConfigs: URL { assets.appendingPathComponent("log_configs", isDirectory: true) }
    static var versions: URL { shared.appendingPathComponent("versions", isDirectory: true) }
    static var runtime: URL { root.appendingPathComponent("runtime", isDirectory: true) }
    static var instances: URL { root.appendingPathComponent("instances", isDirectory: true) }
    static var servers: URL { root.appendingPathComponent("servers", isDirectory: true) }
    static var cache: URL { root.appendingPathComponent("cache", isDirectory: true) }
    static var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    static var skins: URL { root.appendingPathComponent("skins", isDirectory: true) }
    static var stateFile: URL { root.appendingPathComponent("state.json", isDirectory: false) }

    static func skinFile(for accountUUID: String) -> URL {
        skins.appendingPathComponent("\(accountUUID).png", isDirectory: false)
    }

    static func instanceDirectory(_ id: UUID) -> URL {
        instances.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func gameDirectory(_ id: UUID) -> URL {
        instanceDirectory(id).appendingPathComponent("minecraft", isDirectory: true)
    }

    static func nativesDirectory(_ id: UUID) -> URL {
        instanceDirectory(id).appendingPathComponent("natives", isDirectory: true)
    }

    static func instanceMetadataDirectory(_ id: UUID) -> URL {
        instanceDirectory(id).appendingPathComponent("neocraft", isDirectory: true)
    }

    static func serverDirectory(_ id: UUID) -> URL {
        servers.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func installedManifest(_ id: UUID) -> URL {
        instanceMetadataDirectory(id).appendingPathComponent("installed.json", isDirectory: false)
    }

    static func boostMarker(_ id: UUID) -> URL {
        instanceMetadataDirectory(id).appendingPathComponent("neo-boost.json", isDirectory: false)
    }

    static func logFile() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return logs.appendingPathComponent("neocraft-\(formatter.string(from: Date())).log", isDirectory: false)
    }

    static let allDirectories: [URL] = [
        root, shared, libraries, assets, assetObjects, assetIndexes, assetVirtual,
        logConfigs, versions, runtime, instances, servers, cache, logs, skins
    ]

    @discardableResult
    static func ensureDirectories() throws -> URL {
        for directory in allDirectories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return root
    }

    static func folder(forProjectType type: ModrinthProjectType, instance: GameInstance) -> URL {
        let gameDirectory = gameDirectory(instance.id)
        switch type {
        case .mod:
            return gameDirectory.appendingPathComponent("mods", isDirectory: true)
        case .resourcepack:
            return gameDirectory.appendingPathComponent("resourcepacks", isDirectory: true)
        case .shader:
            return gameDirectory.appendingPathComponent("shaderpacks", isDirectory: true)
        case .datapack:
            return gameDirectory.appendingPathComponent("datapacks", isDirectory: true)
        case .modpack:
            return gameDirectory.appendingPathComponent("modpacks", isDirectory: true)
        case .plugin:
            return gameDirectory.appendingPathComponent("plugins", isDirectory: true)
        }
    }
}
