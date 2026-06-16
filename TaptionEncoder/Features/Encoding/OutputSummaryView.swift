import SwiftUI

struct OutputSummaryView: View {
    var outputSummary: String
    var backgroundSummary: String
    var contentScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * contentScale) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label("Output", systemImage: "video")
                    .font(contentScale < 0.9 ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                Text(outputSummary)
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Label(backgroundSummary, systemImage: "clock")
                .font(contentScale < 0.9 ? .caption2 : .footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10 * contentScale)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
