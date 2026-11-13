import SwiftUI

/// NeoCraft's switch, after the label: a capsule track in the accent when on, and a white knob
/// on the side it is on. The whole row switches it.
struct PixelToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 16) {
                configuration.label
                Spacer(minLength: 12)
                Switch(isOn: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct Switch: View {
        let isOn: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Palette.accent : Color.primary.opacity(0.16))
                    .frame(width: 38, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 17, height: 17)
                    .padding(2.5)
                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            }
            .frame(width: 38, height: 22)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isOn)
        }
    }
}

extension ToggleStyle where Self == PixelToggleStyle {
    static var pixel: PixelToggleStyle { PixelToggleStyle() }
}
