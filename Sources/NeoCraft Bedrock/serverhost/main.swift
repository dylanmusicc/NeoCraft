import Darwin
import Foundation
import LauncherCore

/// `bedrock-host`: runs a Minecraft Bedrock Dedicated Server under the
/// launcher's Wine engine, headless. NeoCraft spawns this helper for every
/// hosted Bedrock server and pipes the server console through it, so the
/// engine and prefix stay owned by the NeoCraft Bedrock component.
///
/// Usage: bedrock-host --data <NeoCraft Bedrock data dir> --dir <server folder>
///
/// The server folder holds `bedrock_server.exe` and `server.properties`;
/// its worlds live in `worlds/`. The Wine prefix is `.wine` inside the
/// server folder (hidden, so the dashboard's file browser skips it).

@main
struct BedrockHost {
    static func main() async {
        let arguments = CommandLine.arguments
        func option(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        guard let dataPath = option("--data"), let directory = option("--dir") else {
            FileHandle.standardError.write(Data("bedrock-host: --data and --dir are required\n".utf8))
            exit(2)
        }
        let serverDirectory = URL(fileURLWithPath: directory)
        let dataRoot = URL(fileURLWithPath: dataPath)

        do {
            try await run(dataRoot: dataRoot, serverDirectory: serverDirectory)
        } catch {
            FileHandle.standardError.write(
                Data("bedrock-host: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(dataRoot: URL, serverDirectory: URL) async throws {
        // The engine the launcher installed for game sessions — a Bedrock
        // server needs nothing more than its Wine.
        let library = try Library(contentsOf: dataRoot.appending(path: "library.json"))
        guard let identity = library.engine else {
            throw HostError.noEngine
        }
        let directory = DataDirectory(
            root: dataRoot, sockets: .temporaryDirectory.appending(path: "neocraft-bedrock"))
        let runtime = try await EngineStore(in: directory).open(identity)

        let prefix = WinePrefix(url: serverDirectory.appending(path: ".wine", directoryHint: .isDirectory))
        var environment = prefix.environment(host: .current, msync: true)
        environment["WINEDEBUG"] = "-all"

        // A fresh prefix takes a while the first time; wineboot builds it
        // once so the server's first start isn't eaten by prefix setup.
        let system = serverDirectory.appending(path: ".wine/drive_c/windows", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: system.path) {
            FileHandle.standardOutput.write(
                Data("[NeoCraft] Preparing the Bedrock server's Wine prefix…\n".utf8))
            let boot = try ChildProcess.run(
                runtime.runtime.appending(path: "bin/wineboot"), arguments: ["--init"],
                environment: environment, output: .standardOutput)
            if await boot.termination(within: .seconds(300)) == nil {
                _ = await boot.termination
            }
        }

        let executable = serverDirectory.appending(path: "bedrock_server.exe")
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw HostError.missingExecutable
        }
        // Wine resolves the program through the Z: drive.
        let dosPath = "Z:\\" + executable.path.replacingOccurrences(of: "/", with: "\\")

        FileHandle.standardOutput.write(
            Data("[NeoCraft] Starting bedrock_server.exe (Wine, headless)\n".utf8))
        let server = try ChildProcess.run(
            runtime.wine, arguments: [dosPath], environment: environment,
            currentDirectory: serverDirectory, input: .standardInput, output: .standardOutput)

        // NeoCraft asks the helper to end (SIGTERM): forward it to the
        // prefix's wineserver so the server gets its chance to save first.
        let tool = WineTool(runtime: runtime.runtime, host: .current)
        for caught in [SIGTERM, SIGINT] {
            Darwin.signal(SIGPIPE, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: caught, queue: .global())
            source.setEventHandler {
                Task {
                    try? await tool.killServer(of: prefix, output: .nullDevice)
                    server.kill()
                    exit(0)
                }
            }
            source.resume()
        }

        let termination = await server.termination
        if case .exited(let code) = termination {
            exit(code)
        }
        exit(1)
    }
}

enum HostError: LocalizedError {
    case noEngine
    case missingExecutable

    var errorDescription: String? {
        switch self {
        case .noEngine:
            "No NeoCraft Bedrock engine is installed — open NeoCraft Bedrock once to finish setup."
        case .missingExecutable:
            "bedrock_server.exe is missing — recreate the server."
        }
    }
}
