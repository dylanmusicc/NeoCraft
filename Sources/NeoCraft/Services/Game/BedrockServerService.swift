import Foundation

/// Mojang's Bedrock Dedicated Server downloads. The official links API
/// serves the current Windows build; pinned versions come from the
/// well-known `bedrockdedicatedserver/bin-win` URL pattern.
enum BedrockServerDownload {
    /// `serverBedrockWindows` / `serverBedrockPreviewWindows` link types.
    /// Primary: Mojang's minecraft-services API. Fallback: the community
    /// mirror of the same links, so a Mojang outage doesn't block setup.
    static func latestURL(preview: Bool = false) async throws -> URL {
        let wanted = preview ? "serverBedrockPreviewWindows" : "serverBedrockWindows"
        if let url = try? await apiLatestURL(wanted: wanted) {
            return url
        }
        return try await mirrorLatestURL(preview: preview)
    }

    private static func apiLatestURL(wanted: String) async throws -> URL {
        // net-secondary's v1.0 endpoint was sunset (HTTP 410); the primary
        // net.web host still serves the same API.
        let endpoint = try HTTPClient.url("https://net.web.minecraft-services.net/api/v1.0/download/links")
        var request = URLRequest(url: endpoint)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.transport("Couldn't reach Mojang's download service.")
        }
        struct Link: Decodable { let downloadType: String; let downloadUrl: String }
        struct Result: Decodable { let links: [Link] }
        struct Payload: Decodable { let result: Result }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let link = payload.result.links.first(where: { $0.downloadType == wanted }),
              let url = URL(string: link.downloadUrl) else {
            throw NetworkError.transport("Mojang didn't offer a Windows Bedrock server build.")
        }
        return url
    }

    /// kittizz/bedrock-server-downloads mirrors Mojang's links as JSON.
    private static func mirrorLatestURL(preview: Bool) async throws -> URL {
        let endpoint = try HTTPClient.url(
            "https://raw.githubusercontent.com/kittizz/bedrock-server-downloads/refs/heads/main/bedrock-server-downloads.json")
        var request = URLRequest(url: endpoint)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.transport("Couldn't reach the Bedrock server mirror.")
        }
        struct Entry: Decodable {
            struct Platform: Decodable { let url: String }
            let windows: Platform
        }
        let json = try JSONDecoder().decode([String: [String: Entry]].self, from: data)
        let track = preview ? "preview" : "release"
        guard let versions = json[track],
              let latest = versions.keys.sorted(by: { lhs, rhs in
                  lhs.compare(rhs, options: .numeric) == .orderedAscending
              }).last,
              let entry = versions[latest],
              let url = URL(string: entry.windows.url) else {
            throw NetworkError.transport("The Bedrock server mirror has no Windows build.")
        }
        return url
    }

    /// Direct zip URL for a pinned BDS version like `1.26.63.1`.
    static func url(forVersion version: String, preview: Bool = false) throws -> URL {
        // Mojang serves preview builds under bin-win-preview/.
        let folder = preview ? "bedrockdedicatedserver/bin-win-preview" : "bedrockdedicatedserver/bin-win"
        return try HTTPClient.url("https://www.minecraft.net/\(folder)/bedrock-server-\(version).zip")
    }

    /// BDS versions NeoCraft offers in the picker, newest first. "Latest"
    /// always tracks Mojang; this list covers pinned installs.
    static let knownVersions = [
        "1.26.63.1", "1.26.50.2", "1.26.44.1", "1.26.34.3", "1.26.30.2",
        "1.26.14.1", "1.21.130.3", "1.21.124.1", "1.21.111.1", "1.21.93.1",
    ]
}

enum BedrockServerError: LocalizedError, Sendable {
    case notPrepared(String)
    case alreadyRunning(String)
    case missingExecutable
    case helperMissing
    case engineMissing

