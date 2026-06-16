import SwiftUI

struct EncoderPathInfoView: View {
    var title: String
    var detail: String
    var systemImage: String
    var contentScale: CGFloat = 1

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3 * contentScale) {
                Text(title)
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(detail)
                    .font(contentScale < 0.9 ? .caption2 : .footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 16 * contentScale, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10 * contentScale)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
