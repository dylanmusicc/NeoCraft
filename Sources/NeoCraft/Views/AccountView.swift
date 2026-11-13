import SwiftUI

// MARK: - Account tab (Microsoft + offline account manager)

/// Clean account manager: active-account hero, Microsoft account list,
/// offline account list, and the two add-account entry points.
struct AccountView: View {
    @Environment(AppModel.self) private var model

    /// Per-account session check results for Microsoft accounts.
    @State private var sessionStates: [String: SessionState] = [:]
    @State private var accountPendingRemoval: MinecraftAccount?

    private enum SessionState: Equatable {
        case checking
        case valid(until: Date?)
        case needsSignIn
    }

    private var microsoftAccounts: [MinecraftAccount] {
        model.accounts.filter { !$0.isOffline }
    }

    private var offlineAccounts: [MinecraftAccount] {
        model.accounts.filter(\.isOffline)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: L10n.t("nav.account.title"),
                    subtitle: L10n.t("page.account.subtitle")
                ) {
                    HStack(spacing: 8) {
                        Button {
                            model.showOfflineAccountSheet = true
                        } label: {
                            Label("Add Offline Account", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))

                        Button {
                            model.beginSignIn()
                        } label: {
                            Label("Add Microsoft Account", systemImage: "person.badge.key")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                    }
                }

                if let active = model.activeAccount {
                    heroCard(active)
                } else {
                    NeoCard {
                        EmptyStateView(
                            symbol: "person.crop.circle.badge.questionmark",
                            title: "No account selected",
                            message: "Add a Microsoft or offline account to start playing.",
                            actionTitle: "Add Microsoft Account",
                            action: { model.beginSignIn() }
                        )
                    }
                }

                microsoftSection
                offlineSection
            }
            .padding(28)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .task { refreshSessionStates() }
        .alert(
            "Remove account?",
            isPresented: Binding(
                get: { accountPendingRemoval != nil },
                set: { if !$0 { accountPendingRemoval = nil } }
            ),
            presenting: accountPendingRemoval
        ) { account in
            Button("Remove", role: .destructive) {
                model.removeAccount(account)
                accountPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                accountPendingRemoval = nil
            }
        } message: { account in
            Text("\(account.name) will be removed from NeoCraft. Saved worlds and instances are not affected.")
        }
    }

    // MARK: - Hero

    private func heroCard(_ account: MinecraftAccount) -> some View {
        NeoCard {
            HStack(spacing: 16) {
                MCHeadAvatar(uuid: account.uuid, size: 64)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(account.name)
                            .font(.neoTitle)
                        NeoBadge(
                            text: account.isOffline ? "Offline account" : "Microsoft account",
                            color: account.isOffline ? NeoPalette.amber : NeoPalette.mint
                        )
                        if model.activeAccountID == account.uuid || model.activeAccount?.id == account.id {
                            NeoBadge(text: "Active", color: NeoPalette.accent)
                        }
                    }
                    Text(account.uuid)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack(spacing: 12) {
                        Label("Added \(account.addedAt.formatted(date: .abbreviated, time: .omitted))",
                              systemImage: "calendar")
                        if let lastUsed = account.lastUsed {
                            Label("Last used \(lastUsed.formatted(date: .abbreviated, time: .shortened))",
                                  systemImage: "clock")
                        }
                    }
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                    sessionStatus(for: account)
                }

                Spacer()

                VStack(spacing: 8) {
                    Button {
                        model.setActiveAccount(account)
                        model.go(to: .play)
                    } label: {
                        Label("Play as this account", systemImage: "play.fill")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))

                    Button {
                        refreshSession(for: account)
                    } label: {
                        Label("Refresh Session", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    .disabled(account.isOffline)

                    Button(role: .destructive) {
                        accountPendingRemoval = account
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                }
            }
        }
    }

    @ViewBuilder
    private func sessionStatus(for account: MinecraftAccount) -> some View {
        if account.isOffline {
            Label("Offline profile — no Microsoft session", systemImage: "bolt.horizontal.circle")
                .font(.neoCaption)
                .foregroundStyle(NeoPalette.amber)
        } else {
            switch sessionStates[account.uuid] {
            case .checking, .none:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                    Text("Checking session…")
                }
                .font(.neoCaption)
                .foregroundStyle(.secondary)
            case .valid(let until):
                Label(
                    until.map { "Session valid until \($0.formatted(date: .abbreviated, time: .shortened))" }
                        ?? "Session valid",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.neoCaption)
                .foregroundStyle(NeoPalette.mint)
            case .needsSignIn:
                Label("Session expired — sign in again", systemImage: "exclamationmark.triangle.fill")
                    .font(.neoCaption)
                    .foregroundStyle(NeoPalette.danger)
            }
        }
    }

    // MARK: - Sections

    private var microsoftSection: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Microsoft Accounts",
                    subtitle: "Signed in through Xbox Live / Microsoft",
                    symbol: "person.badge.key.fill"
                )

                if microsoftAccounts.isEmpty {
                    Text("No Microsoft accounts yet.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(microsoftAccounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }
        }
    }

    private var offlineSection: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "Offline Accounts",
                    subtitle: "Local profiles that play without Xbox Live",
                    symbol: "bolt.horizontal.circle.fill",
                    tint: NeoPalette.amber
                )

                if offlineAccounts.isEmpty {
                    Text("No offline accounts yet.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(offlineAccounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }
        }
    }

    private func accountRow(_ account: MinecraftAccount) -> some View {
        let isActive = model.activeAccount?.id == account.id
        return HStack(spacing: 12) {
            MCHeadAvatar(uuid: account.uuid, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(account.name)
                        .font(.neoHeadline)
                        .lineLimit(1)
                    if isActive {
                        NeoBadge(text: "Active", color: NeoPalette.accent)
                    }
                }
                Text(account.uuid)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if !account.isOffline {
                sessionChip(for: account)
            }

            if !isActive {
                Button("Set Active") {
                    model.setActiveAccount(account)
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            }

            Button {
                refreshSession(for: account)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            .help(account.isOffline ? "Offline accounts have no session to refresh" : "Refresh session")
            .disabled(account.isOffline)

            Button(role: .destructive) {
                accountPendingRemoval = account
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            .help("Remove account")
        }
        .padding(12)
        .neoCard(padding: 12)
    }

    @ViewBuilder
    private func sessionChip(for account: MinecraftAccount) -> some View {
        switch sessionStates[account.uuid] {
        case .valid:
            NeoBadge(text: "Session OK", color: NeoPalette.mint)
        case .needsSignIn:
            NeoBadge(text: "Expired", color: NeoPalette.danger)
        case .checking, .none:
            NeoBadge(text: "Checking…", color: Color.secondary)
        }
    }

    // MARK: - Session checks

    /// Validates every Microsoft account's stored session in the
    /// background — `validSession` refreshes expired tokens automatically.
    private func refreshSessionStates() {
        for account in microsoftAccounts {
            sessionStates[account.uuid] = .checking
            Task {
                do {
                    let session = try await model.auth.validSession(for: account)
                    sessionStates[account.uuid] = .valid(until: session.expiresAt)
                } catch {
                    sessionStates[account.uuid] = .needsSignIn
                }
            }
        }
    }

    /// Re-validates one account (also refreshes an expired token) and
    /// updates its chip.
    private func refreshSession(for account: MinecraftAccount) {
        guard !account.isOffline else { return }
        sessionStates[account.uuid] = .checking
        Task {
            do {
                let session = try await model.auth.validSession(for: account)
                sessionStates[account.uuid] = .valid(until: session.expiresAt)
                model.showToast("Session refreshed for \(account.name)")
            } catch {
                sessionStates[account.uuid] = .needsSignIn
                model.presentError("Session expired", error)
            }
        }
    }
}

// MARK: - mc-heads avatar

/// Square avatar loaded from mc-heads.net — works for both Microsoft and
/// offline UUIDs (offline UUIDs render a deterministic default skin).
/// Falls back to a person glyph while loading or on failure.
private struct MCHeadAvatar: View {
    let uuid: String
    var size: CGFloat = 36

    private var url: URL? {
        let clean = uuid.replacingOccurrences(of: "-", with: "").lowercased()
        return URL(string: "https://mc-heads.net/avatar/\(clean)/\(Int(size * 2))")
    }

    var body: some View {
        AsyncImage(url: url) { phase in
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
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
    }
}
