import SwiftUI

struct PendingSaveRecoveryView: View {
    var job: PendingSaveJob
    var onRetry: () -> Void
    var onReset: () -> Void

    var body: some View {
        StatusBanner(
            title: "Pending save",
            message: message,
            systemImage: "arrow.down.doc"
        ) {
            HStack(spacing: 10) {
                Button {
                    onRetry()
                } label: {
                    Label(primaryButtonTitle, systemImage: primaryButtonImage)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
                .background(TaptionTheme.accent)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.accent.opacity(0.65), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    onReset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(TaptionTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
                .background(TaptionTheme.elevatedSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var message: String {
        if let saveGateMessage = job.saveGateMessage {
            return saveGateMessage
        }
        if job.state.requiresRewardedAd {
            return "\(job.sourceName) is ready. Watch one rewarded ad to save this video."
        }
        return "\(job.sourceName) is ready. The rewarded ad is complete, so it can be saved now."
    }

    private var primaryButtonTitle: String {
        job.state.requiresRewardedAd ? "Watch Ad & Save" : "Save"
    }

    private var primaryButtonImage: String {
        job.state.requiresRewardedAd ? "play.rectangle" : "square.and.arrow.down"
    }
}
