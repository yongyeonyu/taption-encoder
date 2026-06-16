import Foundation
import Photos

private enum PendingSaveConflictResolution: Equatable {
    case prompt
    case overwrite
    case saveAsUnique
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: HomeScreenState
    @Published private(set) var selectedOutput: TaptionOutputSelection
    @Published private(set) var saveConflictPrompt: PendingSaveConflictPrompt?

    private let environment: AppEnvironment
    private var activeTask: Task<Void, Never>?
    private var folderBatch: FolderEncodingBatch?
    private var currentReview: PreparedEncodingReview?
    private var pendingSaveQueue: [PendingSaveJob] = []
    private var lastBatchFileCards: [EncodingFileCardSnapshot] = []
    private var selectionInspectionTask: Task<Void, Never>?
    private var hasRestoredPendingSaves = false
    private var securityScopedURLs: [URL] = []

    init(environment: AppEnvironment = .phase0) {
        self.environment = environment
        self.selectedOutput = TaptionOutputSelection(
            videoCodec: environment.configuration.defaultOutputCodec,
            container: environment.configuration.defaultOutputContainer
        )
        self.state = .idle
        self.saveConflictPrompt = nil
        AppLogger.info(
            "HomeViewModel initialized",
            category: .app,
            metadata: ["appName": environment.configuration.appName]
        )
    }

    deinit {
        AppLogger.info("HomeViewModel deinitialized", category: .app)
        activeTask?.cancel()
    }

    var appName: String {
        environment.configuration.appName
    }

    var subtitle: String {
        "Taption Encoder"
    }

    var outputSummary: String {
        "\(selectedOutput.summary) / same folder + \(environment.configuration.outputSuffix)"
    }

    var outputCodecOptions: [TaptionVideoCodec] {
        TaptionOutputSelection.videoCodecOptions
    }

    var outputAudioCodecOptions: [TaptionAudioCodec] {
        TaptionOutputSelection.audioCodecOptions
    }

    var outputContainerOptions: [TaptionVideoContainer] {
        TaptionOutputSelection.containerOptions
    }

    var selectedOutputStatusText: String {
        selectedOutput.implementationState.shortDisplayName
    }

    var selectedVideoOutputStatusText: String {
        selectedOutput.videoImplementationState.shortDisplayName
    }

    var selectedAudioOutputStatusText: String {
        selectedOutput.audioImplementationState.shortDisplayName
    }

    var canChangeOutputSelection: Bool {
        !state.isBusy && pendingSaveQueue.isEmpty
    }

    var encoderPathTitle: String {
        if let output = state.completedTemporaryOutput {
            return codecPathTitle(mode: output.usedEncoderMode)
        }
        if case .completed = state {
            return "Codec Path: Complete"
        }
        return "Codec Path: Automatic"
    }

    var encoderPathDetail: String {
        if let output = state.completedTemporaryOutput {
            return codecPathDetail(mode: output.usedEncoderMode, backend: output.usedBackend)
        }
        return "The app checks this device and automatically uses hardware first, then software fallback when needed."
    }

    var encoderPathSystemImage: String {
        if let output = state.completedTemporaryOutput {
            switch output.usedEncoderMode {
            case .hardware:
                return "cpu"
            case .software:
                return "gearshape.2"
            case .automatic:
                return "wand.and.stars"
            }
        }
        return "wand.and.stars"
    }

    var backgroundSummary: String {
        "Keep the app open on iOS 18-25. Background encoding can be offered on iOS 26+."
    }

    var bannerAdUnitID: String {
        environment.bannerAdProvider.bannerAdUnitID
    }

    func selectOutputCodec(_ codec: TaptionVideoCodec) {
        guard canChangeOutputSelection else {
            AppLogger.warning(
                "Output codec change ignored while flow is busy",
                category: .ui,
                metadata: ["codec": codec.rawValue]
            )
            return
        }
        guard selectedOutput.videoCodec != codec else {
            return
        }

        selectedOutput.videoCodec = codec
        AppLogger.info(
            "Output codec selected",
            category: .ui,
            metadata: [
                "codec": codec.rawValue,
                "state": selectedOutput.implementationState.rawValue
            ]
        )
        refreshPreparedSourceAfterOutputChange()
    }

    func selectOutputAudioCodec(_ codec: TaptionAudioCodec) {
        guard canChangeOutputSelection else {
            AppLogger.warning(
                "Output audio codec change ignored while flow is busy",
                category: .ui,
                metadata: ["codec": codec.rawValue]
            )
            return
        }
        guard selectedOutput.audioCodec != codec else {
            return
        }

        selectedOutput.audioCodec = codec
        AppLogger.info(
            "Output audio codec selected",
            category: .ui,
            metadata: [
                "codec": codec.rawValue,
                "state": selectedOutput.audioImplementationState.rawValue
            ]
        )
        refreshPreparedSourceAfterOutputChange()
    }

    func selectOutputContainer(_ container: TaptionVideoContainer) {
        guard canChangeOutputSelection else {
            AppLogger.warning(
                "Output container change ignored while flow is busy",
                category: .ui,
                metadata: ["container": container.rawValue]
            )
            return
        }
        guard selectedOutput.container != container else {
            return
        }

        selectedOutput.container = container
        AppLogger.info(
            "Output container selected",
            category: .ui,
            metadata: [
                "container": container.rawValue,
                "state": selectedOutput.implementationState.rawValue
            ]
        )
        refreshPreparedSourceAfterOutputChange()
    }

    func outputCodecMenuTitle(_ codec: TaptionVideoCodec) -> String {
        "\(codec.displayName) - \(outputCodecStatusText(codec))"
    }

    func outputAudioCodecMenuTitle(_ codec: TaptionAudioCodec) -> String {
        "\(codec.displayName) - \(outputAudioCodecStatusText(codec))"
    }

    func outputContainerMenuTitle(_ container: TaptionVideoContainer) -> String {
        "\(container.defaultFileExtension.uppercased()) - \(outputContainerStatusText(container))"
    }

    private func outputCodecStatusText(_ codec: TaptionVideoCodec) -> String {
        TaptionCodecOutputCatalog.implementationState(
            videoCodec: codec,
            container: selectedOutput.container
        ).shortDisplayName
    }

    private func outputAudioCodecStatusText(_ codec: TaptionAudioCodec) -> String {
        TaptionAudioCodecOutputCatalog.implementationState(
            audioCodec: codec,
            container: selectedOutput.container
        ).shortDisplayName
    }

    private func outputContainerStatusText(_ container: TaptionVideoContainer) -> String {
        let videoState = TaptionCodecOutputCatalog.implementationState(
            videoCodec: selectedOutput.videoCodec,
            container: container
        )
        let audioState = TaptionAudioCodecOutputCatalog.implementationState(
            audioCodec: selectedOutput.audioCodec,
            container: container
        )
        if videoState == audioState {
            return videoState.shortDisplayName
        }
        return "\(videoState.shortDisplayName) / \(audioState.shortDisplayName)"
    }

    var pendingSaveRecoveryJob: PendingSaveJob? {
        if let job = state.pendingSaveJob {
            return job
        }
        if case .failed = state {
            return pendingSaveQueue.first
        }
        return nil
    }

    var fileCardSnapshots: [EncodingFileCardSnapshot] {
        if let folderBatch {
            return folderBatch.cardSnapshots()
        }

        if !pendingSaveQueue.isEmpty,
           pendingSaveRecoveryJob != nil {
            return pendingSaveQueueCardSnapshots()
        }

        switch state {
        case .completed(_) where !lastBatchFileCards.isEmpty:
            return lastBatchFileCards
        case .importing(let source):
            return [fileCard(
                source: source,
                statusText: "Importing",
                detailText: "Opening the selected video.",
                progress: nil,
                isActive: true,
                isSelected: true,
                isEnabled: true
            )]
        case .inspecting(let source):
            return [fileCard(
                source: source,
                statusText: "Inspecting",
                detailText: "Reading codec and track details.",
                progress: nil,
                isActive: true,
                isSelected: true,
                isEnabled: true
            )]
        case .storageChecking(let source):
            return [fileCard(
                source: source,
                statusText: "Checking Storage",
                detailText: "Confirming temporary and final output space.",
                progress: nil,
                isActive: true,
                isSelected: true,
                isEnabled: true
            )]
        case .readyToStart(let review):
            return [fileCard(
                source: review.source,
                videoInfo: review.videoInfo,
                statusText: review.videoInfo.readinessStatusText,
                detailText: review.videoInfo.isRouteEncodable ? "Ready to encode." : review.videoInfo.codecPathDetail,
                progress: nil,
                isActive: true,
                isSelected: true,
                isEnabled: true
            )]
        case .encoding(let progress):
            if let currentReview {
                return [fileCard(
                    source: currentReview.source,
                    videoInfo: currentReview.videoInfo,
                    statusText: progress.stageTitle,
                    detailText: progress.backendLabel,
                    progress: progress,
                    isActive: true,
                    isSelected: true,
                    isEnabled: true
                )]
            }
            return []
        case .waitingForReward(let output):
            return [fileCard(
                sourceName: output.sourceName,
                sourceKind: currentReview?.source.kind ?? .files,
                videoInfo: currentReview?.videoInfo,
                statusText: "Waiting to Save",
                detailText: "Watch the rewarded ad to save the encoded video.",
                progress: completedProgressSnapshot(label: codecPathTitle(mode: output.usedEncoderMode)),
                isActive: true,
                isSelected: true,
                isEnabled: true
            )]
        case .saving(let job):
            return [fileCard(
                sourceName: job.sourceName,
                sourceKind: currentReview?.source.kind ?? .files,
                videoInfo: currentReview?.videoInfo,
                statusText: "Saving",
                detailText: "Writing the completed H.265 output.",
                progress: completedProgressSnapshot(label: "Saving"),
                isActive: true,
                isSelected: true,
                isEnabled: true
            )]
        case .pendingSave(let job):
            return [fileCard(
                sourceName: job.sourceName,
                sourceKind: currentReview?.source.kind ?? .files,
                videoInfo: currentReview?.videoInfo,
                statusText: "Pending Save",
                detailText: "This output can be saved without re-encoding.",
                progress: completedProgressSnapshot(label: "Pending Save"),
                isActive: true,
                isSelected: true,
                isEnabled: true
            )]
        case .completed(let output):
            return [fileCard(
                sourceName: output.displayName,
                sourceKind: .files,
                videoInfo: nil,
                statusText: "Saved",
                detailText: output.detailOverride ?? output.destinationDescription,
                progress: completedProgressSnapshot(label: "Saved"),
                isActive: false,
                isSelected: true,
                isEnabled: true
            )]
        case .failed(let error):
            return [fileCard(
                sourceName: "Import",
                sourceKind: .files,
                videoInfo: nil,
                statusText: "Failed",
                detailText: error.message,
                progress: nil,
                isActive: false,
                isSelected: true,
                isEnabled: false
            )]
        case .cancelled:
            return [fileCard(
                sourceName: "Encoding",
                sourceKind: .files,
                videoInfo: nil,
                statusText: "Cancelled",
                detailText: "The encoding job was cancelled.",
                progress: nil,
                isActive: false,
                isSelected: true,
                isEnabled: false
            )]
        case .idle, .storageBlocked, .cancelling:
            return []
        }
    }

