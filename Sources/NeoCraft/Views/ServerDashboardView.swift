import AppKit
import SwiftUI

/// Full management console for one hosted dedicated server: live server
/// console with command input, player list, lifecycle controls, world
/// backups, a file browser for the server folder and the editable
/// `server.properties` surface. Rendered inside the Dashboard page — the
/// layout fills whatever space the detail column gives it.
struct ServerDashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Snapshot kept in sync with `model.hostedServers` so edits made in
    /// the settings card (e.g. port) are reflected while the view is open.
    @State private var server: HostedServer

    init(server: HostedServer) {
        _server = State(initialValue: server)
        // Seed from disk synchronously so the first frame — and offscreen
        // renders where `.task` never runs — already shows real values.
        let props = DedicatedServerService.parseProperties(
            at: server.directory.appendingPathComponent("server.properties")
        )
        _browserDirectory = State(initialValue: server.directory)
        _files = State(initialValue: DedicatedServerService.listFiles(at: server.directory))
        _backups = State(initialValue: DedicatedServerService.backupURLs(for: server))
        _motd = State(initialValue: props["motd"] ?? server.name)
        _portText = State(initialValue: props["server-port"] ?? "\(server.port)")
        _onlineMode = State(initialValue: props["online-mode"] != "false")
        _pvp = State(initialValue: props["pvp"] != "false")
        _whiteList = State(initialValue: props["white-list"] == "true")
        _allowFlight = State(initialValue: props["allow-flight"] == "true")
        _spawnProtection = State(initialValue: props["spawn-protection"] ?? "")
        _maxPlayers = State(initialValue: props["max-players"] ?? "")
        _viewDistance = State(initialValue: props["view-distance"] ?? "")
        _simulationDistance = State(initialValue: props["simulation-distance"] ?? "")
        _difficulty = State(initialValue: props["difficulty"] ?? "easy")
        _gamemode = State(initialValue: props["gamemode"] ?? "survival")
        _propertiesLoaded = State(initialValue: !props.isEmpty)
    }

    @State private var command = ""
    @State private var playersPing: ServerStatus?
    @State private var confirmDelete = false

    // File browser state
    @State private var browserDirectory: URL?
    @State private var files: [ServerFileEntry] = []
    @State private var preview: FilePreview?
    @State private var confirmDeleteFile: ServerFileEntry?

    // Backup state
    @State private var backups: [URL] = []
    @State private var confirmRestore: URL?
    @State private var confirmDeleteBackup: URL?

    // server.properties editor state
    @State private var motd = ""
    @State private var portText = ""
    @State private var onlineMode = true
    @State private var pvp = true
    @State private var whiteList = false
    @State private var allowFlight = false
    @State private var spawnProtection = ""
    @State private var maxPlayers = ""
    @State private var viewDistance = ""
    @State private var simulationDistance = ""
    @State private var difficulty = "easy"
    @State private var gamemode = "survival"
    @State private var propertiesLoaded = false

    private var running: Bool { model.isServerRunning(server) }
    private var ready: Bool { model.isServerReady(server) }
    private var settingUp: Bool { model.isSettingUpServer(server) }
    private var address: String { AppModel.serverAddress(server) }
    private var entries: [ConsoleEntry] { model.serverConsoles[server.id] ?? [] }
    private var players: [String] { model.serverPlayers[server.id] ?? [] }
    private var currentDirectory: URL { browserDirectory ?? server.directory }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        consoleCard
                        playersCard
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 14) {
                        actionsCard
                        backupsCard
                    }
                    .frame(maxWidth: .infinity)
                }
                HStack(alignment: .top, spacing: 14) {
                    filesCard
                        .frame(maxWidth: .infinity)
                    settingsCard
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            browserDirectory = server.directory
            await loadProperties()
            await reloadFiles()
            await reloadBackups()
            while !Task.isCancelled {
                if model.isServerRunning(server) {
                    let status = await ServerPinger.ping(address)
                    playersPing = status
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onChange(of: server.id) { _, _ in
            browserDirectory = server.directory
            Task {
                await reloadFiles()
                await reloadBackups()
            }
        }
        .onChange(of: model.hostedServers) { _, servers in
            if let updated = servers.first(where: { $0.id == server.id }) {
                server = updated
            }
        }
        .sheet(item: $preview) { preview in
            FilePreviewSheet(preview: preview, server: server)
                .environment(model)
        }
        .confirmationDialog(
            "Delete hosted server?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(server.name)", role: .destructive) {
                model.deleteHostedServer(server)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the server folder and its copy of the world. The original world in \(server.instanceName)'s saves is not affected.")
        }
        .confirmationDialog(
            "Delete this file?",
            isPresented: Binding(
                get: { confirmDeleteFile != nil },
                set: { if !$0 { confirmDeleteFile = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(confirmDeleteFile?.name ?? "file")", role: .destructive) {
                if let file = confirmDeleteFile {
                    model.deleteServerFile(file.url, for: server)
                }
                confirmDeleteFile = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteFile = nil }
        } message: {
            Text("This permanently deletes the file inside the server folder.")
        }
        .confirmationDialog(
            "Restore this world backup?",
            isPresented: Binding(
                get: { confirmRestore != nil },
                set: { if !$0 { confirmRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let backup = confirmRestore {
                    model.restoreServerBackup(server, backup: backup)
                }
                confirmRestore = nil
            }
            Button("Cancel", role: .cancel) { confirmRestore = nil }
        } message: {
            Text("The current hosted world will be replaced by the backup. The server must be stopped.")
        }
        .confirmationDialog(
            "Delete this backup?",
            isPresented: Binding(
                get: { confirmDeleteBackup != nil },
                set: { if !$0 { confirmDeleteBackup = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Backup", role: .destructive) {
                if let backup = confirmDeleteBackup {
                    model.deleteServerBackup(server, backup: backup)
                    Task { await reloadBackups() }
                }
                confirmDeleteBackup = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteBackup = nil }
        } message: {
            Text("This removes the backup folder inside the server directory.")
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        NeoCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(NeoPalette.accent.opacity(0.14))
                    Image(systemName: "server.rack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NeoPalette.accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(server.name).font(.neoTitle)
                        statusBadge
                        if server.autoStart {
                            NeoBadge(text: "Auto-start", color: NeoPalette.sky)
                        }
                    }
                    Text("\(server.worldName) · Minecraft \(server.minecraftVersion) · from \(server.instanceName)")
                        .font(.neoCaption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(address)
                            .font(.neoCaption.weight(.semibold).monospacedDigit())
                        Button {
                            model.copyServerAddress(server)
                        } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Copy server address")
                        if !server.onlineMode {
                            NeoBadge(text: "Online mode off", color: NeoPalette.amber)
                        }
                    }
                }

                Spacer()

                if let started = model.serverStartedAt[server.id] {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Formatters.duration(Date().timeIntervalSince(started)))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("uptime")
                            .font(.neoCaption).foregroundStyle(.secondary)
                    }
                }

                Button("Join") {
                    model.joinHostedServer(server)
                }
                .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                .disabled(!running || model.isGameRunning)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if settingUp {
            NeoBadge(text: "Setting up", color: NeoPalette.amber)
        } else if running {
            NeoBadge(text: ready ? "Online" : "Starting", color: ready ? NeoPalette.mint : NeoPalette.sky)
        } else {
            NeoBadge(text: "Stopped", color: Color.secondary)
        }
    }

    // MARK: - Console

    private var consoleCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Server Console", symbol: "terminal")
                    Spacer()
                    if running {
                        NeoPill(text: "Live", symbol: "dot.radiowaves.left.and.right", tint: NeoPalette.mint)
                    }
                    Button {
                        model.clearServerConsole(server)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                    .help("Clear console")
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            if entries.isEmpty {
                                Text(running
                                     ? "Waiting for server output…"
                                     : "Server is stopped — start it to see live output here.")
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color(hex: "6B7C99"))
                                    .padding(.vertical, 30)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(entries) { entry in
                                    consoleLine(entry)
                                        .id(entry.id)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 210)
                    .background(Color(hex: "080D17"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: entries.count) { _, _ in
                        if let last = entries.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Server command — try \"list\", \"say Hello\" or \"save-all\"", text: $command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit { sendCommand() }
                    Button("Send") { sendCommand() }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                        .disabled(!running || command.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Stop Server") {
                        model.stopHostedServer(server)
                    }
                    .buttonStyle(NeoButtonStyle(kind: .danger, compact: true))
                    .disabled(!running)
                    .help("Sends \"stop\" — the world is saved before exit")
                }
            }
        }
    }

    private func consoleLine(_ entry: ConsoleEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.date.formatted(date: .omitted, time: .standard))
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "536684"))
                .frame(width: 64, alignment: .leading)
            Text(entry.text)
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundStyle(entry.level == .error ? Color(hex: "FFB4B4") : Color(hex: "D5DFF0"))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1.5)
    }

    private func sendCommand() {
        model.sendServerCommand(server, command)
        command = ""
    }

    // MARK: - Players

    private var playersCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Players", symbol: "person.2.fill")
                if let ping = playersPing, ping.reachable {
                    HStack(spacing: 6) {
                        StatusDot(color: NeoPalette.mint, size: 6)
                        Text("\(ping.playersOnline)/\(ping.playersMax) online")
                            .font(.neoBody.weight(.semibold))
                    }
                } else {
                    Text(running ? "Pinging…" : "Server is offline")
                        .font(.neoCaption).foregroundStyle(.secondary)
                }
                if !players.isEmpty {
                    ForEach(players, id: \.self) { name in
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(NeoPalette.accent)
                            Text(name).font(.neoCaption.weight(.medium))
                            Spacer()
                            if running {
                                Button("Op") {
                                    model.sendServerCommand(server, "op \(name)")
                                }
                                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                                .help("Grant operator status")
                                Button("Kick") {
                                    model.sendServerCommand(server, "kick \(name)")
                                }
                                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                                .help("Kick player from the server")
                            }
                        }
                    }
                } else if running {
                    Text("No players seen in the console yet.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private var actionsCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Manage", symbol: "slider.horizontal.3")
                if running {
                    Button("Stop Server") { model.stopHostedServer(server) }
                        .buttonStyle(NeoButtonStyle(kind: .danger))
                    Button("Restart Server") { model.restartHostedServer(server) }
                        .buttonStyle(NeoButtonStyle(kind: .secondary))
                } else {
                    Button(settingUp ? "Setting up…" : "Start Server") {
                        model.startHostedServer(server)
                    }
                    .buttonStyle(NeoButtonStyle(kind: .primary))
                    .disabled(settingUp)
                }
                Button("Sync World from Instance") {
                    model.syncHostedServerWorld(server)
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary))
                .disabled(running || settingUp || model.instance(for: server.instanceID) == nil)
                .help(model.instance(for: server.instanceID) == nil
                      ? "The original instance was deleted"
                      : "Overwrite the hosted world with the current single-player save")
                Button("Open Server Folder") {
                    model.reveal(server.directory)
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary))
                Button("Open Log Folder") {
                    model.reveal(server.latestLog.deletingLastPathComponent())
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary))
                .help("Shows logs/latest.log in Finder")
                Toggle(isOn: Binding(
                    get: { server.autoStart },
                    set: { model.setServerAutoStart(server, $0) }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Start with NeoCraft")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                        Text("Boot this server automatically on launch.")
                            .font(.neoCaption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(NeoToggleStyle())
                Button("Delete Server…", role: .destructive) {
                    confirmDelete = true
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - World backups

    private var backupsCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "World Backups", symbol: "arrow.triangle.2.circlepath")
                    Spacer()
                    Button("Backup Now") {
                        model.backupServerWorld(server)
                        Task { try? await Task.sleep(for: .milliseconds(400)); await reloadBackups() }
                    }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    .disabled(running || settingUp)
                    .help("Snapshot the hosted world into backups/ — server must be stopped")
                }

                if backups.isEmpty {
                    Text("No backups yet. Create one before risky changes — restore replaces the whole world.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.self) { backup in
                        HStack(spacing: 8) {
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(NeoPalette.sky)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(backup.lastPathComponent)
                                    .font(.neoCaption.weight(.medium))
                                    .lineLimit(1)
                                if let modified = (try? backup.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                                    Text(modified.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Restore") { confirmRestore = backup }
                                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                                .disabled(running || settingUp)
                                .help("Replace the hosted world with this backup")
                            Button {
                                model.reveal(backup)
                            } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                            .help("Reveal in Finder")
                            Button {
                                confirmDeleteBackup = backup
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                            .help("Delete backup")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - File browser

    private var filesCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Server Files", symbol: "folder")
                    Spacer()
                    Button {
                        Task { await reloadFiles() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                    .help("Refresh")
                }

                // Breadcrumb-ish path
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(currentDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    if currentDirectory != server.directory {
                        Button("Up") {
                            browserDirectory = currentDirectory.deletingLastPathComponent()
                            Task { await reloadFiles() }
                        }
                        .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                    }
                }

                if files.isEmpty {
                    Text("Empty folder")
                        .font(.neoCaption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(files) { file in
                                fileRow(file)
                            }
                        }
                    }
                    .frame(height: 220)
                }
            }
        }
    }

    private func fileRow(_ file: ServerFileEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.text")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(file.isDirectory ? NeoPalette.amber : Color.secondary)
                .frame(width: 16)
            Text(file.name)
                .font(.neoCaption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if let size = file.size {
                Text(Formatters.bytes(size))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if file.isDirectory {
                Button {
                    browserDirectory = file.url
                    Task { await reloadFiles() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                .help("Open folder")
            } else {
                Button {
                    previewFile(file)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                .help("Preview text file")
                if !running {
                    Button {
                        confirmDeleteFile = file
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                    .help("Delete file")
                }
            }
            Button {
                model.reveal(file.url)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func previewFile(_ file: ServerFileEntry) {
        Task {
            guard let text = await model.serverFileText(file.url, for: server) else {
                model.showToast("\(file.name) is binary or too large to preview")
                return
            }
            preview = FilePreview(name: file.name, url: file.url, text: text)
        }
    }

    private func reloadFiles() async {
        files = await model.serverFiles(for: server, in: currentDirectory)
    }

    private func reloadBackups() async {
        backups = await model.serverBackups(for: server)
    }

    // MARK: - server.properties editor

    private var settingsCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Server Settings",
                    subtitle: "Written to server.properties — changes apply on next start.",
                    symbol: "gearshape"
                )

                if running || settingUp {
                    Text("Stop the server to edit settings — a running server rewrites this file on shutdown.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    field("MOTD", text: $motd)
                    field("Port", text: $portText)
                    field("Max players", text: $maxPlayers)
                    field("View distance", text: $viewDistance)
                    field("Simulation distance", text: $simulationDistance)
                    field("Spawn protection", text: $spawnProtection)
                    Picker("Difficulty", selection: $difficulty) {
                        Text("Peaceful").tag("peaceful")
                        Text("Easy").tag("easy")
                        Text("Normal").tag("normal")
                        Text("Hard").tag("hard")
                    }
                    .labelsHidden()
                    Picker("Gamemode", selection: $gamemode) {
                        Text("Survival").tag("survival")
                        Text("Creative").tag("creative")
                        Text("Adventure").tag("adventure")
                        Text("Spectator").tag("spectator")
                    }
                    .labelsHidden()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    Toggle(isOn: $onlineMode) {
                        toggleLabel("Online mode", "Verify players with their Minecraft account.")
                    }
                    .toggleStyle(NeoToggleStyle())
                    Toggle(isOn: $pvp) {
                        toggleLabel("PvP", "Allow player-vs-player combat.")
                    }
                    .toggleStyle(NeoToggleStyle())
                    Toggle(isOn: $whiteList) {
                        toggleLabel("Whitelist", "Only listed players may join (edit whitelist.json in Files).")
                    }
                    .toggleStyle(NeoToggleStyle())
                    Toggle(isOn: $allowFlight) {
                        toggleLabel("Allow flight", "Don't kick players for flying.")
                    }
                    .toggleStyle(NeoToggleStyle())
                }
                .disabled(running || settingUp)

                HStack {
                    Spacer()
                    Button("Reset") { Task { await loadProperties() } }
                        .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                        .disabled(running || settingUp)
                    Button("Apply Settings") { applyProperties() }
                        .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                        .disabled(running || settingUp || !propertiesLoaded)
                }
            }
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.neoCaption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func toggleLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 12, weight: .medium, design: .rounded))
            Text(subtitle)
                .font(.neoCaption).foregroundStyle(.secondary)
        }
    }

    private func applyProperties() {
        var values: [String: String] = [
            "motd": motd,
            "online-mode": onlineMode ? "true" : "false",
            "pvp": pvp ? "true" : "false",
            "white-list": whiteList ? "true" : "false",
            "allow-flight": allowFlight ? "true" : "false",
            "difficulty": difficulty,
            "gamemode": gamemode
        ]
        if let port = Int(portText.trimmingCharacters(in: .whitespaces)), (1...65535).contains(port) {
            values["server-port"] = "\(port)"
        }
        for (key, text) in [
            ("max-players", maxPlayers),
            ("view-distance", viewDistance),
            ("simulation-distance", simulationDistance),
            ("spawn-protection", spawnProtection)
        ] {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, Int(trimmed) != nil {
                values[key] = trimmed
            }
        }
        model.updateServerProperties(server, values: values)
    }

    private func loadProperties() async {
        let props = await model.serverProperties(for: server)
        motd = props["motd"] ?? server.name
        portText = props["server-port"] ?? "\(server.port)"
        onlineMode = props["online-mode"] != "false"
        pvp = props["pvp"] != "false"
        whiteList = props["white-list"] == "true"
        allowFlight = props["allow-flight"] == "true"
        spawnProtection = props["spawn-protection"] ?? ""
        maxPlayers = props["max-players"] ?? ""
        viewDistance = props["view-distance"] ?? ""
        simulationDistance = props["simulation-distance"] ?? ""
        difficulty = props["difficulty"] ?? "easy"
        gamemode = props["gamemode"] ?? "survival"
        propertiesLoaded = true
    }
}

/// Payload for the file preview sheet.
struct FilePreview: Identifiable {
    var id: URL { url }
    let name: String
    let url: URL
    let text: String
}

/// Read-only text preview for files inside a server folder, with a shortcut
/// to open the file in the system editor for real edits.
struct FilePreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let preview: FilePreview
    let server: HostedServer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(preview.name).font(.neoTitle)
                Spacer()
                Button("Open in Editor") {
                    NSWorkspace.shared.open(preview.url)
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                Button("Done") { dismiss() }
                    .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                    .keyboardShortcut(.defaultAction)
            }
            Text(preview.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(preview.text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(hex: "080D17"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(18)
        .frame(width: 640, height: 520)
    }
}
