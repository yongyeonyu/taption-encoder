import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @State private var isFileImporterPresented = false

    init(environment: AppEnvironment = .phase0) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(environment: environment))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    bannerPlaceholder
                    header

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
                .padding(20)
                .frame(maxWidth: 430)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Taption Encoder")
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
        }
        .navigationViewStyle(.stack)
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

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "film.stack")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.tint)

            Text(viewModel.appName)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text(viewModel.subtitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HomeView()
}
