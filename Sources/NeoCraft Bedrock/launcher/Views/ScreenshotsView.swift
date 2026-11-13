import AppKit
import LauncherCore
import QuickLookUI
import SwiftUI

/// Every screenshot the player has: the Java instances' `screenshots` folders
/// from NeoCraft's state, and each Bedrock account's `Screenshots` folder in
/// its prefix — grouped by source with the game version it was taken on.
struct ScreenshotsView: View {
    @Environment(AppModel.self) private var model

    /// One group of images: a NeoCraft Java instance or a Bedrock account.
    private struct Source: Identifiable {
        let id: String
        let title: String
        /// The version tag shown on the section, like "1.21.4 · Java".
        let versionTag: String
        let kind: Kind
        var urls: [URL] = []

        enum Kind { case java, bedrock }
    }

    @PlainState private var sources: [Source] = []
    @PlainState private var filter = ""
    @PlainState private var kindFilter: KindFilter = .all

    private enum KindFilter: String, CaseIterable {
        case all, java, bedrock
        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .java: "Java"
            case .bedrock: "Bedrock"
            }
        }
    }

    private var filtered: [Source] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return sources.compactMap { source in
            let kindMatches = switch kindFilter {
            case .all: true
            case .java: source.kind == .java
            case .bedrock: source.kind == .bedrock
            }
            guard kindMatches else { return nil }
            let urls = needle.isEmpty ? source.urls : source.urls.filter {
                source.title.lowercased().contains(needle)
                    || $0.lastPathComponent.lowercased().contains(needle)
            }
            guard !urls.isEmpty else { return nil }
            var copy = source
            copy.urls = urls
            return copy
        }
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: String(localized: "Screenshots"),
                subtitle: String(localized: "Every capture, from NeoCraft and NeoCraft Bedrock")
            ) {
                HStack(spacing: 8) {
                    Picker("", selection: $kindFilter) {
                        ForEach(KindFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    NeoCraftSearchField(
                        placeholder: String(localized: "Filter by name or file"), text: $filter)
                        .frame(width: 220)
                    Button { reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.pixel(.secondary, minHeight: 30))
                    .help("Scan again")
                }
            }
        } content: {
            if filtered.isEmpty {
                panel {
                    VStack(spacing: 10) {
                        TitleText("No screenshots yet", size: 16)
                        Text("Captures from Java and Bedrock instances show up here.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                ForEach(filtered) { source in
                    section(source)
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func section(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                TitleText(verbatim: source.title, size: 14)
                Text(source.versionTag)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                Text("\(source.urls.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.secondaryText)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
                spacing: 12
            ) {
                ForEach(source.urls, id: \.self) { url in
                    ScreenshotCell(url: url)
                }
            }
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().panel()
    }

    // MARK: Scanning

    private func reload() {
        var found: [Source] = []

        // NeoCraft's Java instances.
        for instance in NeoCraftFiles.javaInstances() {
            let urls = imageFiles(in: instance.screenshots)
            guard !urls.isEmpty else { continue }
            found.append(Source(
                id: "java-\(instance.id)", title: instance.name,
                versionTag: "\(instance.minecraftVersion) · Java", kind: .java, urls: urls))
        }

        // Every Bedrock account's game data, both products, deduplicated.
        let directory = DataDirectory.standard
        let user = HostEnvironment.current.user
        var seen = Set<String>()
        for account in model.library.accounts where !account.isPending {
            for product in GameProduct.allCases {
                guard let data = Optional(GameData(
                    of: product, account: account.id, in: directory, user: user)),
                    let comMojang = try? data.user()
                else { continue }
                let folder = comMojang.appending(path: "Screenshots")
                guard seen.insert(folder.path).inserted else { continue }
                let urls = imageFiles(in: folder)
                guard !urls.isEmpty else { continue }
                found.append(Source(
                    id: "bedrock-\(account.id)-\(product.rawValue)",
                    title: account.label,
                    versionTag: "\(bedrockVersion()) · Bedrock",
                    kind: .bedrock, urls: urls))
            }
        }
        sources = found
    }

    /// The version of the game the latest Bedrock profile plays, for the tag.
    private func bedrockVersion() -> String {
        for profile in model.library.profiles where profile.product == .release {
            if let installation = model.installation(of: profile) { return installation.version }
        }
        return "Bedrock"
    }

    private func imageFiles(in directory: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted {
                let l = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let r = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return l > r
            }
    }
}

/// One thumbnail: preview on click, copy/share/Finder in the context menu.
private struct ScreenshotCell: View {
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(Palette.slot)
                    Image(systemName: "photo")
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: NeoSync.shared.radius(10), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: NeoSync.shared.radius(10), style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { ScreenshotQuickLook.shared.preview(url: url) }
            .contextMenu {
                Button("Quick Look") { ScreenshotQuickLook.shared.preview(url: url) }
                Button("Copy Image") { copyToClipboard() }
                Button("Share…") { share() }
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .help("\(url.lastPathComponent) — click for Quick Look, right-click for more")

            Text(url.lastPathComponent)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func copyToClipboard() {
        guard let image = NSImage(contentsOf: url),
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    private func share() {
        guard let window = NSApp.keyWindow else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
    }
}

/// Minimal QLPreviewPanel bridge — one URL at a time.
private final class ScreenshotQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, @unchecked Sendable {
    static let shared = ScreenshotQuickLook()
    private var urls: [URL] = []

    @MainActor
    func preview(url: URL) {
        urls = [url]
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }
}
