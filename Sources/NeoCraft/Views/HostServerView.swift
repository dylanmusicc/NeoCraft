import SwiftUI

/// Setup sheet for turning a single-player world into a Java dedicated
/// server. Creating the entry downloads Mojang's server jar and copies the
/// world — the actual server only starts from the Servers tab.
struct HostWorldSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    let world: WorldInfo

    @State private var name = ""
    @State private var portText = "25565"
    @State private var onlineMode = true
    @State private var agreedEULA = false

    private var port: Int? {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), (1...65535).contains(value) else { return nil }
        return value
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && port != nil
            && agreedEULA
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Host World as Server")
                .font(.neoTitle)
            Text("Runs \"\(world.levelName ?? world.name)\" from \(instance.name) (\(instance.minecraftVersion)) as a Minecraft Java dedicated server.")
                .font(.neoCaption)
                .foregroundStyle(.secondary)

            if instance.loader == .fabric {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NeoPalette.amber)
                    Text("This is a Fabric instance — the dedicated server runs vanilla Minecraft, so installed mods won't be active. Modded blocks may not survive.")
                        .font(.neoCaption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Server name").font(.neoCaption).foregroundStyle(.secondary)
                TextField("e.g. Dylan's Realm", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Port").font(.neoCaption).foregroundStyle(.secondary)
                TextField("25565", text: $portText)
                    .textFieldStyle(.roundedBorder)
                Text("Friends connect with your Mac's local IP and this port. macOS may ask to allow incoming connections.")
                    .font(.neoCaption).foregroundStyle(.secondary)
            }

            Toggle(isOn: $onlineMode) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Online mode").font(.system(size: 12, weight: .medium, design: .rounded))
                    Text("Verify players with their Minecraft account. Turn off only for offline accounts.")
                        .font(.neoCaption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(NeoToggleStyle())

            Toggle(isOn: $agreedEULA) {
                Text("I agree to the Minecraft EULA")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .toggleStyle(NeoToggleStyle())

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                Button("Create & Download") { create() }
                    .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                    .disabled(!canCreate)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            name = world.levelName ?? world.name
        }
    }

    private func create() {
        guard let port else { return }
        model.hostWorld(world, in: instance, name: name, port: port, onlineMode: onlineMode)
        dismiss()
    }
}
