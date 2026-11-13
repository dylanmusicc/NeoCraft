import SwiftUI

/// A page's header, like NeoCraft's `PageHeader`: the voxel mark, the pixel
/// title and an optional subtitle, with trailing controls on the right.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VoxelCube(size: 30)
                .shadow(color: Palette.green.opacity(0.35), radius: 6, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.neoPixelBold(26))
                    .tracking(0.5)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}
