import Foundation

/// Lightweight localization layer. Strings live in `Resources/L10n/*.json`
/// (flat `"group.key": "text"` maps) which build.sh copies into the app
/// bundle. Lookup order: manual override → system preference → English →
/// the raw key, so a missing translation degrades gracefully instead of
/// showing an empty label.
enum L10n {
    /// Languages shipped with the app. `en` is the base/fallback table.
    static let supportedLanguages: [(code: String, name: String)] = [
        ("system", "System"),
        ("en", "English (US)"),
        ("en-GB", "English (UK)"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("ru", "Русский"),
        ("es", "Español")
    ]

    /// UserDefaults key mirrored from `AppSettings.appLanguage`.
    static let overrideKey = "neoCraft.appLanguage"

    /// The language used for the next rendered string.
    static var currentLanguage: String {
        let defaults = UserDefaults.standard
        if let override = defaults.string(forKey: overrideKey),
           !override.isEmpty, override != "system" {
            return override
        }
        for tag in Locale.preferredLanguages {
            // Exact match first (en-GB, pt-BR, …), then the base language.
            if languageTableExists(tag) { return tag }
            let base = tag.split(separator: "-").first.map(String.init) ?? tag
            if base != tag, let match = supportedBaseMatch(base) {
                return match
            }
        }
        return "en"
    }

    /// Localized string for `key`; `args` are substituted into `%@`/`%lld`
    /// placeholders via `String(format:)`.
    static func t(_ key: String, _ args: any CVarArg...) -> String {
        var template = lookup(key, language: currentLanguage)
            ?? lookup(key, language: "en")
            ?? key
        if !args.isEmpty {
            template = String(format: template, arguments: args)
        }
        return template
    }

    /// Convenience for SwiftUI `Text` — same lookup, returns a plain String.
    static func string(_ key: String) -> String {
        t(key)
    }

    // MARK: - Internals

    private nonisolated(unsafe) static var tables: [String: [String: String]] = [:]
    private static let tableLock = NSLock()

    private static func supportedBaseMatch(_ base: String) -> String? {
        // Prefer a region-specific table only when it exists; otherwise the
        // plain base table (de, fr, ru, es, en).
        for entry in supportedLanguages where entry.code != "system" {
            if entry.code == base { return entry.code }
        }
        for entry in supportedLanguages where entry.code.hasPrefix(base + "-") {
            return entry.code
        }
        return nil
    }

    private static func languageTableExists(_ tag: String) -> Bool {
        if tag == "en-GB" { return table(named: "en-GB") != nil }
        let base = tag.split(separator: "-").first.map(String.init) ?? tag
        return ["en", "de", "fr", "ru", "es"].contains(base)
            || supportedLanguages.contains { $0.code == tag }
    }

    private static func lookup(_ key: String, language: String) -> String? {
        let lang = language == "en-GB" ? "en-GB" : (language.split(separator: "-").first.map(String.init) ?? language)
        guard let table = table(named: lang) else { return nil }
        return table[key]
    }

    private static func table(named language: String) -> [String: String]? {
        tableLock.lock()
        defer { tableLock.unlock() }
        if let cached = tables[language] { return cached }

        let fileName = "\(language).json"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("L10n/\(fileName)"))
        }
        // `swift run` / bare binary: fall back to the package's Resources dir.
        candidates.append(URL(fileURLWithPath: "Resources/L10n/\(fileName)"))
        // Source-tree fallback for tests run from the repo root.
        candidates.append(URL(fileURLWithPath: "Sources/../Resources/L10n/\(fileName)"))

        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                continue
            }
            tables[language] = object
            return object
        }
        tables[language] = [:]
        return nil
    }
}
