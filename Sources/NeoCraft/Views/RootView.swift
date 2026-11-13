import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    /// Rebuilds the whole split view when Studio theme settings change so
    /// accent colors, OLED mode and grid intensity apply everywhere at once.
    private var themeSignature: String {
        let s = model.settings
        return "\(s.accentHex)|\(s.secondaryGlowHex)|\(s.cardTintHex)|\(s.themeMode.rawValue)|\(s.gridIntensity)|\(s.cornerStyle.rawValue)|\(s.sidebarMaterial)|\(s.curatedTheme)|\(s.wallpaperStyle)|\(s.themeMode == .dynamic ? Int(Date().timeIntervalSince1970 / 3600) : 0)"
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 218, ideal: 238, max: 272)
        } detail: {
            ZStack {
                NeoBackground()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .tint(NeoPalette.accent)
        .id(themeSignature)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: model.section)
        .sheet(item: editingBinding) { draft in
            InstanceEditorView(draft: draft)
                .environment(model)
        }
        .sheet(item: screenshotBinding) { instance in
            ScreenshotGalleryView(instance: instance)
                .environment(model)
        }
        .sheet(item: projectBinding) { selection in
            ProjectDetailView(selection: selection)
                .environment(model)
        }
        .sheet(item: patchNoteBinding) { entry in
            PatchNoteDetailView(entry: entry)
                .environment(model)
        }
        .sheet(isPresented: consoleBinding) {
            ConsoleView()
                .environment(model)
        }
        .sheet(isPresented: authBinding, onDismiss: {
            if model.isSigningIn {
                model.cancelSignIn()
            }
        }) {
            AuthSheetView()
                .environment(model)
        }
        .sheet(item: crashBinding) { diagnosis in
            CrashDoctorView(diagnosis: diagnosis)
                .environment(model)
        }
        .sheet(item: backupBinding) { instance in
            WorldBackupView(instance: instance)
                .environment(model)
        }
        .sheet(item: upgradeBinding) { instance in
            InstanceUpgradeView(instance: instance)
                .environment(model)
        }
        .sheet(item: flightCheckBinding) { instance in
            FlightCheckView(instance: instance)
                .environment(model)
        }
        .sheet(item: detailBinding) { instance in
            InstanceDetailView(instance: instance)
                .environment(model)
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingView()
                .environment(model)
        }
        .sheet(isPresented: offlineAccountBinding) {
            OfflineAccountSheet()
                .environment(model)
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(message: toast)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.toast)
        .alert(
            model.alert?.title ?? "NeoCraft",
            isPresented: alertBinding,
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .play:
            PlayView()
        case .instances:
            InstancesView()
        case .servers:
            ServersView()
        case .dashboard:
            DashboardView()
        case .studio:
            StudioView()
        case .mods:
            ModLibraryView()
        case .screenshots:
            ScreenshotsView()
        case .account:
            AccountView()
        case .settings:
            SettingsView()
        }
    }

    private var editingBinding: Binding<GameInstance?> {
        Binding(
            get: { model.editingInstance },
            set: { model.editingInstance = $0 }
        )
    }

    private var screenshotBinding: Binding<GameInstance?> {
        Binding(
            get: { model.screenshotInstance },
            set: { model.screenshotInstance = $0 }
        )
    }

    private var projectBinding: Binding<ProjectSelection?> {
        Binding(
            get: { model.projectSelection },
            set: { newValue in
                if newValue == nil {
                    model.closeProject()
                } else {
                    model.projectSelection = newValue
                }
            }
        )
    }

    private var patchNoteBinding: Binding<PatchNoteEntry?> {
        Binding(
            get: { model.selectedPatchNote },
            set: { newValue in
                model.selectedPatchNote = newValue
                if newValue == nil {
                    model.detailedPatchNote = nil
                }
            }
        )
    }

    private var consoleBinding: Binding<Bool> {
        Binding(
            get: { model.showConsole },
            set: { model.showConsole = $0 }
        )
    }

    private var authBinding: Binding<Bool> {
        Binding(
            get: { model.showAuthSheet },
            set: { model.showAuthSheet = $0 }
        )
    }

    private var crashBinding: Binding<CrashDiagnosis?> {
        Binding(
            get: { model.crashDiagnosis },
            set: { model.crashDiagnosis = $0 }
        )
    }

    private var backupBinding: Binding<GameInstance?> {
        Binding(
            get: { model.worldBackupInstance },
            set: { model.worldBackupInstance = $0 }
        )
    }

    private var upgradeBinding: Binding<GameInstance?> {
        Binding(
            get: { model.upgradeInstance },
            set: { model.upgradeInstance = $0 }
        )
    }

    private var flightCheckBinding: Binding<GameInstance?> {
        Binding(
            get: { model.flightCheckInstance },
            set: { model.flightCheckInstance = $0 }
        )
    }

    private var offlineAccountBinding: Binding<Bool> {
        Binding(
            get: { model.showOfflineAccountSheet },
            set: { model.showOfflineAccountSheet = $0 }
        )
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !UserDefaults.standard.bool(forKey: "NeoOnboardingComplete") },
            set: { _ in }
        )
    }

    private var detailBinding: Binding<GameInstance?> {
        Binding(
            get: { model.detailInstance },
            set: { model.detailInstance = $0 }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alert != nil },
            set: { newValue in
                if !newValue {
                    model.alert = nil
                }
            }
        )
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    /// Sections in the user's Studio-defined order, minus hidden ones.
    private var visibleSections: [AppSection] {
        let hidden = Set(model.settings.hiddenSections)
        let order = model.settings.sidebarOrder
        var result: [AppSection] = []
        for raw in order {
            if let section = AppSection(rawValue: raw),
               !hidden.contains(raw), !result.contains(section) {
                result.append(section)
            }
        }
        for section in AppSection.allCases
        where !hidden.contains(section.rawValue) && !result.contains(section) {
            result.append(section)
        }
        // Java mod ecosystem doesn't exist for Bedrock — hide the library
        // entirely while a Bedrock instance is selected.
        if model.selectedInstance?.edition == .bedrock {
            result.removeAll { $0 == .mods }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            brand
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 18)

            VStack(spacing: 3) {
                ForEach(visibleSections) { section in
                    sidebarItem(section)
                }
            }
            .padding(.horizontal, 10)

            if !model.hostedServers.isEmpty {
                hostedServersGroup
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
            }

            Spacer(minLength: 12)

            if let instance = model.selectedInstance {
                instanceSummary(instance)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            javaStatus
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            accountButton
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            Text("NeoCraft \(AppConstants.version)")
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 11)
        }
        .background(StudioSidebarBackground())
    }

    private var brand: some View {
        Button {
            model.go(to: .play)
        } label: {
            HStack(spacing: 10) {
                VoxelCube(size: 38)
                    .shadow(color: NeoPalette.grass.opacity(0.4), radius: 9, y: 3)

                VStack(alignment: .leading, spacing: 1) {
                    Text("NeoCraft")
                        .font(.neoPixelBold(19))
                        .tracking(0.4)
                        .foregroundStyle(.primary)
                    Text("MINECRAFT LAUNCHER")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .tracking(1.35)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarItem(_ section: AppSection) -> some View {
        let selected = model.section == section
        let hovered = model.hoveredSection == section

        return Button {
            model.go(to: section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : (hovered ? NeoPalette.accent : Color.secondary))
                    .frame(width: 24)

                Text(section.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(selected ? Color.white : Color.primary)

                Spacer(minLength: 4)

                if section == .instances, !model.instances.isEmpty {
                    badge("\(model.instances.count)", selected: selected)
                } else if section == .mods, !model.modUpdates.isEmpty {
                    badge("\(model.modUpdates.count)↑", selected: selected, tint: NeoPalette.amber, filled: true)
                } else if section == .mods, !model.installedProjectIDs.isEmpty {
                    badge("\(model.installedProjectIDs.count)", selected: selected)
                } else if section == .dashboard, !model.hostedServers.isEmpty {
                    badge("\(model.hostedServers.count)", selected: selected)
                } else if section == .play, model.isGameRunning {
                    StatusDot(color: NeoPalette.mint, size: 6)
                } else if section == .mods, model.isSearchingMods {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .frame(width: 10, height: 10)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(itemBackground(selected: selected, hovered: hovered))
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                model.hoveredSection = section
            } else if model.hoveredSection == section {
                model.hoveredSection = nil
            }
        }
        .help(section.subtitle)
    }

    private func badge(_ text: String, selected: Bool, tint: Color = NeoPalette.accent, filled: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(selected || filled ? Color.white : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                selected ? Color.white.opacity(0.20) : (filled ? tint : Color.primary.opacity(0.08)),
                in: Capsule()
            )
    }

    private func itemBackground(selected: Bool, hovered: Bool) -> AnyShapeStyle {
        if selected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [NeoPalette.accent, NeoPalette.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(hovered ? Color.primary.opacity(0.07) : Color.clear)
    }

    /// Quick-jump list of hosted dedicated servers under the main sections.
    private var hostedServersGroup: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("HOSTED SERVERS")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)

            ForEach(model.hostedServers.prefix(5)) { server in
                hostedServerRow(server)
            }
            if model.hostedServers.count > 5 {
                Button {
                    model.go(to: .dashboard)
                } label: {
                    Text("+\(model.hostedServers.count - 5) more")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func hostedServerRow(_ server: HostedServer) -> some View {
        let running = model.isServerRunning(server)
        let ready = model.isServerReady(server)
        let settingUp = model.isSettingUpServer(server)
        let selected = model.section == .dashboard && model.dashboardServer?.id == server.id
        let color: Color = settingUp ? NeoPalette.amber
            : running ? (ready ? NeoPalette.mint : NeoPalette.sky)
            : Color.secondary

        return Button {
            model.openServerDashboard(server)
        } label: {
            HStack(spacing: 8) {
                StatusDot(color: color, size: 6)
                Text(server.name)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(AppModel.serverAddress(server).split(separator: ":").last.map(String.init) ?? "")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? NeoPalette.accent.opacity(0.16) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(server.name) — \(AppModel.serverAddress(server))")
    }

    private func instanceSummary(_ instance: GameInstance) -> some View {
        Button {
            model.selectInstance(instance)
            model.go(to: .instances)
        } label: {
            HStack(spacing: 9) {
                BlockIconTile(block: instance.iconBlock, color: Color(hex: instance.colorHex), symbol: instance.iconSymbol, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(instance.name)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(instance.versionLabel)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Selected instance")
    }

    private var javaStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(NeoPalette.mint)
            Text(javaLabel)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: model.settings.thermalMode.symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(model.settings.thermalMode == .coolQuiet ? NeoPalette.sky : NeoPalette.amber)
            Text(model.settings.thermalMode.shortTitle)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var javaLabel: String {
        if let selected = model.settings.selectedJavaPath,
           let runtime = model.javaRuntimes.first(where: { $0.executablePath == selected }) {
            return "Java \(runtime.majorVersion) · manual"
        }
        if let best = model.javaRuntimes
            .filter({ $0.isAppleSilicon })
            .max(by: { $0.majorVersion < $1.majorVersion }) {
            return "Java \(best.majorVersion) · automatic"
        }
        return "Java automatic"
    }

    private var accountButton: some View {
        Button {
            if model.activeAccount == nil {
                model.beginSignIn()
            } else {
                model.go(to: .account)
            }
        } label: {
            HStack(spacing: 9) {
                if let account = model.activeAccount {
                    AvatarView(uuid: account.uuid, size: 32, localImage: model.avatarImage(for: account))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.name)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            StatusDot(color: account.isOffline ? NeoPalette.amber : NeoPalette.mint, size: 5)
                            Text(account.isOffline ? "Offline account" : "Microsoft account")
                                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(NeoPalette.accent.opacity(0.14))
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NeoPalette.accent)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sign in")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text("Microsoft account")
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: model.activeAccount == nil ? "plus.circle" : "gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(model.activeAccount == nil ? "Sign in with Microsoft" : "Account settings")
    }
}
