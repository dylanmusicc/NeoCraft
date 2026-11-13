import Foundation

struct PreparedGame: Sendable {
    var details: MinecraftVersionDetails
    var clientJar: URL
    var classpath: [URL]
    var nativesDirectory: URL
    var assetsDirectory: URL
    var gameDirectory: URL
    var loggingArgument: String?
    var launchVersionName: String
    var versionType: String
    var baseVersionID: String
}

struct ResolvedVersion: Sendable {
    var details: MinecraftVersionDetails
    var fabricLoaderVersion: String?
}

enum InstallerError: LocalizedError, Sendable {
    case missingClient(String)
    case missingAssetIndex(String)
    case unsupportedArchitecture(String)
    case invalidLibrary(String)
    case extraction(String)
    case missingJava(String)

    var errorDescription: String? {
        switch self {
        case .missingClient(let version):
            return "Mojang did not provide a client jar for \(version)."
        case .missingAssetIndex(let version):
            return "Mojang did not provide an asset index for \(version)."
        case .unsupportedArchitecture(let version):
            return "Minecraft \(version) does not ship Apple Silicon (arm64) native libraries. Choose a newer version."
        case .invalidLibrary(let name):
            return "Invalid library entry: \(name)"
        case .extraction(let detail):
            return "Could not extract native libraries: \(detail)"
        case .missingJava(let path):
            return "Java was not found at \(path)."
        }
    }
}

