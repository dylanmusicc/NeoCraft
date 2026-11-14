import AppKit
import Darwin
import Foundation
import Observation
import UniformTypeIdentifiers

struct ProjectSelection: Identifiable, Hashable, Sendable {
    var projectID: String
    var title: String
    var iconURL: String?

    var id: String { projectID }
}

struct StorageUsage: Sendable {
    var sharedBytes: Int64 = 0
    var instanceBytes: Int64 = 0
    var cacheBytes: Int64 = 0
    var runtimeBytes: Int64 = 0

    var totalBytes: Int64 { sharedBytes + instanceBytes + cacheBytes + runtimeBytes }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: - Persisted state

    var settings: AppSettings {
        didSet {
            scheduleSave()
            SoundManager.shared.enabled = settings.uiSoundsEnabled
            SoundManager.shared.volume = settings.uiSoundVolume
            StudioTheme.sync(settings)
            if oldValue.betaFeatures.inGameHUD, !settings.betaFeatures.inGameHUD {
                disableInGameHUD()
            }
        }
    }
    var instances: [GameInstance] {
        didSet { scheduleSave() }
    }
    var accounts: [MinecraftAccount] {
        didSet { scheduleSave() }
    }
    var activeAccountID: String? {
        didSet { scheduleSave() }
    }
    var selectedInstanceID: UUID? {
        didSet { scheduleSave() }
    }

    // MARK: - Navigation and presentation

    /// Initial page — `NEOCRAFT_SECTION=<rawValue>` overrides it for
    /// screenshots and UI automation.
    var section: AppSection = {
        if let raw = ProcessInfo.processInfo.environment["NEOCRAFT_SECTION"],
           let section = AppSection(rawValue: raw) {
            return section
        }
        return .play
    }()
    var showConsole = false
    var showAuthSheet = false
    var showOfflineAccountSheet = false
    var editingInstance: GameInstance?
    var selectedPatchNote: PatchNoteEntry?
    var projectSelection: ProjectSelection?
    var screenshotInstance: GameInstance?
    var worldBackupInstance: GameInstance?
    var upgradeInstance: GameInstance?
    /// Instance whose tabbed Detail Hub sheet is open.
    var detailInstance: GameInstance?
    var alert: AppAlert?
    var toast: String?
    var crashDiagnosis: CrashDiagnosis?
    var backupRunning = false
    /// Hosted dedicated servers (world → Java server) discovered on disk.
    var hostedServers: [HostedServer] = []
    /// Server ids with a live dedicated-server process (starting or online).
    var runningServerIDs: Set<UUID> = []
    /// Server ids whose process printed the "Done" ready line.
    var readyServerIDs: Set<UUID> = []
    /// Server ids still being set up (jar download + world copy).
    var serverSetupIDs: Set<UUID> = []
    /// Hosted server shown in the dashboard sheet.
    var dashboardServer: HostedServer?

    /// Hosted servers visible in the UI right now — Bedrock servers
    /// disappear entirely while the Bedrock-servers beta is off (folders
    /// stay on disk; re-enabling brings them back).
    var visibleHostedServers: [HostedServer] {
        hostedServers.filter {
            $0.edition == .java || settings.betaFeatures.bedrockServers
        }
    }
    /// Per-server console buffers for the dashboard's live log view.
    var serverConsoles: [UUID: [ConsoleEntry]] = [:]
    /// Player names seen joining/leaving in each server's console output.
    var serverPlayers: [UUID: [String]] = [:]
    /// When each running server's process was started (for uptime display).
    var serverStartedAt: [UUID: Date] = [:]
    var upgradingInstanceID: UUID?
    var upgradeResults: [UUID: [ModCompatibility]] = [:]
    var consoleFilter = ""
    var instanceQuery = ""
    /// Edition filter for the Instances page; nil = show all.
    var instanceEditionFilter: GameEdition?
    var hoveredSection: AppSection?
    var hoveredInstanceID: UUID?

    // MARK: Flight Check (pre-launch mod scanner)

    /// Cached scan results per instance id.
    var flightCheckResults: [UUID: FlightCheckResult] = [:]
    /// Instance whose diagnostic sheet is open.
    var flightCheckInstance: GameInstance?
    /// Instance ids currently being scanned.
    var flightCheckRunning: Set<UUID> = []
    /// Instance id a dependency auto-fix is installing into.
    var flightFixInstalling: Set<UUID> = []

    // MARK: - Catalog and content

    var catalog: [MinecraftVersionSummary] = []
    var patchNotes: [PatchNoteEntry] = []
    var selectedVersionDetails: MinecraftVersionDetails?
    var detailedPatchNote: PatchNoteDetail?
    var isBootstrapping = true
    var isLoadingCatalog = false
    var isLoadingPatchNotes = false
    var isLoadingPatchNote = false
    var catalogError: String?
    var patchNotesError: String?

    // MARK: - Runtime

    var snapshot = SystemSnapshot.placeholder
    var javaRuntimes: [JavaRuntime] = []
    var isDiscoveringJava = false
    var isInstallingJava = false
    var installingJavaMajor: Int?
    var activities: [Activity] = []
    var console: [ConsoleEntry] = []
    var isGameRunning = false
    var runningInstanceID: UUID?
    var preparingInstanceIDs: Set<UUID> = []
    var statsByInstance: [UUID: InstanceStats] = [:]
    var boostInstalledInstanceIDs: Set<UUID> = []
    var storageUsage = StorageUsage()
    var isCalculatingStorage = false
    var lastLaunchLogURL: URL?
    var launchStartedAt: Date?

    // MARK: - Authentication

    var deviceCode: DeviceCode?
    var authStatus = ""
    var authError: String?
    var isSigningIn = false

    // MARK: - Modrinth

    var modQuery = ""
    var modType: ModrinthProjectType = .mod
    var modSort: ModrinthSort = .relevance
    var modResults: [ModrinthSearchHit] = []
    var modTotal = 0
    var isSearchingMods = false
    var modSearchError: String?
    var projectDetail: ModrinthProject?
    var projectVersions: [ModrinthVersion] = []
    var isLoadingProject = false
    var projectDetailError: String?
    var installedProjectIDs: Set<String> = []
    var installingProjectID: String?
    var installDetail = ""
    var installFraction: Double?
    var isInstallingBoost = false
    var modUpdates: [ModUpdate] = []
    var isCheckingUpdates = false

    var modUpdateByProjectID: [String: ModUpdate] {
        Dictionary(uniqueKeysWithValues: modUpdates.map { ($0.projectID, $0) })
    }

    // MARK: Neo Studio HUD

    /// True while "Apply HUD" is installing mods / writing configs.
    var isApplyingHUD = false
    var hudApplyDetail = ""

    // MARK: - Services

    let versions: VersionService
    let fabric: FabricService
    let installer: GameInstaller
    let auth: MicrosoftAuthService
    let java: JavaRuntimeManager
    let modrinth: ModrinthService
    let modInstaller: ModInstaller
    let gameProcess: GameProcess
    let dedicatedServers: DedicatedServerService
    /// Bedrock Dedicated Servers (bedrock_server.exe under Wine).
    let bedrockServers: BedrockServerService
    let metrics: SystemMetricsProvider

    // MARK: - Private

    private var didLoad = false
    private var saveTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var modSearchTask: Task<Void, Never>?
    private var currentLogWriter: GameLogWriter?
    private var claimedDefaultInstance = false
    /// Watches the running instance's `config/` directory so in-game HUD
    /// edits made by the companion mod flow back into `settings.hudLayout`.
    private var hudWatcherSource: (any DispatchSourceFileSystemObject)?
    private var hudWatchedConfigURL: URL?
    private var hudLastHandledModification: Date?
    /// NeoCraft bridge (in-game companion mods): running instance, the
    /// `commands/` dir watcher and the periodic `state.json` writer.
    /// Internal (not private) so `NeoCraftBridge.swift` can reach them.
    var bridgeInstance: GameInstance?
    var bridgeWatcherSource: (any DispatchSourceFileSystemObject)?
    var bridgeStateTask: Task<Void, Never>?
    var bridgeWorldsCache: [WorldInfo]?
    var bridgeWorldsCacheDate: Date?
    /// Per-server log files mirroring the dashboard console to disk.
    private var serverLogWriters: [UUID: GameLogWriter] = [:]

