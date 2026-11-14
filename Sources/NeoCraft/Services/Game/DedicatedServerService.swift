import Foundation

enum DedicatedServerError: LocalizedError, Sendable {
    case missingServerJar(String)
    case missingWorld(String)
    case notPrepared(String)
    case alreadyRunning(String)
    case wrongEdition

    var errorDescription: String? {
        switch self {
        case .missingServerJar(let version):
            return "Mojang does not publish a dedicated server for Minecraft \(version)."
        case .missingWorld(let name):
            return "The world \"\(name)\" could not be found in the instance's saves folder."
        case .notPrepared(let name):
            return "\"\(name)\" is not fully set up yet — finish creating it first."
        case .alreadyRunning(let name):
            return "The server \"\(name)\" is already running."
        case .wrongEdition:
            return "This server isn't a Java dedicated server."
        }
    }
}

/// Runs Minecraft Java dedicated servers for hosted single-player worlds.
/// Each server is a self-contained folder under `AppPaths.servers` with the
/// official `server.jar`, an accepted `eula.txt`, a managed `server.properties`
/// and a copy of the world. Processes are tracked per server id so several
/// worlds can be hosted at once.
actor DedicatedServerService {
    private let versions: VersionService
    private let fabric: FabricService
    private var processes: [UUID: GameProcess] = [:]
    /// Invoked (on this actor) after a server process exits.
    private var onExit: (@Sendable (UUID, Int32) -> Void)?

    init(versions: VersionService, fabric: FabricService) {
        self.versions = versions
        self.fabric = fabric
    }

    func setExitHandler(_ handler: @escaping @Sendable (UUID, Int32) -> Void) {
        onExit = handler
    }

    func isRunning(_ id: UUID) -> Bool {
        processes[id] != nil
    }

    // MARK: - Setup

    /// Downloads the server software for the server's type (vanilla
    /// `server.jar`, Paper's paperclip or a scaffolded Fabric server),
    /// copies the save into the server folder when one was chosen and
    /// writes eula/properties. `instance` is nil for standalone servers —
    /// they always boot a fresh world. The whole folder is removed again
    /// when any step fails.
    func create(
        server: HostedServer,
        instance: GameInstance?,
        java: JavaRuntime,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws {
        let fileManager = FileManager.default
        guard server.edition == .java else {
            throw DedicatedServerError.wrongEdition
        }
        try AppPaths.ensureDirectories()
        try fileManager.createDirectory(at: server.directory, withIntermediateDirectories: true)

        do {
            progress(ProgressUpdate(fraction: 0.02, detail: "Resolving Minecraft \(server.minecraftVersion)…"))
            try await installSoftware(for: server, java: java, progress: progress)

            if !server.sourceWorldName.isEmpty, let instance {
                progress(ProgressUpdate(fraction: 0.7, detail: "Copying world \"\(server.sourceWorldName)\"…"))
                try await copyWorld(from: instance, server: server)
            } else {
                progress(ProgressUpdate(fraction: 0.7, detail: "The server generates its world on first start…"))
            }

            progress(ProgressUpdate(fraction: 0.9, detail: "Writing server configuration…"))
            try writeText("eula=true\n", to: server.directory.appendingPathComponent("eula.txt"))
            try writeServerProperties(for: server)
            try HostedServerStore.save(server)

            progress(ProgressUpdate(fraction: 1, detail: "Server is ready to start"))
        } catch {
            try? fileManager.removeItem(at: server.directory)
            throw error
        }
    }

    /// Downloads or scaffolds the software `server.serverType` needs inside
    /// the server folder.
    private func installSoftware(
        for server: HostedServer,
        java: JavaRuntime,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws {
        switch server.serverType {
        case .vanilla:
            let details = try await versions.details(for: server.minecraftVersion)
            guard let download = details.downloads?["server"],
                  let jarURL = URL(string: download.url) else {
                throw DedicatedServerError.missingServerJar(server.minecraftVersion)
            }
            progress(ProgressUpdate(fraction: 0.05, detail: "Downloading dedicated server…"))
            try await Downloader.download(DownloadRequest(
                url: jarURL,
                destination: server.serverJar,
                checksum: download.sha1.map { FileChecksum(algorithm: .sha1, value: $0) },
                expectedSize: download.size,
                label: "Minecraft \(server.minecraftVersion) server"
            )) { fraction in
                progress(ProgressUpdate(fraction: 0.05 + fraction * 0.6, detail: "Downloading dedicated server…"))
            }

        case .paper:
            progress(ProgressUpdate(fraction: 0.05, detail: "Resolving the latest Paper build…"))
            let build = try await PaperService.latestBuild(for: server.minecraftVersion)
            progress(ProgressUpdate(fraction: 0.15, detail: "Downloading Paper \(build.version) build \(build.build)…"))
            try await Downloader.download(DownloadRequest(
                url: build.url,
                destination: server.serverJar,
                label: "Paper \(build.version)-\(build.build)"
            )) { fraction in
                progress(ProgressUpdate(fraction: 0.15 + fraction * 0.6, detail: "Downloading Paper…"))
            }

        case .fabric:
            progress(ProgressUpdate(fraction: 0.05, detail: "Resolving Fabric loader…"))
            let loader = try await fabric.latestLoader(for: server.minecraftVersion)
            let installerVersion = try await FabricServerInstaller.latestInstallerVersion()
            let installerURL = try FabricServerInstaller.installerJarURL(version: installerVersion)
            let installerJar = server.directory.appendingPathComponent("fabric-installer.jar")
            progress(ProgressUpdate(fraction: 0.15, detail: "Downloading Fabric installer \(installerVersion)…"))
            try await Downloader.download(DownloadRequest(
                url: installerURL,
                destination: installerJar,
                label: "Fabric installer \(installerVersion)"
            )) { fraction in
                progress(ProgressUpdate(fraction: 0.15 + fraction * 0.4, detail: "Downloading Fabric installer…"))
            }
            progress(ProgressUpdate(fraction: 0.6, detail: "Scaffolding the Fabric server…"))
            _ = try await FabricServerInstaller.scaffold(
                directory: server.directory,
                minecraftVersion: server.minecraftVersion,
                loaderVersion: loader.version,
                java: java,
                installerJar: installerJar
            ) { text, level in
                // Installer output is verbose; only surface real problems.
                if level == .error {
                    FileHandle.standardError.write(Data(text.utf8))
                }
            }
            try? FileManager.default.removeItem(at: installerJar)
        }
    }

    /// Re-copies the single-player world over the hosted one. Only allowed
    /// while the server is stopped — the hosted copy may have diverged.
    func syncWorld(server: HostedServer, instance: GameInstance) async throws {
        guard processes[server.id] == nil else {
            throw DedicatedServerError.alreadyRunning(server.name)
        }
        try await copyWorld(from: instance, server: server)
    }

    // MARK: - Lifecycle

    /// Starts `java -jar server.jar nogui` inside the server directory.
    /// `log` receives merged stdout/stderr lines like the game launch does.
    @discardableResult
    func start(
        server: HostedServer,
        java: JavaRuntime,
        memoryMB: Int,
        minMemoryMB: Int,
        log: @escaping @Sendable (String, ConsoleLevel) -> Void
    ) async throws -> GameProcess {
        let fileManager = FileManager.default
        guard processes[server.id] == nil else {
            throw DedicatedServerError.alreadyRunning(server.name)
        }
        guard fileManager.fileExists(atPath: server.launchJar.path) else {
            throw DedicatedServerError.notPrepared(server.name)
        }
        // A server created without a world generates `level-name` on its
        // first boot — only hosted copies must already have level.dat.
        if !server.sourceWorldName.isEmpty {
            guard fileManager.fileExists(
                atPath: server.worldDirectory.appendingPathComponent("level.dat").path
            ) else {
                throw DedicatedServerError.missingWorld(server.worldName)
            }
        }

        var arguments = [
            "-Xms\(min(minMemoryMB, memoryMB))M",
            "-Xmx\(memoryMB)M",
            "-XX:+UseG1GC",
            "-XX:+ParallelRefProcEnabled",
            "-XX:MaxGCPauseMillis=100",
            "-XX:+DisableExplicitGC",
            "-XX:+AlwaysPreTouch",
            "-jar", server.launchJar.path,
            "nogui"
        ]
        if java.majorVersion >= 17 {
            arguments.insert(contentsOf: ["--add-exports", "java.base/jdk.internal.misc=ALL-UNNAMED"], at: 6)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["JAVA_HOME"] = java.homePath
        let javaBin = URL(fileURLWithPath: java.executablePath).deletingLastPathComponent().path
        environment["PATH"] = javaBin + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")

        let command = LaunchCommand(
            executable: URL(fileURLWithPath: java.executablePath),
            arguments: arguments,
            workingDirectory: server.directory,
            environment: environment
        )

        let process = GameProcess()
        do {
            try await process.start(command: command, log: log)
        } catch {
            throw error
        }
        processes[server.id] = process

        let serverID = server.id
        Task { [weak self] in
            let status = await process.waitForExit()
            await self?.handleExit(id: serverID, status: status)
        }
        return process
    }

    /// Sends `stop` so the server saves its world, then escalates to
    /// SIGTERM/SIGKILL through `GameProcess.terminate` if it hangs. Waits for
    /// the exit monitor to reap the process so callers can safely restart.
    func stop(_ id: UUID) async {
        guard let process = processes[id] else { return }
        await process.sendInput("stop")
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if await process.isRunning == false { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await process.terminate()
        // The monitor task removes the entry via handleExit — give it a
        // moment so `processes` reflects reality before we return.
        let reapDeadline = Date().addingTimeInterval(5)
        while processes[id] != nil, Date() < reapDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        processes[id] = nil
    }

    /// Runs a server console command (`say`, `list`, `op`, …) on a running
    /// server. No-op when the server isn't running under NeoCraft.
    func sendCommand(_ id: UUID, _ command: String) async {
        guard let process = processes[id] else { return }
        await process.sendInput(command)
    }

    /// Stops every hosted server — used on app termination so worlds flush.
    /// `stop` goes to all servers first, then stragglers are escalated.
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

    // MARK: - server.properties

    /// Current key/value pairs of the server's `server.properties`, decoded
    /// the way java.util.Properties reads them.
    func properties(for server: HostedServer) -> [String: String] {
        Self.parseProperties(
            at: server.directory.appendingPathComponent("server.properties")
        )
    }

    /// Synchronous `server.properties` parse — also used by the dashboard
    /// to seed its form on the first frame (and in offscreen renders where
    /// `.task` never runs).
    static func parseProperties(at url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let raw = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            values[key] = unescapePropertyValue(raw)
        }
        return values
    }

    /// Upserts keys in `server.properties`, preserving every other line.
    /// Only allowed while the server is stopped — a running server rewrites
    /// the file on shutdown and would drop live edits.
    func updateProperties(_ server: HostedServer, values: [String: String]) throws {
        guard processes[server.id] == nil else {
            throw DedicatedServerError.alreadyRunning(server.name)
        }
        let url = server.directory.appendingPathComponent("server.properties")
        var lines = propertyLines(at: url)
        for (key, value) in values {
            upsertProperty(key, value, in: &lines)
        }
        try writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    // MARK: - File browser

    /// Immediate children of a folder inside the server directory. Paths
    /// outside the server folder are rejected so the dashboard can never
    /// browse arbitrary locations.
    func files(in directory: URL, for server: HostedServer) throws -> [ServerFileEntry] {
        let root = server.directory.standardizedFileURL
        let target = directory.standardizedFileURL
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else {
            throw DedicatedServerError.notPrepared(server.name)
        }
        return Self.listFiles(at: target)
    }

    /// Synchronous directory listing shared by the actor method and the
    /// dashboard's first-frame seed.
    static func listFiles(at directory: URL) -> [ServerFileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return ServerFileEntry(
                name: url.lastPathComponent,
                url: url,
                isDirectory: values.isDirectory ?? false,
                size: values.isDirectory == true ? nil : values.fileSize.map(Int64.init),
                modified: values.contentModificationDate
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Reads a text file for the dashboard preview. Returns nil for binary
    /// files or files over ~512 KB; the cap keeps huge logs out of memory.
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

    /// Deletes a single file inside the server folder. Directories and
    /// core server files are refused — use the dashboard's delete-server
    /// flow for those.
    func deleteFile(_ url: URL, for server: HostedServer) throws {
        let root = server.directory.standardizedFileURL
        let target = url.standardizedFileURL
        guard target.path.hasPrefix(root.path + "/"),
              !target.path.hasSuffix("/"),
              FileManager.default.fileExists(atPath: target.path) else {
            throw DedicatedServerError.notPrepared(server.name)
        }
        let name = target.lastPathComponent
        let protected = [
            "server.jar", "fabric-server-launch.jar", "eula.txt", "server.properties",
            "neocraft-server.json", server.worldName, "backups", "plugins", "mods",
            "resourcepacks", "libraries", "versions", ".fabric"
        ]
        guard !protected.contains(name) else {
            throw DedicatedServerError.notPrepared("\(name) is managed by NeoCraft")
        }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
        guard !isDirectory.boolValue else {
            throw DedicatedServerError.notPrepared("Folders can't be deleted here")
        }
        try FileManager.default.removeItem(at: target)
    }

    // MARK: - Plugins & mods

    /// The folder the server software loads extensions from — `plugins/`
    /// for Paper, `mods/` for Fabric. Vanilla servers load neither.
    func extensionDirectory(for server: HostedServer) -> URL? {
        server.extensionDirectory
    }

    /// Files (and `.disabled` ones) inside the extension folder the
    /// server type accepts — jars for Paper/Fabric, zips for vanilla
    /// resource packs — for the dashboard's extension list.
    func extensions(for server: HostedServer) -> [ServerFileEntry] {
        guard let directory = server.extensionDirectory else { return [] }
        let suffixes = server.serverType.extensionSuffixes
        return Self.listFiles(at: directory).filter { entry in
            let name = entry.name.lowercased()
            let base = name.hasSuffix(".disabled") ? String(name.dropLast(".disabled".count)) : name
            return suffixes.contains { base.hasSuffix($0) }
        }
    }

    /// Downloads an extension file into the server's extension folder.
    /// `filename` comes from the source (Modrinth file name or the URL's
    /// last path component); its extension must be one the server type
    /// accepts (jars for Paper/Fabric, zips for vanilla packs).
    @discardableResult
    func installExtension(
        from url: URL,
        filename: String?,
        for server: HostedServer,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard let directory = server.extensionDirectory else {
            throw DedicatedServerError.notPrepared("\(server.name) takes no extensions")
        }
        let name = Self.sanitizeFileName(filename ?? url.lastPathComponent)
        let lower = name.lowercased()
        guard server.serverType.extensionSuffixes.contains(where: { lower.hasSuffix($0) }) else {
            let expected = server.serverType.extensionSuffixes.joined(separator: ", ")
            throw DedicatedServerError.notPrepared("Only \(expected) files can be installed on a \(server.serverType.title) server")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var destination = directory.appendingPathComponent(name)
        // Never silently overwrite an installed file — suffix instead.
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            destination = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        try await Downloader.download(DownloadRequest(
            url: url,
            destination: destination,
            label: name
        )) { fraction in
            progress(fraction)
        }
        return destination
    }

    /// Enables or disables an installed extension by renaming it to/from
    /// `.disabled` — the server software skips disabled files.
    func setExtensionEnabled(_ entry: ServerFileEntry, enabled: Bool, for server: HostedServer) throws {
        guard let directory = server.extensionDirectory,
              entry.url.deletingLastPathComponent().standardizedFileURL
                .path.hasPrefix(directory.standardizedFileURL.path) else {
            throw DedicatedServerError.notPrepared(server.name)
        }
        let name = entry.url.lastPathComponent
        let target: URL
        if enabled {
            guard name.hasSuffix(".disabled") else { return }
            target = entry.url.deletingLastPathComponent()
                .appendingPathComponent(String(name.dropLast(".disabled".count)))
        } else {
            guard !name.hasSuffix(".disabled") else { return }
            target = entry.url.appendingPathExtension("disabled")
        }
        try FileManager.default.moveItem(at: entry.url, to: target)
    }

    func deleteExtension(_ entry: ServerFileEntry, for server: HostedServer) throws {
        guard let directory = server.extensionDirectory,
              entry.url.deletingLastPathComponent().standardizedFileURL
                .path.hasPrefix(directory.standardizedFileURL.path) else {
            throw DedicatedServerError.notPrepared(server.name)
        }
        try FileManager.default.removeItem(at: entry.url)
    }

    private static func sanitizeFileName(_ raw: String) -> String {
        let last = raw.components(separatedBy: "/").last ?? raw
        let cleaned = last.replacingOccurrences(of: #"[^\w.\- ]"#, with: "_", options: .regularExpression)
        return cleaned.isEmpty ? "extension.bin" : cleaned
    }

    // MARK: - World backups

    /// Copies the hosted world into `backups/<timestamp>` inside the server
    /// folder. Requires the server to be stopped so region files aren't
    /// mid-write.
    @discardableResult
    func backupWorld(server: HostedServer) async throws -> URL {
        guard processes[server.id] == nil else {
            throw DedicatedServerError.alreadyRunning(server.name)
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: server.worldDirectory.appendingPathComponent("level.dat").path) else {
            throw DedicatedServerError.missingWorld(server.worldName)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let destination = server.backupsDirectory
            .appendingPathComponent("world-\(formatter.string(from: Date()))", isDirectory: true)
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: server.worldDirectory, to: destination)
            try? fm.removeItem(at: destination.appendingPathComponent("session.lock"))
        }.value
        return destination
    }

    /// Backup folders inside the server directory, newest first.
    func backups(for server: HostedServer) -> [URL] {
        Self.backupURLs(for: server)
    }

    /// Synchronous backup listing shared with the dashboard's first frame.
    static func backupURLs(for server: HostedServer) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: server.backupsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: Set(keys)).isDirectory) ?? false }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
    }

    /// Replaces the hosted world with a backup. Requires the server stopped.
    func restoreBackup(server: HostedServer, backup: URL) async throws {
        guard processes[server.id] == nil else {
            throw DedicatedServerError.alreadyRunning(server.name)
        }
        let fm = FileManager.default
        let backupsRoot = server.backupsDirectory.standardizedFileURL
        let source = backup.standardizedFileURL
        guard source.path.hasPrefix(backupsRoot.path + "/"),
              fm.fileExists(atPath: source.appendingPathComponent("level.dat").path) else {
            throw DedicatedServerError.missingWorld(backup.lastPathComponent)
        }
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            if fm.fileExists(atPath: server.worldDirectory.path) {
                try fm.removeItem(at: server.worldDirectory)
            }
            try fm.copyItem(at: source, to: server.worldDirectory)
            try? fm.removeItem(at: server.worldDirectory.appendingPathComponent("session.lock"))
        }.value
    }

    func deleteBackup(_ backup: URL, for server: HostedServer) throws {
        let backupsRoot = server.backupsDirectory.standardizedFileURL
        let target = backup.standardizedFileURL
        guard target.path.hasPrefix(backupsRoot.path + "/") else {
            throw DedicatedServerError.notPrepared(server.name)
        }
        try FileManager.default.removeItem(at: target)
    }

    // MARK: - Internals

    private func handleExit(id: UUID, status: Int32) {
        processes[id] = nil
        onExit?(id, status)
    }

    /// Copies `saves/<sourceWorldName>` into the server folder as
    /// `<worldName>`, dropping the single-player `session.lock`.
    private func copyWorld(from instance: GameInstance, server: HostedServer) async throws {
        let fileManager = FileManager.default
        let source = instance.gameDirectory
            .appendingPathComponent("saves", isDirectory: true)
            .appendingPathComponent(server.sourceWorldName, isDirectory: true)
        guard fileManager.fileExists(
            atPath: source.appendingPathComponent("level.dat").path
        ) else {
            throw DedicatedServerError.missingWorld(server.sourceWorldName)
        }

        let destination = server.worldDirectory
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fm.copyItem(at: source, to: destination)
            try? fm.removeItem(at: destination.appendingPathComponent("session.lock"))
        }.value
    }

    // MARK: - World export / import

    /// Zips the hosted world folder to `destination` (`.zip`). Uses
    /// `ditto` so macOS metadata and permissions survive the round trip.
    func exportWorldZip(server: HostedServer, to destination: URL) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: server.worldDirectory.appendingPathComponent("level.dat").path) else {
            throw DedicatedServerError.missingWorld(server.worldName)
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
                server.worldDirectory.path, destination.path,
            ]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw DedicatedServerError.notPrepared("Couldn't zip the world")
            }
        }.value
    }

    /// Replaces the hosted world with the world folder inside `archive`
    /// (a `.zip` produced by `exportWorldZip` or a manual zip). The
    /// previous world moves into `backups/` first. Requires the server
    /// stopped.
    func importWorldZip(server: HostedServer, from archive: URL) async throws {
        guard processes[server.id] == nil else {
            throw DedicatedServerError.alreadyRunning(server.name)
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
                throw DedicatedServerError.notPrepared("Couldn't unzip the world archive")
            }
        }.value
        // Find the folder holding level.dat (zip may nest it one level).
        var candidates = [staging]
        if let nested = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
            candidates += nested.filter { $0.hasDirectoryPath }
        }
        guard let world = candidates.first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("level.dat").path)
        }) else {
            throw DedicatedServerError.missingWorld("level.dat")
        }
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            // Park the current world in backups/ before replacing it.
            if fm.fileExists(atPath: server.worldDirectory.path) {
                let stamp = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                let parked = server.backupsDirectory
                    .appendingPathComponent("world-before-import-\(stamp)", isDirectory: true)
                try fm.createDirectory(at: server.backupsDirectory, withIntermediateDirectories: true)
                try fm.moveItem(at: server.worldDirectory, to: parked)
            }
            try fm.createDirectory(at: server.directory, withIntermediateDirectories: true)
            try fm.copyItem(at: world, to: server.worldDirectory)
        }.value
    }

    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Writes the managed keys into server.properties, preserving any other
    /// lines a user (or a previous server run) already added.
    private func writeServerProperties(for server: HostedServer) throws {
        let url = server.directory.appendingPathComponent("server.properties")
        var lines = propertyLines(at: url)
        upsertProperty("motd", server.name, in: &lines)
        upsertProperty("server-port", "\(server.port)", in: &lines)
        upsertProperty("online-mode", server.onlineMode ? "true" : "false", in: &lines)
        upsertProperty("level-name", server.worldName, in: &lines)
        // Creation preset on top of the managed keys.
        if let preset = ServerPreset(rawValue: server.preset) {
            for (key, value) in preset.properties {
                upsertProperty(key, value, in: &lines)
            }
        }
        try writeText(lines.joined(separator: "\n") + "\n", to: url)
    }

    private func propertyLines(at url: URL) -> [String] {
        if let existing = try? String(contentsOf: url, encoding: .utf8), !existing.isEmpty {
            return existing.components(separatedBy: .newlines)
        }
        return ["#Minecraft server properties", "#Generated by NeoCraft"]
    }

    private func upsertProperty(_ key: String, _ value: String, in lines: inout [String]) {
        let prefix = "\(key)="
        let escaped = escapePropertyValue(value)
        if let index = lines.firstIndex(where: { $0.hasPrefix(prefix) }) {
            lines[index] = "\(key)=\(escaped)"
        } else {
            lines.append("\(key)=\(escaped)")
        }
    }

    /// Reverses `escapePropertyValue` for the dashboard's property editor.
    private static func unescapePropertyValue(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            switch next {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "\\": result.append("\\")
            case "u":
                var hex = ""
                for _ in 0..<4 {
                    if let digit = iterator.next() { hex.append(digit) }
                }
                if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                    result.unicodeScalars.append(scalar)
                } else {
                    result += "\\u" + hex
                }
            default:
                result.append(next)
            }
        }
        return result
    }

    /// java.util.Properties reads ISO-8859-1 by default, so non-ASCII and
    /// backslashes must be \uXXXX-escaped to survive a round trip.
    private func escapePropertyValue(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\":
                result += "\\\\"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value > 0x7E {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}
