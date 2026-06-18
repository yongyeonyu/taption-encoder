import Foundation
import Photos

private enum PendingSaveConflictResolution: Equatable {
    case prompt
    case overwrite
    case saveAsUnique
}

private struct ActiveStarCharge: Equatable {
    var sourceURL: URL
    var sourceName: String
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: HomeScreenState
    @Published private(set) var selectedOutput: TaptionOutputSelection
    @Published private(set) var saveConflictPrompt: PendingSaveConflictPrompt?
    @Published private(set) var pendingSaveRenamePrompt: PendingSaveRenamePrompt?
    @Published private(set) var folderAccessPrompt: PendingFolderAccessPrompt?
    @Published private(set) var pendingSaveExportPrompt: PendingSaveExportPrompt?
    @Published private(set) var starWalletSnapshot: StarWalletSnapshot
    @Published private(set) var rewardedAdState: AdLoadState
    @Published private(set) var isWatchingStarAd: Bool

    private let environment: AppEnvironment
    private var activeTask: Task<Void, Never>?
    private var folderBatch: FolderEncodingBatch?
    private var currentReview: PreparedEncodingReview?
    private var pendingSaveQueue: [PendingSaveJob] = []
    private var lastBatchFileCards: [EncodingFileCardSnapshot] = []
    private var selectionInspectionTask: Task<Void, Never>?
    private var hasRestoredPendingSaves = false
    private var hasLoadedStarWallet = false
    private var pendingSaveAccessURLs: [UUID: URL] = [:]
    private var securityScopedURLs: [URL] = []
    private var activeStarCharge: ActiveStarCharge?
    private var shouldAutoResumeBatchAfterStarEarn = false
    private var rewardedAdStatePollingTask: Task<Void, Never>?
    private let pendingSaveExportStagingRootDirectoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("TaptionEncoderPendingSaveExports", isDirectory: true)

    init(environment: AppEnvironment = .phase0) {
        self.environment = environment
        self.selectedOutput = TaptionOutputSelection(
            videoCodec: environment.configuration.defaultOutputCodec,
            container: environment.configuration.defaultOutputContainer
        )
        self.state = .idle
        self.saveConflictPrompt = nil
        self.pendingSaveRenamePrompt = nil
        self.folderAccessPrompt = nil
        self.pendingSaveExportPrompt = nil
        self.starWalletSnapshot = .empty
        self.rewardedAdState = .idle
        self.isWatchingStarAd = false
        AppLogger.info(
            "HomeViewModel initialized",
            category: .app,
            metadata: ["appName": environment.configuration.appName]
        )
    }

    deinit {
        AppLogger.info("HomeViewModel deinitialized", category: .app)
        activeTask?.cancel()
        rewardedAdStatePollingTask?.cancel()
    }

    var appName: String {
        environment.configuration.appName
    }

    var subtitle: String {
        "Taption Encoder"
    }

    var starBalanceDisplayText: String {
        starWalletSnapshot.badgeText
    }

    var canStartEncodingNow: Bool {
        guard let review = state.preparedEncodingReview else {
            return false
        }
        return review.videoInfo.isRouteEncodable && starWalletSnapshot.balance > 0
    }

    var watchAdButtonTitle: String {
        if isWatchingStarAd {
            return "Watching Ad..."
        }
        switch rewardedAdState {
        case .ready:
            return "Watch Ad (+1 Star)"
        case .loading, .idle:
            return "Ad Loading"
        case .unavailable:
            return "Ad Unavailable"
        }
    }

    var canWatchAdForStar: Bool {
        !state.isBusy && !isWatchingStarAd && rewardedAdState == .ready
    }

    var progressDetailText: String {
        if state.preparedEncodingReview != nil,
           !canStartEncodingNow {
            return needsStarMessage
        }
        return state.detail
    }

    private var needsStarMessage: String {
        "Watch a rewarded ad to earn 1 Star and continue."
    }

    var outputSummary: String {
        "\(selectedOutput.summary) / same folder + \(environment.configuration.outputSuffix)"
    }

    var selectedOutputDetailTitle: String {
        "Selected Codec[\(selectedCodecModeText)]"
    }

    var selectedVideoCodecText: String {
        "Video: \(selectedOutput.videoCodec.displayName)"
    }

    var selectedAudioCodecText: String {
        "Audio: \(selectedOutput.audioCodec.displayName)"
    }

