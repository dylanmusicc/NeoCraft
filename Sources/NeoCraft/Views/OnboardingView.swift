import SwiftUI

// MARK: - First-launch onboarding

/// Six-step welcome flow shown once on first launch. Persists completion
/// in UserDefaults so it never reappears unless reset.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0

    private static let doneKey = "NeoOnboardingComplete"
    private let stepCount = 7

    var body: some View {
        VStack(spacing: 22) {
            Group {
                switch step {
                case 0: welcomeStep
                case 1: styleStep
                case 2: editionStep
                case 3: performanceStep
                case 4: accountStep
                case 5: tourStep
                default: readyStep
                }
            }
            .frame(height: 320)
            .id(step)
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            // Page dots
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.neoAccent : Color.secondary.opacity(0.3))
                        .frame(width: i == step ? 20 : 7, height: 7)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: step)

            HStack(spacing: 12) {
                Button("Skip") { finish() }
                    .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
                Spacer()
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                        .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                }
                Button(step == stepCount - 1 ? "Get Started" : "Next") {
                    if step == stepCount - 1 { finish() } else { withAnimation { step += 1 } }
                }
                .buttonStyle(NeoButtonStyle(kind: .primary, compact: true))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 4)
        }
        .padding(30)
        .frame(width: 540)
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        dismiss()
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "7CBD4B"), Color(hex: "38BDF8"), Color(hex: "A78BFA")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .shadow(color: Color(hex: "7CBD4B").opacity(0.45), radius: 18, y: 6)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white)
            }
            Text("Welcome to NeoCraft")
                .font(.neoTitle)
            Text("The native macOS Minecraft launcher — voxel soul, Apple polish. Built for Apple silicon and tuned for long sessions.")
                .font(.neoBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var styleStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make NeoCraft Yours")
                .font(.neoTitle)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: 6) {
                Text("Theme")
                    .font(.neoCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(NeoThemeMode.allCases) { mode in
                        themeModeChip(mode)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Accent")
                    .font(.neoCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(NeoAccent.allCases) { accent in
                        accentDot(accent)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Wallpaper")
                    .font(.neoCaption.weight(.semibold))
                    .foregroundStyle(.secondary)
                WallpaperPickerView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func themeModeChip(_ mode: NeoThemeMode) -> some View {
        let selected = model.settings.themeMode == mode
        return Button {
            model.settings.themeMode = mode
            SoundManager.shared.play(.click)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(mode.title)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                selected ? NeoPalette.accent.opacity(0.16) : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .overlay {
                Capsule().strokeBorder(
                    selected ? NeoPalette.accent.opacity(0.5) : Color.primary.opacity(0.1),
                    lineWidth: selected ? 1 : 0.8
                )
            }
            .foregroundStyle(selected ? NeoPalette.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func accentDot(_ accent: NeoAccent) -> some View {
        let selected = model.settings.accentHex == accent.rawValue
        return Button {
            model.settings.accentHex = accent.rawValue
            model.settings.curatedTheme = ""
            SoundManager.shared.play(.click)
        } label: {
            Circle()
                .fill(Color(hex: accent.rawValue))
                .frame(width: 26, height: 26)
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                    }
                }
                .scaleEffect(selected ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .help(accent.name)
    }

    private var editionStep: some View {
        VStack(spacing: 14) {
            heroIcon("gamecontroller.fill", tint: NeoPalette.sky)
            Text("Java or Bedrock?")
                .font(.neoTitle)
            Text("NeoCraft launches Java Edition natively — mods, shaders, Neo Boost. Bedrock is a beta track: NeoCraft Bedrock (Wine + Xbox GDK) is bundled inside NeoCraft and runs the Windows edition.")
                .font(.neoBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                editionCard(.java)
                editionCard(.bedrock)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editionCard(_ edition: GameEdition) -> some View {
        let selected = model.settings.preferredEdition == edition
        return Button {
            model.settings.preferredEdition = edition
            if edition == .bedrock {
                // Opting into Bedrock during onboarding enables the beta flag.
                model.settings.betaFeatures.bedrockEdition = true
            }
            SoundManager.shared.play(.click)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: edition.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(selected ? Color.neoAccent : .secondary)
                Text(edition.shortTitle)
                    .font(.neoBody.weight(.bold))
                Text(edition == .java
                     ? "Full launch support — mods, shaders, worlds"
                     : "Beta — bundled, Play launches directly")
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .background(
                selected ? Color.neoAccent.opacity(0.12) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? Color.neoAccent.opacity(0.6) : Color.primary.opacity(0.1),
                        lineWidth: selected ? 1.5 : 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private var performanceStep: some View {
        VStack(spacing: 14) {
            heroIcon("bolt.fill", tint: NeoPalette.amber)
            Text("Built for the MacBook Neo")
                .font(.neoTitle)
            Text("Cool & Quiet caps frames and heap for silent fanless play; Max Performance opens the tap. Adaptive Performance shifts automatically on battery or heat.")
                .font(.neoBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                tipChip("snowflake", "Silent")
                tipChip("memorychip", "8 GB safe")
                tipChip("square.stack.3d.up", "32 chunks")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var accountStep: some View {
        VStack(spacing: 14) {
            heroIcon("person.crop.circle.badge.checkmark", tint: NeoPalette.sky)
            Text("Sign In Your Way")
                .font(.neoTitle)
            Text("Microsoft account for online play, or unlimited offline profiles with custom skins — both managed from the Play tab.")
                .font(.neoBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Microsoft Sign-In") {
                    model.showAuthSheet = true
                    finish()
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
                Button("Offline Profile") {
                    model.showOfflineAccountSheet = true
                    finish()
                }
                .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tourStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("The 30-second tour", systemImage: "map.fill")
                .font(.neoTitle)
            tourRow("play.circle.fill", "Play", "Launch instances, browse multiplayer servers, and run Flight Check before launch.")
            tourRow("shippingbox.fill", "Mod Library", "Browse Modrinth mods and shaders with FPS badges.")
            tourRow("square.stack.3d.up.fill", "Instances", "Per-instance mods, shaders, worlds and JVM config.")
            tourRow("paintbrush.pointed.fill", "Studio", "Themes, dashboard layout and audio customization.")
            tourRow("camera.viewfinder", "Screenshots", "Browse in-game captures with Quick Look.")
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readyStep: some View {
        VStack(spacing: 14) {
            heroIcon("gamecontroller.fill", tint: Color.neoAccent)
            Text("You're Ready")
                .font(.neoTitle)
            Text("Pick an instance on Play, or create one in Instances. Everything else lives in the sidebar — enjoy the blocks.")
                .font(.neoBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Building blocks

    private func heroIcon(_ symbol: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 76, height: 76)
            Circle()
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                .frame(width: 76, height: 76)
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(tint)
        }
    }

    private func tipChip(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.neoCaption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func tourRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.neoAccent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.neoBody.weight(.semibold))
                Text(detail).font(.neoCaption).foregroundStyle(.secondary)
            }
        }
    }
}
