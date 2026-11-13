import SwiftUI

/// Neo Studio for the whole NeoCraft look: the same theme NeoCraft's Studio
/// edits, written through to its settings — so both launchers show the same
/// accent, wallpaper, materials and corners. `NeoSync` already reads NeoCraft's
/// defaults, so changes show here at once and in NeoCraft on its next sync.
struct StudioView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let accents: [(hex: String, name: LocalizedStringKey)] = [
        ("5B8CFF", "Apple Blue"), ("4ADE80", "Emerald Creeper"), ("A78BFA", "Amethyst Purple"),
        ("FBBF24", "Sunset Gold"), ("9AA4B2", "Graphite"),
    ]
    private let modes: [(raw: String, title: LocalizedStringKey)] = [
        ("frosted", "Frosted Glass"), ("oled", "Pure OLED Dark"),
        ("dynamic", "Time-of-Day Auto"), ("biome", "Biome-Synced"),
    ]
    private let wallpapers: [(raw: String, title: LocalizedStringKey)] = [
        ("aurora", "Aurora Bloom"), ("deepDarkPulse", "Deep Dark Pulse"),
        ("cherryPetals", "Cherry Petals"), ("endSky", "End Sky"),
        ("netherEmbers", "Nether Embers"), ("plain", "Flat Gradient"),
    ]
    private let corners: [(raw: String, title: LocalizedStringKey)] = [
        ("rounded", "Apple Rounded"), ("voxel", "Sharp Voxel"),
    ]
    private let radii: [(raw: String, title: LocalizedStringKey)] = [
        ("compact", "Compact"), ("regular", "Regular"), ("spacious", "Spacious"),
    ]

    var body: some View {
        PageScroll {
            PageHeader(
                title: String(localized: "Studio"),
                subtitle: String(localized: "The theme NeoCraft and NeoCraft Bedrock share")
            )
        } content: {
            accentPanel
            colourPanel
            wallpaperPanel
            materialPanel
        }
    }

    // MARK: Panels

    private var accentPanel: some View {
        StudioPanel(title: "Accent") {
            HStack(spacing: 10) {
                ForEach(accents, id: \.hex) { accent in
                    Button { apply(["accentHex": accent.hex]) } label: {
                        Circle()
                            .fill(NeoSync.color(accent.hex))
                            .frame(width: 30, height: 30)
                            .overlay {
                                Circle().strokeBorder(
                                    NeoSync.shared.effectiveAccentHex == accent.hex
                                        ? Palette.text : Color.primary.opacity(0.15),
                                    lineWidth: NeoSync.shared.effectiveAccentHex == accent.hex ? 2.5 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(accent.name)
                }
                Spacer()
                ThemeHexField(label: "Custom", value: NeoSync.shared.accentHex) { hex in
                    apply(["accentHex": hex])
                }
            }
        }
    }

    private var colourPanel: some View {
        StudioPanel(title: "Colours") {
            VStack(alignment: .leading, spacing: 14) {
                ThemeHexField(label: "Glow", value: NeoSync.shared.glowHex) { hex in
                    apply(["secondaryGlowHex": hex])
                }
                ThemeHexField(label: "Card Tint", value: NeoSync.shared.cardTintHex, placeholder: "none") { hex in
                    apply(["cardTintHex": hex])
                }
                ThemeHexField(label: "Gradient", value: NeoSync.shared.gradientHexes.joined(separator: ", "), placeholder: "accent, glow") { value in
                    apply(["gradientHexes": value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }])
                }
            }
        }
    }

    private var wallpaperPanel: some View {
        StudioPanel(title: "Wallpaper") {
            VStack(alignment: .leading, spacing: 14) {
                choiceRow(modes, current: NeoSync.shared.themeMode) { apply(["themeMode": $0]) }
                choiceRow(wallpapers, current: NeoSync.shared.wallpaperStyle) { apply(["wallpaperStyle": $0]) }
            }
        }
    }

    private var materialPanel: some View {
        StudioPanel(title: "Material") {
            VStack(alignment: .leading, spacing: 16) {
                choiceRow(corners, current: NeoSync.shared.cornerStyle) { apply(["cornerStyle": $0]) }
                choiceRow(radii, current: radiusKey) { apply(["cornerRadiusPreset": $0]) }
                sliderRow("Grid Intensity", value: NeoSync.shared.gridIntensity, range: 0.1...1.0) {
                    apply(["gridIntensity": $0])
                }
                sliderRow("Sidebar Material", value: NeoSync.shared.sidebarMaterial, range: 0...1) {
                    apply(["sidebarMaterial": $0])
                }
            }
        }
    }

    // MARK: Controls

    private var radiusKey: String {
        switch NeoSync.shared.cornerRadiusScale {
        case 0.72: "compact"
        case 1.38: "spacious"
        default: "regular"
        }
    }

    private func choiceRow(_ options: [(raw: String, title: LocalizedStringKey)], current: String,
        apply: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(options, id: \.raw) { option in
                Button { apply(option.raw) } label: {
                    HStack {
                        Image(systemName: current == option.raw ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(current == option.raw ? Palette.accent : Palette.secondaryText)
                        Text(option.title)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.text)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: NeoSync.shared.radius(10), style: .continuous)
                            .fill(current == option.raw ? Palette.accent.opacity(0.12) : Palette.slot)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sliderRow(_ label: String, value: Double, range: ClosedRange<Double>,
        apply: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText)
            }
            Slider(value: Binding(
                get: { value },
                set: { apply($0) }
            ), in: range)
            .tint(Palette.accent)
        }
    }

    private func apply(_ changes: [String: Any]) {
        NeoCraftFiles.applyTheme(changes)
        NeoSync.shared.reload()
    }
}

/// A titled card of Studio controls, like the launcher's other panels.
private struct StudioPanel<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TitleText(title, size: 14)
            content
        }
        .panel()
    }
}

/// A labelled hex colour field; applies a valid six-digit value on commit.
private struct ThemeHexField: View {
    let label: String
    let value: String
    var placeholder: String = "RRGGBB"
    let onApply: (String) -> Void

    @PlainState private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.secondaryText)
                .frame(width: 80, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: NeoSync.shared.radius(8), style: .continuous)
                        .fill(Palette.slot)
                }
                .frame(width: 150)
                .onSubmit(commit)
                .onAppear { text = value }
                .onChange(of: value) { _, new in
                    if new != text.uppercased().replacingOccurrences(of: "#", with: "") {
                        text = new
                    }
                }
        }
    }

    private func commit() {
        var hex = text.trimmingCharacters(in: .whitespaces).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, UInt32(hex, radix: 16) != nil else { return }
        onApply(hex)
    }
}
