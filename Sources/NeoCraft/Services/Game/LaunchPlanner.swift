import Foundation

struct LaunchCommand: Sendable {
    var executable: URL
    var arguments: [String]
    var workingDirectory: URL
    var environment: [String: String]
}

enum LaunchPlanner {
    static func makeCommand(
        prepared: PreparedGame,
        instance: GameInstance,
        session: MinecraftSession,
        java: JavaRuntime,
        settings: AppSettings,
        thermalMode: ThermalMode,
        quickPlayAddress: String? = nil,
        quickPlayWorld: String? = nil,
        offline: Bool = false
    ) throws -> LaunchCommand {
        let details = prepared.details
        let memory = min(max(instance.memoryMB ?? settings.maxMemoryMB, 512), 6144)
        let initialHeap = min(settings.minMemoryMB, memory)

        var jvm: [String] = []
        #if os(macOS)
        jvm.append("-XstartOnFirstThread")
        #endif
        jvm.append("-Xms\(initialHeap)M")
        jvm.append("-Xmx\(memory)M")

        switch settings.garbageCollector {
        case .g1:
            jvm.append(contentsOf: [
                "-XX:+UseG1GC",
                "-XX:+ParallelRefProcEnabled",
                "-XX:MaxGCPauseMillis=100",
                "-XX:+UnlockExperimentalVMOptions",
                "-XX:+DisableExplicitGC",
                "-XX:+AlwaysPreTouch",
                "-XX:G1NewSizePercent=25",
                "-XX:G1MaxNewSizePercent=40",
                "-XX:G1HeapRegionSize=8M",
                "-XX:G1ReservePercent=20",
                "-XX:G1MixedGCCountTarget=4",
                "-XX:InitiatingHeapOccupancyPercent=15",
                "-XX:G1HeapWastePercent=5",
                "-XX:SurvivorRatio=32",
                "-XX:MaxTenuringThreshold=1",
                "-XX:+PerfDisableSharedMem"
            ])
        case .zgc:
            jvm.append(contentsOf: [
                "-XX:+UseZGC",
                "-XX:+UnlockExperimentalVMOptions",
                "-XX:+DisableExplicitGC",
                "-XX:+AlwaysPreTouch",
                "-XX:+PerfDisableSharedMem"
            ])
        }

        // Modern Mojang launcher profiles rely on these flags. They are added
        // explicitly because NeoCraft resolves JVM arguments itself to keep
        // native libraries in one predictable directory.
        if java.majorVersion >= 17 {
            jvm.append(contentsOf: ["--add-exports", "java.base/jdk.internal.misc=ALL-UNNAMED"])
        }
        if java.majorVersion >= 24 {
            jvm.append("--enable-native-access=ALL-UNNAMED")
        }
        jvm.append("-XX:StackShadowPages=32")
        // Cap off-heap/direct buffers so a modded 8 GB session cannot push the
        // Mac into swap territory.
        jvm.append("-XX:MaxDirectMemorySize=1024M")

        let nativesPath = prepared.nativesDirectory.path
        jvm.append(contentsOf: [
            "-Djava.library.path=\(nativesPath)",
            "-Djna.tmpdir=\(nativesPath)",
            "-Dorg.lwjgl.system.SharedLibraryExtractPath=\(nativesPath)",
            "-Dio.netty.native.workdir=\(nativesPath)",
            "-Dminecraft.launcher.brand=NeoCraft",
            "-Dminecraft.launcher.version=\(AppConstants.version)",
            "-Dminecraft.api.auth.host=https://api.minecraftservices.com",
            "-Dminecraft.api.account.host=https://api.mojang.com",
            "-Dminecraft.api.session.host=https://sessionserver.mojang.com",
            "-Dminecraft.api.services.host=https://api.minecraftservices.com"
        ])
        if let loggingArgument = prepared.loggingArgument {
            jvm.append(loggingArgument)
        }

        let extraJVM = CommandLineSplitter.split(instance.jvmArgs)
        jvm.append(contentsOf: extraJVM)

        jvm.append("-cp")
        jvm.append(prepared.classpath.map(\.path).joined(separator: ":"))

        let assetsIndex = details.assetIndexName ?? ""
        let legacyAssets = AppPaths.assetVirtual
            .appendingPathComponent(details.assets ?? details.id, isDirectory: true)
            .path
        let uuid = session.uuid.replacingOccurrences(of: "-", with: "").lowercased()

        let replacements: [String: String] = [
            "auth_player_name": session.name,
            "version_name": prepared.launchVersionName,
            "game_directory": prepared.gameDirectory.path,
            "assets_root": prepared.assetsDirectory.path,
            "game_assets": legacyAssets,
            "assets_index_name": assetsIndex,
            "auth_uuid": uuid,
            "auth_access_token": session.accessToken,
            "auth_session": "token:\(session.accessToken):\(uuid)",
            "clientid": AppConstants.msaClientID,
            "auth_xuid": session.xuid,
            "user_type": offline ? "legacy" : "msa",
            "version_type": prepared.versionType,
            "user_properties": "{}",
            "launcher_name": AppConstants.appName,
            "launcher_version": AppConstants.version,
            "resolution_width": "1280",
            "resolution_height": "800"
        ]

        var gameArguments = details.resolvedGameArguments()
        gameArguments = gameArguments.map { argument in
            var value = argument
            for (key, replacement) in replacements {
                value = value.replacingOccurrences(of: "${\(key)}", with: replacement)
            }
            return value
        }
        gameArguments.append(contentsOf: CommandLineSplitter.split(instance.gameArgs))
        if let quickPlayAddress, !quickPlayAddress.isEmpty {
            gameArguments.append(contentsOf: ["--quickPlayMultiplayer", quickPlayAddress])
        }
        if let quickPlayWorld, !quickPlayWorld.isEmpty {
            gameArguments.append(contentsOf: ["--quickPlaySingleplayer", quickPlayWorld])
        }

        var environment = ProcessInfo.processInfo.environment
        environment["JAVA_HOME"] = java.homePath
        let javaBin = URL(fileURLWithPath: java.executablePath).deletingLastPathComponent().path
        environment["PATH"] = javaBin + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")

        return LaunchCommand(
            executable: URL(fileURLWithPath: java.executablePath),
            arguments: jvm + [details.mainClass] + gameArguments,
            workingDirectory: prepared.gameDirectory,
            environment: environment
        )
    }

    /// A textual description of the launch command safe for logs: flag values
    /// that carry credentials (`--accessToken`, `--clientId`) and every
    /// occurrence of `secrets` (e.g. the session access token, which also
    /// appears inside the legacy `auth_session` argument) are masked.
    static func redactedDescription(_ command: LaunchCommand, secrets: [String] = []) -> String {
        var arguments: [String] = []
        var skipNext = false
        for argument in command.arguments {
            if skipNext {
                arguments.append("<redacted>")
                skipNext = false
                continue
            }
            var value = argument
            for secret in secrets where !secret.isEmpty {
                value = value.replacingOccurrences(of: secret, with: "<redacted>")
            }
            if argument == "--accessToken" || argument == "--clientId" {
                arguments.append(argument)
                skipNext = true
            } else {
                arguments.append(value)
            }
        }
        var description = ([command.executable.path] + arguments).joined(separator: " ")
            .replacingOccurrences(of: AppConstants.msaClientID, with: "<client-id>")
        for secret in secrets where !secret.isEmpty {
            description = description.replacingOccurrences(of: secret, with: "<redacted>")
        }
        return description
    }
}
