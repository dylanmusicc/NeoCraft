import Foundation

enum FabricError: LocalizedError, Sendable {
    case noLoaders(String)
    case invalidProfile

    var errorDescription: String? {
        switch self {
        case .noLoaders(let version):
            return "Fabric does not publish a loader for Minecraft \(version) yet. Pick a newer Fabric-supported version or use Vanilla."
        case .invalidProfile:
            return "Fabric returned an unreadable launcher profile."
        }
    }
}

actor VersionService {
    private var cachedManifest: MinecraftVersionManifest?

    private var manifestCacheFile: URL {
        AppPaths.root.appendingPathComponent("version_manifest_v2.json")
    }

    private var patchNotesCacheFile: URL {
        AppPaths.cache.appendingPathComponent("javaPatchNotes.json")
    }

    func manifest(forceRefresh: Bool = false) async throws -> MinecraftVersionManifest {
        if !forceRefresh, let cachedManifest {
            return cachedManifest
        }

        let fileManager = FileManager.default
        if !forceRefresh,
           fileManager.fileExists(atPath: manifestCacheFile.path),
           let attributes = try? fileManager.attributesOfItem(atPath: manifestCacheFile.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 1800,
           let data = try? Data(contentsOf: manifestCacheFile),
           let manifest = try? JSONDecoder().decode(MinecraftVersionManifest.self, from: data) {
            cachedManifest = manifest
            return manifest
        }

        do {
            let url = try HTTPClient.url(AppConstants.versionManifestURL)
            let response = try await HTTPClient.get(url)
            let data = try HTTPClient.requireSuccess(response)
            let manifest = try HTTPClient.decode(MinecraftVersionManifest.self, from: data)
            _ = try? AppPaths.ensureDirectories()
            try? data.write(to: manifestCacheFile, options: .atomic)
            cachedManifest = manifest
            return manifest
        } catch {
            if let data = try? Data(contentsOf: manifestCacheFile),
               let manifest = try? JSONDecoder().decode(MinecraftVersionManifest.self, from: data) {
                cachedManifest = manifest
                return manifest
            }
            throw error
        }
    }

    func details(for versionID: String) async throws -> MinecraftVersionDetails {
        let directory = AppPaths.versions.appendingPathComponent(versionID, isDirectory: true)
        let file = directory.appendingPathComponent("\(versionID).json", isDirectory: false)

        if let data = try? Data(contentsOf: file),
           let details = try? JSONDecoder().decode(MinecraftVersionDetails.self, from: data) {
            return details
        }

        let manifest = try await manifest()
        guard let summary = manifest.versions.first(where: { $0.id == versionID }) else {
            throw NetworkError.transport("Minecraft \(versionID) was not found in Mojang's version manifest.")
        }
        let url = try HTTPClient.url(summary.url)
        let response = try await HTTPClient.get(url)
        let data = try HTTPClient.requireSuccess(response)
        let details = try HTTPClient.decode(MinecraftVersionDetails.self, from: data)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        return details
    }

    func recentVersions(includeSnapshots: Bool, limit: Int = 60) async throws -> [MinecraftVersionSummary] {
        let manifest = try await manifest()
        return manifest.versions
            .filter { includeSnapshots || $0.isRelease }
            .prefix(limit)
            .map { $0 }
    }

    func patchNotes(limit: Int = 24) async throws -> [PatchNoteEntry] {
        let fileManager = FileManager.default
        var data: Data
        if fileManager.fileExists(atPath: patchNotesCacheFile.path),
           let attributes = try? fileManager.attributesOfItem(atPath: patchNotesCacheFile.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 3600,
           let cached = try? Data(contentsOf: patchNotesCacheFile) {
            data = cached
        } else {
            let url = try HTTPClient.url("\(AppConstants.launcherContentBase)/javaPatchNotes.json")
            let response = try await HTTPClient.get(url)
            data = try HTTPClient.requireSuccess(response)
            try? data.write(to: patchNotesCacheFile, options: .atomic)
        }

        let decoded = try HTTPClient.decode(PatchNotesFile.self, from: data)
        return Array(decoded.entries.prefix(limit))
    }

    func patchNoteDetail(for entry: PatchNoteEntry) async throws -> PatchNoteDetail {
        guard let contentPath = entry.contentPath else {
            return PatchNoteDetail(title: entry.title, version: entry.version, type: entry.type, body: entry.shortText, image: entry.image, date: entry.date)
        }
        let url = try HTTPClient.url("\(AppConstants.launcherContentBase)/\(contentPath)")
        let response = try await HTTPClient.get(url)
        let data = try HTTPClient.requireSuccess(response)
        return try HTTPClient.decode(PatchNoteDetail.self, from: data)
    }
}

actor FabricService {
    func loaders(for gameVersion: String) async throws -> [FabricLoaderReference] {
        let url = try HTTPClient.url("\(AppConstants.fabricMetaBase)/versions/loader/\(gameVersion)")
        let response = try await HTTPClient.get(url)
        let data = try HTTPClient.requireSuccess(response)
        let loaders = try HTTPClient.decode([FabricLoaderInfo].self, from: data)
        return loaders.map(\.loader)
    }

    func latestLoader(for gameVersion: String) async throws -> FabricLoaderReference {
        let loaders = try await loaders(for: gameVersion)
        guard !loaders.isEmpty else {
            throw FabricError.noLoaders(gameVersion)
        }
        return loaders.first(where: { $0.stable == true }) ?? loaders[0]
    }

    func profile(gameVersion: String, loaderVersion: String?) async throws -> MinecraftVersionDetails {
        let loader: FabricLoaderReference
        if let loaderVersion, !loaderVersion.isEmpty {
            loader = FabricLoaderReference(version: loaderVersion, stable: true)
        } else {
            loader = try await latestLoader(for: gameVersion)
        }

        let cacheDirectory = AppPaths.versions.appendingPathComponent("fabric-\(gameVersion)-\(loader.version)", isDirectory: true)
        let cacheFile = cacheDirectory.appendingPathComponent("fabric-loader-\(loader.version)-\(gameVersion).json")
        if let data = try? Data(contentsOf: cacheFile),
           let details = try? JSONDecoder().decode(MinecraftVersionDetails.self, from: data) {
            return details
        }

        let url = try HTTPClient.url("\(AppConstants.fabricMetaBase)/versions/loader/\(gameVersion)/\(loader.version)/profile/json")
        let response = try await HTTPClient.get(url)
        let data = try HTTPClient.requireSuccess(response)
        let details: MinecraftVersionDetails
        do {
            details = try JSONDecoder().decode(MinecraftVersionDetails.self, from: data)
        } catch {
            throw FabricError.invalidProfile
        }
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheFile, options: .atomic)
        return details
    }
}

enum VersionMerger {
    static func merge(vanilla: MinecraftVersionDetails, fabric: MinecraftVersionDetails) -> MinecraftVersionDetails {
        var merged = vanilla
        merged.id = fabric.id
        merged.inheritsFrom = vanilla.id
        merged.type = fabric.type ?? vanilla.type
        merged.mainClass = fabric.mainClass
        merged.releaseTime = fabric.releaseTime ?? vanilla.releaseTime
        merged.time = fabric.time ?? vanilla.time

        var libraries: [String: MinecraftLibrary] = [:]
        var order: [String] = []
        for library in vanilla.allLibraries + fabric.allLibraries {
            if libraries[library.name] == nil {
                order.append(library.name)
            }
            libraries[library.name] = library
        }
        merged.libraries = order.compactMap { libraries[$0] }

        let vanillaGame = vanilla.arguments?.game ?? []
        let fabricGame = fabric.arguments?.game ?? []
        let vanillaJVM = vanilla.arguments?.jvm ?? []
        let fabricJVM = fabric.arguments?.jvm ?? []
        if !vanillaGame.isEmpty || !fabricGame.isEmpty || !vanillaJVM.isEmpty || !fabricJVM.isEmpty {
            // Fabric profiles carry their own JVM arguments (e.g. loader
            // bootstrap flags) — dropping them breaks the launch.
            merged.arguments = MinecraftArguments(
                game: vanillaGame + fabricGame,
                jvm: vanillaJVM + fabricJVM
            )
        }
        if merged.assets == nil {
            merged.assets = vanilla.assets
        }
        if merged.assetIndex == nil {
            merged.assetIndex = vanilla.assetIndex
        }
        if merged.downloads == nil {
            merged.downloads = vanilla.downloads
        }
        if merged.javaVersion == nil {
            merged.javaVersion = vanilla.javaVersion
        }
        if merged.logging == nil {
            merged.logging = vanilla.logging
        }
        return merged
    }
}
