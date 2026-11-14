import SwiftUI

struct InstancesView: View {
    @Environment(AppModel.self) private var model

    private var bedrockEnabled: Bool {
        model.settings.betaFeatures.bedrockEdition
    }

    private var filteredInstances: [GameInstance] {
        var result = model.instances
        // Bedrock is a beta feature — while it's off, Bedrock instances
        // disappear from the launcher entirely.
        if !bedrockEnabled {
            result = result.filter { $0.edition != .bedrock }
        }
        if let edition = model.instanceEditionFilter {
            result = result.filter { $0.edition == edition }
        }
        let query = model.instanceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }
        return result.filter { instance in
            instance.name.localizedCaseInsensitiveContains(query)
                || instance.minecraftVersion.localizedCaseInsensitiveContains(query)
                || instance.loader.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: L10n.t("nav.instances.title"),
                    subtitle: L10n.t("page.instances.subtitle")
                ) {
                    HStack(spacing: 8) {
                        Picker("Edition", selection: editionFilterBinding) {
                            Text("All").tag("")
                            Text("Java").tag("java")
                            if bedrockEnabled {
                                Text("Bedrock").tag("bedrock")
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 190)
                        NeoSearchField(placeholder: "Filter instances", text: queryBinding)
                            .frame(width: 210)
                        Button {
                            model.beginCreateInstance()
                        } label: {
                            Label("New Instance", systemImage: "plus")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .primary))
                        .keyboardShortcut("n", modifiers: .command)
                    }
                }

                if model.instances.isEmpty {
                    EmptyStateView(
                        symbol: "square.stack.3d.up.fill",
                        title: "No instances yet",
                        message: "Create an instance to pair a Minecraft version with its own mods, worlds and performance profile.",
                        actionTitle: "Create Instance",
                        action: { model.beginCreateInstance() }
                    )
                    .neoCard(padding: 10, cornerRadius: 22)
                } else if filteredInstances.isEmpty {
                    EmptyStateView(
                        symbol: "magnifyingglass",
                        title: "No matching instances",
                        message: "Nothing matches \"\(model.instanceQuery)\". Try another name or version.",
                        actionTitle: "Clear Filter",
                        action: { model.instanceQuery = "" }
                    )
                    .neoCard(padding: 10, cornerRadius: 22)
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 308, maximum: 460), spacing: 18)],
                        spacing: 18
                    ) {
                        ForEach(Array(filteredInstances.enumerated()), id: \.element.id) { index, instance in
                            InstanceCard(instance: instance, appearIndex: index)
                        }
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Instances live in Application Support and can be moved to the Bin safely. Your shared libraries and Java runtime stay cached.")
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                }
            }
            .padding(28)
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private var editionFilterBinding: Binding<String> {
        Binding(
            get: { model.instanceEditionFilter?.rawValue ?? "" },
            set: { raw in
                model.instanceEditionFilter = raw.isEmpty ? nil : GameEdition(rawValue: raw)
            }
        )
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { model.instanceQuery },
            set: { model.instanceQuery = $0 }
        )
    }
}

