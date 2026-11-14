import Foundation

/// NeoCraft's own files, read so the Bedrock component stays in step with the
/// launcher that hosts it. The Studio/Servers/Screenshots pages moved into
/// NeoCraft itself — this file now only answers whether NeoCraft's Bedrock
/// beta flag is on, which `NeoSync` uses to gate synced features.
enum NeoCraftFiles {
    /// `~/Library/Application Support/NeoCraft`.
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("NeoCraft", isDirectory: true)
    }

    static var stateFile: URL { support.appendingPathComponent("state.json") }

    /// The `settings` object of NeoCraft's state file.
    static func settings() -> [String: Any] {
        (state()?["settings"] as? [String: Any]) ?? [:]
    }

    /// Whether NeoCraft's Bedrock beta flag is on. Read from `state.json`
    /// (the flag isn't mirrored into the theme defaults), with a short cache
    /// so menus and sidebars don't re-parse the file per render.
    static func betaEnabled() -> Bool {
        betaLock.lock()
        defer { betaLock.unlock() }
        if let cached = betaBox.cache, Date().timeIntervalSince(cached.at) < 1 { return cached.value }
        let value = (settings()["betaFeatures"] as? [String: Any])?["bedrockEdition"] as? Bool ?? false
        betaBox.cache = (value, Date())
        return value
    }

    private static let betaLock = NSLock()
    private static let betaBox = BetaBox()

    private final class BetaBox: @unchecked Sendable {
        var cache: (value: Bool, at: Date)?
    }

    private static func state() -> [String: Any]? {
        guard let data = try? Data(contentsOf: stateFile) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
