import SwiftUI

// MARK: - Instance Detail Hub

/// Tabbed per-instance manager: installed mods, shader & resource packs,
/// worlds with seed radar, and performance/config tuning.
struct InstanceDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance

    enum DetailTab: String, CaseIterable, Identifiable {
        case mods, visuals, worlds, config
        var id: String { rawValue }
        var title: String {
            switch self {
            case .mods: "Mods"
            case .visuals: "Visuals"
            case .worlds: "Worlds"
            case .config: "Config"
            }
        }
        var symbol: String {
            switch self {
            case .mods: "puzzlepiece.extension"
            case .visuals: "paintbrush.pointed"
            case .worlds: "globe.americas"
            case .config: "slider.horizontal.3"
            }
        }
    }

    @State private var tab: DetailTab = .mods

    /// Bedrock has no Java mod ecosystem — the Mods tab is hidden entirely.
    private var availableTabs: [DetailTab] {
        DetailTab.allCases.filter { $0 != .mods || instance.edition == .java }
    }

    private var effectiveTab: DetailTab {
        availableTabs.contains(tab) ? tab : (availableTabs.first ?? .mods)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BlockIconTile(block: instance.iconBlock, color: Color(hex: instance.colorHex), symbol: instance.iconSymbol, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.name).font(.neoTitle)
                    Text(instance.versionLabel)
                        .font(.neoCaption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Tab picker
            HStack(spacing: 6) {
                ForEach(availableTabs) { item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = item }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(
                                effectiveTab == item ? NeoPalette.accent.opacity(0.16) : Color.primary.opacity(0.05),
                                in: Capsule()
                            )
                            .foregroundStyle(effectiveTab == item ? NeoPalette.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            Divider()

            switch effectiveTab {
            case .mods: ModsTab(instance: instance)
            case .visuals: VisualsTab(instance: instance)
            case .worlds: WorldsTab(instance: instance)
            case .config: ConfigTab(instance: instance)
            }
        }
        .padding(22)
        .frame(width: 720, height: 560)
    }
}

// MARK: - Mods tab

private struct ModsTab: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance

    @State private var mods: [InstalledMod] = []
    @State private var loading = true
    @State private var query = ""
    @State private var statusFilter = "all"
    @State private var records: [String: ModInstaller.InstalledRecord] = [:]
    @State private var updates: [ModUpdate] = []
    @State private var profiles: [InstanceContent.ModProfile] = []
    @State private var newProfileName = ""
    @State private var showingProfileCreator = false
    @State private var editingConfig: URL?
    @State private var configDraft = ""

    private var filtered: [InstalledMod] {
        var result = mods
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            result = result.filter {
                $0.displayName.localizedCaseInsensitiveContains(q)
                    || $0.modID.localizedCaseInsensitiveContains(q)
                    || $0.fileName.localizedCaseInsensitiveContains(q)
            }
        }
        switch statusFilter {
        case "enabled": result = result.filter(\.enabled)
        case "disabled": result = result.filter { !$0.enabled }
        case "updates": result = result.filter { update(for: $0) != nil }
        default: break
        }
        return result
    }

    private func update(for mod: InstalledMod) -> ModUpdate? {
        guard let record = record(for: mod) else { return nil }
        return updates.first { $0.projectID == record.projectID }
    }

    private func record(for mod: InstalledMod) -> ModInstaller.InstalledRecord? {
        // Match by file name — records store the sanitized download name.
        records.values.first { $0.filename == mod.fileName }
    }

    var body: some View {
        if instance.edition == .bedrock {
            bedrockUnavailable
        } else {
            modsBrowser
        }
    }

    /// Bedrock has no Java mod ecosystem — the whole tab is greyed out.
    private var bedrockUnavailable: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("Mods are a Java Edition feature")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("Bedrock uses add-ons and marketplace content instead. This instance can't load Java mods.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(0.75)
    }

    private var modsBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                NeoSearchField(placeholder: "Filter mods", text: $query)
                Picker("", selection: $statusFilter) {
                    Text("All").tag("all")
                    Text("Enabled").tag("enabled")
                    Text("Disabled").tag("disabled")
                    Text("Updates").tag("updates")
                }
                .labelsHidden()
                .frame(width: 110)
                Spacer()
                Menu("Profiles") {
                    Button("Save Current as Profile…") { showingProfileCreator = true }
                    if !profiles.isEmpty { Divider() }
                    ForEach(profiles) { profile in
                        Button(profile.name) { applyProfile(profile) }
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(width: 90)
                Button("Enable All") { bulkSet(enabled: true) }
                    .controlSize(.small)
                Button("Disable All") { bulkSet(enabled: false) }
                    .controlSize(.small)
            }

            if showingProfileCreator {
                HStack(spacing: 8) {
                    TextField("Profile name", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        saveProfile()
                        showingProfileCreator = false
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { showingProfileCreator = false }
                }
            }

            if !profiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(profiles) { profile in
                            HStack(spacing: 6) {
                                Text(profile.name)
                                    .font(.neoCaption.weight(.semibold))
                                Button("Apply") { applyProfile(profile) }
                                    .controlSize(.mini)
                                Button { deleteProfile(profile) } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                    }
                }
            }

            Divider()

            if loading {
                HStack { ProgressView().controlSize(.small); Text("Scanning mods…").font(.neoCaption).foregroundStyle(.secondary) }
                Spacer()
            } else if filtered.isEmpty {
                Spacer()
                EmptyStateView(
                    symbol: "puzzlepiece.extension",
                    title: mods.isEmpty ? "No mods installed" : "Nothing matches",
                    message: mods.isEmpty
                        ? "Install mods from the Mod Library or Neo Boost."
                        : "Try a different filter.",
                    actionTitle: mods.isEmpty ? "Open Mod Library" : nil,
                    action: mods.isEmpty ? { model.go(to: .mods) } : nil
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filtered) { mod in modRow(mod) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { await reload() }
        .sheet(isPresented: Binding(
            get: { editingConfig != nil },
            set: { if !$0 { editingConfig = nil } }
        )) {
            if let file = editingConfig {
                ModConfigEditorSheet(file: file)
            }
        }
    }

    private func modRow(_ mod: InstalledMod) -> some View {
        HStack(spacing: 10) {
            Image(systemName: mod.info == nil ? "doc.zipper" : "shippingbox.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(mod.enabled ? NeoPalette.accent : Color.secondary)
                .frame(width: 30, height: 30)
                .background((mod.enabled ? NeoPalette.accent : Color.secondary).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(mod.displayName)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if !mod.version.isEmpty {
                        Text("v\(mod.version)")
                            .font(.neoCaption).foregroundStyle(.secondary)
                    }
                    NeoBadge(text: mod.loader.title, color: loaderColor(mod.loader))
                    if update(for: mod) != nil {
                        NeoBadge(text: "Update", color: NeoPalette.amber)
                    }
                    if !mod.enabled {
                        NeoBadge(text: "Disabled", color: Color.secondary)
                    }
                }
                Text("\(Formatters.bytes(mod.sizeBytes)) · \(mod.fileName)")
                    .font(.neoCaption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let update = update(for: mod), let record = record(for: mod) {
                Button("Update") {
                    model.updateModInInstance(projectID: record.projectID, title: update.title, into: instance)
                }
                .controlSize(.small)
                .help("Update to \(update.latest.versionNumber)")
            }

            Button {
                if let config = InstanceContent.modConfigURL(for: mod, in: instance) {
                    loadConfig(config)
                } else {
                    model.showToast("No config file found for \(mod.displayName)")
                }
            } label: {
                Image(systemName: "doc.text")
            }
            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            .help("Open mod config")
            .disabled(!mod.enabled)

            Toggle("", isOn: Binding(
                get: { mod.enabled },
                set: { model.setModEnabled(mod, enabled: $0, in: instance) }
            ))
            .toggleStyle(NeoToggleStyle())
            .labelsHidden()
            .frame(width: 38)

            Button(role: .destructive) {
                model.deleteInstalledMod(mod, in: instance)
                Task { await reload() }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loaderColor(_ loader: ModLoaderKind) -> Color {
        switch loader {
        case .fabric: NeoPalette.sky
        case .quilt: NeoPalette.violet
        case .forge, .neoforge: NeoPalette.orange
        case .unknown: Color.secondary
        }
    }

    private func bulkSet(enabled: Bool) {
        for mod in mods where mod.enabled != enabled {
            model.setModEnabled(mod, enabled: enabled, in: instance)
        }
        Task { await reload() }
    }

    private func saveProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let profile = InstanceContent.captureProfile(named: name, from: mods)
        try? InstanceContent.saveModProfile(profile, for: instance)
        newProfileName = ""
        profiles = InstanceContent.modProfiles(for: instance)
        model.showToast("Profile \"\(name)\" saved")
    }

    private func applyProfile(_ profile: InstanceContent.ModProfile) {
        do {
            let changed = try InstanceContent.applyModProfile(profile, to: instance)
            model.showToast("Applied \"\(profile.name)\" — \(changed) change(s)")
            model.rescanFlightCheck(for: instance)
            model.refreshStats(for: instance)
            Task { await reload() }
        } catch {
            model.presentError("Couldn't apply profile", error)
        }
    }

    private func deleteProfile(_ profile: InstanceContent.ModProfile) {
        try? InstanceContent.deleteModProfile(profile, for: instance)
        profiles = InstanceContent.modProfiles(for: instance)
    }

    private func loadConfig(_ url: URL) {
        configDraft = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        editingConfig = url
    }

    private func reload() async {
        loading = true
        let scanned = await InstanceContent.installedMods(in: instance)
        mods = scanned
        records = await model.modInstaller.installedRecords(for: instance)
        updates = await model.modInstaller.checkForUpdates(in: instance)
        profiles = InstanceContent.modProfiles(for: instance)
        loading = false
    }
}

/// Plain-text editor for a mod's JSON/TOML config file.
private struct ModConfigEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let file: URL
    @State private var text = ""
    @State private var dirty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(file.lastPathComponent).font(.neoTitle)
                Spacer()
                Text(file.deletingLastPathComponent().lastPathComponent)
                    .font(.neoCaption).foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.system(size: 11, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: text) { _, _ in dirty = true }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    try? text.write(to: file, atomically: true, encoding: .utf8)
                    dirty = false
                    dismiss()
                }
                .buttonStyle(NeoButtonStyle(kind: .primary))
                .disabled(!dirty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .onAppear {
            text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        }
    }
}

// MARK: - Visuals tab

private struct VisualsTab: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance

    @State private var shaderPacks: [InstanceContent.AssetPack] = []
    @State private var resourcePacks: [InstanceContent.AssetPack] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            packSection(title: "Shader Packs", symbol: "sparkles", packs: $shaderPacks, folder: "shaderpacks")
            NeoDivider()
            packSection(title: "Resource Packs", symbol: "square.stack.3d.up", packs: $resourcePacks, folder: "resourcepacks", reorderable: true)
            NeoDivider()
            HStack {
                Button {
                    do {
                        let file = try InstanceContent.applyA18ShaderConfig(to: instance)
                        model.showToast("A18 shader profile written")
                        model.reveal(file)
                    } catch {
                        model.presentError("Couldn't write shader config", error)
                    }
                } label: {
                    Label("A18 Shader Profile", systemImage: "bolt.fill")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .help("Writes Iris performance settings tuned for the fanless A18")
                Spacer()
                Text("Disabled packs are renamed with .disabled — Minecraft ignores them.")
                    .font(.neoCaption).foregroundStyle(.secondary)
            }
        }
        .task { reload() }
    }

    private func packSection(
        title: String,
        symbol: String,
        packs: Binding<[InstanceContent.AssetPack]>,
        folder: String,
        reorderable: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, symbol: symbol)
            if packs.wrappedValue.isEmpty {
                Text("No \(title.lowercased()) installed.")
                    .font(.neoCaption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(packs.wrappedValue) { pack in
                            packRow(pack, reorderable: reorderable)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 170)
            }
        }
    }

    private func packRow(_ pack: InstanceContent.AssetPack, reorderable: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: pack.isArchive ? "shippingbox" : "folder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(pack.enabled ? NeoPalette.accent : Color.secondary)
                .frame(width: 26, height: 26)
                .background((pack.enabled ? NeoPalette.accent : Color.secondary).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(pack.fileName.replacingOccurrences(of: ".disabled", with: ""))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(Formatters.bytes(pack.sizeBytes)) · \(pack.folder)")
                    .font(.neoCaption).foregroundStyle(.secondary)
            }
            Spacer()
            if reorderable && pack.folder == "resourcepacks" {
                Button {
                    move(pack, by: -1)
                } label: { Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).frame(width: 20, height: 20)
                Button {
                    move(pack, by: 1)
                } label: { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).frame(width: 20, height: 20)
            }
            Toggle("", isOn: Binding(
                get: { pack.enabled },
                set: { enabled in
                    do {
                        _ = try InstanceContent.setAssetPack(pack, enabled: enabled)
                        model.showToast("\(enabled ? "Enabled" : "Disabled") \(pack.fileName)")
                        reload()
                    } catch {
                        model.presentError("Couldn't update pack", error)
                    }
                }
            ))
            .toggleStyle(NeoToggleStyle())
            .labelsHidden()
            .frame(width: 38)
            Button {
                model.reveal(pack.fileURL)
            } label: { Image(systemName: "folder") }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            Button(role: .destructive) {
                do {
                    try InstanceContent.deleteAssetPack(pack)
                    model.showToast("Deleted \(pack.fileName)")
                    reload()
                } catch {
                    model.presentError("Couldn't delete pack", error)
                }
            } label: { Image(systemName: "trash") }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Moves a resource pack one slot in options.txt's `resourcePacks:` order.
    private func move(_ pack: InstanceContent.AssetPack, by offset: Int) {
        let name = pack.fileName
            .replacingOccurrences(of: ".disabled", with: "")
            .replacingOccurrences(of: ".zip", with: "")
        do {
            try InstanceContent.reorderResourcePack(name, by: offset, in: instance)
            reload()
        } catch {
            model.presentError("Couldn't reorder pack", error)
        }
    }

    private func reload() {
        shaderPacks = InstanceContent.assetPacks(inFolder: "shaderpacks", for: instance)
        resourcePacks = InstanceContent.assetPacks(inFolder: "resourcepacks", for: instance)
    }
}

// MARK: - Worlds tab

private struct WorldsTab: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance

    @State private var worlds: [WorldInfo] = []
    @State private var radarWorld: WorldInfo?
    @State private var hostingWorld: WorldInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Worlds", symbol: "globe.americas.fill")
                Spacer()
                Button(model.backupRunning ? "Backing up…" : "Back Up All") {
                    model.backupWorlds(in: instance)
                }
                .disabled(model.backupRunning || worlds.isEmpty)
            }

            if worlds.isEmpty {
                Spacer()
                EmptyStateView(
                    symbol: "globe",
                    title: "No worlds yet",
                    message: "Play this instance once to generate a world, or create one in-game."
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(worlds) { world in worldRow(world) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .task { reload() }
        .sheet(item: radarBinding) { world in
            WorldRadarView(world: world).environment(model)
        }
        .sheet(item: hostingBinding) { world in
            HostWorldSheet(instance: instance, world: world)
                .environment(model)
        }
    }

    private var hostingBinding: Binding<WorldInfo?> {
        Binding(get: { hostingWorld }, set: { hostingWorld = $0 })
    }

    private func worldRow(_ world: WorldInfo) -> some View {
        HStack(spacing: 10) {
            worldIcon(world)
            VStack(alignment: .leading, spacing: 1) {
                Text(world.levelName ?? world.name)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                Text(worldSubtitle(world))
                    .font(.neoCaption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.settings.betaFeatures.worldRadar {
                Button {
                    radarWorld = world
                } label: { Image(systemName: "map.fill") }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                    .help("Seed & biome radar")
            }
            Button("Play") {
                model.playWorld(world, in: instance)
            }
            .controlSize(.small)
            .disabled(model.isGameRunning || model.isRunning(instance))
            if instance.edition == .java {
                Button("Host") {
                    hostingWorld = world
                }
                .controlSize(.small)
                .disabled(model.isRunning(instance))
                .help("Host this world as a Java dedicated server")
            }
            Button("Back Up") { model.backupWorlds(in: instance, world: world) }
                .controlSize(.small)
                .disabled(model.backupRunning)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Seed-derived biome minimap when `level.dat` exposed a seed;
    /// otherwise the classic cube glyph.
    @ViewBuilder
    private func worldIcon(_ world: WorldInfo) -> some View {
        if let seed = world.seed {
            RadarThumbnail(
                field: BiomeField(seed: seed),
                spawnX: world.spawnX,
                spawnZ: world.spawnZ
            )
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
            }
        } else {
            Image(systemName: "cube.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.neoGrass)
                .frame(width: 30, height: 30)
                .background(Color.neoGrass.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func worldSubtitle(_ world: WorldInfo) -> String {
        var parts = [Formatters.bytes(world.sizeBytes), world.name]
        if let seed = world.seed { parts.append("seed \(seed)") }
        if let gameType = world.gameType { parts.append(gameType) }
        return parts.joined(separator: " · ")
    }

    private var radarBinding: Binding<WorldInfo?> {
        Binding(get: { radarWorld }, set: { radarWorld = $0 })
    }

    private func reload() {
        worlds = WorldBackupService.worlds(in: instance)
    }
}

// MARK: - Config tab

private struct ConfigTab: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance

    @State private var draft: GameInstance

    init(instance: GameInstance) {
        self.instance = instance
        _draft = State(initialValue: instance)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NeoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Memory (8 GB Unified)", subtitle: "Per-instance heap — kept inside the safe 4–6 GB band", symbol: "memorychip")
                        HStack {
                            Text("\(Formatters.memory(draft.effectiveMemoryMB))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Spacer()
                            Text("recommended \(Formatters.memory(AppSettings.recommendedMemoryMB))")
                                .font(.neoCaption).foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(draft.effectiveMemoryMB) },
                                set: { draft.memoryMB = Int($0) }
                            ),
                            in: 2048...6144,
                            step: 256
                        )
                        .tint(NeoPalette.accent)
                        HStack {
                            Text("2048 MB").font(.neoCaption).foregroundStyle(.secondary)
                            Spacer()
                            Text("6144 MB").font(.neoCaption).foregroundStyle(.secondary)
                        }
                    }
                }

                NeoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Interface & Rendering", subtitle: "GUI scale for this instance", symbol: "display")
                        HStack {
                            Text("GUI scale")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                            Spacer()
                            Picker("", selection: Binding(
                                get: { draft.guiScale ?? 0 },
                                set: { draft.guiScale = $0 == 0 ? nil : $0 }
                            )) {
                                Text("Auto").tag(0)
                                Text("Small (1×)").tag(1)
                                Text("Normal (2×)").tag(2)
                                Text("Large (3×)").tag(3)
                            }
                            .labelsHidden().frame(width: 130)
                        }
                    }
                }

                NeoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Launch Arguments", subtitle: "Appended to every launch of this instance", symbol: "terminal")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("JVM flags").font(.neoCaption).foregroundStyle(.secondary)
                            TextField("-XX:+UseCompactObjectHeaders", text: $draft.jvmArgs)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Game arguments").font(.neoCaption).foregroundStyle(.secondary)
                            TextField("--width 1280 --height 800", text: $draft.gameArgs)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }
                        Toggle(isOn: Binding(
                            get: { draft.macosInputFix },
                            set: { draft.macosInputFix = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("macOS Input Fixes").font(.system(size: 12, weight: .medium, design: .rounded))
                                Text("Installs the macOS trackpad/right-click fix mod on launch.")
                                    .font(.neoCaption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(NeoToggleStyle())
                    }
                }
            }
            .padding(4)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Revert") {
                    draft = instance
                }
                Button("Apply Configuration") {
                    apply()
                }
                .buttonStyle(NeoButtonStyle(kind: .primary))
            }
            .padding(.horizontal, 4).padding(.vertical, 8)
        }
    }

    private func apply() {
        model.updateInstance(draft)
        model.showToast("Configuration applied to \(draft.name)")
    }
}