private struct InstanceCard: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance
    var appearIndex: Int = 0
    @State private var appeared = false

    private var accent: Color { Color(hex: instance.colorHex) }
    private var hovered: Bool { model.hoveredInstanceID == instance.id }
    private var stats: InstanceStats? { model.statsByInstance[instance.id] }
    private var running: Bool { model.isRunning(instance) }
    private var preparing: Bool { model.isPreparing(instance) }
    /// Bedrock is a beta feature — instances are greyed out and can't be
    /// launched while the flag is off in Settings → Beta Features.
    private var bedrockBetaDisabled: Bool {
        instance.edition == .bedrock && !model.settings.betaFeatures.bedrockEdition
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                BlockIconTile(block: instance.iconBlock, color: accent, symbol: instance.iconSymbol, size: 50)

                VStack(alignment: .leading, spacing: 3) {
                    Text(instance.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        LoaderBadge(loader: instance.loader, size: 15)
                        Text(instance.versionLabel)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 2)

                Menu {
                    instanceMenuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            HStack(spacing: 6) {
                statusPill
                if bedrockBetaDisabled {
                    NeoPill(text: "Beta off", symbol: "flask", tint: Color.secondary)
                }
                if instance.neoBoost && instance.loader == .fabric {
                    NeoPill(
                        text: model.isBoostInstalled(instance) ? "Boosted" : "Neo Boost",
                        symbol: "bolt.fill",
                        tint: model.isBoostInstalled(instance) ? NeoPalette.mint : NeoPalette.amber
                    )
                }
                if let stats, stats.gameInstalled {
                    NeoPill(text: "Installed", symbol: "checkmark.circle", tint: NeoPalette.sky)
                }
            }

            HStack(spacing: 10) {
                MiniStat(label: "Mods", value: "\(stats?.modCount ?? 0)", symbol: "puzzlepiece.extension")
                MiniStat(label: "Worlds", value: "\(stats?.worldCount ?? 0)", symbol: "globe.americas")
                MiniStat(label: "Storage", value: Formatters.bytes(stats?.diskBytes ?? 0), symbol: "internaldrive")
            }

            NeoDivider()

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Formatters.relativeDate(instance.lastPlayed))
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(Formatters.duration(instance.totalPlayTime)) played")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                Button {
                    model.showInstanceDetail(instance)
                } label: {
                    Image(systemName: "square.grid.2x2")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .help("Manage mods, packs, worlds and config")

                Button {
                    model.beginEditInstance(instance)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .help("Edit instance")

                Button {
                    launch()
                } label: {
                    if preparing {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 58)
                    } else {
                        Label(running ? "Stop" : "Play", systemImage: running ? "stop.fill" : "play.fill")
                    }
                }
                .buttonStyle(
                    NeoButtonStyle(
                        kind: running ? .danger : .primary,
                        tint: running ? NeoPalette.danger : accent,
                        compact: true
                    )
                )
                .disabled(preparing || bedrockBetaDisabled)
            }
        }
        .neoCard(padding: 16, cornerRadius: 20)
        .saturation(bedrockBetaDisabled ? 0.15 : 1)
        .opacity(bedrockBetaDisabled ? 0.55 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    model.selectedInstanceID == instance.id || hovered
                        ? accent.opacity(model.selectedInstanceID == instance.id ? 0.55 : 0.30)
                        : Color.clear,
                    lineWidth: model.selectedInstanceID == instance.id ? 1.2 : 0.8
                )
        }
        .shadow(color: hovered ? accent.opacity(0.18) : Color.clear, radius: 14, y: 4)
        .scaleEffect(hovered ? 1.008 : 1)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appeared)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.hoveredInstanceID)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(min(Double(appearIndex), 14) * 0.035)) {
                appeared = true
            }
        }
        .onHover { hovering in
            if hovering {
                model.hoveredInstanceID = instance.id
            } else if model.hoveredInstanceID == instance.id {
                model.hoveredInstanceID = nil
            }
        }
        .onTapGesture {
            model.selectInstance(instance)
        }
        .contextMenu {
            instanceMenuItems
        }
        .help(instance.versionLabel)
    }

    @ViewBuilder
    private var instanceMenuItems: some View {
        Button {
            model.beginEditInstance(instance)
        } label: {
            Label("Edit Instance", systemImage: "slider.horizontal.3")
        }
        Button {
            model.showInstanceDetail(instance)
        } label: {
            Label("Manage Content", systemImage: "square.grid.2x2")
        }
        Button {
            model.revealInstanceFolder(instance)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Button {
            model.showScreenshots(for: instance)
        } label: {
            Label("Screenshots", systemImage: "photo.stack")
        }
        Button {
            model.duplicateInstance(instance)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        Divider()
        Button {
            model.worldBackupInstance = instance
        } label: {
            Label("World Backups", systemImage: "archivebox.fill")
        }
        Button {
            model.upgradeInstance = instance
        } label: {
            Label("Upgrade Version", systemImage: "arrow.up.circle")
        }
        if instance.loader == .fabric {
            Button {
                model.installPerformancePack(instance)
            } label: {
                Label("Performance Pack", systemImage: "gauge.with.dots.needle.67percent")
            }
            .disabled(model.isInstallingBoost)
        }
        Divider()
        Button(role: .destructive) {
            model.deleteInstance(instance)
        } label: {
            Label("Move to Bin", systemImage: "trash")
        }
        .disabled(running || preparing)
    }

    private var statusPill: some View {
        Group {
            if running {
                NeoPill(text: "Running", symbol: "waveform", tint: NeoPalette.mint)
            } else if preparing {
                NeoPill(text: "Preparing", symbol: "arrow.triangle.2.circlepath", tint: NeoPalette.accent)
            } else if stats?.gameInstalled == true {
                NeoPill(text: "Ready", symbol: "checkmark.seal.fill", tint: NeoPalette.sky)
            } else {
                NeoPill(text: "Not installed", symbol: "arrow.down.circle", tint: NeoPalette.slate)
            }
        }
    }

    private func launch() {
        guard !bedrockBetaDisabled else { return }
        if running {
            model.stopGame()
            return
        }
        model.selectInstance(instance)
        model.go(to: .play)
        model.startGame(instance)
    }
}
