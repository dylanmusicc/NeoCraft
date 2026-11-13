import Foundation

// MARK: - Flight Check: pre-launch mod scanner

/// How a JAR's metadata describes its mod loader.
enum ModLoaderKind: String, Sendable {
    case fabric
    case quilt
    case forge
    case neoforge
    case unknown

    var title: String {
        switch self {
        case .fabric: "Fabric"
        case .quilt: "Quilt"
        case .forge: "Forge"
        case .neoforge: "NeoForge"
        case .unknown: "Unknown"
        }
    }
}

/// Metadata extracted from a single mod JAR without extracting it.
struct ModJarInfo: Sendable {
    var fileName: String
    var fileURL: URL
    var modID: String
    var name: String
    var version: String
    var loader: ModLoaderKind
    /// dependency mod-id → version predicate ("", ">=1.20", …)
    var depends: [String: String]
    /// mod-ids this mod explicitly breaks / conflicts with.
    var breaks: Set<String>
    var environment: String?
}

/// Severity of a Flight Check finding.
enum FlightIssueSeverity: String, Sendable {
    case error
    case warning
}

/// What the user can do about an issue from the diagnostic sheet.
enum FlightFix: Sendable {
    case installDependency(String)   // Modrinth slug / project id
    case disableMod(String)          // JAR file name inside mods/
    case none
}

enum FlightIssueKind: String, Sendable {
    case missingDependency
    case versionMismatch
    case duplicateModID
    case loaderMismatch
    case brokenDependency
    case unknownFormat
}

struct FlightIssue: Identifiable, Sendable {
    var id: String { "\(kind.rawValue)-\(fileName ?? "")-\(modID ?? "")-\(detail)" }
    var severity: FlightIssueSeverity
    var kind: FlightIssueKind
    var title: String
    var detail: String
    var fileName: String?
    var modID: String?
    var fix: FlightFix
}

/// The aggregate result shown as the Flight Check pill.
struct FlightCheckResult: Sendable {
    var issues: [FlightIssue]
    var scannedCount: Int
    var checkedAt: Date

    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.filter { $0.severity == .warning }.count }

    enum Status: Sendable {
        case passed
        case warning
        case conflict
        case empty
    }

    var status: Status {
        if scannedCount == 0 { return .empty }
        if errorCount > 0 { return .conflict }
        if warningCount > 0 { return .warning }
        return .passed
    }

    var pillTitle: String {
        switch status {
        case .passed: "Flight Check Passed • Ready"
        case .warning: "\(warningCount) Warning\(warningCount == 1 ? "" : "s")"
        case .conflict: "Conflict Detected"
        case .empty: "No Mods Installed"
        }
    }

    var pillColorHex: String {
        switch status {
        case .passed: "4ADE80"
        case .warning: "FBBF24"
        case .conflict: "F87171"
        case .empty: "9AA4B2"
        }
    }
}

// MARK: - Scanner

