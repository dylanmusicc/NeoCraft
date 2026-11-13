import AppKit
import SwiftUI

/// Sheet for creating local offline profiles: a username, an optional custom
/// skin PNG, and a live preview of the deterministic offline UUID.
struct OfflineAccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var skinData: Data?
    @State private var skinName = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameIsValid: Bool {
        OfflineIdentity.isValidUsername(trimmedName)
    }

    private var previewUUID: String? {
        nameIsValid ? OfflineIdentity.uuid(for: trimmedName) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [NeoPalette.amber, NeoPalette.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("New Offline Account")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Plays without Xbox Live — great for LAN worlds and offline testing")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            NeoDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("Steve_01", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .onSubmit(create)
                HStack(spacing: 6) {
                    Image(systemName: nameIsValid ? "checkmark.circle.fill" : "info.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(nameIsValid ? NeoPalette.mint : Color.secondary)
                    Text(nameIsValid
                         ? "3–16 characters: letters, numbers and underscores"
                         : "Enter a valid Minecraft name to continue")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Skin (optional)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .frame(width: 44, height: 44)
                        if let skinData, let image = NSImage(data: skinData) {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(2)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        } else {
                            Image(systemName: "tshirt")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(skinName.isEmpty ? "Default Steve skin" : skinName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text("64×64 PNG · stored locally on this Mac")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if skinData != nil {
                        Button {
                            skinData = nil
                            skinName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Button(skinData == nil ? "Choose…" : "Replace…") {
                        chooseSkin()
                    }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                }
            }

            if let previewUUID {
                HStack(spacing: 8) {
                    Image(systemName: "number")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NeoPalette.violet)
                    Text("Offline UUID")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(previewUUID)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            NeoDivider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary))
                .keyboardShortcut(.cancelAction)

                Button("Create Account") {
                    create()
                }
                .buttonStyle(NeoButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!nameIsValid)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func create() {
        guard nameIsValid else { return }
        model.createOfflineAccount(name: trimmedName, skinPNG: skinData)
        if model.alert == nil {
            dismiss()
        }
    }

    private func chooseSkin() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a 64×64 Minecraft skin PNG"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        skinData = data
        skinName = url.deletingPathExtension().lastPathComponent
    }
}
