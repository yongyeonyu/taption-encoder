import SwiftUI

struct OutputSummaryView: View {
    var title: String
    var videoCodecText: String
    var audioCodecText: String
    var contentScale: CGFloat = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10 * contentScale) {
            Label(title, systemImage: "film")
                .font(contentScale < 0.9 ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 4 * contentScale)

            HStack(alignment: .firstTextBaseline, spacing: 8 * contentScale) {
                codecLine(videoCodecText)
                codecLine(audioCodecText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10 * contentScale)
        .background(TaptionTheme.elevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TaptionTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func codecLine(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
