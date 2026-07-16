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
    static let appBackground = Color(taptionHex: 0x1A1B26)
    static let surface = Color(taptionHex: 0x1F2335)
    static let elevatedSurface = Color(taptionHex: 0x24283B)
    static let selectedSurface = Color(taptionHex: 0x292E42)
    static let border = Color(taptionHex: 0x3B4261)
    static let strongBorder = Color(taptionHex: 0x565F89)
    static let primaryText = Color(taptionHex: 0xC0CAF5)
    static let mutedText = Color(taptionHex: 0xA9B1D6).opacity(0.78)
    static let disabledText = Color(taptionHex: 0x565F89)
    static let accent = Color(taptionHex: 0x7AA2F7)
    static let accentButtonText = Color(taptionHex: 0x16161E)
    static let coral = Color(taptionHex: 0xFF9E64)
    static let success = Color(taptionHex: 0x9ECE6A)
    static let reward = Color(taptionHex: 0xE0AF68)
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
