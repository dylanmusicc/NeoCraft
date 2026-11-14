import AppKit
import LauncherCore
import SwiftUI

/// The Play page, laid out like NeoCraft's: a header, a hero card with the
/// big launch button, and a dashboard of what's worth knowing — account,
/// game, runtime and the last captures.
struct PlayView: View {
    @Environment(AppModel.self) private var model
    let showProfiles: @MainActor () -> Void
    let editProfile: @MainActor () -> Void
    let go: @MainActor (Page) -> Void

    var body: some View {
        PageScroll {
            PageHeader(
                title: String(localized: "Play"),
                subtitle: String(localized: "Minecraft Bedrock through NeoCraft Bedrock")
            ) {
                HStack(spacing: 8) {
                    statusPill
                    if let account = model.selectedAccount {
                        NeoCraftPill(text: account.label, symbol: "person.crop.circle", tint: Palette.accent)
                    }
                }
            }
        } content: {
            hero
            dashboard
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let state = model.playState
        let caption = StatusCaption(state)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VoxelCube(size: 58)
                    .shadow(color: Palette.green.opacity(0.4), radius: 10, y: 4)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        NeoCraftPill(
                            text: caption.title,
                            symbol: state == .ready ? "sparkles" : "exclamationmark.triangle",
                            tint: state == .ready ? Palette.positive : Palette.warning)
                        if let installation = model.installation {
                            NeoCraftPill(
                                text: "\(installation.version) · \(installation.product == .preview ? "Preview" : "Release")",
                                symbol: "gamecontroller.fill", tint: Palette.accent)
                        }
                    }
                    Text(model.selectedProfile.map { model.name(of: $0) } ?? String(localized: "No profile"))
                        .font(.neoPixelBold(24))
                        .tracking(0.5)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let detail = caption.detail {
                        Text(detail)
                            .font(.neoUI(12.5, bold: false))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 14)

                VStack(alignment: .trailing, spacing: 10) {
                    ProfilePicker(
                        changeable: state.allowsChanges, showProfiles: showProfiles,
                        editProfile: editProfile)
                    HStack(spacing: 10) {
                        if state == .blocked(.gameMissing) {
                            Button("INSTALL") { go(.instances) }
                                .buttonStyle(.pixel(.primary, size: 22, minHeight: PickerLabel.height))
                                .frame(width: 170)
                        } else if state == .running || state == .stopping {
                            Button("STOP") { model.stop() }
                                .buttonStyle(.pixel(.danger, size: 22, minHeight: PickerLabel.height))
                                .frame(width: 170)
                                .disabled(state == .stopping)
                        } else {
                            Button("PLAY") { model.play() }
                                .buttonStyle(.pixel(.primary, size: 22, minHeight: PickerLabel.height))
                                .frame(width: 170)
                                .disabled(state != .ready)
                        }
                        Button { go(.instances) } label: {
                            Image(systemName: "square.stack.3d.up.fill")
                        }
                        .buttonStyle(.pixel(.secondary, minHeight: PickerLabel.height))
                        .frame(width: 52)
                        .help("Instances")
                    }
                }
            }
        }
        .padding(22)
        .panelBackground()
    }

    private var statusPill: some View {
        let state = model.playState
        let caption = StatusCaption(state)
        return NeoCraftPill(
            text: caption.title,
            symbol: state == .ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            tint: state == .ready ? Palette.positive : Palette.warning)
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        let left: [DashboardCard] = [.account, .runtime]
        let right: [DashboardCard] = [.game, .activity]
        return HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 18) {
                ForEach(left) { card($0) }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            VStack(spacing: 18) {
                ForEach(right) { card($0) }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private enum DashboardCard: String, Identifiable {
        case account, game, runtime, activity
        var id: String { rawValue }
    }

    @ViewBuilder
    private func card(_ kind: DashboardCard) -> some View {
        switch kind {
        case .account: accountCard
        case .game: gameCard
        case .runtime: runtimeCard
        case .activity: activityCard
        }
    }

    private func dashHeader(_ title: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.neoUI(11.0, bold: true))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.neoUI(13.0, bold: true))
                .foregroundStyle(Palette.text)
            Spacer()
        }
    }

    private func dashCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(16).panelBackground()
    }

    // MARK: Cards

    private var accountCard: some View {
        dashCard {
            VStack(alignment: .leading, spacing: 12) {
                dashHeader("Account", symbol: "person.crop.circle.fill", tint: Palette.accent)
                if let account = model.selectedAccount {
                    HStack(spacing: 12) {
                        PixelImage(image: Artwork.head(for: account.id))
                            .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: account.label)
                                .font(.neoUI(13.0, bold: true))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                            Text(model.readiness.signedIn == true
                                ? String(localized: "Signed in") : String(localized: "Sign-in needed"))
                                .font(.neoUI(11.0, bold: false))
                                .foregroundStyle(
                                    model.readiness.signedIn == true ? Palette.positive : Palette.warning)
                        }
                        Spacer()
                    }
                } else {
                    Text("No account")
                        .font(.neoUI(13.0, bold: false))
                        .foregroundStyle(Palette.secondaryText)
                }
                Button("Manage Account…") { go(.account) }
                    .buttonStyle(.pixel(.secondary, minHeight: 28))
            }
        }
    }

    private var gameCard: some View {
        let settings = model.selectedProfile?.settings
        return dashCard {
            VStack(alignment: .leading, spacing: 12) {
                dashHeader("Game", symbol: "gamecontroller.fill", tint: Palette.green)
                if let installation = model.installation {
                    infoRow("Version", "\(installation.version) · \(installation.product == .preview ? "Preview" : "Release")")
                    infoRow("Installed", installation.installed.formatted(date: .abbreviated, time: .omitted))
                } else {
                    infoRow("Status", "Not installed")
                }
                if let settings {
                    infoRow("Graphics", settings.backend == .metal4 ? "Metal 4" : "Metal 3")
                    infoRow("msync", settings.usesMsync ? "On" : "Off")
                    infoRow("Full screen", settings.startsFullScreen ? "On" : "Off")
                }
                Button("Edit Instance…") { editProfile() }
                    .buttonStyle(.pixel(.secondary, minHeight: 28))
                    .disabled(model.selectedProfile == nil)
            }
        }
    }

    private var runtimeCard: some View {
        let readiness = model.readiness
        return dashCard {
            VStack(alignment: .leading, spacing: 12) {
                dashHeader("Runtime", symbol: "cpu", tint: Palette.sky)
                checkRow("Engine", ok: readiness.engine)
                checkRow("D3DMetal", ok: readiness.graphics)
                checkRow("Rosetta 2", ok: readiness.rosettaInstalled)
                if model.offeredEngineUpdate != nil {
                    Text("Engine update available")
                        .font(.neoUI(11.0, bold: false))
                        .foregroundStyle(Palette.warning)
                }
                Button("Settings…") { go(.settings) }
                    .buttonStyle(.pixel(.secondary, minHeight: 28))
            }
        }
    }

    private var activityCard: some View {
        let state = model.playState
        let caption = StatusCaption(state)
        return dashCard {
            VStack(alignment: .leading, spacing: 12) {
                dashHeader("Activity", symbol: "waveform.path.ecg", tint: Palette.rose)
                Text(caption.title)
                    .font(.neoPixelBold(15))
                    .foregroundStyle(Palette.text)
                if let session = model.selectedSession {
                    infoRow("Phase", Self.phaseTitle(session.phase))
                } else if let detail = caption.detail {
                    Text(detail)
                        .font(.neoUI(12.0, bold: false))
                        .foregroundStyle(Palette.secondaryText)
                }
                if state == .running || state == .stopping {
                    Button("Stop Minecraft") { model.stop() }
                        .buttonStyle(.pixel(.danger, minHeight: 30))
                        .disabled(state == .stopping)
                }
            }
        }
    }

    private static func phaseTitle(_ phase: SessionPhase) -> String {
        switch phase {
        case .startingService: String(localized: "Starting the account service…")
        case .checkingLicense: String(localized: "Checking the license…")
        case .preparingPrefix: String(localized: "Preparing Windows…")
        case .launching: String(localized: "Launching Minecraft…")
        case .running: String(localized: "Running")
        case .stopping: String(localized: "Stopping…")
        }
    }

    // MARK: Rows

    private func infoRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.neoUI(12.0, bold: false))
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Text(value)
                .font(.neoUI(12.0, bold: true))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func checkRow(_ label: LocalizedStringKey, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.neoUI(12.0, bold: true))
                .foregroundStyle(ok ? Palette.positive : Palette.negative)
            Text(label)
                .font(.neoUI(12.0, bold: false))
                .foregroundStyle(Palette.text)
            Spacer()
        }
    }
}