    func restorePendingSavesIfNeeded() async {
        guard !hasRestoredPendingSaves else {
            return
        }
        hasRestoredPendingSaves = true
        AppLogger.info("Restore pending saves requested", category: .saving)
        await environment.sessionEndAdProvider.preloadSessionEndAd()

        do {
            let pendingStates = try await environment.pendingSaveStore.loadPendingStates()
            let jobs = pendingStates.map(makePendingSaveJob(from:))
            guard let firstJob = jobs.first else {
                AppLogger.info("No pending save found", category: .saving)
                return
            }
            pendingSaveQueue = jobs
            AppLogger.warning(
                "Pending save queue restored",
                category: .saving,
                metadata: [
                    "count": "\(jobs.count)",
                    "first": firstJob.sourceName
                ]
            )
            state = .pendingSave(firstJob)
        } catch {
            AppLogger.error(
                "Restore pending saves failed",
                category: .saving,
                metadata: ["error": error.localizedDescription]
            )
            state = .failed(HomeEncodingError(
                title: "Restore failed",
                message: error.localizedDescription
            ))
        }
    }

    func startFilesFlow(url: URL) {
        AppLogger.info(
            "Single file flow started",
            category: .fileImport,
            metadata: ["name": url.lastPathComponent]
        )
        guard canStartNewSourceFlow() else {
            return
        }
        selectionInspectionTask?.cancel()
        folderBatch = nil
        currentReview = nil
        lastBatchFileCards = []
        let source = HomeSelectedSource(
            kind: .files,
            displayName: url.lastPathComponent,
            url: url
        )
        beginSecurityScopedAccessIfNeeded(for: url)
        prepareEncodingFlow(source: source)
    }

    func startFilesFlow(urls: [URL]) {
        AppLogger.info(
            "Multiple file flow requested",
            category: .fileImport,
            metadata: [
                "count": "\(urls.count)",
                "names": urls.map(\.lastPathComponent).joined(separator: "|")
            ]
        )
        guard canStartNewSourceFlow() else {
            return
        }
        let selectedURLs = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        guard let firstURL = selectedURLs.first else {
            return
        }
        guard selectedURLs.count > 1 else {
            startFilesFlow(url: firstURL)
            return
        }
        guard state.canSelectSource else {
            AppLogger.warning(
                "Multiple file flow ignored because source selection is disabled",
                category: .fileImport,
                metadata: ["state": "\(state)"]
            )
            return
        }

        activeTask?.cancel()
        selectionInspectionTask?.cancel()
        currentReview = nil
        lastBatchFileCards = []
        folderBatch = FolderEncodingBatch(
            folderName: "Selected files",
            sourceKind: .files,
            fileURLs: selectedURLs
        )
        beginSecurityScopedAccessIfNeeded(for: selectedURLs)
        prepareCurrentFolderItem(autoStartAfterPrepare: false)
    }

    func startFolderFlow(url: URL) {
        guard canStartNewSourceFlow() else {
            return
        }
        guard state.canSelectSource else {
            AppLogger.warning(
                "Folder flow ignored because source selection is disabled",
                category: .folderImport,
                metadata: ["name": url.lastPathComponent]
            )
            return
        }

        AppLogger.info(
            "Folder flow started",
            category: .folderImport,
            metadata: ["name": url.lastPathComponent]
        )
        activeTask?.cancel()
        selectionInspectionTask?.cancel()
        currentReview = nil
        lastBatchFileCards = []
        folderBatch = nil
        beginSecurityScopedAccessIfNeeded(for: url)

        do {
            let fileURLs = try videoFileURLs(in: url)
            AppLogger.info(
                "Folder video scan completed",
                category: .folderImport,
                metadata: [
                    "folder": url.lastPathComponent,
                    "count": "\(fileURLs.count)",
                    "names": fileURLs.map(\.lastPathComponent).joined(separator: "|")
                ]
            )
            guard !fileURLs.isEmpty else {
                throw TaptionVideoCoreError.finalSaveFailed("This folder does not contain supported video files.")
            }

            folderBatch = FolderEncodingBatch(
                folderURL: url,
                folderName: url.lastPathComponent,
                sourceKind: .folder,
                fileURLs: fileURLs
            )
            preflightCurrentBatchThenPrepareFirst(displayName: url.lastPathComponent)
        } catch {
            AppLogger.error(
                "Folder flow failed",
                category: .folderImport,
                metadata: [
                    "name": url.lastPathComponent,
                    "error": error.localizedDescription
                ]
            )
            stopSecurityScopedAccess()
            state = .failed(HomeEncodingError(
                title: "Folder failed",
                message: error.localizedDescription
            ))
            requestSessionEndAd(reason: .failedEncoding)
        }
    }

    func startPhotosFlow(url: URL, displayName: String) {
        AppLogger.info(
            "Photos flow started",
            category: .photosImport,
            metadata: ["name": displayName]
        )
        guard canStartNewSourceFlow() else {
            return
        }
        selectionInspectionTask?.cancel()
        folderBatch = nil
        currentReview = nil
        lastBatchFileCards = []
        let source = HomeSelectedSource(
            kind: .photos,
            displayName: displayName,
            url: url
        )
        prepareEncodingFlow(source: source)
    }

