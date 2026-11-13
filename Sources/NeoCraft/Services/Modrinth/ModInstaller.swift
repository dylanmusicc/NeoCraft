import Foundation

/// A Modrinth-installed project whose latest compatible version differs
/// from the one recorded in the instance's installed manifest.
struct ModUpdate: Identifiable, Sendable {
    var projectID: String
    var title: String
    var type: ModrinthProjectType
    var installedVersionID: String
    var latest: ModrinthVersion

    var id: String { projectID }
}

/// Whether an installed project can be resolved for a different Minecraft
/// version — the data behind the smart upgrade breakdown.
struct ModCompatibility: Identifiable, Sendable {
    var projectID: String
    var title: String
    var type: ModrinthProjectType
    var compatible: Bool
    var latestVersion: ModrinthVersion?

    var id: String { projectID }
}

actor ModInstaller {
    private struct Target: Sendable {
        var projectID: String?
        var versionID: String?
        var fallbackTitle: String?
    }

    /// One installed project record — internal so the Instance Manager can
    /// join JAR files on disk with their Modrinth project metadata.
    struct InstalledRecord: Codable, Sendable {
        var projectID: String
        var filename: String
        var folder: String
        var versionID: String
        var projectTitle: String
        var installedAt: Date
    }

    private struct BoostMarker: Codable, Sendable {
        var installedAt: Date
        var gameVersion: String
        var loaderVersion: String?
        var projects: [String]
    }

    private let modrinth: ModrinthService

    init(modrinth: ModrinthService) {
        self.modrinth = modrinth
    }

    func installBoost(
        into instance: GameInstance,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> [String] {
        guard instance.loader == .fabric else {
            throw ModrinthError.requiresFabric
        }

        let slugs = ["fabric-api", "sodium", "lithium", "ferrite-core", "immediatelyfast"]
        var targets: [Target] = []
        for slug in slugs {
            let project = try await modrinth.project(idOrSlug: slug)
            targets.append(Target(projectID: project.id, versionID: nil, fallbackTitle: project.title))
        }

        let installed = try await installTargets(
            targets,
            into: instance,
            expectedCount: slugs.count,
            progress: { update in
                progress(ProgressUpdate(fraction: update.fraction, detail: update.detail))
            }
        )

        let marker = BoostMarker(
            installedAt: Date(),
            gameVersion: instance.minecraftVersion,
            loaderVersion: instance.fabricLoaderVersion,
            projects: installed
        )
        try FileManager.default.createDirectory(
            at: AppPaths.instanceMetadataDirectory(instance.id),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(marker)
        try data.write(to: AppPaths.boostMarker(instance.id), options: .atomic)
        return installed
    }

    /// Performance Pack: the Neo Boost core plus the heavier A18-oriented
    /// stack (ModernFix, C2ME). Optional extras are installed best-effort —
    /// a missing project never fails the install.
    func installPerformancePack(
        into instance: GameInstance,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> [String] {
        let installed = try await installBoost(into: instance, progress: progress)

        let extras = ["modernfix", "c2me-fabric"]
        var packInstalled = installed
        for slug in extras {
            do {
                let project = try await modrinth.project(idOrSlug: slug)
                let titles = try await installTargets(
                    [Target(projectID: project.id, versionID: nil, fallbackTitle: project.title)],
                    into: instance,
                    expectedCount: 1,
                    progress: { update in
                        progress(ProgressUpdate(
                            fraction: update.fraction,
                            detail: "Performance Pack · \(update.detail)"
                        ))
                    }
                )
                packInstalled.append(contentsOf: titles)
            } catch {
                // Optional extras must not sink the core boost install.
                continue
            }
        }
        return packInstalled
    }

    /// Ensures `fabric-api` is installed at the newest version compatible
    /// with the instance's Minecraft version. Safe to call on every launch
    /// and every instance save — `installTargets` short-circuits when the
    /// recorded version already matches Modrinth's latest.
    func ensureFabricAPI(for instance: GameInstance) async {
        guard instance.loader == .fabric else { return }
        do {
            let project = try await modrinth.project(idOrSlug: "fabric-api")
            _ = try await installTargets(
                [Target(projectID: project.id, versionID: nil, fallbackTitle: project.title)],
                into: instance,
                expectedCount: 1,
                progress: { _ in }
            )
        } catch {
            // Fabric API is required for Fabric mods, but a transient
            // Modrinth failure must never block a launch.
        }
    }

    /// Ensures the macOS input-fix mod is present for instances that opted in.
    /// Safe to call on every launch — already-installed projects short-circuit.
    func ensureInputFix(for instance: GameInstance) async {
        guard instance.macosInputFix, instance.loader == .fabric else { return }
        do {
            let project = try await modrinth.project(idOrSlug: "macos-input-fixes")
            _ = try await installTargets(
                [Target(projectID: project.id, versionID: nil, fallbackTitle: project.title)],
                into: instance,
                expectedCount: 1,
                progress: { _ in }
            )
        } catch {
            // Input fix is a nicety; never block a launch over it.
        }
    }

    /// Which installed projects have a compatible version for a *different*
    /// Minecraft version — used by the smart upgrade flow.
    func compatibility(
        for instance: GameInstance,
        targetVersion: String
    ) async -> [ModCompatibility] {
        let records = loadRecords(for: instance)
        guard !records.isEmpty else { return [] }

        let service = modrinth
        let loaderFilter = instance.loader == .fabric ? "fabric" : nil

        return await withTaskGroup(of: ModCompatibility?.self) { group in
            for record in records.values {
                group.addTask {
                    let type = ModrinthProjectType(folderName: record.folder) ?? .mod
                    let loader = type == .mod ? loaderFilter : nil
                    let versions = try? await service.versions(
                        projectID: record.projectID,
                        gameVersion: targetVersion,
                        loader: loader
                    )
                    let latest = versions?.first
                    return ModCompatibility(
                        projectID: record.projectID,
                        title: record.projectTitle,
                        type: type,
                        compatible: latest != nil,
                        latestVersion: latest
                    )
                }
            }

            var results: [ModCompatibility] = []
            for await item in group {
                if let item { results.append(item) }
            }
            return results.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    func install(
        hit: ModrinthSearchHit,
        versionID: String?,
        into instance: GameInstance,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> [String] {
        try await install(
            projectID: hit.projectID,
            versionID: versionID,
            type: hit.type,
            into: instance,
            progress: progress
        )
    }

    func install(
        projectID: String,
        versionID: String?,
        type: ModrinthProjectType,
        into instance: GameInstance,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> [String] {
        if type == .mod && instance.loader != .fabric {
            throw ModrinthError.requiresFabric
        }
        return try await installTargets(
            [Target(projectID: projectID, versionID: versionID, fallbackTitle: nil)],
            into: instance,
            expectedCount: 1,
            progress: progress
        )
    }

    func installedProjectIDs(for instance: GameInstance) -> Set<String> {
        Set(loadRecords(for: instance).keys)
    }

    /// All install records for an instance, keyed by Modrinth project id.
    func installedRecords(for instance: GameInstance) -> [String: InstalledRecord] {
        loadRecords(for: instance)
    }

    /// Compares every recorded install against the newest Modrinth version
    /// compatible with the instance's game version and loader.
    func checkForUpdates(in instance: GameInstance) async -> [ModUpdate] {
        let records = loadRecords(for: instance)
        guard !records.isEmpty else { return [] }

        let service = modrinth
        let loaderFilter = instance.loader == .fabric ? "fabric" : nil

        return await withTaskGroup(of: ModUpdate?.self) { group in
            for record in records.values {
                group.addTask {
                    let type = ModrinthProjectType(folderName: record.folder) ?? .mod
                    let loader = type == .mod ? loaderFilter : nil
                    guard let versions = try? await service.versions(
                        projectID: record.projectID,
                        gameVersion: instance.minecraftVersion,
                        loader: loader
                    ),
                    let latest = versions.first,
                    latest.id != record.versionID else {
                        return nil
                    }
                    return ModUpdate(
                        projectID: record.projectID,
                        title: record.projectTitle,
                        type: type,
                        installedVersionID: record.versionID,
                        latest: latest
                    )
                }
            }

            var updates: [ModUpdate] = []
            for await update in group {
                if let update {
                    updates.append(update)
                }
            }
            return updates.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }

    func remove(projectID: String, from instance: GameInstance) throws {
        var records = loadRecords(for: instance)
        guard let record = records.removeValue(forKey: projectID) else { return }
        let file = instance.gameDirectory
            .appendingPathComponent(record.folder)
            .appendingPathComponent(record.filename)
        if file.standardizedFileURL.path.hasPrefix(instance.gameDirectory.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: file)
        }
        try saveRecords(records, for: instance)
    }

    func isBoostInstalled(for instance: GameInstance) -> Bool {
        guard instance.neoBoost else { return false }
        guard FileManager.default.fileExists(atPath: AppPaths.boostMarker(instance.id).path),
              let data = try? Data(contentsOf: AppPaths.boostMarker(instance.id)),
              let marker = try? JSONDecoder().decode(BoostMarker.self, from: data) else {
            return false
        }
        guard marker.gameVersion == instance.minecraftVersion else { return false }
        let gameDirectory = instance.gameDirectory
        let records = loadRecords(for: instance)
        guard !records.isEmpty else { return false }

        let requiredTitles = ["fabric api", "sodium", "lithium", "ferrite", "immediatelyfast"]
        let installedTitles = records.values.map(\.projectTitle).joined(separator: " ").lowercased()
        guard requiredTitles.allSatisfy({ installedTitles.contains($0) }) else { return false }

        return records.values.allSatisfy { record in
            FileManager.default.fileExists(
                atPath: gameDirectory.appendingPathComponent(record.folder).appendingPathComponent(record.filename).path
            )
        }
    }

    private func installTargets(
        _ initial: [Target],
        into instance: GameInstance,
        expectedCount: Int,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> [String] {
        var queue = initial
        var expected = max(expectedCount, initial.count)
        var completed = 0
        var visited = Set<String>()
        var installedTitles: [String] = []
        var records = loadRecords(for: instance)
        let loader = instance.loader == .fabric ? "fabric" : ""

        progress(ProgressUpdate(fraction: 0, detail: "Resolving Modrinth projects…"))

        while !queue.isEmpty {
            try Task.checkCancellation()
            let target = queue.removeFirst()
            let project: ModrinthProject
            let version: ModrinthVersion

            if let versionID = target.versionID, !versionID.isEmpty {
                version = try await modrinth.version(id: versionID)
                project = try await modrinth.project(idOrSlug: version.projectID)
            } else if let projectID = target.projectID {
                let fetched = try await modrinth.project(idOrSlug: projectID)
                project = fetched
                let loaderFilter: String? = fetched.type == .mod
                    ? (loader.isEmpty ? nil : loader)
                    : nil
                let versions = try await modrinth.versions(
                    projectID: fetched.id,
                    gameVersion: instance.minecraftVersion,
                    loader: loaderFilter
                )
                guard let latest = versions.first else {
                    throw ModrinthError.noCompatibleVersion(
                        project: fetched.title,
                        gameVersion: instance.minecraftVersion,
                        loader: loaderFilter ?? ""
                    )
                }
                version = latest
            } else {
                throw ModrinthError.dependencyResolution("A dependency did not identify a project.")
            }

            let visitKey = "\(project.id):\(version.id)"
            if visited.contains(visitKey) {
                continue
            }
            visited.insert(visitKey)

            guard let file = version.primaryFile else {
                throw ModrinthError.noFiles(project: project.title)
            }

            let folder = AppPaths.folder(forProjectType: project.type, instance: instance)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let filename = sanitizeFilename(file.filename)
            let destination = folder.appendingPathComponent(filename)

            let oldRecord = records[project.id]
            if oldRecord?.versionID == version.id,
               FileManager.default.fileExists(atPath: destination.path) {
                completed += 1
                progress(ProgressUpdate(
                    fraction: Double(completed) / Double(max(expected, 1)),
                    detail: "\(project.title) is already installed"
                ))
                installedTitles.append(project.id)
                enqueueDependencies(
                    of: version,
                    project: project,
                    into: &queue,
                    expected: &expected
                )
                continue
            }

            progress(ProgressUpdate(
                fraction: max(0, Double(completed) / Double(max(expected, 1))),
                detail: "Downloading \(project.title)…"
            ))

            guard let remote = URL(string: file.url) else {
                throw ModrinthError.installFailed("Invalid file URL for \(project.title).")
            }
            let checksum = file.hashes?["sha1"].map { FileChecksum(algorithm: .sha1, value: $0) }
            let request = DownloadRequest(
                url: remote,
                destination: destination,
                checksum: checksum,
                expectedSize: file.size,
                label: filename
            )
            try await Downloader.download(request)

            if let oldRecord, oldRecord.filename != filename || oldRecord.folder != project.type.folderName {
                let oldURL = instance.gameDirectory
                    .appendingPathComponent(oldRecord.folder)
                    .appendingPathComponent(oldRecord.filename)
                if oldURL.standardizedFileURL.path.hasPrefix(instance.gameDirectory.standardizedFileURL.path) {
                    try? FileManager.default.removeItem(at: oldURL)
                }
            }

            records[project.id] = InstalledRecord(
                projectID: project.id,
                filename: filename,
                folder: project.type.folderName,
                versionID: version.id,
                projectTitle: project.title,
                installedAt: Date()
            )
            try saveRecords(records, for: instance)

            completed += 1
            installedTitles.append(project.id)
            progress(ProgressUpdate(
                fraction: Double(completed) / Double(max(expected, 1)),
                detail: "Installed \(project.title)"
            ))

            enqueueDependencies(of: version, project: project, into: &queue, expected: &expected)
        }

        try saveRecords(records, for: instance)
        progress(ProgressUpdate(fraction: 1, detail: "Mod installation complete"))
        return installedTitles
    }

    private func enqueueDependencies(
        of version: ModrinthVersion,
        project: ModrinthProject,
        into queue: inout [Target],
        expected: inout Int
    ) {
        for dependency in version.dependencies where dependency.isRequired {
            if dependency.versionID == nil && dependency.projectID == nil {
                continue
            }
            queue.append(Target(
                projectID: dependency.projectID,
                versionID: dependency.versionID,
                fallbackTitle: "\(project.title) dependency"
            ))
            expected += 1
        }
    }

    private func sanitizeFilename(_ filename: String) -> String {
        let last = URL(fileURLWithPath: filename).lastPathComponent
        let cleaned = last.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download.jar" : cleaned
    }

    private func recordsFile(for instance: GameInstance) -> URL {
        AppPaths.installedManifest(instance.id)
    }

    private func loadRecords(for instance: GameInstance) -> [String: InstalledRecord] {
        guard let data = try? Data(contentsOf: recordsFile(for: instance)) else { return [:] }
        return (try? JSONDecoder().decode([String: InstalledRecord].self, from: data)) ?? [:]
    }

    private func saveRecords(_ records: [String: InstalledRecord], for instance: GameInstance) throws {
        try FileManager.default.createDirectory(
            at: AppPaths.instanceMetadataDirectory(instance.id),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try data.write(to: recordsFile(for: instance), options: .atomic)
    }
}
