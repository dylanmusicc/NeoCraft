import Foundation
@testable import LauncherCore
import Testing

struct WinePrefixTests {
    let temporary: TemporaryDirectory
    let host = HostEnvironment(home: "/Users/test", user: "test", temporaryDirectory: "/tmp/")

    init() throws {
        temporary = try TemporaryDirectory()
    }

    @Test func hasNoServerWhenNothingHoldsItsLock() throws {
        let prefix = WinePrefix(url: temporary.url, serverDirectories: temporary.url)
        #expect(prefix.runningServer() == nil)
    }

    @Test func findsTheProcessHoldingItsServerLock() async throws {
        let url = temporary.url.appending(path: "prefix")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let holder = try await ServerLockHolder(prefix: url, serverDirectories: temporary.url)
        defer { holder.release() }

        let prefix = WinePrefix(url: url, serverDirectories: temporary.url)
        #expect(prefix.runningServer() == holder.process.processIdentifier)
    }

    @Test func toolEnvironmentMatchesTheEngineTests() {
        let prefix = WinePrefix(url: URL(filePath: "/prefixes/a"))
        #expect(
            prefix.environment(host: host, msync: false) == [
                "HOME": "/Users/test", "USER": "test", "TMPDIR": "/tmp/", "PATH": "/usr/bin:/bin",
                "LC_ALL": "en_US.UTF-8", "WINEPREFIX": "/prefixes/a", "WINEARCH": "win64",
                "WINEDEBUG": "-all", "WINEDLLOVERRIDES": "mscoree,mshtml=",
            ])
        #expect(prefix.environment(host: host, msync: true)["WINEMSYNC"] == "1")
    }
}

struct WineToolTests {
    let temporary: TemporaryDirectory
    let host = HostEnvironment(home: "/Users/test", user: "test", temporaryDirectory: "/tmp/")

    init() throws {
        temporary = try TemporaryDirectory()
    }

    func environment() -> [String: String] {
        WinePrefix(url: temporary.url).environment(host: host, msync: true)
    }

    @Test func reportsAProgramThatFails() async throws {
        let runtime = try FakeRuntime(in: temporary.url, behaviours: ["wine reg": "exit 5"])
        await #expect(throws: WineError.failed("reg", .exited(5))) {
            try await WineTool(runtime: runtime.url, host: host).run(
                ["reg", "import", "Z:\\x.reg"], environment: environment(), output: .nullDevice,
                timeout: .seconds(5))
        }
    }

    @Test func killsAProgramThatTakesTooLong() async throws {
        let runtime = try FakeRuntime(
            in: temporary.url, behaviours: ["wine wineboot": "exec sleep 30"])
        await #expect(throws: WineError.timedOut("wineboot")) {
            try await WineTool(runtime: runtime.url, host: host).run(
                ["wineboot"], environment: environment(), output: .nullDevice,
                timeout: .milliseconds(300))
        }
    }

    @Test func waitsForTheServerAndKillsItWhenItDoesNotStop() async throws {
        let runtime = try FakeRuntime(
            in: temporary.url, behaviours: ["wineserver -w": "exec sleep 30"])
        let prefix = WinePrefix(url: temporary.url, serverDirectories: temporary.url)
        try await WineTool(runtime: runtime.url, host: host).waitForServer(
            of: prefix, output: .nullDevice, timeout: .milliseconds(300))
        #expect(
            try runtime.recorded.last == "wineserver -k | WINEMSYNC=unset WINEDLLOVERRIDES=unset")
    }
}

struct GameOptionsTests {
    let temporary: TemporaryDirectory

    init() throws {
        temporary = try TemporaryDirectory()
    }

    private func options(of xboxUser: String, in prefix: WinePrefix) -> URL {
        prefix.gameData(of: .release, user: "test")
            .appending(path: "Users/\(xboxUser)/games/com.mojang/minecraftpe/options.txt")
    }

    private func write(_ text: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    @Test func changesOnlyItsOptionsForEveryUserThatHasPlayed() throws {
        let prefix = WinePrefix(url: temporary.url)
        let first = options(of: "1", in: prefix)
        let second = options(of: "2", in: prefix)
        try write("a:1\r\ngfx_vsync:1\r\ngfx_fullscreen:0\r\nb:2\r\n", to: first)
        try write("gfx_vsync:1\ngfx_fullscreen:0\n", to: second)
        try prefix.setGameOptions(
            ["gfx_fullscreen": true, "gfx_vsync": false], of: .release, user: "test")
        #expect(
            try String(contentsOf: first, encoding: .utf8)
                == "a:1\r\ngfx_vsync:0\r\ngfx_fullscreen:1\r\nb:2\r\n")
        #expect(
            try String(contentsOf: second, encoding: .utf8) == "gfx_vsync:0\ngfx_fullscreen:1\n")
        try prefix.setGameOptions(["gfx_fullscreen": false], of: .release, user: "test")
        #expect(
            try String(contentsOf: second, encoding: .utf8) == "gfx_vsync:0\ngfx_fullscreen:0\n")
    }

    @Test func leavesAnOptionThatOnlyEndsTheSame() throws {
        let prefix = WinePrefix(url: temporary.url)
        let file = options(of: "1", in: prefix)
        try write("other_gfx_vsync:1\n", to: file)
        try prefix.setGameOptions(["gfx_vsync": false], of: .release, user: "test")
        #expect(
            try String(contentsOf: file, encoding: .utf8) == "gfx_vsync:0\nother_gfx_vsync:1\n")
    }

    @Test func leavesAnAccountThatHasNotPlayedAlone() throws {
        let prefix = WinePrefix(url: temporary.url)
        try prefix.setGameOptions(["gfx_vsync": false], of: .release, user: "test")
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.url.path).isEmpty)
    }
}
