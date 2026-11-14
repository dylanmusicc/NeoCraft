import SwiftUI

/// Server browser: join public featured servers or any address directly.
/// Java only — Bedrock speaks a different protocol. Joining writes the
/// server into the selected instance's `servers.dat` and launches with
/// `--quickPlayMultiplayer`, so every Minecraft version can connect; the
/// server decides compatibility.
struct JoinServerView: View {
    @Environment(AppModel.self) private var model

    @State private var joinAddress = ""
    @State private var featuredPings: [String: ServerStatus] = [:]
    @State private var joiningAddress: String?

    private static let featuredServers: [(name: String, address: String)] = [
        ("Hypixel", "mc.hypixel.net"),
        ("2b2t", "2b2t.org"),
        ("The Hive", "game.shivxr.net"),
        ("Mineplex", "us.mineplex.com"),
        ("SMPHub", "play.smp.net"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    title: "Join a Server",
                    subtitle: "Public servers and direct addresses — works with every Minecraft version."
                )

                NeoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "Direct Connect",
                            subtitle: "Enter any Java server address.",
                            symbol: "network"
                        )
                        HStack(spacing: 8) {
                            TextField("play.example.com", text: $joinAddress)
                                .textFieldStyle(.plain)
                                .font(.neoCaption.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                .onSubmit(joinTypedAddress)
                            Button { joinTypedAddress() } label: {
                                Label("Join", systemImage: "play.fill")
                            }
                            .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                            .disabled(joinAddress.trimmingCharacters(in: .whitespaces).isEmpty
                                      || model.selectedInstance?.edition != .java
                                      || model.isGameRunning)
                        }
                        if model.selectedInstance?.edition != .java {
                            Label("Select a Java instance to join servers — Bedrock speaks a different protocol.",
                                  systemImage: "info.circle")
                                .font(.neoCaption).foregroundStyle(.secondary)
                        }
                    }
                }

                NeoCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "Featured Servers",
                            subtitle: "Popular public Java servers with live player counts.",
                            symbol: "star.fill"
                        )
                        LazyVStack(spacing: 8) {
                            ForEach(Self.featuredServers, id: \.address) { entry in
                                featuredRow(entry)
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onAppear { pingFeaturedServers() }
    }

    private func featuredRow(_ entry: (name: String, address: String)) -> some View {
        let ping = featuredPings[entry.address]
        let joining = joiningAddress == entry.address
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NeoPalette.mint.opacity(0.14))
                Image(systemName: "network")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NeoPalette.mint)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.neoHeadline).lineLimit(1)
                Text(entry.address).font(.neoCaption.monospacedDigit())
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let ping, ping.reachable {
                Text("\(ping.playersOnline)/\(ping.playersMax)")
                    .font(.neoCaption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(NeoPalette.mint)
            } else if ping != nil {
                Text("Offline").font(.neoCaption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            Button(joining ? "Joining…" : "Join") {
                join(address: entry.address, name: entry.name)
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            .disabled(joining || model.selectedInstance?.edition != .java || model.isGameRunning)
            .help("Adds \(entry.name) to your server list and joins instantly")
        }
        .padding(10)
        .neoCard(padding: 10)
    }

    private func pingFeaturedServers() {
        for entry in Self.featuredServers where featuredPings[entry.address] == nil {
            Task {
                featuredPings[entry.address] = await ServerPinger.ping(entry.address)
            }
        }
    }

    private func joinTypedAddress() {
        let address = joinAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        join(address: address, name: address)
        joinAddress = ""
    }

    private func join(address: String, name: String) {
        guard let instance = model.selectedInstance, instance.edition == .java else { return }
        joiningAddress = address
        var entries = model.loadServers(for: instance)
        if !entries.contains(where: { $0.address == address }) {
            entries.append(MCServerEntry(name: name, address: address))
            try? model.saveServers(entries, for: instance)
        }
        model.joinServerEntry(MCServerEntry(name: name, address: address), in: instance)
        joiningAddress = nil
    }
}
