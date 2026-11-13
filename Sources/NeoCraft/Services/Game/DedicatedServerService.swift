import Foundation

enum DedicatedServerError: LocalizedError, Sendable {
    case missingServerJar(String)
    case missingWorld(String)
    case notPrepared(String)
    case alreadyRunning(String)

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
    private var processes: [UUID: GameProcess] = [:]
    /// Invoked (on this actor) after a server process exits.
    private var onExit: (@Sendable (UUID, Int32) -> Void)?

    init(versions: VersionService) {
        self.versions = versions
    }

    func setExitHandler(_ handler: @escaping @Sendable (UUID, Int32) -> Void) {
        onExit = handler
    }

    func isRunning(_ id: UUID) -> Bool {
        processes[id] != nil
    }

    // MARK: - Setup

    /// Downloads the official server jar for the world's Minecraft version,
    /// copies the save into the server folder and writes eula/properties.
    /// The whole folder is removed again when any step fails.
    func create(
        server: HostedServer,
        instance: GameInstance,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws {
        let fileManager = FileManager.default
        try AppPaths.ensureDirectories()
        try fileManager.createDirectory(at: server.directory, withIntermediateDirectories: true)

        do {
            progress(ProgressUpdate(fraction: 0.02, detail: "Resolving Minecraft \(server.minecraftVersion)…"))
            let details = try await versions.details(for: server.minecraftVersion)
            guard let download = details.downloads?["server"],
                  let jarURL = URL(string: download.url) else {
                throw DedicatedServerError.missingServerJar(server.minecraftVersion)
            }

            progress(ProgressUpdate(fraction: 0.05, detail: "Downloading dedicated server…"))
            let jarRequest = DownloadRequest(
                url: jarURL,
                destination: server.serverJar,
                checksum: download.sha1.map { FileChecksum(algorithm: .sha1, value: $0) },
                expectedSize: download.size,
                label: "Minecraft \(server.minecraftVersion) server"
            )
            try await Downloader.download(jarRequest) { fraction in
                progress(ProgressUpdate(fraction: 0.05 + fraction * 0.55, detail: "Downloading dedicated server…"))
            }

            progress(ProgressUpdate(fraction: 0.62, detail: "Copying world \"\(server.sourceWorldName)\"…"))
            try await copyWorld(from: instance, server: server)

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
        guard processes[server.id] == nil else {
            throw DedicatedServerError.alreadyRunning(server.name)
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: server.serverJar.path) else {
            throw DedicatedServerError.notPrepared(server.name)
        }
        guard fileManager.fileExists(
            atPath: server.worldDirectory.appendingPathComponent("level.dat").path
        ) else {
            throw DedicatedServerError.missingWorld(server.worldName)
        }

        var arguments = [
            "-Xms\(min(minMemoryMB, memoryMB))M",
            "-Xmx\(memoryMB)M",
            "-XX:+UseG1GC",
            "-XX:+ParallelRefProcEnabled",
            "-XX:MaxGCPauseMillis=100",
            "-XX:+DisableExplicitGC",
            "-XX:+AlwaysPreTouch",
            "-jar", server.serverJar.path,
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
            "server.jar", "eula.txt", "server.properties", "neocraft-server.json",
            server.worldName, "backups"
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