/// The state caption the hero and the activity card share — the same
/// wording the old launch bar used.
private struct StatusCaption {
    let title: String
    let detail: String?

    init(_ state: PlayState) {
        switch state {
        case .ready: (title, detail) = (String(localized: "Ready"), nil)
        case .running: (title, detail) = (String(localized: "Playing"), String(localized: "Quit from the game, or stop it here."))
        case .stopping: (title, detail) = (String(localized: "Closing Minecraft…"), nil)
        case .starting(.startingService): (title, detail) = (String(localized: "Starting the account service…"), nil)
        case .starting(.checkingLicense): (title, detail) = (String(localized: "Checking the license…"), nil)
        case .starting(.preparingPrefix):
            (title, detail) = (String(localized: "Preparing Windows…"), String(localized: "The first time takes about half a minute."))
        case .starting: (title, detail) = (String(localized: "Starting Minecraft…"), nil)
        case .blocked(.earlierSessionRunning):
            (title, detail) = (String(localized: "The last session is still closing"), String(localized: "End it from the message above."))
        case .blocked(.anotherAccountPlaying):
            (title, detail) = (String(localized: "Another account is playing"), String(localized: "Switch to it in the account menu to stop its game."))
        case .blocked(.rosettaMissing):
            (title, detail) = (String(localized: "Rosetta is not installed"), String(localized: "Install it with softwareupdate --install-rosetta."))
        case .blocked(.installingEngine): (title, detail) = (String(localized: "Installing the engine…"), nil)
        case .blocked(.engineMissing):
            (title, detail) = (String(localized: "The engine is not installed"), String(localized: "NeoCraft Bedrock installs it as soon as it can download it."))
        case .blocked(.graphicsMissing):
            (title, detail) = (String(localized: "D3DMetal is missing"), String(localized: "Accept Apple's license in the first-run wizard, or install the app again."))
        case .blocked(.installingGame): (title, detail) = (String(localized: "Installing Minecraft…"), String(localized: "Follow it in Instances."))
        case .blocked(.gameMissing): (title, detail) = (String(localized: "Minecraft is not installed"), String(localized: "Install it from Instances."))
        case .blocked(.accountMissing):
            (title, detail) = (String(localized: "No account"), String(localized: "Add your Microsoft account on the Account page."))
        case .blocked(.accountNotAllowed):
            (title, detail) = (String(localized: "Not in this build"), String(localized: "A debug build plays only the development account."))
        case .blocked(.signInNeeded):
            (title, detail) = (String(localized: "Sign-in needed"), String(localized: "Sign in again on the Account page."))
        }
    }
}

