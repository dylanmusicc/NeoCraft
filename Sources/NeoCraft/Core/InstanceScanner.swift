import Foundation

enum InstanceScanner {
    static func scan(_ instance: GameInstance) -> InstanceStats {
        let gameDirectory = instance.gameDirectory
        var stats = InstanceStats()

        stats.modCount = countFiles(in: gameDirectory.appendingPathComponent("mods"), extension: "jar")
        stats.resourcePackCount = countFiles(in: gameDirectory.appendingPathComponent("resourcepacks"))
        stats.shaderPackCount = countFiles(in: gameDirectory.appendingPathComponent("shaderpacks"))
        stats.worldCount = countDirectories(in: gameDirectory.appendingPathComponent("saves"))
        stats.diskBytes = directorySize(instance.directory)
        stats.screenshots = screenshotURLs(in: gameDirectory, limit: 6)
        stats.gameInstalled = clientJarExists(for: instance)
        return stats
    }

    static func clientJarExists(for instance: GameInstance) -> Bool {
        let base = instance.minecraftVersion
        let jar = AppPaths.versions
            .appendingPathComponent(base, isDirectory: true)
            .appendingPathComponent("\(base).jar", isDirectory: false)
        return FileManager.default.fileExists(atPath: jar.path)
    }

    static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    private static func countFiles(in directory: URL, extension fileExtension: String? = nil) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        return entries.filter { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { return false }
            guard let fileExtension else { return true }
            return url.pathExtension.caseInsensitiveCompare(fileExtension) == .orderedSame
        }.count
    }

    private static func countDirectories(in directory: URL) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }.count
    }

    /// All screenshots in the instance, newest first. `limit` caps the result
    /// (used for lightweight stats); pass `nil` for the full gallery.
    static func screenshotURLs(in gameDirectory: URL, limit: Int? = nil) -> [URL] {
        let directory = gameDirectory.appendingPathComponent("screenshots", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let sorted = entries
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return left > right
            }
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }
}
