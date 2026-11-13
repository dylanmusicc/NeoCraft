import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Neo Studio customizer

/// Dedicated "Studio" section: launcher themes, sidebar/dashboard
/// modularity, audio, and the WYSIWYG in-game HUD editor.
struct StudioView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedWidgetID: UUID?
    @State private var studioSection: StudioSection = .hud

    private enum StudioSection: String, CaseIterable, Identifiable {
        case hud, themes, dashboard, audio
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hud: "In-Game HUD"
            case .themes: "Themes & Colors"
            case .dashboard: "Play Dashboard"
            case .audio: "Audio"
            }
        }
        var symbol: String {
            switch self {
            case .hud: "rectangle.on.rectangle"
            case .themes: "paintpalette.fill"
            case .dashboard: "rectangle.grid.2x2.fill"
            case .audio: "speaker.wave.2.fill"
            }
        }
    }

    /// Sections offered in the picker — the in-game HUD is a beta feature
    /// and only listed while enabled in Settings.
    private var visibleSections: [StudioSection] {
        StudioSection.allCases.filter {
            $0 != .hud || model.settings.betaFeatures.inGameHUD
        }
    }

    /// The section actually rendered; falls back when the stored selection
    /// is the hidden HUD section.
    private var effectiveSection: StudioSection {
        if studioSection == .hud && !model.settings.betaFeatures.inGameHUD {
            return visibleSections.first ?? .themes
        }
        return studioSection
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Neo Studio",
                    subtitle: L10n.t("page.studio.subtitle")
                )

                Picker("Studio section", selection: Binding(
                    get: { effectiveSection },
                    set: { studioSection = $0 }
                )) {
                    ForEach(visibleSections) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 560)

                switch effectiveSection {
                case .hud: hudSection
                case .themes: themesSection
                case .dashboard: dashboardSection
                case .audio: audioSection
                }
            }
            .padding(28)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            if selectedWidgetID == nil {
                selectedWidgetID = model.settings.hudLayout.widgets.first?.id
            }
            if studioSection == .hud && !model.settings.betaFeatures.inGameHUD {
                studioSection = .themes
            }
        }
    }

    // MARK: - Themes section (appearance + layout)

    private var themesSection: some View {
        VStack(spacing: 22) {
            appearanceSection
            layoutSection
        }
    }

    // MARK: - Play Dashboard section

    private var dashboardSection: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Play Dashboard",
                    subtitle: "Choose, order and style the cards on the Play screen",
                    symbol: "rectangle.grid.2x2.fill"
                )
                DashboardCustomizerView()
            }
        }
    }

    // MARK: - Audio section

    private var audioSection: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Interface Audio",
                    subtitle: "Tactile synthesized UI sounds — no audio assets",
                    symbol: "speaker.wave.2.fill"
                )

                Toggle(isOn: Binding(
                    get: { model.settings.uiSoundsEnabled },
                    set: { model.settings.uiSoundsEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UI sounds")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        Text("Clicks, launch blips, chimes and error alerts.")
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Volume")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        Slider(
                            value: Binding(
                                get: { model.settings.uiSoundVolume },
                                set: { model.settings.uiSoundVolume = $0 }
                            ),
                            in: 0...1
                        )
                        .tint(NeoPalette.accent)
                        .frame(maxWidth: 220)
                        .disabled(!model.settings.uiSoundsEnabled)
                    }
                    Text("\(Int(model.settings.uiSoundVolume * 100))%")
                        .font(.neoCaption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Spacer()
                }

                NeoDivider()

                HStack(spacing: 10) {
                    Text("Preview")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    soundButton("Click", .click)
                    soundButton("Chime", .chime)
                    soundButton("Error", .error)
                    soundButton("Launch", .launch)
                }
            }
        }
    }

    private func soundButton(_ title: String, _ sound: NeoSound) -> some View {
        Button(title) { SoundManager.shared.play(sound) }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
    }

    // MARK: HUD presets

    private enum HUDPreset { case minimal, pvp, survival, streamer }

    private func applyHUDPreset(_ preset: HUDPreset) {
        var layout = model.settings.hudLayout
        func w(_ kind: HUDWidgetKind, _ x: Double, _ y: Double, scale: Double = 1, visible: Bool = true) -> HUDWidget {
            HUDWidget(kind: kind, x: x, y: y, scale: scale, visible: visible)
        }
        switch preset {
        case .minimal:
            layout.widgets = [
                w(.fpsPill, 0.5, 0.03), w(.coordsCompass, 0.03, 0.5),
                w(.armorDurability, 0.03, 0.62), w(.keystrokes, 0.97, 0.9)
            ]
        case .pvp:
            layout.widgets = [
                w(.fpsPill, 0.5, 0.03), w(.pingTPS, 0.5, 0.09),
                w(.armorDurability, 0.03, 0.4), w(.keystrokes, 0.97, 0.9, scale: 0.85)
            ]
        case .survival:
            layout.widgets = [
                w(.fpsPill, 0.5, 0.03), w(.coordsCompass, 0.03, 0.5),
                w(.dayLight, 0.03, 0.62), w(.speedometer, 0.5, 0.94),
                w(.clocks, 0.97, 0.05), w(.minimap, 0.93, 0.12, scale: 0.8)
            ]
        case .streamer:
            layout.widgets = [
                w(.fpsPill, 0.5, 0.03), w(.coordsCompass, 0.5, 0.95),
                w(.clocks, 0.03, 0.05)
            ]
        }
        model.settings.hudLayout = layout
        model.showToast("HUD preset applied")
    }

    private func resetHUDLayout() {
        model.settings.hudLayout = HUDLayout(widgets: HUDWidget.defaults)
        selectedWidgetID = model.settings.hudLayout.widgets.first?.id
        model.showToast("HUD layout reset")
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Neo Appearance",
                    subtitle: "Curated themes, custom colors and materials",
                    symbol: "paintpalette.fill"
                )

                // Curated theme presets
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Curated Themes")
                            .font(.neoHeadline)
                        Spacer()
                        if !model.settings.curatedTheme.isEmpty {
                            NeoBadge(text: "Custom mix", color: NeoPalette.amber)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(NeoCuratedThemes.all) { theme in
                                curatedThemeCard(theme)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                NeoDivider()

                // Accent swatches + custom pickers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accent Colors")
                        .font(.neoHeadline)
                    HStack(spacing: 12) {
                        ForEach(NeoAccent.allCases) { accent in
                            accentSwatch(accent)
                        }
                        Spacer()
                    }
                    colorMixerRow(
                        title: "Primary Accent",
                        symbol: "paintpalette",
                        hex: model.settings.accentHex
                    ) { model.settings.accentHex = $0; model.settings.curatedTheme = "" }
                    colorMixerRow(
                        title: "Secondary Glow",
                        symbol: "circle.hexagongrid",
                        hex: model.settings.secondaryGlowHex
                    ) { model.settings.secondaryGlowHex = $0; model.settings.curatedTheme = "" }
                    colorMixerRow(
                        title: "Card Surface Tint",
                        symbol: "square.stack.3d.up",
                        hex: model.settings.cardTintHex,
                        allowEmpty: true
                    ) { model.settings.cardTintHex = $0; model.settings.curatedTheme = "" }
                }

                NeoDivider()

                // Theme mode picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme Mode")
                        .font(.neoHeadline)
                    HStack(spacing: 10) {
                        ForEach(NeoThemeMode.allCases) { mode in
                            themeModeCard(mode)
                        }
                    }
                }

                NeoDivider()

                // Materials
                VStack(alignment: .leading, spacing: 8) {
                    Text("Materials & Shape")
                        .font(.neoHeadline)
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Sidebar translucency", systemImage: "sidebar.left")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            Slider(value: Binding(
                                get: { model.settings.sidebarMaterial },
                                set: { model.settings.sidebarMaterial = $0 }
                            ), in: 0...1)
                            .tint(NeoPalette.accent)
                            .frame(width: 220)
                            Text("\(Int(model.settings.sidebarMaterial * 100))% material")
                                .font(.neoCaption).foregroundStyle(.secondary)
                        }
                        NeoDivider().frame(height: 44)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Corner style")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            HStack(spacing: 6) {
                                ForEach(NeoCornerStyle.allCases) { style in
                                    Button {
                                        model.settings.cornerStyle = style
                                    } label: {
                                        Text(style.title)
                                            .font(.neoCaption.weight(.semibold))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(
                                                model.settings.cornerStyle == style
                                                    ? NeoPalette.accent.opacity(0.16)
                                                    : Color.primary.opacity(0.05),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(
                                                model.settings.cornerStyle == style
                                                    ? NeoPalette.accent : .secondary
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                NeoDivider()

                // Wallpapers
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wallpaper")
                        .font(.neoHeadline)
                    WallpaperPickerView()
                }

                NeoDivider()

                // Theme file actions
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Theme presets")
                            .font(.neoHeadline)
                        HStack(spacing: 8) {
                            Button {
                                exportTheme()
                            } label: {
                                Label("Export .neotheme", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                            Button {
                                importTheme()
                            } label: {
                                Label("Import", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                        }
                        Text("Share your exact look as a .neotheme file.")
                            .font(.neoCaption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Theme presets & file exchange

    private func curatedThemeCard(_ theme: NeoCuratedTheme) -> some View {
        let selected = model.settings.curatedTheme == theme.id
            && model.settings.accentHex == theme.accentHex
        return Button {
            theme.apply(to: &model.settings)
            model.showToast("Theme: \(theme.title)")
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: theme.previewTop), Color(hex: theme.previewBottom)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 86, height: 56)
                    Circle()
                        .fill(Color(hex: theme.accentHex).opacity(0.85))
                        .frame(width: 16, height: 16)
                        .padding(8)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            selected ? Color.white.opacity(0.7) : Color.primary.opacity(0.12),
                            lineWidth: selected ? 2 : 1
                        )
                }
                Text(theme.title)
                    .font(.neoCaption)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: 86)
            }
        }
        .buttonStyle(.plain)
    }

    /// One color-mixer row: name, hex readout, NSColorWell picker and a
    /// text field for direct hex entry.
    private func colorMixerRow(
        title: String,
        symbol: String,
        hex: String,
        allowEmpty: Bool = false,
        apply: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NeoPalette.accent)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .frame(width: 130, alignment: .leading)

            ColorPicker("", selection: Binding(
                get: { Color(hex: hex.isEmpty ? "000000" : hex) },
                set: { apply(hexString(from: $0)) }
            ))
            .labelsHidden()

            TextField(allowEmpty ? "none" : "RRGGBB", text: Binding(
                get: { hex },
                set: { raw in
                    let cleaned = raw.uppercased()
                        .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                    if allowEmpty && cleaned.isEmpty {
                        apply("")
                    } else if cleaned.count == 6 || cleaned.count == 8 {
                        apply(String(cleaned.prefix(6)))
                    }
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .frame(width: 90)

            if !hex.isEmpty {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 16, height: 16)
                    .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8) }
            }
        }
    }

    private func hexString(from color: Color) -> String {
        guard let nsColor = NSColor(color).usingColorSpace(.sRGB) else { return "000000" }
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    private func exportTheme() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "neotheme") ?? .json]
        panel.nameFieldStringValue = "NeoCraft-Theme.neotheme"
        panel.message = "Save your Neo Studio appearance as a shareable preset"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let file = NeoThemeFile(name: url.deletingPathExtension().lastPathComponent, settings: model.settings)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: url, options: .atomic)
            model.showToast("Theme exported")
        } catch {
            model.presentError("Couldn't export theme", error)
        }
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "neotheme") ?? .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a .neotheme preset"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(NeoThemeFile.self, from: data) else {
            return
        }
        file.apply(to: &model.settings)
        model.showToast("Imported theme: \(file.name)")
    }

    private func accentSwatch(_ accent: NeoAccent) -> some View {
        let selected = model.settings.accentHex == accent.rawValue
        return Button {
            model.settings.accentHex = accent.rawValue
            model.showToast("Accent: \(accent.name)")
        } label: {
            VStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: accent.rawValue))
                    .frame(width: 34, height: 34)
                    .overlay {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                selected ? Color.primary.opacity(0.4) : Color.primary.opacity(0.12),
                                lineWidth: selected ? 2 : 1
                            )
                    }
                    .shadow(color: Color(hex: accent.rawValue).opacity(selected ? 0.5 : 0.2), radius: selected ? 6 : 3)
                Text(accent.name)
                    .font(.neoCaption)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func themeModeCard(_ mode: NeoThemeMode) -> some View {
        let selected = model.settings.themeMode == mode
        return Button {
            model.settings.themeMode = mode
            model.showToast("Theme: \(mode.title)")
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(themePreviewColor(mode))
                        .frame(height: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 46, height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.4))
                            .frame(width: 32, height: 5)
                        HStack(spacing: 3) {
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.5))
                                    .frame(width: 14, height: 8)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(mode.title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                Text(mode.subtitle)
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                selected ? NeoPalette.accent.opacity(0.10) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        selected ? NeoPalette.accent.opacity(0.5) : Color.primary.opacity(0.08),
                        lineWidth: selected ? 1.4 : 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func themePreviewColor(_ mode: NeoThemeMode) -> LinearGradient {
        switch mode {
        case .frosted:
            return LinearGradient(
                colors: [Color(hex: "2A3B55"), Color(hex: "141C2E")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .oled:
            return LinearGradient(
                colors: [Color.black, Color(hex: "0A0A0C")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .dynamic:
            return LinearGradient(
                colors: [NeoPalette.accent, NeoPalette.violet],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .biome:
            return LinearGradient(
                colors: [Color(hex: "22D3EE"), Color(hex: "0E7490")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Layout modularity

    private var layoutSection: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Sidebar & Dashboard",
                    subtitle: "Toggle or reorder navigation; Play cards live in the Play Dashboard section",
                    symbol: "sidebar.left"
                )

                // Sidebar visibility + order
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sidebar sections")
                        .font(.neoHeadline)
                    ForEach(orderedSections, id: \.self) { section in
                        sidebarRow(section)
                    }
                }

                NeoDivider()

                HStack(spacing: 10) {
                    Image(systemName: "rectangle.grid.2x2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NeoPalette.accent)
                        .frame(width: 24, height: 24)
                        .background(NeoPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Play dashboard widgets")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        Text("Order, toggle and style the cards shown on the Play screen.")
                            .font(.neoCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Play Dashboard") { studioSection = .dashboard }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                }
            }
        }
    }

    /// Sections in the user's chosen order (hidden ones still listed so
    /// they can be re-enabled).
    private var orderedSections: [AppSection] {
        let order = model.settings.sidebarOrder
        var result: [AppSection] = []
        for raw in order {
            if let section = AppSection(rawValue: raw), !result.contains(section) {
                result.append(section)
            }
        }
        for section in AppSection.allCases where !result.contains(section) {
            result.append(section)
        }
        return result
    }

    private func sidebarRow(_ section: AppSection) -> some View {
        let hidden = model.settings.hiddenSections.contains(section.rawValue)
        let isFirst = orderedSections.first == section
        let isLast = orderedSections.last == section

        return HStack(spacing: 10) {
            Image(systemName: section.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hidden ? Color.secondary : NeoPalette.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(section.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(hidden ? .secondary : .primary)
                Text(section.subtitle)
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Reorder arrows
            Button {
                moveSection(section, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isFirst)
            .opacity(isFirst ? 0.3 : 1)

            Button {
                moveSection(section, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(isLast)
            .opacity(isLast ? 0.3 : 1)

            Toggle("", isOn: Binding(
                get: { !hidden },
                set: { visible in
                    if visible {
                        model.settings.hiddenSections.removeAll { $0 == section.rawValue }
                    } else if section != .play {
                        model.settings.hiddenSections.append(section.rawValue)
                    }
                }
            ))
            .toggleStyle(NeoToggleStyle())
            .labelsHidden()
            .frame(width: 38)
        }
        .padding(.vertical, 3)
    }

    private func moveSection(_ section: AppSection, by offset: Int) {
        var order = model.settings.sidebarOrder.isEmpty
            ? AppSection.allCases.map(\.rawValue)
            : model.settings.sidebarOrder
        guard let index = order.firstIndex(of: section.rawValue) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        model.settings.sidebarOrder = order
    }

    // MARK: - HUD editor

    private var hudSection: some View {
        NeoCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "In-Game HUD Studio",
                    subtitle: "Drag widgets on the preview, then apply to an instance",
                    symbol: "rectangle.on.rectangle"
                )

                HStack(alignment: .top, spacing: 18) {
                    hudCanvas
                        .frame(maxWidth: .infinity)

                    hudInspector
                        .frame(width: 230)
                }

                NeoDivider()

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target instance")
                            .font(.neoCaption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { model.selectedInstanceID },
                            set: { model.selectedInstanceID = $0 }
                        )) {
                            ForEach(model.instances.filter { $0.loader == .fabric }) { instance in
                                Text(instance.name).tag(instance.id as UUID?)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }

                    Menu {
                        Button("Minimal Apple Pro") { applyHUDPreset(.minimal) }
                        Button("PvP Competitive") { applyHUDPreset(.pvp) }
                        Button("Survival Explorer") { applyHUDPreset(.survival) }
                        Button("Streamer Clean") { applyHUDPreset(.streamer) }
                    } label: {
                        Label("Presets", systemImage: "square.stack.3d.up")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 90)

                    Button("Reset Layout") { resetHUDLayout() }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))

                    Spacer()

                    Button {
                        model.applyHUDToInstance()
                    } label: {
                        if model.isApplyingHUD {
                            Label(model.hudApplyDetail, systemImage: "gearshape.2.fill")
                        } else {
                            Label("Apply HUD to Instance", systemImage: "checkmark.circle")
                        }
                    }
                    .buttonStyle(NeoButtonStyle(kind: .primary))
                    .disabled(
                        model.isApplyingHUD
                            || model.selectedInstance?.loader != .fabric
                            || !model.settings.betaFeatures.inGameHUD
                    )
                    .help(model.settings.betaFeatures.inGameHUD
                          ? ""
                          : "Enable the In-Game HUD in Settings → Beta Features first")
                }
            }
        }
    }

    // MARK: HUD canvas

    private var hudCanvas: some View {
        VStack(spacing: 8) {
            // 16:9 gameplay preview
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    // Fake gameplay backdrop
                    LinearGradient(
                        colors: [Color(hex: "7FA8C9"), Color(hex: "4E7A52"), Color(hex: "2E4A34")],
                        startPoint: .top, endPoint: .bottom
                    )

                    // Horizon + fake terrain blocks
                    VStack {
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { i in
                                Rectangle()
                                    .fill(Color(hex: i % 3 == 0 ? "5C8A44" : (i % 3 == 1 ? "6E9A52" : "54803E")))
                                    .frame(height: 26 + CGFloat((i * 7) % 18))
                            }
                        }
                    }

                    // Hotbar
                    HStack(spacing: 3) {
                        ForEach(0..<9, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == 4 ? Color.white.opacity(0.5) : Color.black.opacity(0.35))
                                .frame(width: size.width / 9 - 4, height: size.width / 9 - 4)
                                .overlay {
                                    if i == 4 {
                                        RoundedRectangle(cornerRadius: 3)
                                            .strokeBorder(Color.white, lineWidth: 1.5)
                                    }
                                }
                        }
                    }
                    .padding(6)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                    .position(x: size.width / 2, y: size.height - size.width / 18 - 14)

                    // Widgets
                    ForEach(model.settings.hudLayout.widgets.filter(\.visible)) { widget in
                        hudWidgetView(widget)
                            .position(
                                x: widget.x * size.width,
                                y: widget.y * size.height
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        if dragBase?.id != widget.id {
                                            dragBase = (widget.id, widget.x, widget.y)
                                        }
                                        guard let base = dragBase else { return }
                                        updateWidget(widget.id) { w in
                                            // Snap to a 1/32 grid for clean alignment.
                                            let step = 1.0 / 32.0
                                            let rawX = base.1 + value.translation.width / size.width
                                            let rawY = base.2 + value.translation.height / size.height
                                            w.x = min(max((rawX / step).rounded() * step, 0.02), 0.98)
                                            w.y = min(max((rawY / step).rounded() * step, 0.02), 0.98)
                                        }
                                    }
                                    .onEnded { _ in
                                        dragBase = nil
                                    }
                            )
                            .onTapGesture {
                                selectedWidgetID = widget.id
                            }
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8)
            }

            Text("Drag widgets to reposition (snaps to grid) · tap to select · 16:9 gameplay preview")
                .font(.neoCaption)
                .foregroundStyle(.secondary)
        }
    }

    /// Drag origin captured when a widget drag begins so translation
    /// deltas apply to the position at gesture start, not cumulatively.
    @State private var dragBase: (id: UUID, x: Double, y: Double)?

    /// Drag uses an absolute-position approach: store drag start and compute
    /// from it so translation deltas don't accumulate incorrectly.
    private func updateWidget(_ id: UUID, transform: (inout HUDWidget) -> Void) {
        guard let index = model.settings.hudLayout.widgets.firstIndex(where: { $0.id == id }) else { return }
        transform(&model.settings.hudLayout.widgets[index])
    }

    @ViewBuilder
    private func hudWidgetView(_ widget: HUDWidget) -> some View {
        let tint = Color(hex: widget.colorHex)
        let isSelected = selectedWidgetID == widget.id

        Group {
            switch widget.kind {
            case .fpsPill:
                hudPill(widget) {
                    HStack(spacing: 6) {
                        StatusDot(color: NeoPalette.mint, size: 6)
                        Text("144 FPS")
                        Text("·")
                            .foregroundStyle(.white.opacity(0.4))
                        Text("8.3 ms")
                        Text("·")
                            .foregroundStyle(.white.opacity(0.4))
                        Text("12 chk/s")
                    }
                }
            case .coordsCompass:
                hudPill(widget) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("NE · Cherry Grove")
                            .font(hudFont(widget, size: 9))
                        Text("XYZ: 128 / 64 / -256")
                            .font(hudFont(widget, size: 8))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            case .netherCoords:
                hudPill(widget) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Overworld  128 / 64 / -256")
                        Text("Nether      64 / 32 / -128")
                            .font(hudFont(widget, size: 8))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            case .armorDurability:
                HStack(spacing: 4) {
                    ForEach(0..<10, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(i < 7 ? tint : tint.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.45), in: Capsule())
            case .keystrokes:
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        keyCap("W"); keyCapSpacer(); keyCap("E")
                    }
                    HStack(spacing: 3) {
                        keyCap("A"); keyCap("S"); keyCap("D")
                    }
                    HStack(spacing: 3) {
                        keyCap("LMB"); keyCap("RMB"); keyCap("3.2 CPS")
                    }
                }
            case .potionEffects:
                hudPill(widget) {
                    VStack(alignment: .leading, spacing: 2) {
                        potionRow("Speed II", "0:42", Color(hex: "7CFC00"))
                        potionRow("Strength", "1:18", Color(hex: "CD5C5C"))
                        potionRow("Regeneration", "0:07", Color(hex: "FF69B4"))
                    }
                }
            case .pingTPS:
                hudPill(widget) {
                    HStack(spacing: 6) {
                        StatusDot(color: NeoPalette.mint, size: 6)
                        Text("24 ms")
                        Text("·").foregroundStyle(.white.opacity(0.4))
                        Text("19.8 TPS")
                    }
                }
            case .clocks:
                hudPill(widget) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill").font(.system(size: 8))
                        Text("Day 128")
                        Text("·").foregroundStyle(.white.opacity(0.4))
                        Text("14:32")
                    }
                }
            case .dayLight:
                hudPill(widget) {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill").font(.system(size: 8))
                        Text("Day 128")
                        Text("·").foregroundStyle(.white.opacity(0.4))
                        Text("Light 15")
                    }
                }
            case .speedometer:
                hudPill(widget) {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.67percent").font(.system(size: 8))
                        Text("4.2 B/s")
                    }
                }
            case .statusPills:
                HStack(spacing: 4) {
                    statusPill("SPRINT", active: true, tint: tint)
                    statusPill("SNEAK", active: false, tint: tint)
                }
            case .minimap:
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(widget.backgroundOpacity))
                    // Fake minimap terrain
                    Canvas { context, size in
                        let cell: CGFloat = 8
                        for y in stride(from: 0, to: Int(size.height), by: Int(cell)) {
                            for x in stride(from: 0, to: Int(size.width), by: Int(cell)) {
                                let h = CGFloat((x * 31 + y * 17) % 5)
                                let c: Color = switch h {
                                case 0: Color(hex: "3E7A3A")
                                case 1: Color(hex: "4E8F47")
                                case 2: Color(hex: "6E9A52")
                                case 3: Color(hex: "8A7A55")
                                default: Color(hex: "3B6FD4")
                                }
                                context.fill(
                                    Path(CGRect(x: CGFloat(x), y: CGFloat(y), width: cell, height: cell)),
                                    with: .color(c.opacity(0.8))
                                )
                            }
                        }
                        // Player arrow
                        var arrow = Path()
                        arrow.move(to: CGPoint(x: size.width / 2, y: size.height / 2 - 8))
                        arrow.addLine(to: CGPoint(x: size.width / 2 - 5, y: size.height / 2 + 6))
                        arrow.addLine(to: CGPoint(x: size.width / 2, y: size.height / 2 + 3))
                        arrow.addLine(to: CGPoint(x: size.width / 2 + 5, y: size.height / 2 + 6))
                        arrow.closeSubpath()
                        context.fill(arrow, with: .color(.white))
                    }
                }
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
            }
        }
        .scaleEffect(widget.scale)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(NeoPalette.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .padding(-5)
            }
        }
    }

    private func hudPill<Content: View>(_ widget: HUDWidget, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(hudFont(widget, size: 9.5))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(widget.backgroundOpacity), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
            }
    }

    private func hudFont(_ widget: HUDWidget, size: CGFloat) -> Font {
        widget.fontStyle == .minecraft
            ? .neoPixel(size)
            : .system(size: size, weight: .semibold, design: .rounded)
    }

    private func potionRow(_ name: String, _ time: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).font(.system(size: 8, weight: .medium, design: .rounded))
            Spacer(minLength: 8)
            Text(time).font(.system(size: 8, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    private func statusPill(_ label: String, active: Bool, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 7.5, weight: .bold, design: .rounded))
            .foregroundStyle(active ? .white : .white.opacity(0.45))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(
                active ? tint.opacity(0.85) : Color.black.opacity(0.4),
                in: Capsule()
            )
    }

    private func keyCap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 7.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 24, height: 16)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
            }
    }

    private func keyCapSpacer() -> some View {
        Color.clear.frame(width: 24, height: 16)
    }

    // MARK: HUD inspector

    private var hudInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Widgets")
                    .font(.neoHeadline)
                Spacer()
                Menu {
                    ForEach(HUDWidgetKind.allCases) { kind in
                        if !model.settings.hudLayout.widgets.contains(where: { $0.kind == kind }) {
                            Button {
                                addWidget(kind)
                            } label: {
                                Label(kind.title, systemImage: kind.symbol)
                            }
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 52)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.settings.hudLayout.widgets) { widget in
                        widgetRow(widget)
                    }
                }
            }
            .scrollIndicators(.hidden)

            if let widget = selectedWidget {
                NeoDivider()
                widgetEditor(widget)
            }
        }
    }

    private var selectedWidget: HUDWidget? {
        guard let id = selectedWidgetID else { return nil }
        return model.settings.hudLayout.widgets.first { $0.id == id }
    }

    private func widgetRow(_ widget: HUDWidget) -> some View {
        Button {
            selectedWidgetID = widget.id
        } label: {
            HStack(spacing: 9) {
                Image(systemName: widget.kind.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: widget.colorHex))
                    .frame(width: 22, height: 22)
                    .background(Color(hex: widget.colorHex).opacity(0.14), in: RoundedRectangle(cornerRadius: 6))

                Text(widget.kind.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(widget.visible ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Button {
                    toggleWidget(widget.id)
                } label: {
                    Image(systemName: widget.visible ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(widget.visible ? NeoPalette.accent : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(
                selectedWidgetID == widget.id ? NeoPalette.accent.opacity(0.10) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selectedWidgetID == widget.id ? NeoPalette.accent.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func widgetEditor(_ widget: HUDWidget) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(widget.kind.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))

            // Scale slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scale")
                        .font(.neoCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(widget.scale * 100))%")
                        .font(.neoCaption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { widget.scale },
                        set: { newValue in
                            updateWidget(widget.id) { $0.scale = newValue }
                        }
                    ),
                    in: 0.6...1.6
                )
                .tint(NeoPalette.accent)
            }

            // Color swatches
            VStack(alignment: .leading, spacing: 4) {
                Text("Color")
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    ForEach(["5B8CFF", "4ADE80", "A78BFA", "FB923C", "FBBF24", "F87171", "38BDF8"], id: \.self) { hex in
                        Button {
                            updateWidget(widget.id) { $0.colorHex = hex }
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    if widget.colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Background opacity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Background")
                        .font(.neoCaption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(widget.backgroundOpacity * 100))%")
                        .font(.neoCaption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { widget.backgroundOpacity },
                        set: { newValue in
                            updateWidget(widget.id) { $0.backgroundOpacity = newValue }
                        }
                    ),
                    in: 0...0.9
                )
                .tint(NeoPalette.accent)
            }

            // Font style
            VStack(alignment: .leading, spacing: 4) {
                Text("Font")
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(HUDFontStyle.allCases) { style in
                        Button {
                            updateWidget(widget.id) { $0.fontStyle = style }
                        } label: {
                            Text(style.title)
                                .font(.neoCaption.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(
                                    widget.fontStyle == style
                                        ? NeoPalette.accent.opacity(0.16)
                                        : Color.primary.opacity(0.05),
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    widget.fontStyle == style ? NeoPalette.accent : .secondary
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Position readout + reset
            HStack {
                Text("X \(Int(widget.x * 100))% · Y \(Int(widget.y * 100))%")
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Reset") {
                    if let d = HUDWidget.defaults.first(where: { $0.kind == widget.kind }) {
                        updateWidget(widget.id) {
                            $0.x = d.x; $0.y = d.y; $0.scale = d.scale; $0.colorHex = d.colorHex
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.neoCaption)
                .foregroundStyle(NeoPalette.accent)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toggleWidget(_ id: UUID) {
        guard let index = model.settings.hudLayout.widgets.firstIndex(where: { $0.id == id }) else { return }
        model.settings.hudLayout.widgets[index].visible.toggle()
    }

    /// Adds a widget of `kind` at a sensible default position if the user
    /// removed it earlier.
    private func addWidget(_ kind: HUDWidgetKind) {
        if let existing = HUDWidget.defaults.first(where: { $0.kind == kind }) {
            model.settings.hudLayout.widgets.append(existing)
        } else {
            model.settings.hudLayout.widgets.append(
                HUDWidget(kind: kind, x: 0.5, y: 0.5)
            )
        }
        selectedWidgetID = model.settings.hudLayout.widgets.last?.id
    }
}
