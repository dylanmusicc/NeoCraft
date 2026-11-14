import AppKit
import LauncherCore
import SwiftUI

/// What NeoCraft Bedrock runs every profile on: the engine and Apple's graphics.
struct SettingsView: View {
    var body: some View {
        PageScroll {
            PageHeader(title: "Settings", subtitle: "What NeoCraft Bedrock runs every profile on.")
        } content: {
            AppearancePanel()
            EngineCard()
            GraphicsCard()
            LauncherPanel()
        }
    }
}

/// How the launcher looks. Anything picked here wins over the theme
/// NeoCraft mirrors; "Use NeoCraft's theme" hands control back.
private struct AppearancePanel: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Bumped to re-render after an override write (NeoSync reloads too).
    @PlainState private var tick = 0

    private var sync: NeoSync { NeoSync.shared }

    private var wallpaper: Binding<String> {
        Binding(
            get: { sync.wallpaperStyle },
            set: { NeoSync.LauncherTheme.setWallpaper($0 == "" ? nil : $0); NeoSync.shared.reload(); tick += 1 }
        )
    }

    private var accent: Binding<String> {
        Binding(
            get: { sync.effectiveAccentHex },
            set: { NeoSync.LauncherTheme.setAccent($0); NeoSync.shared.reload(); tick += 1 }
        )
    }

    private var trueBlack: Binding<Bool> {
        Binding(
            get: { sync.trueBlack },
            set: { NeoSync.LauncherTheme.setTrueBlack($0); NeoSync.shared.reload(); tick += 1 }
        )
    }

    private var liquidGlass: Binding<Bool> {
        Binding(
            get: { sync.liquidGlass },
            set: { NeoSync.LauncherTheme.setLiquidGlass($0); NeoSync.shared.reload(); tick += 1 }
        )
    }

    private var usesOverrides: Bool {
        _ = tick
        return NeoSync.LauncherTheme.accentHex != nil
            || NeoSync.LauncherTheme.wallpaperStyle != nil
            || NeoSync.LauncherTheme.trueBlack != nil
            || NeoSync.LauncherTheme.liquidGlass != nil
    }

    var body: some View {
        PanelSection(title: "Appearance") {
            HStack(spacing: 16) {
                RowLabel("Accent colour", detail: "Buttons, highlights and the backdrop blooms.")
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    ForEach(NeoSync.accentPresets, id: \.self) { hex in
                        Button {
                            accent.wrappedValue = hex
                        } label: {
                            Circle()
                                .fill(NeoSync.color(hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if accent.wrappedValue == hex {
                                        Image(systemName: "checkmark")
                                            .font(.neoUI(10, bold: true))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay(Circle().strokeBorder(Palette.ink.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help(hex)
                    }
                }
            }

            Picker(selection: wallpaper) {
                ForEach(NeoSync.wallpaperOptions, id: \.id) { option in
                    Label(option.title, systemImage: option.symbol).tag(option.id)
                }
            } label: {
                RowLabel("Wallpaper", detail: "The animated backdrop behind everything.")
            }
            .pickerStyle(.menu)

            Toggle(isOn: trueBlack) {
                RowLabel(
                    "True black",
                    detail: "Pure OLED black instead of the navy backdrop — easiest on dark mode."
                )
            }
            .toggleStyle(PixelToggleStyle())

            Toggle(isOn: liquidGlass) {
                RowLabel(
                    "Liquid Glass",
                    detail: "Clearer, glossier panels with brighter edge highlights — the macOS glass look."
                )
            }
            .toggleStyle(PixelToggleStyle())

            if usesOverrides {
                HStack {
                    Spacer()
                    Button("Use NeoCraft's Theme") {
                        NeoSync.LauncherTheme.reset()
                        NeoSync.shared.reload()
                        tick += 1
                    }
                    .buttonStyle(.pixel())
                    .fixedSize()
                }
            }
        }
    }
}

private struct EngineCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(
            icon: Artwork.disc, title: title, status: status, warning: releasesFolder,
            progress: model.engineInstall?.downloaded
        ) {
            MoreMenu {
                PixelMenuItem(model.installedEngine == nil ? "Install" : "Reinstall") {
                    model.reinstallEngine()
                }
                if let previous = model.previousEngine {
                    PixelMenuItem("Go Back to \(previous.version)") { model.revertEngine() }
                }
            }
            .disabled(!model.canChangeEngine)
            Button("Check Now") { model.checkForEngineUpdateNow() }
                .buttonStyle(.pixel())
                .fixedSize()
                .disabled(model.engineInstall != nil)
            if case .available(let release) = model.engineUpdate {
                Button("Update to \(release.index.version)") { model.installEngineUpdate() }
                    .buttonStyle(.pixel(.primary))
                    .fixedSize()
                    .disabled(!model.canChangeEngine)
            }
        }
    }

    private var title: String {
        model.installedEngine.map { String(localized: "Engine \($0.version)") }
            ?? String(localized: "No engine installed")
    }

    private var status: String {
        if let install = model.engineInstall {
            return String(localized: "Installing engine \(install.version)…")
        }
        switch model.lastEngineCheck {
        case nil:
            return String(localized: "Looking for a newer engine…")
        case .failure?:
            return String(localized: "The engine releases couldn't be reached.")
        case .success(let date)?:
            switch model.engineUpdate {
            case .available(let release)?:
                return String(localized: "Engine \(release.index.version) is available.")
            case .unsupported(let release, let reason)?:
                return String(localized: "Engine \(release.index.version) is out.") + " "
                    + Notice(error: reason).message
            case nil:
                return String(
                    localized:
                        "Up to date. Checked \(date.formatted(.relative(presentation: .named))).")
            }
        }
    }

    private var releasesFolder: String? {
        #if DEBUG
            if model.engineReleases != .bundled {
                return String(localized: "Releases from \(model.engineReleases.url.path)")
            }
        #endif
        return nil
    }
}

private struct GraphicsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card(icon: Artwork.chest, title: title, status: status, warning: warning) {
            if model.usesInstalledGraphics {
                Button("Use Built-in Version") { model.useBundledGraphics() }
                    .buttonStyle(.pixel())
                    .fixedSize()
                    .disabled(!model.canImportGraphics)
            }
            Button("Install New Version…") {
                if let image = NSOpenPanel.chooseToolkitImage() {
                    model.importToolkit(from: image)
                }
            }
            .buttonStyle(.pixel())
            .fixedSize()
            .disabled(!model.canImportGraphics)
        }
    }

    private var title: String {
        model.graphicsVersion.map { String(localized: "D3DMetal \($0)") }
            ?? String(localized: "D3DMetal: accept Apple's license first")
    }

    private var status: String {
        switch model.graphicsImport {
        case .importing?: String(localized: "Installing D3DMetal…")
        case .awaitingLicense?: String(localized: "Waiting for Apple's license.")
        case nil:
            model.usesInstalledGraphics
                ? String(localized: "From the Game Porting Toolkit you chose, as Apple made it.")
                : String(localized: "From Apple's Game Porting Toolkit, inside the app as Apple made it.")
        }
    }

    private var warning: String? {
        model.usesInstalledGraphics
            ? String(
                localized:
                    "NeoCraft Bedrock is tested with 4.0 beta 3 only. If the game misbehaves, go back to the built-in version."
            )
            : nil
    }
}

