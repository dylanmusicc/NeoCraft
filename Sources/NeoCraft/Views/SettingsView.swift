import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingBetaTitle: String?
    @State private var pendingBetaEnable: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: L10n.t("nav.settings.title"),
                    subtitle: L10n.t("page.settings.subtitle")
                ) {
                    HStack(spacing: 8) {
                        NeoPill(text: "NeoCraft \(AppConstants.version)", symbol: "cube.transparent", tint: NeoPalette.accent)
                        Button {
                            model.showConsole = true
                        } label: {
                            Label("Console", systemImage: "terminal")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    }
                }

                languageCard
                javaCard
                performanceCard
                gameCard
                betaCard
                storageCard
                aboutCard
            }
            .padding(28)
            .frame(maxWidth: 1040, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            model.refreshStorageUsage()
        }
        .alert(
            "Enable beta feature?",
            isPresented: Binding(
                get: { pendingBetaTitle != nil },
                set: { if !$0 { pendingBetaTitle = nil; pendingBetaEnable = nil } }
            )
        ) {
            Button("Enable") {
                pendingBetaEnable?()
                pendingBetaEnable = nil
                pendingBetaTitle = nil
            }
            Button("Cancel", role: .cancel) {
                pendingBetaEnable = nil
                pendingBetaTitle = nil
            }
        } message: {
            Text("“\(pendingBetaTitle ?? "")” is experimental and may be unstable, break saves, or change without notice. Continue?")
        }
    }

    // MARK: - Language

    private var languageCard: some View {
        SettingsCard(
            title: L10n.t("settings.language.title"),
            subtitle: L10n.t("settings.language.subtitle"),
            symbol: "globe",
            tint: NeoPalette.violet
        ) {
            HStack(spacing: 10) {
                Text(L10n.t("settings.language.label"))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Picker("Language", selection: languageBinding) {
                    ForEach(L10n.supportedLanguages, id: \.code) { entry in
                        Text(entry.code == "system" ? L10n.t("settings.language.system") : entry.name)
                            .tag(entry.code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { model.settings.appLanguage },
            set: { model.settings.appLanguage = $0 }
        )
    }

    // MARK: - Java

    private var javaCard: some View {
        SettingsCard(
            title: "Java Runtime (ARM64)",
            subtitle: "Automatic Temurin installation keeps memory use low",
            symbol: "cup.and.saucer.fill",
            tint: NeoPalette.sky
        ) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runtime preference")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Picker("Java Runtime", selection: javaPathBinding) {
                        Text("Automatic (recommended)").tag(Optional<String>.none)
                        ForEach(model.javaRuntimes) { runtime in
                            Text("\(runtime.name) · Java \(runtime.majorVersion) · \(runtime.isAppleSilicon ? "arm64" : runtime.architecture)")
                                .tag(Optional(runtime.executablePath))
                        }
                        if let path = model.settings.selectedJavaPath,
                           !model.javaRuntimes.contains(where: { $0.executablePath == path }) {
                            Text("Custom runtime").tag(Optional(path))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 460)
                }

                Spacer()

                Button {
                    chooseJavaExecutable()
                } label: {
                    Label("Choose…", systemImage: "folder")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))

                Button {
                    Task { await model.loadJavaRuntimes() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .disabled(model.isDiscoveringJava)
            }

            if model.settings.selectedJavaPath != nil {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(NeoPalette.sky)
                    Text("A manual runtime is used for every instance unless that instance has its own runtime selected.")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use Automatic") {
                        model.settings.selectedJavaPath = nil
                    }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                }
            }

            if model.isDiscoveringJava && model.javaRuntimes.isEmpty {
                LoadingStateView(message: "Discovering Java runtimes…")
            } else if model.javaRuntimes.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NeoPalette.amber)
                    Text("No Java runtime found. NeoCraft will download Eclipse Temurin automatically before the first launch.")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NeoPalette.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 7) {
                    ForEach(model.javaRuntimes) { runtime in
                        javaRow(runtime)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    model.installJava(major: 25)
                } label: {
                    Label("Install Java 25", systemImage: "arrow.down.circle")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .disabled(model.isInstallingJava)

                Button {
                    model.installJava(major: 21)
                } label: {
                    Label("Install Java 21", systemImage: "arrow.down.circle")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .disabled(model.isInstallingJava)

                if model.isInstallingJava {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.installingJavaMajor.map { "Installing Temurin \($0)…" } ?? "Installing Java…")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    model.reveal(AppPaths.runtime)
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            }

            NeoDivider()

            // Memory allocation
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Maximum memory")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatters.memory(model.settings.maxMemoryMB))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(NeoPalette.accent)
                }
                Slider(value: maxMemoryBinding, in: 1024...6144, step: 256)
                    .tint(NeoPalette.accent)
                HStack {
                    Text("Minimum memory")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatters.memory(model.settings.minMemoryMB))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(NeoPalette.sky)
                }
                Slider(value: minMemoryBinding, in: 512...3072, step: 256)
                    .tint(NeoPalette.sky)
                HStack(spacing: 7) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(NeoPalette.accent)
                    Text("4.5 GB maximum is the recommended ceiling on an 8 GB Mac. Instances can override this.")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Recommended") {
                        model.settings.maxMemoryMB = AppSettings.recommendedMemoryMB
                        model.settings.minMemoryMB = 1024
                    }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                }
            }

            NeoDivider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Garbage collector")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Picker("Garbage Collector", selection: gcBinding) {
                    ForEach(GarbageCollector.allCases) { collector in
                        Text(collector.title).tag(collector)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.settings.garbageCollector.subtitle)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func javaRow(_ runtime: JavaRuntime) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(runtime.isAppleSilicon ? NeoPalette.mint : NeoPalette.slate)
                .frame(width: 26, height: 26)
                .background(
                    (runtime.isAppleSilicon ? NeoPalette.mint : NeoPalette.slate).opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(runtime.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    NeoPill(
                        text: "Java \(runtime.majorVersion)",
                        tint: runtime.majorVersion >= 25 ? NeoPalette.mint : NeoPalette.sky
                    )
                    if runtime.isAppleSilicon {
                        NeoPill(text: "arm64", symbol: "apple.logo", tint: NeoPalette.violet)
                    }
                    if runtime.isManaged {
                        NeoPill(text: "NeoCraft", symbol: "shippingbox", tint: NeoPalette.amber)
                    }
                }
                Text(runtime.executablePath)
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if runtime.isManaged {
                Button(role: .destructive) {
                    model.removeJava(runtime)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, tint: NeoPalette.danger, compact: true))
                .help("Remove this NeoCraft-managed runtime")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Performance

    private var performanceCard: some View {
        SettingsCard(
            title: "MacBook Neo Performance & Thermal",
            subtitle: "Fanless-friendly profiles tuned for the A18",
            symbol: "gauge.with.dots.needle.67percent",
            tint: NeoPalette.amber
        ) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Thermal profile")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                ThermalModeSelector(selection: thermalBinding)
                Text(model.settings.thermalMode.subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            NeoDivider()

            Toggle(isOn: adaptivePerformanceBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adaptive Performance")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    Text("Switches to Cool & Quiet on battery, Low Power Mode or heat; Max Performance on AC.")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            NeoDivider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GUI scale override")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    Text("0 = automatic. Lower values ease GPU load on the A18.")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper(
                    value: guiScaleBinding,
                    in: 0...4
                ) {
                    Text(model.settings.guiScale == 0 ? "Auto" : "\(model.settings.guiScale)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 34)
                }
            }
        }
    }

    // MARK: - Game

    private var gameCard: some View {
        SettingsCard(
            title: "Gameplay & Downloads",
            subtitle: "Version catalog, downloads and console",
            symbol: "gamecontroller.fill",
            tint: NeoPalette.violet
        ) {
            Toggle(isOn: snapshotsBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show snapshots in version pickers")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    Text("Snapshots can be unstable. Releases are always listed.")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            NeoDivider()

            Toggle(isOn: consoleOnLaunchBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open the console when Minecraft launches")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    Text("Useful for mod troubleshooting and crash reports.")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            NeoDivider()

            Toggle(isOn: uiSoundsBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UI Sound Effects")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    Text("Subtle clicks, launch blips and completion chimes.")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            NeoDivider()

            Toggle(isOn: backupToiCloudBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("World backups to iCloud Drive")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    Text("Backups sync automatically. Falls back to ~/Documents when iCloud is unavailable.")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            NeoDivider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Concurrent downloads")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    Text("Parallel connections used for libraries and assets.")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Stepper(
                    value: concurrencyBinding,
                    in: 1...16
                ) {
                    Text("\(model.settings.downloadConcurrency)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 22)
                }
            }

            NeoToggleSpacer()

            HStack(spacing: 8) {
                Button {
                    Task { await model.reloadCatalog() }
                } label: {
                    Label("Refresh Version Catalog", systemImage: "arrow.clockwise")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .disabled(model.isLoadingCatalog)

                if model.isLoadingCatalog {
                    ProgressView()
                        .controlSize(.small)
                }

                if let error = model.catalogError {
                    Text(error)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(NeoPalette.danger)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    model.reveal(AppPaths.versions)
                } label: {
                    Label("Version Files", systemImage: "folder")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            }
        }
    }

    // MARK: - Beta features

    private var betaCard: some View {
        SettingsCard(
            title: L10n.t("settings.beta.title"),
            subtitle: L10n.t("settings.beta.subtitle"),
            symbol: "flask.fill",
            tint: NeoPalette.amber
        ) {
            betaToggle(
                title: L10n.t("settings.beta.hud"),
                detail: L10n.t("settings.beta.hud.detail"),
                isOn: Binding(
                    get: { model.settings.betaFeatures.inGameHUD },
                    set: { model.settings.betaFeatures.inGameHUD = $0 }
                )
            )
            NeoDivider()
            betaToggle(
                title: L10n.t("settings.beta.ui"),
                detail: L10n.t("settings.beta.ui.detail"),
                isOn: Binding(
                    get: { model.settings.betaFeatures.inGameUI },
                    set: { model.settings.betaFeatures.inGameUI = $0 }
                )
            )
            NeoDivider()
            betaToggle(
                title: L10n.t("settings.beta.radar"),
                detail: L10n.t("settings.beta.radar.detail"),
                isOn: Binding(
                    get: { model.settings.betaFeatures.worldRadar },
                    set: { model.settings.betaFeatures.worldRadar = $0 }
                )
            )
            NeoDivider()
            betaToggle(
                title: L10n.t("settings.beta.args"),
                detail: L10n.t("settings.beta.args.detail"),
                isOn: Binding(
                    get: { model.settings.betaFeatures.customLaunchArgs },
                    set: { model.settings.betaFeatures.customLaunchArgs = $0 }
                )
            )
            NeoDivider()
            betaToggle(
                title: L10n.t("settings.beta.bedrock"),
                detail: L10n.t("settings.beta.bedrock.detail"),
                isOn: Binding(
                    get: { model.settings.betaFeatures.bedrockEdition },
                    set: { model.settings.betaFeatures.bedrockEdition = $0 }
                )
            )
            NeoDivider()
            betaToggle(
                title: L10n.t("settings.beta.bedrockServers"),
                detail: L10n.t("settings.beta.bedrockServers.detail"),
                isOn: Binding(
                    get: { model.settings.betaFeatures.bedrockServers },
                    set: { model.settings.betaFeatures.bedrockServers = $0 }
                )
            )
        }
    }

    private func betaToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { isOn.wrappedValue },
            set: { newValue in
                if newValue {
                    pendingBetaTitle = title
                    pendingBetaEnable = { isOn.wrappedValue = true }
                } else {
                    isOn.wrappedValue = false
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Storage

    private var storageCard: some View {
        SettingsCard(
            title: "Storage & Cache",
            subtitle: "Everything lives in Application Support/NeoCraft",
            symbol: "internaldrive.fill",
            tint: NeoPalette.rose
        ) {
            VStack(spacing: 8) {
                InfoRow(label: "Shared libraries & assets", value: Formatters.bytes(model.storageUsage.sharedBytes), symbol: "shippingbox", tint: NeoPalette.sky)
                InfoRow(label: "Instances & worlds", value: Formatters.bytes(model.storageUsage.instanceBytes), symbol: "square.stack.3d.up", tint: NeoPalette.accent)
                InfoRow(label: "Download cache", value: Formatters.bytes(model.storageUsage.cacheBytes), symbol: "arrow.down.circle", tint: NeoPalette.amber)
                InfoRow(label: "Java runtimes", value: Formatters.bytes(model.storageUsage.runtimeBytes), symbol: "cup.and.saucer", tint: NeoPalette.violet)
                NeoDivider()
                InfoRow(
                    label: "Total",
                    value: Formatters.bytes(model.storageUsage.totalBytes),
                    symbol: "internaldrive",
                    tint: NeoPalette.rose
                )
            }

            HStack(spacing: 8) {
                Button {
                    model.refreshStorageUsage()
                } label: {
                    Label("Recalculate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .disabled(model.isCalculatingStorage)

                Button {
                    model.clearCache()
                } label: {
                    Label("Clear Cache", systemImage: "trash")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))

                Button {
                    clearShaderCacheAndOldLogs()
                } label: {
                    Label("Clear Shader & Logs", systemImage: "sparkles.rectangle.stack")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .help("Removes compiled shader caches in every instance and launcher logs older than 7 days")

                if model.isCalculatingStorage {
                    ProgressView()
                        .controlSize(.small)
                    Text("Calculating…")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button("Data Folder") { model.reveal(AppPaths.root) }
                    Button("Versions") { model.reveal(AppPaths.versions) }
                    Button("Java Runtimes") { model.reveal(AppPaths.runtime) }
                    Button("Download Cache") { model.reveal(AppPaths.cache) }
                    Button("Logs") { model.reveal(AppPaths.logs) }
                } label: {
                    Label("Folders", systemImage: "folder")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 90)
            }
        }
    }

    /// Removes per-instance compiled shader caches (`shadercache/` folders
    /// inside each game's directory) and launcher log files older than a
    /// week. Everything is best-effort — failures are ignored.
    private func clearShaderCacheAndOldLogs() {
        let fileManager = FileManager.default
        var removed = 0

        for instance in model.instances {
            let candidates = [
                instance.gameDirectory.appendingPathComponent("shadercache", isDirectory: true),
                instance.gameDirectory.appendingPathComponent("shaders", isDirectory: true),
                instance.gameDirectory.appendingPathComponent(".fabric", isDirectory: true)
            ]
            for url in candidates where fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
                removed += 1
            }
        }

        // Launcher logs older than 7 days.
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        if let entries = try? fileManager.contentsOfDirectory(
            at: AppPaths.logs,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for url in entries {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                if modified < cutoff {
                    try? fileManager.removeItem(at: url)
                    removed += 1
                }
            }
        }

        model.showToast(removed > 0
            ? "Cleared \(removed) shader cache/log item\(removed == 1 ? "" : "s")"
            : "Nothing to clear")
        model.refreshStorageUsage()
    }

    // MARK: - About

    private var aboutCard: some View {
        SettingsCard(
            title: "Updates & About",
            subtitle: "NeoCraft for Apple silicon",
            symbol: "info.circle.fill",
            tint: NeoPalette.slate
        ) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [NeoPalette.accent, NeoPalette.violet],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 62, height: 62)
                .shadow(color: NeoPalette.accent.opacity(0.35), radius: 11, y: 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text("NeoCraft \(AppConstants.version)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("A native SwiftUI Minecraft launcher")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(model.snapshot.chipName) · macOS \(model.snapshot.osVersion) · \(Formatters.bytes(Int64(model.snapshot.totalMemory)))")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            NeoDivider()

            HStack(spacing: 8) {
                Button {
                    model.checkForUpdates()
                } label: {
                    Label("Check Mod Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .disabled(model.isCheckingUpdates || model.selectedInstance == nil)
                .help(model.selectedInstance == nil
                      ? "Select an instance to check its mods for updates"
                      : "Scan the selected instance's mods on Modrinth")

                if model.isCheckingUpdates {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking…")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            NeoDivider()

            HStack(spacing: 8) {
                Button {
                    model.openURL("https://modrinth.com")
                } label: {
                    Label("Modrinth", systemImage: "shippingbox")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))

                Button {
                    model.openURL("https://fabricmc.net")
                } label: {
                    Label("Fabric", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))

                Button {
                    model.openURL("https://www.minecraft.net")
                } label: {
                    Label("Minecraft", systemImage: "cube")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))

                Spacer()

                Text("Not affiliated with Mojang or Microsoft.")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Bindings

    private var javaPathBinding: Binding<String?> {
        Binding(
            get: { model.settings.selectedJavaPath },
            set: { model.settings.selectedJavaPath = $0 }
        )
    }

    private var thermalBinding: Binding<ThermalMode> {
        Binding(
            get: { model.settings.thermalMode },
            set: { model.settings.thermalMode = $0 }
        )
    }

    private var gcBinding: Binding<GarbageCollector> {
        Binding(
            get: { model.settings.garbageCollector },
            set: { model.settings.garbageCollector = $0 }
        )
    }

    private var maxMemoryBinding: Binding<Double> {
        Binding(
            get: { Double(model.settings.maxMemoryMB) },
            set: { value in
                let rounded = Int(value)
                model.settings.maxMemoryMB = rounded
                if model.settings.minMemoryMB > rounded {
                    model.settings.minMemoryMB = rounded
                }
            }
        )
    }

    private var minMemoryBinding: Binding<Double> {
        Binding(
            get: { Double(model.settings.minMemoryMB) },
            set: { value in
                let rounded = Int(value)
                model.settings.minMemoryMB = min(rounded, model.settings.maxMemoryMB)
            }
        )
    }

    private var snapshotsBinding: Binding<Bool> {
        Binding(
            get: { model.settings.showSnapshots },
            set: { value in
                model.settings.showSnapshots = value
                Task { await model.reloadCatalog() }
            }
        )
    }

    private var consoleOnLaunchBinding: Binding<Bool> {
        Binding(
            get: { model.settings.openConsoleOnLaunch },
            set: { model.settings.openConsoleOnLaunch = $0 }
        )
    }

    private var uiSoundsBinding: Binding<Bool> {
        Binding(
            get: { model.settings.uiSoundsEnabled },
            set: { model.settings.uiSoundsEnabled = $0 }
        )
    }

    private var adaptivePerformanceBinding: Binding<Bool> {
        Binding(
            get: { model.settings.adaptivePerformance },
            set: { model.settings.adaptivePerformance = $0 }
        )
    }

    private var backupToiCloudBinding: Binding<Bool> {
        Binding(
            get: { model.settings.backupToiCloud },
            set: { model.settings.backupToiCloud = $0 }
        )
    }

    private var guiScaleBinding: Binding<Int> {
        Binding(
            get: { model.settings.guiScale },
            set: { model.settings.guiScale = $0 }
        )
    }

    private var concurrencyBinding: Binding<Int> {
        Binding(
            get: { model.settings.downloadConcurrency },
            set: { model.settings.downloadConcurrency = $0 }
        )
    }

    // MARK: - Java picker

    private func chooseJavaExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Java executable"
        panel.message = "Select a java binary, a JDK home, or a macOS JavaVirtualMachines bundle."
        panel.prompt = "Use Java"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var candidates: [URL] = []
        if url.hasDirectoryPath {
            candidates.append(url.appendingPathComponent("bin/java"))
            candidates.append(url.appendingPathComponent("Contents/Home/bin/java"))
        } else {
            candidates.append(url)
        }

        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            model.alert = AppAlert(
                title: "Not a Java executable",
                message: "Choose the java binary inside a JDK, or the JDK home folder itself."
            )
            return
        }

        model.settings.selectedJavaPath = executable.path
        model.showToast("Java runtime selected")
        Task { await model.loadJavaRuntimes() }
    }
}

// MARK: - Settings card

struct SettingsCard<Content: View>: View {
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    let content: Content

    init(
        title: String,
        subtitle: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        NeoCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: title, subtitle: subtitle, symbol: symbol, tint: tint)
                content
            }
        }
    }
}

private struct NeoToggleSpacer: View {
    var body: some View {
        NeoDivider()
    }
}
