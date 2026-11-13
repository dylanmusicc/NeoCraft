import SwiftUI

struct ModLibraryView: View {
    @Environment(AppModel.self) private var model

    private var types: [ModrinthProjectType] { ModrinthProjectType.browserTypes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: L10n.t("nav.mods.title"),
                    subtitle: L10n.t("page.mods.subtitle")
                ) {
                    HStack(spacing: 8) {
                        if model.isSearchingMods || model.isCheckingUpdates {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button {
                            model.checkForUpdates()
                        } label: {
                            Label(
                                model.isCheckingUpdates
                                    ? "Checking…"
                                    : (model.modUpdates.isEmpty ? "Check Updates" : "Updates (\(model.modUpdates.count))"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .buttonStyle(
                            NeoButtonStyle(
                                kind: model.modUpdates.isEmpty ? .secondary : .primary,
                                tint: NeoPalette.amber,
                                compact: true
                            )
                        )
                        .disabled(model.isCheckingUpdates || model.selectedInstance == nil)
                        .help("Compare installed Modrinth projects with their latest versions")

                        Button {
                            model.searchMods(reset: true)
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    }
                }

                controls
                contextBanner

                if !model.modUpdates.isEmpty {
                    updatesCard
                }

                if let error = model.modSearchError, model.modResults.isEmpty {
                    EmptyStateView(
                        symbol: "exclamationmark.triangle",
                        title: "Modrinth couldn't be reached",
                        message: error,
                        actionTitle: "Try Again",
                        action: { model.searchMods(reset: true) }
                    )
                    .neoCard(padding: 10, cornerRadius: 22)
                } else if model.modResults.isEmpty {
                    if model.isSearchingMods {
                        LoadingStateView(message: "Searching Modrinth…")
                            .neoCard(padding: 10, cornerRadius: 22)
                    } else {
                        EmptyStateView(
                            symbol: "shippingbox",
                            title: "Nothing found",
                            message: model.modQuery.isEmpty
                                ? "No \(model.modType.title.lowercased()) are available for \(contextVersion)."
                                : "No results for \"\(model.modQuery)\". Try a shorter search or another content type.",
                            actionTitle: model.modQuery.isEmpty ? nil : "Clear Search",
                            action: model.modQuery.isEmpty ? nil : { model.modQuery = ""; model.searchMods(reset: true) }
                        )
                        .neoCard(padding: 10, cornerRadius: 22)
                    }
                } else {
                    VStack(spacing: 9) {
                        ForEach(model.modResults) { hit in
                            ModProjectRow(hit: hit)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Showing \(model.modResults.count) of \(model.modTotal) projects")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if model.modResults.count < model.modTotal {
                            Button {
                                model.loadMoreMods()
                            } label: {
                                Label("Load More", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                            .disabled(model.isSearchingMods)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(28)
            .frame(maxWidth: 1400, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if model.modResults.isEmpty && !model.isSearchingMods {
                model.searchMods(reset: true)
            }
        }
    }

    private var contextVersion: String {
        model.selectedInstance?.minecraftVersion ?? "your selected version"
    }

    private var selectedIsBedrock: Bool {
        model.selectedInstance?.edition == .bedrock
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Content Type", selection: typeBinding) {
                ForEach(types) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)

            NeoSearchField(placeholder: "Search \(model.modType.title.lowercased())", text: queryBinding)
                .frame(maxWidth: 340)

            Spacer(minLength: 8)

            Picker("Sort", selection: sortBinding) {
                ForEach(ModrinthSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(11)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
    }

    private var updatesCard: some View {
        NeoCard(padding: 15) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 10) {
                    SectionHeader(
                        title: "Updates Available",
                        subtitle: "\(model.modUpdates.count) installed project\(model.modUpdates.count == 1 ? "" : "s") \(model.modUpdates.count == 1 ? "has" : "have") a newer Modrinth version",
                        symbol: "arrow.triangle.2.circlepath",
                        tint: NeoPalette.amber
                    )
                    Spacer(minLength: 8)
                    if model.installingProjectID == nil {
                        Button {
                            model.updateAllMods()
                        } label: {
                            Label("Update All", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .primary, tint: NeoPalette.amber, compact: true))
                    }
                }

                VStack(spacing: 9) {
                    ForEach(model.modUpdates) { update in
                        HStack(spacing: 10) {
                            Image(systemName: update.type.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NeoPalette.accent)
                                .frame(width: 26, height: 26)
                                .background(NeoPalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(update.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Text("→ \(update.latest.versionNumber) for Minecraft \(model.selectedInstance?.minecraftVersion ?? "")")
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 6)

                            Button {
                                model.updateProject(update)
                            } label: {
                                Label("Update", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(NeoButtonStyle(kind: .primary, tint: NeoPalette.amber, compact: true))
                            .disabled(model.installingProjectID != nil)
                        }
                    }
                }
            }
        }
    }

    private var contextBanner: some View {
        HStack(spacing: 11) {
            if let instance = model.selectedInstance {
                BlockIconTile(block: instance.iconBlock, color: Color(hex: instance.colorHex), symbol: instance.iconSymbol, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Installing into \(instance.name)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("\(instance.versionLabel) · \(model.installedProjectIDs.count) installed from Modrinth")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                if instance.edition == .bedrock {
                    NeoPill(text: "No mods on Bedrock", symbol: "gamecontroller.fill", tint: Color.secondary)
                } else if instance.loader != .fabric {
                    NeoPill(text: "Fabric recommended", symbol: "exclamationmark.triangle.fill", tint: NeoPalette.amber)
                }
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NeoPalette.amber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("No instance selected")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    Text("Create or select an instance before installing content.")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            Button {
                model.go(to: .instances)
            } label: {
                Label("Manage Instances", systemImage: "square.stack.3d.up")
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        }
    }

    private var typeBinding: Binding<ModrinthProjectType> {
        Binding(
            get: { model.modType },
            set: { type in
                model.modType = type
                model.searchMods(reset: true)
            }
        )
    }

    private var queryBinding: Binding<String> {
        Binding(
            get: { model.modQuery },
            set: { query in
                model.modQuery = query
                model.scheduleModSearch()
            }
        )
    }

    private var sortBinding: Binding<ModrinthSort> {
        Binding(
            get: { model.modSort },
            set: { sort in
                model.modSort = sort
                model.searchMods(reset: true)
            }
        )
    }
}

// MARK: - Row

private struct ModProjectRow: View {
    @Environment(AppModel.self) private var model
    let hit: ModrinthSearchHit

    private var installed: Bool { model.installedProjectIDs.contains(hit.projectID) }
    private var installing: Bool { model.installingProjectID == hit.projectID }
    private var categories: [String] {
        let list = hit.displayCategories ?? hit.categories
        return Array(list.prefix(3))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            RemoteImage(url: hit.icon, size: 60, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(hit.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if installed {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NeoPalette.mint)
                            .help("Installed in this instance")
                    }
                    Spacer(minLength: 4)
                }

                Text(hit.description)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    NeoPill(text: hit.type.singular, symbol: hit.type.symbol, tint: NeoPalette.accent)
                    ForEach(categories, id: \.self) { category in
                        NeoPill(text: category.capitalized, tint: NeoPalette.violet)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 9, weight: .semibold))
                        Text(Formatters.downloadCount(hit.downloads))
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.secondary)
                    if let author = hit.author, !author.isEmpty {
                        Text("by \(author)")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            action
                .padding(.top, 1)
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .onTapGesture {
            model.openProject(hit)
        }
        .help("Open \(hit.title)")
    }

    @ViewBuilder
    private var action: some View {
        if installing {
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: model.installFraction ?? 0)
                    .progressViewStyle(.linear)
                    .tint(NeoPalette.accent)
                    .frame(width: 84)
                Text(model.installDetail.isEmpty ? "Installing…" : model.installDetail)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 108, alignment: .trailing)
            }
        } else if model.selectedInstance?.edition == .bedrock {
            NeoPill(text: "Bedrock", symbol: "gamecontroller.fill", tint: Color.secondary)
        } else if let update = model.modUpdateByProjectID[hit.projectID] {
            Button {
                model.updateProject(update)
            } label: {
                Label("Update", systemImage: "arrow.down.circle")
            }
            .buttonStyle(NeoButtonStyle(kind: .primary, tint: NeoPalette.amber, compact: true))
            .disabled(model.installingProjectID != nil || model.selectedInstance == nil)
        } else if installed {
            NeoPill(text: "Installed", symbol: "checkmark", tint: NeoPalette.mint)
        } else {
            Button {
                model.install(hit)
            } label: {
                Label("Install", systemImage: "arrow.down.circle")
            }
            .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
            .disabled(model.installingProjectID != nil || model.selectedInstance == nil)
        }
    }
}