/// Reads `fabric.mod.json`, `quilt.mod.json`, `META-INF/mods.toml` and
/// `META-INF/neoforge.mods.toml` straight out of JAR archives via
/// `/usr/bin/unzip`, then cross-checks versions, dependencies and loader
/// compatibility before the JVM is ever launched.
actor ModScanner {
    static let shared = ModScanner()

    /// Dependencies that describe the platform rather than another mod —
    /// they are validated separately and never flagged as "missing".
    private static let platformDependencies: Set<String> = [
        "minecraft", "java", "fabricloader", "fabric-api", "fabric",
        "quilt_loader", "forge", "minecraftforge", "neoforge"
    ]

    func scan(instance: GameInstance) async -> FlightCheckResult {
        let modsDirectory = instance.gameDirectory.appendingPathComponent("mods", isDirectory: true)
        let jars = jarFiles(in: modsDirectory)
        var infos: [ModJarInfo] = []
        infos.reserveCapacity(jars.count)

        for jar in jars {
            if let info = inspect(jar: jar) {
                infos.append(info)
            }
        }

        return evaluate(infos: infos, minecraftVersion: instance.minecraftVersion, expectedLoader: instance.loader)
    }

    // MARK: JAR inspection

    private func jarFiles(in directory: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { $0.pathExtension.lowercased() == "jar" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Lists archive entries then pulls the known metadata files.
    private func inspect(jar: URL) -> ModJarInfo? {
        guard let listing = unzipList(jar), !listing.isEmpty else { return nil }

        let fabricJSON = listing.contains("fabric.mod.json")
            ? unzipExtract(jar, entry: "fabric.mod.json") : nil
        let quiltJSON = listing.contains("quilt.mod.json")
            ? unzipExtract(jar, entry: "quilt.mod.json") : nil
        let forgeTOML = listing.contains("META-INF/mods.toml")
            ? unzipExtract(jar, entry: "META-INF/mods.toml") : nil
        let neoTOML = listing.contains("META-INF/neoforge.mods.toml")
            ? unzipExtract(jar, entry: "META-INF/neoforge.mods.toml") : nil

        if let fabricJSON, let info = parseFabricModJSON(fabricJSON, fileName: jar.lastPathComponent, fileURL: jar) {
            return info
        }
        if let quiltJSON, let info = parseQuiltModJSON(quiltJSON, fileName: jar.lastPathComponent, fileURL: jar) {
            return info
        }
        if let neoTOML, let info = parseForgeTOML(neoTOML, fileName: jar.lastPathComponent, fileURL: jar, loader: .neoforge) {
            return info
        }
        if let forgeTOML, let info = parseForgeTOML(forgeTOML, fileName: jar.lastPathComponent, fileURL: jar, loader: .forge) {
            return info
        }

        // JAR without recognizable mod metadata — could be a library or a
        // plain resource pack. Still report it so the UI can flag it.
        return ModJarInfo(
            fileName: jar.lastPathComponent,
            fileURL: jar,
            modID: "",
            name: jar.deletingPathExtension().lastPathComponent,
            version: "",
            loader: .unknown,
            depends: [:],
            breaks: [],
            environment: nil
        )
    }

    /// Public single-JAR inspection for the Instance Manager — returns the
    /// same metadata Flight Check uses, for any archive path.
    func inspectJar(at url: URL) -> ModJarInfo? {
        inspect(jar: url)
    }

    /// `unzip -Z1` prints one entry name per line.
    private func unzipList(_ jar: URL) -> Set<String>? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", jar.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        return Set(text.split(separator: "\n").map { String($0) })
    }

    /// `unzip -p` streams a single entry to stdout.
    private func unzipExtract(_ jar: URL, entry: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", jar.path, entry]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Metadata parsing

    private func parseFabricModJSON(_ text: String, fileName: String, fileURL: URL) -> ModJarInfo? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let depends = (object["depends"] as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
        let breaks = (object["breaks"] as? [String: Any]).map { Set($0.keys) } ?? []
        let conflicts = (object["conflicts"] as? [String: Any]).map { Set($0.keys) } ?? []

        return ModJarInfo(
            fileName: fileName,
            fileURL: fileURL,
            modID: object["id"] as? String ?? "",
            name: object["name"] as? String ?? fileName,
            version: object["version"] as? String ?? "",
            loader: .fabric,
            depends: depends,
            breaks: breaks.union(conflicts),
            environment: object["environment"] as? String
        )
    }

    private func parseQuiltModJSON(_ text: String, fileName: String, fileURL: URL) -> ModJarInfo? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var depends: [String: String] = [:]
        if let quiltDepends = object["depends"] as? [String: Any] {
            for (key, value) in quiltDepends {
                if let range = value as? String {
                    depends[key] = range
                }
            }
        }
        if let loaderDeps = object["quilt_loader"] as? [String: Any],
           let loaderDepends = loaderDeps["depends"] as? [String: Any] {
            for (key, value) in loaderDepends {
                if depends[key] == nil, let range = value as? String {
                    depends[key] = range
                }
            }
        }

        let loaderObject = object["quilt_loader"] as? [String: Any]
        return ModJarInfo(
            fileName: fileName,
            fileURL: fileURL,
            modID: loaderObject?["id"] as? String
                ?? fileName.replacingOccurrences(of: ".jar", with: ""),
            name: object["name"] as? String ?? fileName,
            version: object["version"] as? String ?? "",
            loader: .quilt,
            depends: depends,
            breaks: [],
            environment: object["environment"] as? String
        )
    }

    /// Minimal TOML reader for Forge/NeoForge `mods.toml` — pulls `modId`,
    /// `version`, and `[[dependencies.<modid>]]` blocks with
    /// `mandatory=true`.
    private func parseForgeTOML(_ text: String, fileName: String, fileURL: URL, loader: ModLoaderKind) -> ModJarInfo? {
        var modID = ""
        var name = fileName
        var version = ""
        var depends: [String: String] = [:]
        let breaks: Set<String> = []

        var currentDependency: String?
        var currentMandatory = false
        var currentVersionRange = ""

        func flushDependency() {
            guard let dep = currentDependency, currentMandatory else {
                currentDependency = nil
                return
            }
            depends[dep] = currentVersionRange
            currentDependency = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                flushDependency()
                if line.hasPrefix("[[dependencies.") {
                    let inner = String(line.dropFirst("[[dependencies.".count).dropLast(2))
                    currentDependency = inner.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    currentMandatory = false
                    currentVersionRange = ""
                }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            if currentDependency != nil {
                if key == "mandatory" {
                    currentMandatory = value == "true"
                } else if key == "versionRange" {
                    currentVersionRange = value
                }
            } else if key == "modId" {
                modID = value
            } else if key == "displayName" {
                name = value
            } else if key == "version" {
                version = value
            }
        }
        flushDependency()

        guard !modID.isEmpty else {
            return ModJarInfo(
                fileName: fileName, fileURL: fileURL, modID: "",
                name: name, version: version, loader: loader,
                depends: depends, breaks: breaks, environment: nil
            )
        }

        return ModJarInfo(
            fileName: fileName,
            fileURL: fileURL,
            modID: modID,
            name: name,
            version: version,
            loader: loader,
            depends: depends,
            breaks: breaks,
            environment: nil
        )
    }

    // MARK: Validation rules

    private func evaluate(
        infos: [ModJarInfo],
        minecraftVersion: String,
        expectedLoader: ModLoader
    ) -> FlightCheckResult {
        var issues: [FlightIssue] = []

        // Index installed mod ids → jars for dependency / duplicate checks.
        var byID: [String: [ModJarInfo]] = [:]
        for info in infos where !info.modID.isEmpty {
            byID[info.modID, default: []].append(info)
        }

        let expectedFabric = expectedLoader == .fabric

        for info in infos {
            // 1. Loader mismatch: a Forge/NeoForge/Quilt binary in a Fabric
            //    instance (or vice versa) will never load.
            if expectedFabric {
                switch info.loader {
                case .forge, .neoforge:
                    issues.append(FlightIssue(
                        severity: .error, kind: .loaderMismatch,
                        title: "Wrong mod loader",
                        detail: "\(info.name) is a \(info.loader.title) mod but this instance runs Fabric. It will be ignored or crash the game.",
                        fileName: info.fileName, modID: info.modID.isEmpty ? nil : info.modID,
                        fix: .disableMod(info.fileName)
                    ))
                case .quilt:
                    issues.append(FlightIssue(
                        severity: .warning, kind: .loaderMismatch,
                        title: "Quilt mod on Fabric",
                        detail: "\(info.name) targets Quilt. Fabric cannot load it — it will be skipped.",
                        fileName: info.fileName, modID: info.modID.isEmpty ? nil : info.modID,
                        fix: .disableMod(info.fileName)
                    ))
                case .unknown:
                    issues.append(FlightIssue(
                        severity: .warning, kind: .unknownFormat,
                        title: "Unrecognized mod format",
                        detail: "\(info.fileName) has no fabric.mod.json / mods.toml. It may be a library or a mislabeled file.",
                        fileName: info.fileName, modID: nil,
                        fix: .disableMod(info.fileName)
                    ))
                case .fabric:
                    break
                }
            } else {
                // Vanilla instance: any real mod loader jar is a mismatch.
                if info.loader != .unknown {
                    issues.append(FlightIssue(
                        severity: .error, kind: .loaderMismatch,
                        title: "Mod in vanilla instance",
                        detail: "\(info.name) is a \(info.loader.title) mod but this instance is Vanilla — remove it or switch the instance to Fabric.",
                        fileName: info.fileName, modID: info.modID.isEmpty ? nil : info.modID,
                        fix: .disableMod(info.fileName)
                    ))
                }
            }

            // 2. Duplicate mod IDs.
            if !info.modID.isEmpty, let duplicates = byID[info.modID], duplicates.count > 1 {
                let others = duplicates.filter { $0.fileName != info.fileName }.map(\.fileName)
                issues.append(FlightIssue(
                    severity: .error, kind: .duplicateModID,
                    title: "Duplicate mod ID",
                    detail: "Mod id \"\(info.modID)\" is provided by multiple JARs: \(others.joined(separator: ", ")). Keep only one.",
                    fileName: info.fileName, modID: info.modID,
                    fix: .disableMod(info.fileName)
                ))
            }

            // 3. Minecraft version compatibility (fabric.mod.json "depends").
            if let mcPredicate = info.depends["minecraft"],
               !mcPredicate.isEmpty,
               !VersionPredicate(mcPredicate).matches(minecraftVersion) {
                issues.append(FlightIssue(
                    severity: .error, kind: .versionMismatch,
                    title: "Incompatible Minecraft version",
                    detail: "\(info.name) requires Minecraft \(mcPredicate), but this instance runs \(minecraftVersion).",
                    fileName: info.fileName, modID: info.modID.isEmpty ? nil : info.modID,
                    fix: .none
                ))
            }

            // 4. Missing required dependencies.
            for (depID, predicate) in info.depends where !Self.platformDependencies.contains(depID) {
                guard !depID.isEmpty else { continue }
                if byID[depID] == nil {
                    issues.append(FlightIssue(
                        severity: .error, kind: .missingDependency,
                        title: "Missing dependency",
                        detail: "\(info.name) requires \"\(depID)\"\(predicate.isEmpty ? "" : " (\(predicate))"), which is not installed.",
                        fileName: info.fileName, modID: info.modID.isEmpty ? nil : info.modID,
                        fix: .installDependency(depID)
                    ))
                } else if !predicate.isEmpty,
                          let installed = byID[depID]?.first,
                          !installed.version.isEmpty,
                          !VersionPredicate(predicate).matches(installed.version) {
                    issues.append(FlightIssue(
                        severity: .warning, kind: .versionMismatch,
                        title: "Dependency version mismatch",
                        detail: "\(info.name) wants \(depID) \(predicate) but \(installed.version) is installed.",
                        fileName: info.fileName, modID: depID,
                        fix: .installDependency(depID)
                    ))
                }
            }

            // 5. Known breakage / conflicts.
            for brokenID in info.breaks where !brokenID.isEmpty {
                if byID[brokenID] != nil {
                    issues.append(FlightIssue(
                        severity: .error, kind: .brokenDependency,
                        title: "Known incompatible mods",
                        detail: "\(info.name) declares it breaks \"\(brokenID)\", which is also installed.",
                        fileName: info.fileName, modID: info.modID.isEmpty ? nil : info.modID,
                        fix: .disableMod(info.fileName)
                    ))
                }
            }
        }

        // De-duplicate identical issues (a pair of conflicting mods reports twice).
        var seen = Set<String>()
        issues = issues.filter { seen.insert($0.id).inserted }
        issues.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity == .error }
            return lhs.title < rhs.title
        }

        return FlightCheckResult(
            issues: issues,
            scannedCount: infos.count,
            checkedAt: Date()
        )
    }
}

