import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: HomeScreenState
    @Published var preferredEncoderMode: TaptionEncoderMode

    private let environment: AppEnvironment
    private var activeTask: Task<Void, Never>?
    private var hasRestoredPendingSaves = false
    private var securityScopedURL: URL?
    private var isAccessingSecurityScopedURL = false

    init(environment: AppEnvironment = .phase0) {
        self.environment = environment
        self.state = .idle
        self.preferredEncoderMode = environment.configuration.defaultEncoderMode
    }

    deinit {
        activeTask?.cancel()
    }

    var appName: String {
        environment.configuration.appName
    }

    var subtitle: String {
        "AV1 to H.265"
    }

    var outputSummary: String {
        "H.265 / \(environment.configuration.defaultOutputContainer.defaultFileExtension.uppercased()) / same folder + \(environment.configuration.outputSuffix)"
    }

    var encoderModeSummary: String {
        switch preferredEncoderMode {
        case .automatic:
            return "Automatic"
        case .hardware:
            return "Hardware"
        case .software:
            return "Software"
        }
    }

    var encoderRecommendation: String {
        switch preferredEncoderMode {
        case .automatic:
            return "Automatic uses hardware first, then falls back when needed."
        case .hardware:
            return "Hardware is preferred; unsupported devices fall back automatically."
        case .software:
            return "Software fallback is slower but keeps older devices supported."
        }
    }

    var backgroundSummary: String {
        "Keep the app open on iOS 15-25. Background encoding can be offered on iOS 26+."
    }

    var canEditEncoderMode: Bool {
        !state.isBusy
    }

    func restorePendingSavesIfNeeded() async {
        guard !hasRestoredPendingSaves else {
            return
        }
        hasRestoredPendingSaves = true

        do {
            guard let pendingState = try await environment.pendingSaveStore.loadPendingStates().first else {
                return
            }
            state = .pendingSave(makePendingSaveJob(from: pendingState))
        } catch {
            state = .failed(HomeEncodingError(
                title: "Restore failed",
                message: error.localizedDescription
            ))
        }
    }

    func startFilesFlow(url: URL) {
        let source = HomeSelectedSource(
            kind: .files,
            displayName: url.lastPathComponent,
            url: url
        )
        beginSecurityScopedAccessIfNeeded(for: url)
        startEncodingFlow(source: source)
    }

    func startPhotosFlow() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Photos_AV1_sample")
            .appendingPathExtension("mov")
        let source = HomeSelectedSource(
            kind: .photos,
            displayName: "Photos video",
            url: url
        )
        startEncodingFlow(source: source)
    }

    func retryPendingSave() {
        guard let job = state.pendingSaveJob else {
            return
        }
        savePendingJob(job)
    }

    func saveCompletedTemporaryOutput() {
        guard let output = state.completedTemporaryOutput else {
            return
        }
        let job = PendingSaveJob(sourceName: output.sourceName, state: output.pendingSaveState)
        savePendingJob(job)
    }

    func reset() {
        guard state.canReset else {
            return
        }
        let pendingStateID = state.pendingSaveJob?.id
            ?? state.completedTemporaryOutput?.pendingSaveState.id
        activeTask?.cancel()
        activeTask = nil
        state = .idle
        stopSecurityScopedAccess()

        if let pendingStateID {
            Task {
                try? await environment.pendingSaveStore.removePendingState(id: pendingStateID)
            }
        }
    }

    func cancel() {
        guard state.canCancel else {
            return
        }
        state = .cancelling
        activeTask?.cancel()
    }

    func fail(message: String) {
        activeTask?.cancel()
        activeTask = nil
        state = .failed(HomeEncodingError(title: "Import failed", message: message))
    }

    private func startEncodingFlow(source: HomeSelectedSource) {
        guard state.canSelectSource else {
            return
        }

        activeTask?.cancel()
        state = .importing(source)

        activeTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try Task.checkCancellation()
                state = .inspecting(source)

                let temporaryOutputURL = makeTemporaryOutputURL(for: source)
                let core = TaptionVideoCore(services: environment.videoCoreServices)
                let job = try await core.prepareSingleAssetHEVCJob(
                    sourceURL: source.url,
                    temporaryOutputURL: temporaryOutputURL,
                    preferredMode: preferredEncoderMode,
                    savePolicy: TaptionSavePolicy(
                        destination: source.kind == .photos ? .photosLibrary : .sourceFolder,
                        saveGate: .rewardedAdBeforeFinalSave,
                        namingPolicy: TaptionOutputNamingPolicy(suffix: environment.configuration.outputSuffix),
                        shouldRestorePendingSaveOnLaunch: true
                    )
                )

                try Task.checkCancellation()
                state = .storageChecking(source)
                try Task.checkCancellation()

                guard job.storageRequirement.hasEnoughSpace else {
                    state = .storageBlocked(StorageIssue(
                        requiredBytes: job.storageRequirement.requiredWorkingBytes,
                        availableBytes: job.storageRequirement.availableBytes,
                        message: "Free up storage before encoding this video."
                    ))
                    activeTask = nil
                    return
                }

                let result = try await core.encodePreparedJob(job) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            return
                        }
                        self.state = .encoding(EncodingProgressSnapshot(
                            stage: progress.stage,
                            fractionCompleted: progress.fractionCompleted,
                            elapsedTime: progress.elapsedTime,
                            estimatedRemainingTime: progress.estimatedRemainingTime,
                            backendLabel: self.backendLabel(for: self.preferredEncoderMode)
                        ))
                    }
                }

                try Task.checkCancellation()

                guard let pendingState = result.pendingSaveState else {
                    throw TaptionVideoCoreError.missingTemporaryOutputURL
                }

                state = .waitingForReward(CompletedTemporaryOutput(
                    planID: result.planID,
                    sourceName: source.displayName,
                    temporaryOutputURL: result.temporaryOutputURL,
                    finalOutputURL: result.finalOutputURL,
                    pendingSaveState: pendingState,
                    usedEncoderMode: result.usedMode,
                    usedBackend: result.usedBackend
                ))
                activeTask = nil
            } catch is CancellationError {
                state = .cancelled
                activeTask = nil
                stopSecurityScopedAccess()
            } catch let error as TaptionVideoCoreError {
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                activeTask = nil
                stopSecurityScopedAccess()
            } catch {
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                activeTask = nil
                stopSecurityScopedAccess()
            }
        }
    }

    private func savePendingJob(_ job: PendingSaveJob) {
        guard !state.isBusy else {
            return
        }

        activeTask?.cancel()
        state = .saving(job)

        activeTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                let isAuthorized = try await environment.adGate.authorizeFinalSave(for: job.state)

                if isAuthorized {
                    let savedURL = try finalizeSave(for: job.state)
                    try await environment.pendingSaveStore.removePendingState(id: job.state.id)
                    let displayName = savedURL.lastPathComponent
                    let destination = destinationDescription(for: job.state)
                    state = .completed(SavedOutput(
                        displayName: displayName,
                        destinationDescription: destination
                    ))
                    stopSecurityScopedAccess()
                } else {
                    state = .pendingSave(job)
                }
                activeTask = nil
            } catch is CancellationError {
                state = .pendingSave(job)
                activeTask = nil
            } catch {
                state = .failed(HomeEncodingError(
                    title: "Save failed",
                    message: error.localizedDescription
                ))
                activeTask = nil
            }
        }
    }

    private func makeTemporaryOutputURL(for source: HomeSelectedSource) -> URL {
        let baseName = source.url.deletingPathExtension().lastPathComponent
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName + environment.configuration.outputSuffix)
            .appendingPathExtension(environment.configuration.defaultOutputContainer.defaultFileExtension)
    }

    private func finalizeSave(for state: TaptionPendingSaveState) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: state.temporaryOutputURL.path) else {
            throw TaptionVideoCoreError.finalSaveFailed("The temporary H.265 output is missing. Please encode again.")
        }

        switch state.saveDestination {
        case .sourceFolder:
            guard let finalOutputURL = state.finalOutputURL else {
                throw TaptionVideoCoreError.finalSaveFailed("The final output path is missing.")
            }
            try fileManager.createDirectory(
                at: finalOutputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? fileManager.removeItem(at: finalOutputURL)
            try fileManager.copyItem(at: state.temporaryOutputURL, to: finalOutputURL)
            return finalOutputURL
        case .photosLibrary:
            throw TaptionVideoCoreError.finalSaveFailed("Photos saving is not enabled in this build yet.")
        case .temporaryOnly:
            return state.temporaryOutputURL
        }
    }

    private func makePendingSaveJob(from state: TaptionPendingSaveState) -> PendingSaveJob {
        let sourceName = state.finalOutputURL?.lastPathComponent
            ?? state.temporaryOutputURL.lastPathComponent
        return PendingSaveJob(sourceName: sourceName, state: state)
    }

    private func backendLabel(for mode: TaptionEncoderMode) -> String {
        switch mode {
        case .automatic:
            return "Hardware-first Encoder"
        case .hardware:
            return "Hardware Encoder"
        case .software:
            return "Software Encoder"
        }
    }

    private func beginSecurityScopedAccessIfNeeded(for url: URL) {
        stopSecurityScopedAccess()
        let didStartAccess = url.startAccessingSecurityScopedResource()
        securityScopedURL = didStartAccess ? url : nil
        isAccessingSecurityScopedURL = didStartAccess
    }

    private func stopSecurityScopedAccess() {
        if isAccessingSecurityScopedURL {
            securityScopedURL?.stopAccessingSecurityScopedResource()
        }
        securityScopedURL = nil
        isAccessingSecurityScopedURL = false
    }

    private func destinationDescription(for state: TaptionPendingSaveState) -> String {
        switch state.saveDestination {
        case .sourceFolder:
            return "source folder"
        case .photosLibrary:
            return "Photos"
        case .temporaryOnly:
            return "temporary storage"
        }
    }
}
