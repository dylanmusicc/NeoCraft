import AppKit
import SwiftUI

@main
struct NeoCraftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    init() {
        NeoFonts.register()
    }

    var body: some Scene {
        WindowGroup("NeoCraft") {
            RootView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1240, height: 820)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Install Performance Pack") {
                    if let instance = model.selectedInstance {
                        model.installPerformancePack(instance)
                    }
                }
                .disabled(model.selectedInstance?.loader != .fabric)

                Button("Run Flight Check") {
                    if let instance = model.selectedInstance {
                        model.openFlightCheck(for: instance)
                    }
                }
                .disabled(model.selectedInstance == nil)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Instance") {
                    model.beginCreateInstance()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Play") {
                Button(model.isGameRunning ? "Stop Minecraft" : "Launch Minecraft") {
                    if model.isGameRunning {
                        model.stopGame()
                    } else {
                        model.startGame()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Quick Launch") {
                    model.startGame()
                }
                .keyboardShortcut(.return, modifiers: .command)

                Button("Prepare Game Files") {
                    if let instance = model.selectedInstance {
                        model.prepareGame(instance)
                    }
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Console") {
                    model.showConsole.toggle()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Install Neo Boost") {
                    if let instance = model.selectedInstance {
                        model.installBoost(instance)
                    }
                }
                .disabled(model.selectedInstance?.loader != .fabric)
            }
            CommandMenu("Go") {
                Button("Play") {
                    model.go(to: .play)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Instances") {
                    model.go(to: .instances)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Neo Studio") {
                    model.go(to: .studio)
                }
                .keyboardShortcut("7", modifiers: .command)

                Button("Mod Library") {
                    model.go(to: .mods)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Screenshots") {
                    model.go(to: .screenshots)
                }
                .keyboardShortcut("5", modifiers: .command)

                Button("Account") {
                    model.go(to: .account)
                }
                .keyboardShortcut("6", modifiers: .command)

                Button("Settings") {
                    model.go(to: .settings)
                }
                .keyboardShortcut("4", modifiers: .command)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.go(to: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                Button("Open Logs Folder") {
                    model.reveal(AppPaths.logs)
                }
                Button("Open Game Data Folder") {
                    model.reveal(AppPaths.root)
                }
            }
        }

        MenuBarExtra("NeoCraft", systemImage: model.isGameRunning
                     ? "gamecontroller.fill" : "shippingbox.fill") {
            NeoCraftMenuBarPanel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Live menu-bar panel styled like an Apple Control Center: a status header,
/// a grid of live telemetry and quick-action tiles, and an Open/Quit footer.
/// `.window` style keeps the telemetry refreshing in real time.
private struct NeoCraftMenuBarPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: app icon + session status.
            HStack(spacing: 10) {
                Group {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 34, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(NeoPalette.accent)
                            .frame(width: 34, height: 34)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("NeoCraft")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(model.isGameRunning
                         ? (model.runningInstance?.name ?? "Minecraft is running")
                         : "Ready when you are")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let started = model.launchStartedAt {
                    Text(Formatters.duration(Date().timeIntervalSince(started)))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Tile grid.
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                thermalTile
                memoryTile
                cpuTile
                powerTile
                instanceTile
                screenshotsTile
                consoleTile
            }

            Divider()

            // Footer.
            HStack {
                Button("Open NeoCraft") {
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: Tiles

    private var thermalTile: some View {
        tileShell(symbol: "thermometer.medium", tint: thermalTint) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.snapshot.thermalState.displayName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("Thermal")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var memoryTile: some View {
        tileShell(symbol: "memorychip", tint: NeoPalette.accent) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(Int(model.snapshot.memoryFraction * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                }
                // Unified memory ring.
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: model.snapshot.memoryFraction)
                        .stroke(
                            NeoPalette.accent,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 26, height: 26)
                Text("Unified Memory")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var cpuTile: some View {
        tileShell(symbol: "cpu", tint: NeoPalette.sky) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int((model.snapshot.cpuUsage * 100).rounded()))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("CPU")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var powerTile: some View {
        let onAC = model.snapshot.onACPower
        return tileShell(
            symbol: onAC ? "powerplug.fill" : "battery.25",
            tint: onAC && !model.snapshot.lowPowerMode ? NeoPalette.mint : NeoPalette.amber
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(onAC ? (model.snapshot.lowPowerMode ? "Low Power" : "AC Power") : "Battery")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(model.snapshot.chipName)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var instanceTile: some View {
        tileShell(
            symbol: model.isGameRunning ? "gamecontroller.fill" : "shippingbox.fill",
            tint: model.isGameRunning ? NeoPalette.mint : NeoPalette.accent
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.runningInstance?.name ?? model.selectedInstance?.name ?? "No instance")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if model.isGameRunning {
                        Button("Stop") { model.stopGame() }
                            .buttonStyle(NeoButtonStyle(kind: .danger, compact: true))
                    } else {
                        Button("Play") {
                            if let instance = model.selectedInstance {
                                model.startGame(instance)
                            }
                        }
                        .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                        .disabled(model.selectedInstance == nil)
                    }
                }
            }
        }
    }

    private var screenshotsTile: some View {
        tileShell(symbol: "photo.stack.fill", tint: NeoPalette.rose) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Screenshots")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Button("Open") { model.go(to: .screenshots) }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            }
        }
    }

    private var consoleTile: some View {
        tileShell(symbol: "terminal", tint: NeoPalette.slate) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Console")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Button("Toggle") { model.showConsole.toggle() }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            }
        }
    }

    /// Shared tile chrome: tinted icon + content on a rounded material cell.
    private func tileShell<Content: View>(
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        }
    }

    private var thermalTint: Color {
        switch model.snapshot.thermalState {
        case .nominal: return NeoPalette.mint
        case .fair: return NeoPalette.amber
        case .serious, .critical: return NeoPalette.danger
        @unknown default: return NeoPalette.sky
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
