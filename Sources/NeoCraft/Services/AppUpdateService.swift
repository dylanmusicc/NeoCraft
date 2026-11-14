import AppKit
import Foundation

/// A NeoCraft release published on GitHub.
struct AppRelease: Sendable, Equatable {
    /// Bare version, e.g. "2.1.3" (the tag's leading "v" is stripped).
    var version: String
    var tag: String
    var name: String
    var notes: String
    var htmlURL: URL?
    /// The `.dmg` asset used for the in-place update, when the release has one.
    var dmgURL: URL?
    var dmgSize: Int64?
    var publishedAt: Date?
}

enum AppUpdatePhase: Equatable {
    case idle
    case checking
    case available(AppRelease)
    case upToDate
    case downloading(version: String, fraction: Double)
    /// The new bundle is on disk; a restart applies it.
    case readyToInstall
    case failed(String)
}

/// Checks GitHub Releases for a newer NeoCraft and performs the in-place
/// update: download the DMG, mount it, replace the running bundle and offer
/// a restart. Everything is best-effort — a failed check never surfaces as
/// an error in the UI, it just stays quiet.
enum AppUpdater {
    static let repository = "dylanmusicc/NeoCraft"
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    /// Re-check at most once a day unless the user asks explicitly.
    private static let checkInterval: TimeInterval = 24 * 3600
    private static let lastCheckKey = "neoCraft.appUpdateLastCheck"

    // MARK: - Check

    static var isDueForAutomaticCheck: Bool {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        return Date().timeIntervalSince1970 - last > checkInterval
    }

    static func markChecked() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
    }

    /// The newest GitHub release, or nil when unreachable or not newer.
    static func latestRelease() async throws -> AppRelease? {
        var request = URLRequest(url: apiURL)
        request.setValue("NeoCraft/\(AppConstants.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NetworkError.transport("GitHub answered \((response as? HTTPURLResponse)?.statusCode ?? 0).")
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard isNewer(version, than: AppConstants.version) else { return nil }

        let dmg = release.assets.first {
            $0.name.hasPrefix("NeoCraft-") && $0.name.hasSuffix(".dmg")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return AppRelease(
            version: version,
            tag: release.tagName,
            name: release.name ?? release.tagName,
            notes: release.body ?? "",
            htmlURL: URL(string: release.htmlURL),
            dmgURL: dmg.flatMap { URL(string: $0.browserDownloadURL) },
            dmgSize: dmg?.size,
            publishedAt: formatter.date(from: release.publishedAt ?? "")
                ?? ISO8601DateFormatter().date(from: release.publishedAt ?? "")
        )
    }

    /// Numeric, component-wise compare: "2.10.0" > "2.9.9".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Download

    /// Downloads the release DMG into the shared cache. Reuses a complete
    /// download when the file is already there.
    static func download(_ release: AppRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let dmg = release.dmgURL else {
            throw NetworkError.transport("This release has no DMG download.")
        }
        let destination = AppPaths.cache.appendingPathComponent("NeoCraft-\(release.version).dmg")
        let request = DownloadRequest(
            url: dmg,
            destination: destination,
            expectedSize: release.dmgSize,
            label: "NeoCraft-\(release.version).dmg"
        )
        try await Downloader.download(request, progress: progress)
        return destination
    }

    // MARK: - Install

    /// Mounts the DMG, copies the new `NeoCraft.app` over the running bundle
    /// and unmounts. Returns the installed bundle URL.
    @discardableResult
    static func install(from dmg: URL) async throws -> URL {
        let mounted = try await mount(dmg)
        defer { unmount(mounted) }

        let contents = try FileManager.default.contentsOfDirectory(
            at: mounted, includingPropertiesForKeys: nil)
        guard let source = contents.first(where: {
            $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix("NeoCraft")
        }) else {
            throw NetworkError.transport("No NeoCraft.app inside the disk image.")
        }

        let target = Bundle.main.bundleURL
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".NeoCraft-update-\(UUID().uuidString).app")
        do {
            try FileManager.default.copyItem(at: source, to: staging)
        } catch {
            throw NetworkError.transport("Couldn't stage the update: \(error.localizedDescription)")
        }
        do {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw NetworkError.transport("Couldn't replace \(target.lastPathComponent): \(error.localizedDescription)")
        }
        return target
    }

    private static func mount(_ dmg: URL) async throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-nobrowse", "-readonly", dmg.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NetworkError.transport("hdiutil attach failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        // Last whitespace-separated field of the last line is the mount point.
        guard let line = output.split(separator: "\n").last,
              let point = line.split(separator: " ").last else {
            throw NetworkError.transport("Couldn't find the mount point.")
        }
        return URL(fileURLWithPath: String(point), isDirectory: true)
    }

    private static func unmount(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["detach", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Relaunch

    /// Opens the freshly installed bundle, then quits this process.
    static func relaunch() {
        let app = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [app.path]
        try? process.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - GitHub payload

    private struct GitHubRelease: Decodable {
        var tagName: String
        var name: String?
        var body: String?
        var htmlURL: String
        var publishedAt: String?
        var assets: [GitHubAsset]
    }

    private struct GitHubAsset: Decodable {
        var name: String
        var browserDownloadURL: String
        var size: Int64?
    }
}
