import AppKit
import SwiftUI

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let selection: ProjectSelection

    private var project: ModrinthProject? { model.projectDetail }
    private var installed: Bool {
        guard let project else { return false }
        return model.installedProjectIDs.contains(project.id)
    }
    private var installing: Bool {
        guard let project else { return false }
        return model.installingProjectID == project.id
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            NeoDivider()

            if model.isLoadingProject && project == nil {
                LoadingStateView(message: "Loading project from Modrinth…")
                    .frame(maxHeight: .infinity)
            } else if let error = model.projectDetailError, project == nil {
                EmptyStateView(
                    symbol: "exclamationmark.triangle",
                    title: "Couldn't load this project",
                    message: error,
                    actionTitle: "Try Again",
                    action: {
                        model.openProject(id: selection.projectID, title: selection.title, iconURL: selection.iconURL)
                    }
                )
                .frame(maxHeight: .infinity)
            } else if let project {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        descriptionCard(project)
                        if let gallery = project.gallery, !gallery.isEmpty {
                            galleryCard(gallery)
                        }
                        infoCard(project)
                        versionsCard(project)
                    }
                    .padding(22)
                }
                .scrollIndicators(.hidden)
            } else {
                LoadingStateView(message: "Loading project…")
                    .frame(maxHeight: .infinity)
            }

            NeoDivider()
            footer
        }
        .frame(width: 820, height: 800)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 15) {
            RemoteImage(
                url: project?.icon ?? selection.iconURL.flatMap(URL.init(string:)),
                size: 72,
                cornerRadius: 17
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(project?.title ?? selection.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    if installed {
                        NeoPill(text: "Installed", symbol: "checkmark.seal.fill", tint: NeoPalette.mint)
                    }
                }

                if let project {
                    HStack(spacing: 6) {
                        NeoPill(text: project.type.singular, symbol: project.type.symbol, tint: NeoPalette.accent)
                        NeoPill(text: project.slug, tint: NeoPalette.slate)
                        if let license = project.license?.name ?? project.license?.id {
                            NeoPill(text: license, symbol: "doc.text", tint: NeoPalette.violet)
                        }
                    }
                    Text(project.description)
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Fetching details…")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    // MARK: - Description

    private func descriptionCard(_ project: ModrinthProject) -> some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "About",
                    subtitle: "Project description and notes",
                    symbol: "text.alignleft",
                    tint: NeoPalette.accent
                )
                MarkdownText(markdown: project.body ?? project.description, baseSize: 12)
            }
        }
    }

    // MARK: - Gallery

    private func galleryCard(_ gallery: [ModrinthGalleryItem]) -> some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Gallery",
                    subtitle: "Screenshots from the author",
                    symbol: "photo.on.rectangle.angled",
                    tint: NeoPalette.violet
                )
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(gallery.prefix(6))) { item in
                            RemoteImage(url: URL(string: item.url), size: 150, cornerRadius: 12)
                                .help(item.title ?? "")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Info

    private func infoCard(_ project: ModrinthProject) -> some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Compatibility",
                    subtitle: "Versions and environment",
                    symbol: "checkmark.shield.fill",
                    tint: NeoPalette.mint
                )

                InfoRow(label: "Downloads", value: Formatters.downloadCount(project.downloads), symbol: "arrow.down.circle", tint: NeoPalette.sky)
                InfoRow(label: "Followers", value: Formatters.downloadCount(project.followers), symbol: "heart.fill", tint: NeoPalette.rose)
                InfoRow(
                    label: "Client side",
                    value: (project.clientSide ?? "unknown").capitalized,
                    symbol: "desktopcomputer",
                    tint: NeoPalette.accent
                )
                InfoRow(
                    label: "Server side",
                    value: (project.serverSide ?? "unknown").capitalized,
                    symbol: "server.rack",
                    tint: NeoPalette.violet
                )

                if let loaders = project.loaders, !loaders.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Loaders")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 5) {
                            ForEach(Array(loaders.prefix(6)), id: \.self) { loader in
                                NeoPill(text: loader, tint: NeoPalette.accent)
                            }
                        }
                    }
                }

                if let versions = project.gameVersions, !versions.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Minecraft versions · \(versions.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 5) {
                            ForEach(Array(versions.prefix(10)), id: \.self) { version in
                                NeoPill(text: version, tint: NeoPalette.slate)
                            }
                            if versions.count > 10 {
                                NeoPill(text: "+\(versions.count - 10)", tint: NeoPalette.slate)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    if let url = project.sourceURL, let link = URL(string: url) {
                        Button {
                            NSWorkspace.shared.open(link)
                        } label: {
                            Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    }
                    if let url = project.issuesURL, let link = URL(string: url) {
                        Button {
                            NSWorkspace.shared.open(link)
                        } label: {
                            Label("Issues", systemImage: "ladybug")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    }
                    if let url = project.wikiURL, let link = URL(string: url) {
                        Button {
                            NSWorkspace.shared.open(link)
                        } label: {
                            Label("Wiki", systemImage: "book")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    }
                    if let url = project.discordURL, let link = URL(string: url) {
                        Button {
                            NSWorkspace.shared.open(link)
                        } label: {
                            Label("Discord", systemImage: "bubble.left.and.bubble.right")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    }
                }
            }
        }
    }

    // MARK: - Versions

    private func versionsCard(_ project: ModrinthProject) -> some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Files",
                    subtitle: compatibleSubtitle,
                    symbol: "doc.badge.arrow.up",
                    tint: NeoPalette.amber
                )

                if model.projectVersions.isEmpty {
                    Text("No files match this instance's Minecraft version and loader. Try a different release of \(project.title).")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 9) {
                        ForEach(Array(model.projectVersions.prefix(12))) { version in
                            versionRow(version)
                        }
                    }
                }
            }
        }
    }

    private var compatibleSubtitle: String {
        guard let instance = model.selectedInstance else {
            return "Select an instance to filter downloads"
        }
        return "Compatible with \(instance.minecraftVersion) · \(instance.loader.title)"
    }

    private func versionRow(_ version: ModrinthVersion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NeoPalette.amber)
                .frame(width: 28, height: 28)
                .background(NeoPalette.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(version.name)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    NeoPill(text: version.versionNumber, tint: NeoPalette.slate)
                }
                HStack(spacing: 5) {
                    ForEach(Array(version.gameVersions.prefix(4)), id: \.self) { gameVersion in
                        Text(gameVersion)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.055), in: Capsule())
                    }
                    if let date = version.datePublished {
                        Text(String(date.prefix(10)))
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            if installed {
                NeoPill(text: "Installed", symbol: "checkmark", tint: NeoPalette.mint)
            } else {
                Button {
                    model.installProject(versionID: version.id)
                } label: {
                    Label("Install", systemImage: "arrow.down.circle")
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                .disabled(installing || model.selectedInstance == nil)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let project, let url = project.webURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("View on Modrinth", systemImage: "safari")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            }

            if installing {
                ProgressView()
                    .controlSize(.small)
                Text(model.installDetail.isEmpty ? "Installing…" : model.installDetail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Close") {
                close()
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary))

            if let project {
                if installed {
                    Button {
                        model.removeInstalledProject(project.id, title: project.title)
                    } label: {
                        Label("Remove from Instance", systemImage: "trash")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, tint: NeoPalette.danger, compact: false))
                } else {
                    Button {
                        model.installProject()
                    } label: {
                        Label("Install Latest", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .primary))
                    .disabled(installing || model.selectedInstance == nil || model.projectVersions.isEmpty)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func close() {
        model.closeProject()
        dismiss()
    }
}
