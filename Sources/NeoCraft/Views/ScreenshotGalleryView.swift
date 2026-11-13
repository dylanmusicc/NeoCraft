import AppKit
import SwiftUI

/// Full-screen-ish gallery of an instance's `screenshots/` folder.
/// Thumbnails load lazily per cell; tapping one opens it in Preview.
struct ScreenshotGalleryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance

    private var screenshots: [URL] {
        InstanceScanner.screenshotURLs(in: instance.gameDirectory)
    }

    private var screenshotsDirectory: URL {
        instance.gameDirectory.appendingPathComponent("screenshots", isDirectory: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            NeoDivider()

            if screenshots.isEmpty {
                EmptyStateView(
                    symbol: "camera",
                    title: "No screenshots yet",
                    message: "Press F2 in-game to capture a moment. Screenshots from \(instance.name) show up here."
                )
                .padding(30)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 210, maximum: 320), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(screenshots, id: \.self) { url in
                            ScreenshotCell(url: url)
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: 860, height: 660)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 13) {
            BlockIconTile(
                block: instance.iconBlock,
                color: Color(hex: instance.colorHex),
                symbol: instance.iconSymbol,
                size: 42
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshots")
                    .font(.neoPixelBold(18))
                Text("\(instance.name) · \(screenshots.count) captured")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.reveal(screenshotsDirectory)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }
}

private struct ScreenshotCell: View {
    let url: URL

    /// `NSImage(contentsOf:)` only reads the file header eagerly, so this is
    /// cheap enough to evaluate per render and avoids `@State` (the SwiftUI
    /// macro plugin is unavailable in this toolchain).
    private var image: NSImage? { NSImage(contentsOf: url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.primary.opacity(0.06))

                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                }
            }
            .buttonStyle(.plain)
            .help(url.lastPathComponent)

            Text(url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
