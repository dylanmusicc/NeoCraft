import Foundation

/// Resolves the downloadable server software for the non-vanilla Java
/// server types: Paper (paperclip jar from PaperMC's API) and Fabric
/// (the Fabric installer, run once to scaffold a server directory).
enum ServerSoftwareError: LocalizedError, Sendable {
    case noPaperBuild(String)
    case noFabricLoader(String)
    case installerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPaperBuild(let version):
            return "PaperMC doesn't publish a build for Minecraft \(version)."
        case .noFabricLoader(let version):
            return "Fabric doesn't publish a loader for Minecraft \(version) yet."
        case .installerFailed(let detail):
            return "The Fabric installer failed: \(detail)"
        }
    }
}

/// PaperMC's v2 API: project → versions → builds → download URL.
struct PaperBuild: Sendable {
    let version: String
    let build: Int
    let url: URL
}

enum PaperService {
    /// The newest Paper build for a Minecraft version.
    static func latestBuild(for minecraftVersion: String) async throws -> PaperBuild {
        let base = "https://api.papermc.io/v2/projects/paper/versions/\(minecraftVersion)"
        let buildsURL = try HTTPClient.url(base)
        let data = try HTTPClient.requireSuccess(try await HTTPClient.get(buildsURL))
        struct Response: Decodable { let builds: [Int] }
        let builds = try HTTPClient.decode(Response.self, from: data).builds.sorted(by: >)
        guard let build = builds.first else {
            throw ServerSoftwareError.noPaperBuild(minecraftVersion)
        }
        let download = "\(base)/builds/\(build)/downloads/paper-\(minecraftVersion)-\(build).jar"
        return PaperBuild(version: minecraftVersion, build: build, url: try HTTPClient.url(download))
    }
}

/// Fabric's installer scaffolds a ready-to-run server folder: the launch
/// jar, `libraries/`, `versions/` and a downloaded vanilla server jar.
enum FabricServerInstaller {
    /// Latest stable Fabric installer version from the meta API.
    static func latestInstallerVersion() async throws -> String {
        let url = try HTTPClient.url("\(AppConstants.fabricMetaBase)/versions/installer")
        struct Info: Decodable { let version: String; let stable: Bool? }
        let data = try HTTPClient.requireSuccess(try await HTTPClient.get(url))
        let installers = try HTTPClient.decode([Info].self, from: data)
        return (installers.first(where: { $0.stable == true }) ?? installers[0]).version
    }

    static func installerJarURL(version: String) throws -> URL {
        try HTTPClient.url(
            "https://maven.fabricmc.net/net/fabricmc/fabric-installer/\(version)/fabric-installer-\(version).jar")
    }

    /// Runs `java -jar fabric-installer.jar server …` inside `directory`,
    /// producing `fabric-server-launch.jar` and friends. Returns the
    /// launch jar's path relative to the server folder.
    @discardableResult
    static func scaffold(
        directory: URL,
        minecraftVersion: String,
        loaderVersion: String,
        java: JavaRuntime,
        installerJar: URL,
        log: @escaping @Sendable (String, ConsoleLevel) -> Void
    ) async throws -> URL {
        let process = GameProcess()
        var environment = ProcessInfo.processInfo.environment
        environment["JAVA_HOME"] = java.homePath
        let javaBin = URL(fileURLWithPath: java.executablePath).deletingLastPathComponent().path
        environment["PATH"] = javaBin + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")

        let command = LaunchCommand(
            executable: URL(fileURLWithPath: java.executablePath),
            arguments: [
                "-jar", installerJar.path, "server",
                "-dir", directory.path,
                "-mcversion", minecraftVersion,
                "-loader", loaderVersion,
                "-downloadMinecraft",
            ],
            workingDirectory: directory,
            environment: environment
        )
        try await process.start(command: command, log: log)
        let status = await process.waitForExit()
        guard status == 0 else {
            throw ServerSoftwareError.installerFailed("exit status \(status)")
        }
        let launchJar = directory.appendingPathComponent("fabric-server-launch.jar")
        guard FileManager.default.fileExists(atPath: launchJar.path) else {
            throw ServerSoftwareError.installerFailed("no fabric-server-launch.jar was produced")
        }
        return launchJar
    }
}
