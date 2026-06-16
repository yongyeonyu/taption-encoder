import SwiftUI

struct StatusBanner<Actions: View>: View {
    var title: String
    var message: String
    var systemImage: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.92))

            Text(message)
                .font(.subheadline)
                .foregroundStyle(TaptionTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(TaptionTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TaptionTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension StatusBanner where Actions == EmptyView {
    init(title: String, message: String, systemImage: String) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actions = { EmptyView() }
    }
}
