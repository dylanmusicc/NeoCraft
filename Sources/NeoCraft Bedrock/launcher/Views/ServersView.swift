import SwiftUI

/// NeoCraft's servers, mirrored: every Java instance's `servers.dat`, read
/// live from NeoCraft's own files. Bedrock doesn't keep a server list — the
/// games do — so this page shows what NeoCraft manages and points there for
/// edits.
struct ServersView: View {
    @PlainState private var instances: [NeoCraftFiles.JavaInstance] = []
    @PlainState private var servers: [UUID: [NeoCraftFiles.ServerEntry]] = [:]
    @PlainState private var filter = ""

    var body: some View {
        PageScroll {
            PageHeader(
                title: String(localized: "Servers"),
                subtitle: String(localized: "The server lists of your NeoCraft instances")
            ) {
                NeoCraftSearchField(placeholder: String(localized: "Filter by name, address or instance"), text: $filter)
                    .frame(width: 260)
            }
        } content: {
            if instances.isEmpty {
                emptyPanel
            } else {
                ForEach(instances) { instance in
                    let entries = filtered(instance)
                    if !entries.isEmpty {
                        section(instance: instance, entries: entries)
                    }
                }
                if instances.allSatisfy({ filtered($0).isEmpty }) {
                    emptyPanel
                }
            }
        }
        .onAppear(perform: reload)
    }

    private var emptyPanel: some View {
        panel {
            VStack(spacing: 10) {
                TitleText("No servers yet", size: 16)
                Text("Servers are added per instance in NeoCraft — they show up here.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    private func section(instance: NeoCraftFiles.JavaInstance,
        entries: [NeoCraftFiles.ServerEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                TitleText(verbatim: instance.name, size: 14)
                Text("\(entries.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                Text(instance.minecraftVersion)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText)
            }
            ForEach(entries) { server in
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 22, height: 22)
                        .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: server.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.text)
                        Text(verbatim: server.address)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .panelBackground()
            }
        }
    }

    private func filtered(_ instance: NeoCraftFiles.JavaInstance) -> [NeoCraftFiles.ServerEntry] {
        let entries = servers[instance.id] ?? []
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.name.lowercased().contains(needle)
                || $0.address.lowercased().contains(needle)
                || instance.name.lowercased().contains(needle)
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().panel()
    }

    private func reload() {
        let found = NeoCraftFiles.javaInstances()
        instances = found
        servers = Dictionary(uniqueKeysWithValues: found.map { ($0.id, NeoCraftFiles.servers(of: $0)) })
    }
}

/// A small rounded search field in the launcher's style.
struct NeoCraftSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: NeoSync.shared.radius(10), style: .continuous)
                .fill(Palette.slot)
        }
        .overlay {
            RoundedRectangle(cornerRadius: NeoSync.shared.radius(10), style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
    }
}
