import SwiftUI

/// The standard card container: a surface, a hairline border, one radius.
///
/// Colours and radius come from the design system so a card can never drift from the rest of the
/// UI. `TaptionTheme` lives in `Shared/DesignSystem/TaptionDesignSystem.swift`.
struct ProgressCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TaptionTheme.cardContentPadding)
            .background(TaptionTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: TaptionRadius.card)
                    .stroke(TaptionTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: TaptionRadius.card, style: .continuous))
    }
}
