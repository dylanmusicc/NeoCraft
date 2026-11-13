import SwiftUI

/// The Dashboard page: every hosted dedicated server in a compact list on
/// the left, the full `ServerDashboardView` for the selected server on the
/// right. Replaces the old dashboard sheet — servers are now a first-class
/// sidebar destination.
struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: L10n.t("nav.dashboard.title"),
                subtitle: L10n.t("nav.dashboard.subtitle")
            )
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 14)

            if model.hostedServers.isEmpty {
                EmptyStateView(
                    symbol: "server.rack",
                    title: "No hosted servers yet",
                    message: "Open an instance's Worlds tab and press Host on a world to run it as a Java dedicated server on this Mac.",
                    actionTitle: "Go to Instances",
                    action: { model.go(to: .instances) }
                )
                .padding(.horizontal, 28)
            } else {
                HStack(spacing: 0) {
                    serverList
                        .frame(width: 280)
                    Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.refreshHostedServers()
        }
    }

    // MARK: - Server list column

    private var serverList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.hostedServers) { server in
                    serverRow(server)
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
    }

    private func serverRow(_ server: HostedServer) -> some View {
        let running = model.isServerRunning(server)
        let ready = model.isServerReady(server)
        let settingUp = model.isSettingUpServer(server)
        let selected = model.dashboardServer?.id == server.id

        return HStack(spacing: 10) {
            StatusDot(color: statusColor(running: running, ready: ready, settingUp: settingUp), size: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
                Text(statusText(running: running, ready: ready, settingUp: settingUp))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if running {
                Button {
                    model.stopHostedServer(server)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NeoPalette.danger)
                .help("Stop server")
            } else {
                Button {
                    model.startHostedServer(server)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NeoPalette.mint)
                .disabled(settingUp)
                .help("Start server")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground(selected: selected))
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            model.dashboardServer = server
        }
        .help(AppModel.serverAddress(server))
    }

    private func rowBackground(selected: Bool) -> AnyShapeStyle {
        if selected {
            return AnyShapeStyle(NeoPalette.accent.opacity(0.16))
        }
        return AnyShapeStyle(Color.primary.opacity(0.04))
    }

    private func statusColor(running: Bool, ready: Bool, settingUp: Bool) -> Color {
        if settingUp { return NeoPalette.amber }
        if running { return ready ? NeoPalette.mint : NeoPalette.sky }
        return Color.secondary
    }

    private func statusText(running: Bool, ready: Bool, settingUp: Bool) -> String {
        if settingUp { return "Setting up" }
        if running { return ready ? "Online" : "Starting" }
        return "Stopped"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let server = model.dashboardServer,
           model.hostedServers.contains(where: { $0.id == server.id }) {
            ServerDashboardView(server: server)
        } else {
            EmptyStateView(
                symbol: "gauge.with.dots.needle.33percent",
                title: "Select a server",
                message: "Pick a hosted server on the left to open its console, players, files and settings."
            )
        }
    }
}
