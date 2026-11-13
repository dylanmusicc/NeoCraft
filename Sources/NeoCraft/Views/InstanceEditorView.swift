import SwiftUI

struct InstanceEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let draft: GameInstance

    private var current: GameInstance? { model.editingInstance }
    private var isExisting: Bool { model.isExistingInstance(draft) }
    private var isJavaEdition: Bool { current?.edition != .bedrock }
    /// The edition picker is a beta feature — it stays visible for existing
    /// Bedrock instances so they can be switched back even if the flag is off.
    private var showEditionPicker: Bool {
        model.settings.betaFeatures.bedrockEdition || current?.edition == .bedrock
    }
    private var accent: Color { Color(hex: current?.colorHex ?? draft.colorHex) }

    private var canSave: Bool {
        guard let current else { return false }
        return !current.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !current.minecraftVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            NeoDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    basicsCard
                    if isJavaEdition {
                        performanceCard
                    }
                    appearanceCard
                    if isJavaEdition,
                       model.settings.betaFeatures.customLaunchArgs
                        || !(current?.jvmArgs.isEmpty ?? true)
                        || !(current?.gameArgs.isEmpty ?? true) {
                        advancedCard
                    }
                }
                .padding(22)
            }
            .scrollIndicators(.hidden)
            NeoDivider()
            footer
        }
        .frame(width: 720, height: 730)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            BlockIconTile(
                block: current?.iconBlock ?? "grass_block",
                color: accent,
                symbol: current?.iconSymbol ?? "cube.fill",
                size: 54
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(isExisting ? "Edit Instance" : "New Instance")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(isExisting ? "Changes apply the next time this instance launches." : "Give your world a name, a version and a performance profile.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                closeWithoutSaving()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    // MARK: - Basics

    private var basicsCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Basics",
                    subtitle: "Name, version and mod loader",
                    symbol: "cube.fill",
                    tint: accent
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Instance Name")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("My Survival World", text: nameBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }

                if showEditionPicker {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edition")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Picker("Edition", selection: editionBinding) {
                            ForEach(GameEdition.allCases) { edition in
                                if edition == .java
                                    || model.settings.betaFeatures.bedrockEdition
                                    || current?.edition == .bedrock {
                                    Label(edition.title, systemImage: edition.symbol)
                                        .tag(edition)
                                }
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        if !isJavaEdition {
                            Text("Bedrock runs through NeoCraft Bedrock, bundled inside NeoCraft — this instance tracks your Bedrock version and Play launches it directly.")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Minecraft Version")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        versionPicker
                    }

                    Button {
                        Task { await model.reloadCatalog() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    .disabled(model.isLoadingCatalog)
                    .help("Reload the Mojang version list")
                }

                if isJavaEdition {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mod Loader")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Picker("Mod Loader", selection: loaderBinding) {
                            ForEach(ModLoader.allCases) { loader in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(hex: loader.badgeHex))
                                        .frame(width: 8, height: 8)
                                    Text(loader.title)
                                }
                                .tag(loader)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Toggle(isOn: boostBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Install Neo Boost performance mods")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            Text("Sodium, Lithium, FerriteCore and Fabric API are installed on first launch.")
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(current?.loader != .fabric)
                    .opacity(current?.loader == .fabric ? 1 : 0.5)
                }
            }
        }
    }

    @ViewBuilder
    private var versionPicker: some View {
        if !isJavaEdition {
            bedrockVersionPicker
        } else if model.catalog.isEmpty {
            TextField("e.g. 1.21.8", text: versionBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(width: 260)
        } else {
            Picker("Minecraft Version", selection: versionBinding) {
                ForEach(versionOptions, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .labelsHidden()
            .frame(width: 260)
        }
    }

    /// Recent Bedrock releases — Mojang doesn't publish a machine-readable
    /// catalog for Bedrock, so this is a curated list kept deliberately small.
    private static let bedrockVersions = [
        "1.21.124", "1.21.120", "1.21.114", "1.21.111", "1.21.109",
        "1.21.103", "1.21.99", "1.21.93", "1.21.90", "1.21.86",
        "1.21.80", "1.21.74", "1.21.60", "1.21.51", "1.21.44",
        "1.21.30", "1.21.20", "1.21.2", "1.20.80", "1.20.72"
    ]

    private var bedrockVersionPicker: some View {
        var ids = Self.bedrockVersions
        if let version = current?.minecraftVersion, !ids.contains(version) {
            ids.insert(version, at: 0)
        }
        return Picker("Bedrock Version", selection: versionBinding) {
            ForEach(ids, id: \.self) { id in
                Text(id).tag(id)
            }
        }
        .labelsHidden()
        .frame(width: 260)
    }

    private var versionOptions: [String] {
        var ids = model.catalog.map(\.id)
        if let version = current?.minecraftVersion, !ids.contains(version) {
            ids.insert(version, at: 0)
        }
        return ids
    }

    // MARK: - Performance

    private var performanceCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Performance",
                    subtitle: "Memory, Java and launch options",
                    symbol: "gauge.with.dots.needle.67percent",
                    tint: NeoPalette.amber
                )

                Toggle(isOn: overrideMemoryBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Override launcher memory")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        Text("Launcher default is \(Formatters.memory(model.settings.maxMemoryMB)) maximum.")
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if current?.memoryMB != nil {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Maximum memory")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Formatters.memory(current?.memoryMB ?? 0))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(accent)
                        }
                        Slider(value: memoryBinding, in: 1024...6144, step: 256)
                            .tint(accent)
                    }
                    .padding(.leading, 2)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Java Runtime")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Picker("Java Runtime", selection: javaBinding) {
                        Text("Automatic (recommended)").tag(Optional<String>.none)
                        ForEach(model.javaRuntimes) { runtime in
                            Text("\(runtime.name) · Java \(runtime.majorVersion)\(runtime.isAppleSilicon ? " · ARM" : "")")
                                .tag(Optional(runtime.executablePath))
                        }
                        if let path = current?.javaPath,
                           !model.javaRuntimes.contains(where: { $0.executablePath == path }) {
                            Text("Custom runtime").tag(Optional(path))
                        }
                    }
                    .labelsHidden()
                }

                HStack(spacing: 7) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NeoPalette.mint)
                    Text("NeoCraft installs the exact Eclipse Temurin JDK this version needs, automatically.")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(
                    title: "Appearance",
                    subtitle: "Pick an icon and accent",
                    symbol: "paintpalette.fill",
                    tint: NeoPalette.violet
                )

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(36), spacing: 7), count: 8),
                        alignment: .leading,
                        spacing: 7
                    ) {
                        ForEach(MinecraftBlockIcon.allCases, id: \.self) { icon in
                            let selected = current?.iconBlock == icon.rawValue
                            Button {
                                model.editingInstance?.iconBlock = icon.rawValue
                            } label: {
                                BlockIconTile(block: icon.rawValue, color: accent, size: 34)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(
                                                selected ? accent : Color.clear,
                                                lineWidth: 2
                                            )
                                    }
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(selected ? accent.opacity(0.14) : Color.primary.opacity(0.03))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(icon.displayName)
                        }
                    }
                }
                .frame(height: 148)

                HStack(spacing: 8) {
                    ForEach(InstanceStyle.palette, id: \.self) { hex in
                        let selected = current?.colorHex.caseInsensitiveCompare(hex) == .orderedSame
                        Button {
                            model.editingInstance?.colorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: selected ? 2.2 : 0)
                                }
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                                }
                                .padding(2)
                                .background(
                                    Circle().strokeBorder(
                                        selected ? Color(hex: hex) : Color.clear,
                                        lineWidth: 1.4
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Advanced

    private var advancedCard: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(
                    title: "Advanced",
                    subtitle: "Optional JVM and game arguments",
                    symbol: "terminal",
                    tint: NeoPalette.slate
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Additional JVM arguments")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("-XX:+UseG1GC …", text: jvmBinding, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(2...4)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Additional game arguments")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("--fullscreen …", text: gameArgsBinding, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1...3)
                }

                HStack(spacing: 7) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NeoPalette.sky)
                    Text("NeoCraft already applies tuned G1GC flags, native access and arm64 library paths. Add only what you need.")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if isExisting {
                Button(role: .destructive) {
                    if let current {
                        model.deleteInstance(current)
                        model.editingInstance = nil
                    }
                } label: {
                    Label("Move to Bin", systemImage: "trash")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, tint: NeoPalette.danger, compact: true))
                .disabled(current.map { model.isRunning($0) || model.isPreparing($0) } ?? false)
            }

            Spacer()

            Button("Cancel") {
                closeWithoutSaving()
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary))

            Button {
                save()
            } label: {
                Label(isExisting ? "Save Changes" : "Create Instance", systemImage: "checkmark")
            }
            .buttonStyle(NeoButtonStyle(kind: .primary, tint: accent))
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func closeWithoutSaving() {
        model.editingInstance = nil
        dismiss()
    }

    private func save() {
        guard let current else { return }
        var cleaned = current
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.minecraftVersion = cleaned.minecraftVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.loader == .vanilla {
            cleaned.neoBoost = false
        }
        model.saveInstance(cleaned)
        model.editingInstance = nil
        dismiss()
    }

    // MARK: - Bindings

    private var nameBinding: Binding<String> {
        Binding(
            get: { model.editingInstance?.name ?? "" },
            set: { model.editingInstance?.name = $0 }
        )
    }

    private var versionBinding: Binding<String> {
        Binding(
            get: { model.editingInstance?.minecraftVersion ?? "" },
            set: { model.editingInstance?.minecraftVersion = $0 }
        )
    }

    private var editionBinding: Binding<GameEdition> {
        Binding(
            get: { current?.edition ?? .java },
            set: { edition in
                model.editingInstance?.edition = edition
                if edition == .bedrock {
                    // Bedrock has no loaders or Java-side performance mods.
                    model.editingInstance?.loader = .vanilla
                    model.editingInstance?.neoBoost = false
                }
            }
        )
    }

    private var loaderBinding: Binding<ModLoader> {
        Binding(
            get: { model.editingInstance?.loader ?? .fabric },
            set: { loader in
                model.editingInstance?.loader = loader
                if loader == .vanilla {
                    model.editingInstance?.neoBoost = false
                }
            }
        )
    }

    private var boostBinding: Binding<Bool> {
        Binding(
            get: { model.editingInstance?.neoBoost ?? false },
            set: { model.editingInstance?.neoBoost = $0 }
        )
    }

    private var overrideMemoryBinding: Binding<Bool> {
        Binding(
            get: { model.editingInstance?.memoryMB != nil },
            set: { override in
                model.editingInstance?.memoryMB = override ? AppSettings.recommendedMemoryMB : nil
            }
        )
    }

    private var memoryBinding: Binding<Double> {
        Binding(
            get: { Double(model.editingInstance?.memoryMB ?? AppSettings.recommendedMemoryMB) },
            set: { model.editingInstance?.memoryMB = Int($0) }
        )
    }

    private var javaBinding: Binding<String?> {
        Binding(
            get: { model.editingInstance?.javaPath },
            set: { model.editingInstance?.javaPath = $0 }
        )
    }

    private var jvmBinding: Binding<String> {
        Binding(
            get: { model.editingInstance?.jvmArgs ?? "" },
            set: { model.editingInstance?.jvmArgs = $0 }
        )
    }

    private var gameArgsBinding: Binding<String> {
        Binding(
            get: { model.editingInstance?.gameArgs ?? "" },
            set: { model.editingInstance?.gameArgs = $0 }
        )
    }
}
