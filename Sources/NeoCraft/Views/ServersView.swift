import AppKit
import SwiftUI

// MARK: - Servers tab (hosted dedicated servers)

/// Dedicated-server manager: every hosted world — Java (vanilla/Paper/
/// Fabric) or Bedrock (Windows BDS through Wine) — with its live
/// dashboard, console, players, files, backups and plugins. The tab is
/// only about servers NeoCraft hosts; remote servers live in each
/// instance's own server list.
struct ServersView: View {
    @Environment(AppModel.self) private var model

    @State private var hostedPings: [UUID: ServerStatus] = [:]
    @State private var isCreatingServer = false
    @State private var deletingServer: HostedServer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Servers",
                subtitle: "Java and Bedrock dedicated servers hosted on this Mac."
            ) {
                HStack(spacing: 8) {
                    Button {
                        pingHostedServers()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))

                    Button {
                        isCreatingServer = true
                    } label: {
                        Label("New Server", systemImage: "plus")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                }
            }

            HStack(alignment: .top, spacing: 0) {
                // Left column: hosted servers + synced Bedrock content.
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        hostedCard
                        if model.settings.betaFeatures.bedrockEdition {
                            bedrockWorldsCard
                            bedrockPacksCard
                        }
                    }
                    .padding(.trailing, 4)
                }
                .scrollIndicators(.hidden)
                .frame(width: 400)

                Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1)

                // Right column: the hosted server's dashboard
                // (console, players, files, settings) or a hint.
                serverDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            model.refreshHostedServers()
            model.refreshBedrockContent()
            pingHostedServers()
        }
        .onChange(of: model.runningServerIDs) { _, _ in pingHostedServers() }
        .sheet(isPresented: $isCreatingServer) {
            NewHostedServerSheet()
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

    // MARK: - Detail pane (hosted server dashboard)

    /// Right-hand pane: the full dashboard of the selected hosted server.
    /// The dashboard renders its own header card, so the pane only adds
    /// a small floating close button — no duplicated title bar.
    @ViewBuilder
    private var serverDetail: some View {
        if let server = model.dashboardServer,
           model.visibleHostedServers.contains(where: { $0.id == server.id }) {
            ZStack(alignment: .topTrailing) {
                ServerDashboardView(server: server)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button {
                    model.dashboardServer = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(12)
                .help("Close dashboard")
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No server selected")
                    .font(.neoHeadline)
                Text("Create a server or pick one on the left to open its live dashboard — console, players, files, plugins and server.properties.")
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                Button("New Server") { isCreatingServer = true }
                    .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Hosted servers card

    /// Every dedicated server NeoCraft hosts on this Mac.
    private var hostedCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Hosted Servers",
                    subtitle: "Java (vanilla, Paper, Fabric) and Bedrock servers running on this Mac.",
                    symbol: "network"
                )

                if model.visibleHostedServers.isEmpty {
                    EmptyStateView(
                        symbol: "server.rack",
                        title: "No servers yet",
                        message: "Create a Java or Bedrock dedicated server — pick a fresh world or copy one from an instance.",
                        actionTitle: "New Server",
                        action: { isCreatingServer = true }
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(serverGroups, id: \.name) { section in
                            if !section.name.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(section.name.uppercased())
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .tracking(1.0)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.top, 4)
                            }
                            LazyVStack(spacing: 8) {
                                ForEach(section.servers) { server in
                                    hostedRow(server)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Servers grouped by their `group` label — ungrouped servers sort
    /// into a trailing "Servers" section, groups alphabetically before.
    private var serverGroups: [(name: String, servers: [HostedServer])] {
        var groups: [String: [HostedServer]] = [:]
        for server in model.visibleHostedServers {
            groups[server.group, default: []].append(server)
        }
        var result: [(String, [HostedServer])] = groups
            .filter { !$0.key.isEmpty }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value) }
        if let ungrouped = groups[""] {
            result.append(("", ungrouped))
        }
        return result
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
                    .fill(serverAccent(server).opacity(0.14))
                Image(systemName: server.edition == .bedrock ? "cube" : "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(serverAccent(server))
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
                    if server.edition == .bedrock {
                        NeoBadge(text: "Bedrock", color: NeoPalette.sky)
                    } else if server.serverType != .vanilla {
                        NeoBadge(text: server.serverType.title, color: Color.secondary)
                    }
                }
                Text(serverSubtitle(server))
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

            Menu {
                Button("Open Dashboard") {
                    model.openServerDashboard(server)
                }
                Button("Join Server") {
                    model.joinHostedServer(server)
                }
                .disabled(!running || model.isGameRunning)
                if server.edition == .java {
                    Button("Sync World from Instance") {
                        model.syncHostedServerWorld(server)
                    }
                    .disabled(running || settingUp || model.instance(for: server.instanceID) == nil)
                }
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
        .padding(14)
        .neoCard(padding: 14)
        .contentShape(Rectangle())
        .onTapGesture {
            model.openServerDashboard(server)
        }
        .overlay {
            if model.dashboardServer?.id == server.id {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(NeoPalette.accent.opacity(0.55), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The server's custom accent, or the edition default when unset.
    private func serverAccent(_ server: HostedServer) -> Color {
        let hex = server.colorHex.trimmingCharacters(in: .alphanumerics.inverted)
        if hex.count == 6 {
            return Color(hex: hex)
        }
        return server.edition == .bedrock ? NeoPalette.sky : NeoPalette.accent
    }

    private func serverSubtitle(_ server: HostedServer) -> String {
        if server.edition == .bedrock {
            return "\(server.worldName) · Bedrock \(server.minecraftVersion)"
        }
        return "\(server.worldName) · Minecraft \(server.minecraftVersion) · \(server.serverType.title) · from \(server.instanceName)"
    }

    @ViewBuilder
    private func hostedStatusBadge(running: Bool, ready: Bool, settingUp: Bool) -> some View {
        if settingUp {
            NeoBadge(text: "Setting up", color: NeoPalette.amber)
        } else if running {
            HStack(spacing: 4) {
                if ready { PulseDot(color: NeoPalette.mint, size: 6) }
                NeoBadge(text: ready ? "Online" : "Starting", color: ready ? NeoPalette.mint : NeoPalette.sky)
            }
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

    // MARK: - Bedrock content (synced from NeoCraft Bedrock)

    /// Bedrock worlds found in the launcher's Wine prefixes — managed in
    /// NeoCraft Bedrock, listed here so everything lives in one app.
    private var bedrockWorldsCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Bedrock Worlds",
                    subtitle: "Synced from NeoCraft Bedrock — manage them in the Bedrock launcher.",
                    symbol: "globe.americas"
                )

                if model.bedrockContent.worlds.isEmpty {
                    Text("No Bedrock worlds yet — play Bedrock once and its worlds show up here.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(model.bedrockContent.worlds.prefix(8)) { world in
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(NeoPalette.sky.opacity(0.14))
                                    Image(systemName: "globe.americas")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(NeoPalette.sky)
                                }
                                .frame(width: 34, height: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(world.name)
                                        .font(.neoHeadline)
                                        .lineLimit(1)
                                    Text(world.product)
                                        .font(.neoCaption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Button {
                                    model.reveal(world.folder)
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                                .help("Reveal in Finder")
                            }
                            .padding(10)
                            .neoCard(padding: 10)
                        }
                    }
                }
            }
        }
    }

    /// Resource/behavior/skin packs installed in the Bedrock prefixes.
    private var bedrockPacksCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Bedrock Packs",
                    subtitle: "Resource, behavior and skin packs synced from NeoCraft Bedrock.",
                    symbol: "puzzlepiece.extension.fill"
                )

                if model.bedrockContent.packs.isEmpty {
                    Text("No Bedrock packs installed yet.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(model.bedrockContent.packs.prefix(12)) { pack in
                            HStack(spacing: 12) {
                                Group {
                                    if let icon = pack.icon, let image = NSImage(contentsOf: icon) {
                                        Image(nsImage: image)
                                            .resizable().scaledToFill()
                                    } else {
                                        Image(systemName: "puzzlepiece.extension.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(NeoPalette.accent)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(NeoPalette.accent.opacity(0.14))
                                    }
                                }
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pack.name)
                                        .font(.neoHeadline)
                                        .lineLimit(1)
                                    Text([pack.kind, pack.version].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.neoCaption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Button {
                                    model.reveal(pack.folder)
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                                .help("Reveal in Finder")
                            }
                            .padding(10)
                            .neoCard(padding: 10)
                        }
                    }
                }
            }
        }
    }
}
