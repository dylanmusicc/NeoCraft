import AppKit
import SwiftUI

struct PlayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: L10n.t("nav.play.title"),
                    subtitle: L10n.t("page.play.subtitle")
                ) {
                    HStack(spacing: 8) {
                        if !model.modUpdates.isEmpty {
                            Button {
                                model.go(to: .mods)
                            } label: {
                                NeoPill(
                                    text: "\(model.modUpdates.count) mod update\(model.modUpdates.count == 1 ? "" : "s")",
                                    symbol: "arrow.down.circle.fill",
                                    tint: NeoPalette.amber
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Open the Mod Library to install updates")
                        }
                        NeoPill(
                            text: model.settings.thermalMode.title,
                            symbol: model.settings.thermalMode.symbol,
                            tint: model.settings.thermalMode == .coolQuiet ? NeoPalette.sky : NeoPalette.amber
                        )
                        Button {
                            model.showConsole = true
                        } label: {
                            Label("Console", systemImage: "terminal")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                        .help("Open the game console")
                    }
                }

                if let instance = model.selectedInstance {
                    hero(instance)
                } else {
                    emptyHero
                }

                dashboardGrid
            }
            .padding(28)
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if let instance = model.selectedInstance {
                model.refreshStats(for: instance)
                if instance.edition == .java {
                    model.refreshFlightCheck(for: instance)
                }
            }
        }
    }

    /// Widgets in the Studio-defined order.
    private var orderedWidgetKinds: [DashboardCardKind] {
        model.settings.orderedDashboardKinds
    }

    /// Rough height weights so the two columns end up visually balanced
    /// instead of naively alternating cards of wildly different sizes.
    private func columnWeight(_ kind: DashboardCardKind) -> Double {
        switch kind {
        case .memory: 1.0
        case .thermal: 1.0
        case .activity: 1.3
        case .flightCheck: 0.9
        case .hardware: 1.4
        case .screenshots: 1.0
        case .boost: 1.7
        case .servers: 1.2
        }
    }

    /// Deals cards into two columns, always appending to the shorter one so
    /// the customized order is preserved down each column.
    private var dashboardColumns: [[DashboardCardKind]] {
        var columns: [[DashboardCardKind]] = [[], []]
        var heights: [Double] = [0, 0]
        for kind in orderedWidgetKinds {
            let target = heights[0] <= heights[1] ? 0 : 1
            columns[target].append(kind)
            heights[target] += columnWeight(kind)
        }
        return columns
    }

    private var dashboardGrid: some View {
        let columns = dashboardColumns
        return HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 18) {
                ForEach(columns[0], id: \.self) { kind in
                    dashboardCard(kind)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            VStack(spacing: 18) {
                ForEach(columns[1], id: \.self) { kind in
                    dashboardCard(kind)
                }
                patchNotesCard
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func dashboardCard(_ kind: DashboardCardKind) -> some View {
        switch kind {
        case .memory: memoryCard
        case .thermal: thermalCard
        case .activity: activitiesCard
        case .flightCheck:
            if model.selectedInstance?.edition == .bedrock { EmptyView() } else { flightCheckCard }
        case .hardware: hardwareCard
        case .screenshots: recentScreenshotsCard
        case .boost:
            if model.selectedInstance?.edition == .bedrock { EmptyView() } else { boostCard }
        case .servers: hostedServersCard
        }
    }

    /// Dashboard card listing hosted servers — start/stop inline and a
    /// jump into the Servers tab dashboard.
    private var hostedServersCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Hosted Servers", symbol: "server.rack")
                    Spacer()
                    Button {
                        model.go(to: .servers)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                    .help("Open Servers tab")
                }

                let servers = model.visibleHostedServers.prefix(4)
                if servers.isEmpty {
                    Text("No hosted servers yet — create one in the Servers tab.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(servers)) { server in
                        let running = model.isServerRunning(server)
                        HStack(spacing: 8) {
                            Circle()
                                .fill(running ? NeoPalette.mint : Color.secondary.opacity(0.4))
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.name)
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Text("\(server.edition == .bedrock ? "Bedrock" : server.serverType.title) · :\(server.port)")
                                    .font(.neoCaption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(running ? "Stop" : "Start") {
                                running ? model.stopHostedServer(server) : model.startHostedServer(server)
                            }
                            .buttonStyle(NeoButtonStyle(
                                kind: running ? .danger : .primary, compact: true))
                            Button {
                                model.openServerDashboard(server)
                                model.go(to: .servers)
                            } label: {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Open dashboard")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private func hero(_ instance: GameInstance) -> some View {
        switch model.settings.heroCardStyle {
        case "compact": compactHero(instance)
        case "glass": glassHero(instance)
        default: bannerHero(instance)
        }
    }

    /// Shared hero body for the banner and glass variants. `glass` flips
    /// the foreground palette so content stays legible on light materials.
    private func heroContent(_ instance: GameInstance, glass: Bool) -> some View {
        let stats = model.statsByInstance[instance.id]
        let running = model.isRunning(instance)
        let preparing = model.isPreparing(instance)
        let primary: Color = glass ? .primary : .white
        let secondary: Color = glass ? .secondary : .white.opacity(0.72)
        let pillTint: Color = glass ? NeoPalette.accent : .white

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                BlockIconTile(block: instance.iconBlock, color: Color(hex: instance.colorHex), symbol: instance.iconSymbol, size: 62)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        NeoPill(
                            text: running ? "Running" : (preparing ? "Preparing" : "Ready to play"),
                            symbol: running ? "waveform" : (preparing ? "arrow.triangle.2.circlepath" : "sparkles"),
                            tint: pillTint
                        )
                        NeoPill(text: instance.versionLabel, symbol: instance.edition == .bedrock ? "gamecontroller.fill" : instance.loader.symbol, tint: pillTint)
                        if model.isBoostInstalled(instance) {
                            NeoPill(text: "Neo Boost", symbol: "bolt.fill", tint: pillTint)
                        }
                    }

                    Text(instance.name)
                        .font(.neoPixelBold(24))
                        .tracking(0.5)
                        .foregroundStyle(primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(heroSubtitle(instance, stats: stats))
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 14)

                VStack(alignment: .trailing, spacing: 9) {
                    launchButton(instance)
                    if instance.edition == .bedrock,
                       model.settings.betaFeatures.bedrockEdition {
                        bedrockSourceCaption
                    }
                    if instance.edition == .java {
                        flightCheckPill(instance)
                    }
                    HStack(spacing: 8) {
                        if instance.edition == .java {
                            heroChip("Prepare", symbol: "arrow.down.circle", glass: glass) {
                                model.prepareGame(instance)
                            }
                            .disabled(preparing || running)
                            .opacity(preparing || running ? 0.5 : 1)
                        }

                        heroChip("Edit", symbol: "slider.horizontal.3", glass: glass) {
                            model.beginEditInstance(instance)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                accountStrip(glass: glass)

                Spacer(minLength: 8)

                heroStat("Mods", value: "\(stats?.modCount ?? 0)", symbol: "puzzlepiece.extension", glass: glass)
                heroStat("Worlds", value: "\(stats?.worldCount ?? 0)", symbol: "globe.americas", glass: glass)
                heroStat("Storage", value: Formatters.bytes(stats?.diskBytes ?? 0), symbol: "internaldrive", glass: glass)
                heroStat("Played", value: Formatters.duration(instance.totalPlayTime), symbol: "clock", glass: glass)
            }
        }
        .padding(20)
    }

    /// Full-width gradient hero — the classic Play header.
    private func bannerHero(_ instance: GameInstance) -> some View {
        let accent = Color(hex: instance.colorHex)
        let running = model.isRunning(instance)
        let preparing = model.isPreparing(instance)

        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    accent.opacity(0.98),
                    accent.opacity(0.74),
                    NeoPalette.ink.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: 520, y: -250)

            Circle()
                .fill(accent.opacity(0.45))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: 760, y: 160)

            // Grass-block rim across the top edge — the NeoCraft signature.
            NeoGrassEdge(height: 12)
                .frame(maxWidth: .infinity, alignment: .top)

            heroContent(instance, glass: false)
        }
        .frame(minHeight: 188)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: accent.opacity(0.32), radius: 26, x: 0, y: 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: running)
        .animation(.spring(response: 0.45, dampingFraction: 0.84), value: preparing)
    }

    /// Frosted-material hero that blends into the Studio theme.
    private func glassHero(_ instance: GameInstance) -> some View {
        let accent = Color(hex: instance.colorHex)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)

            LinearGradient(
                colors: [accent.opacity(0.22), accent.opacity(0.05), .clear],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.7, y: 0.9)
            )

            Circle()
                .fill(accent.opacity(0.20))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: 560, y: -180)

            heroContent(instance, glass: true)
        }
        .frame(minHeight: 188)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(accent.opacity(0.30), lineWidth: 1)
        }
        .shadow(color: accent.opacity(0.22), radius: 22, x: 0, y: 10)
    }

    /// Slim one-row hero for tight dashboards.
    private func compactHero(_ instance: GameInstance) -> some View {
        let accent = Color(hex: instance.colorHex)
        let stats = model.statsByInstance[instance.id]
        let running = model.isRunning(instance)
        let preparing = model.isPreparing(instance)

        return HStack(spacing: 16) {
            BlockIconTile(block: instance.iconBlock, color: accent, symbol: instance.iconSymbol, size: 54)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    NeoPill(
                        text: running ? "Running" : (preparing ? "Preparing" : "Ready"),
                        symbol: running ? "waveform" : (preparing ? "arrow.triangle.2.circlepath" : "sparkles"),
                        tint: running ? NeoPalette.mint : NeoPalette.accent
                    )
                    NeoPill(text: instance.versionLabel, symbol: instance.edition == .bedrock ? "gamecontroller.fill" : instance.loader.symbol, tint: NeoPalette.sky)
                    if model.isBoostInstalled(instance) {
                        NeoPill(text: "Neo Boost", symbol: "bolt.fill", tint: NeoPalette.amber)
                    }
                }
                Text(instance.name)
                    .font(.neoPixelBold(19))
                    .tracking(0.4)
                    .lineLimit(1)
                Text(heroSubtitle(instance, stats: stats))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 8) {
                    launchButton(instance)
                    if instance.edition == .java {
                        flightCheckPill(instance)
                    }
                }
                HStack(spacing: 8) {
                    if instance.edition == .java {
                        heroChip("Prepare", symbol: "arrow.down.circle") {
                            model.prepareGame(instance)
                        }
                        .disabled(preparing || running)
                        .opacity(preparing || running ? 0.5 : 1)
                    }
                    heroChip("Edit", symbol: "slider.horizontal.3") {
                        model.beginEditInstance(instance)
                    }
                    accountStrip(glass: false)
                }
            }
        }
        .neoCard(padding: 16, cornerRadius: 20)
    }

    private func heroChip(_ title: String, symbol: String, glass: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.neoPixel(10.5))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(
                    glass ? Color.primary.opacity(0.07) : Color.white.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            glass ? Color.primary.opacity(0.14) : Color.white.opacity(0.25),
                            lineWidth: 0.8
                        )
                }
                .foregroundStyle(glass ? Color.primary : Color.white)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func launchButton(_ instance: GameInstance) -> some View {
        if instance.edition == .bedrock {
            // Bedrock beta off → no launch UI at all.
            if model.settings.betaFeatures.bedrockEdition {
                bedrockPlayButton
            }
        } else {
            javaLaunchButton(instance)
        }
    }

    /// Bedrock launches through the NeoCraft Bedrock component bundled inside
    /// NeoCraft.app — Play starts the game directly, no second launcher.
    private var bedrockPlayButton: some View {
        let betaOff = !model.settings.betaFeatures.bedrockEdition
        let bundled = model.bedrockLauncherCandidate != nil
        let supported = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        let title = betaOff
            ? "Bedrock beta off"
            : !supported ? "macOS 27 required"
            : bundled ? "Play Bedrock" : "Bedrock unavailable"
        return HStack(spacing: 10) {
            Button {
                model.openBedrockGame()
            } label: {
            HStack(spacing: 8) {
                Image(systemName: betaOff ? "flask" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
            }
            .font(.neoPixelBold(13))
            .frame(width: 176)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [Color(hex: "38BDF8"), Color(hex: "6366F1")],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .foregroundStyle(.white)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: Color(hex: "6366F1").opacity(0.35), radius: 8, x: 0, y: 4)
        }
            .buttonStyle(.plain)
            .disabled(betaOff || !bundled || !supported)
            .opacity(betaOff || !bundled || !supported ? 0.55 : 1)
            .help(betaOff
                  ? "Bedrock Edition is a beta feature — enable it in Settings → Beta Features"
                  : !supported
                    ? "NeoCraft Bedrock needs macOS 27 or newer"
                    : bundled
                      ? "Launch Minecraft Bedrock directly"
                      : "This NeoCraft build doesn't include the Bedrock component")

            Button {
                model.openBedrockLauncher()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!bundled)
            .help("Open NeoCraft Bedrock — accounts, profiles, worlds and settings")
        }
    }

    /// Small caption under the Bedrock button naming the bundled component.
    private var bedrockSourceCaption: some View {
        Text(bedrockSourceDescription)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private var bedrockSourceDescription: String {
        if !model.settings.betaFeatures.bedrockEdition {
            return "Beta feature — enable in Settings"
        }
        if model.bedrockLauncherCandidate != nil {
            return "bundled in NeoCraft — Play launches directly"
        }
        return "NeoCraft Bedrock not bundled in this build"
    }

    private func javaLaunchButton(_ instance: GameInstance) -> some View {
        let running = model.isRunning(instance)
        let preparing = model.isPreparing(instance)
        let accent = Color(hex: instance.colorHex)

        return Button {
            if running {
                model.stopGame()
            } else {
                model.startGame(instance)
            }
        } label: {
            HStack(spacing: 8) {
                if preparing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(accent)
                    Text("Preparing…")
                } else {
                    Image(systemName: running ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(running ? "Stop Game" : "Launch Game")
                }
            }
            .font(.neoPixelBold(13))
            .frame(width: 176)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [Color(hex: "A9A9A9"), Color(hex: "8E8E8E"), Color(hex: "6E6E6E")],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .foregroundStyle(running ? NeoPalette.danger : NeoPalette.ink)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.65),
                                Color.white.opacity(0.08),
                                Color.black.opacity(0.38)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            }
            .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(preparing)
    }

    /// Live Flight Check status pill — tap opens the diagnostic sheet.
    private func flightCheckPill(_ instance: GameInstance) -> some View {
        let result = model.flightCheckResults[instance.id]
        let running = model.flightCheckRunning.contains(instance.id)
        let color = Color(hex: result?.pillColorHex ?? "9AA4B2")
        let title = running ? "Flight Check…" : (result?.pillTitle ?? "Flight Check")

        return Button {
            model.openFlightCheck(for: instance)
        } label: {
            HStack(spacing: 6) {
                if running {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                } else {
                    Image(systemName: statusIcon(result))
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.9), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .help("Pre-launch mod validation — tap for details")
    }

    private func statusIcon(_ result: FlightCheckResult?) -> String {
        switch result?.status {
        case .passed: "checkmark.shield.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .conflict: "xmark.octagon.fill"
        case .empty, nil: "tray"
        }
    }

    private var accountStrip: some View {
        accountStrip(glass: false)
    }

    private func accountStrip(glass: Bool) -> some View {
        let primary: Color = glass ? .primary : .white
        let secondary: Color = glass ? .secondary : .white.opacity(0.62)
        let capsuleFill = glass ? Color.primary.opacity(0.07) : Color.white.opacity(0.12)
        return HStack(spacing: 8) {
            if let account = model.activeAccount {
                AvatarView(uuid: account.uuid, size: 27, localImage: model.avatarImage(for: account))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Playing as")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(secondary)
                    Text(account.name)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(primary)
                }
            } else {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(primary.opacity(0.85))
                VStack(alignment: .leading, spacing: 0) {
                    Text("No account connected")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(primary)
                    Text("Sign in with Microsoft to play")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(secondary)
                }
                Button {
                    model.beginSignIn()
                } label: {
                    Text("Sign in")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white, in: Capsule())
                        .foregroundStyle(NeoPalette.accentDeep)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(capsuleFill, in: Capsule())
    }

    private func heroStat(_ label: String, value: String, symbol: String, glass: Bool = false) -> some View {
        let primary: Color = glass ? .primary : .white
        let secondary: Color = glass ? .secondary : .white.opacity(0.55)
        let fill = glass ? Color.primary.opacity(0.05) : Color.white.opacity(0.09)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .bold))
                Text(label)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(secondary)
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func heroSubtitle(_ instance: GameInstance, stats: InstanceStats?) -> String {
        var parts: [String] = []
        if let lastPlayed = instance.lastPlayed {
            parts.append("Last played \(Formatters.relativeDate(lastPlayed))")
        } else {
            parts.append("Ready for its first launch")
        }
        if let stats, stats.gameInstalled {
            parts.append("Game files installed")
        } else {
            parts.append("Files download automatically on launch")
        }
        if instance.neoBoost && instance.loader == .fabric {
            parts.append(model.isBoostInstalled(instance) ? "Neo Boost active" : "Neo Boost included")
        }
        return parts.joined(separator: "  ·  ")
    }

    private var emptyHero: some View {
        VStack(spacing: 14) {
            if model.isBootstrapping {
                ProgressView()
                    .controlSize(.regular)
                Text("Preparing NeoCraft…")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                EmptyStateView(
                    symbol: "square.stack.3d.up.fill",
                    title: "Create your first instance",
                    message: "Instances keep your worlds, mods and versions isolated. NeoCraft will set up Minecraft, Fabric and Java for you.",
                    actionTitle: "New Instance",
                    action: { model.beginCreateInstance() }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .neoCard(padding: 16, cornerRadius: 24)
    }

    // MARK: - Memory card

    private var memoryCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(
                    title: "Unified Memory",
                    subtitle: "Live headroom on this Mac",
                    symbol: "memorychip",
                    tint: NeoPalette.accent
                )

                MetricBar(
                    title: "Memory in use",
                    value: model.snapshot.memoryFraction,
                    detail: "\(Formatters.bytes(Int64(model.snapshot.usedMemory))) of \(Formatters.bytes(Int64(model.snapshot.totalMemory)))",
                    tint: NeoPalette.accent
                )

                if model.snapshot.swapUsed > 0 {
                    MetricBar(
                        title: "Swap in use",
                        value: min(1, Double(model.snapshot.swapUsed) / Double(max(model.snapshot.totalMemory, 1))),
                        detail: Formatters.bytes(Int64(model.snapshot.swapUsed)),
                        tint: NeoPalette.amber
                    )
                }

                HStack(spacing: 7) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(model.snapshot.chipName)
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(Formatters.bytes(Int64(model.snapshot.totalMemory))) unified")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Thermal card

    private var thermalCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 15) {
                SectionHeader(
                    title: "Thermal & CPU",
                    subtitle: "A18 thermals and processor load",
                    symbol: "thermometer.medium",
                    tint: thermalTint
                )

                HStack(spacing: 8) {
                    MetricTile(
                        title: "CPU",
                        value: "\(Int((model.snapshot.cpuUsage * 100).rounded()))%",
                        symbol: "cpu",
                        tint: NeoPalette.sky
                    )
                    MetricTile(
                        title: "Thermal",
                        value: model.snapshot.thermalState.displayName,
                        symbol: "thermometer.medium",
                        tint: thermalTint
                    )
                    MetricTile(
                        title: "Power",
                        value: model.snapshot.onACPower
                            ? (model.snapshot.lowPowerMode ? "AC · Low" : "AC")
                            : "Battery",
                        symbol: model.snapshot.onACPower ? "powerplug.fill" : "battery.25",
                        tint: model.snapshot.onACPower && !model.snapshot.lowPowerMode ? NeoPalette.mint : NeoPalette.amber
                    )
                }

                if let percent = model.snapshot.batteryPercent, !model.snapshot.onACPower {
                    MetricBar(
                        title: "Battery",
                        value: Double(percent) / 100,
                        detail: "\(percent)% remaining",
                        tint: percent > 30 ? NeoPalette.mint : NeoPalette.amber
                    )
                }
            }
        }
    }

    // MARK: - Hardware specs card

    private var hardwareCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(
                    title: "Hardware Specs",
                    subtitle: "This Mac, at a glance",
                    symbol: "desktopcomputer",
                    tint: NeoPalette.slate
                )

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    MiniStat(label: "Chip", value: model.snapshot.chipName, symbol: "apple.logo")
                    MiniStat(label: "Memory", value: Formatters.bytes(Int64(model.snapshot.totalMemory)), symbol: "memorychip")
                    MiniStat(label: "Model", value: model.snapshot.hardwareModel, symbol: "laptopcomputer")
                    MiniStat(label: "macOS", value: model.snapshot.osVersion, symbol: "gear")
                    MiniStat(
                        label: "Power",
                        value: model.snapshot.onACPower ? "AC Power" : "Battery",
                        symbol: model.snapshot.onACPower ? "powerplug.fill" : "battery.100"
                    )
                    MiniStat(
                        label: "Swap",
                        value: model.snapshot.swapUsed > 0 ? Formatters.bytes(Int64(model.snapshot.swapUsed)) : "None",
                        symbol: "arrow.triangle.2.circlepath"
                    )
                }
            }
        }
    }

    // MARK: - Flight check card

    @ViewBuilder
    private var flightCheckCard: some View {
        if let instance = model.selectedInstance {
            let result = model.flightCheckResults[instance.id]
            let running = model.flightCheckRunning.contains(instance.id)
            let tint = Color(hex: result?.pillColorHex ?? "9AA4B2")

            NeoCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Flight Check",
                        subtitle: "Pre-launch mod validation",
                        symbol: "checkmark.shield",
                        tint: tint
                    )

                    HStack(spacing: 10) {
                        NeoPill(
                            text: running ? "Scanning…" : (result?.pillTitle ?? "Not scanned yet"),
                            symbol: running ? "arrow.triangle.2.circlepath" : (result == nil ? "tray" : "checkmark.shield.fill"),
                            tint: tint
                        )
                        Spacer()
                        Button {
                            model.openFlightCheck(for: instance)
                        } label: {
                            Label(result == nil ? "Run Check" : "Details", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                        .disabled(running)
                    }

                    if let result {
                        Text("\(result.scannedCount) mod\(result.scannedCount == 1 ? "" : "s") scanned · \(result.errorCount) error\(result.errorCount == 1 ? "" : "s") · \(result.warningCount) warning\(result.warningCount == 1 ? "" : "s")")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Scans loaded mods for conflicts before launch.")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var thermalTint: Color {
        switch model.snapshot.thermalState {
        case .nominal: return NeoPalette.mint
        case .fair: return NeoPalette.amber
        case .serious, .critical: return NeoPalette.danger
        @unknown default: return NeoPalette.slate
        }
    }

    // MARK: - Boost card

    private var boostCard: some View {
        let instance = model.selectedInstance
        let installed = instance.map { model.isBoostInstalled($0) } ?? false
        let canBoost = instance?.loader == .fabric

        return NeoCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Neo Boost",
                    subtitle: "Fabric performance pack tuned for fanless Macs",
                    symbol: "bolt.fill",
                    tint: NeoPalette.amber
                )

                HStack(spacing: 6) {
                    NeoPill(
                        text: installed ? "Installed" : (canBoost ? "Ready" : "Fabric required"),
                        symbol: installed ? "checkmark.seal.fill" : "sparkles",
                        tint: installed ? NeoPalette.mint : (canBoost ? NeoPalette.amber : NeoPalette.slate)
                    )
                    NeoPill(text: "\(boostMods.count) mods", symbol: "shippingbox", tint: NeoPalette.sky)
                    if let stats = instance.flatMap({ model.statsByInstance[$0.id] }) {
                        NeoPill(text: "\(stats.modCount) total", symbol: "puzzlepiece.extension", tint: NeoPalette.violet)
                    }
                }

                Text("Sodium, Lithium and FerriteCore lift frame rates while keeping memory below the 8 GB ceiling. Installed straight from Modrinth and updated with your instance.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    ForEach(boostMods, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.055), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    if model.isInstallingBoost {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing performance mods…")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else if installed {
                        Label("Your instance is boosted", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(NeoPalette.mint)
                    }

                    Spacer(minLength: 0)

                    if let instance {
                        if canBoost && !installed {
                            Button {
                                model.installBoost(instance)
                            } label: {
                                Label("Install Neo Boost", systemImage: "bolt.fill")
                            }
                            .buttonStyle(NeoButtonStyle(kind: .primary, tint: NeoPalette.amber, compact: true))
                            .disabled(model.isInstallingBoost)
                        } else if !canBoost {
                            Button {
                                model.beginEditInstance(instance)
                            } label: {
                                Label("Switch to Fabric", systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                        }
                    }
                }
            }
        }
    }

    private var boostMods: [String] {
        ["Fabric API", "Sodium", "Lithium", "FerriteCore", "ImmediatelyFast"]
    }

    // MARK: - Activities

    private var activitiesCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(
                    title: "Recent Activity",
                    subtitle: "Downloads, installs and launches",
                    symbol: "clock.arrow.circlepath",
                    tint: NeoPalette.violet
                )

                if model.activities.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text("Nothing running right now. Everything is quiet.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 11) {
                        ForEach(Array(model.activities.prefix(5))) { activity in
                            ActivityRow(activity: activity)
                            if activity.id != model.activities.prefix(5).last?.id {
                                NeoDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recent screenshots

    /// Dashboard card listing the newest captures across all instances.
    private var recentScreenshotsCard: some View {
        let shots = model.allScreenshots().prefix(4)
        return NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Recent Screenshots",
                    subtitle: shots.isEmpty ? "Press F2 in-game to capture" : "Latest captures",
                    symbol: "photo.stack.fill",
                    tint: NeoPalette.rose
                )

                if shots.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "camera")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.tertiary)
                        Text("No screenshots yet")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 72), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(Array(shots), id: \.url) { entry in
                            Button {
                                model.go(to: .screenshots)
                            } label: {
                                ZStack {
                                    if let image = NSImage(contentsOf: entry.url) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .scaledToFill()
                                    } else {
                                        Color.primary.opacity(0.06)
                                    }
                                }
                                .frame(height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("\(entry.instance.name) — \(entry.url.lastPathComponent)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Patch notes

    private var patchNotesCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(
                    title: "What's New",
                    subtitle: "Latest Minecraft releases",
                    symbol: "sparkles",
                    tint: NeoPalette.sky
                )

                if model.isLoadingPatchNotes && model.patchNotes.isEmpty {
                    LoadingStateView(message: "Loading patch notes…")
                } else if model.patchNotes.isEmpty {
                    VStack(spacing: 8) {
                        Text(model.patchNotesError ?? "Patch notes are unavailable right now.")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await model.loadPatchNotes() }
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    VStack(spacing: 9) {
                        ForEach(Array(model.patchNotes.prefix(3))) { entry in
                            Button {
                                model.openPatchNote(entry)
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: entry.type == "snapshot" ? "flask.fill" : "cube.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(entry.type == "snapshot" ? NeoPalette.violet : NeoPalette.sky)
                                        .frame(width: 24, height: 24)
                                        .background(
                                            (entry.type == "snapshot" ? NeoPalette.violet : NeoPalette.sky).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.version.isEmpty ? entry.title : entry.version)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .lineLimit(1)
                                        if let short = entry.shortText, !short.isEmpty {
                                            Text(short)
                                                .font(.system(size: 9.5, weight: .regular, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 4)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}


