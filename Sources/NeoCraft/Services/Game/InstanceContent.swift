import Foundation

// MARK: - Instance content manager
//
// File-level operations for the Instance Detail Hub: mod JARs (enable /
// disable / delete / config lookup), shader & resource packs, mod profiles,
// per-instance performance config and A18 shader tuning. Everything here is
// synchronous file I/O kept off the main actor by callers when needed.

/// One entry in an instance's `/mods` folder — enabled `.jar` or disabled
/// `.jar.disabled`, with JAR metadata when it parses.
struct InstalledMod: Identifiable, Sendable {
    var id: String { fileURL.lastPathComponent }
    var fileURL: URL
    var fileName: String
    /// True when the file ends in `.jar` (Fabric will load it).
    var enabled: Bool
    var sizeBytes: Int64
    var info: ModJarInfo?

    var displayName: String { info?.name ?? fileName }
    var version: String { info?.version ?? "" }
    var loader: ModLoaderKind { info?.loader ?? .unknown }
    var modID: String { info?.modID ?? "" }
}

enum InstanceContent {

    // MARK: Mods

    static let modsFolder = "mods"
    static let disabledSuffix = ".disabled"

    /// Every mod JAR in `mods/`, enabled and disabled, sorted by name.
    static func installedMods(in instance: GameInstance) async -> [InstalledMod] {
        let directory = instance.gameDirectory
            .appendingPathComponent(modsFolder, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let candidates = entries.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasSuffix(".jar") || name.hasSuffix(".jar.disabled")
        }

        return await withTaskGroup(of: InstalledMod?.self) { group in
            for url in candidates {
                group.addTask {
                    let name = url.lastPathComponent
                    let enabled = name.lowercased().hasSuffix(".jar")
                    let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                    let info = await ModScanner.shared.inspectJar(at: url)
                    return InstalledMod(
                        fileURL: url,
                        fileName: name,
                        enabled: enabled,
                        sizeBytes: size,
                        info: info
                    )
                }
            }
            var mods: [InstalledMod] = []
            for await mod in group {
                if let mod { mods.append(mod) }
            }
            return mods.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    /// Renames `foo.jar` ↔ `foo.jar.disabled` — the standard launcher
    /// convention Fabric respects (only `.jar` files load).
    @discardableResult
    static func setMod(_ mod: InstalledMod, enabled: Bool) throws -> URL {
        let fm = FileManager.default
        let source = mod.fileURL
        let targetName: String
        if enabled {
            guard mod.fileName.lowercased().hasSuffix(disabledSuffix) else { return source }
            targetName = String(mod.fileName.dropLast(disabledSuffix.count))
        } else {
            guard mod.fileName.lowercased().hasSuffix(".jar") else { return source }
            targetName = mod.fileName + disabledSuffix
        }
        let target = source.deletingLastPathComponent()
            .appendingPathComponent(targetName)
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
        try fm.moveItem(at: source, to: target)
        return target
    }

    static func deleteMod(_ mod: InstalledMod) throws {
        try FileManager.default.removeItem(at: mod.fileURL)
    }

    /// Best-effort config file for a mod inside `config/`. Checks the mod id
    /// first, then the display name, then any config entry containing the id.
    static func modConfigURL(for mod: InstalledMod, in instance: GameInstance) -> URL? {
        let configRoot = instance.gameDirectory.appendingPathComponent("config", isDirectory: true)
        let candidates: [String] = {
            var names: [String] = []
            if !mod.modID.isEmpty { names.append(mod.modID) }
            let cleaned = mod.displayName
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
            if !cleaned.isEmpty, !names.contains(cleaned) { names.append(cleaned) }
            let fileStem = mod.fileName
                .replacingOccurrences(of: ".jar.disabled", with: "")
                .replacingOccurrences(of: ".jar", with: "")
                .lowercased()
            if !names.contains(fileStem) { names.append(fileStem) }
            return names
        }()

        for name in candidates {
            for ext in ["json", "toml", "cfg", "yaml", "yml"] {
                let file = configRoot.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: file.path) { return file }
            }
            let dir = configRoot.appendingPathComponent(name, isDirectory: true)
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
               let first = contents.sorted().first {
                return dir.appendingPathComponent(first)
            }
        }
        return nil
    }

    // MARK: Mod profiles

    struct ModProfile: Codable, Identifiable, Hashable, Sendable {
        var id: UUID
        var name: String
        /// File names (with `.disabled` suffix where applicable) that should
        /// be disabled when the profile is active.
        var disabledFiles: [String]
        var created: Date

        init(id: UUID = UUID(), name: String, disabledFiles: [String], created: Date = Date()) {
            self.id = id
            self.name = name
            self.disabledFiles = disabledFiles
            self.created = created
        }
    }

    private struct ProfileStore: Codable {
        var profiles: [ModProfile]
    }

    static func profilesFile(for instance: GameInstance) -> URL {
        AppPaths.instanceMetadataDirectory(instance.id)
            .appendingPathComponent("mod-profiles.json", isDirectory: false)
    }

    static func modProfiles(for instance: GameInstance) -> [ModProfile] {
        guard let data = try? Data(contentsOf: profilesFile(for: instance)),
              let store = try? JSONDecoder().decode(ProfileStore.self, from: data) else {
            return []
        }
        return store.profiles
    }

    static func saveModProfile(_ profile: ModProfile, for instance: GameInstance) throws {
        var profiles = modProfiles(for: instance)
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        try writeProfiles(profiles, for: instance)
    }

    static func deleteModProfile(_ profile: ModProfile, for instance: GameInstance) throws {
        var profiles = modProfiles(for: instance)
        profiles.removeAll { $0.id == profile.id }
        try writeProfiles(profiles, for: instance)
    }

    /// Applies a profile: enables every JAR not in `disabledFiles` and
    /// disables every JAR that is. Returns the number of files changed.
    @discardableResult
    static func applyModProfile(_ profile: ModProfile, to instance: GameInstance) throws -> Int {
        let directory = instance.gameDirectory
            .appendingPathComponent(modsFolder, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let disabled = Set(profile.disabledFiles.map { $0.lowercased() })
        var changed = 0
        for url in entries {
            let name = url.lastPathComponent
            let lower = name.lowercased()
            guard lower.hasSuffix(".jar") || lower.hasSuffix(".jar.disabled") else { continue }

            // Canonical jar name (strip .disabled) for set membership.
            let stem = lower.hasSuffix(disabledSuffix)
                ? String(lower.dropLast(disabledSuffix.count))
                : lower
            let shouldBeDisabled = disabled.contains(lower) || disabled.contains(stem + disabledSuffix) || disabled.contains(stem)

            if shouldBeDisabled && lower.hasSuffix(".jar") {
                _ = try setMod(InstalledMod(fileURL: url, fileName: name, enabled: true, sizeBytes: 0, info: nil), enabled: false)
                changed += 1
            } else if !shouldBeDisabled && lower.hasSuffix(disabledSuffix) {
                _ = try setMod(InstalledMod(fileURL: url, fileName: name, enabled: false, sizeBytes: 0, info: nil), enabled: true)
                changed += 1
            }
        }
        return changed
    }

    /// Captures the current enabled/disabled state as a new profile.
    static func captureProfile(named name: String, from mods: [InstalledMod]) -> ModProfile {
        ModProfile(
            name: name,
            disabledFiles: mods.filter { !$0.enabled }.map(\.fileName)
        )
    }

    private static func writeProfiles(_ profiles: [ModProfile], for instance: GameInstance) throws {
        let directory = AppPaths.instanceMetadataDirectory(instance.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ProfileStore(profiles: profiles))
            .write(to: profilesFile(for: instance), options: .atomic)
    }

    // MARK: Shader & resource packs

    /// A file inside `shaderpacks/` or `resourcepacks/`.
    struct AssetPack: Identifiable, Sendable {
        var id: String { fileURL.lastPathComponent }
        var fileURL: URL
        var fileName: String
        var folder: String       // "shaderpacks" | "resourcepacks"
        var enabled: Bool
        var sizeBytes: Int64
        var isArchive: Bool      // .zip file vs unpacked folder
    }

    static func assetPacks(inFolder folder: String, for instance: GameInstance) -> [AssetPack] {
        let directory = instance.gameDirectory.appendingPathComponent(folder, isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url in
            let name = url.lastPathComponent
            let lower = name.lowercased()
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let disabled = lower.hasSuffix(".disabled")
            let base = disabled ? String(lower.dropLast(disabledSuffix.count)) : lower
            let valid = base.hasSuffix(".zip") || isDir || (!disabled && !isDir && !base.contains("."))
            guard valid || disabled else { return nil }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            return AssetPack(
                fileURL: url,
                fileName: name,
                folder: folder,
                enabled: !disabled,
                sizeBytes: size,
                isArchive: base.hasSuffix(".zip")
            )
        }
        .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    @discardableResult
    static func setAssetPack(_ pack: AssetPack, enabled: Bool) throws -> URL {
        let fm = FileManager.default
        let source = pack.fileURL
        let name = pack.fileName
        let lower = name.lowercased()
        let targetName: String
        if enabled {
            guard lower.hasSuffix(disabledSuffix) else { return source }
            targetName = String(name.dropLast(disabledSuffix.count))
        } else {
            guard !lower.hasSuffix(disabledSuffix) else { return source }
            targetName = name + disabledSuffix
        }
        let target = source.deletingLastPathComponent().appendingPathComponent(targetName)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: source, to: target)
        return target
    }

    static func deleteAssetPack(_ pack: AssetPack) throws {
        try FileManager.default.removeItem(at: pack.fileURL)
    }

    // MARK: options.txt pack ordering

    /// Reorders the `resourcePacks:` list inside options.txt. Pack entries
    /// are stored as `file/<name>` or `folder/<name>`; disabled packs are
    /// still listed but ordered last by the game anyway.
    static func reorderResourcePack(_ packName: String, by offset: Int, in instance: GameInstance) throws {
        let optionsURL = instance.gameDirectory.appendingPathComponent("options.txt")
        var lines: [String] = []
        if let contents = try? String(contentsOf: optionsURL, encoding: .utf8) {
            lines = contents.components(separatedBy: .newlines)
        }
        guard let index = lines.firstIndex(where: { $0.hasPrefix("resourcePacks:") }) else { return }

        var packs = lines[index]
            .dropFirst("resourcePacks:".count)
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let packIndex = packs.firstIndex(where: { $0.contains(packName) }) else { return }
        let target = packIndex + offset
        guard packs.indices.contains(target) else { return }
        packs.swapAt(packIndex, target)
        lines[index] = "resourcePacks:[\(packs.joined(separator: ","))]"
        try lines.joined(separator: "\n").write(to: optionsURL, atomically: true, encoding: .utf8)
    }

    // MARK: Performance & shader config

    /// Writes the A18-optimized Iris shader profile into `config/iris.properties`.
    /// Keeps shaders but caps the expensive features that melt the fanless A18.
    static func applyA18ShaderConfig(to instance: GameInstance) throws -> URL {
        let configDir = instance.gameDirectory.appendingPathComponent("config", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let file = configDir.appendingPathComponent("iris.properties")

        var values: [String: String] = [:]
        if let contents = try? String(contentsOf: file, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                guard let eq = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { values[key] = value }
            }
        }

        values["enableShaders"] = "true"
        values["disableUpdateCheck"] = "true"
        values["maxShadowRenderDistance"] = "6"
        values["ambientOcclusion"] = "false"
        values["cloudQuality"] = "0"
        values["stochasticTransparency"] = "false"

        let text = values.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n") + "\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
