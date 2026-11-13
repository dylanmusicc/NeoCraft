import Foundation

// MARK: - servers.dat editor

/// One entry in a Minecraft `servers.dat`.
struct MCServerEntry: Identifiable, Sendable {
    var id = UUID()
    var name: String
    var address: String
    /// Base64-encoded PNG favicon stored in the `icon` field (no
    /// `data:` prefix — Minecraft stores the raw base64 payload).
    /// `nil`/empty means "no favicon".
    var icon: String? = nil
    /// Extra fields preserved verbatim from the original compound
    /// (e.g. `acceptTransfers`) so round-trips don't lose data.
    var extra: [String: NBTValue] = [:]
}

/// Reads and writes the gzipped-NBT `servers.dat` inside an instance's
/// game directory (`<instance>/minecraft/servers.dat`) — the file the
/// game itself reads on launch because its working directory is the
/// instance's `minecraft` folder.
enum ServerListService {

    static func fileURL(for instance: GameInstance) -> URL {
        instance.gameDirectory.appendingPathComponent("servers.dat")
    }

    /// Parses `servers.dat`. Returns [] when the file is absent or
    /// unreadable — a missing file simply means "no servers yet".
    /// Handles both gzipped and raw (uncompressed) NBT payloads.
    static func load(for instance: GameInstance) -> [MCServerEntry] {
        let url = fileURL(for: instance)
        guard let raw = try? Data(contentsOf: url), !raw.isEmpty else { return [] }
        let payload = GZip.decompress(raw) ?? raw
        guard let root = try? NBTReader.parse(payload),
              let servers = root[""]?.compoundValue?["servers"]?.listValue else { return [] }
        return servers.compactMap { item in
            guard let dict = item.compoundValue,
                  let name = dict["name"]?.stringValue,
                  let ip = dict["ip"]?.stringValue else { return nil }
            var extra = dict
            extra.removeValue(forKey: "name")
            extra.removeValue(forKey: "ip")
            let icon = dict["icon"]?.stringValue
            extra.removeValue(forKey: "icon")
            return MCServerEntry(
                name: name,
                address: ip,
                icon: (icon?.isEmpty == false) ? icon : nil,
                extra: extra
            )
        }
    }

    /// Atomically rewrites `servers.dat` with the given entries.
    static func save(_ entries: [MCServerEntry], for instance: GameInstance) throws {
        let compounds: [NBTValue] = entries.map { entry in
            var dict = entry.extra
            dict["name"] = .string(entry.name)
            dict["ip"] = .string(entry.address)
            // Minecraft expects an `icon` string (empty = no favicon)
            // and the `acceptTextures` byte for the resource-pack prompt.
            dict["icon"] = .string(entry.icon ?? "")
            dict["acceptTextures"] = dict["acceptTextures"] ?? .byte(1)
            dict["acceptTransfers"] = dict["acceptTransfers"] ?? .byte(1)
            return .compound(dict)
        }
        let root: NBTValue = .compound([
            "": .compound(["servers": .list(compounds)])
        ])
        // Root is an unnamed compound — exactly what serialize produces.
        let nbt = NBTWriter.serialize(rootName: "", root)
        guard let gzipped = GZip.compress(nbt) else {
            throw NSError(domain: "NeoCraft", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Gzip compression failed"])
        }
        let url = fileURL(for: instance)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try gzipped.write(to: url, options: .atomic)
    }
}
