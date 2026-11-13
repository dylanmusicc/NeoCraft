import SwiftUI

struct ConsoleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var filteredEntries: [ConsoleEntry] {
        let query = model.consoleFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.console }
        return model.console.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            NeoDivider()
            filterBar
            NeoDivider()
            consoleBody
            NeoDivider()
            footer
        }
        .frame(width: 980, height: 640)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: "0E1626"))
                Image(systemName: "terminal.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NeoPalette.mint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Game Console")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                HStack(spacing: 5) {
                    StatusDot(color: model.isGameRunning ? NeoPalette.mint : NeoPalette.slate, size: 6)
                    Text(model.isGameRunning ? "Minecraft is running" : "Minecraft is not running")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            NeoPill(text: "\(filteredEntries.count) lines", symbol: "text.alignleft", tint: NeoPalette.accent)

            Button {
                model.copyConsoleToClipboard()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))

            Button {
                model.clearConsole()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            NeoSearchField(placeholder: "Filter console output", text: filterBinding)
                .frame(maxWidth: 330)

            if model.isGameRunning {
                NeoPill(text: "Live", symbol: "dot.radiowaves.left.and.right", tint: NeoPalette.mint)
            }

            Spacer()

            if let url = model.lastLaunchLogURL {
                Button {
                    model.reveal(url)
                } label: {
                    Label("Show Log File", systemImage: "doc.text")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            }

            Button {
                model.reveal(AppPaths.logs)
            } label: {
                Label("Logs Folder", systemImage: "folder")
            }
            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private var consoleBody: some View {
        let entries = filteredEntries

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(Color(hex: "6B7C99"))
                            Text(model.consoleFilter.isEmpty ? "Console output will appear here." : "No lines match \"\(model.consoleFilter)\".")
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color(hex: "6B7C99"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        ForEach(entries) { entry in
                            consoleLine(entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .scrollIndicators(.visible)
            .background(Color(hex: "080D17"))
            .onAppear {
                if let last = entries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: entries.count) { _, _ in
                if let last = entries.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func consoleLine(_ entry: ConsoleEntry) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(entry.date.formatted(date: .omitted, time: .standard))
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(hex: "536684"))
                .frame(width: 70, alignment: .leading)

            Circle()
                .fill(levelColor(entry.level))
                .frame(width: 5, height: 5)
                .padding(.top, 4)

            Text(entry.text)
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundStyle(entry.level == .error ? Color(hex: "FFB4B4") : Color(hex: "D5DFF0"))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2.5)
        .contextMenu {
            Button {
                model.copyToClipboard(entry.text, label: "Line copied")
            } label: {
                Label("Copy Line", systemImage: "doc.on.doc")
            }
        }
    }

    private func levelColor(_ level: ConsoleLevel) -> Color {
        switch level {
        case .info: return NeoPalette.sky
        case .warning: return NeoPalette.amber
        case .error: return NeoPalette.danger
        case .game: return NeoPalette.mint
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("Access tokens are redacted from the launch command.")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)

            Spacer()

            if let url = model.lastLaunchLogURL {
                Text(url.lastPathComponent)
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Button("Close") {
                close()
            }
            .buttonStyle(NeoButtonStyle(kind: .secondary, compact: true))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var filterBinding: Binding<String> {
        Binding(
            get: { model.consoleFilter },
            set: { model.consoleFilter = $0 }
        )
    }

    private func close() {
        model.showConsole = false
        dismiss()
    }
}
