import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @State private var isFileImporterPresented = false

    init(environment: AppEnvironment = .phase0) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(environment: environment))
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 760

            VStack(spacing: isCompact ? 10 : 14) {
                bannerPlaceholder
                header(isCompact: isCompact)

                SourceActionBar(
                    canSelectSource: viewModel.state.canSelectSource,
                    canReset: viewModel.state.canReset,
                    onFiles: { isFileImporterPresented = true },
                    onPhotos: { viewModel.startPhotosFlow() },
                    onReset: { viewModel.reset() }
                )

                EncoderPathInfoView(
                    title: viewModel.encoderPathTitle,
                    detail: viewModel.encoderPathDetail,
                    systemImage: viewModel.encoderPathSystemImage
                )

                OutputSummaryView(
                    outputSummary: viewModel.outputSummary,
                    backgroundSummary: viewModel.backgroundSummary
                )

                if let pendingJob = viewModel.state.pendingSaveJob {
                    PendingSaveRecoveryView(
                        job: pendingJob,
                        onRetry: { viewModel.retryPendingSave() },
                        onReset: { viewModel.reset() }
                    )
                }

                EncodingProgressView(
                    state: viewModel.state,
                    onCancel: { viewModel.cancel() }
                )

                if viewModel.state.completedTemporaryOutput != nil {
                    Button {
                        viewModel.saveCompletedTemporaryOutput()
                    } label: {
                        Label("Watch Ad & Save", systemImage: "play.rectangle")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, isCompact ? 16 : 20)
            .padding(.vertical, isCompact ? 10 : 16)
            .frame(maxWidth: 430)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.startFilesFlow(url: url)
                }
            case .failure(let error):
                viewModel.fail(message: error.localizedDescription)
            }
        }
        .task {
            await viewModel.restorePendingSavesIfNeeded()
        }
    }

    private var bannerPlaceholder: some View {
        Text("Ad banner")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
            )
            .accessibilityLabel("Ad banner placeholder")
    }

    private func header(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 4 : 6) {
            Image(systemName: "film.stack")
                .font(.system(size: isCompact ? 34 : 42, weight: .semibold))
                .foregroundStyle(.tint)

            Text(viewModel.subtitle)
                .font((isCompact ? Font.headline : Font.title3).weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HomeView()
}
