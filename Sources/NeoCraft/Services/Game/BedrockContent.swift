import Foundation

/// Read-only view into NeoCraft Bedrock's Wine prefixes: the worlds,
/// screenshots and packs the Bedrock game wrote under
/// `~/Library/Application Support/NeoCraft Bedrock/prefixes/`. The main app
/// and the launcher share the same folders, so listing them here *is* the
/// synchronization — edits in either app are visible to both.
enum BedrockContent {

    struct World: Identifiable, Hashable, Sendable {
        var id: URL { folder }
        let name: String
        let folder: URL
        let modified: Date?
        /// "Minecraft Bedrock" or "Minecraft Bedrock Preview".
        let product: String
    }

    struct Pack: Identifiable, Hashable, Sendable {
        var id: URL { folder }
        let name: String
        let kind: String
        let version: String
        let icon: URL?
        let folder: URL
    }

    struct ScreenshotGroup: Identifiable, Hashable, Sendable {
        var id: String { title }
        let title: String
        let urls: [URL]
    }

    struct Snapshot: Sendable {
        var worlds: [World] = []
        var packs: [Pack] = []
        var screenshots: [ScreenshotGroup] = []

        var isEmpty: Bool { worlds.isEmpty && packs.isEmpty && screenshots.isEmpty }
    }

    /// `~/Library/Application Support/NeoCraft Bedrock` — same root
    /// LauncherCore's `DataDirectory` uses (with the legacy
    /// `SiliconBedrock` fallback).
    static var dataRoot: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = support.appendingPathComponent("NeoCraft Bedrock", isDirectory: true)
        let legacy = support.appendingPathComponent("SiliconBedrock", isDirectory: true)
        if !FileManager.default.fileExists(atPath: root.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }
        return root
    }

    /// Scans every account prefix for both products (release + preview).
    /// Cheap enough to run on appear/refresh — directory listings only.
    static func snapshot() -> Snapshot {
        var result = Snapshot()
        let prefixes = dataRoot.appendingPathComponent("prefixes", isDirectory: true)
        guard let accounts = try? FileManager.default.contentsOfDirectory(
            at: prefixes, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return result }

        let products: [(folder: String, title: String)] = [
            ("Minecraft Bedrock", "Bedrock"),
            ("Minecraft Bedrock Preview", "Bedrock Preview"),
        ]
        // Wine runs the game as the macOS user inside the prefix.
        let wineUser = NSUserName()

        for account in accounts {
            for product in products {
                let gameData = account
                    .appendingPathComponent("drive_c/users/\(wineUser)/AppData/Roaming/\(product.folder)", isDirectory: true)
                guard FileManager.default.fileExists(atPath: gameData.path) else { continue }
                collectWorlds(in: gameData, product: product.title, into: &result)
                collectScreenshots(in: gameData, product: product.title, into: &result)
            }
            collectPacks(in: account, into: &result)
        }
        return result
    }

    // MARK: - Worlds

    /// `<gameData>/Users/<name>/games/com.mojang/minecraftWorlds/<id>` —
    /// the display name lives in `levelname.txt` inside each world.
    private static func collectWorlds(in gameData: URL, product: String, into result: inout Snapshot) {
        let users = gameData.appendingPathComponent("Users", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: users.path) else { return }
        for name in names where name != "Shared" && !name.hasPrefix(".") {
            let worlds = users
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("games/com.mojang/minecraftWorlds", isDirectory: true)
            guard let folders = try? FileManager.default.contentsOfDirectory(
                at: worlds, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for folder in folders {
                let isDir = (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                guard isDir,
                      FileManager.default.fileExists(atPath: folder.appendingPathComponent("level.dat").path)
                else { continue }
                let levelName = (try? String(
                    contentsOf: folder.appendingPathComponent("levelname.txt"), encoding: .utf8
                ))?.trimmingCharacters(in: .whitespacesAndNewlines)
                let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                result.worlds.append(World(
                    name: levelName?.isEmpty == false ? levelName! : folder.lastPathComponent,
                    folder: folder,
                    modified: modified,
                    product: product
                ))
            }
        }
        result.worlds.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    // MARK: - Screenshots

    /// `<gameData>/Users/<name>/games/com.mojang/Screenshots/*.png`.
    private static func collectScreenshots(in gameData: URL, product: String, into result: inout Snapshot) {
        let users = gameData.appendingPathComponent("Users", isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: users.path) else { return }
        for name in names where name != "Shared" && !name.hasPrefix(".") {
            let folder = users
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("games/com.mojang/Screenshots", isDirectory: true)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            let urls = files.filter { $0.pathExtension.lowercased() == "png" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            if !urls.isEmpty {
                result.screenshots.append(ScreenshotGroup(title: product, urls: urls))
            }
        }
    }

    // MARK: - Packs

    /// `<gameData>/Users/Shared/games/com.mojang/{resource,behavior,skin}_packs/*`
    /// for each product — read name/version/icon from `manifest.json`.
    private static func collectPacks(in account: URL, into result: inout Snapshot) {
        for product in ["Minecraft Bedrock", "Minecraft Bedrock Preview"] {
            let shared = account
                .appendingPathComponent("drive_c/users/\(NSUserName())/AppData/Roaming/\(product)/Users/Shared/games/com.mojang", isDirectory: true)
            guard FileManager.default.fileExists(atPath: shared.path) else { continue }
            let kinds: [(folder: String, title: String)] = [
                ("resource_packs", "Resource Pack"),
                ("behavior_packs", "Behavior Pack"),
                ("skin_packs", "Skin Pack"),
            ]
            for kind in kinds {
                let folder = shared.appendingPathComponent(kind.folder, isDirectory: true)
                guard let packs = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                ) else { continue }
                for packFolder in packs {
                    let manifest = packFolder.appendingPathComponent("manifest.json")
                    guard FileManager.default.fileExists(atPath: manifest.path),
                          let data = try? Data(contentsOf: manifest),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let header = json["header"] as? [String: Any] else { continue }
                    let name = header["name"] as? String ?? packFolder.lastPathComponent
                    let version = (header["version"] as? [String: Any])
                        .map { "\($0["major"] as? Int ?? 0).\($0["minor"] as? Int ?? 0).\($0["patch"] as? Int ?? 0)" }
                        ?? ""
                    let icon = packFolder.appendingPathComponent("pack_icon.png")
                    result.packs.append(Pack(
                        name: name,
                        kind: kind.title,
                        version: version,
                        icon: FileManager.default.fileExists(atPath: icon.path) ? icon : nil,
                        folder: packFolder
                    ))
                }
            }
        }
        result.packs.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
