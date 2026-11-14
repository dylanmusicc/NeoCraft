import SwiftUI

/// Neo Studio "Play Dashboard" section: widget toggles + ordering, hero
/// card style picker and wallpaper quick-picks for the Play screen.
struct DashboardCustomizerView: View {
    @Environment(AppModel.self) private var model

    /// Widgets in their effective display order.
    private var orderedKinds: [DashboardCardKind] {
        model.settings.orderedDashboardKinds
    }

    /// Curated Play-dashboard layouts — one click sets the hero style,
    /// the enabled widget set and their order.
    private enum DashboardPreset: String, CaseIterable, Identifiable {
        case clean, minimal, full, telemetry
        var id: String { rawValue }
        var title: String {
            switch self {
            case .clean: "Clean"
            case .minimal: "Minimal"
            case .full: "Full"
            case .telemetry: "Telemetry"
            }
        }
        var symbol: String {
            switch self {
            case .clean: "sparkles"
            case .minimal: "minus.rectangle"
            case .full: "rectangle.grid.2x2.fill"
            case .telemetry: "waveform.path.ecg"
            }
        }
        var widgets: [DashboardCardKind] {
            switch self {
            case .clean: [.memory, .activity, .screenshots]
            case .minimal: [.activity]
            case .full: DashboardCardKind.allCases
            case .telemetry: [.memory, .thermal, .boost, .flightCheck]
            }
        }
        var hero: String {
            switch self {
            case .clean, .minimal: "compact"
            case .full: "banner"
            case .telemetry: "glass"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Presets
            VStack(alignment: .leading, spacing: 8) {
                Text("Presets")
                    .font(.neoHeadline)
                HStack(spacing: 8) {
                    ForEach(DashboardPreset.allCases) { preset in
                        presetButton(preset)
                    }
                }
                Text("Presets set the hero style, widget set and order — fine-tune below.")
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
            }

            NeoDivider()

            // Hero card style
            VStack(alignment: .leading, spacing: 8) {
                Text("Hero card style")
                    .font(.neoHeadline)
                HStack(spacing: 8) {
                    ForEach(HeroCardStyle.allCases) { style in
                        heroStyleButton(style)
                    }
                }
                Text(heroStyleSubtitle)
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
            }

            NeoDivider()

            // Widget toggles + ordering
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Dashboard widgets")
                        .font(.neoHeadline)
                    Spacer()
                    Text("\(orderedKinds.count) of \(DashboardCardKind.allCases.count) enabled")
                        .font(.neoCaption)
                        .foregroundStyle(.secondary)
                    Button("Reset") {
                        model.settings.dashboardCards = DashboardCardKind.allCases.map(\.rawValue)
                        model.settings.dashboardWidgetOrder = []
                        model.showToast("Dashboard layout reset")
                    }
                    .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                    .help("Restore the default widget set and order")
                }
                ForEach(orderedKinds) { kind in
                    widgetRow(kind)
                }
                // Disabled widgets listed after, so they can be re-enabled.
                ForEach(DashboardCardKind.allCases.filter {
                    !model.settings.dashboardCards.contains($0.rawValue)
                }) { kind in
                    widgetRow(kind)
                }
            }

            NeoDivider()

            // Wallpaper quick picks
            VStack(alignment: .leading, spacing: 8) {
                Text("Wallpaper quick-picks")
                    .font(.neoHeadline)
                WallpaperPickerView()
            }
        }
    }

    // MARK: Presets

    private func presetButton(_ preset: DashboardPreset) -> some View {
        let selected = model.settings.dashboardWidgetOrder == preset.widgets.map(\.rawValue)
            && model.settings.dashboardCards == preset.widgets.map(\.rawValue)
            && model.settings.heroCardStyle == preset.hero
        return Button {
            model.settings.dashboardCards = preset.widgets.map(\.rawValue)
            model.settings.dashboardWidgetOrder = preset.widgets.map(\.rawValue)
            model.settings.heroCardStyle = preset.hero
            model.showToast("\(preset.title) preset applied")
        } label: {
            VStack(spacing: 5) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? NeoPalette.accent : .secondary)
                Text(preset.title)
                    .font(.neoCaption.weight(.semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(width: 74, height: 52)
            .background(
                selected ? NeoPalette.accent.opacity(0.12) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? NeoPalette.accent.opacity(0.45) : Color.primary.opacity(0.08),
                        lineWidth: selected ? 1.2 : 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Hero style

    private enum HeroCardStyle: String, CaseIterable, Identifiable {
        case compact, banner, glass
        var id: String { rawValue }
        var title: String {
            switch self {
            case .compact: "Compact"
            case .banner: "Banner"
            case .glass: "Glass"
            }
        }
        var symbol: String {
            switch self {
            case .compact: "rectangle.compress.vertical"
            case .banner: "rectangle.expand.vertical"
            case .glass: "square.on.square"
            }
        }
    }

    private var heroStyleSubtitle: String {
        switch model.settings.heroCardStyle {
        case "compact": "A slim card that keeps the playfield open."
        case "banner": "The full gradient hero with live stats."
        default: "A frosted material hero that blends into your theme."
        }
    }

    private func heroStyleButton(_ style: HeroCardStyle) -> some View {
        let selected = model.settings.heroCardStyle == style.rawValue
        return Button {
            model.settings.heroCardStyle = style.rawValue
        } label: {
            VStack(spacing: 5) {
                Image(systemName: style.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? NeoPalette.accent : .secondary)
                Text(style.title)
                    .font(.neoCaption.weight(.semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .frame(width: 74, height: 52)
            .background(
                selected ? NeoPalette.accent.opacity(0.12) : Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        selected ? NeoPalette.accent.opacity(0.45) : Color.primary.opacity(0.08),
                        lineWidth: selected ? 1.2 : 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Widget rows

    private func widgetRow(_ kind: DashboardCardKind) -> some View {
        let enabled = model.settings.dashboardCards.contains(kind.rawValue)
        let ordered = orderedKinds
        let index = ordered.firstIndex(of: kind)
        let isFirst = ordered.isEmpty || index == ordered.startIndex
        let isLast = ordered.isEmpty || index == ordered.index(before: ordered.endIndex)

        return HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? NeoPalette.accent : Color.secondary)
                .frame(width: 28, height: 28)
                .background(
                    (enabled ? NeoPalette.accent : Color.secondary).opacity(enabled ? 0.12 : 0.07),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabled ? .primary : .secondary)
                Text(kind.subtitle)
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Reorder arrows (only meaningful while enabled)
            Button {
                moveWidget(kind, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled || isFirst)
            .opacity(!enabled || isFirst ? 0.3 : 1)

            Button {
                moveWidget(kind, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled || isLast)
            .opacity(!enabled || isLast ? 0.3 : 1)

            Toggle("", isOn: Binding(
                get: { enabled },
                set: { visible in
                    if visible {
                        model.settings.dashboardCards.append(kind.rawValue)
                    } else {
                        model.settings.dashboardCards.removeAll { $0 == kind.rawValue }
                    }
                }
            ))
            .toggleStyle(NeoToggleStyle())
            .labelsHidden()
            .frame(width: 38)
        }
        .padding(.vertical, 3)
    }

    private func moveWidget(_ kind: DashboardCardKind, by offset: Int) {
        var order = orderedKinds
        guard let index = order.firstIndex(of: kind) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        model.settings.dashboardWidgetOrder = order.map(\.rawValue)
    }
}
