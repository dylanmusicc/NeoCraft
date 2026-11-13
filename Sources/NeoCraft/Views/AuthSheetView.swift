import SwiftUI

struct AuthSheetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            NeoDivider()

            ScrollView {
                VStack(spacing: 16) {
                    if model.isSigningIn {
                        signingInContent
                    } else if let error = model.authError {
                        errorContent(error)
                    } else {
                        readyContent
                    }
                }
                .padding(24)
            }
            .scrollIndicators(.hidden)

            NeoDivider()
            footer
        }
        .frame(width: 480, height: 590)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [NeoPalette.accent, NeoPalette.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .shadow(color: NeoPalette.accent.opacity(0.35), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sign in to Minecraft")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("Microsoft account · device code")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                cancel()
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

    // MARK: - Content

    private var signingInContent: some View {
        VStack(spacing: 15) {
            if let code = model.deviceCode {
                VStack(spacing: 10) {
                    Text("Enter this code at microsoft.com/devicelogin")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text(code.userCode)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(NeoPalette.accent)
                        .textSelection(.enabled)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            NeoPalette.accent.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(NeoPalette.accent.opacity(0.22), lineWidth: 0.8)
                        }

                    HStack(spacing: 8) {
                        Button {
                            model.copyToClipboard(code.userCode, label: "Code copied")
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))

                        Button {
                            model.openURL(code.verificationURI)
                        } label: {
                            Label("Open Browser", systemImage: "safari")
                        }
                        .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                    }
                }

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.authStatus.isEmpty ? "Waiting for Microsoft…" : model.authStatus)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("This code expires in \(max(1, code.expiresIn / 60)) minutes. NeoCraft never sees your password — Microsoft handles the sign-in.")
                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text(model.authStatus.isEmpty ? "Contacting Microsoft…" : model.authStatus)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }

    private func errorContent(_ error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(NeoPalette.amber)
                .frame(width: 62, height: 62)
                .background(NeoPalette.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Sign-in didn't finish")
                .font(.system(size: 16, weight: .semibold, design: .rounded))

            Text(error)
                .font(.system(size: 11.5, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            Button {
                model.beginSignIn()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(NeoButtonStyle(kind: .primary))
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private var readyContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(NeoPalette.accent)
                .frame(width: 62, height: 62)
                .background(NeoPalette.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Connect a Microsoft account")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("NeoCraft uses Microsoft's device-code flow to authorize Minecraft: Java Edition. Tokens are stored securely in your macOS Keychain.")
                .font(.system(size: 11.5, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                model.beginSignIn()
            } label: {
                Label("Sign In with Microsoft", systemImage: "person.badge.key")
            }
            .buttonStyle(NeoButtonStyle(kind: .primary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(NeoPalette.mint)
                Text("Keychain protected")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel") {
                cancel()
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func cancel() {
        model.cancelSignIn()
        dismiss()
    }
}
