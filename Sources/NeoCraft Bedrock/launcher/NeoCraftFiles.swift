import Foundation

/// NeoCraft's own files, read (and for the Studio theme, written) so the Bedrock
/// component stays in step with the launcher that hosts it: the Studio theme in
/// `state.json` + the `neoCraft.theme.*` defaults, Java instances for the Servers
/// and Screenshots pages, and each instance's `servers.dat`.
enum NeoCraftFiles {
    /// `~/Library/Application Support/NeoCraft`.
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("NeoCraft", isDirectory: true)
    }

    static var stateFile: URL { support.appendingPathComponent("state.json") }

    /// A Java instance as NeoCraft's `state.json` records it — all the synced
    /// pages need is where its files live and what it is called.
    struct JavaInstance: Identifiable, Hashable {
        let id: UUID
        let name: String
        let minecraftVersion: String
        /// `instances/<id>/minecraft` — screenshots and servers.dat live here.
        let gameDirectory: URL

        var screenshots: URL { gameDirectory.appendingPathComponent("screenshots") }
        var serversDat: URL { gameDirectory.appendingPathComponent("servers.dat") }
    }

    /// Every Java instance in NeoCraft's state file, in file order.
    static func javaInstances() -> [JavaInstance] {
        guard let root = state(), let list = root["instances"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let raw = entry["id"] as? String, let id = UUID(uuidString: raw),
                entry["edition"] as? String != "bedrock"
            else { return nil }
            let name = entry["name"] as? String ?? id.uuidString
            let version = entry["minecraftVersion"] as? String ?? ""
            let game = support
                .appendingPathComponent("instances", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent("minecraft", isDirectory: true)
            return JavaInstance(id: id, name: name, minecraftVersion: version, gameDirectory: game)
        }
    }

    /// The `settings` object of NeoCraft's state file.
    static func settings() -> [String: Any] {
        (state()?["settings"] as? [String: Any]) ?? [:]
    }

    /// Whether NeoCraft's Bedrock beta flag is on — the Studio/Servers pages
    /// that mirror NeoCraft only exist as part of that beta track. Read from
    /// `state.json` (the flag isn't mirrored into the theme defaults), with a
    /// short cache so menus and sidebars don't re-parse the file per render.
    static func betaEnabled() -> Bool {
        betaLock.lock()
        defer { betaLock.unlock() }
        if let cached = betaBox.cache, Date().timeIntervalSince(cached.at) < 1 { return cached.value }
        let value = (settings()["betaFeatures"] as? [String: Any])?["bedrockEdition"] as? Bool ?? false
        betaBox.cache = (value, Date())
        return value
    }

    private static let betaLock = NSLock()
    private static let betaBox = BetaBox()

    private final class BetaBox: @unchecked Sendable {
        var cache: (value: Bool, at: Date)?
    }

    /// Writes theme keys into NeoCraft's state file and its `neoCraft.theme.*`
    /// defaults — the same two places `StudioTheme.sync` fills, so Neo Studio
    /// picks the change up on its next sync and this launcher sees it at once.
    /// `changes` maps AppSettings field names ("accentHex", "wallpaperStyle", …)
    /// to their raw values.
    static func applyTheme(_ changes: [String: Any]) {
        let defaults = UserDefaults(suiteName: "com.neocraft.launcher")
        for (key, value) in changes {
            switch key {
            case "accentHex": defaults?.set(value as? String ?? "", forKey: "neoCraft.theme.accentHex")
            case "secondaryGlowHex": defaults?.set(value as? String ?? "", forKey: "neoCraft.theme.glowHex")
            case "cardTintHex": defaults?.set(value as? String ?? "", forKey: "neoCraft.theme.cardTintHex")
            case "themeMode": defaults?.set(value as? String ?? "", forKey: "neoCraft.theme.mode")
            case "gridIntensity": defaults?.set(value as? Double ?? 1, forKey: "neoCraft.theme.gridIntensity")
            case "cornerStyle": defaults?.set(value as? String ?? "", forKey: "neoCraft.theme.cornerStyle")
            case "sidebarMaterial": defaults?.set(value as? Double ?? 0.5, forKey: "neoCraft.theme.sidebarMaterial")
            case "wallpaperStyle": defaults?.set(value as? String ?? "", forKey: "neoCraft.theme.wallpaperStyle")
            case "cornerRadiusPreset": defaults?.set(value as? String ?? "", forKey: "neoCraft.theme.cornerRadiusPreset")
            case "gradientHexes":
                defaults?.set((value as? [String] ?? []).joined(separator: ","), forKey: "neoCraft.theme.gradientHexes")
            default: break
            }
        }
        guard var root = state() else { return }
        var settingsObject = root["settings"] as? [String: Any] ?? [:]
        for (key, value) in changes { settingsObject[key] = value }
        root["settings"] = settingsObject
        if let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: stateFile, options: .atomic)
        }
    }

    /// One `servers.dat` entry: what the Servers page lists.
    struct ServerEntry: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let address: String
    }

    /// The servers of one NeoCraft instance, read straight from its
    /// `servers.dat` — Bedrock doesn't edit them, NeoCraft does.
    static func servers(of instance: JavaInstance) -> [ServerEntry] {
        guard let raw = try? Data(contentsOf: instance.serversDat), !raw.isEmpty else { return [] }
        let payload = GZip.decompress(raw) ?? raw
        guard let root = try? NBTReader.parse(payload),
            let servers = root[""]?.compoundValue?["servers"]?.listValue
        else { return [] }
        return servers.compactMap { item in
            guard let dict = item.compoundValue,
                let name = dict["name"]?.stringValue,
                let ip = dict["ip"]?.stringValue
            else { return nil }
            return ServerEntry(name: name, address: ip)
        }
    }

    private static func state() -> [String: Any]? {
        guard let data = try? Data(contentsOf: stateFile) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
