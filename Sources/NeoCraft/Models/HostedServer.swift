import Darwin
import Foundation

/// Which game a hosted server runs.
enum ServerEdition: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case java
    case bedrock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .java: "Java Edition"
        case .bedrock: "Bedrock Edition"
        }
    }
}

/// The server software a Java hosted server runs. Paper loads Bukkit/
/// Spigot plugins, Fabric loads Fabric mods, and a vanilla server takes
/// resource packs only — Mojang's jar runs no code extensions.
enum ServerType: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case vanilla
    case paper
    case fabric

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vanilla: "Vanilla"
        case .paper: "Paper"
        case .fabric: "Fabric"
        }
    }

    var subtitle: String {
        switch self {
        case .vanilla: "Mojang's official server.jar — resource packs only."
        case .paper: "PaperMC — Bukkit/Spigot plugins from Modrinth or URLs."
        case .fabric: "Fabric loader — Fabric mods from Modrinth."
        }
    }

    /// What the dashboard calls the extension area for this type.
    var extensionTitle: String {
        switch self {
        case .vanilla: "Resource Packs"
        case .paper: "Plugins"
        case .fabric: "Mods"
        }
    }

    /// Singular noun for toasts ("Installed pack.zip").
    var extensionNoun: String {
        switch self {
        case .vanilla: "resource pack"
        case .paper: "plugin"
        case .fabric: "mod"
        }
    }

    /// Folder server software loads extensions from — `resourcepacks/`
    /// for vanilla (distributed to clients), `plugins/` for Paper,
    /// `mods/` for Fabric.
    var extensionDirectory: String? {
        switch self {
        case .vanilla: "resourcepacks"
        case .paper: "plugins"
        case .fabric: "mods"
        }
    }

    /// File extensions an installable extension may have. Vanilla packs
    /// are zips (`.mcpack`/`.jar` are zip containers too); plugins and
    /// mods are jars.
    var extensionSuffixes: [String] {
        switch self {
        case .vanilla: [".zip", ".mcpack", ".jar"]
        case .paper, .fabric: [".jar"]
        }
    }

    /// Jar the server starts with inside its folder.
    var launchJar: String {
        switch self {
        case .vanilla, .paper: "server.jar"
        case .fabric: "fabric-server-launch.jar"
        }
    }
}

