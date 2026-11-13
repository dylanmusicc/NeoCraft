import SwiftUI

/// A title, in NeoCraft's pixel font.
struct TitleText: View {
    let text: Text
    var size: CGFloat = 14
    var color = Palette.text

    init(_ key: LocalizedStringKey, size: CGFloat = 14, color: Color = Palette.text) {
        text = Text(key)
        self.size = size
        self.color = color
    }

    init(verbatim string: String, size: CGFloat = 14, color: Color = Palette.text) {
        text = Text(verbatim: string)
        self.size = size
        self.color = color
    }

    var body: some View {
        text.font(.neoPixelBold(size)).foregroundStyle(color)
    }
}
