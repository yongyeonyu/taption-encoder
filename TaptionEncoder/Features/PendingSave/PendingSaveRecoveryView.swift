import SwiftUI

struct PendingSaveRecoveryView: View {
    var job: PendingSaveJob
    var onRetry: () -> Void
    var onReset: () -> Void

    var body: some View {
        StatusBanner(
            title: "Pending save",
            message: "\(job.sourceName) is ready. Save it without re-encoding.",
            systemImage: "arrow.down.doc"
        ) {
            HStack(spacing: 10) {
                Button {
                    onRetry()
                } label: {
                    Label("Watch Ad & Save", systemImage: "play.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onReset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