    var errorDescription: String? {
        switch self {
        case .notPrepared(let name):
            return "\"\(name)\" isn't set up yet — finish creating it first."
        case .alreadyRunning(let name):
            return "The server \"\(name)\" is already running."
        case .missingExecutable:
            return "bedrock_server.exe is missing — recreate the server."
        case .helperMissing:
            return "This NeoCraft build doesn't include the Bedrock server runner — rebuild NeoCraft Bedrock first."
        case .engineMissing:
            return "No NeoCraft Bedrock engine is installed — open NeoCraft Bedrock once to finish setup."
        }
    }
}

/// Runs Minecraft Bedrock Dedicated Servers (`bedrock_server.exe`) under
/// the NeoCraft Bedrock component's Wine engine via the `bedrock-host`
/// helper. Mirrors `DedicatedServerService`'s lifecycle for the Bedrock
/// `server.properties` key set and the `worlds/` folder layout.
actor BedrockServerService {
    private var processes: [UUID: GameProcess] = [:]
    private var onExit: (@Sendable (UUID, Int32) -> Void)?

    func setExitHandler(_ handler: @escaping @Sendable (UUID, Int32) -> Void) {
        onExit = handler
    }

    func isRunning(_ id: UUID) -> Bool { processes[id] != nil }

    // MARK: - Setup

    /// Downloads the Windows BDS zip (latest or a pinned version),
    /// extracts it into the server folder and writes `server.properties`.
    /// The whole folder is removed again when any step fails.
    func create(
        server: HostedServer,
        preview: Bool,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws {
        var server = server // may be re-pinned when "latest" resolves to a version
        let fileManager = FileManager.default
        guard server.edition == .bedrock else {
            throw BedrockServerError.notPrepared(server.name)
        }
        try AppPaths.ensureDirectories()
        try fileManager.createDirectory(at: server.directory, withIntermediateDirectories: true)

        do {
            progress(ProgressUpdate(fraction: 0.05, detail: "Resolving Bedrock Dedicated Server…"))
            let zipURL: URL
            var resolvedVersion = server.minecraftVersion
            if resolvedVersion == "latest" || resolvedVersion.isEmpty {
                zipURL = try await BedrockServerDownload.latestURL(preview: preview)
                // bedrock-server-1.26.63.1.zip → 1.26.63.1
                if let name = zipURL.lastPathComponent
                    .split(separator: "-").dropFirst(2).first.map(String.init) {
                    resolvedVersion = name.replacingOccurrences(of: ".zip", with: "")
                }
            } else {
                zipURL = try BedrockServerDownload.url(forVersion: resolvedVersion, preview: preview)
            }
            if resolvedVersion != server.minecraftVersion {
                var updated = server
                updated.minecraftVersion = resolvedVersion
                server = updated
            }

            progress(ProgressUpdate(fraction: 0.15, detail: "Downloading Bedrock Dedicated Server \(resolvedVersion)…"))
            let zipFile = server.directory.appendingPathComponent("bedrock-server.zip")
            try await Downloader.download(DownloadRequest(
                url: zipURL,
                destination: zipFile,
                label: "Bedrock Dedicated Server \(resolvedVersion)"
            )) { fraction in
                progress(ProgressUpdate(fraction: 0.15 + fraction * 0.7, detail: "Downloading Bedrock Dedicated Server…"))
            }

            progress(ProgressUpdate(fraction: 0.88, detail: "Extracting server files…"))
            try await Self.extract(zipFile, into: server.directory)
            try? fileManager.removeItem(at: zipFile)

            progress(ProgressUpdate(fraction: 0.95, detail: "Writing server configuration…"))
            try writeProperties(for: server)
            // BDS refuses to boot without an accepted EULA.
            try Self.writeText("eula=true\n", to: server.directory.appendingPathComponent("eula.txt"))
            try HostedServerStore.save(server)

            progress(ProgressUpdate(fraction: 1, detail: "Server is ready to start"))
        } catch {
            try? fileManager.removeItem(at: server.directory)
            throw error
        }
    }

    /// `ditto -x -k` handles the zip's resource forks and permissions the
    /// way macOS archives expect; `unzip` is the fallback.
    private static func extract(_ zip: URL, into directory: URL) async throws {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, directory.path]
        try ditto.run()
        ditto.waitUntilExit()
        if ditto.terminationStatus == 0 { return }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", "-q", zip.path, "-d", directory.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw BedrockServerError.notPrepared("the server archive couldn't be extracted")
        }
    }

    /// Re-downloads the BDS zip and overlays the fresh server files onto
    /// the existing folder — `worlds/`, `server.properties`, `backups/`,
    /// `.wine` and NeoCraft metadata are preserved.
    func updateSoftware(
        server: HostedServer,
        zipURL: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        guard processes[server.id] == nil else {
            throw BedrockServerError.alreadyRunning(server.name)
        }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("neocraft-bds-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let zipFile = staging.appendingPathComponent("bedrock-server.zip")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        try await Downloader.download(DownloadRequest(
            url: zipURL, destination: zipFile, label: "Bedrock Dedicated Server"
        )) { fraction in progress(fraction * 0.8) }
        progress(0.85)
        try await Self.extract(zipFile, into: staging)

        // Overlay everything except NeoCraft-managed content.
        let protected: Set<String> = [
            "worlds", "backups", ".wine", "server.properties",
            "neocraft-server.json", "allowlist.json", "permissions.json",
        ]
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(
                at: staging, includingPropertiesForKeys: nil) else { return }
            for item in items where !protected.contains(item.lastPathComponent) {
                let destination = server.directory.appendingPathComponent(item.lastPathComponent)
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: item, to: destination)
            }
        }.value
        progress(1)
    }

    // MARK: - Lifecycle

    /// Runs `bedrock-host --data <launcher data> --dir <server folder>`,
    /// which drives `bedrock_server.exe` under Wine. `log` receives the
    /// server console like the Java service's.
    @discardableResult
    func start(
        server: HostedServer,
        helper: URL,
        dataDirectory: URL,
        log: @escaping @Sendable (String, ConsoleLevel) -> Void
    ) async throws -> GameProcess {
        guard processes[server.id] == nil else {
            throw BedrockServerError.alreadyRunning(server.name)
        }
        guard FileManager.default.fileExists(
            atPath: server.directory.appendingPathComponent("bedrock_server.exe").path
        ) else {
            throw BedrockServerError.missingExecutable
        }
        guard FileManager.default.fileExists(atPath: helper.path) else {
            throw BedrockServerError.helperMissing
        }

        let process = GameProcess()
        let command = LaunchCommand(
            executable: helper,
            arguments: [
                "--data", dataDirectory.path,
                "--dir", server.directory.path,
            ],
            workingDirectory: server.directory,
            environment: ProcessInfo.processInfo.environment
        )
        try await process.start(command: command, log: log)
        processes[server.id] = process

        let serverID = server.id
        Task { [weak self] in
            let status = await process.waitForExit()
            await self?.handleExit(id: serverID, status: status)
        }
        return process
    }

    /// Sends `stop` so the server saves its world, then escalates through
    /// `GameProcess.terminate` if it hangs.
    func stop(_ id: UUID) async {
        guard let process = processes[id] else { return }
        await process.sendInput("stop")
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if await process.isRunning == false { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await process.terminate()
        let reapDeadline = Date().addingTimeInterval(5)
        while processes[id] != nil, Date() < reapDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        processes[id] = nil
    }

    func sendCommand(_ id: UUID, _ command: String) async {
        guard let process = processes[id] else { return }
        await process.sendInput(command)
    }

    func terminateAll() async {
        for id in Array(processes.keys) {
            if let process = processes[id] {
                await process.sendInput("stop")
            }
        }
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !processes.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        for id in Array(processes.keys) {
            if let process = processes[id] {
                await process.terminate()
            }
            processes[id] = nil
        }
    }

    // MARK: - server.properties (BDS key set)

    /// Current key/value pairs of the server's `server.properties`.
    func properties(for server: HostedServer) -> [String: String] {
        DedicatedServerService.parseProperties(
            at: server.directory.appendingPathComponent("server.properties")
        )
    }

    /// Upserts keys in `server.properties`, preserving every other line.
    /// Only while stopped — a running BDS rewrites the file on shutdown.
    func updateProperties(_ server: HostedServer, values: [String: String]) throws {
        guard processes[server.id] == nil else {
            throw BedrockServerError.alreadyRunning(server.name)
        }
        let url = server.directory.appendingPathComponent("server.properties")
        var lines = Self.propertyLines(at: url)
        for (key, value) in values {
            Self.upsertProperty(key, value, in: &lines)
        }
        try Self.writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    private static func propertyLines(at url: URL) -> [String] {
        if let existing = try? String(contentsOf: url, encoding: .utf8), !existing.isEmpty {
            return existing.components(separatedBy: .newlines)
        }
        return ["#Minecraft Bedrock server properties", "#Generated by NeoCraft"]
    }

    private static func upsertProperty(_ key: String, _ value: String, in lines: inout [String]) {
        let prefix = "\(key)="
        if let index = lines.firstIndex(where: { $0.hasPrefix(prefix) }) {
            lines[index] = "\(key)=\(value)"
        } else {
            lines.append("\(key)=\(value)")
        }
    }

    private static func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The managed BDS keys written at creation; everything else keeps the
    /// defaults Mojang ships in the extracted properties file.
    private func writeProperties(for server: HostedServer) throws {
        let url = server.directory.appendingPathComponent("server.properties")
        var lines = Self.propertyLines(at: url)
        let managed: [(String, String)] = [
            ("server-name", server.name),
            ("server-port", "\(server.port)"),
            ("online-mode", server.onlineMode ? "true" : "false"),
            ("level-name", server.worldName),
        ]
        for (key, value) in managed {
            Self.upsertProperty(key, value, in: &lines)
        }
        if let preset = ServerPreset(rawValue: server.preset) {
            for (key, value) in preset.bedrockProperties {
                Self.upsertProperty(key, value, in: &lines)
            }
        }
        try Self.writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    // MARK: - File browser

    func files(in directory: URL, for server: HostedServer) throws -> [ServerFileEntry] {
        let root = server.directory.standardizedFileURL
        let target = directory.standardizedFileURL
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else {
            throw BedrockServerError.notPrepared(server.name)
        }
        return DedicatedServerService.listFiles(at: target)
    }

    func readTextFile(_ url: URL, for server: HostedServer) -> String? {
        let root = server.directory.standardizedFileURL
        let target = url.standardizedFileURL
        guard target.path == root.path || target.path.hasPrefix(root.path + "/"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: target.path),
              let size = attributes[.size] as? Int, size <= 512 * 1024,
              let data = try? Data(contentsOf: target),
              !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteFile(_ url: URL, for server: HostedServer) throws {
        let root = server.directory.standardizedFileURL
        let target = url.standardizedFileURL
        guard target.path.hasPrefix(root.path + "/"),
              !target.path.hasSuffix("/"),
              FileManager.default.fileExists(atPath: target.path) else {
            throw BedrockServerError.notPrepared(server.name)
        }
        let name = target.lastPathComponent
        let protected = [
            "bedrock_server.exe", "server.properties", "permissions.json",
            "allowlist.json", "neocraft-server.json", "worlds", "backups", ".wine"
        ]
        guard !protected.contains(name) else {
            throw BedrockServerError.notPrepared("\(name) is managed by NeoCraft")
        }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else {
            throw BedrockServerError.notPrepared("Folders can't be deleted here")
        }
        try FileManager.default.removeItem(at: target)
    }

    // MARK: - World backups (the whole `worlds/` folder)

    /// The folder BDS keeps its worlds in.
    static func worldsDirectory(for server: HostedServer) -> URL {
        server.directory.appendingPathComponent("worlds", isDirectory: true)
    }

    @discardableResult
    func backupWorld(server: HostedServer) async throws -> URL {
        guard processes[server.id] == nil else {
            throw BedrockServerError.alreadyRunning(server.name)
        }
        let worlds = Self.worldsDirectory(for: server)
        let fm = FileManager.default
        guard fm.fileExists(atPath: worlds.path) else {
            throw BedrockServerError.notPrepared("\(server.name) has no worlds yet")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let destination = server.backupsDirectory
            .appendingPathComponent("worlds-\(formatter.string(from: Date()))", isDirectory: true)
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: worlds, to: destination)
        }.value
        return destination
    }

    func backups(for server: HostedServer) -> [URL] {
        DedicatedServerService.backupURLs(for: server)
    }

    /// Replaces `worlds/` with a backup. Requires the server stopped.
    func restoreBackup(server: HostedServer, backup: URL) async throws {
        guard processes[server.id] == nil else {
            throw BedrockServerError.alreadyRunning(server.name)
        }
        let backupsRoot = server.backupsDirectory.standardizedFileURL
        let source = backup.standardizedFileURL
        guard source.path.hasPrefix(backupsRoot.path + "/") else {
            throw BedrockServerError.notPrepared(server.name)
        }
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let worlds = Self.worldsDirectory(for: server)
            if fm.fileExists(atPath: worlds.path) {
                try fm.removeItem(at: worlds)
            }
            try fm.copyItem(at: source, to: worlds)
        }.value
    }

    func deleteBackup(_ backup: URL, for server: HostedServer) throws {
        let backupsRoot = server.backupsDirectory.standardizedFileURL
        let target = backup.standardizedFileURL
        guard target.path.hasPrefix(backupsRoot.path + "/") else {
            throw BedrockServerError.notPrepared(server.name)
        }
        try FileManager.default.removeItem(at: target)
    }

    // MARK: - World export / import

    /// Zips the whole `worlds/` folder to `destination` (`.zip`).
    func exportWorldZip(server: HostedServer, to destination: URL) async throws {
        let fm = FileManager.default
        let worlds = Self.worldsDirectory(for: server)
        guard fm.fileExists(atPath: worlds.path) else {
            throw BedrockServerError.notPrepared("\(server.name) has no worlds yet")
        }
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-c", "-k", "--sequesterRsrc", "--keepParent",
                worlds.path, destination.path,
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw BedrockServerError.notPrepared("Couldn't zip the worlds")
            }
        }.value
    }

    /// Replaces `worlds/` with the contents of `archive`. The previous
    /// worlds move into `backups/` first. Requires the server stopped.
    func importWorldZip(server: HostedServer, from archive: URL) async throws {
        guard processes[server.id] == nil else {
            throw BedrockServerError.alreadyRunning(server.name)
        }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("neocraft-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", archive.path, staging.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                throw BedrockServerError.notPrepared("Couldn't unzip the worlds archive")
            }
        }.value
        // Accept either a `worlds/` folder or loose level folders inside.
        var source = staging
        if let nested = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil),
           nested.count == 1, nested[0].lastPathComponent == "worlds" {
            source = nested[0]
        }
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let worlds = Self.worldsDirectory(for: server)
            if fm.fileExists(atPath: worlds.path) {
                let stamp = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                let parked = server.backupsDirectory
                    .appendingPathComponent("worlds-before-import-\(stamp)", isDirectory: true)
                try fm.createDirectory(at: server.backupsDirectory, withIntermediateDirectories: true)
                try fm.moveItem(at: worlds, to: parked)
            }
            try fm.createDirectory(at: worlds.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: worlds)
        }.value
    }

    // MARK: - Internals

    private func handleExit(id: UUID, status: Int32) {
        processes[id] = nil
        onExit?(id, status)
    }
}
