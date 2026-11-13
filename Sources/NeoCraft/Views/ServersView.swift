import AppKit
import SwiftUI

// MARK: - Servers tab (servers.dat)

/// Top-level multiplayer manager for the live `servers.dat` of the
/// selected instance. Every mutation writes the file atomically straight
/// away — there is no Apply button.
struct ServersView: View {
    @Environment(AppModel.self) private var model

    @State private var entries: [MCServerEntry] = []
    @State private var pings: [UUID: ServerStatus] = [:]
    @State private var hostedPings: [UUID: ServerStatus] = [:]
    @State private var editing: MCServerEntry?
    @State private var isAdding = false
    @State private var loadedInstanceID: UUID?
    @State private var deletingServer: HostedServer?

    private var instance: GameInstance? { model.selectedInstance }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: L10n.t("nav.servers.title"),
                    subtitle: L10n.t("page.servers.subtitle")
                ) {
                    HStack(spacing: 8) {
                        Button {
                            pingAll()
                        } label: {
                            Label("Refresh All", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                        .disabled(instance == nil)

                        Button {
                            isAdding = true
                        } label: {
                            Label("Add Server", systemImage: "plus")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                        .disabled(instance == nil)
                    }
                }

                if model.instances.count > 1 {
                    Picker("Instance", selection: instanceBinding) {
                        ForEach(model.instances) { candidate in
                            Text(candidate.name).tag(Optional(candidate.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }

                hostedCard

                serversCard
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            reload()
            model.refreshHostedServers()
            pingHostedServers()
        }
        .onChange(of: model.selectedInstanceID) { _, _ in reload() }
        .onChange(of: model.runningServerIDs) { _, _ in pingHostedServers() }
        .sheet(isPresented: editorPresented) {
            ServerEntryEditorSheet(entry: editing) { saved in
                upsert(saved)
            }
            .environment(model)
        }
        .confirmationDialog(
            "Delete hosted server?",
            isPresented: Binding(
                get: { deletingServer != nil },
                set: { if !$0 { deletingServer = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete \(deletingServer?.name ?? "server")", role: .destructive) {
                if let server = deletingServer {
                    model.deleteHostedServer(server)
                }
                deletingServer = nil
            }
            Button("Cancel", role: .cancel) { deletingServer = nil }
        } message: {
            Text("This removes the server folder and its copy of the world. The original world in the instance's saves is not affected.")
        }
    }

    // MARK: - Hosted servers card

    /// Worlds from the user's instances running as Java dedicated servers.
    private var hostedCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Hosted Worlds",
                    subtitle: "Press Host on a world in an instance's Worlds tab to run it as a Java dedicated server on this Mac.",
                    symbol: "network"
                )

                if model.hostedServers.isEmpty {
                    Text("No hosted servers yet.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(model.hostedServers) { server in
                            hostedRow(server)
                        }
                    }
                }
            }
        }
    }

    private func hostedRow(_ server: HostedServer) -> some View {
        let running = model.isServerRunning(server)
        let ready = model.isServerReady(server)
        let settingUp = model.isSettingUpServer(server)
        let address = AppModel.serverAddress(server)
        let ping = hostedPings[server.id]

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NeoPalette.accent.opacity(0.14))
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NeoPalette.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Button {
                        model.openServerDashboard(server)
                    } label: {
                        Text(server.name)
                            .font(.neoHeadline)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .help("Open server dashboard")
                    hostedStatusBadge(running: running, ready: ready, settingUp: settingUp)
                }
                Text("\(server.worldName) · Minecraft \(server.minecraftVersion) · from \(server.instanceName)")
                    .font(.neoCaption).foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(address)
                        .font(.neoCaption.weight(.semibold).monospacedDigit())
                    Button {
                        model.copyServerAddress(server)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Copy server address")
                    if running, let ping, ping.reachable {
                        Text("· \(ping.playersOnline)/\(ping.playersMax) players")
                            .font(.neoCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            if running {
                Button("Stop") {
                    model.stopHostedServer(server)
                }
                .buttonStyle(NeoButtonStyle(kind: .danger, compact: true))
            } else {
                Button(settingUp ? "Setting up…" : "Start") {
                    model.startHostedServer(server)
                }
                .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                .disabled(settingUp)
            }

            Button("Join") {
                model.joinHostedServer(server)
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            .disabled(!running || model.isGameRunning)

            Menu {
                Button("Open Dashboard") {
                    model.openServerDashboard(server)
                }
                Button("Sync World from Instance") {
                    model.syncHostedServerWorld(server)
                }
                .disabled(running || settingUp || model.instance(for: server.instanceID) == nil)
                Button("Copy Address") {
                    model.copyServerAddress(server)
                }
                Button("Reveal Folder") {
                    model.reveal(server.directory)
                }
                Divider()
                Button("Delete Server", role: .destructive) {
                    deletingServer = server
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help("Server options")
        }
        .padding(12)
        .neoCard(padding: 12)
    }

    @ViewBuilder
    private func hostedStatusBadge(running: Bool, ready: Bool, settingUp: Bool) -> some View {
        if settingUp {
            NeoBadge(text: "Setting up", color: NeoPalette.amber)
        } else if running {
            NeoBadge(text: ready ? "Online" : "Starting", color: ready ? NeoPalette.mint : NeoPalette.sky)
        } else {
            NeoBadge(text: "Stopped", color: Color.secondary)
        }
    }

    private func pingHostedServers() {
        for server in model.hostedServers where model.isServerRunning(server) {
            let address = AppModel.serverAddress(server)
            Task {
                let status = await ServerPinger.ping(address)
                hostedPings[server.id] = status
            }
        }
    }

    // MARK: - servers.dat card

    private var serversCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Server List",
                    subtitle: instance == nil
                        ? "Create an instance first — each instance keeps its own servers.dat."
                        : "Read live from \(instance!.name)/servers.dat — edits save instantly.",
                    symbol: "server.rack"
                )

                if instance != nil {
                    if entries.isEmpty {
                        EmptyStateView(
                            symbol: "server.rack",
                            title: "No servers yet",
                            message: "Add a server and it appears in the game's multiplayer list on next launch.",
                            actionTitle: "Add Server",
                            action: { isAdding = true }
                        )
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, server in
                                serverRow(server, index: index)
                            }
                        }
                    }
                } else {
                    Text("Select an instance to manage its server list.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func serverRow(_ server: MCServerEntry, index: Int) -> some View {
        let status = pings[server.id]
        return HStack(spacing: 12) {
            serverIcon(server, status: status)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(server.name)
                        .font(.neoHeadline)
                        .lineLimit(1)
                    if let version = status?.versionName, !version.isEmpty, status?.reachable == true {
                        NeoBadge(text: version, color: Color.secondary)
                    }
                }
                Text(server.address)
                    .font(.neoCaption).foregroundStyle(.secondary)
                if let motd = status?.motd, !motd.isEmpty {
                    Text(motd)
                        .font(.neoCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            pingBadge(for: server, status: status)

            Button {
                move(server, by: -1)
            } label: {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            .disabled(index == 0)
            .help("Move up")

            Button {
                move(server, by: 1)
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            .disabled(index == entries.count - 1)
            .help("Move down")

            Button("Join") {
                join(server)
            }
            .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
            .disabled(model.isGameRunning)

            Button {
                editing = server
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            .help("Edit server")

            Button(role: .destructive) {
                delete(server)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            .help("Delete server")
        }
        .padding(12)
        .neoCard(padding: 12)
    }

    @ViewBuilder
    private func pingBadge(for server: MCServerEntry, status: ServerStatus?) -> some View {
        if let status {
            if status.reachable {
                let ms = status.latencyMilliseconds ?? 0
                let tint: Color = ms < 80 ? NeoPalette.mint : (ms < 180 ? NeoPalette.amber : NeoPalette.danger)
                HStack(spacing: 5) {
                    StatusDot(color: tint, size: 6)
                    Text("\(ms) ms")
                        .font(.neoCaption.weight(.semibold))
                        .monospacedDigit()
                    Text("· \(status.playersOnline)/\(status.playersMax)")
                        .font(.neoCaption)
                        .foregroundStyle(.secondary)
                }
            } else {
                NeoBadge(text: "Unreachable", color: NeoPalette.danger)
            }
        } else {
            NeoBadge(text: "Pinging…", color: Color.secondary)
        }
    }

    @ViewBuilder
    private func serverIcon(_ server: MCServerEntry, status: ServerStatus?) -> some View {
        // Prefer the live ping favicon, then the favicon stored in servers.dat.
        if let data = status?.faviconData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable().scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if let icon = server.icon, let data = Data(base64Encoded: icon),
                  let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable().scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NeoPalette.accent.opacity(0.14))
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NeoPalette.accent)
            }
            .frame(width: 34, height: 34)
        }
    }

    // MARK: - Bindings & actions

    private var instanceBinding: Binding<UUID?> {
        Binding(
            get: { model.selectedInstanceID },
            set: { newValue in
                guard let newValue,
                      let candidate = model.instances.first(where: { $0.id == newValue }) else { return }
                model.selectInstance(candidate)
            }
        )
    }

    private var editorPresented: Binding<Bool> {
        Binding(
            get: { editing != nil || isAdding },
            set: { if !$0 { editing = nil; isAdding = false } }
        )
    }

    private func reload() {
        guard let instance else {
            entries = []
            pings = [:]
            loadedInstanceID = nil
            return
        }
        guard loadedInstanceID != instance.id else { return }
        loadedInstanceID = instance.id
        entries = ServerListService.load(for: instance)
        pingAll()
    }

    private func upsert(_ saved: MCServerEntry) {
        if let index = entries.firstIndex(where: { $0.id == saved.id }) {
            entries[index] = saved
        } else {
            entries.append(saved)
        }
        persist()
        pingAll()
    }

    private func move(_ server: MCServerEntry, by offset: Int) {
        guard let index = entries.firstIndex(where: { $0.id == server.id }) else { return }
        let target = index + offset
        guard entries.indices.contains(target) else { return }
        entries.swapAt(index, target)
        persist()
    }

    private func delete(_ server: MCServerEntry) {
        entries.removeAll { $0.id == server.id }
        pings[server.id] = nil
        persist()
        model.showToast("Removed \(server.name)")
    }

    private func join(_ server: MCServerEntry) {
        guard let instance else { return }
        model.joinServerEntry(server, in: instance)
    }

    /// Every edit writes `servers.dat` atomically — Minecraft reads the
    /// same file on launch.
    private func persist() {
        guard let instance else { return }
        do {
            try ServerListService.save(entries, for: instance)
        } catch {
            model.presentError("Couldn't write servers.dat", error)
        }
    }

    private func pingAll() {
        pings = [:]
        for server in entries {
            Task {
                let status = await ServerPinger.ping(server.address)
                pings[server.id] = status
                persistFavicon(status, for: server.id)
            }
        }
    }

    /// The ping response carries the server's favicon in the exact base64
    /// form `servers.dat` stores in its `icon` field — keep the file in
    /// sync so the in-game server list shows the icon too.
    private func persistFavicon(_ status: ServerStatus, for id: UUID) {
        guard let icon = status.faviconBase64, !icon.isEmpty,
              let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].icon != icon else { return }
        entries[index].icon = icon
        persist()
    }
}

// MARK: - Single server editor sheet

/// Compact add/edit form for one `servers.dat` entry. `nil` entry = add.
struct ServerEntryEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: MCServerEntry?
    let onSave: (MCServerEntry) -> Void

    @State private var name = ""
    @State private var address = ""

    private var isNew: Bool { entry == nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Add Server" : "Edit Server")
                .font(.neoTitle)
            TextField("Server name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Address (host or host:port)", text: $address)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                Button("Save") { save() }
                    .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            name = entry?.name ?? ""
            address = entry?.address ?? ""
        }
    }

    private func save() {
        var saved = entry ?? MCServerEntry(name: "", address: "")
        saved.name = name.trimmingCharacters(in: .whitespaces)
        saved.address = address.trimmingCharacters(in: .whitespaces)
        onSave(saved)
        model.showToast(isNew ? "Server added" : "Server updated")
        dismiss()
    }
}