    func selectFileCard(id: String) {
        guard var batch = folderBatch,
              let selectedURL = batch.fileURLs.first(where: { $0.absoluteString == id }) else {
            AppLogger.warning("File card selection ignored because item was not found", category: .ui)
            return
        }

        let item = batch.itemStates[selectedURL] ?? .queued
        guard item.isEnabled else {
            AppLogger.info(
                "Disabled file card tapped",
                category: .ui,
                metadata: [
                    "name": selectedURL.lastPathComponent,
                    "status": item.statusText
                ]
            )
            return
        }

        AppLogger.info(
            "File card selected",
            category: .ui,
            metadata: ["name": selectedURL.lastPathComponent]
        )
        batch.selectedURL = selectedURL
        folderBatch = batch
        objectWillChange.send()

        guard item.videoInfo == nil,
              !state.isBusy else {
            return
        }

        selectionInspectionTask?.cancel()
        selectionInspectionTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.inspectSelectedBatchItemInfo(url: selectedURL)
        }
    }

    func startPreparedEncoding() {
        guard let review = state.preparedEncodingReview else {
            AppLogger.warning("Start encoding ignored because no prepared review exists", category: .encoding)
            return
        }
        guard review.videoInfo.isRouteEncodable else {
            AppLogger.warning(
                "Start encoding ignored because selected route is not implemented",
                category: .encoding,
                metadata: [
                    "name": review.source.displayName,
                    "output": review.videoInfo.outputSummary,
                    "detail": review.videoInfo.codecPathDetail
                ]
            )
            return
        }

        AppLogger.info(
            "Start encoding requested",
            category: .encoding,
            metadata: [
                "name": review.source.displayName,
                "plan": review.job.plan.id.uuidString
            ]
        )
        activeTask?.cancel()
        state = .encoding(startingProgressSnapshot(for: review))

        activeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await environment.sessionEndAdProvider.showSessionEndAd(reason: .startingEncoding)

            do {
                try Task.checkCancellation()
                startEncoding(review: review, allowsBusyState: true)
            } catch {
                state = .cancelled
                activeTask = nil
                folderBatch = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .cancelledEncoding)
            }
        }
    }

    func retryPendingSave() {
        guard let job = pendingSaveRecoveryJob else {
            return
        }
        saveConflictPrompt = nil
        savePendingJob(job)
    }

    func saveCompletedTemporaryOutput() {
        guard let output = state.completedTemporaryOutput else {
            AppLogger.warning("Save requested without completed temporary output", category: .saving)
            return
        }
        AppLogger.info(
            "Save completed temporary output requested",
            category: .saving,
            metadata: [
                "source": output.sourceName,
                "plan": output.planID.uuidString
            ]
        )
        let job = PendingSaveJob(sourceName: output.sourceName, state: output.pendingSaveState)
        savePendingJob(job)
    }

    func overwriteExistingPendingSave() {
        guard let prompt = saveConflictPrompt else {
            return
        }
        saveConflictPrompt = nil
        var job = prompt.job
        job.saveGateMessage = nil
        AppLogger.info(
            "User chose to overwrite existing save destination",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "destination": prompt.existingURL.lastPathComponent
            ]
        )
        savePendingJob(job, conflictResolution: .overwrite)
    }

    func savePendingOutputAsNewFile() {
        guard let prompt = saveConflictPrompt else {
            return
        }
        saveConflictPrompt = nil
        var state = prompt.job.state
        state.finalOutputURL = prompt.suggestedURL
        var job = PendingSaveJob(sourceName: prompt.job.sourceName, state: state)
        job.saveGateMessage = "Saving as \(prompt.suggestedURL.lastPathComponent)."
        AppLogger.info(
            "User chose to save pending output as a new file",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "destination": prompt.suggestedURL.lastPathComponent
            ]
        )
        savePendingJob(job, conflictResolution: .saveAsUnique)
    }

    func dismissSaveConflictPrompt() {
        guard saveConflictPrompt != nil else {
            return
        }
        AppLogger.info("Save conflict prompt dismissed", category: .saving)
        saveConflictPrompt = nil
    }

    func reset() {
        guard state.canReset else {
            AppLogger.info("Reset ignored because state cannot reset", category: .ui)
            return
        }
        AppLogger.info("Reset requested", category: .ui)
        let pendingStatesToReset = resetPendingStates()
        activeTask?.cancel()
        activeTask = nil
        selectionInspectionTask?.cancel()
        selectionInspectionTask = nil
        currentReview = nil
        saveConflictPrompt = nil
        pendingSaveQueue = []
        lastBatchFileCards = []
        folderBatch = nil
        state = .idle
        stopSecurityScopedAccess()

        for pendingState in pendingStatesToReset {
            Task {
                try? await environment.pendingSaveStore.removePendingState(id: pendingState.id)
                try? removeTemporaryOutput(for: pendingState)
            }
        }

        Task {
            removeAllPendingTemporaryOutputs()
        }
    }

    func cancel() {
        guard state.canCancel else {
            AppLogger.info("Cancel ignored because state cannot cancel", category: .ui)
            return
        }
        AppLogger.warning("Cancel requested", category: .encoding)
        state = .cancelling
        activeTask?.cancel()
    }

    func fail(message: String) {
        AppLogger.error(
            "Home flow failed",
            category: .app,
            metadata: ["message": message]
        )
        activeTask?.cancel()
        activeTask = nil
        selectionInspectionTask?.cancel()
        selectionInspectionTask = nil
        currentReview = nil
        lastBatchFileCards = []
        folderBatch = nil
        state = .failed(HomeEncodingError(title: "Import failed", message: message))
        stopSecurityScopedAccess()
    }

    private func prepareEncodingFlow(
        source: HomeSelectedSource,
        autoStartAfterPrepare: Bool = false,
        allowsBusyState: Bool = false
    ) {
        guard state.canSelectSource || autoStartAfterPrepare || allowsBusyState else {
            AppLogger.warning(
                "Prepare encoding ignored because state is busy",
                category: .encoding,
                metadata: [
                    "name": source.displayName,
                    "autoStart": "\(autoStartAfterPrepare)",
                    "allowsBusyState": "\(allowsBusyState)"
                ]
            )
            return
        }

        AppLogger.info(
            "Prepare encoding started",
            category: .encoding,
            metadata: [
                "name": source.displayName,
                "kind": source.kind.rawValue,
                "autoStart": "\(autoStartAfterPrepare)"
            ]
        )
        activeTask?.cancel()
        markBatchItem(
            source.url,
            statusText: "Importing",
            detailText: "Opening the selected video.",
            progress: nil,
            isActive: true
        )
        state = .importing(source)

        activeTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try Task.checkCancellation()
                markBatchItem(
                    source.url,
                    statusText: "Inspecting",
                    detailText: "Reading codec and track details.",
                    progress: nil,
                    isActive: true
                )
                state = .inspecting(source)

                let temporaryOutputURL = makeTemporaryOutputURL(for: source)
                let core = TaptionVideoCore(services: environment.videoCoreServices)
                let job = try await core.prepareSingleAssetJob(
                    sourceURL: source.url,
                    temporaryOutputURL: temporaryOutputURL,
                    outputPolicy: selectedOutput.outputPolicy,
                    preferredMode: .automatic,
                    savePolicy: TaptionSavePolicy(
                        destination: source.kind == .photos ? .photosLibrary : .sourceFolder,
                        saveGate: .rewardedAdBeforeFinalSave,
                        namingPolicy: TaptionOutputNamingPolicy(suffix: environment.configuration.outputSuffix),
                        shouldRestorePendingSaveOnLaunch: true
                    )
                )
                AppLogger.info(
                    "Prepare encoding job created",
                    category: .mediaInspection,
                    metadata: [
                        "name": source.displayName,
                        "codec": job.asset.videoTrack?.codec.displayName ?? "unknown",
                        "container": job.asset.container.defaultFileExtension,
                        "plan": job.plan.id.uuidString,
                        "temporary": temporaryOutputURL.lastPathComponent
                    ]
                )

                try Task.checkCancellation()
                markBatchItem(
                    source.url,
                    statusText: "Checking Storage",
                    detailText: "Confirming temporary and final output space.",
                    progress: nil,
                    isActive: true
                )
                state = .storageChecking(source)
                try Task.checkCancellation()

                let canEncodeSelectedOutput = job.routeSelection.isEncodableNow && selectedOutput.isImplementedNow
                guard !canEncodeSelectedOutput || job.storageRequirement.hasEnoughSpace else {
                    AppLogger.error(
                        "Storage check blocked encoding",
                        category: .storage,
                        metadata: [
                            "name": source.displayName,
                            "required": "\(job.storageRequirement.requiredWorkingBytes)",
                            "available": job.storageRequirement.availableBytes.map(String.init) ?? "unknown"
                        ]
                    )
                    markBatchItem(
                        source.url,
                        statusText: "Blocked",
                        detailText: "Free up storage before encoding this video.",
                        progress: nil,
                        isActive: false
                    )
                    if handleFolderItemFailure(
                        source: source,
                        errorMessage: "Free up storage before encoding this video."
                    ) {
                        return
                    }
                    state = .storageBlocked(StorageIssue(
                        requiredBytes: job.storageRequirement.requiredWorkingBytes,
                        availableBytes: job.storageRequirement.availableBytes,
                        message: "Free up storage before encoding this video."
                    ))
                    activeTask = nil
                    return
                }

                let review = PreparedEncodingReview(
                    source: source,
                    job: job,
                    videoInfo: makeLoadedVideoInfo(source: source, job: job),
                    folderQueue: folderBatch?.snapshot(currentFileName: source.displayName)
                )
                currentReview = review
                AppLogger.info(
                    "Prepare encoding ready",
                    category: .encoding,
                    metadata: [
                        "name": source.displayName,
                        "plan": job.plan.id.uuidString
                    ]
                )
                markBatchItem(
                    source.url,
                    asset: job.asset,
                    videoInfo: review.videoInfo,
                    statusText: review.videoInfo.readinessStatusText,
                    detailText: review.videoInfo.isRouteEncodable ? "Ready to encode." : review.videoInfo.codecPathDetail,
                    progress: nil,
                    isActive: true
                )

                activeTask = nil
                if autoStartAfterPrepare {
                    startEncoding(review: review, allowsBusyState: true)
                } else {
                    state = .readyToStart(review)
                }
            } catch is CancellationError {
                AppLogger.warning(
                    "Prepare encoding cancelled",
                    category: .encoding,
                    metadata: ["name": source.displayName]
                )
                markBatchItem(
                    source.url,
                    statusText: "Cancelled",
                    detailText: "The encoding job was cancelled.",
                    progress: nil,
                    isActive: false
                )
                state = .cancelled
                activeTask = nil
                currentReview = nil
                folderBatch = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .cancelledEncoding)
            } catch let error as TaptionVideoCoreError {
                AppLogger.error(
                    "Prepare encoding failed with TaptionVideoCoreError",
                    category: .encoding,
                    metadata: [
                        "name": source.displayName,
                        "error": error.localizedDescription
                    ]
                )
                markBatchItem(
                    source.url,
                    statusText: "Failed",
                    detailText: error.localizedDescription,
                    progress: nil,
                    isActive: false
                )
                if handleFolderItemFailure(source: source, errorMessage: error.localizedDescription) {
                    return
                }
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                activeTask = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .failedEncoding)
            } catch {
                AppLogger.error(
                    "Prepare encoding failed",
                    category: .encoding,
                    metadata: [
                        "name": source.displayName,
                        "error": error.localizedDescription
                    ]
                )
                markBatchItem(
                    source.url,
                    statusText: "Failed",
                    detailText: error.localizedDescription,
                    progress: nil,
                    isActive: false
                )
                if handleFolderItemFailure(source: source, errorMessage: error.localizedDescription) {
                    return
                }
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                activeTask = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .failedEncoding)
            }
        }
    }

    private func startEncoding(review: PreparedEncodingReview, allowsBusyState: Bool = false) {
        guard allowsBusyState || !state.isBusy else {
            AppLogger.warning(
                "Start encoding ignored because state is busy",
                category: .encoding,
                metadata: ["name": review.source.displayName]
            )
            return
        }

        AppLogger.info(
            "Encoding task started",
            category: .encoding,
            metadata: [
                "name": review.source.displayName,
                "plan": review.job.plan.id.uuidString
            ]
        )
        activeTask?.cancel()
        currentReview = review
        let initialProgress = EncodingProgressSnapshot(
            stage: .queued,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil,
            backendLabel: review.videoInfo.codecPathTitle,
            outputSummary: review.videoInfo.outputSummary
        )
        markBatchItem(
            review.source.url,
            videoInfo: review.videoInfo,
            statusText: initialProgress.stageTitle,
            detailText: initialProgress.backendLabel,
            progress: initialProgress,
            isActive: true
        )
        state = .encoding(initialProgress)

        activeTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let core = TaptionVideoCore(services: environment.videoCoreServices)
                var lastLoggedProgressBucket = -1
                let result = try await core.encodePreparedJob(review.job) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            return
                        }
                        let bucket = Int((progress.fractionCompleted * 10).rounded(.down))
                        if bucket != lastLoggedProgressBucket || progress.stage == .waitingForSaveGate {
                            lastLoggedProgressBucket = bucket
                            AppLogger.debug(
                                "Encoding progress",
                                category: .encoding,
                                metadata: [
                                    "name": review.source.displayName,
                                    "stage": progress.stage.rawValue,
                                    "fraction": String(format: "%.3f", progress.fractionCompleted)
                                ]
                            )
                        }
                        let snapshot = self.encodingProgressSnapshot(
                            from: progress,
                            sourceName: review.source.displayName
                        )
                        self.markBatchItem(
                            review.source.url,
                            videoInfo: review.videoInfo,
                            statusText: snapshot.stageTitle,
                            detailText: snapshot.backendLabel,
                            progress: snapshot,
                            isActive: true
                        )
                        self.state = .encoding(snapshot)
                    }
                }

                try Task.checkCancellation()

                guard let pendingState = result.pendingSaveState else {
                    throw TaptionVideoCoreError.missingTemporaryOutputURL
                }
                let restorablePendingState = await pendingSaveStateWithAccessBookmark(
                    pendingState,
                    source: review.source
                )

                let completedProgress = completedProgressSnapshot(label: codecPathTitle(mode: result.usedMode))
                AppLogger.info(
                    "Encoding completed and queued for rewarded save",
                    category: .encoding,
                    metadata: [
                        "name": review.source.displayName,
                        "plan": result.planID.uuidString,
                        "mode": result.usedMode.rawValue,
                        "backend": result.usedBackend.rawValue,
                        "temporary": result.temporaryOutputURL.lastPathComponent
                    ]
                )
                let pendingJob = PendingSaveJob(
                    sourceName: review.source.displayName,
                    state: restorablePendingState
                )
                enqueuePendingSaveJob(pendingJob)
                markBatchItem(
                    review.source.url,
                    videoInfo: review.videoInfo,
                    statusText: folderBatch == nil ? "Waiting to Save" : "Encoded",
                    detailText: codecPathDetail(mode: result.usedMode, backend: result.usedBackend),
                    progress: completedProgress,
                    isActive: folderBatch == nil
                )

                if folderBatch != nil {
                    if handleFolderItemEncoded() {
                        return
                    }
                }

                state = .waitingForReward(CompletedTemporaryOutput(
                    planID: result.planID,
                    sourceName: review.source.displayName,
                    temporaryOutputURL: result.temporaryOutputURL,
                    finalOutputURL: result.finalOutputURL,
                    pendingSaveState: restorablePendingState,
                    usedEncoderMode: result.usedMode,
                    usedBackend: result.usedBackend
                ))
                activeTask = nil
            } catch is CancellationError {
                AppLogger.warning(
                    "Encoding task cancelled",
                    category: .encoding,
                    metadata: ["name": review.source.displayName]
                )
                markBatchItem(
                    review.source.url,
                    videoInfo: review.videoInfo,
                    statusText: "Cancelled",
                    detailText: "The encoding job was cancelled.",
                    progress: nil,
                    isActive: false
                )
                state = .cancelled
                activeTask = nil
                currentReview = nil
                folderBatch = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .cancelledEncoding)
            } catch let error as TaptionVideoCoreError {
                AppLogger.error(
                    "Encoding task failed with TaptionVideoCoreError",
                    category: .encoding,
                    metadata: [
                        "name": review.source.displayName,
                        "error": error.localizedDescription
                    ]
                )
                markBatchItem(
                    review.source.url,
                    videoInfo: review.videoInfo,
                    statusText: "Failed",
                    detailText: error.localizedDescription,
                    progress: nil,
                    isActive: false
                )
                if handleFolderItemFailure(source: review.source, errorMessage: error.localizedDescription) {
                    return
                }
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                activeTask = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .failedEncoding)
            } catch {
                AppLogger.error(
                    "Encoding task failed",
                    category: .encoding,
                    metadata: [
                        "name": review.source.displayName,
                        "error": error.localizedDescription
                    ]
                )
                markBatchItem(
                    review.source.url,
                    videoInfo: review.videoInfo,
                    statusText: "Failed",
                    detailText: error.localizedDescription,
                    progress: nil,
                    isActive: false
                )
                if handleFolderItemFailure(source: review.source, errorMessage: error.localizedDescription) {
                    return
                }
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                activeTask = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .failedEncoding)
            }
        }
    }

    private func savePendingJob(
        _ job: PendingSaveJob,
        conflictResolution: PendingSaveConflictResolution = .prompt
    ) {
        guard !state.isBusy else {
            AppLogger.warning(
                "Save pending job ignored because state is busy",
                category: .saving,
                metadata: ["source": job.sourceName]
            )
            return
        }

        AppLogger.info(
            "Save pending job started",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "id": job.state.id.uuidString,
                "destination": "\(job.state.saveDestination)",
                "rewardedAdRequired": "\(job.state.requiresRewardedAd)"
            ]
        )
        activeTask?.cancel()
        markCurrentSaveItem(
            statusText: "Saving",
            detailText: job.state.requiresRewardedAd
                ? "Waiting for rewarded ad before saving."
                : "Rewarded ad completed. Writing the output.",
            progress: completedProgressSnapshot(label: "Saving"),
            isActive: true
        )
        state = .saving(job)

        activeTask = Task { [weak self] in
            guard let self else {
                return
            }
            var workingJob = job

            do {
                try await Task.sleep(nanoseconds: 300_000_000)

                if workingJob.state.requiresRewardedAd {
                    let adDecision = try await environment.adGate.requestSaveAuthorization(for: workingJob.state)
                    guard adDecision == .allowed else {
                        let gateMessage = saveGateMessage(for: adDecision)
                        workingJob.saveGateMessage = gateMessage
                        updatePendingSaveJob(workingJob)
                        AppLogger.warning(
                            "Rewarded save was not authorized; pending state retained",
                            category: .saving,
                            metadata: [
                                "source": workingJob.sourceName,
                                "decision": adDecision.rawValue
                            ]
                        )
                        markCurrentSaveItem(
                            statusText: "Ad Unavailable",
                            detailText: gateMessage,
                            progress: completedProgressSnapshot(label: "Pending Save"),
                            isActive: true
                        )
                        state = .pendingSave(workingJob)
                        activeTask = nil
                        return
                    }

                    workingJob = try await clearRewardedAdRequirement(for: workingJob)
                    markCurrentSaveItem(
                        statusText: "Saving",
                        detailText: "Ad completed. Writing the output.",
                        progress: completedProgressSnapshot(label: "Saving"),
                        isActive: true
                    )
                    state = .saving(workingJob)
                } else {
                    AppLogger.info(
                        "Rewarded save flag already cleared; skipping ad",
                        category: .saving,
                        metadata: [
                            "source": workingJob.sourceName,
                            "id": workingJob.state.id.uuidString
                        ]
                    )
                    markCurrentSaveItem(
                        statusText: "Saving",
                        detailText: "Ad already completed. Writing the output.",
                        progress: completedProgressSnapshot(label: "Saving"),
                        isActive: true
                    )
                    state = .saving(workingJob)
                }

                if conflictResolution == .saveAsUnique {
                    try await environment.pendingSaveStore.savePendingState(workingJob.state)
                    updatePendingSaveJob(workingJob)
                }

                let savedURL = try await finalizeSave(
                    for: workingJob.state,
                    conflictResolution: conflictResolution
                )
                try await environment.pendingSaveStore.removePendingState(id: workingJob.state.id)
                try? removeTemporaryOutput(for: workingJob.state)
                removePendingSaveJob(id: workingJob.id)
                AppLogger.info(
                    "Final save completed",
                    category: .saving,
                    metadata: [
                        "source": workingJob.sourceName,
                        "saved": savedURL.lastPathComponent
                    ]
                )
                markCurrentSaveItem(
                    statusText: "Saved",
                    detailText: savedURL.lastPathComponent,
                    progress: completedProgressSnapshot(label: "Saved"),
                    isActive: false
                )

                if showNextPendingSaveIfNeeded(afterSaving: workingJob) {
                    return
                }
                let displayName = savedURL.lastPathComponent
                let destination = destinationDescription(for: workingJob.state)
                state = .completed(SavedOutput(
                    displayName: displayName,
                    destinationDescription: destination
                ))
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .completedSave)
                activeTask = nil
            } catch is CancellationError {
                AppLogger.warning(
                    "Save pending job cancelled; pending state retained",
                    category: .saving,
                    metadata: [
                        "source": workingJob.sourceName,
                        "rewardedAdRequired": "\(workingJob.state.requiresRewardedAd)"
                    ]
                )
                markCurrentSaveItem(
                    statusText: "Pending Save",
                    detailText: workingJob.state.requiresRewardedAd
                        ? "The save was interrupted and can be retried."
                        : "Ad completed. Save can be retried without another ad.",
                    progress: completedProgressSnapshot(label: "Pending Save"),
                    isActive: true
                )
                state = .pendingSave(workingJob)
                activeTask = nil
            } catch TaptionFinalSaveConflictError.destinationAlreadyExists(let existingURL) {
                let suggestedURL = uniqueDestinationURL(
                    preferred: existingURL,
                    fileManager: FileManager.default
                )
                workingJob.saveGateMessage = "A file named \(existingURL.lastPathComponent) already exists. Choose Overwrite or Save As."
                updatePendingSaveJob(workingJob)
                saveConflictPrompt = PendingSaveConflictPrompt(
                    job: workingJob,
                    existingURL: existingURL,
                    suggestedURL: suggestedURL
                )
                AppLogger.warning(
                    "Final save paused because destination already exists",
                    category: .saving,
                    metadata: [
                        "source": workingJob.sourceName,
                        "existing": existingURL.lastPathComponent,
                        "suggested": suggestedURL.lastPathComponent,
                        "rewardedAdRequired": "\(workingJob.state.requiresRewardedAd)"
                    ]
                )
                markCurrentSaveItem(
                    statusText: "Needs Choice",
                    detailText: "A file named \(existingURL.lastPathComponent) already exists. Choose Overwrite or Save As.",
                    progress: completedProgressSnapshot(label: "Pending Save"),
                    isActive: true
                )
                state = .pendingSave(workingJob)
                activeTask = nil
            } catch {
                let failure = TaptionSaveFailurePresenter.presentation(
                    for: error,
                    saveDestination: workingJob.state.saveDestination,
                    requiresRewardedAd: workingJob.state.requiresRewardedAd
                )
                AppLogger.error(
                    "Save pending job failed",
                    category: .saving,
                    metadata: [
                        "source": workingJob.sourceName,
                        "cause": failure.cause,
                        "action": failure.action,
                        "diagnostic": failure.diagnostic,
                        "rewardedAdRequired": "\(workingJob.state.requiresRewardedAd)"
                    ]
                )
                markCurrentSaveItem(
                    statusText: "Failed",
                    detailText: failure.cardMessage,
                    progress: nil,
                    isActive: false
                )
                state = .failed(HomeEncodingError(
                    title: "Save failed",
                    message: failure.displayMessage
                ))
                activeTask = nil
                requestSessionEndAd(reason: .failedEncoding)
            }
        }
    }

    private func requestSessionEndAd(reason: SessionEndAdReason) {
        AppLogger.info(
            "Session end ad requested",
            category: .ads,
            metadata: ["reason": reason.rawValue]
        )
        Task { [environment] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await environment.sessionEndAdProvider.showSessionEndAd(reason: reason)
        }
    }

    private func saveGateMessage(for decision: AdGateDecision) -> String {
        switch decision {
        case .allowed:
            return "Rewarded ad complete. Saving can continue."
        case .unavailable:
            return "No rewarded ad is available right now. The encoded video is kept pending; try Watch Ad & Save again later."
        case .skipped:
            return "Rewarded ad was skipped. The encoded video is kept pending until one ad is completed."
        }
    }

    private func preflightCurrentBatchThenPrepareFirst(displayName: String) {
        guard let batch = folderBatch,
              let displayURL = batch.folderURL ?? batch.fileURLs.first else {
            AppLogger.warning("Batch preflight skipped because batch is missing", category: .folderImport)
            finishFolderBatch()
            return
        }

        AppLogger.info(
            "Batch preflight started",
            category: .folderImport,
            metadata: [
                "name": displayName,
                "count": "\(batch.totalCount)"
            ]
        )
        let source = HomeSelectedSource(
            kind: batch.sourceKind,
            displayName: displayName,
            url: displayURL
        )
        state = .inspecting(source)

        activeTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await preflightFolderBatch()
                guard folderBatch?.hasEncodableFiles == true else {
                    AppLogger.error(
                        "Batch preflight found no encodable videos for selected output",
                        category: .folderImport,
                        metadata: ["name": displayName]
                    )
                    activeTask = nil
                    state = .failed(HomeEncodingError(
                        title: "No encodable videos",
                        message: "This folder does not contain videos that can be encoded to \(selectedOutput.summary) in this build."
                    ))
                    requestSessionEndAd(reason: .failedEncoding)
                    return
                }

                activeTask = nil
                AppLogger.info("Batch preflight completed", category: .folderImport)
                prepareCurrentFolderItem(autoStartAfterPrepare: false, allowsBusyState: true)
            } catch is CancellationError {
                AppLogger.warning("Batch preflight cancelled", category: .folderImport)
                state = .cancelled
                activeTask = nil
                folderBatch = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .cancelledEncoding)
            } catch {
                AppLogger.error(
                    "Batch preflight failed",
                    category: .folderImport,
                    metadata: ["error": error.localizedDescription]
                )
                activeTask = nil
                state = .failed(HomeEncodingError(
                    title: "Folder failed",
                    message: error.localizedDescription
                ))
                requestSessionEndAd(reason: .failedEncoding)
            }
        }
    }

    private func preflightFolderBatch() async throws {
        guard let batch = folderBatch else {
            return
        }

        for url in batch.fileURLs {
            try Task.checkCancellation()
            markBatchItem(
                url,
                statusText: "Inspecting",
                detailText: "Reading video info.",
                progress: nil,
                isActive: false
            )
            await inspectBatchItemInfo(url: url)
        }
    }

    private func inspectSelectedBatchItemInfo(url: URL) async {
        markBatchItem(
            url,
            statusText: "Inspecting",
            detailText: "Reading video info.",
            progress: nil,
            isActive: false
        )
        await inspectBatchItemInfo(url: url)
    }

    private func inspectBatchItemInfo(url: URL) async {
        guard let batch = folderBatch else {
            return
        }

        AppLogger.debug(
            "Batch item inspection started",
            category: .mediaInspection,
            metadata: ["name": url.lastPathComponent]
        )
        let source = HomeSelectedSource(
            kind: batch.sourceKind,
            displayName: url.lastPathComponent,
            url: url
        )

        do {
            let asset = try await environment.videoCoreServices.inspector.inspectVideo(at: url)
            let routeSelection = TaptionCodecRoutePlanner.selectRoute(
                for: asset,
                outputCodec: selectedOutput.videoCodec,
                requestedMode: .automatic
            )
            let info = makeLoadedVideoInfo(
                source: source,
                asset: asset,
                outputName: outputName(for: source),
                routeSelection: routeSelection
            )
            guard let videoTrack = asset.videoTrack else {
                AppLogger.warning(
                    "Batch item disabled because no video track was found",
                    category: .mediaInspection,
                    metadata: ["name": url.lastPathComponent]
                )
                markBatchItem(
                    url,
                    asset: asset,
                    videoInfo: info,
                    statusText: "No Video",
                    detailText: "Disabled. No readable video track.",
                    progress: nil,
                    isActive: false,
                    isEnabled: false
                )
                return
            }

            if info.isRouteEncodable {
                AppLogger.info(
                    "Batch item accepted for implemented codec route",
                    category: .mediaInspection,
                    metadata: [
                        "name": url.lastPathComponent,
                        "route": routeSelection.route.displayName,
                        "path": routeSelection.displayTitle
                    ]
                )
                markBatchItem(
                    url,
                    asset: asset,
                    videoInfo: info,
                    statusText: "Queued",
                    detailText: "\(routeSelection.displayTitle). Ready to encode.",
                    progress: nil,
                    isActive: false,
                    isEnabled: true
                )
            } else {
                AppLogger.info(
                    "Batch item disabled because codec route is not implemented",
                    category: .mediaInspection,
                    metadata: [
                        "name": url.lastPathComponent,
                        "codec": videoTrack.codec.displayName,
                        "route": routeSelection.route.displayName,
                        "support": routeSelection.support.rawValue
                    ]
                )
                markBatchItem(
                    url,
                    asset: asset,
                    videoInfo: info,
                    statusText: info.readinessStatusText,
                    detailText: "Disabled. \(info.codecPathDetail)",
                    progress: nil,
                    isActive: false,
                    isEnabled: false
                )
            }
        } catch {
            AppLogger.error(
                "Batch item inspection failed",
                category: .mediaInspection,
                metadata: [
                    "name": url.lastPathComponent,
                    "error": error.localizedDescription
                ]
            )
            markBatchItem(
                url,
                statusText: "Unreadable",
                detailText: "Disabled. \(error.localizedDescription)",
                progress: nil,
                isActive: false,
                isEnabled: false
            )
        }
    }

    private func prepareCurrentFolderItem(autoStartAfterPrepare: Bool, allowsBusyState: Bool = false) {
        guard let batch = folderBatch,
              let url = batch.currentFileURL else {
            AppLogger.info("No current batch item remains; finishing batch", category: .folderImport)
            finishFolderBatch()
            return
        }

        if batch.itemStates[url]?.isEnabled == false {
            AppLogger.info(
                "Skipping disabled batch item",
                category: .folderImport,
                metadata: [
                    "name": url.lastPathComponent,
                    "index": "\(batch.currentIndex + 1)",
                    "total": "\(batch.totalCount)"
                ]
            )
            var nextBatch = batch
            nextBatch.currentIndex += 1
            folderBatch = nextBatch
            prepareCurrentFolderItem(
                autoStartAfterPrepare: autoStartAfterPrepare,
                allowsBusyState: allowsBusyState
            )
            return
        }

        AppLogger.info(
            "Preparing current batch item",
            category: .folderImport,
            metadata: [
                "name": url.lastPathComponent,
                "index": "\(batch.currentIndex + 1)",
                "total": "\(batch.totalCount)",
                "autoStart": "\(autoStartAfterPrepare)"
            ]
        )
        let source = HomeSelectedSource(
            kind: batch.sourceKind,
            displayName: url.lastPathComponent,
            url: url
        )
        prepareEncodingFlow(
            source: source,
            autoStartAfterPrepare: autoStartAfterPrepare,
            allowsBusyState: allowsBusyState
        )
    }

    private func handleFolderItemEncoded() -> Bool {
        guard var batch = folderBatch else {
            return false
        }

        AppLogger.info(
            "Batch item encoded",
            category: .folderImport,
            metadata: [
                "encoded": "\(batch.completedCount + 1)",
                "total": "\(batch.totalCount)"
            ]
        )
        batch.completedCount += 1
        batch.currentIndex += 1
        folderBatch = batch

        guard batch.hasRemainingFiles else {
            finishFolderBatch()
            return true
        }

        activeTask = nil
        prepareCurrentFolderItem(autoStartAfterPrepare: true)
        return true
    }

    private func handleFolderItemFailure(source: HomeSelectedSource, errorMessage: String) -> Bool {
        guard var batch = folderBatch else {
            return false
        }

        AppLogger.error(
            "Batch item failed",
            category: .folderImport,
            metadata: [
                "name": source.displayName,
                "error": errorMessage
            ]
        )
        batch.failedCount += 1
        batch.currentIndex += 1
        batch.lastFailureMessage = "\(source.displayName): \(errorMessage)"
        folderBatch = batch

        guard batch.hasRemainingFiles else {
            finishFolderBatch()
            return true
        }

        activeTask = nil
        prepareCurrentFolderItem(autoStartAfterPrepare: true)
        return true
    }

    private func finishFolderBatch() {
        guard let batch = folderBatch else {
            return
        }

        AppLogger.info(
            "Batch finished",
            category: .folderImport,
            metadata: [
                "folder": batch.folderName,
                "completed": "\(batch.completedCount)",
                "failed": "\(batch.failedCount)",
                "total": "\(batch.totalCount)"
            ]
        )
        lastBatchFileCards = batch.cardSnapshots()
        folderBatch = nil
        currentReview = nil
        activeTask = nil
        if let nextPendingJob = pendingSaveQueue.first {
            state = .pendingSave(nextPendingJob)
        } else {
            state = .completed(SavedOutput(
                displayName: "Folder complete",
                destinationDescription: batch.folderName,
                detailOverride: folderCompletionMessage(for: batch)
            ))
        }
        stopSecurityScopedAccess()
        requestSessionEndAd(reason: batch.failedCount > 0 ? .failedEncoding : .completedSave)
    }

    private func folderCompletionMessage(for batch: FolderEncodingBatch) -> String {
        var message = "Folder encoding complete. \(batch.completedCount) of \(batch.totalCount) files are ready to save with rewarded ads."
        if batch.failedCount > 0 {
            message += " \(batch.failedCount) failed."
        }
        if let lastFailureMessage = batch.lastFailureMessage {
            message += " Last issue: \(lastFailureMessage)"
        }
        return message
    }

    private func startingProgressSnapshot(for review: PreparedEncodingReview) -> EncodingProgressSnapshot {
        EncodingProgressSnapshot(
            stage: .queued,
            fractionCompleted: folderBatch == nil ? 0 : Double(folderBatch?.currentIndex ?? 0) / Double(max(folderBatch?.totalCount ?? 1, 1)),
            elapsedTime: 0,
            estimatedRemainingTime: nil,
            backendLabel: review.folderQueue?.statusText ?? "Starting Codec Path",
            outputSummary: review.videoInfo.outputSummary
        )
    }

    private func encodingProgressSnapshot(
        from progress: TaptionEncodingProgress,
        sourceName: String
    ) -> EncodingProgressSnapshot {
        if let batch = folderBatch {
            let total = max(batch.totalCount, 1)
            let currentOffset = min(max(batch.currentIndex, 0), total - 1)
            let overallFraction = (Double(currentOffset) + progress.fractionCompleted) / Double(total)
            return EncodingProgressSnapshot(
                stage: progress.stage,
                fractionCompleted: overallFraction,
                elapsedTime: progress.elapsedTime,
                estimatedRemainingTime: progress.estimatedRemainingTime,
                backendLabel: batch.snapshot(currentFileName: sourceName).statusText,
                outputSummary: currentReview?.videoInfo.outputSummary
            )
        }

        return EncodingProgressSnapshot(
            stage: progress.stage,
            fractionCompleted: progress.fractionCompleted,
            elapsedTime: progress.elapsedTime,
            estimatedRemainingTime: progress.estimatedRemainingTime,
            backendLabel: currentReview?.videoInfo.codecPathTitle ?? "Automatic Codec Path",
            outputSummary: currentReview?.videoInfo.outputSummary
        )
    }

    private func markBatchItem(
        _ url: URL,
        asset: TaptionVideoAsset? = nil,
        videoInfo: LoadedVideoInfo? = nil,
        statusText: String,
        detailText: String?,
        progress: EncodingProgressSnapshot?,
        isActive: Bool,
        isEnabled: Bool? = nil
    ) {
        guard var batch = folderBatch else {
            return
        }
        var item = batch.itemStates[url] ?? .queued
        if let asset {
            item.asset = asset
        }
        if let videoInfo {
            item.videoInfo = videoInfo
        }
        item.progress = progress
        item.statusText = statusText
        item.detailText = detailText
        item.isActive = isActive
        if let isEnabled {
            item.isEnabled = isEnabled
        }
        if isActive {
            batch.selectedURL = url
        }
        batch.itemStates[url] = item
        if item.isEnabled == false,
           batch.selectedURL == url {
            batch.selectedURL = batch.fileURLs.first { batch.itemStates[$0]?.isEnabled != false }
        }
        folderBatch = batch
        objectWillChange.send()
    }

    private func markCurrentSaveItem(
        statusText: String,
        detailText: String?,
        progress: EncodingProgressSnapshot?,
        isActive: Bool
    ) {
        if let url = folderBatch?.currentFileURL {
            markBatchItem(
                url,
                videoInfo: currentReview?.videoInfo,
                statusText: statusText,
                detailText: detailText,
                progress: progress,
                isActive: isActive
            )
        }
    }

    private func pendingSaveQueueCardSnapshots() -> [EncodingFileCardSnapshot] {
        let activeJobID = pendingSaveRecoveryJob?.id
        return pendingSaveQueue.map { job in
            let isActive = job.id == activeJobID
            let isSaving: Bool
            if case .saving(let savingJob) = state {
                isSaving = savingJob.id == job.id
            } else {
                isSaving = false
            }
            let statusText: String
            let detailText: String
            if isSaving {
                statusText = "Saving"
                detailText = job.state.requiresRewardedAd
                    ? "Waiting for rewarded ad before saving."
                    : "Ad completed. Writing this video."
            } else if isActive {
                statusText = job.saveGateMessage == nil ? "Pending Save" : "Ad Unavailable"
                detailText = job.saveGateMessage ?? (job.state.requiresRewardedAd
                    ? "Watch one rewarded ad to save this video."
                    : "Ad completed. Save this video now.")
            } else {
                statusText = "Pending Save"
                detailText = job.saveGateMessage ?? (job.state.requiresRewardedAd
                    ? "Waiting for its rewarded ad save turn."
                    : "Ad completed. Waiting to save.")
            }

            return EncodingFileCardSnapshot(
                id: job.id.uuidString,
                fileName: job.sourceName,
                sourceKind: .files,
                videoInfo: nil,
                statusText: statusText,
                detailText: detailText,
                progress: completedProgressSnapshot(label: isSaving ? "Saving" : "Pending Save"),
                isActive: isActive,
                isSelected: isActive,
                isEnabled: true
            )
        }
    }

    private func enqueuePendingSaveJob(_ job: PendingSaveJob) {
        pendingSaveQueue.removeAll { $0.id == job.id }
        pendingSaveQueue.append(job)
        pendingSaveQueue.sort { $0.state.createdAt < $1.state.createdAt }
        AppLogger.info(
            "Pending save job enqueued",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "queueCount": "\(pendingSaveQueue.count)"
            ]
        )
    }

    private func updatePendingSaveJob(_ job: PendingSaveJob) {
        pendingSaveQueue.removeAll { $0.id == job.id }
        pendingSaveQueue.append(job)
        pendingSaveQueue.sort { $0.state.createdAt < $1.state.createdAt }
        AppLogger.info(
            "Pending save job updated",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "queueCount": "\(pendingSaveQueue.count)",
                "rewardedAdRequired": "\(job.state.requiresRewardedAd)"
            ]
        )
    }

    private func clearRewardedAdRequirement(for job: PendingSaveJob) async throws -> PendingSaveJob {
        guard job.state.requiresRewardedAd else {
            return job
        }

        var updatedState = job.state
        updatedState.requiresRewardedAd = false
        updatedState.rewardedAdCompletedAt = Date()
        try await environment.pendingSaveStore.savePendingState(updatedState)

        let updatedJob = PendingSaveJob(sourceName: job.sourceName, state: updatedState)
        updatePendingSaveJob(updatedJob)
        AppLogger.info(
            "Rewarded save flag cleared",
            category: .saving,
            metadata: [
                "source": updatedJob.sourceName,
                "id": updatedState.id.uuidString
            ]
        )
        return updatedJob
    }

    private func removePendingSaveJob(id: UUID) {
        pendingSaveQueue.removeAll { $0.id == id }
    }

    private func showNextPendingSaveIfNeeded(afterSaving job: PendingSaveJob) -> Bool {
        guard let nextJob = pendingSaveQueue.first else {
            return false
        }

        AppLogger.info(
            "Advancing to next pending save job",
            category: .saving,
            metadata: [
                "previous": job.sourceName,
                "next": nextJob.sourceName,
                "remaining": "\(pendingSaveQueue.count)"
            ]
        )
        state = .pendingSave(nextJob)
        activeTask = nil
        return true
    }

    private func canStartNewSourceFlow() -> Bool {
        guard pendingSaveQueue.isEmpty else {
            if let firstJob = pendingSaveQueue.first {
                AppLogger.warning(
                    "Source selection blocked until pending saves are completed",
                    category: .saving,
                    metadata: [
                        "first": firstJob.sourceName,
                        "count": "\(pendingSaveQueue.count)"
                    ]
                )
                state = .pendingSave(firstJob)
            }
            return false
        }
        return true
    }

    private func refreshPreparedSourceAfterOutputChange() {
        guard !state.isBusy else {
            return
        }

        if let review = currentReview {
            AppLogger.info(
                "Refreshing prepared source for output change",
                category: .ui,
                metadata: [
                    "name": review.source.displayName,
                    "output": selectedOutput.summary
                ]
            )
            prepareEncodingFlow(source: review.source, allowsBusyState: true)
            return
        }

        guard var batch = folderBatch else {
            return
        }

        for url in batch.fileURLs {
            guard var item = batch.itemStates[url],
                  let asset = item.asset else {
                continue
            }
            let source = HomeSelectedSource(
                kind: batch.sourceKind,
                displayName: url.lastPathComponent,
                url: url
            )
            let routeSelection = TaptionCodecRoutePlanner.selectRoute(
                for: asset,
                outputCodec: selectedOutput.videoCodec,
                requestedMode: .automatic
            )
            let info = makeLoadedVideoInfo(
                source: source,
                asset: asset,
                outputName: outputName(for: source),
                routeSelection: routeSelection
            )
            item.videoInfo = info
            item.isEnabled = info.isRouteEncodable
            item.statusText = info.isRouteEncodable ? "Queued" : info.readinessStatusText
            item.detailText = info.isRouteEncodable ? "\(routeSelection.displayTitle). Ready to encode." : "Disabled. \(info.codecPathDetail)"
            item.progress = nil
            item.isActive = false
            batch.itemStates[url] = item
        }

        batch.selectedURL = batch.fileURLs.first { batch.itemStates[$0]?.isEnabled != false }
            ?? batch.fileURLs.first
        folderBatch = batch
        objectWillChange.send()
    }

    private func resetPendingStates() -> [TaptionPendingSaveState] {
        var states = pendingSaveQueue.map(\.state)
        if let visibleState = state.pendingSaveJob?.state
            ?? state.completedTemporaryOutput?.pendingSaveState,
           !states.contains(where: { $0.id == visibleState.id }) {
            states.append(visibleState)
        }
        return states
    }

    private func fileCard(
        source: HomeSelectedSource,
        videoInfo: LoadedVideoInfo? = nil,
        statusText: String,
        detailText: String?,
        progress: EncodingProgressSnapshot?,
        isActive: Bool,
        isSelected: Bool,
        isEnabled: Bool
    ) -> EncodingFileCardSnapshot {
        fileCard(
            sourceName: source.displayName,
            sourceKind: source.kind,
            videoInfo: videoInfo,
            statusText: statusText,
            detailText: detailText,
            progress: progress,
            isActive: isActive,
            isSelected: isSelected,
            isEnabled: isEnabled
        )
    }

    private func fileCard(
        sourceName: String,
        sourceKind: HomeSourceKind,
        videoInfo: LoadedVideoInfo?,
        statusText: String,
        detailText: String?,
        progress: EncodingProgressSnapshot?,
        isActive: Bool,
        isSelected: Bool,
        isEnabled: Bool
    ) -> EncodingFileCardSnapshot {
        EncodingFileCardSnapshot(
            id: sourceName,
            fileName: sourceName,
            sourceKind: sourceKind,
            videoInfo: videoInfo,
            statusText: statusText,
            detailText: detailText,
            progress: progress,
            isActive: isActive,
            isSelected: isSelected,
            isEnabled: isEnabled
        )
    }

    private func completedProgressSnapshot(label: String) -> EncodingProgressSnapshot {
        EncodingProgressSnapshot(
            stage: .completed,
            fractionCompleted: 1,
            elapsedTime: 0,
            estimatedRemainingTime: 0,
            backendLabel: label,
            outputSummary: currentReview?.videoInfo.outputSummary
        )
    }

    private func makeLoadedVideoInfo(
        source: HomeSelectedSource,
        job: TaptionPreparedEncodingJob
    ) -> LoadedVideoInfo {
        makeLoadedVideoInfo(
            source: source,
            asset: job.asset,
            outputName: job.plan.finalOutputURL?.lastPathComponent ?? "Output not ready",
            routeSelection: job.routeSelection
        )
    }

    private func makeLoadedVideoInfo(
        source: HomeSelectedSource,
        asset: TaptionVideoAsset,
        outputName: String,
        routeSelection: TaptionCodecRouteSelection? = nil
    ) -> LoadedVideoInfo {
        let videoTrack = asset.videoTrack
        let audioTrack = asset.audioTracks.first
        let routeSelection = routeSelection ?? TaptionCodecRoutePlanner.selectRoute(
            for: asset,
            outputCodec: selectedOutput.videoCodec,
            requestedMode: .automatic
        )
        let videoPath = LoadedVideoPathInfo.make(
            sourceCodec: videoTrack?.codec ?? .unknown,
            routeSelection: routeSelection,
            outputSelection: selectedOutput
        )
        let audioPath = LoadedAudioPathInfo.make(
            firstAudioTrack: audioTrack,
            trackCount: asset.audioTracks.count,
            outputCodec: selectedOutput.audioCodec,
            outputContainer: selectedOutput.container
        )
        return LoadedVideoInfo(
            fileName: source.displayName,
            inputSummary: "\(videoTrack?.codec.displayName ?? "Unknown") / \(asset.container.defaultFileExtension.uppercased())",
            resolution: resolutionText(for: videoTrack),
            frameRate: frameRateText(for: videoTrack?.nominalFrameRate),
            duration: durationText(asset.duration),
            audio: audioText(for: audioTrack, count: asset.audioTracks.count),
            audioPathTitle: audioPath.title,
            audioPathDetail: audioPath.detail,
            audioOutputSummary: audioPath.outputSummary,
            fileSize: fileSizeText(asset.fingerprint.fileSize),
            codecPathTitle: videoPath.title,
            codecPathDetail: videoPath.detail,
            outputSummary: videoPath.outputSummary,
            outputName: outputName,
            isRouteEncodable: videoPath.isRouteEncodable
        )
    }

    private func outputName(for source: HomeSelectedSource) -> String {
        source.url.deletingPathExtension().lastPathComponent
            + environment.configuration.outputSuffix
            + "."
            + selectedOutput.container.defaultFileExtension
    }

    private func resolutionText(for track: TaptionVideoTrackInfo?) -> String {
        guard let track else {
            return "Unknown"
        }
        return "\(track.displaySize.width)x\(track.displaySize.height)"
    }

    private func frameRateText(for frameRate: TaptionRationalFrameRate?) -> String {
        guard let frameRate else {
            return "Unknown fps"
        }
        let value = frameRate.value
        if abs(value.rounded() - value) < 0.01 {
            return "\(Int(value.rounded())) fps"
        }
        return String(format: "%.2f fps", value)
    }

    private func durationText(_ duration: TimeInterval?) -> String {
        guard let duration, duration.isFinite else {
            return "Unknown"
        }
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func audioText(for audioTrack: TaptionAudioTrackInfo?, count: Int) -> String {
        guard let audioTrack else {
            return "No audio"
        }
        let suffix = count > 1 ? " +\(count - 1)" : ""
        return "\(audioCodecName(audioTrack.codec))\(suffix)"
    }

    private func audioCodecName(_ codec: TaptionAudioCodec) -> String {
        codec == .unknown ? "Unknown audio" : codec.displayName
    }

    private func fileSizeText(_ bytes: Int64?) -> String {
        guard let bytes else {
            return "Unknown size"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func videoFileURLs(in folderURL: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        let urls = try FileManager.default
            .contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            .filter { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true,
                      values?.isHidden != true else {
                    return false
                }
                return SupportedVideoFileExtensions.contains(url.pathExtension)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        AppLogger.info(
            "Supported video files scanned",
            category: .folderImport,
            metadata: [
                "folder": folderURL.lastPathComponent,
                "count": "\(urls.count)"
            ]
        )
        return urls
    }

    private func makeTemporaryOutputURL(for source: HomeSelectedSource) -> URL {
        let baseName = source.url.deletingPathExtension().lastPathComponent
        let directoryURL = TaptionEncoderStorageLocations.pendingEncodedVideosDirectoryURL
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
            .appendingPathComponent(UUID().uuidString + "_" + baseName + environment.configuration.outputSuffix)
            .appendingPathExtension(selectedOutput.container.defaultFileExtension)
    }

    private func finalizeSave(
        for state: TaptionPendingSaveState,
        conflictResolution: PendingSaveConflictResolution = .prompt
    ) async throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: state.temporaryOutputURL.path) else {
            AppLogger.error(
                "Final save failed because temporary output is missing",
                category: .saving,
                metadata: ["temporary": state.temporaryOutputURL.lastPathComponent]
            )
            throw TaptionVideoCoreError.finalSaveFailed("The temporary H.265 output is missing. Please encode again.")
        }

        switch state.saveDestination {
        case .sourceFolder:
            guard var finalOutputURL = state.finalOutputURL else {
                AppLogger.error("Final save failed because final output path is missing", category: .saving)
                throw TaptionVideoCoreError.finalSaveFailed("The final output path is missing.")
            }
            let securityScopedURL = resolveSecurityScopedAccessURL(from: state.accessBookmarkData)
            let didStartSecurityScope = securityScopedURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if didStartSecurityScope {
                    securityScopedURL?.stopAccessingSecurityScopedResource()
                }
            }
            AppLogger.info(
                "Copying final output to source folder",
                category: .saving,
                metadata: [
                    "temporary": state.temporaryOutputURL.lastPathComponent,
                    "final": finalOutputURL.lastPathComponent,
                    "securityScope": "\(didStartSecurityScope)"
                ]
            )
            try fileManager.createDirectory(
                at: finalOutputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: finalOutputURL.path) {
                switch conflictResolution {
                case .prompt:
                    AppLogger.warning(
                        "Final save destination already exists",
                        category: .saving,
                        metadata: ["final": finalOutputURL.lastPathComponent]
                    )
                    throw TaptionFinalSaveConflictError.destinationAlreadyExists(finalOutputURL)
                case .overwrite:
                    AppLogger.info(
                        "Overwriting existing final output",
                        category: .saving,
                        metadata: ["final": finalOutputURL.lastPathComponent]
                    )
                    try fileManager.removeItem(at: finalOutputURL)
                case .saveAsUnique:
                    let uniqueURL = uniqueDestinationURL(
                        preferred: finalOutputURL,
                        fileManager: fileManager
                    )
                    AppLogger.info(
                        "Saving final output with unique name",
                        category: .saving,
                        metadata: [
                            "original": finalOutputURL.lastPathComponent,
                            "unique": uniqueURL.lastPathComponent
                        ]
                    )
                    finalOutputURL = uniqueURL
                }
            }
            try fileManager.copyItem(at: state.temporaryOutputURL, to: finalOutputURL)
            return finalOutputURL
        case .photosLibrary:
            AppLogger.info(
                "Saving final output to Photos",
                category: .saving,
                metadata: ["temporary": state.temporaryOutputURL.lastPathComponent]
            )
            try await saveVideoToPhotos(state.temporaryOutputURL)
            return state.finalOutputURL ?? state.temporaryOutputURL
        case .temporaryOnly:
            AppLogger.info(
                "Final output remains in temporary storage",
                category: .saving,
                metadata: ["temporary": state.temporaryOutputURL.lastPathComponent]
            )
            return state.temporaryOutputURL
        }
    }

    private func uniqueDestinationURL(
        preferred url: URL,
        fileManager: FileManager
    ) -> URL {
        let directoryURL = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension

        for index in 2...999 {
            let candidate = directoryURL
                .appendingPathComponent("\(baseName) \(index)")
                .appendingPathExtension(pathExtension)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directoryURL
            .appendingPathComponent("\(baseName) \(UUID().uuidString.prefix(8))")
            .appendingPathExtension(pathExtension)
    }

    private func saveVideoToPhotos(_ videoURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                AppLogger.info(
                    "Photos save authorization completed",
                    category: .saving,
                    metadata: ["status": "\(status.rawValue)"]
                )
                guard status == .authorized || status == .limited else {
                    continuation.resume(throwing: TaptionVideoCoreError.finalSaveFailed(
                        "Photos save permission was not granted."
                    ))
                    return
                }

                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = false
                    request.addResource(with: .video, fileURL: videoURL, options: options)
                } completionHandler: { isSuccess, error in
                    if let error {
                        AppLogger.error(
                            "Photos save failed",
                            category: .saving,
                            metadata: ["error": error.localizedDescription]
                        )
                        continuation.resume(throwing: error)
                    } else if isSuccess {
                        AppLogger.info("Photos save completed", category: .saving)
                        continuation.resume()
                    } else {
                        AppLogger.error("Photos did not save the encoded video", category: .saving)
                        continuation.resume(throwing: TaptionVideoCoreError.finalSaveFailed(
                            "Photos did not save the encoded video."
                        ))
                    }
                }
            }
        }
    }

    private func makePendingSaveJob(from state: TaptionPendingSaveState) -> PendingSaveJob {
        let sourceName = state.finalOutputURL?.lastPathComponent
            ?? state.temporaryOutputURL.lastPathComponent
        return PendingSaveJob(sourceName: sourceName, state: state)
    }

    private func pendingSaveStateWithAccessBookmark(
        _ state: TaptionPendingSaveState,
        source: HomeSelectedSource
    ) async -> TaptionPendingSaveState {
        var updatedState = state
        if updatedState.accessBookmarkData == nil {
            let bookmarkURL = securityBookmarkSourceURL(for: source)
            updatedState.accessBookmarkData = makeSecurityScopedBookmarkData(for: bookmarkURL)
        }

        do {
            try await environment.pendingSaveStore.savePendingState(updatedState)
        } catch {
            AppLogger.error(
                "Failed to persist pending save state with access bookmark",
                category: .saving,
                metadata: [
                    "source": source.displayName,
                    "error": error.localizedDescription
                ]
            )
        }

        return updatedState
    }

    private func securityBookmarkSourceURL(for source: HomeSelectedSource) -> URL {
        if source.kind == .folder,
           let folderURL = folderBatch?.folderURL {
            return folderURL
        }
        return source.url
    }

    private func makeSecurityScopedBookmarkData(for url: URL) -> Data? {
        do {
            let data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            AppLogger.info(
                "Security scoped bookmark created",
                category: .fileImport,
                metadata: ["name": url.lastPathComponent]
            )
            return data
        } catch {
            AppLogger.warning(
                "Security scoped bookmark creation failed",
                category: .fileImport,
                metadata: [
                    "name": url.lastPathComponent,
                    "error": error.localizedDescription
                ]
            )
            return nil
        }
    }

    private func resolveSecurityScopedAccessURL(from bookmarkData: Data?) -> URL? {
        guard let bookmarkData else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            AppLogger.info(
                "Security scoped bookmark resolved",
                category: .fileImport,
                metadata: [
                    "name": url.lastPathComponent,
                    "isStale": "\(isStale)"
                ]
            )
            return url
        } catch {
            AppLogger.warning(
                "Security scoped bookmark resolve failed",
                category: .fileImport,
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    private func removeTemporaryOutput(for state: TaptionPendingSaveState) throws {
        guard FileManager.default.fileExists(atPath: state.temporaryOutputURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: state.temporaryOutputURL)
        AppLogger.info(
            "Temporary encoded output removed after save",
            category: .saving,
            metadata: ["temporary": state.temporaryOutputURL.lastPathComponent]
        )
    }

    private func removeAllPendingTemporaryOutputs() {
        let directoryURL = TaptionEncoderStorageLocations.pendingEncodedVideosDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        var removedCount = 0
        for fileURL in files {
            do {
                try FileManager.default.removeItem(at: fileURL)
                removedCount += 1
            } catch {
                AppLogger.warning(
                    "Pending temporary output cleanup failed",
                    category: .saving,
                    metadata: [
                        "temporary": fileURL.lastPathComponent,
                        "error": error.localizedDescription
                    ]
                )
            }
        }

        if removedCount > 0 {
            AppLogger.info(
                "Pending temporary outputs removed by reset",
                category: .saving,
                metadata: ["count": "\(removedCount)"]
            )
        }
    }

    private func codecPathTitle(mode: TaptionEncoderMode) -> String {
        switch mode {
        case .hardware:
            return "Codec Path: Hardware"
        case .software:
            return "Codec Path: Software"
        case .automatic:
            return "Codec Path: Automatic"
        }
    }

    private func codecPathDetail(mode: TaptionEncoderMode, backend: TaptionEncodingBackend) -> String {
        switch (mode, backend) {
        case (.hardware, .appleVideoToolbox):
            return "This file was converted with the device H.265 hardware encoder."
        case (.software, .softwareAV1Decoder):
            return "Native AV1 conversion was unavailable, so the app used software AV1 decoding automatically."
        case (.software, _):
            return "Hardware conversion was unavailable, so the app used the software fallback automatically."
        case (.automatic, _):
            return "The app selected the available codec path automatically."
        case (.hardware, _):
            return "The app selected the available hardware codec path automatically."
        }
    }

    private func beginSecurityScopedAccessIfNeeded(for url: URL) {
        beginSecurityScopedAccessIfNeeded(for: [url])
    }

    private func beginSecurityScopedAccessIfNeeded(for urls: [URL]) {
        stopSecurityScopedAccess()
        securityScopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        AppLogger.info(
            "Security scoped access started",
            category: .fileImport,
            metadata: [
                "requested": "\(urls.count)",
                "granted": "\(securityScopedURLs.count)",
                "names": urls.map(\.lastPathComponent).joined(separator: "|")
            ]
        )
    }

    private func stopSecurityScopedAccess() {
        guard !securityScopedURLs.isEmpty else {
            return
        }
        AppLogger.info(
            "Security scoped access stopped",
            category: .fileImport,
            metadata: [
                "count": "\(securityScopedURLs.count)",
                "names": securityScopedURLs.map(\.lastPathComponent).joined(separator: "|")
            ]
        )
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs = []
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
