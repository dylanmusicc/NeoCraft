import Foundation

/// Result of scanning a crashed Minecraft session for a human-readable
/// diagnosis and concrete remediation steps.
struct CrashDiagnosis: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var summary: String
    var suggestions: [String]
    var crashReportURL: URL?
}

/// Parses crash-reports and latest.log tails after a non-zero game exit.
enum CrashDoctor {
    /// Inspects the instance's crash output and returns a diagnosis, or nil
    /// when nothing actionable was found.
    static func diagnose(instance: GameInstance) -> CrashDiagnosis? {
        let gameDirectory = instance.gameDirectory
        let crashDir = gameDirectory.appendingPathComponent("crash-reports", isDirectory: true)

        // Newest crash report wins; fall back to the tail of latest.log.
        var text = ""
        var reportURL: URL?
        if let reports = try? FileManager.default.contentsOfDirectory(
            at: crashDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ), let newest = reports
            .filter({ $0.pathExtension == "txt" })
            .max(by: { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l < r
            }),
            let contents = try? String(contentsOf: newest, encoding: .utf8) {
            text = contents
            reportURL = newest
        } else {
            let latestLog = gameDirectory.appendingPathComponent("logs/latest.log", isDirectory: false)
            if let contents = try? String(contentsOf: latestLog, encoding: .utf8) {
                text = String(contents.suffix(60_000))
            }
        }

        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()

        var suggestions: [String] = []
        var title = "Minecraft crashed"
        var summary = "The game exited unexpectedly. The crash report was analyzed for common causes."

        if lower.contains("outofmemoryerror") || lower.contains("java heap space") {
            title = "Out of memory"
            summary = "The JVM ran out of heap space during gameplay."
            suggestions = [
                "Lower the instance's maximum memory in Edit Instance (4–4.5 GB is the sweet spot for 8 GB Macs).",
                "Close other memory-heavy apps before relaunching.",
                "If Distant Horizons is installed, reduce its LOD quality in its config."
            ]
        } else if lower.contains("distanthorizons") || lower.contains("distant horizons") {
            title = "Distant Horizons problem"
            summary = "Distant Horizons appears in the crash trace."
            suggestions = [
                "Update Distant Horizons and Sodium to their latest versions via the Mod Library.",
                "Reduce DH's LOD render distance in its in-game config.",
                "Try Neo Boost's Cool & Quiet profile to lower overall memory pressure."
            ]
        } else if lower.contains("classnotfoundexception") || lower.contains("noclassdeffounderror") || lower.contains("nosuchmethoderror") {
            title = "Mod conflict"
            summary = "A class or method expected by one mod is missing — usually a version or dependency mismatch."
            suggestions = [
                "Update all mods in this instance (Mod Library → Check Updates → Update All).",
                "Remove recently added mods to isolate the conflict.",
                "Make sure Fabric API and every mod support this Minecraft version."
            ]
        } else if lower.contains("requires fabric") || lower.contains("fabricloader") && lower.contains("neoforge") {
            title = "Loader mismatch"
            summary = "A mod or file requires a different mod loader than this instance provides."
            suggestions = [
                "Check that every mod in the mods folder supports Fabric.",
                "Remove mods that were installed for NeoForge or Forge."
            ]
        } else if lower.contains("opengl") || lower.contains("lwjgl") || lower.contains("gpu") {
            title = "Graphics error"
            summary = "The crash trace points at OpenGL/LWJGL — often a shader pack or driver-level issue."
            suggestions = [
                "Disable shader packs temporarily (rename the shaderpacks folder contents).",
                "Update macOS and restart the Mac to refresh GPU drivers."
            ]
        } else if lower.contains("access denied") || lower.contains("permission") {
            title = "File access problem"
            summary = "Minecraft could not read or write files in its game directory."
            suggestions = [
                "Reveal the instance folder and check for locked or read-only files.",
                "Restart NeoCraft and try again."
            ]
        }

        if suggestions.isEmpty {
            suggestions = [
                "Open the Console (⌘L) for the full log around the crash.",
                "Update all mods and Java, then try again.",
                "If it keeps crashing, share the crash report with the mod authors."
            ]
        }

        return CrashDiagnosis(
            title: title,
            summary: summary,
            suggestions: suggestions,
            crashReportURL: reportURL
        )
    }
}