/// A single-player world or a fresh map packaged as a Minecraft dedicated
/// server. Each hosted server lives in its own folder under
/// `AppPaths.servers` (`server.jar`, `eula.txt`, `server.properties`, the
/// copied world and a `neocraft-server.json` metadata file that makes the
/// folder self-describing). Bedrock servers hold Mojang's
/// `bedrock_server.exe` plus a `server.properties` and `worlds/` instead.
struct HostedServer: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Which game this server runs — Java dedicated or Bedrock dedicated.
    var edition: ServerEdition
    /// Java server software (vanilla/paper/fabric); ignored for Bedrock.
    var serverType: ServerType
    /// Display name — used for the motd and the launcher UI.
    var name: String
    /// Instance the world was taken from; used for Java/memory preferences
    /// and to re-sync the world later. May reference a deleted instance.
    /// Empty `sourceWorldName` means the server generates its own world.
    var instanceID: UUID
    var instanceName: String
    var minecraftVersion: String
    /// Folder name of the world inside the server directory (`level-name`).
    var worldName: String
    /// Folder name of the world inside the instance's `saves/` directory —
    /// empty when the server creates a fresh world on first boot.
    var sourceWorldName: String
    var port: Int
    var onlineMode: Bool
    /// Start this server automatically when NeoCraft launches.
    var autoStart: Bool
    /// Accent hex (no '#') tinting the server's row icon and dashboard —
    /// empty means the edition default.
    var colorHex: String
    /// Optional grouping label shown as a section header in the Servers
    /// tab ("Survival", "Minigames", …). Empty = ungrouped.
    var group: String
    /// `ServerPreset` raw value chosen at creation — the dashboard can
    /// re-apply it to `server.properties`.
    var preset: String
    var createdAt: Date

    var directory: URL { AppPaths.serverDirectory(id) }
    var serverJar: URL { directory.appendingPathComponent("server.jar") }
    var worldDirectory: URL { directory.appendingPathComponent(worldName, isDirectory: true) }
    /// The server's own rolling log (`logs/latest.log` inside the folder).
    var latestLog: URL {
        directory.appendingPathComponent("logs/latest.log", isDirectory: false)
    }
    /// Folder holding world snapshots created from the dashboard.
    var backupsDirectory: URL {
        directory.appendingPathComponent("backups", isDirectory: true)
    }

    init(
        id: UUID = UUID(),
        edition: ServerEdition = .java,
        serverType: ServerType = .vanilla,
        name: String,
        instanceID: UUID,
        instanceName: String,
        minecraftVersion: String,
        worldName: String,
        sourceWorldName: String,
        port: Int = 25565,
        onlineMode: Bool = true,
        autoStart: Bool = false,
        colorHex: String = "",
        group: String = "",
        preset: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.edition = edition
        self.serverType = serverType
        self.name = name
        self.instanceID = instanceID
        self.instanceName = instanceName
        self.minecraftVersion = minecraftVersion
        self.worldName = worldName
        self.sourceWorldName = sourceWorldName
        self.port = port
        self.onlineMode = onlineMode
        self.autoStart = autoStart
        self.colorHex = colorHex
        self.group = group
        self.preset = preset
        self.createdAt = createdAt
    }

    /// Tolerant decoding: metadata written before `edition`/`serverType`
    /// existed (and any future field) must still load.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        edition = try container.decodeIfPresent(ServerEdition.self, forKey: .edition) ?? .java
        serverType = try container.decodeIfPresent(ServerType.self, forKey: .serverType) ?? .vanilla
        name = try container.decode(String.self, forKey: .name)
        instanceID = try container.decode(UUID.self, forKey: .instanceID)
        instanceName = try container.decode(String.self, forKey: .instanceName)
        minecraftVersion = try container.decode(String.self, forKey: .minecraftVersion)
        worldName = try container.decode(String.self, forKey: .worldName)
        sourceWorldName = try container.decode(String.self, forKey: .sourceWorldName)
        port = try container.decode(Int.self, forKey: .port)
        onlineMode = try container.decode(Bool.self, forKey: .onlineMode)
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? ""
        preset = try container.decodeIfPresent(String.self, forKey: .preset) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// The jar/executable the server boots with inside its folder.
    var launchJar: URL { directory.appendingPathComponent(serverType.launchJar) }
    /// Folder server software loads plugins/mods from (nil for vanilla).
    var extensionDirectory: URL? {
        serverType.extensionDirectory.map {
            directory.appendingPathComponent($0, isDirectory: true)
        }
    }
    /// Whether the server still needs its software downloaded (Bedrock:
    /// `bedrock_server.exe`; Java: the type's launch jar).
    var isPrepared: Bool {
        FileManager.default.fileExists(
            atPath: (edition == .bedrock
                ? directory.appendingPathComponent("bedrock_server.exe")
                : launchJar).path
        )
    }
}

/// One row in the dashboard's server file browser.
struct ServerFileEntry: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let name: String
    let url: URL
    let isDirectory: Bool
    /// Byte size for files; `nil` for folders.
    let size: Int64?
    let modified: Date?
}

/// Filesystem-backed registry of hosted servers: each server folder carries
/// its own `neocraft-server.json`, so discovery is a directory scan and no
/// state.json migration is needed.
enum HostedServerStore {
    static let metadataFileName = "neocraft-server.json"

    static func metadataURL(for server: HostedServer) -> URL {
        server.directory.appendingPathComponent(metadataFileName, isDirectory: false)
    }

    /// All hosted servers found on disk, newest first.
    static func discover() -> [HostedServer] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: AppPaths.servers,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { directory in
            let metadata = directory.appendingPathComponent(metadataFileName, isDirectory: false)
            guard let data = try? Data(contentsOf: metadata),
                  let server = try? JSONDecoder().decode(HostedServer.self, from: data) else {
                return nil
            }
            return server
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ server: HostedServer) throws {
        try FileManager.default.createDirectory(at: server.directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(server)
        try data.write(to: metadataURL(for: server), options: .atomic)
    }

    /// Removes the whole server folder (jar, world, logs). Caller is
    /// responsible for stopping a running server first.
    static func delete(_ server: HostedServer) throws {
        if FileManager.default.fileExists(atPath: server.directory.path) {
            try FileManager.default.removeItem(at: server.directory)
        }
    }
}

/// Best-effort LAN IPv4 address for "join my server" hints. Prefers the
/// primary interface (en0); falls back to any non-loopback IPv4.
enum LANAddress {
    static var primaryIPv4: String? {
        var address: String?
        var fallback: String?

        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            let length = buffer.firstIndex(of: 0) ?? buffer.count
            let ip = String(decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard !ip.hasPrefix("127."), !ip.hasPrefix("169.254.") else { continue }
            if name == "en0" {
                address = ip
                break
            }
            if fallback == nil {
                fallback = ip
            }
        }
        return address ?? fallback
    }
}
