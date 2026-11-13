import AppKit
import SwiftUI

struct PatchNoteDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let entry: PatchNoteEntry

    private var detail: PatchNoteDetail? { model.detailedPatchNote }
    private var imageURL: URL? {
        (detail?.image?.url ?? entry.image?.url).flatMap(URL.init(string:))
    }
    private var bodyText: String {
        if let body = detail?.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        if let short = entry.shortText, !short.isEmpty {
            return short
        }
        return "Patch notes for this release are not available offline. Open Minecraft.net for the complete notes."
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            NeoDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if imageURL != nil {
                        banner
                    }
                    if model.isLoadingPatchNote && detail == nil {
                        LoadingStateView(message: "Loading patch notes…")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 7) {
                            NeoPill(
                                text: entry.type == "snapshot" ? "Snapshot" : "Release",
                                symbol: entry.type == "snapshot" ? "flask.fill" : "checkmark.seal.fill",
                                tint: entry.type == "snapshot" ? NeoPalette.violet : NeoPalette.mint
                            )
                            if !entry.version.isEmpty {
                                NeoPill(text: entry.version, symbol: "cube.fill", tint: NeoPalette.accent)
                            }
                            if !entry.date.isEmpty {
                                Text(entry.date)
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        MarkdownText(markdown: bodyText, baseSize: 12.5)
                    }
                    .padding(.horizontal, 2)
                }
                .padding(22)
            }
            .scrollIndicators(.hidden)
            NeoDivider()
            footer
        }
        .frame(width: 620, height: 660)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [NeoPalette.sky, NeoPalette.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: entry.type == "snapshot" ? "flask.fill" : "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail?.title ?? entry.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text("Minecraft Java Edition · patch notes")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var banner: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    LinearGradient(
                        colors: [NeoPalette.accent.opacity(0.35), NeoPalette.violet.opacity(0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.copyToClipboard(entry.version, label: "Version copied")
            } label: {
                Label("Copy Version", systemImage: "doc.on.doc")
            }
            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))

            if let url = URL(string: "https://www.minecraft.net/en-us/news") {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Minecraft.net", systemImage: "safari")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary))
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
    }
}
