import Darwin
import Foundation

// MARK: - NeoCraft Bridge (in-game companion-mod IPC)

/// File-based IPC between the running NeoCraft app and the first-party
/// Fabric mods (`neocraft-host`, `neocraft-ui`).
///
/// While a Java instance runs, NeoCraft keeps a `neocraft_bridge/` folder
/// inside the instance's `config/` directory:
///
/// ```
/// config/neocraft_bridge/
/// ├── bridge.json          handshake written once at launch
/// ├── state.json           refreshed ~every 2 s (worlds + hosted servers)
/// ├── commands/<id>.json   request files dropped by the mods
/// └── responses/<id>.json  one response per request
/// ```
///
/// The mods poll `state.json` for live data and drop command files for
/// actions (host a world, start/stop/restart a server, run a console
/// command). Everything is plain JSON on disk — no sockets, no ports.
extension AppModel {

    // MARK: Bridge state

    /// Folder the running instance's mods read/write.
    private var bridgeDirectory: URL? { bridgeInstance.map(bridgeDir(for:)) }

    private func bridgeDir(for instance: GameInstance) -> URL {
        instance.gameDirectory
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("neocraft_bridge", isDirectory: true)
    }

    private func bridgeCommandsDir(_ dir: URL) -> URL {
        dir.appendingPathComponent("commands", isDirectory: true)
    }

    private func bridgeResponsesDir(_ dir: URL) -> URL {
        dir.appendingPathComponent("responses", isDirectory: true)
    }

    // MARK: Lifecycle

    /// Called right after the game process started. Only Java/Fabric
    /// instances can carry the companion mods — the bridge is still
    /// written for vanilla so a later-added mod can pick it up.
    func startNeoCraftBridge(for instance: GameInstance) {
        stopNeoCraftBridge()
        guard instance.edition == .java else { return }

        let dir = bridgeDir(for: instance)
        let commands = bridgeCommandsDir(dir)
        let responses = bridgeResponsesDir(dir)
        do {
            try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: responses, withIntermediateDirectories: true)
        } catch {
            appendConsole("NeoCraft bridge: couldn't create \(dir.path): \(error.localizedDescription)", level: .warning)
            return
        }

