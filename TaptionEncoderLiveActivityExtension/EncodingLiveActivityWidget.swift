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
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TaptionEncodingCompactProgressView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "film.stack")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                Text(context.state.percentText)
                    .font(.caption2)
                    .bold()
                    .monospacedDigit()
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
    var state: TaptionEncodingLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

                Text(state.percentText)
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: true, vertical: false)
            }

            ProgressView(value: state.fractionCompleted)
                .tint(.cyan)

            HStack(spacing: 10) {
                Label(state.countText, systemImage: "list.bullet.rectangle")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.78)
                Label(state.remainingText, systemImage: "hourglass")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("\(state.codecPathText) -> \(state.outputText)")
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.72)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 5)
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
                Spacer()
                Text(state.sourceName)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: state.fractionCompleted)
                .tint(.cyan)
            HStack(spacing: 6) {
                Text(state.codecPathText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(state.outputText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