/// A small tinted pill like NeoCraft's `NeoPill`.
private struct NeoCraftPill: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.neoUI(9.0, bold: true))
            Text(verbatim: text)
                .font(.neoUI(11.0, bold: true))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 0.8))
    }
}

/// The newest few captures for the dashboard card.
private struct RecentShots: View {
    @Environment(AppModel.self) private var model
    @PlainState private var urls: [URL] = []

    var body: some View {
        HStack(spacing: 8) {
            if urls.isEmpty {
                Text("Nothing captured yet")
                    .font(.neoUI(12.0, bold: false))
                    .foregroundStyle(Palette.secondaryText)
            } else {
                ForEach(urls.prefix(4), id: \.self) { url in
                    if let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: NeoSync.shared.radius(6), style: .continuous))
                    }
                }
            }
        }
        .frame(height: 40, alignment: .leading)
        .onAppear(perform: scan)
    }

    private func scan() {
        var found: [URL] = []
        let directory = DataDirectory.standard
        let user = HostEnvironment.current.user
        for account in model.library.accounts where !account.isPending {
            for product in GameProduct.allCases {
                guard let data = Optional(GameData(
                    of: product, account: account.id, in: directory, user: user)),
                    let comMojang = try? data.user()
                else { continue }
                let folder = comMojang.appending(path: "Screenshots")
                if let entries = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) {
                    found += entries.filter { $0.pathExtension.lowercased() == "png" }
                }
            }
        }
        urls = found.sorted {
            let l = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let r = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return l > r
        }
    }
}
