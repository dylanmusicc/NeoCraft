import Foundation

struct StoreFile: Codable, Sendable {
    var settings: AppSettings
    var instances: [GameInstance]
    var accounts: [MinecraftAccount]
    var activeAccountID: String?
    var selectedInstanceID: UUID?

    init(
        settings: AppSettings = AppSettings(),
        instances: [GameInstance] = [],
        accounts: [MinecraftAccount] = [],
        activeAccountID: String? = nil,
        selectedInstanceID: UUID? = nil
    ) {
        self.settings = settings
        self.instances = instances
        self.accounts = accounts
        self.activeAccountID = activeAccountID
        self.selectedInstanceID = selectedInstanceID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        instances = try container.decodeIfPresent([GameInstance].self, forKey: .instances) ?? []
        accounts = try container.decodeIfPresent([MinecraftAccount].self, forKey: .accounts) ?? []
        activeAccountID = try container.decodeIfPresent(String.self, forKey: .activeAccountID)
        selectedInstanceID = try container.decodeIfPresent(UUID.self, forKey: .selectedInstanceID)
    }
}

enum Persistence {
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func load() -> StoreFile {
        do {
            try AppPaths.ensureDirectories()
        } catch {
            NSLog("NeoCraft: could not create application support directories: \(error)")
            return StoreFile()
        }

        guard FileManager.default.fileExists(atPath: AppPaths.stateFile.path) else {
            return StoreFile()
        }

        do {
            let data = try Data(contentsOf: AppPaths.stateFile)
            return try makeDecoder().decode(StoreFile.self, from: data)
        } catch {
            NSLog("NeoCraft: state file could not be read, backing it up: \(error)")
            let backup = AppPaths.stateFile.deletingLastPathComponent()
                .appendingPathComponent("state.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: AppPaths.stateFile, to: backup)
            return StoreFile()
        }
    }

    static func save(_ store: StoreFile) throws {
        try AppPaths.ensureDirectories()
        let data = try makeEncoder().encode(store)
        let temporary = AppPaths.stateFile.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: AppPaths.stateFile.path) {
            _ = try FileManager.default.replaceItemAt(AppPaths.stateFile, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: AppPaths.stateFile)
        }
    }
}
