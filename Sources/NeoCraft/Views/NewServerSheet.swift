import SwiftUI

/// Creation sheet for the Servers tab: a fresh Java dedicated server
/// (vanilla/Paper/Fabric, optional world copy from a Java instance) or a
/// Bedrock Dedicated Server (Windows BDS through the bundled NeoCraft
/// Bedrock component's Wine helper).
struct NewHostedServerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var edition: ServerEdition = .java
    @State private var name = ""
    @State private var portText = "25565"
    @State private var onlineMode = true
    @State private var agreedEULA = false

    // Java
    @State private var javaVersions: [MinecraftVersionSummary] = []
    @State private var javaVersion = ""
    @State private var serverType: ServerType = .vanilla
    @State private var sourceInstanceID: UUID?
    @State private var sourceWorldName = ""

    // Bedrock
    @State private var bedrockVersion = "latest"
    @State private var levelName = "world"

    // Shared
    @State private var preset: ServerPreset = .custom
    @State private var group = ""

    private var javaInstances: [GameInstance] {
        model.instances.filter { $0.edition == .java }
    }

    private var sourceInstance: GameInstance? {
        javaInstances.first { $0.id == sourceInstanceID } ?? javaInstances.first
    }

    private var sourceWorlds: [WorldInfo] {
        guard let sourceInstance else { return [] }
        return WorldBackupService.worlds(in: sourceInstance)
    }

    private var port: Int? {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), (1...65535).contains(value) else { return nil }
        return value
    }

    private var canCreate: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              port != nil, agreedEULA else { return false }
        if edition == .java {
            return !javaVersion.isEmpty
        }
        return model.settings.betaFeatures.bedrockServers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Server")
                .font(.neoTitle)

            Picker("Edition", selection: $edition) {
                Text("Java Edition").tag(ServerEdition.java)
                Text("Bedrock Edition").tag(ServerEdition.bedrock)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!model.settings.betaFeatures.bedrockServers)

            if edition == .bedrock, !model.settings.betaFeatures.bedrockServers {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NeoPalette.amber)
                    Text("Bedrock servers are a beta feature — enable Bedrock server hosting in Settings → Beta Features.")
                        .font(.neoCaption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Server name").font(.neoCaption).foregroundStyle(.secondary)
                TextField("e.g. Dylan's Realm", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            if edition == .java {
                javaFields
            } else {
                bedrockFields
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preset").font(.neoCaption).foregroundStyle(.secondary)
                Picker("Preset", selection: $preset) {
                    ForEach(ServerPreset.allCases) { option in
                        Label(option.title, systemImage: option.symbol).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(preset.detail)
                    .font(.neoCaption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Group (optional)").font(.neoCaption).foregroundStyle(.secondary)
                TextField("e.g. Survival, Minigames, Bedrock", text: $group)
                    .textFieldStyle(.roundedBorder)
                Text("Servers with the same group name are sectioned together in the Servers tab.")
                    .font(.neoCaption).foregroundStyle(.secondary)
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
                    Text(edition == .bedrock
                         ? "Verify players with their Xbox Live account. Turn off only for offline/LAN play."
                         : "Verify players with their Minecraft account. Turn off only for offline accounts.")
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
                Button(edition == .bedrock ? "Download & Create" : "Create & Download") { create() }
                    .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                    .disabled(!canCreate)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            javaVersions = (try? await model.versions.recentVersions(includeSnapshots: false, limit: 40)) ?? []
            if javaVersion.isEmpty {
                javaVersion = javaVersions.first(where: { $0.isRelease })?.id
                    ?? javaVersions.first?.id ?? ""
            }
        }
        .onChange(of: sourceInstanceID) { _, _ in sourceWorldName = "" }
    }

    // MARK: - Java fields

    @ViewBuilder
    private var javaFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Minecraft version").font(.neoCaption).foregroundStyle(.secondary)
            Picker("Version", selection: $javaVersion) {
                ForEach(javaVersions) { version in
                    Text(version.id).tag(version.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if javaVersions.isEmpty {
                Text("Loading versions…")
                    .font(.neoCaption).foregroundStyle(.secondary)
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Server software").font(.neoCaption).foregroundStyle(.secondary)
            Picker("Software", selection: $serverType) {
                ForEach(ServerType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            Text(serverType.subtitle)
                .font(.neoCaption).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("World").font(.neoCaption).foregroundStyle(.secondary)
            Picker("World source", selection: $sourceWorldName) {
                Text("New world (generated on first start)").tag("")
                ForEach(sourceWorlds) { world in
                    Text(world.levelName ?? world.name).tag(world.name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if !javaInstances.isEmpty {
                Picker("Instance", selection: instanceBinding) {
                    ForEach(javaInstances) { candidate in
                        Text(candidate.name).tag(Optional(candidate.id))
                    }
                }
                .labelsHidden()
                .font(.neoCaption)
            } else {
                Text("No Java instances yet — the server will start with a fresh world.")
                    .font(.neoCaption).foregroundStyle(.secondary)
            }
        }
    }

    private var instanceBinding: Binding<UUID?> {
        Binding(
            get: { sourceInstance?.id },
            set: { sourceInstanceID = $0 }
        )
    }

    // MARK: - Bedrock fields

    @ViewBuilder
    private var bedrockFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bedrock version").font(.neoCaption).foregroundStyle(.secondary)
            Picker("Version", selection: $bedrockVersion) {
                Text("Latest").tag("latest")
                ForEach(BedrockServerDownload.knownVersions, id: \.self) { version in
                    Text(version).tag(version)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text("Runs Mojang's Windows Bedrock Dedicated Server through Wine — the first start downloads the server (~100 MB) and prepares the runtime.")
                .font(.neoCaption).foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("World name").font(.neoCaption).foregroundStyle(.secondary)
            TextField("world", text: $levelName)
                .textFieldStyle(.roundedBorder)
            Text("The level folder inside the server's worlds/ directory.")
                .font(.neoCaption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Create

    private func create() {
        guard let port else { return }
        if edition == .java {
            model.createJavaServer(
                name: name,
                minecraftVersion: javaVersion,
                serverType: serverType,
                port: port,
                onlineMode: onlineMode,
                instance: sourceWorldName.isEmpty ? nil : sourceInstance,
                worldName: sourceWorldName,
                group: group,
                preset: preset
            )
        } else {
            model.createBedrockServer(
                name: name,
                bedrockVersion: bedrockVersion,
                port: port,
                onlineMode: onlineMode,
                levelName: levelName,
                group: group,
                preset: preset
            )
        }
        dismiss()
    }
}
