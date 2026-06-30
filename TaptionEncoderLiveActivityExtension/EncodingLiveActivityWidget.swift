import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TaptionEncoderLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        TaptionEncodingLiveActivityWidget()
    }
}

struct TaptionEncodingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaptionEncodingLiveActivityAttributes.self) { context in
            TaptionEncodingLockScreenView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.modeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(context.state.countText)
                            .font(.caption)
                            .bold()
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, CGFloat(TaptionEncodingLiveActivityLayoutMetrics.dynamicIslandExpandedTopPadding))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.percentText)
                            .font(.title3)
                            .bold()
                        Text(context.state.remainingText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.top, CGFloat(TaptionEncodingLiveActivityLayoutMetrics.dynamicIslandExpandedTopPadding))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TaptionEncodingCompactProgressView(state: context.state)
                        .padding(.top, CGFloat(TaptionEncodingLiveActivityLayoutMetrics.dynamicIslandBottomTopPadding))
                        .padding(.horizontal, 2)
                }
            } compactLeading: {
                Image(systemName: "film.stack")
                    .font(.caption.bold())
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                Text(context.state.percentText)
                    .font(.caption2)
                    .bold()
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } minimal: {
                ProgressView(value: context.state.fractionCompleted)
                    .progressViewStyle(.circular)
                    .tint(.cyan)
            }
            .keylineTint(.cyan)
        }
    }
}

private struct TaptionEncodingLockScreenView: View {
    @Environment(\.activityFamily) private var activityFamily
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var state: TaptionEncodingLiveActivityAttributes.ContentState

    var body: some View {
        let isSupplementalSmallFamily = activityFamily == .small
        let metrics = TaptionEncodingLiveActivityLayoutMetrics.lockScreen(
            isRegularWidth: horizontalSizeClass == .regular,
            isSupplementalSmallFamily: isSupplementalSmallFamily
        )

        VStack(alignment: .leading, spacing: CGFloat(metrics.verticalSpacing)) {
            if isSupplementalSmallFamily {
                condensedHeader
            } else {
                standardHeader
            }

            ProgressView(value: state.fractionCompleted)
                .tint(.cyan)

            if isSupplementalSmallFamily {
                condensedDetails
            } else {
                standardDetails
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CGFloat(metrics.horizontalPadding))
        .padding(.top, CGFloat(metrics.topPadding))
        .padding(.bottom, CGFloat(metrics.bottomPadding))
    }

    private var standardHeader: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.statusText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.78)
                Text(state.sourceName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(.secondary)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            percentText
        }
    }

    private var condensedHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(state.statusText)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.78)
                .layoutPriority(1)

            Spacer(minLength: 4)

            percentText
        }
    }

    private var percentText: some View {
        Text(state.percentText)
            .font(.title3)
            .bold()
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var standardDetails: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    countLabel
                    remainingLabel
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 2) {
                    countLabel
                    remainingLabel
                }
            }

            ViewThatFits(in: .horizontal) {
                Text("\(state.codecPathText) -> \(state.outputText)")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.codecPathText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.78)
                    Text(state.outputText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.78)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var condensedDetails: some View {
        HStack(spacing: 8) {
            countLabel
            remainingLabel
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var countLabel: some View {
        Label(state.countText, systemImage: "list.bullet.rectangle")
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.78)
    }

    private var remainingLabel: some View {
        Label(state.remainingText, systemImage: "hourglass")
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.78)
    }
}

private struct TaptionEncodingCompactProgressView: View {
    var state: TaptionEncodingLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(state.statusText)
                    .font(.caption)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.78)
                Spacer()
                Text(state.sourceName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: state.fractionCompleted)
                .tint(.cyan)
            HStack(spacing: 6) {
                Text(state.codecPathText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)
                Spacer()
                Text(state.outputText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.72)
                    .layoutPriority(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
