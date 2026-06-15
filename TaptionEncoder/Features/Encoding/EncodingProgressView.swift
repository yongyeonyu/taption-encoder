import SwiftUI

struct EncodingProgressView: View {
    var state: HomeScreenState
    var onStart: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ProgressCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                    }
                    Spacer(minLength: 12)
                    if let progress = state.progress {
                        Text(progress.percentText)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: state.progress?.fractionCompleted ?? 0)
                    .progressViewStyle(.linear)

                if let progress = state.progress {
                    HStack(spacing: 10) {
                        Label(formatTime(progress.elapsedTime), systemImage: "timer")
                        Label(formatRemainingTime(progress.estimatedRemainingTime), systemImage: "hourglass")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                actionButton
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if state.canStartEncoding {
            Button {
                onStart()
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                onCancel()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!state.canCancel)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        let minutes = wholeSeconds / 60
        let seconds = wholeSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatRemainingTime(_ seconds: TimeInterval?) -> String {
        guard let seconds else {
            return "--:--"
        }
        return formatTime(seconds)
    }
}
