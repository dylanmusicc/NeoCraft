import SwiftUI

// MARK: - World backups sheet

struct WorldBackupView: View {
    @Environment(AppModel.self) private var model
    @State private var radarWorld: WorldInfo?
    let instance: GameInstance

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "World Backups", subtitle: instance.name)

            NeoCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Save location", symbol: "icloud.fill")
                    Toggle(isOn: Binding(
                        get: { model.settings.backupToiCloud },
                        set: { model.settings.backupToiCloud = $0 }
                    )) {
                        Text("Save backups to iCloud Drive")
                            .font(.neoBody.weight(.medium))
                    }
                    Text(model.settings.backupToiCloud
                         ? "Backups go to iCloud Drive/NeoCraft Backups and sync automatically."
                         : "Backups go to ~/Documents/NeoCraft Backups.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                }
            }

            NeoCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeader(title: "Worlds", symbol: "globe.europe.africa.fill")
                        Spacer()
                        Button(model.backupRunning ? "Backing up…" : "Back Up All") {
                            model.backupWorlds(in: instance)
                        }
                        .disabled(model.backupRunning)
                    }
                    let worlds = WorldBackupService.worlds(in: instance)
                    if worlds.isEmpty {
                        Text("No worlds found in this instance yet.")
                            .font(.neoBody).foregroundStyle(.secondary)
                    } else {
                        ForEach(worlds) { world in
                            HStack {
                                worldIcon(world)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(world.levelName ?? world.name)
                                        .font(.neoBody.weight(.semibold))
                                    Text(worldSubtitle(world))
                                        .font(.neoCaption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.settings.betaFeatures.worldRadar {
                                    Button {
                                        radarWorld = world
                                    } label: {
                                        Image(systemName: "map.fill")
                                    }
                                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                                    .help("Seed & biome radar")
                                }
                                Button("Back Up") { model.backupWorlds(in: instance, world: world) }
                                    .disabled(model.backupRunning)
                            }
                        }
                    }
                }
            }

            let backups = model.worldBackups(for: instance)
            if !backups.isEmpty {
                NeoCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Existing backups", symbol: "archivebox.fill")
                        ForEach(backups.prefix(12), id: \.self) { url in
                            HStack {
                                Image(systemName: "doc.zipper").foregroundStyle(Color.neoAccent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .font(.neoCaption.weight(.medium)).lineLimit(1)
                                    Text(Formatters.bytes(Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)))
                                        .font(.neoCaption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Reveal") { model.revealBackup(url) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .sheet(item: radarBinding) { world in
            WorldRadarView(world: world)
                .environment(model)
        }
    }

    private var radarBinding: Binding<WorldInfo?> {
        Binding(get: { radarWorld }, set: { radarWorld = $0 })
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
            .frame(width: 26, height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
            }
        } else {
            Image(systemName: "cube.fill")
                .foregroundStyle(Color.neoGrass)
        }
    }

    private func worldSubtitle(_ world: WorldInfo) -> String {
        var parts = ["\(Formatters.bytes(world.sizeBytes))", world.name]
        if let seed = world.seed {
            parts.append("seed \(seed)")
        }
        if let gameType = world.gameType {
            parts.append(gameType)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Smart upgrade sheet

struct InstanceUpgradeView: View {
    @Environment(AppModel.self) private var model
    @StateObject private var picker = UpgradePickerModel()
    let instance: GameInstance
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Upgrade \(instance.name)",
                subtitle: "Clone to \(instance.minecraftVersion) → newer, with compatible mods"
            )

            NeoCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Target version", symbol: "arrow.up.circle.fill")
                    targetPicker
                }
            }

            if let results = model.upgradeResults[instance.id] {
                compatibilityCard(results)
            } else if model.upgradingInstanceID == instance.id {
                NeoCard {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Checking Modrinth compatibility…")
                            .font(.neoBody.weight(.medium))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                if let target = targetVersion {
                    Button("Check Compatibility") {
                        model.checkUpgradeCompatibility(instance: instance, targetVersion: target)
                    }
                    .disabled(model.upgradingInstanceID != nil)
                    Button("Clone & Upgrade") {
                        model.cloneAndUpgrade(instance: instance, targetVersion: target)
                        dismiss()
                    }
                    .buttonStyle(NeoButtonStyle(kind: .primary))
                    .disabled(model.upgradingInstanceID != nil)
                }
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private var targetVersion: String? {
        picker.target
    }

    /// Releases newer than the instance's version, newest first.
    private var newerVersions: [String] {
        model.catalog
            .filter(\.isRelease)
            .map(\.id)
            .filter { compareVersions($0, instance.minecraftVersion) > 0 }
            .sorted { compareVersions($0, $1) > 0 }
            .prefix(8)
            .map { $0 }
    }

    /// Dotted-numeric compare for "1.21.4"-style versions.
    private func versionKey(_ id: String) -> [Int] {
        id.split(separator: ".").compactMap { Int($0) }
    }

    private func compareVersions(_ a: String, _ b: String) -> Int {
        let ka = versionKey(a), kb = versionKey(b)
        for i in 0..<max(ka.count, kb.count) {
            let va = i < ka.count ? ka[i] : 0
            let vb = i < kb.count ? kb[i] : 0
            if va != vb { return va < vb ? -1 : 1 }
        }
        return 0
    }

    private var targetPicker: some View {
        Picker("Newer release", selection: Binding(
            get: { picker.target ?? newerVersions.first ?? "" },
            set: { picker.target = $0.isEmpty ? nil : $0 }
        )) {
            ForEach(newerVersions, id: \.self) { version in
                Text(version).tag(version)
            }
        }
        .labelsHidden()
        .onAppear {
            if picker.target == nil { picker.target = newerVersions.first }
        }
    }

    private func compatibilityCard(_ results: [ModCompatibility]) -> some View {
        let ready = results.filter(\.compatible)
        let pending = results.filter { !$0.compatible }
        return NeoCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Compatibility", symbol: "checkmark.shield.fill")
                HStack(spacing: 16) {
                    NeoBadge(text: "\(ready.count) Ready", color: Color.neoGrass)
                    NeoBadge(text: "\(pending.count) Incompatible", color: pending.isEmpty ? Color.neoGrass : Color.neoDanger)
                }
                ForEach(results.prefix(20)) { item in
                    HStack {
                        Image(systemName: item.compatible ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.compatible ? Color.neoGrass : Color.neoDanger)
                        Text(item.title).font(.neoBody.weight(.medium))
                        Spacer()
                        Text(item.type.title).font(.neoBadge).foregroundStyle(.secondary)
                    }
                }
                if results.count > 20 {
                    Text("…and \(results.count - 20) more")
                        .font(.neoCaption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

@MainActor
final class UpgradePickerModel: ObservableObject {
    @Published var target: String?
}

// MARK: - Crash Doctor sheet

struct CrashDoctorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let diagnosis: CrashDiagnosis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.neoAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crash Doctor").font(.neoTitle)
                    Text(diagnosis.title).font(.neoBody.weight(.semibold))
                }
                Spacer()
            }

            NeoCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Diagnosis", symbol: "waveform.path.ecg")
                    Text(diagnosis.summary).font(.neoBody).foregroundStyle(.secondary)
                }
            }

            NeoCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Suggested fixes", symbol: "wrench.and.screwdriver.fill")
                    ForEach(diagnosis.suggestions, id: \.self) { suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(Color.neoAccent)
                            Text(suggestion).font(.neoBody)
                            Spacer()
                        }
                    }
                }
            }

            HStack {
                if diagnosis.crashReportURL != nil {
                    Button("Reveal Crash Report") {
                        model.revealCrashReport(diagnosis)
                    }
                }
                Spacer()
                Button("Open Console") {
                    model.dismissCrashDiagnosis()
                    model.showConsole = true
                }
                Button("Close") {
                    model.dismissCrashDiagnosis()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
