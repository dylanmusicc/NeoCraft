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

    var section: AppSection = .play
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
        await loadJavaRuntimes()
        async let catalogLoad: Void = reloadCatalog()
        async let patchNoteLoad: Void = loadPatchNotes()
        _ = await (catalogLoad, patchNoteLoad)
        ensureDefaultInstance()
        selectionDidChange()
        StudioTheme.refreshBiomeAccent()
        isBootstrapping = false
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
        instance: GameInstance,
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> JavaRuntime {
        if let path = instance.javaPath, !path.isEmpty {
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
                    instance: instance
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
            instance: instance
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

                // 3. Drop the bundled neocraft-hud.jar companion mod in.
                self.installCompanionHUDMod(into: instance)

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

    /// Copies the bundled `neocraft-hud.jar` companion mod into the
    /// instance's mods folder so the Studio layout renders in-game.
    /// Idempotent — safe to call on every launch and every save.
    private func installCompanionHUDMod(into instance: GameInstance) {
        guard let bundled = Bundle.main.url(forResource: "neocraft-hud", withExtension: "jar", subdirectory: "Mods")
                ?? Bundle.main.url(forResource: "neocraft-hud", withExtension: "jar")
                ?? Bundle.main.resourceURL?.appendingPathComponent("Mods/neocraft-hud.jar") else { return }
        let modsDir = instance.gameDirectory.appendingPathComponent("mods", isDirectory: true)
        let dest = modsDir.appendingPathComponent("neocraft-hud.jar")
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
            appendConsole("Installed companion HUD mod into \(instance.name)", level: .info)
        } catch {
            appendConsole("Couldn't install neocraft-hud.jar: \(error.localizedDescription)", level: .warning)
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
    /// when current) and — only while the beta feature is on — the bundled
    /// `neocraft-hud.jar` companion mod. Called on instance save and
    /// before every launch — both steps are idempotent and cheap when
    /// everything is already installed.
    private func ensureFabricRuntimeMods(for instance: GameInstance) async {
        guard instance.loader == .fabric else { return }
        if settings.betaFeatures.inGameHUD {
            installCompanionHUDMod(into: instance)
        }
        await modInstaller.ensureFabricAPI(for: instance)
    }

    /// Removes the companion HUD mod and the NeoCraft-written HUD config
    /// files from every instance. Called when the beta toggle is switched
    /// off so no stale jar keeps rendering an old layout in-game.
    /// `config/minihud.json` is left alone — it may belong to a
    /// user-installed MiniHUD.
    func disableInGameHUD() {
        stopHUDConfigWatcher()
        var removed = 0
        for instance in instances {
            removed += removeCompanionHUDMod(from: instance) ? 1 : 0
            let configRoot = instance.gameDirectory.appendingPathComponent("config", isDirectory: true)
            for name in ["neocraft_hud.json"] {
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
        appendConsole("In-Game HUD beta disabled — companion mod removed from \(removed) instance(s)", level: .info)
        showToast("In-Game HUD disabled")
    }

    /// Deletes `mods/neocraft-hud.jar` from an instance. Returns true when
    /// a file was actually removed.
    @discardableResult
    private func removeCompanionHUDMod(from instance: GameInstance) -> Bool {
        let dest = instance.gameDirectory
            .appendingPathComponent("mods", isDirectory: true)
            .appendingPathComponent("neocraft-hud.jar")
        guard FileManager.default.fileExists(atPath: dest.path) else { return false }
        do {
            try FileManager.default.removeItem(at: dest)
            appendConsole("Removed companion HUD mod from \(instance.name)", level: .info)
            return true
        } catch {
            appendConsole("Couldn't remove neocraft-hud.jar from \(instance.name): \(error.localizedDescription)", level: .warning)
            return false
        }
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
