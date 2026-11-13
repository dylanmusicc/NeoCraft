import AppKit
import LauncherCore
import SwiftUI

enum Page: CaseIterable, Identifiable {
    case play, instances, studio, servers, screenshots, account, settings

    /// Pages that only exist as part of the NeoCraft beta track — they mirror
    /// NeoCraft's own data (its theme, Java servers) and stay hidden until the
    /// `bedrockEdition` beta flag is on in NeoCraft's settings.
    var isNeoCraftSynced: Bool { self == .studio || self == .servers }

    /// The pages the sidebar and menus offer right now.
    static var visible: [Page] {
        allCases.filter { !$0.isNeoCraftSynced || NeoCraftFiles.betaEnabled() }
    }

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .play: "Play"
        case .instances: "Instances"
        case .studio: "Studio"
        case .servers: "Servers"
        case .screenshots: "Screenshots"
        case .account: "Account"
        case .settings: "Settings"
        }
    }

    /// The page's symbol, like NeoCraft's sidebar items.
    var symbol: String {
        switch self {
        case .play: "play.circle.fill"
        case .instances: "square.stack.3d.up.fill"
        case .studio: "paintbrush.pointed.fill"
        case .servers: "server.rack"
        case .screenshots: "photo.stack.fill"
        case .account: "person.crop.circle.fill"
        case .settings: "gearshape.fill"
        }
    }
}

