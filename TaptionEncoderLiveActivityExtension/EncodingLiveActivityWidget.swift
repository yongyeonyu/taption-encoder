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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.statusText)
                        .font(.headline)
                    Text(state.sourceName)
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(state.percentText)
                    .font(.title2)
                    .bold()
                    .monospacedDigit()
            }

            ProgressView(value: state.fractionCompleted)
                .tint(.cyan)

            HStack(spacing: 12) {
                Label(state.countText, systemImage: "list.bullet.rectangle")
                Label(state.remainingText, systemImage: "hourglass")
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("\(state.codecPathText) -> \(state.outputText)")
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
                Spacer()
                Text(state.sourceName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: state.fractionCompleted)
                .tint(.cyan)
            HStack {
                Text(state.codecPathText)
                Spacer()
                Text(state.outputText)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
