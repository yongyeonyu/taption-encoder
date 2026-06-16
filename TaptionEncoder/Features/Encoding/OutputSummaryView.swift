import SwiftUI

struct OutputSummaryView: View {
    var title: String
    var statusText: String
    var outputSummary: String
    var detailText: String
    var routeBadges: [String] = []
    var contentScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * contentScale) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label(title, systemImage: "arrow.triangle.2.circlepath")
                    .font(contentScale < 0.9 ? .subheadline.weight(.semibold) : .headline)
                Spacer()
                Text(statusText)
                    .font(contentScale < 0.9 ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .padding(.horizontal, 8 * contentScale)
                    .padding(.vertical, 4 * contentScale)
                    .background(TaptionTheme.surface.opacity(0.9))
                    .overlay(
                        Capsule().stroke(TaptionTheme.border, lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }

            Text(outputSummary)
                .font(contentScale < 0.9 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if !routeBadges.isEmpty {
                HStack(spacing: 6 * contentScale) {
                    ForEach(routeBadges, id: \.self) { badge in
                        Text(badge)
                            .font(contentScale < 0.9 ? .caption2.weight(.semibold) : .caption2.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .padding(.horizontal, 8 * contentScale)
                            .padding(.vertical, 4 * contentScale)
                            .background(TaptionTheme.surface.opacity(0.92))
                            .overlay(
                                Capsule()
                                    .stroke(TaptionTheme.border, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                }
            }

            Text(detailText)
                .font(contentScale < 0.9 ? .caption2 : .footnote)
                .foregroundStyle(TaptionTheme.mutedText)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
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
}