        bridgeInstance = instance
        writeBridgeHandshake(instance, in: dir)
        writeBridgeState(instance, in: dir)
        startBridgeWatcher(commandsDir: commands)
        startBridgeStateLoop()
        appendConsole("NeoCraft bridge online — in-game mods can reach the launcher", level: .info)
    }

    func stopNeoCraftBridge() {
        bridgeWatcherSource?.cancel()
        bridgeWatcherSource = nil
        bridgeStateTask?.cancel()
        bridgeStateTask = nil
        bridgeInstance = nil
        bridgeWorldsCache = nil
        bridgeWorldsCacheDate = nil
    }

    private func writeBridgeHandshake(_ instance: GameInstance, in dir: URL) {
        let payload: [String: Any] = [
            "format": "neocraft-bridge",
            "version": 1,
            "app": "NeoCraft",
            "appVersion": AppConstants.version,
            "instance": instance.name,
            "instanceId": instance.id.uuidString,
            "minecraftVersion": instance.minecraftVersion,
            "edition": instance.edition.rawValue,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("bridge.json"), options: .atomic)
        }
    }

    // MARK: State publishing

    /// Rewrites `state.json` — called every ~2 s while the game runs and
    /// once more right after every handled command.
    private func writeBridgeState(_ instance: GameInstance, in dir: URL? = nil) {
        let dir = dir ?? bridgeDir(for: instance)
        let payload = bridgeStatePayload(instance: instance)
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: dir.appendingPathComponent("state.json"), options: .atomic)
    }

    private func bridgeStatePayload(instance: GameInstance) -> [String: Any] {
        var payload: [String: Any] = [
            "format": "neocraft-bridge",
            "version": 1,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "gameRunning": isGameRunning,
            "instance": [
                "id": instance.id.uuidString,
                "name": instance.name,
                "minecraftVersion": instance.minecraftVersion,
                "loader": instance.loader.rawValue,
                "edition": instance.edition.rawValue,
            ],
        ]

        payload["worlds"] = bridgeWorlds(instance).map { world in
            [
                "name": world.name,
                "levelName": world.levelName ?? world.name,
                "lastPlayed": world.lastPlayed.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                "sizeBytes": world.sizeBytes,
            ]
        }

        payload["servers"] = hostedServers.map { server in
            [
                "id": server.id.uuidString,
                "name": server.name,
                "worldName": server.worldName,
                "sourceWorldName": server.sourceWorldName,
                "address": Self.serverAddress(server),
                "running": runningServerIDs.contains(server.id),
                "ready": readyServerIDs.contains(server.id),
                "settingUp": serverSetupIDs.contains(server.id),
                "port": server.port,
                "onlineMode": server.onlineMode,
                "instanceId": server.instanceID.uuidString,
                "instanceName": server.instanceName,
                "playersSeen": (serverPlayers[server.id] ?? []).count,
            ]
        }
        return payload
    }

    /// Worlds of the running instance, cached for a few seconds —
    /// `WorldBackupService.worlds` parses every `level.dat`, which is too
    /// heavy for a 2 s refresh loop.
    private func bridgeWorlds(_ instance: GameInstance) -> [WorldInfo] {
        let now = Date()
        if let cache = bridgeWorldsCache,
           let date = bridgeWorldsCacheDate,
           now.timeIntervalSince(date) < 10 {
            return cache
        }
        let worlds = WorldBackupService.worlds(in: instance)
        bridgeWorldsCache = worlds
        bridgeWorldsCacheDate = now
        return worlds
    }

    private func startBridgeStateLoop() {
        bridgeStateTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let instance = self.bridgeInstance else { return }
                self.writeBridgeState(instance)
            }
        }
    }

    // MARK: Command watcher

    private func startBridgeWatcher(commandsDir: URL) {
        let fd = open(commandsDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.bridgeCommandsDirectoryChanged(commandsDir)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        bridgeWatcherSource = source
    }

    private func bridgeCommandsDirectoryChanged(_ commandsDir: URL) {
        guard let dir = bridgeDirectory else { return }
        let responsesDir = bridgeResponsesDir(dir)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: commandsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files where file.pathExtension == "json" {
            handleBridgeRequest(file, commandsDir: commandsDir, responsesDir: responsesDir)
        }
    }

    private func handleBridgeRequest(_ file: URL, commandsDir: URL, responsesDir: URL) {
        defer { try? FileManager.default.removeItem(at: file) }
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let requestID = (object["id"] as? String) ?? file.deletingPathExtension().lastPathComponent
        let action = (object["action"] as? String ?? "").lowercased()
        let response = dispatchBridgeAction(action, params: object)
        var payload = response
        payload["id"] = requestID
        payload["format"] = "neocraft-bridge"
        payload["version"] = 1
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(
                to: responsesDir.appendingPathComponent("\(requestID).json"),
                options: .atomic
            )
        }
        if let instance = bridgeInstance {
            writeBridgeState(instance)
        }
    }

    /// Executes one bridge action. Always returns a response dictionary —
    /// errors come back as `{"ok": false, "error": "…"}` so the mod can
    /// surface them in-game instead of hanging.
    private func dispatchBridgeAction(_ action: String, params: [String: Any]) -> [String: Any] {
        switch action {
        case "ping", "state":
            guard let instance = bridgeInstance else {
                return ["ok": false, "error": "bridge offline"]
            }
            return ["ok": true, "state": bridgeStatePayload(instance: instance)]

        case "host":
            return bridgeHost(params: params)

        case "start", "stop", "restart":
            guard let server = bridgeServer(params: params) else {
                return ["ok": false, "error": "unknown or missing server id"]
            }
            switch action {
            case "start": startHostedServer(server)
            case "stop": stopHostedServer(server)
            default: restartHostedServer(server)
            }
            return ["ok": true, "server": server.name]

        case "command":
            guard let server = bridgeServer(params: params) else {
                return ["ok": false, "error": "unknown or missing server id"]
            }
            guard let command = params["command"] as? String,
                  !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return ["ok": false, "error": "missing command"]
            }
            sendServerCommand(server, command)
            return ["ok": true]

        default:
            return ["ok": false, "error": "unknown action '\(action)'"]
        }
    }

    private func bridgeServer(params: [String: Any]) -> HostedServer? {
        guard let raw = params["serverId"] as? String,
              let id = UUID(uuidString: raw) else { return nil }
        return hostedServers.first { $0.id == id }
    }

    /// `host` — packages a world of the running instance as a dedicated
    /// server. Params: `worldName` (folder name inside `saves/`),
    /// optional `name`, `port`, `onlineMode`.
    private func bridgeHost(params: [String: Any]) -> [String: Any] {
        guard let instance = bridgeInstance else {
            return ["ok": false, "error": "no running instance"]
        }
        guard let worldName = params["worldName"] as? String,
              !worldName.isEmpty else {
            return ["ok": false, "error": "missing worldName"]
        }
        let worlds = bridgeWorlds(instance)
        guard let world = worlds.first(where: {
            $0.name == worldName || $0.directory.lastPathComponent == worldName
        }) else {
            return ["ok": false, "error": "world '\(worldName)' not found in \(instance.name)"]
        }
        // One hosted server per world per instance — hosting the same
        // save twice would fork the world state.
        if hostedServers.contains(where: {
            $0.instanceID == instance.id && $0.sourceWorldName == world.name
        }) {
            return ["ok": false, "error": "world is already hosted"]
        }

        let name = (params["name"] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? (world.levelName ?? world.name)
        let port = (params["port"] as? Int).flatMap { (1...65535).contains($0) ? $0 : nil }
            ?? bridgeFirstFreePort()
        let onlineMode = (params["onlineMode"] as? Bool) ?? true

        hostWorld(world, in: instance, name: name, port: port, onlineMode: onlineMode)
        return ["ok": true, "server": name, "port": port]
    }

    /// First port ≥25565 not claimed by an existing hosted server.
    private func bridgeFirstFreePort() -> Int {
        let used = Set(hostedServers.map(\.port))
        var port = 25565
        while used.contains(port), port < 65535 { port += 1 }
        return port
    }
}
