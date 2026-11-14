import AppKit
import SwiftUI

/// Hidden `--snapshot=<section>` mode: renders a launcher page offscreen
/// via `ImageRenderer` and writes a PNG — used for README/marketing
/// screenshots where macOS screen-recording permission isn't available.
///
/// Usage:
///   NeoCraft --snapshot=servers --snapshot-out=/tmp/servers.png
///
/// The app still boots normally (bootstrap loads real state from disk),
/// shows one tiny helper window while rendering, then quits.
enum SnapshotSupport {
    struct Request {
        let section: AppSection
        let output: URL
    }

    static var request: Request? {
        let args = ProcessInfo.processInfo.arguments
        guard let spec = args.first(where: { $0.hasPrefix("--snapshot=") }) else { return nil }
        let raw = String(spec.dropFirst("--snapshot=".count))
        guard let section = AppSection(rawValue: raw) else { return nil }
        let output = args.first(where: { $0.hasPrefix("--snapshot-out=") })
            .map { URL(fileURLWithPath: String($0.dropFirst("--snapshot-out=".count))) }
            ?? URL(fileURLWithPath: "/tmp/neocraft-\(raw).png")
        return Request(section: section, output: output)
    }
}

/// Tiny window host that runs the offscreen render and then quits.
struct SnapshotRenderView: View {
    let request: SnapshotSupport.Request

    var body: some View {
        Color.clear
            .frame(width: 10, height: 10)
            .task { await render() }
    }

    @MainActor
    private func render() async {
        let model = AppModel.shared
        // `init` already kicked off bootstrap — wait for it to settle.
        var waited = 0
        while model.isBootstrapping, waited < 300 {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 1
        }

        if request.section == .dashboard, model.dashboardServer == nil {
            model.dashboardServer = model.hostedServers.first
        }
        model.go(to: request.section)

        // Give section-specific async loads (mod search, pings, backups)
        // time to land before the single rendered frame is captured.
        let settle: Duration = request.section == .mods ? .seconds(14) : .seconds(5)
        try? await Task.sleep(for: settle)

        let renderer = ImageRenderer(content: snapshotContent(model: model))
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("snapshot: render failed\n".data(using: .utf8)!)
            NSApp.terminate(nil)
            return
        }
        do {
            try png.write(to: request.output)
            FileHandle.standardError.write("snapshot: wrote \(request.output.path)\n".data(using: .utf8)!)
        } catch {
            FileHandle.standardError.write("snapshot: write failed: \(error)\n".data(using: .utf8)!)
        }
        NSApp.terminate(nil)
    }

    /// Mirrors RootView's chrome (sidebar + detail on NeoBackground) at a
    /// fixed marketing resolution instead of the live split view.
    @ViewBuilder
    private func snapshotContent(model: AppModel) -> some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 240)
            Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1)
            ZStack {
                NeoBackground()
                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 1440, height: 900)
        .environment(model)
        .tint(NeoPalette.accent)
    }

    @ViewBuilder
    private var detailView: some View {
        switch request.section {
        case .play: PlayView()
        case .instances: InstancesView()
        case .servers, .dashboard: ServersView()
        case .studio: StudioView()
        case .mods: ModLibraryView()
        case .screenshots: ScreenshotsView()
        case .account: AccountView()
        case .settings: SettingsView()
        }
    }
}