actor GameInstaller {
    private let versions: VersionService
    private let fabric: FabricService

    init(versions: VersionService, fabric: FabricService) {
        self.versions = versions
        self.fabric = fabric
    }

    func resolve(instance: GameInstance) async throws -> ResolvedVersion {
        let vanilla = try await versions.details(for: instance.minecraftVersion)
        guard instance.loader == .fabric else {
            return ResolvedVersion(details: vanilla, fabricLoaderVersion: nil)
        }

        let loader = try await fabric.latestLoader(for: instance.minecraftVersion)
        let selectedLoader = instance.fabricLoaderVersion ?? loader.version
        let profile = try await fabric.profile(
            gameVersion: instance.minecraftVersion,
            loaderVersion: selectedLoader
        )
        return ResolvedVersion(
            details: VersionMerger.merge(vanilla: vanilla, fabric: profile),
            fabricLoaderVersion: selectedLoader
        )
    }

    func prepare(
        instance: GameInstance,
        resolved: ResolvedVersion,
        concurrency: Int,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> PreparedGame {
        let details = resolved.details
        try AppPaths.ensureDirectories()
        let gameDirectory = instance.gameDirectory
        let nativesDirectory = AppPaths.nativesDirectory(instance.id)
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nativesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: AppPaths.libraries, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: AppPaths.assetObjects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: AppPaths.assetIndexes, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: AppPaths.logConfigs, withIntermediateDirectories: true)

        let context = MinecraftRuleContext.current
        progress(ProgressUpdate(fraction: 0.01, detail: "Resolving libraries for \(details.id)…"))

        guard let clientDownload = details.clientDownload else {
            throw InstallerError.missingClient(details.id)
        }
        guard let assetIndexReference = details.assetIndex, let assetURL = URL(string: assetIndexReference.url) else {
            throw InstallerError.missingAssetIndex(details.id)
        }

        let baseVersionID = details.inheritsFrom ?? details.id
        let clientJar = AppPaths.versions
            .appendingPathComponent(baseVersionID, isDirectory: true)
            .appendingPathComponent("\(baseVersionID).jar", isDirectory: false)

        let assetIndexFile = AppPaths.assetIndexes.appendingPathComponent("\(assetIndexReference.id).json", isDirectory: false)
        let indexRequest = DownloadRequest(
            url: assetURL,
            destination: assetIndexFile,
            checksum: FileChecksum(algorithm: .sha1, value: assetIndexReference.sha1),
            expectedSize: assetIndexReference.size,
            label: "Asset index"
        )
        progress(ProgressUpdate(fraction: 0.02, detail: "Fetching asset index…"))
        try await Downloader.download(indexRequest)

        guard let indexData = try? Data(contentsOf: assetIndexFile) else {
            throw InstallerError.missingAssetIndex(details.id)
        }
        let assetIndex: MinecraftAssetIndex
        do {
            assetIndex = try JSONDecoder().decode(MinecraftAssetIndex.self, from: indexData)
        } catch {
            throw InstallerError.missingAssetIndex(details.id)
        }

        let libraryResolution = try resolveLibraries(details: details, context: context)
        progress(ProgressUpdate(fraction: 0.03, detail: "Preparing game files…"))

        var requests: [String: DownloadRequest] = [:]
        func add(_ request: DownloadRequest) {
            requests[request.destination.path] = request
        }

        add(
            DownloadRequest(
                url: try clientDownloadURL(clientDownload, versionID: details.id),
                destination: clientJar,
                checksum: clientDownload.sha1.map { FileChecksum(algorithm: .sha1, value: $0) },
                expectedSize: clientDownload.size,
                label: "\(details.id) client"
            )
        )

        for download in libraryResolution.downloads {
            add(download)
        }

        var loggingArgument: String?
        if let logging = details.logging?.client {
            if let fileURL = URL(string: logging.file.url) {
                let name = logging.file.id ?? logging.file.path.map { ($0 as NSString).lastPathComponent }
                    ?? fileURL.lastPathComponent
                let destination = AppPaths.logConfigs.appendingPathComponent(name, isDirectory: false)
                add(
                    DownloadRequest(
                        url: fileURL,
                        destination: destination,
                        checksum: logging.file.sha1.map { FileChecksum(algorithm: .sha1, value: $0) },
                        expectedSize: logging.file.size,
                        label: "Logging configuration"
                    )
                )
                loggingArgument = logging.argument.replacingOccurrences(of: "${path}", with: destination.path)
            }
        }

        for (_, object) in assetIndex.objects {
            let destination = AppPaths.assetObjects
                .appendingPathComponent(String(object.hash.prefix(2)), isDirectory: true)
                .appendingPathComponent(object.hash, isDirectory: false)
            guard let url = URL(string: "https://resources.download.minecraft.net/\(object.hash.prefix(2))/\(object.hash)") else {
                continue
            }
            add(
                DownloadRequest(
                    url: url,
                    destination: destination,
                    checksum: FileChecksum(algorithm: .sha1, value: object.hash),
                    expectedSize: object.size,
                    label: "Asset \(object.hash.prefix(8))"
                )
            )
        }

        let allRequests = Array(requests.values)
        let throttle = ProgressThrottle()
        let downloadProgress: @Sendable (Int, Int, String) -> Void = { completed, total, label in
            guard throttle.shouldReport(completed: completed, total: total) else { return }
            let fraction = total > 0 ? Double(completed) / Double(total) : 0
            progress(
                ProgressUpdate(
                    fraction: 0.03 + fraction * 0.87,
                    detail: "Downloading game files (\(completed)/\(total)) · \(label)"
                )
            )
        }

        try await Downloader.downloadMany(
            allRequests,
            concurrency: max(1, min(16, concurrency)),
            progress: downloadProgress
        )

        progress(ProgressUpdate(fraction: 0.92, detail: "Extracting Apple Silicon native libraries…"))
        try extractNatives(
            jars: libraryResolution.nativeDownloads,
            into: nativesDirectory
        )

        if assetIndex.virtual == true || assetIndex.mapToResources == true {
            progress(ProgressUpdate(fraction: 0.96, detail: "Linking legacy assets…"))
            try linkLegacyAssets(
                index: assetIndex,
                versionName: details.assets ?? details.id,
                gameDirectory: gameDirectory
            )
        }

        if details.id != baseVersionID {
            let versionDirectory = AppPaths.versions.appendingPathComponent(details.id, isDirectory: true)
            try? FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
            if let encoded = try? JSONEncoder().encode(details) {
                try? encoded.write(
                    to: versionDirectory.appendingPathComponent("\(details.id).json"),
                    options: .atomic
                )
            }
        }

        var classpath = libraryResolution.classpath
        classpath.append(clientJar)

        progress(ProgressUpdate(fraction: 1, detail: "Game files are ready"))
        return PreparedGame(
            details: details,
            clientJar: clientJar,
            classpath: classpath,
            nativesDirectory: nativesDirectory,
            assetsDirectory: AppPaths.assets,
            gameDirectory: gameDirectory,
            loggingArgument: loggingArgument,
            launchVersionName: details.id,
            versionType: (details.type == "snapshot") ? "snapshot" : "release",
            baseVersionID: baseVersionID
        )
    }

    // MARK: - Libraries

    private struct Coordinate {
        var group: String
        var artifact: String
        var version: String
        var classifier: String?
        var fileExtension: String

        var baseKey: String { "\(group):\(artifact)" }

        var path: String {
            var filename = "\(artifact)-\(version)"
            if let classifier, !classifier.isEmpty {
                filename += "-\(classifier)"
            }
            filename += ".\(fileExtension)"
            return "\(group.replacingOccurrences(of: ".", with: "/"))/\(artifact)/\(version)/\(filename)"
        }

        init?(mavenName: String) {
            var name = mavenName
            var fileExtension = "jar"
            if let atIndex = name.lastIndex(of: "@") {
                fileExtension = String(name[name.index(after: atIndex)...])
                name = String(name[..<atIndex])
            }
            let pieces = name.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard pieces.count >= 3 else { return nil }
            group = pieces[0]
            artifact = pieces[1]
            version = pieces[2]
            classifier = pieces.count > 3 && !pieces[3].isEmpty ? pieces[3] : nil
            self.fileExtension = fileExtension.isEmpty ? "jar" : fileExtension
        }
    }

    private struct LibraryResolution {
        var classpath: [URL]
        var downloads: [DownloadRequest]
        var nativeDownloads: [URL]
    }

    private func resolveLibraries(
        details: MinecraftVersionDetails,
        context: MinecraftRuleContext
    ) throws -> LibraryResolution {
        struct Candidate {
            var library: MinecraftLibrary
            var coordinate: Coordinate
            var isNativeOnly: Bool
        }

        var candidates: [Candidate] = []
        for library in details.allLibraries {
            guard (library.rules ?? []).allows(context) else { continue }
            guard let coordinate = Coordinate(mavenName: library.name) else {
                throw InstallerError.invalidLibrary(library.name)
            }
            let nativeOnly = (library.natives == nil)
                && (coordinate.classifier?.contains("natives") == true)
            if nativeOnly {
                let classifier = coordinate.classifier ?? ""
                if classifier.contains("windows") || classifier.contains("linux") {
                    continue
                }
                if context.osArch == "arm64" && classifier.contains("x86") {
                    continue
                }
            }
            candidates.append(Candidate(library: library, coordinate: coordinate, isNativeOnly: nativeOnly))
        }

        var nativeBasesWithARM64 = Set<String>()
        for candidate in candidates where candidate.isNativeOnly {
            if candidate.coordinate.classifier?.contains("arm64") == true {
                nativeBasesWithARM64.insert(candidate.coordinate.baseKey)
            }
        }

        var classpath: [URL] = []
        var classpathPaths = Set<String>()
        var downloads: [String: DownloadRequest] = [:]
        var nativeJars: [String: URL] = [:]
        var sawARM64Native = false
        var sawAnyNative = false

        func addDownload(_ request: DownloadRequest) {
            downloads[request.destination.path] = request
        }

        for candidate in candidates {
            let library = candidate.library
            let coordinate = candidate.coordinate
            let isNative = candidate.isNativeOnly
                || (library.natives != nil && library.natives?[context.osName] != nil)

            if isNative {
                if candidate.isNativeOnly,
                   context.osArch == "arm64",
                   nativeBasesWithARM64.contains(coordinate.baseKey),
                   coordinate.classifier?.contains("arm64") != true {
                    continue
                }

                if let classifier = nativeClassifier(
                    library: library,
                    coordinate: coordinate,
                    context: context
                ) {
                    if classifier.contains("arm64") {
                        sawARM64Native = true
                    }
                    sawAnyNative = true

                    let nativeInfo: MinecraftDownloadInfo? = {
                        if candidate.isNativeOnly, let artifact = library.downloads?.artifact {
                            return artifact
                        }
                        return library.downloads?.classifiers?[classifier]
                    }()

                    let destination: URL
                    let url: URL
                    var checksum: FileChecksum?
                    var expectedSize: Int64?

                    if let nativeInfo {
                        guard let remote = URL(string: nativeInfo.url) else {
                            throw InstallerError.invalidLibrary(library.name)
                        }
                        let relative = safeRelativePath(nativeInfo.path) ?? coordinate.path
                        destination = AppPaths.libraries.appendingPathComponent(relative)
                        url = remote
                        checksum = nativeInfo.sha1.map { FileChecksum(algorithm: .sha1, value: $0) }
                        expectedSize = nativeInfo.size
                    } else {
                        var nativeCoordinate = coordinate
                        nativeCoordinate.classifier = classifier
                        let base = normalizedBase(library.url)
                        guard let remote = URL(string: base + nativeCoordinate.path) else {
                            throw InstallerError.invalidLibrary(library.name)
                        }
                        destination = AppPaths.libraries.appendingPathComponent(nativeCoordinate.path)
                        url = remote
                        checksum = library.sha1.map { FileChecksum(algorithm: .sha1, value: $0) }
                        expectedSize = library.size
                    }
                    addDownload(
                        DownloadRequest(
                            url: url,
                            destination: destination,
                            checksum: checksum,
                            expectedSize: expectedSize,
                            label: destination.lastPathComponent
                        )
                    )
                    nativeJars[destination.path] = destination
                    // LWJGL 3.4 ships native libraries in platform-scoped jars
                    // (macos/arm64/…) and extracts them from the classpath at
                    // runtime. Keep the jar on the classpath as well as unpacking
                    // it into the natives directory for older LWJGL versions.
                    appendClasspath(destination, to: &classpath, seen: &classpathPaths)
                }
            }

            if candidate.isNativeOnly {
                continue
            }

            if library.natives != nil && library.natives?[context.osName] != nil {
                if let artifact = library.downloads?.artifact {
                    let relative = safeRelativePath(artifact.path) ?? coordinate.path
                    let destination = AppPaths.libraries.appendingPathComponent(relative)
                    if let url = URL(string: artifact.url) {
                        addDownload(
                            DownloadRequest(
                                url: url,
                                destination: destination,
                                checksum: artifact.sha1.map { FileChecksum(algorithm: .sha1, value: $0) },
                                expectedSize: artifact.size,
                                label: destination.lastPathComponent
                            )
                        )
                        appendClasspath(destination, to: &classpath, seen: &classpathPaths)
                    }
                }
                continue
            }

            let info = library.downloads?.artifact
                ?? MinecraftDownloadInfo(
                    path: coordinate.path,
                    sha1: library.sha1,
                    size: library.size,
                    url: normalizedBase(library.url) + coordinate.path,
                    id: nil
                )

            guard let remote = URL(string: info.url) else {
                throw InstallerError.invalidLibrary(library.name)
            }
            let relative = safeRelativePath(info.path) ?? coordinate.path
            let destination = AppPaths.libraries.appendingPathComponent(relative)
            addDownload(
                DownloadRequest(
                    url: remote,
                    destination: destination,
                    checksum: info.sha1.map { FileChecksum(algorithm: .sha1, value: $0) },
                    expectedSize: info.size,
                    label: destination.lastPathComponent
                )
            )
            appendClasspath(destination, to: &classpath, seen: &classpathPaths)
        }

        if context.osArch == "arm64" && sawAnyNative && !sawARM64Native {
            throw InstallerError.unsupportedArchitecture(details.id)
        }

        return LibraryResolution(
            classpath: classpath,
            downloads: Array(downloads.values),
            nativeDownloads: Array(nativeJars.values)
        )
    }

    private func appendClasspath(_ url: URL, to classpath: inout [URL], seen: inout Set<String>) {
        let path = url.standardizedFileURL.path
        guard !seen.contains(path) else { return }
        seen.insert(path)
        classpath.append(url)
    }

    private func nativeClassifier(
        library: MinecraftLibrary,
        coordinate: Coordinate,
        context: MinecraftRuleContext
    ) -> String? {
        if let natives = library.natives, let template = natives[context.osName] {
            let classifier = template.replacingOccurrences(of: "${arch}", with: context.osArch == "arm64" ? "arm64" : "64")
            if context.osArch == "arm64" && classifier.contains("64") && !classifier.contains("arm64") && template.contains("${arch}") {
                return nil
            }
            return classifier
        }
        if let classifier = coordinate.classifier, classifier.contains("natives") {
            return classifier
        }
        return nil
    }

    private func normalizedBase(_ base: String?) -> String {
        let value = base ?? "https://libraries.minecraft.net/"
        return value.hasSuffix("/") ? value : value + "/"
    }

    private func clientDownloadURL(_ info: MinecraftDownloadInfo, versionID: String) throws -> URL {
        guard let url = URL(string: info.url), url.scheme != nil else {
            throw InstallerError.missingClient(versionID)
        }
        return url
    }

    private func safeRelativePath(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        guard !path.hasPrefix("/"), !path.contains("..") else { return nil }
        return path
    }

    private func extractNatives(jars: [URL], into directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try? fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for jar in jars {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-o", "-q", jar.path, "-d", directory.path, "-x", "META-INF/*"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                throw InstallerError.extraction("Could not run unzip for \(jar.lastPathComponent).")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let output = String(data: data, encoding: .utf8) ?? ""
                throw InstallerError.extraction(output.isEmpty ? jar.lastPathComponent : output)
            }
        }
    }

    private func linkLegacyAssets(
        index: MinecraftAssetIndex,
        versionName: String,
        gameDirectory: URL
    ) throws {
        let fileManager = FileManager.default
        let virtualRoot = AppPaths.assetVirtual.appendingPathComponent(versionName, isDirectory: true)
        try fileManager.createDirectory(at: virtualRoot, withIntermediateDirectories: true)

        for (name, object) in index.objects {
            let source = AppPaths.assetObjects
                .appendingPathComponent(String(object.hash.prefix(2)), isDirectory: true)
                .appendingPathComponent(object.hash)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            if index.virtual == true {
                let destination = virtualRoot.appendingPathComponent(name)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.copyItem(at: source, to: destination)
                }
            }
            if index.mapToResources == true {
                let destination = gameDirectory
                    .appendingPathComponent("resources", isDirectory: true)
                    .appendingPathComponent(name)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.copyItem(at: source, to: destination)
                }
            }
        }
    }
}

final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPercent = -1

    func shouldReport(completed: Int, total: Int) -> Bool {
        guard total > 0 else { return false }
        let percent = Int((Double(completed) / Double(total)) * 100)
        lock.lock()
        defer { lock.unlock() }
        guard percent != lastPercent else { return false }
        lastPercent = percent
        return true
    }
}
