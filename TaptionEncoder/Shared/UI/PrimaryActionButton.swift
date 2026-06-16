import SwiftUI

struct PrimaryActionButton: View {
    var title: String
    var systemImage: String
    var isProminent: Bool
    var isEnabled: Bool
    var height: CGFloat = 44
    var font: Font = .body
    var action: () -> Void

    var body: some View {
        button
            .buttonStyle(.plain)
    }

    private var button: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(font)
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: height)
        }
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }

    private var backgroundColor: Color {
        if isProminent {
            return isEnabled ? TaptionTheme.accent : TaptionTheme.elevatedSurface
        }
        return TaptionTheme.elevatedSurface
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return TaptionTheme.disabledText
        }
        return isProminent ? .white : TaptionTheme.accent
    }

    private var borderColor: Color {
        if isProminent {
            return TaptionTheme.accent.opacity(isEnabled ? 0.65 : 0.18)
        }
        return isEnabled ? TaptionTheme.border : Color.white.opacity(0.06)
    }
}
