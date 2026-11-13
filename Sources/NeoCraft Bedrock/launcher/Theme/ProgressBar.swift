import SwiftUI

/// Fills from the left, rounded like NeoCraft's meters, in its accent.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Palette.accent, Palette.accent.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                    .frame(width: geometry.size.width * value)
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.2), value: value)
    }
}
