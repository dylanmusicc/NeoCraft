import AppKit
import LauncherCore
import SwiftUI

@main
struct SiliconBedrockApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        NeoFonts.register()
    }

    var body: some Scene {
        Window("NeoCraft Bedrock", id: "main") {
            RootView().environment(delegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutCommand() }
            CommandGroup(replacing: .appSettings) { SettingsCommand() }
            PlayCommands(model: delegate.model)
            #if DEBUG
                DeveloperCommands(model: delegate.model)
            #endif
        }
        Window("About NeoCraft Bedrock", id: "about") {
            AboutView().environment(delegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}

/// The Play and Go menus NeoCraft has: launch or stop the game, and jump
/// between the pages. `play()` itself checks readiness, so the items stay
/// live and simply do nothing while something blocks a session.
private struct PlayCommands: Commands {
    let model: AppModel
    @FocusedValue(\.page) private var page

    var body: some Commands {
        CommandMenu("Play") {
            Button(model.isPlaying ? "Stop Minecraft" : "Play Minecraft") {
                model.isPlaying ? model.stop() : model.play()
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        CommandMenu("Go") {
            let shortcuts: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6", "7"]
            ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) {
                    page?.wrappedValue = item
                }
                .keyboardShortcut(shortcuts[index], modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let autoPlay = CommandLine.arguments.contains("--play")
    private var autoPlayTask: Task<Void, Never>?

    /// A `--play` launch is NeoCraft Bedrock running inside NeoCraft: it starts
    /// without a Dock icon or window and plays as soon as it can. Sudden
    /// termination must stay off — with no window on screen AppKit would
    /// otherwise quit the launcher before the game is up.
    func applicationWillFinishLaunching(_ notification: Notification) {
        if autoPlay {
            NSApp.setActivationPolicy(.accessory)
            ProcessInfo.processInfo.disableSuddenTermination()
            ProcessInfo.processInfo.disableAutomaticTermination("A Bedrock game may be running")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard autoPlay, autoPlayTask == nil else { return }
        NSApp.windows.forEach { $0.orderOut(nil) }
        autoPlayTask = Task { await playWhenReady() }
    }

    /// Waits for the launcher to know what it can do, then plays — or comes on
    /// screen when the player has to fix something first. Work already under
    /// way (an engine or game install) keeps the screen off.
    @MainActor
    private func playWhenReady() async {
        await model.start()
        while !Task.isCancelled {
            switch model.playState {
            case .ready:
                model.play()
                return
            case .blocked(.installingEngine), .blocked(.installingGame),
                .blocked(.earlierSessionRunning):
                try? await Task.sleep(for: .milliseconds(500))
            case .blocked(_):
                model.showLauncher()
                return
            case .starting(_), .running, .stopping:
                return
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        model.open(urls)
    }

    /// Opening the app again brings it back from having left for a game.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showLauncher()
        return true
    }

    /// Not when it took its windows off the screen for a game, which needs it
    /// running. A `--play` launch manages its own lifetime: it must not quit
    /// just because its window never came on screen.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        autoPlay ? false : !model.hasLeftForGame
    }

    /// Quitting with a game running asks first, then closes every game and waits until nothing
    /// of their sessions is left.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !model.sessions.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit NeoCraft Bedrock?")
        alert.informativeText = String(localized: "Minecraft is running and will close.")
        alert.addButton(withTitle: String(localized: "Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        Task {
            await model.endSessions()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