    init() {
        let versions = VersionService()
        let fabric = FabricService()
        let modrinth = ModrinthService()

        self.versions = versions
        self.fabric = fabric
        self.installer = GameInstaller(versions: versions, fabric: fabric)
        self.auth = MicrosoftAuthService()
        self.java = JavaRuntimeManager()
        self.modrinth = modrinth
        self.modInstaller = ModInstaller(modrinth: modrinth)
        self.gameProcess = GameProcess()
        self.dedicatedServers = DedicatedServerService(versions: versions, fabric: fabric)
        self.bedrockServers = BedrockServerService()
        self.metrics = SystemMetricsProvider()

        let store = Persistence.load()
        self.settings = store.settings
        self.instances = store.instances
        self.accounts = store.accounts
        self.activeAccountID = store.activeAccountID
        self.selectedInstanceID = store.selectedInstanceID

        if let activeAccountID, !accounts.contains(where: { $0.uuid == activeAccountID }) {
            self.activeAccountID = accounts.first?.uuid
        } else if activeAccountID == nil {
            self.activeAccountID = accounts.first?.uuid
        }
        if let selected = selectedInstanceID {
            if !instances.contains(where: { $0.id == selected }) {
                self.selectedInstanceID = instances.first?.id
            }
        } else {
            self.selectedInstanceID = instances.first?.id
        }

        didLoad = true
        SoundManager.shared.enabled = settings.uiSoundsEnabled
        SoundManager.shared.volume = settings.uiSoundVolume
        StudioTheme.sync(settings)
        appendConsole("NeoCraft \(AppConstants.version) ready.", level: .info)
        startMetrics()
        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    // MARK: - Derived state

    var selectedInstance: GameInstance? {
        if let selectedInstanceID,
           let instance = instances.first(where: { $0.id == selectedInstanceID }) {
            return instance
        }
        return instances.first
    }

    var activeAccount: MinecraftAccount? {
        if let activeAccountID,
           let account = accounts.first(where: { $0.uuid == activeAccountID }) {
            return account
        }
        return accounts.first
    }

    var latestRelease: String? {
        catalog.first(where: { $0.isRelease })?.id
    }

    var selectedInstanceStats: InstanceStats? {
        guard let id = selectedInstance?.id else { return nil }
        return statsByInstance[id]
    }

    var modSearchGameVersion: String {
        selectedInstance?.minecraftVersion ?? ""
    }

    var modSearchLoader: String {
        selectedInstance?.loader == .fabric ? "fabric" : ""
    }

    /// Adaptive Performance: on battery, Low Power Mode or heat, the launcher
    /// silently drops to Cool & Quiet; on AC it unlocks Max Performance.
    var effectiveThermalMode: ThermalMode {
        guard settings.adaptivePerformance else { return settings.thermalMode }
        let hot = snapshot.thermalState == .serious || snapshot.thermalState == .critical
        if snapshot.lowPowerMode || !snapshot.onACPower || hot {
            return .coolQuiet
        }
        return .maxPerformance
    }

    var requiredJavaMajor: Int? {
        selectedVersionDetails?.requiredJavaMajor
    }

    var isPreparingSelectedInstance: Bool {
        guard let id = selectedInstance?.id else { return false }
        return preparingInstanceIDs.contains(id)
    }

    func instance(for id: UUID?) -> GameInstance? {
        guard let id else { return nil }
        return instances.first(where: { $0.id == id })
    }

    func isRunning(_ instance: GameInstance) -> Bool {
        isGameRunning && runningInstanceID == instance.id
    }

    func isPreparing(_ instance: GameInstance) -> Bool {
        preparingInstanceIDs.contains(instance.id)
    }

    func isBoostInstalled(_ instance: GameInstance) -> Bool {
        boostInstalledInstanceIDs.contains(instance.id)
    }

    func versionIsInstalled(_ instance: GameInstance) -> Bool {
        InstanceScanner.clientJarExists(for: instance)
    }

    // MARK: - Bootstrapping

    func bootstrap() async {
        isBootstrapping = true
        hostedServers = HostedServerStore.discover()
        await dedicatedServers.setExitHandler { [weak self] id, status in
            Task { @MainActor in
                self?.handleServerExit(id: id, status: status)
            }
        }
        await bedrockServers.setExitHandler { [weak self] id, status in
            Task { @MainActor in
                self?.handleServerExit(id: id, status: status)
            }
        }
        await loadJavaRuntimes()
        async let catalogLoad: Void = reloadCatalog()
        async let patchNoteLoad: Void = loadPatchNotes()
        _ = await (catalogLoad, patchNoteLoad)
        ensureDefaultInstance()
        selectionDidChange()
        StudioTheme.refreshBiomeAccent()
        refreshBedrockContent()
        isBootstrapping = false
        // Servers flagged "Start with NeoCraft" boot after the UI is up.
        // Bedrock servers wait for their own beta flag.
        for server in hostedServers where server.autoStart {
            if server.edition == .bedrock, !settings.betaFeatures.bedrockServers { continue }
            startHostedServer(server)
        }
    }

    func reloadCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            catalog = try await versions.recentVersions(
                includeSnapshots: settings.showSnapshots,
                limit: 120
            )
            catalogError = nil
        } catch {
            if catalog.isEmpty {
                catalogError = error.localizedDescription
            }
        }
    }

    func loadPatchNotes() async {
        isLoadingPatchNotes = true
        defer { isLoadingPatchNotes = false }
        do {
            patchNotes = try await versions.patchNotes(limit: 18)
            patchNotesError = nil
        } catch {
            patchNotesError = error.localizedDescription
        }
    }

    private func ensureDefaultInstance() {
        guard instances.isEmpty, !claimedDefaultInstance else { return }
        claimedDefaultInstance = true
        let version = catalog.first(where: { $0.isRelease })?.id ?? "1.21.1"
        let instance = GameInstance(
            name: "Neo Survival",
            minecraftVersion: version,
            loader: .fabric,
            iconSymbol: "leaf.fill",
            colorHex: InstanceStyle.palette[0],
            neoBoost: true
        )
        instances = [instance]
        selectedInstanceID = instance.id
    }

    func selectionDidChange() {
        if selectedInstance?.edition == .bedrock, section == .mods {
            section = .play
        }
        guard let instance = selectedInstance else {
            installedProjectIDs = []
            modUpdates = []
            selectedVersionDetails = nil
            return
        }
        refreshStats(for: instance)
        loadVersionDetails(for: instance)
        Task { [weak self] in
            guard let self else { return }
            let ids = await self.modInstaller.installedProjectIDs(for: instance)
            if self.selectedInstanceID == instance.id {
                self.installedProjectIDs = ids
            }
        }
        if section == .mods {
            searchMods(reset: true)
            checkForUpdates()
        }
    }

    func loadVersionDetails(for instance: GameInstance) {
        Task { [weak self] in
            guard let self else { return }
            guard let details = try? await self.versions.details(for: instance.minecraftVersion) else { return }
            if self.selectedInstanceID == instance.id {
                self.selectedVersionDetails = details
            }
        }
    }

    // MARK: - Persistence

    private func scheduleSave() {
        guard didLoad else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(280))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard didLoad else { return }
        let store = StoreFile(
            settings: settings,
            instances: instances,
            accounts: accounts,
            activeAccountID: activeAccountID,
            selectedInstanceID: selectedInstanceID
        )
        do {
            try Persistence.save(store)
        } catch {
            NSLog("NeoCraft: could not save state: \(error)")
        }
    }

    // MARK: - Toasts, alerts, console

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2.8))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func presentError(_ title: String, _ error: any Error) {
        alert = AppAlert(title: title, message: error.localizedDescription)
        appendConsole("\(title): \(error.localizedDescription)", level: .error)
        SoundManager.shared.play(.error)
    }

    func appendConsole(_ text: String, level: ConsoleLevel = .info) {
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }
        let entry = ConsoleEntry(String(trimmed.suffix(24_000)), level: level)
        console.append(entry)
        if console.count > 4_000 {
            console.removeFirst(console.count - 4_000)
        }
    }

    private func appendGameOutput(_ text: String, defaultLevel: ConsoleLevel) {
        var level = defaultLevel
        let lowercased = text.lowercased()
        if lowercased.contains("error") || lowercased.contains("exception") || lowercased.contains("fatal") {
            level = .error
        } else if lowercased.contains("warn") {
            level = .warning
        }
        appendConsole(text, level: level)
    }

    func clearConsole() {
        console.removeAll(keepingCapacity: true)
        appendConsole("Console cleared.", level: .info)
    }

    func copyConsoleToClipboard() {
        let text = console.map { "[\($0.date.formatted(date: .omitted, time: .standard))] \($0.text)" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("Console copied to clipboard")
    }

    // MARK: - Activities

    @discardableResult
    private func beginActivity(_ title: String, detail: String = "Starting…") -> UUID {
        let activity = Activity(title: title, detail: detail)
        activities.insert(activity, at: 0)
        if activities.count > 10 {
            activities = Array(activities.prefix(10))
        }
        return activity.id
    }

    private func updateActivity(_ id: UUID, fraction: Double?, detail: String) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        if let fraction {
            activities[index].progress = min(max(fraction, 0), 1)
        }
        activities[index].detail = detail
    }

    private func finishActivity(_ id: UUID, success: Bool, detail: String) {
        guard let index = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[index].state = success ? .success : .failure
        activities[index].detail = detail
        if success {
            activities[index].progress = 1
            SoundManager.shared.play(.chime)
        }
    }

    // MARK: - System metrics and storage

    private func startMetrics() {
        snapshot = metrics.sample()
        metricsTask?.cancel()
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard let self else { return }
                self.snapshot = self.metrics.sample()
            }
        }
    }

    func refreshStats(for instance: GameInstance) {
        Task { [weak self] in
            guard let self else { return }
            var stats = await Task.detached(priority: .utility) {
                InstanceScanner.scan(instance)
            }.value
            let boost = await self.modInstaller.isBoostInstalled(for: instance)
            stats.boostInstalled = boost
            self.statsByInstance[instance.id] = stats
            if boost {
                self.boostInstalledInstanceIDs.insert(instance.id)
            } else {
                self.boostInstalledInstanceIDs.remove(instance.id)
            }
        }
    }

    func refreshAllStats() {
        for instance in instances {
            refreshStats(for: instance)
        }
        refreshInstalledProjects()
    }

    func refreshInstalledProjects() {
        guard let instance = selectedInstance else {
            installedProjectIDs = []
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let ids = await self.modInstaller.installedProjectIDs(for: instance)
            if self.selectedInstanceID == instance.id {
                self.installedProjectIDs = ids
            }
        }
    }

    func refreshStorageUsage() {
        guard !isCalculatingStorage else { return }
        isCalculatingStorage = true
        let shared = AppPaths.shared
        let instances = AppPaths.instances
        let cache = AppPaths.cache
        let runtime = AppPaths.runtime
        Task { [weak self] in
            let usage = await Task.detached(priority: .utility) {
                StorageUsage(
                    sharedBytes: InstanceScanner.directorySize(shared),
                    instanceBytes: InstanceScanner.directorySize(instances),
                    cacheBytes: InstanceScanner.directorySize(cache),
                    runtimeBytes: InstanceScanner.directorySize(runtime)
                )
            }.value
            guard let self else { return }
            self.storageUsage = usage
            self.isCalculatingStorage = false
        }
    }

    func clearCache() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: AppPaths.cache,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
        showToast("Download cache cleared")
        refreshStorageUsage()
    }

    // MARK: - Instances

    func beginCreateInstance() {
        // Bedrock requires the beta flag — fall back to Java when it's off.
        let edition = settings.betaFeatures.bedrockEdition ? settings.preferredEdition : .java
        let isBedrock = edition == .bedrock
        let version = isBedrock
            ? "1.21.124"
            : (latestRelease ?? selectedInstance?.minecraftVersion ?? "1.21.1")
        editingInstance = GameInstance(
            name: "New Instance",
            minecraftVersion: version,
            edition: edition,
            loader: isBedrock ? .vanilla : .fabric,
            iconSymbol: "cube.fill",
            colorHex: InstanceStyle.palette[1],
            neoBoost: !isBedrock
        )
    }

    func beginEditInstance(_ instance: GameInstance) {
        editingInstance = instance
    }

    func isExistingInstance(_ instance: GameInstance) -> Bool {
        instances.contains(where: { $0.id == instance.id })
    }

    func saveInstance(_ instance: GameInstance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
            showToast("Updated \(instance.name)")
        } else {
            instances.append(instance)
            selectedInstanceID = instance.id
            showToast("Created \(instance.name)")
        }
        refreshStats(for: instance)
        loadVersionDetails(for: instance)
        if section == .mods {
            searchMods(reset: true)
        }
        // Fabric instances always get Fabric API ensured on create and on
        // every edit/save; the companion HUD jar is a beta feature.
        if instance.loader == .fabric {
            Task { [weak self] in
                await self?.ensureFabricRuntimeMods(for: instance)
            }
        }
    }

    /// Replaces an instance in place (per-instance settings edited in the
    /// Detail Hub's Config tab).
    func updateInstance(_ instance: GameInstance) {
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = instance
        }
        refreshStats(for: instance)
    }

    func deleteInstance(_ instance: GameInstance) {
        guard !isRunning(instance), !isPreparing(instance) else {
            showToast("Stop the game before deleting this instance")
            return
        }
        do {
            if FileManager.default.fileExists(atPath: instance.directory.path) {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: instance.directory, resultingItemURL: &resultingURL)
            }
            instances.removeAll(where: { $0.id == instance.id })
            statsByInstance[instance.id] = nil
            boostInstalledInstanceIDs.remove(instance.id)
            if selectedInstanceID == instance.id {
                selectedInstanceID = instances.first?.id
            }
            showToast("Moved \(instance.name) to the Bin")
            selectionDidChange()
        } catch {
            presentError("Couldn't delete instance", error)
        }
    }

    func duplicateInstance(_ instance: GameInstance) {
        var copy = instance
        copy.id = UUID()
        copy.name = "\(instance.name) Copy"
        copy.created = Date()
        copy.lastPlayed = nil
        copy.totalPlayTime = 0
        copy.fabricLoaderVersion = instance.fabricLoaderVersion
        instances.append(copy)
        selectedInstanceID = copy.id
        refreshStats(for: copy)
        showToast("Duplicated \(instance.name)")

        // Carry over the game directory (mods, saves, config, resourcepacks)
        // so the copy is actually playable, not just metadata.
        let source = instance.gameDirectory
        let destination = copy.gameDirectory
        Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: source.path) else { return }
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func selectInstance(_ instance: GameInstance) {
        selectedInstanceID = instance.id
        selectionDidChange()
    }

    func revealInstanceFolder(_ instance: GameInstance) {
        try? FileManager.default.createDirectory(at: instance.gameDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([instance.gameDirectory])
    }

    // MARK: - Accounts

    func beginSignIn() {
        if isSigningIn {
            showAuthSheet = true
            return
        }
        showAuthSheet = true
        authError = nil
        deviceCode = nil
        authStatus = "Contacting Microsoft…"
        isSigningIn = true
        authTask = Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await self.auth.requestDeviceCode()
                guard !Task.isCancelled else { return }
                self.deviceCode = code
                self.authStatus = "Enter the code in your browser to continue."
                let (account, _) = try await self.auth.signIn(deviceCode: code) { status in
                    Task { @MainActor in
                        self.authStatus = status
                    }
                }
                guard !Task.isCancelled else { return }
                self.accounts.removeAll(where: { $0.uuid == account.uuid })
                self.accounts.append(account)
                self.activeAccountID = account.uuid
                self.isSigningIn = false
                self.showAuthSheet = false
                self.showToast("Signed in as \(account.name)")
                self.saveNow()
            } catch is CancellationError {
                self.isSigningIn = false
            } catch {
                self.isSigningIn = false
                self.authError = error.localizedDescription
                self.authStatus = "Sign-in did not complete."
                self.appendConsole("Sign-in failed: \(error.localizedDescription)", level: .error)
            }
        }
    }

    func cancelSignIn() {
        authTask?.cancel()
        authTask = nil
        isSigningIn = false
        deviceCode = nil
        authStatus = ""
        authError = nil
        showAuthSheet = false
    }

    func removeAccount(_ account: MinecraftAccount) {
        Task { await auth.removeCredentials(for: account.uuid) }
        KeychainStore.delete(for: account.uuid)
        accounts.removeAll(where: { $0.uuid == account.uuid })
        if activeAccountID == account.uuid {
            activeAccountID = accounts.first?.uuid
        }
        showToast("Removed \(account.name)")
    }

    func setActiveAccount(_ account: MinecraftAccount) {
        activeAccountID = account.uuid
        if let index = accounts.firstIndex(where: { $0.uuid == account.uuid }) {
            accounts[index].lastUsed = Date()
        }
        showToast("Playing as \(account.name)")
    }

    /// The instance currently running, if any.
    var runningInstance: GameInstance? {
        guard let runningInstanceID else { return nil }
        return instances.first { $0.id == runningInstanceID }
    }

    /// Fresh Minecraft access token for Minecraft Services calls (skin studio).
    /// Goes through the auth service so expired sessions refresh automatically.
    func minecraftAccessToken(for account: MinecraftAccount) async throws -> String {
        guard !account.isOffline else { throw AuthError.offlineAccount }
        return try await auth.validSession(for: account).accessToken
    }

    func validateAccount(_ account: MinecraftAccount) {
        guard !account.isOffline else {
            showToast("\(account.name) is an offline account — no session to validate")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await self.auth.validSession(for: account)
                self.showToast("Session valid until \(session.expiresAt.formatted(date: .abbreviated, time: .shortened))")
            } catch {
                self.presentError("Session expired", error)
            }
        }
    }

    /// Local skin image for offline accounts, used by avatar views.
    /// Microsoft accounts render their skin through Crafatar instead.
    func avatarImage(for account: MinecraftAccount) -> NSImage? {
        guard account.isOffline, let skinURL = account.skinURL ?? Optional(AppPaths.skinFile(for: account.uuid)),
              FileManager.default.fileExists(atPath: skinURL.path) else { return nil }
        return NSImage(contentsOf: skinURL)
    }

    // MARK: - Offline accounts

    /// Creates a local offline profile with a deterministic Minecraft offline
    /// UUID (MD5 of "OfflinePlayer:" + name, version-3 variant bits).
    func createOfflineAccount(name: String, skinPNG: Data?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OfflineIdentity.isValidUsername(trimmed) else {
            alert = AppAlert(
                title: "Invalid username",
                message: "Offline names must be 3–16 characters using only letters, numbers and underscores."
            )
            return
        }
        let uuid = OfflineIdentity.uuid(for: trimmed)
        guard !accounts.contains(where: { $0.uuid == uuid }) else {
            showToast("\(trimmed) already exists as an offline account")
            return
        }

        var account = MinecraftAccount(
            uuid: uuid,
            name: trimmed,
            skinURL: nil,
            addedAt: Date(),
            lastUsed: nil,
            isOffline: true
        )
        if let skinPNG {
            let skinURL = AppPaths.skinFile(for: uuid)
            if (try? skinPNG.write(to: skinURL)) != nil {
                account.skinURL = skinURL
            }
        }
        accounts.append(account)
        activeAccountID = uuid
        showOfflineAccountSheet = false
        showToast("Created offline account \(trimmed)")
        SoundManager.shared.play(.chime)
        appendConsole("Created offline account \(trimmed) (\(uuid))", level: .info)
    }

    func updateOfflineSkin(_ account: MinecraftAccount, pngData: Data) {
        guard account.isOffline else { return }
        let skinURL = AppPaths.skinFile(for: account.uuid)
        guard (try? pngData.write(to: skinURL)) != nil else {
            presentError("Couldn't save skin", AppError.install("The skin PNG could not be written to \(skinURL.path)"))
            return
        }
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index].skinURL = skinURL
        }
        showToast("Skin updated for \(account.name)")
    }

    /// Opens a PNG picker and applies the chosen skin to an offline account.
    func changeOfflineSkin(for account: MinecraftAccount) {
        guard account.isOffline else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a 64×64 Minecraft skin PNG for \(account.name)"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        updateOfflineSkin(account, pngData: data)
    }

    // MARK: - Java

    func loadJavaRuntimes() async {
        isDiscoveringJava = true
        let runtimes = await java.discoverRuntimes()
        javaRuntimes = runtimes
        isDiscoveringJava = false
    }

    func installJava(major: Int) {
        guard !isInstallingJava else { return }
        isInstallingJava = true
        installingJavaMajor = major
        let activity = beginActivity("Installing Java \(major)", detail: "Contacting Eclipse Adoptium…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let runtime = try await self.java.ensureRuntime(major: major) { update in
                    Task { @MainActor in
                        self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
                    }
                }
                self.javaRuntimes = await self.java.discoverRuntimes()
                self.isInstallingJava = false
                self.installingJavaMajor = nil
                self.finishActivity(activity, success: true, detail: "Installed \(runtime.name)")
                self.showToast("Java \(major) is ready")
                SoundManager.shared.play(.chime)
                self.refreshStorageUsage()
            } catch {
                self.isInstallingJava = false
                self.installingJavaMajor = nil
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't install Java \(major)", error)
            }
        }
    }

    func removeJava(_ runtime: JavaRuntime) {
        guard runtime.isManaged else {
            showToast("Only NeoCraft-managed runtimes can be removed here")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.java.removeRuntime(runtime)
                if self.settings.selectedJavaPath == runtime.executablePath {
                    self.settings.selectedJavaPath = nil
                }
                await self.loadJavaRuntimes()
                self.showToast("Moved \(runtime.name) to the Bin")
                self.refreshStorageUsage()
            } catch {
                self.presentError("Couldn't remove Java runtime", error)
            }
        }
    }

    private func resolveJava(
        requiredMajor: Int,
        preferredJavaPath: String?,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> JavaRuntime {
        if let path = preferredJavaPath, !path.isEmpty {
            guard let runtime = await java.runtime(executablePath: path) else {
                throw AppError.invalidJava(path)
            }
            guard runtime.majorVersion >= requiredMajor else {
                throw AppError.javaTooOld(required: requiredMajor, found: runtime.majorVersion)
            }
            return runtime
        }
        if let path = settings.selectedJavaPath, !path.isEmpty {
            guard let runtime = await java.runtime(executablePath: path) else {
                throw AppError.invalidJava(path)
            }
            guard runtime.majorVersion >= requiredMajor else {
                throw AppError.javaTooOld(required: requiredMajor, found: runtime.majorVersion)
            }
            return runtime
        }

        let runtimes = await java.discoverRuntimes()
        javaRuntimes = runtimes
        if let exact = runtimes.first(where: { $0.majorVersion == requiredMajor && $0.isAppleSilicon }) {
            return exact
        }
        if let newer = runtimes
            .filter({ $0.majorVersion >= requiredMajor && $0.isAppleSilicon })
            .sorted(by: { $0.majorVersion < $1.majorVersion })
            .first {
            return newer
        }

        progress(ProgressUpdate(fraction: nil, detail: "Java \(requiredMajor) is required. Downloading Eclipse Temurin…"))
        let runtime = try await java.ensureRuntime(major: requiredMajor, progress: progress)
        javaRuntimes = await java.discoverRuntimes()
        return runtime
    }

    // MARK: - Game preparation and launching

    func prepareGame(_ instance: GameInstance) {
        guard instance.edition == .java else {
            // Bedrock has nothing to prepare inside NeoCraft — the runtime
            // is the NeoCraft Bedrock component bundled in this app's
            // Resources, which Play launches directly.
            guard settings.betaFeatures.bedrockEdition else {
                alert = AppAlert(
                    title: "Bedrock beta",
                    message: "NeoCraft Bedrock is a beta feature — enable it in Settings → Beta Features."
                )
                return
            }
            guard bedrockSystemSupported else {
                presentBedrockSystemUnsupported()
                return
            }
            if bedrockLauncherCandidate != nil {
                showToast("Bedrock is bundled — press Play to launch")
                appendConsole("NeoCraft Bedrock is bundled for Bedrock instance \(instance.name)", level: .info)
            } else {
                presentBedrockMissing()
            }
            return
        }
        guard !isPreparing(instance) else { return }
        preparingInstanceIDs.insert(instance.id)
        let activity = beginActivity("Preparing \(instance.name)", detail: "Resolving version…")
        Task { [weak self] in
            guard let self else { return }
            defer { self.preparingInstanceIDs.remove(instance.id) }
            do {
                let resolved = try await self.installer.resolve(instance: instance)
                self.persistLoaderVersion(resolved.fabricLoaderVersion, for: instance)
                let runtime = try await self.resolveJava(
                    requiredMajor: resolved.details.requiredJavaMajor,
                    preferredJavaPath: instance.javaPath
                ) { update in
                    Task { @MainActor in
                        self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
                    }
                }
                let prepared = try await self.installer.prepare(
                    instance: instance,
                    resolved: resolved,
                    concurrency: self.settings.downloadConcurrency
                ) { update in
                    Task { @MainActor in
                        self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
                    }
                }
                try OptionsTweaker.apply(mode: effectiveThermalMode, settings: settings, instance: instance, to: prepared.gameDirectory)
                self.finishActivity(
                    activity,
                    success: true,
                    detail: "Ready to play with \(runtime.name)"
                )
                self.showToast("\(instance.name) is ready to play")
                self.refreshStats(for: instance)
                self.refreshStorageUsage()
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't prepare \(instance.name)", error)
            }
        }
    }

    /// NeoCraft Bedrock.app bundled inside NeoCraft.app's Resources by
    /// build.sh — the only Bedrock runtime NeoCraft uses. It is launched in
    /// place; nothing is copied into /Applications. `nil` in dev builds
    /// (`swift run`) or when the Bedrock component wasn't built first.
    private static var bundledBedrockApp: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/Bedrock/NeoCraft Bedrock.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The NeoCraft Bedrock.app bundled inside this NeoCraft build, if any.
    var bedrockLauncherCandidate: URL? { Self.bundledBedrockApp }

    /// lsregister makes an app Launch Services doesn't know yet visible to
    /// `openApplication` immediately instead of after the next login.
    private func registerWithLaunchServices(_ app: URL) {
        let lsregister = URL(fileURLWithPath:
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        guard FileManager.default.isExecutableFile(atPath: lsregister.path) else { return }
        let process = Process()
        process.executableURL = lsregister
        process.arguments = ["-f", app.path]
        try? process.run()
        process.waitUntilExit()
    }

    /// NeoCraft Bedrock needs macOS 27: it runs the Windows edition of
    /// Minecraft through Wine and Apple's D3DMetal.
    private var bedrockSystemSupported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    /// Launches Bedrock through the NeoCraft Bedrock component bundled in
    /// this app. With `autoPlay` it starts the game directly; without it the
    /// component's own window opens for accounts, profiles and settings.
    func openBedrockGame(autoPlay: Bool = true) {
        // The whole Bedrock track is a beta feature — every entry point
        // (Play, the gear button, instance actions) funnels through here.
        guard settings.betaFeatures.bedrockEdition else {
            alert = AppAlert(
                title: "Bedrock beta",
                message: "NeoCraft Bedrock is a beta feature — enable it in Settings → Beta Features."
            )
            return
        }
        guard bedrockSystemSupported else {
            presentBedrockSystemUnsupported()
            return
        }
        guard let app = Self.bundledBedrockApp else {
            presentBedrockMissing()
            return
        }
        registerWithLaunchServices(app)
        let configuration = NSWorkspace.OpenConfiguration()
        // Bedrock localizes through .lproj bundles, which follow the system
        // locale — hand it NeoCraft's resolved language so an in-app
        // override applies there too.
        configuration.arguments = (autoPlay ? ["--play"] : [])
            + ["-AppleLanguages", "(\(L10n.currentLanguage))"]
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in
                    self.presentError("Couldn't launch NeoCraft Bedrock", error)
                }
            }
        }
    }

    /// Opens NeoCraft Bedrock's own window — accounts, profiles, worlds and
    /// settings live there; Play in NeoCraft launches the game directly.
    func openBedrockLauncher() {
        openBedrockGame(autoPlay: false)
    }

    /// Bedrock can't run on this macOS version — NeoCraft Bedrock requires 27.
    private func presentBedrockSystemUnsupported() {
        alert = AppAlert(
            title: "macOS 27 required",
            message: "NeoCraft Bedrock needs macOS 27 or newer to run Minecraft Bedrock."
        )
        appendConsole("Bedrock requires macOS 27; this Mac runs an older version.", level: .warning)
    }

    /// This NeoCraft build has no bundled Bedrock component — it happens in
    /// dev builds or when NeoCraft Bedrock wasn't built before build.sh ran.
    private func presentBedrockMissing() {
        alert = AppAlert(
            title: "NeoCraft Bedrock missing",
            message: "This NeoCraft build doesn't include NeoCraft Bedrock. Build Sources/NeoCraft Bedrock first (scripts/build.sh inside it), then rebuild NeoCraft so build.sh can bundle it."
        )
        appendConsole("NeoCraft Bedrock is not bundled in this NeoCraft build.", level: .warning)
    }

    func startGame(_ instance: GameInstance? = nil, quickPlay: String? = nil, quickPlayWorld: String? = nil) {
        guard let instance = instance ?? selectedInstance else {
            alert = AppAlert(title: "No instance selected", message: "Create an instance before launching Minecraft.")
            return
        }
        guard !isGameRunning else {
            showToast("Minecraft is already running")
            showConsole = true
            return
        }
        guard !isPreparing(instance) else {
            showToast("This instance is already being prepared")
            return
        }
        guard instance.edition == .java else {
            openBedrockGame()
            return
        }
        guard let account = activeAccount else {
            showToast("Sign in with a Microsoft account to play")
            beginSignIn()
            return
        }

        preparingInstanceIDs.insert(instance.id)
        let activity = beginActivity("Launching \(instance.name)", detail: "Preparing your world…")
        Task { [weak self] in
            guard let self else { return }
            defer { self.preparingInstanceIDs.remove(instance.id) }
            do {
                try await self.launch(instance: instance, account: account, activity: activity, quickPlay: quickPlay, quickPlayWorld: quickPlayWorld)
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't launch \(instance.name)", error)
            }
        }
    }

    private func launch(instance: GameInstance, account: MinecraftAccount, activity: UUID, quickPlay: String? = nil, quickPlayWorld: String? = nil) async throws {
        let resolved = try await installer.resolve(instance: instance)
        persistLoaderVersion(resolved.fabricLoaderVersion, for: instance)
        updateActivity(activity, fraction: 0.02, detail: "Resolved \(resolved.details.id). Checking Java \(resolved.details.requiredJavaMajor)…")

        let runtime = try await resolveJava(
            requiredMajor: resolved.details.requiredJavaMajor,
            preferredJavaPath: instance.javaPath
        ) { update in
            Task { @MainActor in
                self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
            }
        }
        updateActivity(activity, fraction: 0.05, detail: "Using \(runtime.name)")

        let prepared = try await installer.prepare(
            instance: instance,
            resolved: resolved,
            concurrency: settings.downloadConcurrency
        ) { update in
            Task { @MainActor in
                self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
            }
        }

        if instance.loader == .fabric && instance.neoBoost && !isBoostInstalled(instance) {
            updateActivity(activity, fraction: 0.92, detail: "Installing Neo Boost performance mods…")
            do {
                _ = try await modInstaller.installBoost(into: instance) { update in
                    Task { @MainActor in
                        self.updateActivity(
                            activity,
                            fraction: 0.92 + (update.fraction ?? 0) * 0.04,
                            detail: "Neo Boost · \(update.detail)"
                        )
                    }
                }
                boostInstalledInstanceIDs.insert(instance.id)
                refreshStats(for: instance)
            } catch {
                appendConsole("Neo Boost could not be installed: \(error.localizedDescription)", level: .warning)
                showToast("Neo Boost skipped: \(error.localizedDescription)")
            }
        }

        // macOS input fixes (trackpad scroll/right-click) are opt-in per
        // instance and install silently alongside the launch.
        if instance.macosInputFix {
            await modInstaller.ensureInputFix(for: instance)
        }

        // Every Fabric launch guarantees Fabric API is present; the
        // companion HUD jar only ships while the beta feature is enabled.
        if instance.loader == .fabric {
            await ensureFabricRuntimeMods(for: instance)
        }

        try OptionsTweaker.apply(mode: effectiveThermalMode, settings: settings, instance: instance, to: prepared.gameDirectory)

        updateActivity(activity, fraction: 0.97, detail: "Authorizing your session…")
        let session: MinecraftSession
        if account.isOffline {
            // Offline profiles launch without Xbox Live: the client accepts a
            // self-consistent UUID/token pair and stays in offline mode.
            let plainUUID = account.uuid.replacingOccurrences(of: "-", with: "").lowercased()
            session = MinecraftSession(
                accessToken: plainUUID,
                uuid: account.uuid,
                name: account.name,
                xuid: "",
                expiresAt: .distantFuture
            )
        } else {
            session = try await auth.validSession(for: account)
        }

        let command = try LaunchPlanner.makeCommand(
            prepared: prepared,
            instance: instance,
            session: session,
            java: runtime,
            settings: settings,
            thermalMode: effectiveThermalMode,
            quickPlayAddress: quickPlay,
            quickPlayWorld: quickPlayWorld,
            offline: account.isOffline
        )

        let logURL = AppPaths.logs.appendingPathComponent(
            "launch-\(Int(Date().timeIntervalSince1970)).log",
            isDirectory: false
        )
        let writer = try? GameLogWriter(url: logURL)
        currentLogWriter = writer
        lastLaunchLogURL = writer?.url
        writer?.write("NeoCraft \(AppConstants.version) · \(instance.name) · \(instance.versionLabel)\n")
        writer?.write("Java: \(runtime.name) (\(runtime.executablePath))\n")
        writer?.write("Command: \(LaunchPlanner.redactedDescription(command, secrets: [session.accessToken]))\n\n")

        appendConsole("Launching \(instance.name) with \(runtime.name)", level: .info)
        appendConsole("Profile: \(instance.versionLabel) · \(effectiveThermalMode.title)", level: .info)
        SoundManager.shared.play(.launch)

        try await gameProcess.start(command: command) { text, level in
            Task { @MainActor in
                self.appendGameOutput(text, defaultLevel: level)
                writer?.write(text)
            }
        }

        isGameRunning = true
        runningInstanceID = instance.id
        launchStartedAt = Date()
        if settings.betaFeatures.inGameHUD {
            startHUDConfigWatcher(for: instance)
        }
        startNeoCraftBridge(for: instance)
        finishActivity(activity, success: true, detail: "Minecraft is running")

        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index].lastPlayed = Date()
        }
        refreshStats(for: instance)
        if settings.openConsoleOnLaunch {
            showConsole = true
        }

        let start = Date()
        Task { [weak self] in
            guard let self else { return }
            let status = await self.gameProcess.waitForExit()
            self.handleGameExit(status: status, instance: instance, startedAt: start)
        }
    }

    private func persistLoaderVersion(_ loaderVersion: String?, for instance: GameInstance) {
        guard let loaderVersion, !loaderVersion.isEmpty else { return }
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        if instances[index].fabricLoaderVersion != loaderVersion {
            instances[index].fabricLoaderVersion = loaderVersion
        }
    }

    private func handleGameExit(status: Int32, instance: GameInstance, startedAt: Date) {
        isGameRunning = false
        runningInstanceID = nil
        stopHUDConfigWatcher()
        stopNeoCraftBridge()
        let duration = Date().timeIntervalSince(startedAt)
        launchStartedAt = nil
        currentLogWriter?.write("\n[NeoCraft] Minecraft exited with status \(status).\n")
        currentLogWriter?.close()
        currentLogWriter = nil
        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index].totalPlayTime += max(0, duration)
            instances[index].lastPlayed = Date()
        }
        appendConsole(
            status == 0
                ? "Minecraft exited after \(Formatters.duration(duration))."
                : "Minecraft exited with status \(status) after \(Formatters.duration(duration)).",
            level: status == 0 ? .info : .error
        )
        refreshStats(for: instance)
        if status != 0 {
            handleCrashExit(instance: instance, exitCode: status)
            showToast("Minecraft exited with status \(status). Check the console.")
        }
    }

    /// Crash Doctor: scans the instance's crash reports and latest.log after
    /// a non-zero exit and presents a diagnosis with concrete suggestions.
    private func handleCrashExit(instance: GameInstance, exitCode: Int32) {
        guard let diagnosis = CrashDoctor.diagnose(instance: instance) else { return }
        crashDiagnosis = diagnosis
        SoundManager.shared.play(.error)
    }

    func dismissCrashDiagnosis() {
        crashDiagnosis = nil
    }

    func revealCrashReport(_ diagnosis: CrashDiagnosis) {
        if let url = diagnosis.crashReportURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func stopGame() {
        guard isGameRunning else { return }
        appendConsole("Stopping Minecraft…", level: .warning)
        Task { [weak self] in
            await self?.gameProcess.terminate()
        }
    }

    // MARK: - Neo Boost

    func installBoost(_ instance: GameInstance) {
        guard instance.loader == .fabric else {
            alert = AppAlert(
                title: "Fabric required",
                message: "Neo Boost requires a Fabric instance. Duplicate this instance with Fabric selected instead."
            )
            return
        }
        guard !isInstallingBoost else { return }
        isInstallingBoost = true
        let activity = beginActivity("Installing Neo Boost", detail: "Resolving performance mods…")
        Task { [weak self] in
            guard let self else { return }
            defer { self.isInstallingBoost = false }
            do {
                let installed = try await self.modInstaller.installBoost(into: instance) { update in
                    Task { @MainActor in
                        self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
                    }
                }
                self.finishActivity(
                    activity,
                    success: true,
                    detail: "Installed \(installed.count) performance mods"
                )
                self.boostInstalledInstanceIDs.insert(instance.id)
                self.refreshStats(for: instance)
                self.refreshInstalledProjects()
                self.showToast("Neo Boost is ready")
                SoundManager.shared.play(.chime)
                self.refreshStorageUsage()
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't install Neo Boost", error)
            }
        }
    }

    /// Performance Pack: Neo Boost core plus ModernFix and C2ME.
    func installPerformancePack(_ instance: GameInstance) {
        guard instance.loader == .fabric else {
            alert = AppAlert(
                title: "Fabric required",
                message: "The Performance Pack requires a Fabric instance."
            )
            return
        }
        guard !isInstallingBoost else { return }
        isInstallingBoost = true
        let activity = beginActivity("Installing Performance Pack", detail: "Resolving performance stack…")
        Task { [weak self] in
            guard let self else { return }
            defer { self.isInstallingBoost = false }
            do {
                let installed = try await self.modInstaller.installPerformancePack(into: instance) { update in
                    Task { @MainActor in
                        self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
                    }
                }
                self.finishActivity(
                    activity,
                    success: true,
                    detail: "Installed \(installed.count) performance mods"
                )
                self.boostInstalledInstanceIDs.insert(instance.id)
                self.refreshStats(for: instance)
                self.refreshInstalledProjects()
                self.refreshStorageUsage()
                self.showToast("Performance Pack is ready — set render distance to taste")
                SoundManager.shared.play(.chime)
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't install Performance Pack", error)
            }
        }
    }

    // MARK: - servers.dat (Servers tab)

    /// Live read of an instance's `servers.dat`. Returns [] when absent.
    func loadServers(for instance: GameInstance) -> [MCServerEntry] {
        ServerListService.load(for: instance)
    }

    /// Atomically persists a servers.dat entry list for an instance.
    func saveServers(_ entries: [MCServerEntry], for instance: GameInstance) throws {
        try ServerListService.save(entries, for: instance)
    }

    /// Quick-joins a `servers.dat` entry: selects the owning instance and
    /// launches with `--quickPlayMultiplayer <address>` (same path as
    /// pinned servers).
    func joinServerEntry(_ entry: MCServerEntry, in instance: GameInstance) {
        selectInstance(instance)
        startGame(instance, quickPlay: entry.address)
    }

    // MARK: - World backups

    /// Backs up every world in the instance; backs up all when `world` is nil.
    func backupWorlds(in instance: GameInstance, world: WorldInfo? = nil) {
        guard !backupRunning else { return }
        backupRunning = true
        let useiCloud = settings.backupToiCloud
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.backupRunning = false }
            do {
                if let world {
                    let url = try WorldBackupService.backup(world, instance: instance, useiCloud: useiCloud)
                    self.showToast("Backed up \(world.name) → \(url.lastPathComponent)")
                } else {
                    let urls = try WorldBackupService.backupAll(instance, useiCloud: useiCloud)
                    self.showToast("Backed up \(urls.count) world(s)")
                }
                SoundManager.shared.play(.chime)
            } catch {
                self.presentError("Backup failed", error)
            }
        }
    }

    func worldBackups(for instance: GameInstance) -> [URL] {
        WorldBackupService.existingBackups(instance: instance, useiCloud: settings.backupToiCloud)
    }

    func revealBackup(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Hosted servers (world → Java dedicated server)

    /// `host:port` friends on the LAN type into Minecraft's multiplayer screen.
    static func serverAddress(_ server: HostedServer) -> String {
        "\(LANAddress.primaryIPv4 ?? "localhost"):\(server.port)"
    }

    func isServerRunning(_ server: HostedServer) -> Bool {
        runningServerIDs.contains(server.id)
    }

    func isServerReady(_ server: HostedServer) -> Bool {
        readyServerIDs.contains(server.id)
    }

    func isSettingUpServer(_ server: HostedServer) -> Bool {
        serverSetupIDs.contains(server.id)
    }

    func refreshHostedServers() {
        hostedServers = HostedServerStore.discover()
    }

    // MARK: - Bedrock content sync

    /// Worlds, packs and screenshots found in NeoCraft Bedrock's Wine
    /// prefixes — the same folders the launcher manages, so both apps
    /// always show the same content.
    private(set) var bedrockContent = BedrockContent.Snapshot()

    /// Rescans the Bedrock prefixes. Directory listings only — safe to
    /// call whenever a synced view appears. Skipped entirely while the
    /// Bedrock beta is off so nothing Bedrock-related leaks into the UI
    /// (and no filesystem scan runs for a hidden feature).
    func refreshBedrockContent() {
        guard settings.betaFeatures.bedrockEdition else {
            if !bedrockContent.isEmpty { bedrockContent = BedrockContent.Snapshot() }
            return
        }
        bedrockContent = BedrockContent.snapshot()
    }

    /// Packages a single-player world as a Java dedicated server: downloads
    /// Mojang's server jar for the instance's version, copies the save and
    /// writes eula.txt/server.properties into a fresh server folder.
    func hostWorld(
        _ world: WorldInfo,
        in instance: GameInstance,
        name: String,
        port: Int,
        onlineMode: Bool
    ) {
        guard instance.edition == .java else {
            alert = AppAlert(
                title: "Java Edition only",
                message: "Bedrock worlds can't be hosted as a Minecraft Java server."
            )
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard (1...65535).contains(port) else {
            alert = AppAlert(title: "Invalid port", message: "The server port must be between 1 and 65535.")
            return
        }

        let server = HostedServer(
            name: trimmedName,
            instanceID: instance.id,
            instanceName: instance.name,
            minecraftVersion: instance.minecraftVersion,
            worldName: world.name,
            sourceWorldName: world.name,
            port: port,
            onlineMode: onlineMode
        )
        enqueueServerSetup(server, instance: instance)
    }

    /// Creates a standalone Java dedicated server from the Servers tab:
    /// a fresh world the server generates on first boot, or a copy of a
    /// world from a Java instance. `instance`/`worldName` nil/empty means
    /// "new world".
    func createJavaServer(
        name: String,
        minecraftVersion: String,
        serverType: ServerType,
        port: Int,
        onlineMode: Bool,
        instance: GameInstance?,
        worldName: String,
        group: String = "",
        preset: ServerPreset = .custom
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard (1...65535).contains(port) else {
            alert = AppAlert(title: "Invalid port", message: "The server port must be between 1 and 65535.")
            return
        }
        let sourceWorld = worldName.trimmingCharacters(in: .whitespacesAndNewlines)
        var owner = instance
        if !sourceWorld.isEmpty {
            guard let instance, instance.edition == .java else {
                alert = AppAlert(title: "No Java instance", message: "Pick a Java instance and one of its worlds, or choose “New world”.")
                return
            }
            owner = instance
        } else {
            owner = nil
        }

        let server = HostedServer(
            serverType: serverType,
            name: trimmedName,
            instanceID: owner?.id ?? UUID(),
            instanceName: owner?.name ?? "Standalone",
            minecraftVersion: minecraftVersion,
            worldName: sourceWorld.isEmpty ? "world" : sourceWorld,
            sourceWorldName: sourceWorld,
            port: port,
            onlineMode: onlineMode,
            group: group.trimmingCharacters(in: .whitespacesAndNewlines),
            preset: preset.rawValue
        )
        enqueueServerSetup(server, instance: owner)
    }

    /// Creates a Bedrock Dedicated Server: downloads Mojang's Windows BDS
    /// build ("latest" or a pinned version) for the `bedrock-host` helper.
    func createBedrockServer(
        name: String,
        bedrockVersion: String,
        port: Int,
        onlineMode: Bool,
        levelName: String,
        group: String = "",
        preset: ServerPreset = .custom
    ) {
        guard settings.betaFeatures.bedrockServers else {
            alert = AppAlert(
                title: "Bedrock servers beta",
                message: "Bedrock server hosting is a beta feature — enable it in Settings → Beta Features."
            )
            return
        }
        guard bedrockSystemSupported else {
            presentBedrockSystemUnsupported()
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard (1...65535).contains(port) else {
            alert = AppAlert(title: "Invalid port", message: "The server port must be between 1 and 65535.")
            return
        }
        let level = levelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = HostedServer(
            edition: .bedrock,
            name: trimmedName,
            instanceID: UUID(),
            instanceName: "Bedrock",
            minecraftVersion: bedrockVersion.isEmpty ? "latest" : bedrockVersion,
            worldName: level.isEmpty ? "world" : level,
            sourceWorldName: "",
            port: port,
            onlineMode: onlineMode,
            group: group.trimmingCharacters(in: .whitespacesAndNewlines),
            preset: preset.rawValue
        )
        hostedServers.insert(server, at: 0)
        serverSetupIDs.insert(server.id)
        let activity = beginActivity("Setting up \(server.name)", detail: "Preparing Bedrock Dedicated Server…")
        Task { [weak self] in
            guard let self else { return }
            defer { self.serverSetupIDs.remove(server.id) }
            do {
                try await self.bedrockServers.create(server: server, preview: false) { update in
                    Task { @MainActor in
                        self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
                    }
                }
                // `create` may have resolved "latest" to a pinned version.
                self.hostedServers = HostedServerStore.discover()
                self.finishActivity(activity, success: true, detail: "Ready — press Start to open it to players")
                self.showToast("\(server.name) is ready to host")
                SoundManager.shared.play(.chime)
                self.refreshStorageUsage()
            } catch {
                self.hostedServers.removeAll { $0.id == server.id }
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't set up \(server.name)", error)
            }
        }
    }

    /// Shared setup pipeline for Java hosted servers: resolves Java,
    /// downloads the server software, copies the world when present and
    /// writes the managed configuration.
    private func enqueueServerSetup(_ server: HostedServer, instance: GameInstance?) {
        hostedServers.insert(server, at: 0)
        serverSetupIDs.insert(server.id)
        let activity = beginActivity("Setting up \(server.name)", detail: "Preparing dedicated server…")
        Task { [weak self] in
            guard let self else { return }
            defer { self.serverSetupIDs.remove(server.id) }
            do {
                let details = try await self.versions.details(for: server.minecraftVersion)
                let runtime = try await self.resolveJava(
                    requiredMajor: details.requiredJavaMajor,
                    preferredJavaPath: instance?.javaPath
                ) { update in
                    Task { @MainActor in
                        self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
                    }
                }
                try await self.dedicatedServers.create(server: server, instance: instance, java: runtime) { update in
                    Task { @MainActor in
                        self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
                    }
                }
                self.hostedServers = HostedServerStore.discover()
                self.finishActivity(
                    activity,
                    success: true,
                    detail: "Ready — press Start to open it to players"
                )
                self.showToast("\(server.name) is ready to host")
                SoundManager.shared.play(.chime)
                self.refreshStorageUsage()
            } catch {
                self.hostedServers.removeAll { $0.id == server.id }
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't set up \(server.name)", error)
            }
        }
    }

    /// Boots the dedicated server with the owning instance's Java preference
    /// (falling back to the global Java setting) and its memory profile.
    /// Bedrock servers go through the `bedrock-host` Wine helper instead.
    func startHostedServer(_ server: HostedServer) {
        guard !runningServerIDs.contains(server.id),
              !serverSetupIDs.contains(server.id) else { return }
        if server.edition == .bedrock {
            startBedrockServer(server)
            return
        }
        runningServerIDs.insert(server.id)
        readyServerIDs.remove(server.id)
        let activity = beginActivity("Starting \(server.name)", detail: "Launching dedicated server…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let details = try await self.versions.details(for: server.minecraftVersion)
                let instance = self.instance(for: server.instanceID)
                let runtime = try await self.resolveJava(
                    requiredMajor: details.requiredJavaMajor,
                    preferredJavaPath: instance?.javaPath
                ) { update in
                    Task { @MainActor in
                        self.updateActivity(activity, fraction: update.fraction, detail: update.detail)
                    }
                }
                let memory = min(max(instance?.effectiveMemoryMB ?? self.settings.maxMemoryMB, 1024), 6144)
                let logURL = AppPaths.logs.appendingPathComponent(
                    "server-\(server.name.replacingOccurrences(of: "/", with: "-"))-\(Int(Date().timeIntervalSince1970)).log",
                    isDirectory: false
                )
                let writer = try? GameLogWriter(url: logURL)
                self.serverLogWriters[server.id] = writer
                writer?.write("NeoCraft \(AppConstants.version) · dedicated server · Minecraft \(server.minecraftVersion)\n")
                writer?.write("Address: \(Self.serverAddress(server))\n\n")
                _ = try await self.dedicatedServers.start(
                    server: server,
                    java: runtime,
                    memoryMB: memory,
                    minMemoryMB: self.settings.minMemoryMB
                ) { text, level in
                    Task { @MainActor in
                        self.appendServerOutput(server.id, text: text, level: level)
                        writer?.write(text)
                        if text.contains("Done (") && text.contains("help") {
                            self.readyServerIDs.insert(server.id)
                            self.updateActivity(
                                activity,
                                fraction: 1,
                                detail: "Online at \(Self.serverAddress(server))"
                            )
                        }
                    }
                }
                self.serverStartedAt[server.id] = Date()
                self.finishActivity(
                    activity,
                    success: true,
                    detail: "Running at \(Self.serverAddress(server))"
                )
                self.showToast("\(server.name) is running — join at \(Self.serverAddress(server))")
                if self.settings.openConsoleOnLaunch {
                    self.showConsole = true
                }
            } catch {
                self.runningServerIDs.remove(server.id)
                self.readyServerIDs.remove(server.id)
                self.serverStartedAt[server.id] = nil
                self.serverLogWriters[server.id]?.close()
                self.serverLogWriters[server.id] = nil
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't start \(server.name)", error)
            }
        }
    }

    /// Boots a Bedrock Dedicated Server through the bundled NeoCraft
    /// Bedrock component's `bedrock-host` helper (Wine, headless).
    private func startBedrockServer(_ server: HostedServer) {
        guard let helper = Self.bedrockHostHelper else {
            alert = AppAlert(
                title: "NeoCraft Bedrock missing",
                message: "This NeoCraft build doesn't include the Bedrock server runner. Rebuild NeoCraft Bedrock (scripts/build.sh), then rebuild NeoCraft."
            )
            return
        }
        guard bedrockSystemSupported else {
            presentBedrockSystemUnsupported()
            return
        }
        // The helper needs the launcher's installed Wine engine.
        guard FileManager.default.fileExists(
            atPath: (Self.bedrockDataDirectory.appendingPathComponent("library.json")).path
        ) else {
            alert = AppAlert(
                title: "Engine missing",
                message: "No NeoCraft Bedrock engine is installed — open NeoCraft Bedrock once to finish setup."
            )
            return
        }
        runningServerIDs.insert(server.id)
        readyServerIDs.remove(server.id)
        let activity = beginActivity("Starting \(server.name)", detail: "Launching Bedrock Dedicated Server…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let logURL = AppPaths.logs.appendingPathComponent(
                    "server-\(server.name.replacingOccurrences(of: "/", with: "-"))-\(Int(Date().timeIntervalSince1970)).log",
                    isDirectory: false
                )
                let writer = try? GameLogWriter(url: logURL)
                self.serverLogWriters[server.id] = writer
                writer?.write("NeoCraft \(AppConstants.version) · Bedrock dedicated server · \(server.minecraftVersion)\n")
                writer?.write("Address: \(Self.serverAddress(server))\n\n")
                _ = try await self.bedrockServers.start(
                    server: server,
                    helper: helper,
                    dataDirectory: Self.bedrockDataDirectory
                ) { text, level in
                    Task { @MainActor in
                        self.appendServerOutput(server.id, text: text, level: level)
                        writer?.write(text)
                        // BDS announces readiness with "Server started.".
                        if text.contains("Server started") {
                            self.readyServerIDs.insert(server.id)
                            self.updateActivity(
                                activity,
                                fraction: 1,
                                detail: "Online at \(Self.serverAddress(server))"
                            )
                        }
                    }
                }
                self.serverStartedAt[server.id] = Date()
                self.finishActivity(
                    activity,
                    success: true,
                    detail: "Running at \(Self.serverAddress(server))"
                )
                self.showToast("\(server.name) is running — join at \(Self.serverAddress(server))")
                if self.settings.openConsoleOnLaunch {
                    self.showConsole = true
                }
            } catch {
                self.runningServerIDs.remove(server.id)
                self.readyServerIDs.remove(server.id)
                self.serverStartedAt[server.id] = nil
                self.serverLogWriters[server.id]?.close()
                self.serverLogWriters[server.id] = nil
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't start \(server.name)", error)
            }
        }
    }

    /// `bedrock-host` inside the bundled NeoCraft Bedrock.app — the only
    /// Bedrock runtime NeoCraft uses, same as the game launcher.
    private static var bedrockHostHelper: URL? {
        guard let app = bundledBedrockApp else { return nil }
        let helper = app.appendingPathComponent("Contents/Helpers/bedrock-host")
        return FileManager.default.fileExists(atPath: helper.path) ? helper : nil
    }

    /// The NeoCraft Bedrock component's data directory — where its
    /// installed Wine engine lives for the host helper.
    private static var bedrockDataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("NeoCraft Bedrock", isDirectory: true)
    }

    /// Sends `stop` to the server so it saves its world before exiting.
    func stopHostedServer(_ server: HostedServer) {
        guard runningServerIDs.contains(server.id) else { return }
        appendConsole("Stopping server \(server.name)…", level: .warning)
        Task { [weak self] in
            if server.edition == .bedrock {
                await self?.bedrockServers.stop(server.id)
            } else {
                await self?.dedicatedServers.stop(server.id)
            }
            self?.runningServerIDs.remove(server.id)
            self?.readyServerIDs.remove(server.id)
        }
    }

    /// Stops (if needed) and immediately starts the server again.
    func restartHostedServer(_ server: HostedServer) {
        guard runningServerIDs.contains(server.id) else {
            startHostedServer(server)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if server.edition == .bedrock {
                await self.bedrockServers.stop(server.id)
            } else {
                await self.dedicatedServers.stop(server.id)
            }
            self.runningServerIDs.remove(server.id)
            self.readyServerIDs.remove(server.id)
            self.startHostedServer(server)
        }
    }

    /// Runs a command on the server console (`say`, `list`, `save-all`, …).
    func sendServerCommand(_ server: HostedServer, _ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, runningServerIDs.contains(server.id) else { return }
        appendServerLine(server.id, "> \(trimmed)", level: .info)
        Task {
            if server.edition == .bedrock {
                await bedrockServers.sendCommand(server.id, trimmed)
            } else {
                await dedicatedServers.sendCommand(server.id, trimmed)
            }
        }
    }

    func clearServerConsole(_ server: HostedServer) {
        serverConsoles[server.id] = []
    }

    /// Reads the server's current `server.properties` for the dashboard form.
    func serverProperties(for server: HostedServer) async -> [String: String] {
        if server.edition == .bedrock {
            return await bedrockServers.properties(for: server)
        }
        return await dedicatedServers.properties(for: server)
    }

    /// Writes dashboard edits back to `server.properties` (server must be
    /// stopped — a running server would overwrite them on shutdown).
    func updateServerProperties(_ server: HostedServer, values: [String: String]) {
        Task { [weak self] in
            guard let self else { return }
            do {
                if server.edition == .bedrock {
                    try await self.bedrockServers.updateProperties(server, values: values)
                } else {
                    try await self.dedicatedServers.updateProperties(server, values: values)
                }
                // Keep the launcher's address/join metadata in sync when the
                // dashboard edits the port.
                if let portText = values["server-port"],
                   let port = Int(portText), (1...65535).contains(port), port != server.port {
                    var updated = server
                    updated.port = port
                    try? HostedServerStore.save(updated)
                    if let index = self.hostedServers.firstIndex(where: { $0.id == server.id }) {
                        self.hostedServers[index] = updated
                    }
                    if self.dashboardServer?.id == server.id {
                        self.dashboardServer = updated
                    }
                }
                self.showToast("Server settings saved — restart to apply")
            } catch {
                self.presentError("Couldn't update server settings", error)
            }
        }
    }

    // MARK: - Server world export / import

    /// Zips the hosted world(s) to `destination` — Java exports the
    /// single world folder, Bedrock the whole `worlds/` directory.
    func exportServerWorld(_ server: HostedServer, to destination: URL) {
        let activity = beginActivity("Exporting \(server.name)", detail: "Zipping world…")
        Task { [weak self] in
            guard let self else { return }
            do {
                if server.edition == .bedrock {
                    try await self.bedrockServers.exportWorldZip(server: server, to: destination)
                } else {
                    try await self.dedicatedServers.exportWorldZip(server: server, to: destination)
                }
                self.finishActivity(activity, success: true, detail: "World exported")
                self.showToast("World exported")
                self.reveal(destination.deletingLastPathComponent())
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't export world", error)
            }
        }
    }

    /// Replaces the hosted world(s) with the world folder inside `archive`.
    /// The previous world is parked in `backups/` first. Server must be
    /// stopped.
    func importServerWorld(_ server: HostedServer, from archive: URL) {
        guard !runningServerIDs.contains(server.id) else {
            showToast("Stop the server before importing a world")
            return
        }
        let activity = beginActivity("Importing \(server.name)", detail: "Unzipping world…")
        Task { [weak self] in
            guard let self else { return }
            do {
                if server.edition == .bedrock {
                    try await self.bedrockServers.importWorldZip(server: server, from: archive)
                } else {
                    try await self.dedicatedServers.importWorldZip(server: server, from: archive)
                }
                self.finishActivity(activity, success: true, detail: "World imported — start the server to play")
                self.showToast("World imported")
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't import world", error)
            }
        }
    }

    // MARK: - Server software updates

    /// What an update would change, or nil when already current / unknown.
    struct ServerUpdateInfo: Sendable {
        let title: String
        let detail: String
    }

    /// Checks whether newer server software exists for this hosted server.
    /// Vanilla compares against Mojang's latest release, Paper against the
    /// newest build for its version, Bedrock against the BDS download API.
    /// Fabric servers report no check (loader updates are rare and manual).
    func checkServerUpdate(_ server: HostedServer) async -> ServerUpdateInfo? {
        switch (server.edition, server.serverType) {
        case (.java, .vanilla):
            guard let manifest = try? await versions.manifest(),
                  manifest.latest.release != server.minecraftVersion else { return nil }
            return ServerUpdateInfo(
                title: "Minecraft \(manifest.latest.release)",
                detail: "Latest release — your server runs \(server.minecraftVersion). Updating downloads the new server.jar."
            )
        case (.java, .paper):
            guard let build = try? await PaperService.latestBuild(for: server.minecraftVersion) else { return nil }
            return ServerUpdateInfo(
                title: "Paper build \(build.build)",
                detail: "Newest PaperMC build for \(server.minecraftVersion). Updating replaces server.jar."
            )
        case (.bedrock, _):
            guard server.minecraftVersion != "latest",
                  let url = try? await BedrockServerDownload.latestURL(preview: false),
                  let version = Self.bdsVersion(from: url),
                  version != server.minecraftVersion else { return nil }
            return ServerUpdateInfo(
                title: "BDS \(version)",
                detail: "Newest Bedrock Dedicated Server — your server runs \(server.minecraftVersion). Updating re-downloads the Windows build."
            )
        default:
            return nil
        }
    }

    /// Extracts `1.26.63.1` from a `bedrock-server-<version>.zip` URL.
    private static func bdsVersion(from url: URL) -> String? {
        let name = url.lastPathComponent
        guard name.hasPrefix("bedrock-server-"), name.hasSuffix(".zip") else { return nil }
        return String(name.dropFirst("bedrock-server-".count).dropLast(4))
    }

    /// Applies the pending update: vanilla downloads Mojang's server.jar
    /// for the latest release (and bumps the recorded version), Paper
    /// downloads the newest build, Bedrock re-downloads BDS. Fabric has
    /// no updater — returns false.
    @discardableResult
    func applyServerUpdate(_ server: HostedServer) async -> Bool {
        guard !runningServerIDs.contains(server.id) else {
            showToast("Stop the server before updating")
            return false
        }
        let activity = beginActivity("Updating \(server.name)", detail: "Downloading server software…")
        do {
            switch (server.edition, server.serverType) {
            case (.java, .vanilla):
                let manifest = try await versions.manifest()
                guard let details = try? await versions.details(for: manifest.latest.release),
                      let jar = details.downloads?["server"]?.url,
                      let jarURL = URL(string: jar) else {
                    throw NetworkError.transport("Couldn't resolve the latest server.jar")
                }
                let destination = server.serverJar
                try await Downloader.download(DownloadRequest(
                    url: jarURL, destination: destination, label: "server.jar")) { _ in }
                var updated = server
                updated.minecraftVersion = manifest.latest.release
                try HostedServerStore.save(updated)
                replaceServerInLists(updated)
            case (.java, .paper):
                let build = try await PaperService.latestBuild(for: server.minecraftVersion)
                let destination = server.serverJar
                try await Downloader.download(DownloadRequest(
                    url: build.url, destination: destination, label: "paper-\(build.build).jar")) { _ in }
            case (.bedrock, _):
                let zipURL = try await BedrockServerDownload.latestURL(preview: false)
                try await bedrockServers.updateSoftware(server: server, zipURL: zipURL) { _ in }
                var updated = server
                if let version = Self.bdsVersion(from: zipURL) {
                    updated.minecraftVersion = version
                    try HostedServerStore.save(updated)
                    replaceServerInLists(updated)
                }
            default:
                finishActivity(activity, success: false, detail: "No updater for this server type")
                return false
            }
            finishActivity(activity, success: true, detail: "Update installed — restart to use it")
            showToast("\(server.name) updated")
            return true
        } catch {
            finishActivity(activity, success: false, detail: error.localizedDescription)
            presentError("Couldn't update server", error)
            return false
        }
    }

    private func replaceServerInLists(_ updated: HostedServer) {
        if let index = hostedServers.firstIndex(where: { $0.id == updated.id }) {
            hostedServers[index] = updated
        }
        if dashboardServer?.id == updated.id {
            dashboardServer = updated
        }
    }

    /// Re-copies the single-player save over the hosted world — use after
    /// playing more in single player. Only while the server is stopped.
    /// Java servers only — Bedrock worlds sync through the launcher.
    func syncHostedServerWorld(_ server: HostedServer) {
        guard server.edition == .java else {
            showToast("Bedrock worlds can't be re-synced from a Java instance")
            return
        }
        guard let instance = instance(for: server.instanceID) else {
            showToast("The original instance is gone — the world can't be re-synced")
            return
        }
        guard !runningServerIDs.contains(server.id) else {
            showToast("Stop the server before syncing the world")
            return
        }
        let activity = beginActivity("Syncing \(server.name)", detail: "Copying world from \(instance.name)…")
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.dedicatedServers.syncWorld(server: server, instance: instance)
                self.finishActivity(activity, success: true, detail: "World re-synced")
                self.showToast("World re-synced from \(instance.name)")
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't sync \(server.name)", error)
            }
        }
    }

    /// Deletes the server folder entirely. A running server is stopped first.
    func deleteHostedServer(_ server: HostedServer) {
        Task { [weak self] in
            guard let self else { return }
            if self.runningServerIDs.contains(server.id) {
                if server.edition == .bedrock {
                    await self.bedrockServers.stop(server.id)
                } else {
                    await self.dedicatedServers.stop(server.id)
                }
                self.runningServerIDs.remove(server.id)
                self.readyServerIDs.remove(server.id)
            }
            do {
                try HostedServerStore.delete(server)
                self.hostedServers.removeAll { $0.id == server.id }
                self.serverConsoles[server.id] = nil
                self.serverPlayers[server.id] = nil
                self.serverStartedAt[server.id] = nil
                self.serverLogWriters[server.id]?.close()
                self.serverLogWriters[server.id] = nil
                if self.dashboardServer?.id == server.id {
                    self.dashboardServer = nil
                }
                self.showToast("Deleted \(server.name)")
            } catch {
                self.presentError("Couldn't delete \(server.name)", error)
            }
        }
    }

    /// Quick-joins a running hosted server through the owning instance.
    /// Bedrock has no quick-play — its clients join through the game's
    /// own server list, so only the address is copied for them.
    func joinHostedServer(_ server: HostedServer) {
        guard runningServerIDs.contains(server.id) else {
            showToast("Start the server first")
            return
        }
        guard server.edition == .java else {
            copyServerAddress(server)
            showToast("Bedrock address copied — add it in Minecraft's server list")
            return
        }
        guard let instance = instance(for: server.instanceID)
            ?? instances.first(where: { $0.edition == .java }) else {
            alert = AppAlert(title: "No instance", message: "Create a Java instance before joining a hosted server.")
            return
        }
        selectInstance(instance)
        startGame(instance, quickPlay: Self.serverAddress(server))
    }

    func copyServerAddress(_ server: HostedServer) {
        copyToClipboard(Self.serverAddress(server), label: "Server address copied")
    }

    /// Opens the Server Dashboard page with `server` selected.
    func openServerDashboard(_ server: HostedServer) {
        dashboardServer = server
        go(to: .servers)
    }

    /// Persists the per-server "Start with NeoCraft" flag.
    func setServerAutoStart(_ server: HostedServer, _ enabled: Bool) {
        var updated = server
        updated.autoStart = enabled
        do {
            try HostedServerStore.save(updated)
        } catch {
            presentError("Couldn't save server settings", error)
            return
        }
        if let index = hostedServers.firstIndex(where: { $0.id == server.id }) {
            hostedServers[index] = updated
        }
        if dashboardServer?.id == server.id {
            dashboardServer = updated
        }
        showToast(enabled ? "\(server.name) starts with NeoCraft" : "\(server.name) won't auto-start")
    }

    /// Persists launcher-side metadata (group label, accent colour,
    /// creation preset) without touching the server folder.
    func updateServerMeta(_ server: HostedServer, group: String? = nil, colorHex: String? = nil, preset: String? = nil) {
        var updated = server
        if let group { updated.group = group.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let colorHex { updated.colorHex = colorHex }
        if let preset { updated.preset = preset }
        do {
            try HostedServerStore.save(updated)
        } catch {
            presentError("Couldn't save server settings", error)
            return
        }
        if let index = hostedServers.firstIndex(where: { $0.id == server.id }) {
            hostedServers[index] = updated
        }
        if dashboardServer?.id == server.id {
            dashboardServer = updated
        }
    }

    /// Writes a preset's `server.properties` keys over the current file —
    /// the server must be stopped so it doesn't rewrite them on shutdown.
    func applyServerPreset(_ server: HostedServer, _ preset: ServerPreset) {
        guard preset != .custom else { return }
        guard !runningServerIDs.contains(server.id) else {
            showToast("Stop the server before applying a preset")
            return
        }
        let values = server.edition == .bedrock ? preset.bedrockProperties : preset.properties
        guard !values.isEmpty else { return }
        updateServerMeta(server, preset: preset.rawValue)
        updateServerProperties(server, values: values)
    }

    // MARK: - Dashboard file browser & world backups

    /// Immediate children of `directory` inside the server folder.
    func serverFiles(for server: HostedServer, in directory: URL? = nil) async -> [ServerFileEntry] {
        let target = directory ?? server.directory
        if server.edition == .bedrock {
            return (try? await bedrockServers.files(in: target, for: server)) ?? []
        }
        return (try? await dedicatedServers.files(in: target, for: server)) ?? []
    }

    /// Text preview of a file inside the server folder (nil = binary/too big).
    func serverFileText(_ url: URL, for server: HostedServer) async -> String? {
        if server.edition == .bedrock {
            return await bedrockServers.readTextFile(url, for: server)
        }
        return await dedicatedServers.readTextFile(url, for: server)
    }

    func deleteServerFile(_ url: URL, for server: HostedServer) {
        Task { [weak self] in
            guard let self else { return }
            do {
                if server.edition == .bedrock {
                    try await self.bedrockServers.deleteFile(url, for: server)
                } else {
                    try await self.dedicatedServers.deleteFile(url, for: server)
                }
                self.showToast("Deleted \(url.lastPathComponent)")
            } catch {
                self.presentError("Couldn't delete \(url.lastPathComponent)", error)
            }
        }
    }

    /// World snapshots inside `server.backupsDirectory`, newest first.
    func serverBackups(for server: HostedServer) async -> [URL] {
        if server.edition == .bedrock {
            return await bedrockServers.backups(for: server)
        }
        return await dedicatedServers.backups(for: server)
    }

    /// Copies the hosted world into `backups/` — server must be stopped.
    func backupServerWorld(_ server: HostedServer) {
        let activity = beginActivity("Backing up \(server.name)", detail: "Copying world…")
        Task { [weak self] in
            guard let self else { return }
            do {
                if server.edition == .bedrock {
                    _ = try await self.bedrockServers.backupWorld(server: server)
                } else {
                    _ = try await self.dedicatedServers.backupWorld(server: server)
                }
                self.finishActivity(activity, success: true, detail: "Backup created")
                self.showToast("World backup created")
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't back up \(server.name)", error)
            }
        }
    }

    /// Replaces the hosted world with a backup — server must be stopped.
    func restoreServerBackup(_ server: HostedServer, backup: URL) {
        let activity = beginActivity("Restoring \(server.name)", detail: "Copying backup…")
        Task { [weak self] in
            guard let self else { return }
            do {
                if server.edition == .bedrock {
                    try await self.bedrockServers.restoreBackup(server: server, backup: backup)
                } else {
                    try await self.dedicatedServers.restoreBackup(server: server, backup: backup)
                }
                self.finishActivity(activity, success: true, detail: "World restored")
                self.showToast("World restored from backup")
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't restore backup", error)
            }
        }
    }

    func deleteServerBackup(_ server: HostedServer, backup: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                if server.edition == .bedrock {
                    try await self.bedrockServers.deleteBackup(backup, for: server)
                } else {
                    try await self.dedicatedServers.deleteBackup(backup, for: server)
                }
                self.showToast("Backup deleted")
            } catch {
                self.presentError("Couldn't delete backup", error)
            }
        }
    }

    // MARK: - Server plugins & mods

    /// Installed plugin/mod jars of a Java server (`plugins/` for Paper,
    /// `mods/` for Fabric), for the dashboard's extension list.
    func serverExtensions(for server: HostedServer) async -> [ServerFileEntry] {
        guard server.edition == .java else { return [] }
        return await dedicatedServers.extensions(for: server)
    }

    /// Installs a plugin/mod jar downloaded from a URL (Modrinth file or a
    /// direct link the user pasted).
    func installServerExtension(from url: URL, filename: String?, for server: HostedServer) {
        guard server.edition == .java else { return }
        guard runningServerIDs.contains(server.id) == false else {
            showToast("Stop the server before changing its plugins")
            return
        }
        let activity = beginActivity("Installing extension", detail: filename ?? url.lastPathComponent)
        Task { [weak self] in
            guard let self else { return }
            do {
                if url.isFileURL {
                    _ = try await self.dedicatedServers.installExtension(
                        from: url, filename: filename, for: server
                    )
                } else {
                    _ = try await self.dedicatedServers.installExtension(
                        from: url, filename: filename, for: server
                    ) { fraction in
                        Task { @MainActor in
                            self.updateActivity(activity, fraction: fraction * 0.9, detail: "Downloading…")
                        }
                    }
                }
                self.finishActivity(activity, success: true, detail: "Installed — restart the server to load it")
                self.showToast("Installed \(filename ?? url.lastPathComponent)")
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't install extension", error)
            }
        }
    }

    /// Installs an extension from a local file — jar for Paper/Fabric,
    /// zip/mcpack/jar resource pack for vanilla.
    func installServerExtension(fromFile file: URL, for server: HostedServer) {
        let ext = "." + file.pathExtension.lowercased()
        guard server.serverType.extensionSuffixes.contains(ext) else {
            let expected = server.serverType.extensionSuffixes.joined(separator: ", ")
            showToast("A \(server.serverType.title) server only takes \(expected) files")
            return
        }
        installServerExtension(from: file, filename: file.lastPathComponent, for: server)
    }

    /// Searches Modrinth for plugins (Paper/Spigot/Bukkit) or mods (Fabric)
    /// matching the server's Minecraft version.
    func searchServerExtensions(
        query: String,
        for server: HostedServer,
        offset: Int = 0
    ) async throws -> ModrinthSearchResponse {
        let (type, loader): (ModrinthProjectType, String) =
            switch server.serverType {
            case .paper: (.plugin, "paper")
            case .fabric: (.mod, "fabric")
            case .vanilla: (.resourcepack, "")
            }
        return try await modrinth.search(
            query: query,
            type: type,
            gameVersion: server.minecraftVersion,
            loader: loader,
            sort: .relevance,
            offset: offset
        )
    }

    /// Downloads the primary file of a Modrinth version into the server's
    /// extension folder.
    func installServerExtension(version: ModrinthVersion, for server: HostedServer) {
        guard let file = version.primaryFile, let url = URL(string: file.url) else {
            showToast("That version has no downloadable file")
            return
        }
        installServerExtension(from: url, filename: file.filename, for: server)
    }

    func setServerExtensionEnabled(_ entry: ServerFileEntry, enabled: Bool, for server: HostedServer) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.dedicatedServers.setExtensionEnabled(entry, enabled: enabled, for: server)
            } catch {
                self.presentError("Couldn't update extension", error)
            }
        }
    }

    func deleteServerExtension(_ entry: ServerFileEntry, for server: HostedServer) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.dedicatedServers.deleteExtension(entry, for: server)
                self.showToast("Deleted \(entry.name)")
            } catch {
                self.presentError("Couldn't delete extension", error)
            }
        }
    }

    private func handleServerExit(id: UUID, status: Int32) {
        runningServerIDs.remove(id)
        readyServerIDs.remove(id)
        serverStartedAt[id] = nil
        serverPlayers[id] = []
        serverLogWriters[id]?.write("\n[NeoCraft] Server exited with status \(status).\n")
        serverLogWriters[id]?.close()
        serverLogWriters[id] = nil
        guard let server = hostedServers.first(where: { $0.id == id }) else { return }
        appendConsole(
            status == 0
                ? "Server \(server.name) stopped."
                : "Server \(server.name) exited with status \(status).",
            level: status == 0 ? .info : .error
        )
    }

    // MARK: Server console helpers

    /// Appends one logical line to a hosted server's dashboard console and
    /// mirrors it into the shared game console.
    private func appendServerLine(_ id: UUID, _ line: String, level: ConsoleLevel) {
        appendConsole("[\(hostedServers.first(where: { $0.id == id })?.name ?? "server")] \(line)", level: level)
        var entries = serverConsoles[id] ?? []
        entries.append(ConsoleEntry(line, level: level))
        if entries.count > 1_500 {
            entries.removeFirst(entries.count - 1_500)
        }
        serverConsoles[id] = entries
    }

    /// Splits raw process output into lines for the dashboard console,
    /// tracks joins/leaves for the player list and mirrors to the writer.
    private func appendServerOutput(_ id: UUID, text: String, level: ConsoleLevel) {
        appendGameOutput(text, defaultLevel: level)
        var entries = serverConsoles[id] ?? []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            parseServerPlayerLine(line, serverID: id)
            entries.append(ConsoleEntry(line, level: level))
        }
        if entries.count > 1_500 {
            entries.removeFirst(entries.count - 1_500)
        }
        serverConsoles[id] = entries
    }

    /// Vanilla servers log `<name> joined the game` / `left the game` on the
    /// Server thread — the dashboard turns those into a live player list.
    private func parseServerPlayerLine(_ line: String, serverID: UUID) {
        if let range = line.range(of: " joined the game") {
            if let name = serverPlayerName(from: String(line[..<range.lowerBound])) {
                addServerPlayer(name, serverID: serverID)
            }
        } else if let range = line.range(of: " left the game") {
            if let name = serverPlayerName(from: String(line[..<range.lowerBound])) {
                removeServerPlayer(name, serverID: serverID)
            }
        }
    }

    /// Extracts the player name from a log prefix like
    /// `[13:37:00] [Server thread/INFO]: Notch`.
    private func serverPlayerName(from prefix: String) -> String? {
        var name = prefix
        if let index = name.lastIndex(of: "]") {
            name = String(name[name.index(after: index)...])
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix(":") {
            name = String(name.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? nil : name
    }

    private func addServerPlayer(_ name: String, serverID: UUID) {
        var players = serverPlayers[serverID] ?? []
        guard !players.contains(name) else { return }
        players.append(name)
        serverPlayers[serverID] = players
    }

    private func removeServerPlayer(_ name: String, serverID: UUID) {
        guard var players = serverPlayers[serverID] else { return }
        players.removeAll { $0 == name }
        serverPlayers[serverID] = players
    }

    // MARK: - Smart upgrade

    /// Computes which installed mods can follow `instance` to `targetVersion`.
    func checkUpgradeCompatibility(instance: GameInstance, targetVersion: String) {
        guard upgradingInstanceID == nil else { return }
        upgradingInstanceID = instance.id
        upgradeResults[instance.id] = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.upgradingInstanceID = nil }
            let results = await self.modInstaller.compatibility(
                for: instance,
                targetVersion: targetVersion
            )
            self.upgradeResults[instance.id] = results
        }
    }

    /// Clones the instance at `targetVersion`; compatible mods are re-installed
    /// automatically while incompatible ones are left out and reported.
    func cloneAndUpgrade(instance: GameInstance, targetVersion: String) {
        guard upgradingInstanceID == nil else { return }
        upgradingInstanceID = instance.id
        let activity = beginActivity(
            "Upgrading \(instance.name)",
            detail: "Checking mod compatibility for \(targetVersion)…"
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.upgradingInstanceID = nil }
            do {
                let compatibility = await self.modInstaller.compatibility(
                    for: instance,
                    targetVersion: targetVersion
                )
                // Clone the instance at the target version (fresh game dir,
                // loader version resolved on next prepare).
                var clone = instance
                clone.id = UUID()
                clone.name = "\(instance.name) \(targetVersion)"
                clone.minecraftVersion = targetVersion
                clone.fabricLoaderVersion = nil
                clone.created = Date()
                clone.lastPlayed = nil
                clone.totalPlayTime = 0
                self.instances.append(clone)
                self.selectedInstanceID = clone.id
                let cloneInstance = clone
                try FileManager.default.createDirectory(
                    at: cloneInstance.gameDirectory,
                    withIntermediateDirectories: true
                )

                // Re-install every mod that has a compatible version.
                var reinstalled = 0
                var skipped = 0
                for item in compatibility where item.compatible {
                    do {
                        let type = item.type
                        _ = try await self.modInstaller.install(
                            projectID: item.projectID,
                            versionID: nil,
                            type: type,
                            into: cloneInstance
                        ) { _ in }
                        reinstalled += 1
                    } catch {
                        skipped += 1
                    }
                    self.updateActivity(
                        activity,
                        fraction: nil,
                        detail: "Upgraded mods: \(reinstalled) ok, \(skipped) skipped"
                    )
                }

                self.refreshStats(for: cloneInstance)
                self.refreshInstalledProjects()
                self.upgradeResults[instance.id] = compatibility
                self.selectedInstanceID = clone.id
                self.section = .instances
                self.finishActivity(
                    activity,
                    success: true,
                    detail: "Clone ready — \(reinstalled) mods compatible, \(compatibility.count - reinstalled) left behind"
                )
                self.showToast("Upgraded clone created")
                SoundManager.shared.play(.chime)
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Upgrade failed", error)
            }
        }
    }

    // MARK: - Screenshots aggregation

    /// Every screenshot across all instances, newest first.
    func allScreenshots() -> [(instance: GameInstance, url: URL)] {
        instances.flatMap { instance in
            InstanceScanner.screenshotURLs(in: instance.gameDirectory).map {
                (instance: instance, url: $0)
            }
        }
        .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    func screenshotInstanceStats() -> [(instance: GameInstance, urls: [URL])] {
        instances.compactMap { instance in
            let urls = InstanceScanner.screenshotURLs(in: instance.gameDirectory)
            return urls.isEmpty ? nil : (instance, urls)
        }
    }

    // MARK: - Modrinth

    func scheduleModSearch() {
        modSearchTask?.cancel()
        isSearchingMods = true
        modSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(320))
                try Task.checkCancellation()
                try await self.performModSearch(reset: true)
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    self.modSearchError = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                self.isSearchingMods = false
            }
        }
    }

    func searchMods(reset: Bool = true) {
        modSearchTask?.cancel()
        if reset {
            modSearchError = nil
        }
        isSearchingMods = true
        modSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.performModSearch(reset: reset)
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled {
                    self.modSearchError = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                self.isSearchingMods = false
            }
        }
    }

    func loadMoreMods() {
        guard !isSearchingMods, modResults.count < modTotal else { return }
        searchMods(reset: false)
    }

    private func performModSearch(reset: Bool) async throws {
        try Task.checkCancellation()
        let offset = reset ? 0 : modResults.count
        let response = try await modrinth.search(
            query: modQuery,
            type: modType,
            gameVersion: modSearchGameVersion,
            loader: modSearchLoader,
            sort: modSort,
            offset: offset,
            limit: 20
        )
        try Task.checkCancellation()
        if reset {
            modResults = response.hits
        } else {
            let existing = Set(modResults.map(\.projectID))
            modResults.append(contentsOf: response.hits.filter { !existing.contains($0.projectID) })
        }
        modTotal = response.totalHits
        modSearchError = nil
    }

    func openProject(_ hit: ModrinthSearchHit) {
        openProject(id: hit.projectID, title: hit.title, iconURL: hit.iconURL)
    }

    func openProject(id: String, title: String, iconURL: String?) {
        projectSelection = ProjectSelection(projectID: id, title: title, iconURL: iconURL)
        projectDetail = nil
        projectVersions = []
        projectDetailError = nil
        isLoadingProject = true
        let selection = projectSelection
        Task { [weak self] in
            guard let self else { return }
            do {
                let project = try await self.modrinth.project(idOrSlug: id)
                let instance = self.selectedInstance
                let loader = project.type == .mod
                    ? (instance?.loader == .fabric ? "fabric" : "")
                    : ""
                let versions = try await self.modrinth.versions(
                    projectID: project.id,
                    gameVersion: instance?.minecraftVersion ?? "",
                    loader: loader.isEmpty ? nil : loader
                )
                guard self.projectSelection?.id == selection?.id else { return }
                self.projectDetail = project
                self.projectVersions = versions
                self.isLoadingProject = false
            } catch {
                guard self.projectSelection?.id == selection?.id else { return }
                self.projectDetailError = error.localizedDescription
                self.isLoadingProject = false
            }
        }
    }

    func closeProject() {
        projectSelection = nil
        projectDetail = nil
        projectVersions = []
        projectDetailError = nil
        isLoadingProject = false
    }

    func installProject(versionID: String? = nil) {
        guard let project = projectDetail else { return }
        install(
            projectID: project.id,
            type: project.type,
            title: project.title,
            versionID: versionID
        )
    }

    func install(_ hit: ModrinthSearchHit) {
        install(
            projectID: hit.projectID,
            type: hit.type,
            title: hit.title,
            versionID: nil
        )
    }

    private func install(
        projectID: String,
        type: ModrinthProjectType,
        title: String,
        versionID: String?
    ) {
        guard let instance = selectedInstance else {
            alert = AppAlert(
                title: "Select an instance",
                message: "Choose an instance before installing \(title)."
            )
            return
        }
        if instance.edition == .bedrock {
            alert = AppAlert(
                title: "Bedrock Edition",
                message: "\(title) can't be installed — Bedrock doesn't use Java mods."
            )
            return
        }
        if type == .mod && instance.loader != .fabric {
            alert = AppAlert(
                title: "Fabric required",
                message: "\(title) is a Fabric mod. Edit this instance and switch the loader to Fabric, then try again."
            )
            return
        }
        guard installingProjectID == nil else {
            showToast("Another installation is already running")
            return
        }

        installingProjectID = projectID
        installFraction = 0
        installDetail = "Resolving \(title)…"
        Task { [weak self] in
            guard let self else { return }
            await self.performInstall(
                projectID: projectID,
                type: type,
                title: title,
                versionID: versionID,
                into: instance
            )
            self.checkForUpdates()
        }
    }

    /// Runs one install end-to-end and keeps the shared install UI state in
    /// sync. Used by single installs and by "Update All".
    private func performInstall(
        projectID: String,
        type: ModrinthProjectType,
        title: String,
        versionID: String?,
        into instance: GameInstance
    ) async {
        do {
            _ = try await modInstaller.install(
                projectID: projectID,
                versionID: versionID,
                type: type,
                into: instance
            ) { update in
                Task { @MainActor in
                    self.installFraction = update.fraction
                    self.installDetail = update.detail
                }
            }
            installingProjectID = nil
            installFraction = nil
            installDetail = ""
            installedProjectIDs = await modInstaller.installedProjectIDs(for: instance)
            refreshStats(for: instance)
            refreshStorageUsage()
            showToast("Installed \(title)")
            SoundManager.shared.play(.chime)
        } catch {
            installingProjectID = nil
            installFraction = nil
            installDetail = ""
            presentError("Couldn't install \(title)", error)
        }
    }

    // MARK: - Mod updates

    func checkForUpdates() {
        guard let instance = selectedInstance, instance.edition == .java, !isCheckingUpdates else { return }
        isCheckingUpdates = true
        Task { [weak self] in
            guard let self else { return }
            let updates = await self.modInstaller.checkForUpdates(in: instance)
            if self.selectedInstanceID == instance.id {
                self.modUpdates = updates
            }
            self.isCheckingUpdates = false
        }
    }

    func updateProject(_ update: ModUpdate) {
        install(
            projectID: update.projectID,
            type: update.type,
            title: update.title,
            versionID: update.latest.id
        )
    }

    /// Installs every pending update sequentially. `performInstall` serializes
    /// through `installingProjectID`, so updates must run one at a time.
    func updateAllMods() {
        guard let instance = selectedInstance,
              instance.edition == .java,
              !modUpdates.isEmpty,
              installingProjectID == nil else { return }
        let updates = modUpdates
        Task { [weak self] in
            guard let self else { return }
            for update in updates {
                guard self.selectedInstanceID == instance.id else { break }
                await self.performInstall(
                    projectID: update.projectID,
                    type: update.type,
                    title: update.title,
                    versionID: update.latest.id,
                    into: instance
                )
            }
            self.checkForUpdates()
        }
    }

    func removeInstalledProject(_ projectID: String, title: String) {
        guard let instance = selectedInstance else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.modInstaller.remove(projectID: projectID, from: instance)
                self.installedProjectIDs.remove(projectID)
                self.modUpdates.removeAll { $0.projectID == projectID }
                self.refreshStats(for: instance)
                self.showToast("Removed \(title)")
            } catch {
                self.presentError("Couldn't remove \(title)", error)
            }
        }
    }

    // MARK: - Flight Check (pre-launch mod scanner)

    func flightCheckResult(for instance: GameInstance) -> FlightCheckResult? {
        flightCheckResults[instance.id]
    }

    /// Runs the scanner if no cached result exists. Cheap enough to call on
    /// every Play-screen appearance — results are cached per instance.
    func refreshFlightCheck(for instance: GameInstance, force: Bool = false) {
        if !force, flightCheckResults[instance.id] != nil { return }
        runFlightCheck(for: instance)
    }

    func runFlightCheck(for instance: GameInstance) {
        guard !flightCheckRunning.contains(instance.id) else { return }
        flightCheckRunning.insert(instance.id)
        Task { [weak self] in
            guard let self else { return }
            let result = await ModScanner.shared.scan(instance: instance)
            self.flightCheckResults[instance.id] = result
            self.flightCheckRunning.remove(instance.id)
        }
    }

    /// Opens the diagnostic sheet for an instance.
    func openFlightCheck(for instance: GameInstance) {
        flightCheckInstance = instance
        if flightCheckResults[instance.id] == nil {
            runFlightCheck(for: instance)
        }
    }

    /// Re-scans after the user applied a fix.
    func rescanFlightCheck(for instance: GameInstance) {
        runFlightCheck(for: instance)
    }

    /// Applies a one-click fix from the diagnostic sheet.
    func applyFlightFix(_ issue: FlightIssue, for instance: GameInstance) {
        switch issue.fix {
        case .disableMod(let fileName):
            disableModFile(fileName, in: instance)
        case .installDependency(let slug):
            installMissingDependency(slug, for: instance)
        case .none:
            break
        }
    }

    /// Moves a JAR out of `mods/` into `disabled-mods/` so Fabric ignores it.
    func disableModFile(_ fileName: String, in instance: GameInstance) {
        let modsDir = instance.gameDirectory.appendingPathComponent("mods", isDirectory: true)
        let disabledDir = instance.gameDirectory.appendingPathComponent("disabled-mods", isDirectory: true)
        let source = modsDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: source.path) else {
            showToast("\(fileName) is no longer in mods/")
            rescanFlightCheck(for: instance)
            return
        }
        do {
            try FileManager.default.createDirectory(at: disabledDir, withIntermediateDirectories: true)
            let destination = disabledDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            showToast("Disabled \(fileName)")
            rescanFlightCheck(for: instance)
        } catch {
            presentError("Couldn't disable mod", error)
        }
    }

    /// Looks up a missing dependency on Modrinth and installs the newest
    /// version compatible with the instance.
    func installMissingDependency(_ slug: String, for instance: GameInstance) {
        guard instance.loader == .fabric else {
            showToast("This instance isn't Fabric — dependency install skipped")
            return
        }
        guard !flightFixInstalling.contains(instance.id), installingProjectID == nil else {
            showToast("Another installation is already running")
            return
        }
        flightFixInstalling.insert(instance.id)
        let activity = beginActivity("Installing dependency", detail: "Resolving \(slug) on Modrinth…")
        Task { [weak self] in
            guard let self else { return }
            defer { self.flightFixInstalling.remove(instance.id) }
            do {
                let project = try await self.modrinth.project(idOrSlug: slug)
                let versions = try await self.modrinth.versions(
                    projectID: project.id,
                    gameVersion: instance.minecraftVersion,
                    loader: "fabric"
                )
                guard let version = versions.first else {
                    throw AppError.install("No \(instance.minecraftVersion)-compatible version of \(project.title) on Modrinth")
                }
                _ = try await self.modInstaller.install(
                    projectID: project.id,
                    versionID: version.id,
                    type: project.type,
                    into: instance
                ) { _ in }
                self.finishActivity(activity, success: true, detail: "Installed \(project.title)")
                self.showToast("Installed \(project.title)")
                self.rescanFlightCheck(for: instance)
                self.refreshStats(for: instance)
                self.refreshInstalledProjects()
            } catch {
                self.finishActivity(activity, success: false, detail: error.localizedDescription)
                self.presentError("Couldn't install \(slug)", error)
            }
        }
    }

    // MARK: - Neo Studio HUD

    /// Ensures the lightweight HUD mod stack is present, then writes the
    /// editor layout into the instance's config directory.
    /// Writes the Studio "In-Game UI" theme to the selected Fabric
    /// instance's `config/neocraft_ui.json`. The `neocraft-ui` mod
    /// hot-reloads the file, so changes apply without a restart.
    func applyUIThemeToInstance(_ instance: GameInstance? = nil) {
        guard let instance = instance ?? selectedInstance else {
            alert = AppAlert(title: "No instance selected", message: "Choose an instance before applying the UI theme.")
            return
        }
        guard settings.betaFeatures.inGameUI else {
            alert = AppAlert(
                title: "Beta feature",
                message: "The in-game UI theme is a beta feature. Enable it in Settings → Beta Features first."
            )
            return
        }
        guard instance.loader == .fabric else {
            alert = AppAlert(
                title: "Fabric required",
                message: "The UI theme mod is a Fabric mod. Switch this instance to Fabric first."
            )
            return
        }
        do {
            _ = try UIConfigWriter.write(settings.uiTheme, launcher: settings, to: instance)
            installCompanionMods(into: instance)
            showToast("UI theme applied to \(instance.name)")
            SoundManager.shared.play(.chime)
            appendConsole("NeoCraft UI theme written for \(instance.name)", level: .info)
        } catch {
            presentError("Couldn't apply UI theme", error)
        }
    }

    func applyHUDToInstance(_ instance: GameInstance? = nil) {
        guard settings.betaFeatures.inGameHUD else {
            alert = AppAlert(
                title: "Beta feature",
                message: "The In-Game HUD is a beta feature. Enable it in Settings → Beta Features first."
            )
            return
        }
        guard let instance = instance ?? selectedInstance else {
            alert = AppAlert(title: "No instance selected", message: "Choose an instance before applying the HUD layout.")
            return
        }
        guard instance.loader == .fabric else {
            alert = AppAlert(
                title: "Fabric required",
                message: "The HUD sync installs Fabric mods. Switch this instance to Fabric first."
            )
            return
        }
        guard !isApplyingHUD else { return }
        isApplyingHUD = true
        hudApplyDetail = "Checking HUD mods…"
        Task { [weak self] in
            guard let self else { return }
            defer { self.isApplyingHUD = false }
            do {
                // 1. Ensure the lightweight HUD stack via Modrinth.
                var installed: [String] = []
                for slug in HUDConfigWriter.recommendedMods {
                    self.hudApplyDetail = "Installing \(slug)…"
                    do {
                        let project = try await self.modrinth.project(idOrSlug: slug)
                        let versions = try await self.modrinth.versions(
                            projectID: project.id,
                            gameVersion: instance.minecraftVersion,
                            loader: "fabric"
                        )
                        guard let version = versions.first else { continue }
                        _ = try await self.modInstaller.install(
                            projectID: project.id,
                            versionID: version.id,
                            type: project.type,
                            into: instance
                        ) { _ in }
                        installed.append(project.title)
                    } catch {
                        appendConsole("HUD mod \(slug) skipped: \(error.localizedDescription)", level: .warning)
                    }
                }

                // 2. Write exact widget coordinates into config/ — both
                //    the legacy v2 document and the v3 profile document
                //    the Fabric companion mod consumes.
                self.hudApplyDetail = "Writing HUD config…"
                var files = try HUDConfigWriter.write(settings.hudLayout, to: instance)
                files.append(contentsOf: try HUDConfigWriter.writeDocument(
                    HUDConfigWriter.document(from: settings.hudLayout),
                    to: instance
                ))

                // 3. Drop the bundled companion mod jars in.
                self.installCompanionMods(into: instance)

                self.refreshStats(for: instance)
                self.refreshInstalledProjects()
                self.runFlightCheck(for: instance)
                self.showToast("HUD applied to \(instance.name) — \(installed.count) mods ready")
                SoundManager.shared.play(.chime)
                appendConsole(
                    "Neo Studio HUD applied: \(files.count) config file(s), mods: \(installed.joined(separator: ", "))",
                    level: .info
                )
            } catch {
                self.presentError("Couldn't apply HUD", error)
            }
        }
    }

    /// Companion mod jars shipped with every NeoCraft Fabric instance.
    /// All in-game features — UI theme/menu, HUD editor and host panel —
    /// are beta and install together only while the flag is on.
    private static let betaCompanionModJars = [
        "neocraft-ui", "neocraft-hud", "neocraft-host",
    ]
    private static let companionModJars = betaCompanionModJars

    /// Copies the bundled companion mod jars into the instance's mods
    /// folder — only while the beta feature is enabled.
    /// Idempotent — safe to call on every launch and every save.
    private func installCompanionMods(into instance: GameInstance) {
        let modsDir = instance.gameDirectory.appendingPathComponent("mods", isDirectory: true)
        if settings.betaFeatures.inGameHUD {
            for jar in Self.betaCompanionModJars {
                installCompanionJar(jar, into: instance, modsDir: modsDir)
            }
        }
    }

    private func installCompanionJar(_ jar: String, into instance: GameInstance, modsDir: URL) {
        guard let bundled = Bundle.main.url(forResource: jar, withExtension: "jar", subdirectory: "Mods")
                ?? Bundle.main.url(forResource: jar, withExtension: "jar")
                ?? Bundle.main.resourceURL?.appendingPathComponent("Mods/\(jar).jar") else { return }
        let dest = modsDir.appendingPathComponent("\(jar).jar")
        do {
            try FileManager.default.createDirectory(at: modsDir, withIntermediateDirectories: true)
            // Skip the copy when the bundled jar is already in place —
            // comparing sizes keeps every-launch checks cheap.
            if let bundledSize = try? bundled.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               let destSize = try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               bundledSize == destSize {
                return
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: bundled, to: dest)
            appendConsole("Installed companion mod \(jar).jar into \(instance.name)", level: .info)
        } catch {
            appendConsole("Couldn't install \(jar).jar: \(error.localizedDescription)", level: .warning)
        }
    }

    // MARK: - HUD config watcher (two-way sync)

    /// Watches `<instance>/minecraft/config/` while the game runs. When the
    /// companion mod rewrites `neocraft_hud.json`, the parsed layout is
    /// compared against `settings.hudLayout` and adopted when it differs —
    /// so Studio reflects in-game edits. Launch-success calls this; every
    /// game exit calls `stopHUDConfigWatcher`.
    func startHUDConfigWatcher(for instance: GameInstance) {
        stopHUDConfigWatcher()
        let configDir = instance.gameDirectory.appendingPathComponent("config", isDirectory: true)
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let fd = open(configDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.hudConfigDirectoryChanged()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        hudWatcherSource = source
        hudWatchedConfigURL = configDir.appendingPathComponent("neocraft_hud.json")
        hudLastHandledModification = Self.fileModificationDate(hudWatchedConfigURL)
    }

    func stopHUDConfigWatcher() {
        hudWatcherSource?.cancel()
        hudWatcherSource = nil
        hudWatchedConfigURL = nil
        hudLastHandledModification = nil
    }

    private func hudConfigDirectoryChanged() {
        guard let url = hudWatchedConfigURL else { return }
        guard let modified = Self.fileModificationDate(url) else { return }
        // Only react to a *newer* write than the one we last handled —
        // this is what prevents reload/write feedback loops.
        if let last = hudLastHandledModification, modified <= last { return }
        hudLastHandledModification = modified
        guard let layout = HUDConfigWriter.loadLayout(from: url),
              layout != settings.hudLayout else { return }
        settings.hudLayout = layout
        appendConsole("HUD layout synced from in-game edits", level: .info)
    }

    private static func fileModificationDate(_ url: URL?) -> Date? {
        guard let url else { return nil }
        return try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    /// Everything a Fabric instance needs at runtime beyond the game
    /// files themselves: a compatible `fabric-api` from Modrinth (skipped
    /// when current) and — only while the beta feature is on — the
    /// `neocraft-ui`/`neocraft-hud`/`neocraft-host` jars plus the synced
    /// `neocraft_ui.json`/`neocraft_hud.json` configs. Called on instance
    /// save and before every launch — all steps are idempotent and cheap
    /// when everything is already installed.
    private func ensureFabricRuntimeMods(for instance: GameInstance) async {
        guard instance.loader == .fabric else { return }
        installCompanionMods(into: instance)
        if settings.betaFeatures.inGameUI {
            // Keep the NeoCraft UI theme in sync with Studio on every
            // launch — the mod hot-reloads the file anyway.
            UIConfigWriter.writeQuietly(settings.uiTheme, launcher: settings, to: instance)
        }
        await modInstaller.ensureFabricAPI(for: instance)
    }

    /// Removes the beta companion mods (`neocraft-ui`, `neocraft-hud`,
    /// `neocraft-host`) and the NeoCraft-written config files from every
    /// instance. Called when the beta toggle is switched off so no stale
    /// jar keeps rendering an old layout in-game. `config/minihud.json`
    /// is left alone — it may belong to a user-installed MiniHUD.
    /// `config/neocraft_ui.json` is removed too — the in-game UI is part
    /// of the same beta feature.
    func disableInGameHUD() {
        stopHUDConfigWatcher()
        var removed = 0
        for instance in instances {
            removed += removeCompanionHUDMod(from: instance) ? 1 : 0
            let configRoot = instance.gameDirectory.appendingPathComponent("config", isDirectory: true)
            for name in ["neocraft_hud.json", "neocraft_ui.json"] {
                let url = configRoot.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            let legacy = configRoot.appendingPathComponent("neocraft/neo-hud.json")
            if FileManager.default.fileExists(atPath: legacy.path) {
                try? FileManager.default.removeItem(at: legacy)
            }
        }
        appendConsole("In-Game HUD beta disabled — companion mods removed from \(removed) instance(s)", level: .info)
        showToast("In-Game HUD disabled")
    }

    /// Deletes the beta companion mod jars (`neocraft-ui`,
    /// `neocraft-hud`, `neocraft-host`) from an instance.
    /// Returns true when at least one file was actually removed.
    @discardableResult
    private func removeCompanionHUDMod(from instance: GameInstance) -> Bool {
        var removed = false
        for jar in Self.betaCompanionModJars {
            let dest = instance.gameDirectory
                .appendingPathComponent("mods", isDirectory: true)
                .appendingPathComponent("\(jar).jar")
            guard FileManager.default.fileExists(atPath: dest.path) else { continue }
            do {
                try FileManager.default.removeItem(at: dest)
                appendConsole("Removed companion mod \(jar).jar from \(instance.name)", level: .info)
                removed = true
            } catch {
                appendConsole("Couldn't remove \(jar).jar from \(instance.name): \(error.localizedDescription)", level: .warning)
            }
        }
        return removed
    }

    // MARK: - Instance Detail Hub

    func showInstanceDetail(_ instance: GameInstance) {
        detailInstance = instance
    }

    /// Enables/disables a mod JAR in place, then refreshes Flight Check and
    /// instance stats so every surface stays consistent.
    func setModEnabled(_ mod: InstalledMod, enabled: Bool, in instance: GameInstance) {
        do {
            _ = try InstanceContent.setMod(mod, enabled: enabled)
            showToast("\(enabled ? "Enabled" : "Disabled") \(mod.displayName)")
            rescanFlightCheck(for: instance)
            refreshStats(for: instance)
        } catch {
            presentError("Couldn't update mod", error)
        }
    }

    func deleteInstalledMod(_ mod: InstalledMod, in instance: GameInstance) {
        do {
            try InstanceContent.deleteMod(mod)
            showToast("Deleted \(mod.displayName)")
            rescanFlightCheck(for: instance)
            refreshStats(for: instance)
        } catch {
            presentError("Couldn't delete mod", error)
        }
    }

    /// Updates one installed project to its newest version compatible with
    /// the instance — used by the per-mod "Update" button in the hub.
    func updateModInInstance(projectID: String, title: String, into instance: GameInstance) {
        guard installingProjectID == nil else {
            showToast("Another installation is already running")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let records = await self.modInstaller.installedRecords(for: instance)
            guard let record = records[projectID] else { return }
            let type = ModrinthProjectType(folderName: record.folder) ?? .mod
            await self.performInstall(
                projectID: projectID,
                type: type,
                title: title,
                versionID: nil,
                into: instance
            )
            self.rescanFlightCheck(for: instance)
        }
    }

    /// Launches straight into a single-player world via `--quickPlaySingleplayer`.
    func playWorld(_ world: WorldInfo, in instance: GameInstance) {
        startGame(instance, quickPlayWorld: world.name)
    }

    // MARK: - Screenshots

    func showScreenshots(for instance: GameInstance) {
        screenshotInstance = instance
    }

    // MARK: - Patch notes

    func openPatchNote(_ entry: PatchNoteEntry) {
        selectedPatchNote = entry
        detailedPatchNote = nil
        isLoadingPatchNote = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let detail = try await self.versions.patchNoteDetail(for: entry)
                guard self.selectedPatchNote?.id == entry.id else { return }
                self.detailedPatchNote = detail
            } catch {
                // The short text in the list is still useful when the detail
                // endpoint is unavailable.
            }
            self.isLoadingPatchNote = false
        }
    }

    // MARK: - Finder and links

    func openURL(_ string: String) {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func copyToClipboard(_ string: String, label: String = "Copied") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        showToast(label)
    }

    func go(to section: AppSection) {
        // The mod library is hidden for Bedrock instances — reroute instead.
        if section == .mods, selectedInstance?.edition == .bedrock {
            self.section = .play
            SoundManager.shared.play(.click)
            return
        }
        self.section = section
        SoundManager.shared.play(.click)
        if section == .mods && modResults.isEmpty {
            searchMods(reset: true)
        }
        if section == .mods {
            checkForUpdates()
        }
        if section == .settings {
            refreshStorageUsage()
        }
    }
}

enum Formatters {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.isAdaptive = true
        let formatted = formatter.string(fromByteCount: value)
        return formatted.replacingOccurrences(of: "Zero", with: "0")
    }

    static func memory(_ megabytes: Int) -> String {
        megabytes >= 1024 ? String(format: "%.1f GB", Double(megabytes) / 1024) : "\(megabytes) MB"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if totalMinutes > 0 {
            return "\(totalMinutes)m"
        }
        return "\(max(0, Int(interval)))s"
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "Never played" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func downloadCount(_ value: Int) -> String {
        switch value {
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return "\(value)"
        }
    }
}
