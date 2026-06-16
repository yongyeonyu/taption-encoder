import SwiftUI

enum TaptionTheme {
    static let appBackground = Color(red: 0.005, green: 0.006, blue: 0.008)
    static let surface = Color(red: 0.045, green: 0.049, blue: 0.058)
    static let elevatedSurface = Color(red: 0.071, green: 0.077, blue: 0.091)
    static let selectedSurface = Color(red: 0.035, green: 0.083, blue: 0.135)
    static let border = Color.white.opacity(0.10)
    static let strongBorder = Color.white.opacity(0.18)
    static let accent = Color(red: 0.18, green: 0.55, blue: 1.0)
    static let mutedText = Color.white.opacity(0.58)
    static let disabledText = Color.white.opacity(0.34)
}

struct ProgressCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(TaptionTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(TaptionTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
