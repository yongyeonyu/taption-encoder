import SwiftUI

struct OutputSummaryView: View {
    var outputSummary: String
    var backgroundSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Output", systemImage: "video")
                    .font(.headline)
                Spacer()
                Text(outputSummary)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Label(backgroundSummary, systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
