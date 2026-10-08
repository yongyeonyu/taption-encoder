import SwiftUI

private extension Color {
    init(taptionHex value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum TaptionTheme {
    static let appBackground = Color(taptionHex: 0x0F191E)
    static let surface = Color(taptionHex: 0x182931)
    static let elevatedSurface = Color(taptionHex: 0x1D333D)
    static let selectedSurface = Color(taptionHex: 0x203E48)
    static let border = Color(taptionHex: 0x2F4650)
    static let strongBorder = Color(taptionHex: 0x526E7A)
    static let primaryText = Color(taptionHex: 0xE8F3F7)
    static let mutedText = Color(taptionHex: 0x9AAFBA)
    static let disabledText = Color(taptionHex: 0x78909B)
    static let accent = Color(taptionHex: 0x6DD0E5)
    static let accentButtonText = Color(taptionHex: 0x0B1B21)
    static let coral = Color(taptionHex: 0xEBA58B)
    static let success = Color(taptionHex: 0x91CBB6)
    static let reward = Color(taptionHex: 0xE5C184)
    static let cardContentPadding: CGFloat = 12
}

struct ProgressCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TaptionTheme.cardContentPadding)
            .background(TaptionTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TaptionTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
