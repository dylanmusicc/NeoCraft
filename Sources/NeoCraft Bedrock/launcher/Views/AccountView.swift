import LauncherCore
import SwiftUI

/// The accounts the launcher can play with: pick the active one, sign in
/// again, add or remove — the same actions the account menu offers, as a page.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(Popups.self) private var popups

    var body: some View {
        PageScroll {
            PageHeader(
                title: String(localized: "Account"),
                subtitle: String(localized: "The Microsoft account Bedrock plays with")
            )
        } content: {
            let accounts = model.library.accounts.filter { !$0.isPending }
            if accounts.isEmpty {
                panel {
                    VStack(spacing: 10) {
                        TitleText("No account yet", size: 16)
                        Text("Add your Microsoft account to install and play Minecraft.")
                            .font(.neoUI(13.0, bold: false))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                ForEach(accounts) { account in
                    accountRow(account)
                }
            }

            HStack {
                Spacer()
                Button("Add Account…") { askToAdd() }
                    .buttonStyle(.pixel(.primary, minHeight: 30))
                    .disabled(!model.canAddAccount || model.isSigningIn)
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        let selected = account.id == model.library.selectedAccount
        let usable = model.mayUse(account) && model.selectedSession == nil
        let signedIn = selected ? model.readiness.signedIn == true : nil
        return panel {
            HStack(spacing: 14) {
                PixelImage(image: Artwork.head(for: account.id))
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    TitleText(verbatim: account.label, size: 15)
                    HStack(spacing: 8) {
                        if selected {
                            statusPill(
                                signedIn == true ? "Signed in" : "Sign-in needed",
                                colour: signedIn == true ? Palette.positive : Palette.warning)
                        }
                        if selected, model.selectedSession != nil {
                            statusPill("Playing", colour: Palette.accent)
                        }
                    }
                }
                Spacer()
                if !selected {
                    Button("Use") { model.selectAccount(account.id) }
                        .buttonStyle(.pixel(.secondary, minHeight: 28))
                }
                Button("Sign In Again…") { model.signInAgain(account.id) }
                    .buttonStyle(.pixel(.secondary, minHeight: 28))
                    .disabled(!usable)
                Button("Remove…", role: .destructive) { confirmRemoval(of: account) }
                    .buttonStyle(.pixel(.secondary, minHeight: 28))
                    .disabled(!usable)
            }
        }
    }

    private func statusPill(_ title: LocalizedStringKey, colour: Color) -> some View {
        Text(title)
            .font(.neoUI(11.0, bold: true))
            .foregroundStyle(colour)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(colour.opacity(0.14), in: Capsule())
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().panel()
    }

    private func askToAdd() {
        popups.dialog = Dialog(
            title: String(localized: "Add a Microsoft account"),
            message: AccountMenu.beforeSigningIn,
            answers: [
                .init(title: String(localized: "Cancel"), role: .cancel),
                .init(title: String(localized: "Continue")) { model.addAccount() },
            ])
    }

    private func confirmRemoval(of account: Account) {
        popups.dialog = Dialog(
            title: String(localized: "Remove “\(account.label)”?"),
            message: String(
                localized:
                    "NeoCraft Bedrock signs the account out on this Mac and deletes its Windows prefix. Its worlds, packs and settings are kept in a backup first."
            ),
            answers: [
                .init(title: String(localized: "Cancel"), role: .cancel),
                .init(title: String(localized: "Remove"), role: .destructive) {
                    model.removeAccount(account.id)
                },
            ])
    }
}
