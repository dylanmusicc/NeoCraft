import SwiftUI

extension View {
    /// A sunken slot inside a card, rounded like the rest of NeoCraft's surfaces.
    func slot() -> some View {
        background {
            RoundedRectangle(cornerRadius: NeoSync.shared.radius(8), style: .continuous)
                .fill(Palette.slot)
        }
        .overlay {
            RoundedRectangle(cornerRadius: NeoSync.shared.radius(8), style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
    }
}
