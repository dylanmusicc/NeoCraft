import Foundation

struct JavaRuntime: Identifiable, Hashable, Sendable {
    var id: String { executablePath }
    var name: String
    var version: String
    var majorVersion: Int
    var architecture: String
    var homePath: String
    var executablePath: String
    var isManaged: Bool

    var isAppleSilicon: Bool {
        architecture.localizedCaseInsensitiveContains("aarch64")
            || architecture.localizedCaseInsensitiveContains("arm64")
    }
}

enum JavaRuntimeError: LocalizedError, Sendable {
    case noBuildForVersion(Int)
    case downloadFailed(String)
    case extractionFailed(String)
    case validationFailed(String)
    case notManaged(String)

    var errorDescription: String? {
        switch self {
        case .noBuildForVersion(let major):
            return "Eclipse Temurin does not publish a macOS aarch64 JDK \(major). Choose another runtime in Settings."
        case .downloadFailed(let detail):
            return "The Java runtime could not be downloaded: \(detail)"
        case .extractionFailed(let detail):
            return "The Java runtime could not be extracted: \(detail)"
        case .validationFailed(let path):
            return "The Java runtime at \(path) could not be started."
        case .notManaged(let path):
            return "\(path) is not managed by NeoCraft."
        }
    }
}

actor JavaRuntimeManager {
    private struct JavaProbe {
        var version: String
        var major: Int
        var architecture: String
        var vendor: String
    }

    private struct AdoptiumAsset: Decodable {
        var binary: AdoptiumBinary
        var releaseName: String?

        enum CodingKeys: String, CodingKey {
            case binary
            case releaseName = "release_name"
        }
    }

    private struct AdoptiumBinary: Decodable {
        var package: AdoptiumPackage
        var imageType: String?
        var os: String?
        var architecture: String?

        enum CodingKeys: String, CodingKey {
            case package
            case imageType = "image_type"
            case os
            case architecture
        }
    }

    private struct AdoptiumPackage: Decodable {
        var link: String
        var checksum: String
        var name: String
        var size: Int64?
    }

    private struct InstalledMarker: Codable {
        var majorVersion: Int
        var version: String
        var installedAt: Date
    }

    func discoverRuntimes() -> [JavaRuntime] {
        var homes = Set<String>()

        for directory in managedHomeCandidates() {
            homes.insert(directory.path)
        }
        for root in systemJVMHomes() {
            homes.insert(root.path)
        }
        for path in javaHomeToolPaths() {
            homes.insert(path)
        }

        var runtimes: [JavaRuntime] = []
        for home in homes.sorted() {
            let executable = URL(fileURLWithPath: home).appendingPathComponent("bin/java").path
            guard FileManager.default.isExecutableFile(atPath: executable) else { continue }
            guard let probe = probe(home: home), probe.major > 0 else { continue }
            let managed = home.hasPrefix(AppPaths.runtime.path)
            let vendor = managed ? "Eclipse Temurin" : (probe.vendor.isEmpty ? "Java" : probe.vendor)
            runtimes.append(
                JavaRuntime(
                    name: "\(vendor) \(probe.version)",
                    version: probe.version,
                    majorVersion: probe.major,
                    architecture: probe.architecture,
                    homePath: home,
                    executablePath: executable,
                    isManaged: managed
                )
            )
        }

        return runtimes.sorted {
            if $0.majorVersion != $1.majorVersion { return $0.majorVersion > $1.majorVersion }
            if $0.isManaged != $1.isManaged { return $0.isManaged && !$1.isManaged }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func validateExecutable(at path: String) -> JavaRuntime? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let home = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        guard let probe = probe(home: home) else { return nil }
        return JavaRuntime(
            name: "\(probe.vendor.isEmpty ? "Java" : probe.vendor) \(probe.version)",
            version: probe.version,
            majorVersion: probe.major,
            architecture: probe.architecture,
            homePath: home,
            executablePath: path,
            isManaged: home.hasPrefix(AppPaths.runtime.path)
        )
    }

    func runtime(executablePath: String) -> JavaRuntime? {
        validateExecutable(at: executablePath)
    }

    func ensureRuntime(
        major: Int,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> JavaRuntime {
        progress(ProgressUpdate(fraction: nil, detail: "Checking installed Java \(major) runtimes…"))
        let runtimes = discoverRuntimes()
        if let existing = runtimes.first(where: { $0.majorVersion == major && $0.isAppleSilicon }) {
            progress(ProgressUpdate(fraction: 1, detail: "Using \(existing.name)"))
            return existing
        }

        let managedRoot = managedRoot(for: major)
        if FileManager.default.isExecutableFile(atPath: managedRoot.appendingPathComponent("Contents/Home/bin/java").path),
           let validated = validateExecutable(at: managedRoot.appendingPathComponent("Contents/Home/bin/java").path) {
            progress(ProgressUpdate(fraction: 1, detail: "Using \(validated.name)"))
            return validated
        }

        progress(ProgressUpdate(fraction: nil, detail: "Finding Eclipse Temurin \(major) for Apple Silicon…"))
        let asset = try await adoptiumAsset(major: major)
        guard let packageURL = URL(string: asset.binary.package.link) else {
            throw JavaRuntimeError.noBuildForVersion(major)
        }

        try FileManager.default.createDirectory(at: AppPaths.runtime, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: AppPaths.cache, withIntermediateDirectories: true)
        let archive = AppPaths.cache.appendingPathComponent(asset.binary.package.name)

        let request = DownloadRequest(
            url: packageURL,
            destination: archive,
            checksum: FileChecksum(algorithm: .sha256, value: asset.binary.package.checksum),
            expectedSize: asset.binary.package.size,
            label: "Temurin JDK \(major)"
        )

        do {
            try await Downloader.download(request) { fraction in
                progress(ProgressUpdate(fraction: fraction * 0.9, detail: "Downloading Temurin JDK \(major)…"))
            }
        } catch {
            throw JavaRuntimeError.downloadFailed(error.localizedDescription)
        }

        progress(ProgressUpdate(fraction: 0.92, detail: "Extracting Java runtime…"))
        let extractionRoot = AppPaths.runtime.appendingPathComponent(".extract-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: extractionRoot)
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractionRoot) }

        do {
            try runProcess(
                executable: "/usr/bin/tar",
                arguments: ["-xzf", archive.path, "-C", extractionRoot.path]
            )
        } catch {
            throw JavaRuntimeError.extractionFailed(error.localizedDescription)
        }

        guard let extractedHome = findJavaHome(in: extractionRoot) else {
            throw JavaRuntimeError.extractionFailed("The archive did not contain a JDK home directory.")
        }
        let contents = extractedHome.deletingLastPathComponent()

        try? FileManager.default.removeItem(at: managedRoot)
        try FileManager.default.createDirectory(at: managedRoot, withIntermediateDirectories: true)
        do {
            try FileManager.default.moveItem(at: contents, to: managedRoot.appendingPathComponent("Contents", isDirectory: true))
        } catch {
            throw JavaRuntimeError.extractionFailed(error.localizedDescription)
        }

        let executable = managedRoot.appendingPathComponent("Contents/Home/bin/java").path
        _ = try? runProcess(executable: "/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", managedRoot.path], ignoreFailure: true)

        guard let runtime = validateExecutable(at: executable) else {
            throw JavaRuntimeError.validationFailed(executable)
        }

        let marker = InstalledMarker(majorVersion: major, version: runtime.version, installedAt: Date())
        if let data = try? JSONEncoder().encode(marker) {
            try? data.write(to: managedRoot.appendingPathComponent("runtime.json"), options: .atomic)
        }

        try? FileManager.default.removeItem(at: archive)
        progress(ProgressUpdate(fraction: 1, detail: "Installed \(runtime.name)"))
        return runtime
    }

    func removeRuntime(_ runtime: JavaRuntime) throws {
        guard runtime.isManaged else {
            throw JavaRuntimeError.notManaged(runtime.homePath)
        }
        let managedRoot = URL(fileURLWithPath: runtime.homePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard managedRoot.path.hasPrefix(AppPaths.runtime.path) else {
            throw JavaRuntimeError.notManaged(runtime.homePath)
        }
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: managedRoot, resultingItemURL: &resultingURL)
    }

    // MARK: - Adoptium

    private func adoptiumAsset(major: Int) async throws -> AdoptiumAsset {
        let url = try HTTPClient.url(
            "\(AppConstants.adoptiumBase)/assets/latest/\(major)/hotspot",
            query: [
                URLQueryItem(name: "architecture", value: "aarch64"),
                URLQueryItem(name: "image_type", value: "jdk"),
                URLQueryItem(name: "os", value: "mac"),
                URLQueryItem(name: "vendor", value: "eclipse")
            ]
        )
        let response = try await HTTPClient.get(url)
        let data = try HTTPClient.requireSuccess(response)
        let assets = try HTTPClient.decode([AdoptiumAsset].self, from: data)
        let candidates = assets.filter {
            $0.binary.os == "mac"
                && $0.binary.architecture == "aarch64"
                && $0.binary.imageType == "jdk"
                && $0.binary.package.name.hasSuffix(".tar.gz")
        }
        guard let asset = candidates.first ?? assets.first(where: { $0.binary.package.name.hasSuffix(".tar.gz") }) else {
            throw JavaRuntimeError.noBuildForVersion(major)
        }
        return asset
    }

    private func managedRoot(for major: Int) -> URL {
        AppPaths.runtime.appendingPathComponent("temurin-\(major)-aarch64", isDirectory: true)
    }

    private func managedHomeCandidates() -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: AppPaths.runtime,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.compactMap { directory in
            let home = directory.appendingPathComponent("Contents/Home", isDirectory: true)
            let executable = home.appendingPathComponent("bin/java")
            return FileManager.default.isExecutableFile(atPath: executable.path) ? home : nil
        }
    }

    private func systemJVMHomes() -> [URL] {
        let roots = [
            URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Java/JavaVirtualMachines", isDirectory: true)
        ]
        var homes: [URL] = []
        for root in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                let home = entry.appendingPathComponent("Contents/Home", isDirectory: true)
                if FileManager.default.isExecutableFile(atPath: home.appendingPathComponent("bin/java").path) {
                    homes.append(home)
                }
            }
        }
        return homes
    }

    private func javaHomeToolPaths() -> [String] {
        guard let result = try? runProcess(executable: "/usr/libexec/java_home", arguments: ["-V"], ignoreFailure: true) else {
            return []
        }
        let text = result.output
        let regex = try? NSRegularExpression(pattern: "(/[^\\s]+?/Contents/Home)")
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex?.matches(in: text, range: range) ?? []
        return matches.compactMap { match in
            guard let matchRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private func findJavaHome(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "java", url.deletingLastPathComponent().lastPathComponent == "bin" {
                let home = url.deletingLastPathComponent().deletingLastPathComponent()
                if home.lastPathComponent == "Home" {
                    return home
                }
            }
        }
        return nil
    }

    // MARK: - Process helpers

    private struct ProcessOutput {
        var status: Int32
        var output: String
    }

    private func probe(home: String) -> JavaProbe? {
        let executable = URL(fileURLWithPath: home).appendingPathComponent("bin/java").path
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        guard let result = try? runProcess(
            executable: executable,
            arguments: ["-XshowSettings:properties", "-version"],
            ignoreFailure: true
        ) else { return nil }

        var version = ""
        var architecture = ""
        var vendor = ""
        for line in result.output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("java.version = ") {
                version = String(trimmed.dropFirst("java.version = ".count))
            } else if trimmed.hasPrefix("os.arch = ") {
                architecture = String(trimmed.dropFirst("os.arch = ".count))
            } else if trimmed.hasPrefix("java.vendor = ") {
                vendor = String(trimmed.dropFirst("java.vendor = ".count))
            }
        }
        if version.isEmpty {
            let pattern = "version \"([^\"]+)\""
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: result.output, range: NSRange(result.output.startIndex..., in: result.output)),
               let range = Range(match.range(at: 1), in: result.output) {
                version = String(result.output[range])
            }
        }
        guard !version.isEmpty else { return nil }
        return JavaProbe(
            version: version,
            major: majorVersion(from: version),
            architecture: architecture.isEmpty ? "unknown" : architecture,
            vendor: vendor
        )
    }

    private func majorVersion(from version: String) -> Int {
        let components = version.split(separator: ".")
        if components.first == "1", components.count > 1 {
            return Int(components[1]) ?? 8
        }
        return Int(components.first ?? "") ?? 0
    }

    @discardableResult
    private func runProcess(
        executable: String,
        arguments: [String],
        ignoreFailure: Bool = false
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw JavaRuntimeError.validationFailed(executable)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 && !ignoreFailure {
            throw JavaRuntimeError.extractionFailed(output.isEmpty ? "Process failed with status \(process.terminationStatus)." : output)
        }
        return ProcessOutput(status: process.terminationStatus, output: output)
    }
}