    private var selectedCodecModeText: String {
        guard let info = currentReview?.videoInfo else {
            return "Auto"
        }

        let videoMode = info.codecPathBadge
        let audioMode = info.audioPathBadge

        if videoMode == "Unsupported" || audioMode == "Unsupported" {
            return "Unsupported"
        }
        if videoMode == "Blocked" || audioMode == "Blocked" {
            return "Blocked"
        }
        if videoMode == "HW/SW" || audioMode == "HW/SW" {
            return "HW/SW"
        }
        if videoMode == "SW" || audioMode == "SW" {
            return "SW"
        }
        if videoMode == "HW" || audioMode == "HW" || audioMode == "Copy" || audioMode == "None" {
            return "HW"
        }
        return videoMode
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

    var outputResolutionOptions: [TaptionOutputResolutionPreset] {
        let asset = selectedAssetForOutputConfiguration
        let supported = TaptionOutputSelection.resolutionOptions.filter { resolutionPresetIsAvailable($0, for: asset) }
        let unsupported = TaptionOutputSelection.resolutionOptions.filter { !resolutionPresetIsAvailable($0, for: asset) }
        return supported + unsupported
    }

    var selectedOutputTargetSizeText: String {
        let value = selectedOutput.normalizedTargetSizeMB(for: selectedAssetForOutputConfiguration)
        return "\(Int(value.rounded())) MB"
    }

    var selectedResolutionAspectRatioText: String {
        let sourceSize = selectedAssetForOutputConfiguration?.videoTrack?.displaySize
        let size = sourceSize ?? selectedOutput.resolutionPreset.referenceSize
        guard let size, size.width > 0, size.height > 0 else {
            return "--"
        }

        let divisor = greatestCommonDivisor(size.width, size.height)
        return "\(size.width / divisor):\(size.height / divisor)"
    }

    var outputTargetSizeRangeMB: ClosedRange<Double> {
        selectedOutput.targetSizeRangeMB(for: selectedAssetForOutputConfiguration)
    }

    var selectedOutputTargetSizeValueMB: Double {
        selectedOutput.normalizedTargetSizeMB(for: selectedAssetForOutputConfiguration)
    }

    var outputSizeDisplayText: String {
        if let encodedOutputSizeText {
            return encodedOutputSizeText
        }
        if selectedOutput.sizePreset == .auto {
            return "Auto"
        }
        return selectedOutputTargetSizeText
    }

    var outputSizeSecondaryText: String? {
        if outputSizeShowsWarning {
            return "Low Space"
        }
        if encodedOutputSizeText != nil {
            return "Encoded"
        }
        if selectedOutput.sizePreset == .auto {
            return selectedOutputTargetSizeText
        }
        return nil
    }

    var outputSizeShowsWarning: Bool {
        currentStorageIssue != nil
    }

    var outputSizeStatusMessage: String? {
        if let issue = currentStorageIssue {
            return storageWarningMessage(
                requiredBytes: issue.requiredBytes,
                availableBytes: issue.availableBytes
            )
        }
        if let encodedOutputSizeText {
            return "Encoded output: \(encodedOutputSizeText)."
        }
        return nil
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

    var canChangeOutputSizeSelection: Bool {
        pendingSaveQueue.isEmpty
            && (!state.isBusy || isRefreshingPreparedSourceForOutputChange)
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
        "Encoding keeps the device awake. If the screen is locked manually, iOS grants limited background time."
    }

    var showsSaveAction: Bool {
        if state.completedTemporaryOutput != nil || state.pendingSaveJob != nil {
            return true
        }
        if case .completed = state,
           !pendingSaveQueue.isEmpty {
            return true
        }
        return false
    }

    var saveActionTitle: String {
        if case .completed = state,
           !pendingSaveQueue.isEmpty {
            return "Save Next"
        }
        return "Save"
    }

    var bannerAdUnitID: String {
        environment.bannerAdProvider.bannerAdUnitID
    }

    private var currentStorageIssue: StorageIssue? {
        if case .storageBlocked(let issue) = state {
            return issue
        }
        return nil
    }

    private var encodedOutputSizeText: String? {
        currentEncodedOutputSizeBytes.map(formattedByteCount)
    }

    private var currentEncodedOutputSizeBytes: Int64? {
        if case .completed(let output) = state,
           let fileSizeBytes = output.fileSizeBytes {
            return fileSizeBytes
        }

        let pendingState = state.pendingSaveJob?.state
            ?? state.completedTemporaryOutput?.pendingSaveState
            ?? pendingSaveRecoveryJob?.state
        guard let pendingState else {
            return nil
        }
        return fileSizeInBytes(at: pendingState.temporaryOutputURL)
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

    func selectOutputResolution(_ preset: TaptionOutputResolutionPreset) {
        guard canChangeOutputSelection else {
            AppLogger.warning(
                "Output resolution change ignored while flow is busy",
                category: .ui,
                metadata: ["resolution": preset.rawValue]
            )
            return
        }
        guard resolutionPresetIsAvailable(preset, for: selectedAssetForOutputConfiguration) else {
            return
        }
        guard selectedOutput.resolutionPreset != preset else {
            return
        }

        selectedOutput.resolutionPreset = preset
        AppLogger.info(
            "Output resolution selected",
            category: .ui,
            metadata: ["resolution": preset.rawValue]
        )
        refreshPreparedSourceAfterOutputChange()
    }

    func selectOutputSize(_ preset: TaptionOutputSizePreset) {
        guard canChangeOutputSizeSelection else {
            AppLogger.warning(
                "Output size change ignored while flow is busy",
                category: .ui,
                metadata: ["size": preset.rawValue]
            )
            return
        }
        guard selectedOutput.sizePreset != preset else {
            return
        }

        selectedOutput.sizePreset = preset
        if preset == .manual, selectedOutput.targetSizeMB == nil {
            selectedOutput.targetSizeMB = selectedOutput.normalizedTargetSizeMB(
                for: selectedAssetForOutputConfiguration
            )
        }
        AppLogger.info(
            "Output size selected",
            category: .ui,
            metadata: ["size": preset.rawValue]
        )
        refreshPreparedSourceAfterOutputChange()
    }

    func updateOutputTargetSizeMB(_ value: Double) {
        guard canChangeOutputSizeSelection else {
            return
        }

        let clamped = min(max(value, outputTargetSizeRangeMB.lowerBound), outputTargetSizeRangeMB.upperBound)
        guard selectedOutput.targetSizeMB != clamped || selectedOutput.sizePreset != .manual else {
            return
        }

        selectedOutput.sizePreset = .manual
        selectedOutput.targetSizeMB = clamped
        AppLogger.info(
            "Output target size updated",
            category: .ui,
            metadata: ["targetMB": String(Int(clamped.rounded()))]
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
        container.defaultFileExtension.uppercased()
    }

    func outputResolutionMenuTitle(_ preset: TaptionOutputResolutionPreset) -> String {
        preset.menuTitle
    }

    func outputSizeMenuTitle(_ preset: TaptionOutputSizePreset) -> String {
        preset.menuTitle
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

    func outputContainerIsAvailableNow(_ container: TaptionVideoContainer) -> Bool {
        let videoState = TaptionCodecOutputCatalog.implementationState(
            videoCodec: selectedOutput.videoCodec,
            container: container
        )
        let audioState = TaptionAudioCodecOutputCatalog.implementationState(
            audioCodec: selectedOutput.audioCodec,
            container: container
        )
        return videoState == .implemented && audioState == .implemented
    }

    func resolutionPresetIsAvailable(
        _ preset: TaptionOutputResolutionPreset,
        for asset: TaptionVideoAsset? = nil
    ) -> Bool {
        guard let sourceSize = asset?.videoTrack?.displaySize,
              let referenceSize = preset.alignedReferenceSize(for: sourceSize) else {
            return true
        }
        return referenceSize.width <= sourceSize.width
            && referenceSize.height <= sourceSize.height
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
            let needsStar = review.videoInfo.isRouteEncodable && starWalletSnapshot.balance == 0
            return [fileCard(
                source: review.source,
                videoInfo: review.videoInfo,
                statusText: needsStar ? "Needs Star" : review.videoInfo.readinessStatusText,
                detailText: needsStar ? needsStarMessage : review.videoInfo.readinessDetailText,
                progress: nil,
                isActive: true,
                isSelected: true,
                isEnabled: review.videoInfo.isRouteEncodable
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
                detailText: "Ready to save the encoded video.",
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
                statusText: "Save Complete",
                detailText: nil,
                progress: completedProgressSnapshot(label: "Save Complete"),
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
        await refreshStarsIfNeeded()

        do {
            let pendingStates = try await environment.pendingSaveStore.loadPendingStates()
            let saveReadyStates = await pendingStatesWithoutSaveAdRequirement(pendingStates)
            beginRestoredPendingSaveAccessIfNeeded(for: saveReadyStates)
            let jobs = saveReadyStates.map(makePendingSaveJob(from:))
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

    func refreshStarsIfNeeded() async {
        if !hasLoadedStarWallet {
            hasLoadedStarWallet = true
        }
        starWalletSnapshot = await environment.starWalletStore.currentSnapshot()
        await refreshRewardedAdState(startPollingIfNeeded: true)
    }

    private func refreshRewardedAdState(startPollingIfNeeded: Bool) async {
        rewardedAdState = await environment.starEarningService.currentAdState()
        if startPollingIfNeeded, rewardedAdState != .ready, !isWatchingStarAd {
            startRewardedAdStatePolling()
        } else if rewardedAdState == .ready {
            rewardedAdStatePollingTask?.cancel()
            rewardedAdStatePollingTask = nil
        }
    }

    private func startRewardedAdStatePolling() {
        rewardedAdStatePollingTask?.cancel()
        rewardedAdStatePollingTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            while !Task.isCancelled {
                let state = await environment.starEarningService.currentAdState()
                rewardedAdState = state
                if state == .ready || isWatchingStarAd {
                    break
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            rewardedAdStatePollingTask = nil
        }
    }

    private func clearActiveStarCharge(for source: HomeSelectedSource) {
        guard activeStarCharge?.sourceURL == source.url else {
            return
        }
        activeStarCharge = nil
    }

    private func refundActiveStarChargeIfNeeded(for source: HomeSelectedSource) {
        guard activeStarCharge?.sourceURL == source.url else {
            return
        }
        let chargedSource = activeStarCharge
        activeStarCharge = nil
        Task { @MainActor [weak self] in
            guard let self, let chargedSource else {
                return
            }
            do {
                starWalletSnapshot = try await environment.starWalletStore.refundStar(
                    source: chargedSource.sourceName
                )
                AppLogger.info(
                    "Consumed star refunded after terminal encoding failure",
                    category: .encoding,
                    metadata: [
                        "source": chargedSource.sourceName,
                        "balance": "\(starWalletSnapshot.balance)"
                    ]
                )
            } catch {
                AppLogger.error(
                    "Consumed star refund failed after terminal encoding failure",
                    category: .encoding,
                    metadata: [
                        "source": chargedSource.sourceName,
                        "error": error.localizedDescription
                    ]
                )
            }
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
        Task { @MainActor [weak self] in
            await self?.attemptEncodingStart(
                for: review,
                autoResumeAfterStarEarn: false
            )
        }
    }

    func watchAdForStar() {
        guard !state.isBusy else {
            AppLogger.info("Watch ad ignored because state is busy", category: .ads)
            return
        }
        guard !isWatchingStarAd else {
            return
        }

        isWatchingStarAd = true
        AppLogger.info("Watch ad for star requested", category: .ads)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            defer {
                isWatchingStarAd = false
            }

            do {
                let result = try await environment.starEarningService.watchAdAndEarnStar()
                starWalletSnapshot = result.snapshot
                await refreshRewardedAdState(startPollingIfNeeded: true)

                guard result.adResult == .earnedReward else {
                    return
                }

                AppLogger.info(
                    "Star rewarded ad completed",
                    category: .ads,
                    metadata: ["balance": "\(result.snapshot.balance)"]
                )

                if shouldAutoResumeBatchAfterStarEarn,
                   let review = state.preparedEncodingReview,
                   canStartEncodingNow {
                    shouldAutoResumeBatchAfterStarEarn = false
                    await attemptEncodingStart(
                        for: review,
                        autoResumeAfterStarEarn: true
                    )
                }
            } catch {
                AppLogger.error(
                    "Watch ad for star failed",
                    category: .ads,
                    metadata: ["error": error.localizedDescription]
                )
                await refreshRewardedAdState(startPollingIfNeeded: true)
            }
        }
    }

    func retryPendingSave() {
        guard let job = nextPendingSaveJobForAction else {
            return
        }
        saveConflictPrompt = nil
        pendingSaveRenamePrompt = nil
        clearPendingSaveExportPrompt()
        savePendingJob(job)
    }

    func saveCurrentPendingOutput() {
        if state.completedTemporaryOutput != nil {
            saveCompletedTemporaryOutput()
            return
        }
        retryPendingSave()
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
        AppLogger.info(
            "User chose Save As for pending output",
            category: .saving,
            metadata: [
                "source": prompt.job.sourceName,
                "suggested": prompt.suggestedURL.lastPathComponent
            ]
        )
        pendingSaveRenamePrompt = PendingSaveRenamePrompt(
            job: prompt.job,
            existingURL: prompt.existingURL,
            suggestedURL: prompt.suggestedURL
        )
    }

    func dismissSaveConflictPrompt() {
        guard saveConflictPrompt != nil else {
            return
        }
        AppLogger.info("Save conflict prompt dismissed", category: .saving)
        saveConflictPrompt = nil
    }

    func confirmPendingSaveAsNewFile(named requestedFileName: String) {
        guard let prompt = pendingSaveRenamePrompt,
              let destinationURL = pendingSaveAsDestinationURL(
                from: prompt,
                requestedFileName: requestedFileName
              ) else {
            return
        }

        pendingSaveRenamePrompt = nil
        var state = prompt.job.state
        state.finalOutputURL = destinationURL
        var job = PendingSaveJob(sourceName: prompt.job.sourceName, state: state)
        job.saveGateMessage = "Saving as \(destinationURL.lastPathComponent)."
        AppLogger.info(
            "Pending save Save As confirmed",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "destination": destinationURL.lastPathComponent
            ]
        )
        savePendingJob(job)
    }

    func dismissPendingSaveRenamePrompt() {
        guard pendingSaveRenamePrompt != nil else {
            return
        }
        AppLogger.info("Pending save rename prompt dismissed", category: .saving)
        pendingSaveRenamePrompt = nil
    }

    func recoverFolderAccessForPendingSave(url: URL) {
        guard let jobToRecover = folderAccessPrompt?.job ?? pendingSaveRecoveryJob else {
            return
        }
        let recoveryURL = normalizedFolderRecoveryURL(for: url)
        folderAccessPrompt = nil
        beginSecurityScopedAccessIfNeeded(for: recoveryURL)

        var updatedState = jobToRecover.state
        updatedState.accessBookmarkData = makeSecurityScopedBookmarkData(for: recoveryURL)
        var job = PendingSaveJob(sourceName: jobToRecover.sourceName, state: updatedState)
        job.saveGateMessage = "Folder access restored. Saving again."
        pendingSaveAccessURLs[job.id] = recoveryURL

        AppLogger.info(
            "Folder access recovery selected",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "folder": recoveryURL.lastPathComponent
            ]
        )

        Task { [weak self] in
            guard let self else {
                return
            }
            try? await environment.pendingSaveStore.savePendingState(updatedState)
        }
        updatePendingSaveJob(job)
        state = .pendingSave(job)
        savePendingJob(job)
    }

    func dismissFolderAccessRecoveryPrompt() {
        guard folderAccessPrompt != nil else {
            return
        }
        AppLogger.info("Folder access recovery prompt dismissed", category: .saving)
        folderAccessPrompt = nil
    }

    func dismissPendingSaveExportPrompt() {
        guard pendingSaveExportPrompt != nil else {
            return
        }
        AppLogger.info("Pending save export prompt dismissed", category: .saving)
        clearPendingSaveExportPrompt()
    }

    func completePendingSaveExport(prompt: PendingSaveExportPrompt, destinationURL: URL) {
        if pendingSaveExportPrompt?.id == prompt.id {
            clearPendingSaveExportPrompt(cleanupPresentationFile: false)
        }
        var recoveredState = prompt.job.state
        recoveredState.finalOutputURL = destinationURL
        let job = PendingSaveJob(sourceName: prompt.job.sourceName, state: recoveredState)
        AppLogger.info(
            "Pending save export finalized",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "saved": destinationURL.lastPathComponent
            ]
        )
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.finishPendingSaveJob(job, savedURL: destinationURL)
        }
    }

    private func clearPendingSaveExportPrompt(cleanupPresentationFile: Bool = true) {
        let prompt = pendingSaveExportPrompt
        pendingSaveExportPrompt = nil

        guard cleanupPresentationFile, let prompt else {
            return
        }
        cleanupPendingSaveExportPresentation(for: prompt.job.id)
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
        activeStarCharge = nil
        shouldAutoResumeBatchAfterStarEarn = false
        saveConflictPrompt = nil
        pendingSaveRenamePrompt = nil
        folderAccessPrompt = nil
        clearPendingSaveExportPrompt()
        pendingSaveQueue = []
        pendingSaveAccessURLs = [:]
        lastBatchFileCards = []
        folderBatch = nil
        rewardedAdStatePollingTask?.cancel()
        rewardedAdStatePollingTask = nil
        state = .idle
        stopSecurityScopedAccess()
        cleanupAllPendingSaveExportPresentations()

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
        activeStarCharge = nil
        shouldAutoResumeBatchAfterStarEarn = false
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

                let asset = try await environment.videoCoreServices.inspector.inspectVideo(at: source.url)
                guard asset.videoTrack != nil else {
                    throw TaptionVideoCoreError.noVideoTrack
                }

                let temporaryOutputURL = makeTemporaryOutputURL(for: source)
                let core = TaptionVideoCore(services: environment.videoCoreServices)
                let savePolicy = defaultSavePolicy(for: source)
                var job = try await core.prepareSingleAssetJob(
                    asset: asset,
                    sourceURL: source.url,
                    temporaryOutputURL: temporaryOutputURL,
                    outputPolicy: selectedOutput.outputPolicy(for: asset),
                    preferredMode: .automatic,
                    savePolicy: savePolicy
                )
                if source.kind == .photos {
                    job.plan.finalOutputURL = nil
                }
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
                guard canEncodeSelectedOutput else {
                    let detail = selectedOutput.isImplementedNow
                        ? job.routeSelection.reason
                        : "\(selectedOutput.implementationState.rawValue) output path is not executable in this build."
                    AppLogger.error(
                        "Prepare encoding blocked due to unsupported route/output",
                        category: .encoding,
                        metadata: [
                            "name": source.displayName,
                            "route": job.routeSelection.route.displayName,
                            "output": selectedOutput.summary,
                            "routeSelection": job.routeSelection.support.rawValue,
                            "state": selectedOutput.implementationState.rawValue
                        ]
                    )
                    markBatchItem(
                        source.url,
                        statusText: "Blocked",
                        detailText: detail,
                        progress: nil,
                        isActive: false
                    )
                    if handleFolderItemFailure(
                        source: source,
                        errorMessage: detail
                    ) {
                        return
                    }
                    state = .failed(HomeEncodingError(
                        title: "Encoding blocked",
                        message: detail
                    ))
                    activeTask = nil
                    stopSecurityScopedAccess()
                    requestSessionEndAd(reason: .failedEncoding)
                    return
                }

                guard job.storageRequirement.hasEnoughSpace else {
                    AppLogger.error(
                        "Storage check blocked encoding",
                        category: .storage,
                        metadata: [
                            "name": source.displayName,
                            "required": "\(job.storageRequirement.requiredWorkingBytes)",
                            "available": job.storageRequirement.availableBytes.map(String.init) ?? "unknown"
                        ]
                    )
                    let storageMessage = storageWarningMessage(
                        requiredBytes: job.storageRequirement.requiredWorkingBytes,
                        availableBytes: job.storageRequirement.availableBytes
                    )
                    markBatchItem(
                        source.url,
                        statusText: "Blocked",
                        detailText: storageMessage,
                        progress: nil,
                        isActive: false
                    )
                    if handleFolderItemFailure(
                        source: source,
                        errorMessage: storageMessage
                    ) {
                        return
                    }
                    state = .storageBlocked(StorageIssue(
                        requiredBytes: job.storageRequirement.requiredWorkingBytes,
                        availableBytes: job.storageRequirement.availableBytes,
                        message: storageMessage
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
                    detailText: review.videoInfo.readinessDetailText,
                    progress: nil,
                    isActive: true
                )

                activeTask = nil
                if autoStartAfterPrepare {
                    await attemptEncodingStart(
                        for: review,
                        autoResumeAfterStarEarn: true
                    )
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
            } catch TaptionVideoCoreError.insufficientStorage(let requiredBytes, let availableBytes) {
                let storageMessage = storageWarningMessage(
                    requiredBytes: requiredBytes,
                    availableBytes: availableBytes
                )
                AppLogger.error(
                    "Prepare encoding blocked due to insufficient storage",
                    category: .storage,
                    metadata: [
                        "name": source.displayName,
                        "required": "\(requiredBytes)",
                        "available": availableBytes.map(String.init) ?? "unknown"
                    ]
                )
                markBatchItem(
                    source.url,
                    statusText: "Blocked",
                    detailText: storageMessage,
                    progress: nil,
                    isActive: false
                )
                if handleFolderItemFailure(source: source, errorMessage: storageMessage) {
                    return
                }
                state = .storageBlocked(StorageIssue(
                    requiredBytes: requiredBytes,
                    availableBytes: availableBytes,
                    message: storageMessage
                ))
                activeTask = nil
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
                    "Encoding completed and queued for final save",
                    category: .encoding,
                    metadata: [
                        "name": review.source.displayName,
                        "plan": result.planID.uuidString,
                        "mode": result.usedMode.rawValue,
                        "backend": result.usedBackend.rawValue,
                        "temporary": result.temporaryOutputURL.lastPathComponent
                    ]
                )
                clearActiveStarCharge(for: review.source)
                let pendingJob = PendingSaveJob(
                    sourceName: review.source.displayName,
                    state: restorablePendingState
                )
                enqueuePendingSaveJob(pendingJob)
                markBatchItem(
                    review.source.url,
                    videoInfo: review.videoInfo,
                    statusText: "Saving",
                    detailText: codecPathDetail(mode: result.usedMode, backend: result.usedBackend),
                    progress: completedProgress,
                    isActive: true
                )
                activeTask = nil
                state = .pendingSave(pendingJob)
                savePendingJob(pendingJob)
            } catch is CancellationError {
                AppLogger.warning(
                    "Encoding task cancelled",
                    category: .encoding,
                    metadata: ["name": review.source.displayName]
                )
                clearActiveStarCharge(for: review.source)
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
                refundActiveStarChargeIfNeeded(for: review.source)
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
                refundActiveStarChargeIfNeeded(for: review.source)
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
            detailText: "Writing the output.",
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
                    workingJob = try await clearRewardedAdRequirement(
                        for: workingJob,
                        rewardedAdCompleted: false
                    )
                }
                markCurrentSaveItem(
                    statusText: "Saving",
                    detailText: "Writing the output.",
                    progress: completedProgressSnapshot(label: "Saving"),
                    isActive: true
                )
                state = .saving(workingJob)

                workingJob.saveGateMessage = nil

                if conflictResolution == .saveAsUnique {
                    try await environment.pendingSaveStore.savePendingState(workingJob.state)
                    updatePendingSaveJob(workingJob)
                }

                let savedURL = try await finalizeSave(
                    for: workingJob.state,
                    conflictResolution: conflictResolution
                )
                await finishPendingSaveJob(workingJob, savedURL: savedURL)
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
                        ? "The save was interrupted and can be retried without another ad."
                        : "Save can be retried without another ad.",
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
                if workingJob.state.saveDestination == .sourceFolder,
                   isFileProviderWritePermissionDenied(error) {
                    workingJob.saveGateMessage = "Choose where to save the encoded video, then the export will continue."
                    updatePendingSaveJob(workingJob)
                    clearPendingSaveExportPrompt()
                    pendingSaveExportPrompt = makePendingSaveExportPrompt(for: workingJob)
                    AppLogger.warning(
                        "Final save needs export picker recovery",
                        category: .saving,
                        metadata: [
                            "source": workingJob.sourceName,
                            "error": error.localizedDescription
                        ]
                    )
                    markCurrentSaveItem(
                        statusText: "Needs Save Location",
                        detailText: workingJob.saveGateMessage,
                        progress: completedProgressSnapshot(label: "Pending Save"),
                        isActive: true
                    )
                    state = .pendingSave(workingJob)
                    activeTask = nil
                    return
                }

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
            }
        }
    }

    private func requestFolderAccessRecoveryIfNeeded(for job: PendingSaveJob) {
        guard job.state.saveDestination == .sourceFolder else {
            return
        }
        folderAccessPrompt = PendingFolderAccessPrompt(job: job)
        AppLogger.info(
            "Folder access recovery requested for restored pending save",
            category: .saving,
            metadata: ["source": job.sourceName]
        )
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

    private func finishPendingSaveJob(
        _ job: PendingSaveJob,
        savedURL: URL
    ) async {
        let completedOutputURL = finalizedOutputURL(savedURL: savedURL, for: job.state)
        let metadataURL: URL
        if FileManager.default.fileExists(atPath: job.state.temporaryOutputURL.path) {
            metadataURL = job.state.temporaryOutputURL
        } else {
            metadataURL = completedOutputURL
        }
        let completedSaveDetail = await completedSaveDetailMessage(
            savedURL: completedOutputURL,
            metadataURL: metadataURL,
            saveDestination: job.state.saveDestination
        )

        do {
            try await environment.pendingSaveStore.removePendingState(id: job.state.id)
        } catch {
            AppLogger.error(
                "Pending save state removal failed after save",
                category: .saving,
                metadata: [
                    "source": job.sourceName,
                    "error": error.localizedDescription
                ]
            )
        }
        try? removeTemporaryOutput(for: job.state)
        removePendingSaveJob(id: job.id)
        AppLogger.info(
            "Final save completed",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "saved": savedURL.lastPathComponent
            ]
        )
        markCurrentSaveItem(
            statusText: "Save Complete",
            detailText: nil,
            progress: completedProgressSnapshot(label: "Save Complete"),
            isActive: false
        )

        if folderBatch != nil,
           handleFolderItemEncoded() {
            activeTask = nil
            return
        }

        let displayName = completedOutputURL.lastPathComponent
        let destination = destinationDescription(for: job.state)
        state = .completed(SavedOutput(
            displayName: displayName,
            destinationDescription: destination,
            detailOverride: completedSaveDetail,
            fileSizeBytes: fileSizeInBytes(at: completedOutputURL)
        ))
        stopSecurityScopedAccess()
        activeTask = nil
    }

    private func saveGateMessage(for decision: AdGateDecision) -> String {
        switch decision {
        case .allowed:
            return "Saving can continue."
        case .unavailable:
            return "The save is temporarily unavailable. Try Save again in a moment."
        case .skipped:
            return "The save was skipped."
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
                    detailText: "Not supported yet. No readable video track.",
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
                    detailText: info.readinessDetailText,
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
                statusText: "Not supported yet",
                detailText: "Not supported yet. \(error.localizedDescription)",
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
        if batch.failedCount > 0 {
            requestSessionEndAd(reason: .failedEncoding)
        }
    }

    private func attemptEncodingStart(
        for review: PreparedEncodingReview,
        autoResumeAfterStarEarn: Bool
    ) async {
        AppLogger.info(
            "Start encoding requested",
            category: .encoding,
            metadata: [
                "name": review.source.displayName,
                "plan": review.job.plan.id.uuidString,
                "autoResumeAfterStarEarn": "\(autoResumeAfterStarEarn)"
            ]
        )

        do {
            starWalletSnapshot = try await environment.starWalletStore.consumeStar(
                source: review.source.displayName
            )
            activeStarCharge = ActiveStarCharge(
                sourceURL: review.source.url,
                sourceName: review.source.displayName
            )
            shouldAutoResumeBatchAfterStarEarn = false
            startEncoding(review: review, allowsBusyState: true)
        } catch let error as StarWalletError {
            if case .insufficientStars = error {
                AppLogger.warning(
                    "Start encoding blocked because no stars are available",
                    category: .encoding,
                    metadata: [
                        "name": review.source.displayName,
                        "balance": "\(starWalletSnapshot.balance)"
                    ]
                )
                if folderBatch != nil {
                    shouldAutoResumeBatchAfterStarEarn = true
                }
                markNeedsStarState(for: review)
                return
            }

            AppLogger.error(
                "Unexpected star wallet error blocked encoding start",
                category: .encoding,
                metadata: [
                    "name": review.source.displayName,
                    "error": error.localizedDescription
                ]
            )
            state = .failed(HomeEncodingError(
                title: "Star error",
                message: error.localizedDescription
            ))
        } catch {
            AppLogger.error(
                "Star debit failed before encoding start",
                category: .encoding,
                metadata: [
                    "name": review.source.displayName,
                    "error": error.localizedDescription
                ]
            )
            state = .failed(HomeEncodingError(
                title: "Star error",
                message: error.localizedDescription
            ))
        }
    }

    private func markNeedsStarState(for review: PreparedEncodingReview) {
        currentReview = review
        markBatchItem(
            review.source.url,
            asset: review.job.asset,
            videoInfo: review.videoInfo,
            statusText: "Needs Star",
            detailText: needsStarMessage,
            progress: nil,
            isActive: false
        )
        state = .readyToStart(review)
    }

    private func folderCompletionMessage(for batch: FolderEncodingBatch) -> String {
        var message = "Folder encoding complete. \(batch.completedCount) of \(batch.totalCount) files were saved."
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
                detailText = "Writing this video."
            } else if isActive {
                statusText = "Pending Save"
                detailText = job.saveGateMessage ?? "Ready to save."
            } else {
                statusText = "Pending Save"
                detailText = job.saveGateMessage ?? "Waiting to save."
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

    private func clearRewardedAdRequirement(
        for job: PendingSaveJob,
        rewardedAdCompleted: Bool
    ) async throws -> PendingSaveJob {
        guard job.state.requiresRewardedAd else {
            return job
        }

        var updatedState = job.state
        updatedState.requiresRewardedAd = false
        updatedState.rewardedAdCompletedAt = rewardedAdCompleted ? Date() : nil
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
        pendingSaveAccessURLs.removeValue(forKey: id)
        cleanupPendingSaveExportPresentation(for: id)
    }

    private func showNextPendingSaveIfNeeded(afterSaving job: PendingSaveJob) -> Bool {
        guard let nextJob = pendingSaveQueue.first else {
            return false
        }

        AppLogger.info(
            "Pending save remains queued after current save completed",
            category: .saving,
            metadata: [
                "previous": job.sourceName,
                "next": nextJob.sourceName,
                "remaining": "\(pendingSaveQueue.count)"
            ]
        )
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
            item.detailText = info.isRouteEncodable ? "\(routeSelection.displayTitle). Ready to encode." : info.readinessDetailText
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
            outputName: job.plan.finalOutputURL?.lastPathComponent ?? outputName(for: source),
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
        let inputSupport = TaptionLaunchSupportCatalog.diagnoseInput(
            container: asset.container,
            videoCodec: videoTrack?.codec ?? .unknown
        )
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
            inputSupportTitle: inputSupport.title,
            inputSupportDetail: inputSupport.detail,
            isInputSupportedNow: inputSupport.isSupportedNow,
            codecPathTitle: videoPath.title,
            codecPathDetail: videoPath.detail,
            outputSummary: videoPath.outputSummary,
            outputName: outputName,
            isRouteEncodable: videoPath.isRouteEncodable
        )
    }

    private func outputName(for source: HomeSelectedSource) -> String {
        let baseName = source.kind == .photos
            ? URL(fileURLWithPath: source.displayName).deletingPathExtension().lastPathComponent
            : source.url.deletingPathExtension().lastPathComponent
        return baseName
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
        return formattedByteCount(bytes)
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func finalizedOutputURL(
        savedURL: URL,
        for state: TaptionPendingSaveState
    ) -> URL {
        guard state.saveDestination == .sourceFolder,
              let finalOutputURL = state.finalOutputURL else {
            return savedURL
        }
        if savedURL.standardizedFileURL == finalOutputURL.standardizedFileURL
            || savedURL.lastPathComponent == finalOutputURL.lastPathComponent {
            return finalOutputURL
        }
        return savedURL
    }

    private func fileSizeInBytes(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return Int64(fileSize)
    }

    private func storageWarningMessage(
        requiredBytes: Int64,
        availableBytes: Int64?
    ) -> String {
        let requiredText = formattedByteCount(requiredBytes)
        let availableText = availableBytes.map(formattedByteCount) ?? "unknown"
        return "Low space. Need \(requiredText) free. Available \(availableText)."
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

    private func defaultSavePolicy(for source: HomeSelectedSource) -> TaptionSavePolicy {
        let destination: TaptionSaveDestinationKind = source.kind == .photos
            ? .photosLibrary
            : .sourceFolder
        return TaptionSavePolicy(
            destination: destination,
            saveGate: .none,
            namingPolicy: TaptionOutputNamingPolicy(suffix: environment.configuration.outputSuffix),
            shouldRestorePendingSaveOnLaunch: true
        )
    }

    private var selectedAssetForOutputConfiguration: TaptionVideoAsset? {
        if let asset = currentReview?.job.asset {
            return asset
        }

        guard let batch = folderBatch,
              let selectedURL = batch.selectedURL else {
            return nil
        }
        return batch.itemStates[selectedURL]?.asset
    }

    private var nextPendingSaveJobForAction: PendingSaveJob? {
        if let job = state.pendingSaveJob {
            return job
        }
        if case .failed = state {
            return pendingSaveQueue.first
        }
        if case .completed = state {
            return pendingSaveQueue.first
        }
        return nil
    }

    private func pendingSaveAsDestinationURL(
        from prompt: PendingSaveRenamePrompt,
        requestedFileName: String
    ) -> URL? {
        let trimmed = requestedFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastComponent = URL(fileURLWithPath: trimmed).lastPathComponent
        let expectedExtension = prompt.suggestedURL.pathExtension
        let baseName = URL(fileURLWithPath: lastComponent)
            .deletingPathExtension()
            .lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseName.isEmpty else {
            return nil
        }
        let fileName = expectedExtension.isEmpty
            ? baseName
            : "\(baseName).\(expectedExtension)"
        return prompt.suggestedURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    private func makePendingSaveExportPrompt(for job: PendingSaveJob) -> PendingSaveExportPrompt {
        PendingSaveExportPrompt(
            job: job,
            exportPresentationURL: preparePendingSaveExportPresentationURL(for: job)
        )
    }

    private func preparePendingSaveExportPresentationURL(for job: PendingSaveJob) -> URL {
        let fileManager = FileManager.default
        let stagingDirectoryURL = pendingSaveExportStagingDirectoryURL(for: job.id)
        let stagingURL = stagingDirectoryURL.appendingPathComponent(
            job.state.finalOutputURL?.lastPathComponent ?? job.sourceName
        )

        do {
            if fileManager.fileExists(atPath: stagingDirectoryURL.path) {
                try fileManager.removeItem(at: stagingDirectoryURL)
            }
            try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)

            do {
                try fileManager.linkItem(at: job.state.temporaryOutputURL, to: stagingURL)
                AppLogger.info(
                    "Pending save export staging prepared with hard link",
                    category: .saving,
                    metadata: [
                        "source": job.sourceName,
                        "staging": stagingURL.lastPathComponent
                    ]
                )
            } catch {
                AppLogger.warning(
                    "Pending save export hard link failed; copying staging file",
                    category: .saving,
                    metadata: [
                        "source": job.sourceName,
                        "staging": stagingURL.lastPathComponent,
                        "error": error.localizedDescription
                    ]
                )
                try fileManager.copyItem(at: job.state.temporaryOutputURL, to: stagingURL)
                AppLogger.info(
                    "Pending save export staging prepared with copy",
                    category: .saving,
                    metadata: [
                        "source": job.sourceName,
                        "staging": stagingURL.lastPathComponent
                    ]
                )
            }

            return stagingURL
        } catch {
            AppLogger.error(
                "Pending save export staging preparation failed; using temporary output directly",
                category: .saving,
                metadata: [
                    "source": job.sourceName,
                    "error": error.localizedDescription
                ]
            )
            return job.state.temporaryOutputURL
        }
    }

    private func pendingSaveExportStagingDirectoryURL(for jobID: UUID) -> URL {
        pendingSaveExportStagingRootDirectoryURL
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
    }

    private func cleanupPendingSaveExportPresentation(for jobID: UUID) {
        let stagingDirectoryURL = pendingSaveExportStagingDirectoryURL(for: jobID)
        guard FileManager.default.fileExists(atPath: stagingDirectoryURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: stagingDirectoryURL)
            AppLogger.info(
                "Pending save export staging cleaned up",
                category: .saving,
                metadata: ["job": jobID.uuidString]
            )
        } catch {
            AppLogger.warning(
                "Pending save export staging cleanup failed",
                category: .saving,
                metadata: [
                    "job": jobID.uuidString,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    private func cleanupAllPendingSaveExportPresentations() {
        guard FileManager.default.fileExists(atPath: pendingSaveExportStagingRootDirectoryURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: pendingSaveExportStagingRootDirectoryURL)
            AppLogger.info("All pending save export staging cleaned up", category: .saving)
        } catch {
            AppLogger.warning(
                "Pending save export staging root cleanup failed",
                category: .saving,
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func completedSaveDetailMessage(
        savedURL: URL,
        metadataURL: URL,
        saveDestination: TaptionSaveDestinationKind
    ) async -> String {
        let fileSizeBytes = fileSizeInBytes(at: metadataURL) ?? fileSizeInBytes(at: savedURL)
        let fileName = savedURL.lastPathComponent
        let fileFormat = savedURL.pathExtension.isEmpty ? "Unknown" : savedURL.pathExtension.uppercased()
        let durationValue: String
        if let asset = try? await environment.mediaInspector.inspectVideo(at: metadataURL) {
            durationValue = durationText(asset.duration)
        } else {
            durationValue = "Unknown"
        }

        let savePath: String
        switch saveDestination {
        case .sourceFolder:
            savePath = savedURL.path
        case .photosLibrary:
            savePath = "Photos"
        case .temporaryOnly:
            savePath = "temporary storage"
        }

        return [
            "File: \(fileName)",
            "Format: \(fileFormat)",
            "Size: \(fileSizeText(fileSizeBytes))",
            "Time: \(durationValue)",
            "Path: \(savePath)"
        ].joined(separator: "\n")
    }

    private var isRefreshingPreparedSourceForOutputChange: Bool {
        guard currentReview != nil else {
            return false
        }

        switch state {
        case .importing, .inspecting, .storageChecking:
            return true
        default:
            return false
        }
    }

    private func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
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
            let securityScopedURL = pendingSaveAccessURLs[state.id]
                ?? resolveSecurityScopedAccessURL(from: state.accessBookmarkData)
            let hasActiveSecurityScope = securityScopedURL.map(hasActiveSecurityScopedAccess(for:)) ?? false
            let didStartSecurityScope = hasActiveSecurityScope
                ? false
                : (securityScopedURL?.startAccessingSecurityScopedResource() ?? false)
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
                    "securityScope": "\(hasActiveSecurityScope || didStartSecurityScope)"
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
                    finalOutputURL = try overwriteFinalOutputOrSaveUnique(
                        temporaryURL: state.temporaryOutputURL,
                        destinationURL: finalOutputURL,
                        fileManager: fileManager
                    )
                    return finalOutputURL
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
            do {
                try fileManager.copyItem(at: state.temporaryOutputURL, to: finalOutputURL)
            } catch where TaptionFinalSaveConflictError.isDestinationAlreadyExistsError(error) {
                AppLogger.warning(
                    "Final save copy collided with an existing destination",
                    category: .saving,
                    metadata: [
                        "temporary": state.temporaryOutputURL.lastPathComponent,
                        "final": finalOutputURL.lastPathComponent,
                        "resolution": "\(conflictResolution)"
                    ]
                )
                switch conflictResolution {
                case .prompt:
                    throw TaptionFinalSaveConflictError.destinationAlreadyExists(finalOutputURL)
                case .overwrite:
                    finalOutputURL = try overwriteFinalOutputOrSaveUnique(
                        temporaryURL: state.temporaryOutputURL,
                        destinationURL: finalOutputURL,
                        fileManager: fileManager
                    )
                case .saveAsUnique:
                    let uniqueURL = uniqueDestinationURL(
                        preferred: finalOutputURL,
                        fileManager: fileManager
                    )
                    try fileManager.copyItem(at: state.temporaryOutputURL, to: uniqueURL)
                    finalOutputURL = uniqueURL
                }
            }
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

    private func overwriteFinalOutputOrSaveUnique(
        temporaryURL: URL,
        destinationURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        do {
            let resultingURL = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
            AppLogger.info(
                "Existing final output replaced",
                category: .saving,
                metadata: ["final": destinationURL.lastPathComponent]
            )
            return resultingURL ?? destinationURL
        } catch where isFileProviderWritePermissionDenied(error) {
            let uniqueURL = uniqueDestinationURL(
                preferred: destinationURL,
                fileManager: fileManager
            )
            AppLogger.warning(
                "Overwrite was denied by the file provider; saving with a unique name",
                category: .saving,
                metadata: [
                    "original": destinationURL.lastPathComponent,
                    "unique": uniqueURL.lastPathComponent
                ]
            )
            try fileManager.copyItem(at: temporaryURL, to: uniqueURL)
            return uniqueURL
        }
    }

    private func isFileProviderWritePermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            let cocoaCode = CocoaError.Code(rawValue: nsError.code)
            if cocoaCode == .fileWriteNoPermission || cocoaCode == .fileReadNoPermission {
                return true
            }
        }

        let permissionDeniedPOSIXCodes = [
            Int(POSIXErrorCode.EPERM.rawValue),
            Int(POSIXErrorCode.EACCES.rawValue)
        ]
        if nsError.domain == NSPOSIXErrorDomain,
           permissionDeniedPOSIXCodes.contains(nsError.code) {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isFileProviderWritePermissionDenied(underlying)
        }

        return false
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

    private func pendingStatesWithoutSaveAdRequirement(
        _ states: [TaptionPendingSaveState]
    ) async -> [TaptionPendingSaveState] {
        var updatedStates: [TaptionPendingSaveState] = []
        for state in states {
            guard state.requiresRewardedAd else {
                updatedStates.append(state)
                continue
            }

            var updatedState = state
            updatedState.requiresRewardedAd = false
            updatedState.rewardedAdCompletedAt = nil
            do {
                try await environment.pendingSaveStore.savePendingState(updatedState)
                AppLogger.info(
                    "Restored pending save no longer requires save-time ad",
                    category: .saving,
                    metadata: ["id": updatedState.id.uuidString]
                )
            } catch {
                AppLogger.warning(
                    "Failed to persist save-time ad removal for restored pending save",
                    category: .saving,
                    metadata: [
                        "id": updatedState.id.uuidString,
                        "error": error.localizedDescription
                    ]
                )
            }
            updatedStates.append(updatedState)
        }
        return updatedStates
    }

    private func pendingSaveStateWithAccessBookmark(
        _ state: TaptionPendingSaveState,
        source: HomeSelectedSource
    ) async -> TaptionPendingSaveState {
        var updatedState = state
        guard source.kind != .photos else {
            return updatedState
        }
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
        if source.kind == .files {
            return source.url.deletingLastPathComponent()
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
                "Access bookmark created",
                category: .fileImport,
                metadata: ["name": url.lastPathComponent]
            )
            return data
        } catch {
            AppLogger.warning(
                "Access bookmark creation failed",
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
                "Access bookmark resolved",
                category: .fileImport,
                metadata: [
                    "name": url.lastPathComponent,
                    "isStale": "\(isStale)"
                ]
            )
            return url
        } catch {
            AppLogger.warning(
                "Access bookmark resolve failed",
                category: .fileImport,
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    private func beginRestoredPendingSaveAccessIfNeeded(for states: [TaptionPendingSaveState]) {
        let recoveredAccessURLs = states.compactMap { state in
            resolveSecurityScopedAccessURL(from: state.accessBookmarkData).map { (state.id, $0) }
        }
        for (id, url) in recoveredAccessURLs {
            pendingSaveAccessURLs[id] = url
        }
        let urls = recoveredAccessURLs.map(\.1)
        guard !urls.isEmpty else {
            return
        }
        beginSecurityScopedAccessIfNeeded(for: urls)
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
        case (.software, .softwareVLCDecoder):
            return "Native conversion was unavailable, so the app used the VLC-based software decode path automatically."
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

    private func normalizedFolderRecoveryURL(for url: URL) -> URL {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              values.isDirectory == false else {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func hasActiveSecurityScopedAccess(for url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        return securityScopedURLs.contains { scopedURL in
            scopedURL.standardizedFileURL == standardizedURL
        }
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
