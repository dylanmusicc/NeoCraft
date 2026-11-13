import Darwin
import Foundation

/// A single-player world packaged as a Minecraft Java dedicated server.
/// Each hosted server lives in its own folder under `AppPaths.servers`
/// (`server.jar`, `eula.txt`, `server.properties`, the copied world and a
/// `neocraft-server.json` metadata file that makes the folder self-describing).
struct HostedServer: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Display name — used for the motd and the launcher UI.
    var name: String
    /// Instance the world was taken from; used for Java/memory preferences
    /// and to re-sync the world later. May reference a deleted instance.
    var instanceID: UUID
    var instanceName: String
    var minecraftVersion: String
    /// Folder name of the world inside the server directory (`level-name`).
    var worldName: String
    /// Folder name of the world inside the instance's `saves/` directory.
    var sourceWorldName: String
    var port: Int
    var onlineMode: Bool
    /// Start this server automatically when NeoCraft launches.
    var autoStart: Bool
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
        name: String,
        instanceID: UUID,
        instanceName: String,
        minecraftVersion: String,
        worldName: String,
        sourceWorldName: String,
        port: Int = 25565,
        onlineMode: Bool = true,
        autoStart: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.instanceID = instanceID
        self.instanceName = instanceName
        self.minecraftVersion = minecraftVersion
        self.worldName = worldName
        self.sourceWorldName = sourceWorldName
        self.port = port
        self.onlineMode = onlineMode
        self.autoStart = autoStart
        self.createdAt = createdAt
    }

    /// Tolerant decoding: metadata written before `autoStart` existed (and
    /// any future field) must still load.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        instanceID = try container.decode(UUID.self, forKey: .instanceID)
        instanceName = try container.decode(String.self, forKey: .instanceName)
        minecraftVersion = try container.decode(String.self, forKey: .minecraftVersion)
        worldName = try container.decode(String.self, forKey: .worldName)
        sourceWorldName = try container.decode(String.self, forKey: .sourceWorldName)
        port = try container.decode(Int.self, forKey: .port)
        onlineMode = try container.decode(Bool.self, forKey: .onlineMode)
        autoStart = try container.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
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
