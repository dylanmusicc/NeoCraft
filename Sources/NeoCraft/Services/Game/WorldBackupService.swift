import Foundation

/// A single world inside an instance's `saves/` folder.
struct WorldInfo: Identifiable, Sendable {
    var id: String { directory.lastPathComponent }
    var directory: URL
    var name: String
    var levelName: String?
    /// Parsed from `level.dat` via the native NBT reader.
    var metadata: WorldMetadata?
    var sizeBytes: Int64
    var lastPlayed: Date?

    var seed: Int64? { metadata?.seed }
    var spawnX: Int? { metadata?.spawnX }
    var spawnY: Int? { metadata?.spawnY }
    var spawnZ: Int? { metadata?.spawnZ }
    var gameType: String? { metadata?.gameType }
}

/// Lists worlds and writes compressed `.zip` backups, either to
/// `~/Documents/NeoCraft Backups` or iCloud Drive.
enum WorldBackupService {
    /// Where backups land. iCloud Drive path is used when the setting is on;
    /// the directory is created on demand.
    static func backupDirectory(useiCloud: Bool) -> URL {
        if useiCloud {
            let cloud = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            if FileManager.default.fileExists(atPath: cloud.path) {
                return cloud.appendingPathComponent("NeoCraft Backups", isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/NeoCraft Backups", isDirectory: true)
    }

    /// All worlds in the instance, newest first.
    static func worlds(in instance: GameInstance) -> [WorldInfo] {
        let saves = instance.gameDirectory.appendingPathComponent("saves", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: saves,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            guard isDirectory,
                  FileManager.default.fileExists(
                      atPath: url.appendingPathComponent("level.dat").path
                  ) else { return nil }

            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let metadata = WorldDataService.metadata(worldDirectory: url)
            return WorldInfo(
                directory: url,
                name: url.lastPathComponent,
                levelName: metadata?.levelName ?? url.lastPathComponent,
                metadata: metadata,
                sizeBytes: InstanceScanner.directorySize(url),
                lastPlayed: modified
            )
        }
        .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    /// Zips one world into the backup directory. Returns the archive URL.
    @discardableResult
    static func backup(_ world: WorldInfo, instance: GameInstance, useiCloud: Bool) throws -> URL {
        let destination = try backupDestination(instance: instance, world: world, useiCloud: useiCloud)
        try zip(world.directory, to: destination)
        return destination
    }

    /// Zips every world of the instance; returns the created archives.
    @discardableResult
    static func backupAll(_ instance: GameInstance, useiCloud: Bool) throws -> [URL] {
        var created: [URL] = []
        for world in worlds(in: instance) {
            created.append(try backup(world, instance: instance, useiCloud: useiCloud))
        }
        return created
    }

    /// Existing backups for this instance, newest first.
    static func existingBackups(instance: GameInstance, useiCloud: Bool) -> [URL] {
        let directory = backupDirectory(useiCloud: useiCloud)
        let prefix = "\(instance.name)-"
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { $0.pathExtension == "zip" && $0.deletingPathExtension().lastPathComponent.hasPrefix(prefix) }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l > r
            }
    }

    // MARK: - Internals

    private static func backupDestination(instance: GameInstance, world: WorldInfo, useiCloud: Bool) throws -> URL {
        let directory = backupDirectory(useiCloud: useiCloud)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let safeInstance = instance.name.replacingOccurrences(of: "/", with: "-")
        let safeWorld = world.name.replacingOccurrences(of: "/", with: "-")
        return directory.appendingPathComponent("\(safeInstance)-\(safeWorld)-\(stamp).zip")
    }

    private static func zip(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = [
            "-r", "-q", "-X",
            destination.path,
            source.lastPathComponent
        ]
        process.currentDirectoryURL = source.deletingLastPathComponent()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppError.backupFailed("zip exited with status \(process.terminationStatus)")
        }
    }
}