/// How the launcher behaves, and where the game is.
private struct LauncherPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PanelSection(title: "Launcher") {
            Toggle(
                isOn: Binding {
                    model.library.closesAfterLaunch
                } set: {
                    model.setClosesAfterLaunch($0)
                }
            ) {
                RowLabel(
                    "Close after the game starts",
                    detail:
                        "The launcher leaves the screen and the Dock while the game runs, and quits with it. If the game ends with a problem, it comes back to tell."
                )
            }
            HStack(spacing: 16) {
                RowLabel("Game folder", detail: "Where the selected profile's game is installed.")
                Spacer(minLength: 12)
                OpenButton("Open", url: model.installation?.game)
            }
        }
    }
}

private struct MoreMenu<Items: View>: View {
    @ViewBuilder let items: Items

    var body: some View {
        PixelMenu(width: 220) {
            Text(verbatim: "…")
        } items: {
            items
        }
        .buttonStyle(.pixel())
        .fixedSize()
        .accessibilityLabel("More")
    }
}

/// ⌘, opens the Settings page, as Settings… does in every Mac app.
struct SettingsCommand: View {
    @FocusedBinding(\.page) private var page

    var body: some View {
        Button("Settings…") { page = .settings }
            .keyboardShortcut(",")
            .disabled(page == nil)
    }
}
