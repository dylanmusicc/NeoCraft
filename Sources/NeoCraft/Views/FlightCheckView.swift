import SwiftUI

/// Diagnostic sheet for the pre-launch Flight Check scanner. Lists every
/// conflict / warning found in the instance's `mods/` folder with
/// one-click fixes (Modrinth dependency install or mod disable).
struct FlightCheckView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance

    private var result: FlightCheckResult? {
        model.flightCheckResults[instance.id]
    }

    private var isRunning: Bool {
        model.flightCheckRunning.contains(instance.id)
    }

    private var statusColor: Color {
        Color(hex: result?.pillColorHex ?? "9AA4B2")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            NeoDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard

                    if isRunning && result == nil {
                        LoadingStateView(message: "Scanning \(instance.name)'s mods…")
                    } else if let result, result.issues.isEmpty {
                        EmptyStateView(
                            symbol: "checkmark.shield.fill",
                            title: result.scannedCount == 0 ? "No mods installed" : "All clear",
                            message: result.scannedCount == 0
                                ? "Drop JARs into \(instance.name)/mods and run Flight Check again."
                                : "\(result.scannedCount) mod JARs passed every check — safe to launch."
                        )
                    } else if let result {
                        ForEach(result.issues) { issue in
                            issueRow(issue)
                        }
                    }
                }
                .padding(22)
            }
            .scrollIndicators(.hidden)

            NeoDivider()
            footer
        }
        .frame(width: 640, height: 620)
        .background(.regularMaterial)
        .onAppear {
            if result == nil { model.runFlightCheck(for: instance) }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [statusColor, statusColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "airplane")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Flight Check")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("\(instance.name) · pre-launch mod validation")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.runFlightCheck(for: instance)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
            .help("Rescan mods")

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

    // MARK: - Summary

    private var summaryCard: some View {
        NeoCard {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.18))
                        .frame(width: 46, height: 46)
                    Image(systemName: statusSymbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(statusColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(result?.pillTitle ?? "Scanning…")
                        .font(.neoHeadline)
                    Text(summaryDetail)
                        .font(.neoCaption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let result {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(result.scannedCount)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("JARs")
                            .font(.neoCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var statusSymbol: String {
        switch result?.status {
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .conflict: "xmark.octagon.fill"
        case .empty, nil: "tray"
        }
    }

    private var summaryDetail: String {
        guard let result else { return "Reading every JAR in mods/…" }
        switch result.status {
        case .passed:
            return "Checked \(result.checkedAt.formatted(date: .omitted, time: .shortened))"
        case .warning:
            return "\(result.warningCount) warning\(result.warningCount == 1 ? "" : "s") — review below before playing"
        case .conflict:
            return "\(result.errorCount) conflict\(result.errorCount == 1 ? "" : "s") will likely crash or break the game"
        case .empty:
            return "Install mods from the Mod Library, then rescan"
        }
    }

    // MARK: - Issue rows

    private func issueRow(_ issue: FlightIssue) -> some View {
        NeoCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(issue.severity == .error ? NeoPalette.danger : NeoPalette.amber)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(issue.title)
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        if let fileName = issue.fileName {
                            Text(fileName)
                                .font(.neoCaption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer()

                    NeoBadge(
                        text: issue.kind.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression),
                        color: issue.severity == .error ? NeoPalette.danger : NeoPalette.amber
                    )
                }

                Text(issue.detail)
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .none = issue.fix {
                    EmptyView()
                } else {
                    HStack(spacing: 8) {
                        Spacer()
                        fixButton(for: issue)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fixButton(for issue: FlightIssue) -> some View {
        switch issue.fix {
        case .installDependency(let slug):
            Button {
                model.applyFlightFix(issue, for: instance)
            } label: {
                Label("Install \(slug) via Modrinth", systemImage: "arrow.down.circle")
            }
            .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
            .disabled(model.flightFixInstalling.contains(instance.id) || model.installingProjectID != nil)
        case .disableMod(let fileName):
            Button {
                model.applyFlightFix(issue, for: instance)
            } label: {
                Label("Disable \(fileName)", systemImage: "eye.slash")
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
        case .none:
            EmptyView()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.reveal(instance.gameDirectory.appendingPathComponent("mods", isDirectory: true))
            } label: {
                Label("Open mods/", systemImage: "folder")
            }
            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))

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
