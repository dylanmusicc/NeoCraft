import AppKit
import QuickLookUI
import SwiftUI

// MARK: - Aggregated screenshots

/// Photos-style grid of every `.png` across all instances, grouped by
/// instance. Spacebar triggers Quick Look, buttons offer copy/share/Finder.
struct ScreenshotsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    /// Instance sections narrowed by the search field — matches the
    /// instance name or the screenshot filename.
    private var filteredStats: [(instance: GameInstance, urls: [URL])] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return model.screenshotInstanceStats() }
        return model.screenshotInstanceStats().compactMap { entry in
            let urls = entry.urls.filter {
                entry.instance.name.lowercased().contains(needle)
                    || $0.lastPathComponent.lowercased().contains(needle)
            }
            return urls.isEmpty ? nil : (entry.instance, urls)
        }
    }

    /// Bedrock screenshots synced from NeoCraft Bedrock's prefixes,
    /// narrowed by the same filter.
    private var bedrockSections: [BedrockContent.ScreenshotGroup] {
        // Bedrock is a beta feature — synced screenshots hide with it.
        guard model.settings.betaFeatures.bedrockEdition else { return [] }
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return model.bedrockContent.screenshots.compactMap { group in
            let urls = needle.isEmpty ? group.urls : group.urls.filter {
                $0.lastPathComponent.lowercased().contains(needle)
            }
            return urls.isEmpty ? nil : BedrockContent.ScreenshotGroup(title: group.title, urls: urls)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: L10n.t("nav.screenshots.title"),
                    subtitle: L10n.t("page.screenshots.subtitle")
                ) {
                    NeoSearchField(placeholder: "Filter by instance or file", text: $filter)
                        .frame(width: 240)
                }

                if filteredStats.isEmpty && bedrockSections.isEmpty {
                    EmptyStateView(
                        symbol: "photo.on.rectangle.angled",
                        title: filter.isEmpty ? "No screenshots yet" : "No matches",
                        message: filter.isEmpty
                            ? "Press F2 in-game to capture a moment — it will show up here."
                            : "Nothing matches “\(filter)”."
                    )
                } else {
                    ForEach(filteredStats, id: \.instance.id) { entry in
                        instanceSection(instance: entry.instance, urls: entry.urls)
                    }
                    ForEach(bedrockSections) { group in
                        bedrockSection(group)
                    }
                }
            }
            .padding(28)
        }
        .onAppear { model.refreshBedrockContent() }
    }

    private func bedrockSection(_ group: BedrockContent.ScreenshotGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Bedrock — \(group.title)",
                subtitle: "\(group.urls.count) screenshots · synced from NeoCraft Bedrock"
            )
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
                spacing: 12
            ) {
                ForEach(group.urls, id: \.self) { url in
                    ScreenshotCell(url: url)
                }
            }
        }
    }

    private func instanceSection(instance: GameInstance, urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: instance.name,
                subtitle: "\(urls.count) screenshots"
            )
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
                spacing: 12
            ) {
                ForEach(urls, id: \.self) { url in
                    ScreenshotCell(url: url)
                }
            }
        }
    }
}

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
                    Rectangle().fill(Color.neoCardBackground)
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.neoCardStroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { openQuickLook(url) }
            .contextMenu {
                Button("Quick Look") { openQuickLook(url) }
                Button("Copy Image") { copyToClipboard(url) }
                Button("Share…") { share(url) }
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .help("\(url.lastPathComponent) — click for Quick Look, right-click for more")

            Text(url.lastPathComponent)
                .font(.neoCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func openQuickLook(_ url: URL) {
        QuickLookCoordinator.shared.preview(url: url)
    }

    private func copyToClipboard(_ url: URL) {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    private func share(_ url: URL) {
        guard let window = NSApp.keyWindow else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: .zero, of: window.contentView!, preferredEdge: .minY)
    }
}

// MARK: - Quick Look bridge

/// Minimal QLPreviewPanel data source — one URL at a time.
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate, @unchecked Sendable {
    static let shared = QuickLookCoordinator()
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