// MARK: - Version predicates

/// Evaluates the small predicate language used by `depends` entries:
/// comma/space separated clauses like `">=1.20 <1.22"`, `"~1.21"`,
/// `"^1.20.1"`, `"1.21.x"` or a bare version.
struct VersionPredicate: Sendable {
    let expression: String

    init(_ expression: String) { self.expression = expression }

    func matches(_ version: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }

        // Split clauses on commas or whitespace between comparators.
        let clauses = trimmed
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        for clause in clauses {
            if !match(clause: clause, version: version) { return false }
        }
        return true
    }

    private func match(clause: String, version: String) -> Bool {
        if clause.hasPrefix(">=") { return compare(version, clause.dropFirst(2)) >= 0 }
        if clause.hasPrefix("<=") { return compare(version, clause.dropFirst(2)) <= 0 }
        if clause.hasPrefix(">")  { return compare(version, clause.dropFirst(1)) > 0 }
        if clause.hasPrefix("<")  { return compare(version, clause.dropFirst(1)) < 0 }
        if clause.hasPrefix("!=") { return compare(version, clause.dropFirst(2)) != 0 }
        if clause.hasPrefix("=")  { return compare(version, clause.dropFirst(1)) == 0 }
        if clause.hasPrefix("~")  { return tilde(clause.dropFirst(), version: version) }
        if clause.hasPrefix("^")  { return caret(clause.dropFirst(), version: version) }
        if clause.contains("x") || clause.contains("X") || clause.contains("*") {
            return wildcard(clause, version: version)
        }
        return compare(version, clause) == 0 || compare(version, clause) > 0
    }

    /// Numeric component-wise comparison. Missing components count as 0.
    private func components(_ s: Substring) -> [Int] {
        s.split(separator: ".").map { Int($0) ?? 0 }
    }

    /// String convenience overload.
    private func compare(_ lhs: String, _ rhs: String) -> Int {
        compare(lhs, Substring(rhs))
    }

    /// Returns -1/0/1 comparing `lhs` to `rhs` (both version strings).
    private func compare(_ lhs: String, _ rhs: Substring) -> Int {
        let a = components(Substring(lhs))
        var b = components(rhs)
        let count = max(a.count, b.count)
        if b.count < count { b += Array(repeating: 0, count: count - b.count) }
        for i in 0..<count {
            let av = i < a.count ? a[i] : 0
            let bv = i < b.count ? b[i] : 0
            if av != bv { return av < bv ? -1 : 1 }
        }
        return 0
    }

    private func tilde(_ spec: Substring, version: String) -> Bool {
        // ~1.2  → >=1.2.0 <1.3.0 ; ~1.2.3 → >=1.2.3 <1.3.0
        let parts = components(spec)
        guard !parts.isEmpty else { return true }
        let lowerOK = compare(version, spec) >= 0
        let upper = parts.count >= 2 ? "\(parts[0]).\(parts[1] + 1)" : "\(parts[0] + 1)"
        return lowerOK && compare(version, Substring(upper)) < 0
    }

    private func caret(_ spec: Substring, version: String) -> Bool {
        // ^1.2.3 → >=1.2.3 <2.0.0 ; ^0.2.3 → >=0.2.3 <0.3.0
        let parts = components(spec)
        guard !parts.isEmpty else { return true }
        let lowerOK = compare(version, spec) >= 0
        let upper: String
        if parts[0] > 0 {
            upper = "\(parts[0] + 1)"
        } else if parts.count > 1 && parts[1] > 0 {
            upper = "0.\(parts[1] + 1)"
        } else {
            upper = "0.0.\((parts.count > 2 ? parts[2] : 0) + 1)"
        }
        return lowerOK && compare(version, Substring(upper)) < 0
    }

    private func wildcard(_ spec: String, version: String) -> Bool {
        // 1.21.x or 1.21.* — prefix match on numeric components.
        let pattern = spec
            .replacingOccurrences(of: "*", with: "x")
            .split(separator: ".")
            .map { $0.lowercased() == "x" ? nil : Int($0) }
        let actual = version.split(separator: ".").map { Int($0) ?? 0 }
        for (i, component) in pattern.enumerated() {
            guard let expected = component else { return true }
            let av = i < actual.count ? actual[i] : 0
            if av != expected { return false }
        }
        return true
    }
}