extension FocusedValues {
    /// The page the main window shows, for the menu bar's commands.
    var page: Binding<Page>? {
        get { self[PageKey.self] }
        set { self[PageKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @PlainState private var page = Page.play
    /// The page actually on screen — a synced page falls back to Play when the
    /// NeoCraft beta flag is off.
    private var effectivePage: Page {
        page.isNeoCraftSynced && !NeoCraftFiles.betaEnabled() ? .play : page
    }

    /// What the Profiles page shows instead of the list.
    @PlainState private var profileDetail: ProfileDetail?
    @PlainState private var popups = Popups()
    @PlainState private var dropTargeted = false
    @PlainState private var bannersHeight: CGFloat = 0

    var body: some View {
        Group {
            if let failure = model.libraryFailure {
                UnreadableLibrary(error: failure)
            } else if !model.hasStarted {
                Color.clear
            } else if inFirstRun {
                FirstRunView()
            } else {
                HStack(spacing: 0) {
                    Sidebar(page: $page)
                    Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1)
                    Group {
                        switch effectivePage {
                        case .play:
                            PlayView(
                                showProfiles: {
                                    page = .instances
                                },
                                editProfile: {
                                    profileDetail = model.library.selectedProfile.map(
                                        ProfileDetail.settings)
                                    page = .instances
                                },
                                go: { page = $0 }
                            )
                        case .instances: ProfilesView(detail: $profileDetail)
                        case .studio: StudioView()
                        case .servers: ServersView()
                        case .screenshots: ScreenshotsView()
                        case .account: AccountView()
                        case .settings: SettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.bannersHeight, bannersHeight)
                }
                .focusedSceneValue(\.page, $page)
                .onChange(of: page) {
                    if page != .instances { profileDetail = nil }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    model.open(urls, into: openContentsProduct)
                    return urls.contains { ContentFile($0) != nil }
                } isTargeted: {
                    dropTargeted = $0
                }
                .tint(Palette.accent)
                .overlay {
                    if dropTargeted {
                        DropTarget(product: openContentsProduct)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if !inFirstRun {
                    if !model.leftovers.isEmpty {
                        LeftoversBanner()
                    }
                    EngineBanner()
                }
                if let notice = model.notice {
                    // A new notice is a new banner, with all of its time ahead.
                    NoticeBanner(notice: notice)
                        .id(notice.id)
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                bannersHeight = $0
            }
            .padding(.top, 84)
            .padding(.horizontal, 28)
            .padding(.leading, inFirstRun ? 0 : Sidebar.width)
        }
        .sheet(
            isPresented: Binding(
                get: { model.pendingToolkitLicense != nil },
                set: { if !$0 { model.decideToolkitLicense(accepted: false) } })
        ) {
            if let license = model.pendingToolkitLicense {
                ToolkitLicenseSheet(license: license)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { model.isSigningIn },
                set: { if !$0 { model.cancelSignIn() } })
        ) {
            SignInSheet()
        }
        .background { NeoBackdrop() }
        .ignoresSafeArea()
        .frame(minWidth: 920, minHeight: 600)
        .onChange(of: model.filesToPlace) {
            if !model.filesToPlace.isEmpty {
                popups.dialog = choiceOfGame(for: model.filesToPlace)
            }
        }
        .popups(popups)
        .task {
            await model.start()
            await model.watchForUpdates()
        }
    }

    /// Release last, so that Return chooses it.
    private func choiceOfGame(for files: [URL]) -> Dialog {
        let title =
            files.count == 1
            ? String(
                localized:
                    "Add “\(files[0].deletingPathExtension().lastPathComponent)” to which game?")
            : String(localized: "Add \(files.count) files to which game?")
        let account = model.selectedAccount?.label ?? ""
        return Dialog(
            title: title,
            message: String(
                localized:
                    "Worlds and packs go to \(account), and every profile of a game shares them."),
            answers: [
                .init(title: String(localized: "Cancel"), role: .cancel) { model.place(into: nil) }
            ]
                + model.playedProducts.reversed().map { product in
                    .init(title: product.title) { model.place(into: product) }
                })
    }

    /// The product of the Contents page on screen, which dropped files go to.
    private var openContentsProduct: GameProduct? {
        guard page == .instances, case .contents(let id)? = profileDetail else { return nil }
        return model.library.profile(id)?.product
    }

    /// The wizard shows the engine's download itself, and no session can have run before it.
    private var inFirstRun: Bool {
        model.library.setupCompleted == nil
    }
}

private struct Sidebar: View {
    static let width: CGFloat = 224

    @Binding var page: Page
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // The brand block, like NeoCraft's sidebar header.
            HStack(spacing: 10) {
                VoxelCube(size: 34)
                    .shadow(color: Palette.green.opacity(0.4), radius: 9, y: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("NeoCraft Bedrock")
                        .font(.neoPixelBold(15))
                        .tracking(0.3)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("BEDROCK EDITION")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 46)
            .padding(.bottom, 18)

            VStack(spacing: 3) {
                ForEach(Page.visible) { item in
                    NavigationItem(
                        title: item.title, symbol: item.symbol, selected: item == page
                    ) {
                        page = item
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            Activity()
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                // Neo Studio's sidebar translucency, 0…1.
                Rectangle().fill(.thinMaterial)
                    .opacity(0.55 + NeoSync.shared.sidebarMaterial * 0.45)
                Palette.accent.opacity(colorScheme == .dark ? 0.05 : 0.03)
            }
        }
    }
}

/// Where worlds and packs dropped on the window go.
private struct DropTarget: View {
    @Environment(AppModel.self) private var model
    let product: GameProduct?

    var body: some View {
        VStack(spacing: 10) {
            TitleText("Drop to add", size: 20)
            Text(verbatim: detail)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Palette.secondaryText)
        }
        .padding(24)
        .panel()
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.45))
        .allowsHitTesting(false)
    }

    private var detail: String {
        guard let account = model.selectedAccount else {
            return String(localized: "Add an account first.")
        }
        guard let product else {
            return String(
                localized: "Worlds and packs go to \(account.label). Choose the game next.")
        }
        return String(localized: "Worlds and packs go to \(account.label) in \(product.title).")
    }
}

/// Shown instead of everything else while the library can't be read.
private struct UnreadableLibrary: View {
    @Environment(AppModel.self) private var model
    let error: any Error

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleText("NeoCraft Bedrock can't read its settings", size: 20)
            Text(verbatim: reason)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Until it can, NeoCraft Bedrock changes none of its files.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Palette.secondaryText)
            RevealButton("Show in Finder", url: model.directory.library)
        }
        .padding(24)
        .frame(width: 520, alignment: .leading)
        .panel()
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neoBackground()
    }

    private var reason: String {
        switch error {
        case is LibraryError:
            String(
                localized: "A newer version of NeoCraft Bedrock saved them. Open NeoCraft Bedrock with that version.")
        default:
            error.localizedDescription
        }
    }
}

/// What the launcher is busy with, seen from every page: the game being installed, the sessions
/// starting, playing or closing.
private struct Activity: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let install = model.gameInstall, let profile = model.library.profile(install.profile)
            {
                VStack(alignment: .leading, spacing: 6) {
                    TitleText(verbatim: String(localized: "Installing"), size: 12)
                    Text(verbatim: model.name(of: profile))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Palette.secondaryText)
                    ProgressBar(value: install.progress?.fraction ?? 0)
                }
            }
            ForEach(model.library.accounts) { account in
                if let session = model.sessions[account.id],
                    let profile = model.library.profile(session.profile)
                {
                    VStack(alignment: .leading, spacing: 6) {
                        TitleText(verbatim: title(of: session), size: 12, color: Palette.positive)
                        Text(verbatim: "\(model.name(of: profile))\n\(account.label)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(of session: RunningSession) -> String {
        switch session.phase {
        case .running:
            session.editor ? String(localized: "In Editor") : String(localized: "Playing")
        case .stopping: String(localized: "Closing")
        case .startingService, .checkingLicense, .preparingPrefix, .launching:
            String(localized: "Starting")
        }
    }
}

/// A sidebar item like NeoCraft's: symbol and title, the accent gradient
/// when selected.
private struct NavigationItem: View {
    let title: LocalizedStringKey
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @PlainState private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(
                        selected ? Color.white : (hovered ? Palette.accent : Color.secondary))
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: NeoSync.shared.radius(9), style: .continuous)
                    .fill(background)
            }
            .contentShape(RoundedRectangle(cornerRadius: NeoSync.shared.radius(9), style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .padding(.horizontal, 10)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var background: AnyShapeStyle {
        if selected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Palette.accent, Palette.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        }
        return AnyShapeStyle(hovered ? Color.primary.opacity(0.07) : Color.clear)
    }
}

nonisolated private struct PageKey: FocusedValueKey {
    typealias Value = Binding<Page>
}
