import Foundation
import Photos
import UIKit

private enum PendingSaveConflictResolution: Equatable {
    case prompt
    case overwrite
    case saveAsUnique
}

private struct ActiveStarCharge: Equatable {
    var sourceURL: URL
    var sourceName: String
}

struct BatteryEncodingAlert: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var message: String
}

protocol BatteryPowerMonitoring {
    var currentSnapshot: BatteryEncodingPowerSnapshot { get }
}

struct UIDeviceBatteryPowerMonitor: BatteryPowerMonitoring {
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var currentSnapshot: BatteryEncodingPowerSnapshot {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let batteryLevel = device.batteryLevel
        let batteryPercent: Int? = batteryLevel >= 0
            ? Int((batteryLevel * 100).rounded())
            : nil
        let batteryState = device.batteryState
        return BatteryEncodingPowerSnapshot(
            batteryPercent: batteryPercent,
            isPowerConnected: batteryState == .charging || batteryState == .full,
            isPowerStateKnown: batteryState != .unknown
        )
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    private static let previewKnownNoVideoOutputCodecs: Set<TaptionVideoCodec> = [
        .losslessJPEG,
        .microsoftRLE,
        .r10k,
        .r210,
        .snow
    ]

    @Published private(set) var state: HomeScreenState
    @Published private(set) var selectedOutput: TaptionOutputSelection
    @Published private(set) var pendingSaveDestinationPrompt: PendingSaveDestinationPrompt?
    @Published private(set) var starWalletSnapshot: StarWalletSnapshot
    @Published private(set) var rewardedAdState: AdLoadState
    @Published private(set) var isWatchingStarAd: Bool
    @Published private(set) var activePreview: QueueVideoPreview?
    @Published private(set) var importBrowserContext: HomeImportBrowserContext?
    @Published private(set) var importBrowserFolders: [HomeImportBrowserFolderSnapshot]
    @Published private(set) var importBrowserFiles: [HomeImportBrowserFileSnapshot]
    @Published private(set) var folderPreviewContext: FolderPreviewContext?
    @Published private(set) var batteryEncodingAlert: BatteryEncodingAlert?

    private let environment: AppEnvironment
    private let batteryPowerMonitor: any BatteryPowerMonitoring
    private let batterySettingsProvider: () -> BatteryEncodingSettings
    private var activeTask: Task<Void, Never>?
    private var folderBatch: FolderEncodingBatch?
    private var currentReview: PreparedEncodingReview?
    private var pendingSaveQueue: [PendingSaveJob] = []
    private var lastBatchFileCards: [EncodingFileCardSnapshot] = []
    private var selectionInspectionTask: Task<Void, Never>?
    private var previewInspectionTask: Task<Void, Never>?
    private var inspectedMediaCache = TaptionInspectedMediaCache()
    private var hasRestoredPendingSaves = false
    private var hasLoadedStarWallet = false
    private var pendingSaveAccessURLs: [UUID: URL] = [:]
    private var securityScopedURLs: [URL] = []
    private var importBrowserMode: HomeImportBrowserMode?
    private var importBrowserRootURL: URL?
    private var importBrowserCurrentURL: URL?
    private var importBrowserHistory: [URL] = []
    private var importBrowserSelectedFileURLs: Set<URL> = []
    private var activeStarCharge: ActiveStarCharge?
    private var shouldAutoResumeBatchAfterStarEarn = false
    private var rewardedAdStatePollingTask: Task<Void, Never>?
    private var activeEncodingActivitySessionID: UUID?
    private var lastEncodingActivitySnapshot: TaptionEncodingActivitySnapshot?
    private var deferredBatteryStopReason: BatteryEncodingBlockReason?
    private var batteryObservationTokens: [NSObjectProtocol] = []

    init(
        environment: AppEnvironment = .phase0,
        batteryPowerMonitor: any BatteryPowerMonitoring = UIDeviceBatteryPowerMonitor(),
        batterySettingsProvider: @escaping () -> BatteryEncodingSettings = { BatteryEncodingSettings.load() }
    ) {
        self.environment = environment
        self.batteryPowerMonitor = batteryPowerMonitor
        self.batterySettingsProvider = batterySettingsProvider
        self.selectedOutput = TaptionOutputSelection(
            videoCodec: environment.configuration.defaultOutputCodec,
            container: environment.configuration.defaultOutputContainer
        )
        self.state = .idle
        self.pendingSaveDestinationPrompt = nil
        self.starWalletSnapshot = .empty
        self.rewardedAdState = .idle
        self.isWatchingStarAd = false
        self.activePreview = nil
        self.importBrowserContext = nil
        self.importBrowserFolders = []
        self.importBrowserFiles = []
        self.folderPreviewContext = nil
        self.batteryEncodingAlert = nil
        observeBatteryPowerChanges()
        AppLogger.info(
            "HomeViewModel initialized",
            category: .app,
            metadata: ["appName": environment.configuration.appName]
        )
    }

    deinit {
        AppLogger.info("HomeViewModel deinitialized", category: .app)
        activeTask?.cancel()
        selectionInspectionTask?.cancel()
        previewInspectionTask?.cancel()
        rewardedAdStatePollingTask?.cancel()
        for token in batteryObservationTokens {
            NotificationCenter.default.removeObserver(token)
        }
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
        return review.videoInfo.isRouteEncodable
    }

    var startActionTitle: String {
        let starCost = estimatedStartStarCost
        guard starCost > 0 else {
            return "Start"
        }
        return "Start (\(formattedStarDelta(-starCost)))"
    }

    var watchAdButtonTitle: String {
        if isWatchingStarAd {
            return "Watching Ad..."
        }
        if let pendingSaveJob = state.pendingSaveJob,
           pendingSaveJob.state.requiresRewardedAd {
            switch rewardedAdState {
            case .ready:
                return "Watch Ad to Save"
            case .loading, .idle:
                return "Ad Loading"
            case .unavailable:
                return "Find Ad"
            }
        }
        switch rewardedAdState {
        case .ready:
            return "Watch Ad (+1 Star)"
        case .loading, .idle:
            return "Ad Loading"
        case .unavailable:
            return "Find Ad"
        }
    }

    var canWatchAdForStar: Bool {
        !state.isBusy && !isWatchingStarAd
    }

    func dismissBatteryEncodingAlert() {
        batteryEncodingAlert = nil
    }

    private func observeBatteryPowerChanges() {
        let center = NotificationCenter.default
        batteryObservationTokens = [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification
        ].map { name in
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.captureDeferredBatteryStopIfNeeded()
                }
            }
        }
    }

    private func currentBatteryEncodingBlockReason() -> BatteryEncodingBlockReason? {
        BatteryEncodingGate.blockReason(
            settings: batterySettingsProvider(),
            snapshot: batteryPowerMonitor.currentSnapshot
        )
    }

    private func blockEncodingStart(
        for review: PreparedEncodingReview,
        reason: BatteryEncodingBlockReason
    ) {
        AppLogger.warning(
            "Encoding start blocked by battery settings",
            category: .encoding,
            metadata: [
                "name": review.source.displayName,
                "reason": reason.alertMessage
            ]
        )
        batteryEncodingAlert = BatteryEncodingAlert(
            title: reason.alertTitle,
            message: reason.alertMessage
        )
        activeTask = nil
        state = .readyToStart(review)
    }

    private func captureDeferredBatteryStopIfNeeded() {
        guard folderBatch != nil,
              deferredBatteryStopReason == nil,
              state.isBusy,
              let reason = currentBatteryEncodingBlockReason() else {
            return
        }

        deferredBatteryStopReason = reason
        AppLogger.warning(
            "Folder batch will stop after current item due to battery settings",
            category: .encoding,
            metadata: ["reason": reason.batchStopMessage]
        )
    }

    private var estimatedStartStarCost: Int {
        guard let review = state.preparedEncodingReview,
              review.videoInfo.isRouteEncodable else {
            return 0
        }
        guard let folderBatch else {
            return 1
        }
        return max(folderBatch.remainingEncodableFileCount, 1)
    }

    private func formattedStarDelta(_ delta: Int) -> String {
        let absoluteValue = abs(delta)
        let sign = delta < 0 ? "-" : "+"
        let noun = absoluteValue == 1 ? "Star" : "Stars"
        return "\(sign)\(absoluteValue) \(noun)"
    }

    var progressDetailText: String {
        return state.detail
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
        if selectedOutput.sizePreset != .manual {
            return selectedOutput.sizePreset.menuTitle
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
        if selectedOutput.sizePreset != .manual {
            return "~\(selectedOutputTargetSizeText)"
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
        return "Estimated output: \(selectedOutputTargetSizeText)."
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
        if #available(iOS 26.0, *) {
            if environment.liveActivityCoordinator.areActivitiesEnabled {
                return "Background encoding can continue after lock. Progress appears on the Lock Screen and Dynamic Island."
            }
            return "Background encoding can continue after lock. Turn on Live Activities in iOS settings to show Lock Screen progress."
        }
        return "Keep Taption Encoder open for reliable encoding on this iOS version."
    }

    var showsSaveAction: Bool {
        if let pendingSaveJob = state.pendingSaveJob,
           pendingSaveJob.state.requiresRewardedAd {
            return false
        }
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
            return [fileCard(
                source: review.source,
                videoInfo: review.videoInfo,
                statusText: review.videoInfo.readinessStatusText,
                detailText: review.videoInfo.readinessDetailText,
                progress: nil,
                isActive: true,
                isSelected: true,
                isEnabled: review.videoInfo.isRouteEncodable,
                isPreviewable: isPreviewableInCurrentBuild(asset: review.job.asset)
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
                    isEnabled: true,
                    isPreviewable: isPreviewableInCurrentBuild(asset: currentReview.job.asset)
                )]
            }
            return []
        case .waitingForReward(let output):
            return [fileCard(
                sourceName: output.sourceName,
                sourceKind: currentReview?.source.kind ?? .files,
                thumbnailSourceURL: currentReview?.source.url,
                videoInfo: currentReview?.videoInfo,
                statusText: "Waiting to Save",
                detailText: "Ready to save the encoded video.",
                progress: completedProgressSnapshot(label: codecPathTitle(mode: output.usedEncoderMode)),
                isActive: true,
                isSelected: true,
                isEnabled: true,
                isPreviewable: currentReview.map { isPreviewableInCurrentBuild(asset: $0.job.asset) } ?? false
            )]
        case .saving(let job):
            return [fileCard(
                sourceName: job.sourceName,
                sourceKind: currentReview?.source.kind ?? .files,
                thumbnailSourceURL: currentReview?.source.url,
                videoInfo: currentReview?.videoInfo,
                statusText: "Saving",
                detailText: "Writing the completed H.265 output.",
                progress: completedProgressSnapshot(label: "Saving"),
                isActive: true,
                isSelected: true,
                isEnabled: true,
                isPreviewable: currentReview.map { isPreviewableInCurrentBuild(asset: $0.job.asset) } ?? false
            )]
        case .pendingSave(let job):
            let requiresRewardedAd = job.state.requiresRewardedAd
            return [fileCard(
                sourceName: job.sourceName,
                sourceKind: currentReview?.source.kind ?? .files,
                thumbnailSourceURL: currentReview?.source.url,
                videoInfo: currentReview?.videoInfo,
                statusText: requiresRewardedAd ? "Watch Ad to Save" : "Pending Save",
                detailText: job.saveGateMessage ?? (
                    requiresRewardedAd
                        ? "Watch a rewarded ad to save this completed video."
                        : "This output can be saved without re-encoding."
                ),
                progress: completedProgressSnapshot(label: requiresRewardedAd ? "Ready to Save" : "Pending Save"),
                isActive: true,
                isSelected: true,
                isEnabled: true,
                isPreviewable: currentReview.map { isPreviewableInCurrentBuild(asset: $0.job.asset) } ?? false
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

    var folderPreviewFileSnapshots: [EncodingFileCardSnapshot] {
        guard folderPreviewContext != nil else {
            return []
        }
        return folderBatch?.cardSnapshots() ?? []
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
            let restorableStates = restorablePendingStates(pendingStates)
            beginRestoredPendingSaveAccessIfNeeded(for: restorableStates)
            let jobs = restorableStates.map(makePendingSaveJob(from:))
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
        let nextState: AdLoadState
        if startPollingIfNeeded {
            nextState = await environment.starEarningService.prepareNextAd()
        } else {
            nextState = await environment.starEarningService.currentAdState()
        }
        applyRewardedAdState(nextState, startPollingIfNeeded: startPollingIfNeeded)
    }

    private func applyRewardedAdState(
        _ nextState: AdLoadState,
        startPollingIfNeeded: Bool
    ) {
        rewardedAdState = nextState
        if startPollingIfNeeded, nextState != .ready, !isWatchingStarAd {
            startRewardedAdStatePolling()
        } else if nextState == .ready {
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
                let state = await environment.starEarningService.prepareNextAd()
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

    func handleFolderPickerSelection(urls: [URL]) {
        let selectedURLs = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        guard let firstURL = selectedURLs.first else {
            return
        }

        let fileURLs = selectedURLs.filter { !selectedURLIsDirectory($0) }
        if !fileURLs.isEmpty {
            if fileURLs.count == 1 {
                startFilesFlow(url: fileURLs[0])
            } else {
                startFilesFlow(urls: fileURLs)
            }
            return
        }

        startFolderFlow(url: firstURL)
    }

    func openImportBrowser(mode: HomeImportBrowserMode) {
        guard canStartNewSourceFlow() else {
            return
        }
        guard state.canSelectSource else {
            AppLogger.warning(
                "Import browser ignored because source selection is disabled",
                category: .fileImport,
                metadata: ["mode": mode.rawValue, "state": "\(state)"]
            )
            return
        }

        if importBrowserMode != mode {
            clearImportBrowserState(stoppingAccess: true)
        }
        importBrowserMode = mode
        refreshImportBrowser()
    }

    func openImportBrowserRoot(url: URL, mode: HomeImportBrowserMode) {
        guard canStartNewSourceFlow() else {
            return
        }
        guard state.canSelectSource else {
            AppLogger.warning(
                "Import browser root ignored because source selection is disabled",
                category: .fileImport,
                metadata: ["mode": mode.rawValue, "state": "\(state)"]
            )
            return
        }

        AppLogger.info(
            "Import browser root opened",
            category: .fileImport,
            metadata: ["mode": mode.rawValue, "name": url.lastPathComponent]
        )
        dismissPreview()
        activeTask?.cancel()
        selectionInspectionTask?.cancel()
        previewInspectionTask?.cancel()
        currentReview = nil
        lastBatchFileCards = []
        folderPreviewContext = nil
        folderBatch = nil
        beginSecurityScopedAccessIfNeeded(for: url)
        importBrowserMode = mode
        importBrowserRootURL = url
        importBrowserCurrentURL = url
        importBrowserHistory = []
        importBrowserSelectedFileURLs = []
        refreshImportBrowser()
        state = .idle
    }

    func dismissImportBrowser() {
        clearImportBrowserState(stoppingAccess: true)
    }

    func navigateImportBrowserIntoFolder(id: String) {
        guard let folder = importBrowserFolders.first(where: { $0.id == id }) else {
            return
        }
        if importBrowserCurrentURL == nil {
            openImportBrowserRoot(
                url: URL(fileURLWithPath: folder.id),
                mode: importBrowserMode ?? .files
            )
            return
        }

        guard let currentURL = importBrowserCurrentURL else {
            return
        }
        importBrowserHistory.append(currentURL)
        importBrowserCurrentURL = URL(fileURLWithPath: folder.id)
        refreshImportBrowser()
    }

    func navigateImportBrowserBack() {
        guard let previousURL = importBrowserHistory.popLast() else {
            guard importBrowserRootURL != nil else {
                return
            }
            importBrowserRootURL = nil
            importBrowserCurrentURL = nil
            importBrowserHistory = []
            importBrowserSelectedFileURLs = []
            stopSecurityScopedAccess()
            refreshImportBrowser()
            return
        }
        importBrowserCurrentURL = previousURL
        refreshImportBrowser()
    }

    func navigateImportBrowserUp() {
        guard let rootURL = importBrowserRootURL?.standardizedFileURL,
              let currentURL = importBrowserCurrentURL?.standardizedFileURL,
              currentURL != rootURL else {
            return
        }

        let parentURL = currentURL.deletingLastPathComponent()
        guard importBrowserURL(parentURL, isInsideRoot: rootURL) else {
            return
        }
        importBrowserHistory.append(currentURL)
        importBrowserCurrentURL = parentURL
        refreshImportBrowser()
    }

    func toggleImportBrowserFileSelection(id: String) {
        guard importBrowserMode == .files,
              importBrowserFiles.contains(where: { $0.id == id }) else {
            return
        }
        let url = URL(fileURLWithPath: id).standardizedFileURL
        if importBrowserSelectedFileURLs.contains(url) {
            importBrowserSelectedFileURLs.remove(url)
        } else {
            importBrowserSelectedFileURLs.insert(url)
        }
        refreshImportBrowser()
    }

    func importFromImportBrowser() {
        guard let mode = importBrowserMode,
              let currentURL = importBrowserCurrentURL else {
            return
        }

        switch mode {
        case .files:
            let selectedURLs = importBrowserSelectedFileURLs.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            guard !selectedURLs.isEmpty else {
                AppLogger.warning("Import browser file import ignored because no files are selected", category: .fileImport)
                return
            }
            let rootURL = importBrowserRootURL
            clearImportBrowserState(stoppingAccess: false)
            openFilesPreviewBrowser(urls: selectedURLs, securityScopedRootURL: rootURL)
        case .folder:
            let rootURL = importBrowserRootURL
            clearImportBrowserState(stoppingAccess: false)
            startFolderFlow(url: currentURL, securityScopedRootURL: rootURL)
        }
    }

    func openFilesPreviewBrowser(urls: [URL]) {
        openFilesPreviewBrowser(urls: urls, securityScopedRootURL: nil)
    }

    private func openFilesPreviewBrowser(urls: [URL], securityScopedRootURL: URL?) {
        AppLogger.info(
            "Files preview browser requested",
            category: .fileImport,
            metadata: [
                "count": "\(urls.count)",
                "names": urls.map(\.lastPathComponent).joined(separator: "|")
            ]
        )
        guard canStartNewSourceFlow() else {
            return
        }
        guard state.canSelectSource else {
            AppLogger.warning(
                "Files preview browser ignored because source selection is disabled",
                category: .fileImport,
                metadata: ["state": "\(state)"]
            )
            return
        }

        let selectedURLs = urls
            .filter { !selectedURLIsDirectory($0) }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        guard !selectedURLs.isEmpty else {
            AppLogger.warning("Files preview browser ignored because no files were selected", category: .fileImport)
            return
        }

        let title = filesPreviewBrowserTitle(for: selectedURLs)
        dismissPreview()
        activeTask?.cancel()
        selectionInspectionTask?.cancel()
        previewInspectionTask?.cancel()
        currentReview = nil
        lastBatchFileCards = []
        folderPreviewContext = nil
        folderBatch = FolderEncodingBatch(
            folderName: title,
            sourceKind: .files,
            fileURLs: selectedURLs
        )
        let scopedURLs = ([securityScopedRootURL].compactMap { $0 } + selectedURLs)
        beginSecurityScopedAccessIfNeeded(for: scopedURLs)
        folderPreviewContext = FolderPreviewContext(
            id: "selected-files-\(UUID().uuidString)",
            folderName: title,
            fileCount: selectedURLs.count
        )
        state = .idle
    }

    func openExternalPlayerFile(url: URL) {
        AppLogger.info(
            "External player file routed into preview flow",
            category: .fileImport,
            metadata: ["name": url.lastPathComponent]
        )
        startFilesFlow(url: url)
    }

    #if DEBUG
    func openDebugFileAndStartEncoding(url: URL) {
        AppLogger.info(
            "Debug file routed into auto-start encoding flow",
            category: .fileImport,
            metadata: ["name": url.lastPathComponent]
        )
        startFilesFlow(url: url, autoStartAfterPrepare: true)
    }
    #endif

    func startFilesFlow(url: URL) {
        startFilesFlow(url: url, autoStartAfterPrepare: false)
    }

    private func startFilesFlow(url: URL, autoStartAfterPrepare: Bool) {
        AppLogger.info(
            "Single file flow started",
            category: .fileImport,
            metadata: [
                "name": url.lastPathComponent,
                "autoStart": "\(autoStartAfterPrepare)"
            ]
        )
        guard canStartNewSourceFlow() else {
            return
        }
        dismissPreview()
        selectionInspectionTask?.cancel()
        folderBatch = nil
        folderPreviewContext = nil
        currentReview = nil
        lastBatchFileCards = []
        let source = HomeSelectedSource(
            kind: .files,
            displayName: url.lastPathComponent,
            url: url
        )
        beginSecurityScopedAccessIfNeeded(for: url)
        prepareEncodingFlow(source: source, autoStartAfterPrepare: autoStartAfterPrepare)
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

        dismissPreview()
        activeTask?.cancel()
        selectionInspectionTask?.cancel()
        currentReview = nil
        lastBatchFileCards = []
        folderPreviewContext = nil
        folderBatch = FolderEncodingBatch(
            folderName: "Selected files",
            sourceKind: .files,
            fileURLs: selectedURLs
        )
        beginSecurityScopedAccessIfNeeded(for: selectedURLs)
        preflightCurrentBatchThenPrepareFirst(displayName: "Selected files")
    }

    func startFolderFlow(url: URL) {
        startFolderFlow(url: url, securityScopedRootURL: nil)
    }

    private func startFolderFlow(url: URL, securityScopedRootURL: URL?) {
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
        dismissPreview()
        activeTask?.cancel()
        selectionInspectionTask?.cancel()
        currentReview = nil
        lastBatchFileCards = []
        folderPreviewContext = nil
        folderBatch = nil
        let scopedURLs = ([securityScopedRootURL].compactMap { $0 } + [url])
        beginSecurityScopedAccessIfNeeded(for: scopedURLs)

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
            folderPreviewContext = FolderPreviewContext(
                id: url.standardizedFileURL.absoluteString,
                folderName: url.lastPathComponent,
                fileCount: fileURLs.count
            )
            state = .idle
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

    func openSampleLibrary(fileManager: FileManager = .default) {
        guard canStartNewSourceFlow() else {
            return
        }
        guard state.canSelectSource else {
            AppLogger.warning(
                "Sample library ignored because source selection is disabled",
                category: .folderImport,
                metadata: ["state": "\(state)"]
            )
            return
        }

        do {
            var sampleFolderURL = try TaptionTestVideoSeeder.documentsSampleFolderURL(fileManager: fileManager)
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: sampleFolderURL.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                TaptionTestVideoSeeder.seedBundledSamplesIntoDocuments(fileManager: fileManager)
                sampleFolderURL = try TaptionTestVideoSeeder.documentsSampleFolderURL(fileManager: fileManager)
            }

            AppLogger.info(
                "Sample library opened without Files picker",
                category: .folderImport,
                metadata: ["path": sampleFolderURL.path]
            )
            startFolderFlow(url: sampleFolderURL)
        } catch {
            AppLogger.error(
                "Sample library failed",
                category: .folderImport,
                metadata: ["error": error.localizedDescription]
            )
            state = .failed(HomeEncodingError(
                title: "Samples failed",
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
        dismissPreview()
        selectionInspectionTask?.cancel()
        folderBatch = nil
        folderPreviewContext = nil
        currentReview = nil
        lastBatchFileCards = []
        let source = HomeSelectedSource(
            kind: .photos,
            displayName: displayName,
            url: url
        )
        prepareEncodingFlow(source: source)
    }

    func openPreviewForFileCard(id: String) {
        if openBatchPreviewForFileCard(id: id) {
            return
        }

        guard !state.isBusy else {
            AppLogger.info(
                "Preview ignored because the encoder is busy",
                category: .ui,
                metadata: ["id": id]
            )
            return
        }

        guard let preview = currentReviewPreview(for: id) else {
            AppLogger.warning("File card preview ignored because item was not found", category: .ui)
            return
        }

        presentPreview(preview)
    }

    func selectFolderPreviewFile(id: String) {
        _ = openBatchPreviewForFileCard(id: id)
    }

    func importFolderPreviewBatch() {
        guard let context = folderPreviewContext,
              folderBatch != nil else {
            AppLogger.warning("Folder preview import ignored because no preview batch exists", category: .folderImport)
            return
        }
        AppLogger.info(
            "Folder preview import accepted",
            category: .folderImport,
            metadata: [
                "name": context.folderName,
                "count": "\(context.fileCount)"
            ]
        )
        folderPreviewContext = nil
        preflightCurrentBatchThenPrepareFirst(displayName: context.folderName)
    }

    func dismissFolderPreviewBrowser() {
        guard let context = folderPreviewContext else {
            return
        }
        AppLogger.info(
            "Folder preview browser dismissed",
            category: .folderImport,
            metadata: ["name": context.folderName]
        )
        folderPreviewContext = nil
        folderBatch = nil
        selectionInspectionTask?.cancel()
        selectionInspectionTask = nil
        stopSecurityScopedAccess()
        if !state.isBusy {
            state = .idle
        }
    }

    func dismissPreview() {
        previewInspectionTask?.cancel()
        previewInspectionTask = nil
        if let activePreview {
            AppLogger.info(
                "Queue preview dismissed",
                category: .ui,
                metadata: ["name": activePreview.displayName]
            )
        }
        activePreview = nil
    }

    func restorePreview(_ preview: QueueVideoPreview) {
        AppLogger.info(
            "Queue mini player restored to full preview",
            category: .ui,
            metadata: ["name": preview.displayName]
        )
        presentPreview(preview)
    }

    func openPreviousPreview() {
        openAdjacentPreview(offset: -1)
    }

    func openNextPreview() {
        openAdjacentPreview(offset: 1)
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
        dismissPreview()
        Task { @MainActor [weak self] in
            await self?.attemptEncodingStart(
                for: review,
                autoResumeAfterStarEarn: false
            )
        }
    }

    private func openBatchPreviewForFileCard(id: String) -> Bool {
        guard var batch = folderBatch,
              let selectedURL = batch.fileURLs.first(where: { $0.absoluteString == id }) else {
            return false
        }

        guard canOpenFolderPreviewInCurrentState else {
            AppLogger.info(
                "Folder preview ignored because the encoder is processing output",
                category: .ui,
                metadata: ["id": id]
            )
            return true
        }

        let item = batch.itemStates[selectedURL] ?? .queued
        guard item.isEnabled || item.isPreviewable else {
            AppLogger.info(
                "Disabled file card preview ignored",
                category: .ui,
                metadata: [
                    "name": selectedURL.lastPathComponent,
                    "status": item.statusText
                ]
            )
            return true
        }

        batch.selectedURL = selectedURL
        folderBatch = batch
        objectWillChange.send()

        if let preview = batchPreview(for: selectedURL) {
            presentPreview(preview)
            return true
        }

        guard item.videoInfo == nil else {
            AppLogger.info(
                "Queue preview ignored because route is not encodable",
                category: .ui,
                metadata: [
                    "name": selectedURL.lastPathComponent,
                    "status": item.statusText
                ]
            )
            return true
        }

        previewInspectionTask?.cancel()
        previewInspectionTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await self.inspectSelectedBatchItemInfo(url: selectedURL)
            guard !Task.isCancelled,
                  let preview = self.batchPreview(for: selectedURL) else {
                return
            }
            self.presentPreview(preview)
        }
        return true
    }

    private func openAdjacentPreview(offset: Int) {
        guard offset != 0,
              let activePreview,
              let batch = folderBatch,
              let currentIndex = batch.fileURLs.firstIndex(of: activePreview.sourceURL),
              let targetURL = adjacentPreviewURL(in: batch, currentIndex: currentIndex, offset: offset) else {
            AppLogger.info(
                "Queue preview adjacent navigation ignored",
                category: .ui,
                metadata: ["direction": offset < 0 ? "previous" : "next"]
            )
            return
        }

        AppLogger.info(
            "Queue preview adjacent navigation requested",
            category: .ui,
            metadata: [
                "direction": offset < 0 ? "previous" : "next",
                "from": activePreview.displayName,
                "to": targetURL.lastPathComponent
            ]
        )
        _ = openBatchPreviewForFileCard(id: targetURL.absoluteString)
    }

    private func currentReviewPreview(for id: String) -> QueueVideoPreview? {
        guard let review = currentReview ?? state.preparedEncodingReview,
              isPreviewableInCurrentBuild(asset: review.job.asset),
              id == review.source.displayName
                || id == review.source.url.absoluteString
                || id == review.source.id.uuidString else {
            return nil
        }

        return QueueVideoPreview(
            id: review.source.url.absoluteString,
            displayName: review.source.displayName,
            sourceURL: review.source.url,
            videoInfo: review.videoInfo,
            displaySize: review.job.asset.videoTrack?.displaySize
        )
    }

    private func batchPreview(for url: URL) -> QueueVideoPreview? {
        guard let batch = folderBatch,
              let item = batch.itemStates[url],
              item.isPreviewable,
              let videoInfo = item.videoInfo,
              item.asset?.videoTrack != nil else {
            return nil
        }

        return QueueVideoPreview(
            id: url.absoluteString,
            displayName: url.lastPathComponent,
            sourceURL: url,
            videoInfo: videoInfo,
            displaySize: item.asset?.videoTrack?.displaySize,
            playlist: batchPreviewPlaylist(for: url, in: batch)
        )
    }

    private func batchPreviewPlaylist(
        for url: URL,
        in batch: FolderEncodingBatch
    ) -> QueueVideoPreviewPlaylist? {
        guard let currentIndex = batch.fileURLs.firstIndex(of: url) else {
            return nil
        }

        let previewCandidateURLs = batch.fileURLs.filter { candidateURL in
            isQueuePreviewNavigationCandidate(batch.itemStates[candidateURL] ?? .queued)
        }
        guard let candidateIndex = previewCandidateURLs.firstIndex(of: url),
              previewCandidateURLs.count > 1 else {
            return nil
        }

        let previousURL = adjacentPreviewURL(in: batch, currentIndex: currentIndex, offset: -1)
        let nextURL = adjacentPreviewURL(in: batch, currentIndex: currentIndex, offset: 1)
        return QueueVideoPreviewPlaylist(
            currentIndex: candidateIndex,
            totalCount: previewCandidateURLs.count,
            previousID: previousURL?.absoluteString,
            previousName: previousURL?.lastPathComponent,
            nextID: nextURL?.absoluteString,
            nextName: nextURL?.lastPathComponent
        )
    }

    private func adjacentPreviewURL(
        in batch: FolderEncodingBatch,
        currentIndex: Int,
        offset: Int
    ) -> URL? {
        guard offset != 0 else {
            return nil
        }

        var index = currentIndex + offset
        while batch.fileURLs.indices.contains(index) {
            let url = batch.fileURLs[index]
            if isQueuePreviewNavigationCandidate(batch.itemStates[url] ?? .queued) {
                return url
            }
            index += offset
        }
        return nil
    }

    private func isQueuePreviewNavigationCandidate(_ item: BatchItemRuntime) -> Bool {
        item.isPreviewable
            && item.videoInfo != nil
            && item.asset?.videoTrack != nil
    }

    private var canOpenFolderPreviewInCurrentState: Bool {
        switch state {
        case .encoding, .cancelling, .saving:
            return false
        case .idle, .importing, .inspecting, .storageChecking, .storageBlocked, .readyToStart,
                .waitingForReward, .pendingSave, .completed, .failed, .cancelled:
            return true
        }
    }

    private func presentPreview(_ preview: QueueVideoPreview) {
        activePreview = preview
        AppLogger.info(
            "Queue preview opened",
            category: .ui,
            metadata: [
                "name": preview.displayName,
                "codec": preview.codecBadge,
                "path": preview.pathBadge,
                "position": preview.playlist?.positionText ?? "single"
            ]
        )
    }

    private func openPreviewAfterImportIfAvailable(for review: PreparedEncodingReview) {
        guard activePreview == nil else {
            return
        }

        if let batch = folderBatch {
            if let preview = batchPreview(for: review.source.url) {
                presentPreview(preview)
                return
            }

            if let firstPreviewURL = batch.fileURLs.first(where: { url in
                isQueuePreviewNavigationCandidate(batch.itemStates[url] ?? .queued)
            }),
               let preview = batchPreview(for: firstPreviewURL) {
                presentPreview(preview)
            }
            return
        }

        if let preview = currentReviewPreview(for: review.source.url.absoluteString) {
            presentPreview(preview)
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

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await handleRewardedAdButtonTap()
        }
    }

    private func handleRewardedAdButtonTap() async {
        guard !state.isBusy else {
            return
        }
        guard !isWatchingStarAd else {
            return
        }

        guard rewardedAdState == .ready else {
            AppLogger.info(
                "Rewarded ad requested while ad is not ready; continuing preload",
                category: .ads,
                metadata: ["state": rewardedAdState.rawValue]
            )
            let nextState: AdLoadState
            if rewardedAdState == .unavailable {
                nextState = await environment.starEarningService.retryNextAdNow()
            } else {
                nextState = await environment.starEarningService.prepareNextAd()
            }
            applyRewardedAdState(nextState, startPollingIfNeeded: true)
            return
        }

        if let job = pendingSaveJobRequiringRewardedAd {
            await watchAdForPendingSave(job)
            return
        }

        await watchAdAndEarnStar()
    }

    private func watchAdAndEarnStar() async {
        isWatchingStarAd = true
        AppLogger.info("Watch ad for star requested", category: .ads)

        do {
            let result = try await environment.starEarningService.watchAdAndEarnStar()
            starWalletSnapshot = result.snapshot
            isWatchingStarAd = false
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
            isWatchingStarAd = false
            AppLogger.error(
                "Watch ad for star failed",
                category: .ads,
                metadata: ["error": error.localizedDescription]
            )
            await refreshRewardedAdState(startPollingIfNeeded: true)
        }
    }

    private var pendingSaveJobRequiringRewardedAd: PendingSaveJob? {
        if let job = state.pendingSaveJob,
           job.state.requiresRewardedAd {
            return job
        }
        if case .failed = state {
            return pendingSaveQueue.first { $0.state.requiresRewardedAd }
        }
        return nil
    }

    private func watchAdForPendingSave(_ job: PendingSaveJob) async {
        isWatchingStarAd = true
        AppLogger.info(
            "Watch ad for pending save requested",
            category: .ads,
            metadata: [
                "source": job.sourceName,
                "id": job.state.id.uuidString
            ]
        )

        let result = await environment.rewardedAdProvider.showRewardedAd()
        isWatchingStarAd = false

        switch result {
        case .earnedReward:
            do {
                let authorizedJob = try await clearRewardedAdRequirement(
                    for: job,
                    rewardedAdCompleted: true
                )
                AppLogger.info(
                    "Pending save rewarded ad completed",
                    category: .ads,
                    metadata: [
                        "source": authorizedJob.sourceName,
                        "id": authorizedJob.state.id.uuidString
                    ]
                )
                await refreshRewardedAdState(startPollingIfNeeded: true)
                requestSaveDestinationIfNeeded(for: authorizedJob)
            } catch {
                AppLogger.error(
                    "Pending save rewarded ad completion failed",
                    category: .ads,
                    metadata: [
                        "source": job.sourceName,
                        "error": error.localizedDescription
                    ]
                )
                pausePendingSaveForRewardedAd(job)
                await refreshRewardedAdState(startPollingIfNeeded: true)
            }
        case .closedWithoutReward:
            AppLogger.warning(
                "Pending save rewarded ad closed without reward",
                category: .ads,
                metadata: ["source": job.sourceName]
            )
            pausePendingSaveForRewardedAd(job)
            await refreshRewardedAdState(startPollingIfNeeded: true)
        case .unavailable:
            AppLogger.warning(
                "Pending save rewarded ad unavailable",
                category: .ads,
                metadata: ["source": job.sourceName]
            )
            rewardedAdState = .unavailable
            pausePendingSaveForRewardedAd(job)
            await refreshRewardedAdState(startPollingIfNeeded: true)
        }
    }

    func retryPendingSave() {
        guard let job = nextPendingSaveJobForAction else {
            return
        }
        requestSaveDestinationIfNeeded(for: job)
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
        requestSaveDestinationIfNeeded(for: job)
    }

    func dismissPendingSaveDestinationPrompt() {
        guard pendingSaveDestinationPrompt != nil else {
            return
        }
        AppLogger.info("Pending save destination prompt dismissed", category: .saving)
        pendingSaveDestinationPrompt = nil
    }

    func chooseAlbumForPendingSave(prompt: PendingSaveDestinationPrompt) {
        guard pendingSaveDestinationPrompt?.id == prompt.id else {
            return
        }
        pendingSaveDestinationPrompt = nil
        var job = prompt.job
        job.state.saveDestination = .photosLibrary
        job.state.finalOutputURL = nil
        job.state.saveDestinationWasChosen = true
        rememberFolderBatchSaveDestinationIfNeeded(.photosLibrary)
        persistPendingSaveState(job.state)
        updatePendingSaveJob(job)
        state = .pendingSave(job)
        AppLogger.info(
            "Pending save destination selected",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "destination": "album"
            ]
        )
        savePendingJob(job)
    }

    func chooseFolderForPendingSave(prompt: PendingSaveDestinationPrompt) {
        guard pendingSaveDestinationPrompt?.id == prompt.id else {
            return
        }
        pendingSaveDestinationPrompt = nil
        var job = prompt.job
        job.state.saveDestination = .sourceFolder
        job.state.saveDestinationWasChosen = true
        rememberFolderBatchSaveDestinationIfNeeded(.sourceFolder)
        job = applySelectedFolderBatchDestination(to: job)
        persistPendingSaveState(job.state)
        updatePendingSaveJob(job)
        state = .pendingSave(job)
        AppLogger.info(
            "Pending save destination selected",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "destination": "folder",
                "final": job.state.finalOutputURL?.path ?? "in-app-output"
            ]
        )

        guard job.state.finalOutputURL != nil else {
            let routedJob = reroutePendingSaveToInternalOutput(job, reason: "missing final output path")
            persistPendingSaveState(routedJob.state)
            updatePendingSaveJob(routedJob)
            state = .pendingSave(routedJob)
            savePendingJob(routedJob)
            return
        }

        savePendingJob(job)
    }

    func reset() {
        guard state.canReset else {
            AppLogger.info("Reset ignored because state cannot reset", category: .ui)
            return
        }
        AppLogger.info("Reset requested", category: .ui)
        let pendingStatesToReset = resetPendingStates()
        dismissPreview()
        activeTask?.cancel()
        activeTask = nil
        selectionInspectionTask?.cancel()
        selectionInspectionTask = nil
        currentReview = nil
        activeStarCharge = nil
        shouldAutoResumeBatchAfterStarEarn = false
        cancelEncodingActivity()
        pendingSaveDestinationPrompt = nil
        folderPreviewContext = nil
        clearImportBrowserState(stoppingAccess: false)
        pendingSaveQueue = []
        pendingSaveAccessURLs = [:]
        lastBatchFileCards = []
        folderBatch = nil
        inspectedMediaCache.removeAll()
        rewardedAdStatePollingTask?.cancel()
        rewardedAdStatePollingTask = nil
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
        endEncodingActivity(
            statusText: "Cancelling",
            fractionCompleted: lastEncodingActivitySnapshot?.fractionCompleted ?? 0
        )
        activeTask?.cancel()
    }

    func fail(message: String) {
        AppLogger.error(
            "Home flow failed",
            category: .app,
            metadata: ["message": message]
        )
        dismissPreview()
        activeTask?.cancel()
        activeTask = nil
        selectionInspectionTask?.cancel()
        selectionInspectionTask = nil
        currentReview = nil
        activeStarCharge = nil
        shouldAutoResumeBatchAfterStarEarn = false
        endEncodingActivity(
            statusText: "Failed",
            fractionCompleted: lastEncodingActivitySnapshot?.fractionCompleted ?? 0
        )
        lastBatchFileCards = []
        folderPreviewContext = nil
        folderBatch = nil
        inspectedMediaCache.removeAll()
        state = .failed(HomeEncodingError(title: "Import failed", message: message))
        stopSecurityScopedAccess()
    }

    private func inspectVideoReusingCache(
        at url: URL,
        preinspectedAsset: TaptionVideoAsset? = nil
    ) async throws -> (asset: TaptionVideoAsset, reusedCache: Bool) {
        let fingerprint = mediaFingerprint(for: url)
        let canValidateFingerprint = fingerprint.fileSize != nil
            || fingerprint.modificationDate != nil
            || fingerprint.creationDate != nil
            || fingerprint.contentIdentifier != nil

        if canValidateFingerprint,
           let preinspectedAsset,
           preinspectedAsset.fingerprint == fingerprint {
            inspectedMediaCache.store(preinspectedAsset, for: url)
            AppLogger.info(
                "Media inspection reused preinspected asset",
                category: .mediaInspection,
                metadata: ["name": url.lastPathComponent]
            )
            return (preinspectedAsset, true)
        }

        if canValidateFingerprint,
           let cachedAsset = inspectedMediaCache.asset(for: url, currentFingerprint: fingerprint) {
            AppLogger.info(
                "Media inspection reused cached asset",
                category: .mediaInspection,
                metadata: ["name": url.lastPathComponent]
            )
            return (cachedAsset, true)
        }

        let asset = try await environment.videoCoreServices.inspector.inspectVideo(at: url)
        if canValidateFingerprint {
            inspectedMediaCache.store(asset, for: url)
        }
        return (asset, false)
    }

    private func mediaFingerprint(for url: URL) -> TaptionMediaFingerprint {
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]) else {
            return TaptionMediaFingerprint()
        }

        return TaptionMediaFingerprint(
            fileSize: values.fileSize.map(Int64.init),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            contentIdentifier: nil
        )
    }

    private func prepareEncodingFlow(
        source: HomeSelectedSource,
        autoStartAfterPrepare: Bool = false,
        allowsBusyState: Bool = false,
        preinspectedAsset: TaptionVideoAsset? = nil
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
            let trace = TaptionEncodingPerformanceTrace(
                name: "home_prepare_encoding",
                category: .encoding,
                metadata: [
                    "name": source.displayName,
                    "kind": source.kind.rawValue,
                    "autoStart": "\(autoStartAfterPrepare)"
                ]
            )

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

                trace.mark("inspection_start")
                let inspected = try await inspectVideoReusingCache(
                    at: source.url,
                    preinspectedAsset: preinspectedAsset
                )
                let asset = inspected.asset
                trace.mark(
                    "inspection_complete",
                    metadata: [
                        "cacheHit": "\(inspected.reusedCache)",
                        "codec": asset.videoTrack?.codec.rawValue ?? "unknown",
                        "audioTracks": "\(asset.audioTracks.count)"
                    ]
                )
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
                trace.mark(
                    "job_prepared",
                    metadata: [
                        "plan": job.plan.id.uuidString,
                        "route": job.routeSelection.route.displayName,
                        "executionKind": job.routeSelection.executionKind.rawValue
                    ]
                )
                if source.kind == .photos {
                    job.plan.finalOutputURL = nil
                }
                applySelectedFolderBatchDestination(to: &job, source: source)
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
                trace.mark(
                    "storage_checked",
                    metadata: [
                        "requiredBytes": "\(job.storageRequirement.requiredWorkingBytes)",
                        "availableBytes": job.storageRequirement.availableBytes.map(String.init) ?? "unknown",
                        "hasEnoughSpace": "\(job.storageRequirement.hasEnoughSpace)"
                    ]
                )

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
                        trace.finish("blocked", metadata: ["reason": detail])
                        return
                    }
                    state = .failed(HomeEncodingError(
                        title: "Encoding blocked",
                        message: detail
                    ))
                    trace.finish("blocked", metadata: ["reason": detail])
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
                        trace.finish("storage_blocked", metadata: ["reason": storageMessage])
                        return
                    }
                    state = .storageBlocked(StorageIssue(
                        requiredBytes: job.storageRequirement.requiredWorkingBytes,
                        availableBytes: job.storageRequirement.availableBytes,
                        message: storageMessage
                    ))
                    trace.finish("storage_blocked", metadata: ["reason": storageMessage])
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
                    isActive: true,
                    isEnabled: review.videoInfo.isRouteEncodable,
                    isPreviewable: isPreviewableInCurrentBuild(asset: job.asset)
                )

                activeTask = nil
                if autoStartAfterPrepare {
                    trace.finish("ready_auto_start")
                    await attemptEncodingStart(
                        for: review,
                        autoResumeAfterStarEarn: true
                    )
                } else {
                    state = .readyToStart(review)
                    trace.finish("ready")
                    openPreviewAfterImportIfAvailable(for: review)
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
                trace.finish("cancelled")
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
                    trace.finish("storage_blocked", metadata: ["reason": storageMessage])
                    return
                }
                state = .storageBlocked(StorageIssue(
                    requiredBytes: requiredBytes,
                    availableBytes: availableBytes,
                    message: storageMessage
                ))
                trace.finish("storage_blocked", metadata: ["reason": storageMessage])
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
                    trace.finish("failed", metadata: ["error": error.localizedDescription])
                    return
                }
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                activeTask = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .failedEncoding)
                trace.finish("failed", metadata: ["error": error.localizedDescription])
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
                    trace.finish("failed", metadata: ["error": error.localizedDescription])
                    return
                }
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                activeTask = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .failedEncoding)
                trace.finish("failed", metadata: ["error": error.localizedDescription])
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
        deferredBatteryStopReason = nil
        let trace = TaptionEncodingPerformanceTrace(
            name: "home_encode_flow",
            category: .encoding,
            metadata: [
                "name": review.source.displayName,
                "plan": review.job.plan.id.uuidString,
                "route": review.job.plan.codecRoute?.displayName ?? "unknown"
            ]
        )
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
        startEncodingActivity(for: review, progress: initialProgress)

        activeTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let core = TaptionVideoCore(services: environment.videoCoreServices)
                var lastLoggedProgressBucket = -1
                let firstProgressLock = NSLock()
                var didMarkFirstProgress = false
                let result = try await core.encodePreparedJob(review.job) { [weak self] progress in
                    let shouldMarkFirstProgress: Bool = {
                        firstProgressLock.lock()
                        defer {
                            firstProgressLock.unlock()
                        }
                        guard !didMarkFirstProgress else {
                            return false
                        }
                        didMarkFirstProgress = true
                        return true
                    }()
                    if shouldMarkFirstProgress {
                        trace.mark(
                            "first_progress",
                            metadata: [
                                "stage": progress.stage.rawValue,
                                "fraction": String(format: "%.3f", progress.fractionCompleted)
                            ]
                        )
                    }
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
                        self.captureDeferredBatteryStopIfNeeded()
                        self.markBatchItem(
                            review.source.url,
                            videoInfo: review.videoInfo,
                            statusText: snapshot.stageTitle,
                            detailText: snapshot.backendLabel,
                            progress: snapshot,
                            isActive: true
                        )
                        self.state = .encoding(snapshot)
                        self.updateEncodingActivity(for: review, progress: snapshot)
                    }
                }

                try Task.checkCancellation()
                trace.mark(
                    "encode_completed",
                    metadata: [
                        "mode": result.usedMode.rawValue,
                        "backend": result.usedBackend.rawValue
                    ]
                )

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
                updateEncodingActivity(
                    for: review,
                    progress: completedProgress,
                    statusText: restorablePendingState.requiresRewardedAd ? "Ready to save" : "Saving"
                )
                if restorablePendingState.requiresRewardedAd && folderBatch == nil {
                    endEncodingActivity(statusText: "Ready to save", fractionCompleted: 1)
                }
                activeTask = nil
                state = .pendingSave(pendingJob)
                trace.finish("pending_save_started", metadata: ["pendingSave": pendingJob.id.uuidString])
                requestSaveDestinationIfNeeded(for: pendingJob)
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
                endEncodingActivity(statusText: "Cancelled", fractionCompleted: lastEncodingActivitySnapshot?.fractionCompleted ?? 0)
                activeTask = nil
                currentReview = nil
                folderBatch = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .cancelledEncoding)
                trace.finish("cancelled")
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
                    trace.finish("failed", metadata: ["error": error.localizedDescription])
                    return
                }
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                endEncodingActivity(statusText: "Failed", fractionCompleted: lastEncodingActivitySnapshot?.fractionCompleted ?? 0)
                activeTask = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .failedEncoding)
                trace.finish("failed", metadata: ["error": error.localizedDescription])
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
                    trace.finish("failed", metadata: ["error": error.localizedDescription])
                    return
                }
                state = .failed(HomeEncodingError(
                    title: "Encoding failed",
                    message: error.localizedDescription
                ))
                endEncodingActivity(statusText: "Failed", fractionCompleted: lastEncodingActivitySnapshot?.fractionCompleted ?? 0)
                activeTask = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .failedEncoding)
                trace.finish("failed", metadata: ["error": error.localizedDescription])
            }
        }
    }

    private func savePendingJob(
        _ job: PendingSaveJob,
        conflictResolution: PendingSaveConflictResolution = .saveAsUnique
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
        let trace = TaptionEncodingPerformanceTrace(
            name: "home_final_save",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "pendingSave": job.state.id.uuidString,
                "destination": "\(job.state.saveDestination)"
            ]
        )

        guard !job.state.requiresRewardedAd else {
            trace.finish("waiting_for_reward")
            pausePendingSaveForRewardedAd(job)
            return
        }

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
                markCurrentSaveItem(
                    statusText: "Saving",
                    detailText: "Writing the output.",
                    progress: completedProgressSnapshot(label: "Saving"),
                    isActive: true
                )
                state = .saving(workingJob)

                workingJob.saveGateMessage = nil

                if conflictResolution == .saveAsUnique {
                    trace.mark("pending_save_state_update_start")
                    try await environment.pendingSaveStore.savePendingState(workingJob.state)
                    trace.mark("pending_save_state_updated")
                    updatePendingSaveJob(workingJob)
                }

                trace.mark("finalize_save_start")
                let savedURL = try await finalizeSave(
                    for: workingJob.state,
                    conflictResolution: conflictResolution
                )
                trace.mark("finalize_save_complete", metadata: ["saved": savedURL.lastPathComponent])
                await finishPendingSaveJob(workingJob, savedURL: savedURL)
                trace.finish("completed", metadata: ["saved": savedURL.lastPathComponent])
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
                    detailText: "Save can be retried without another ad.",
                    progress: completedProgressSnapshot(label: "Pending Save"),
                    isActive: true
                )
                state = .pendingSave(workingJob)
                activeTask = nil
                trace.finish("cancelled")
            } catch TaptionFinalSaveConflictError.destinationAlreadyExists(let existingURL) {
                AppLogger.warning(
                    "Final save destination exists; retrying with unique name",
                    category: .saving,
                    metadata: [
                        "source": workingJob.sourceName,
                        "existing": existingURL.lastPathComponent,
                        "rewardedAdRequired": "\(workingJob.state.requiresRewardedAd)"
                    ]
                )
                state = .pendingSave(workingJob)
                activeTask = nil
                trace.finish("retry_unique", metadata: ["existing": existingURL.lastPathComponent])
                savePendingJob(workingJob, conflictResolution: .saveAsUnique)
            } catch {
                if workingJob.state.saveDestination == .sourceFolder,
                   isFileProviderWritePermissionDenied(error) {
                    let routedJob = reroutePendingSaveToInternalOutput(workingJob, reason: error.localizedDescription)
                    try? await environment.pendingSaveStore.savePendingState(routedJob.state)
                    updatePendingSaveJob(routedJob)
                    AppLogger.warning(
                        "Final save rerouted to in-app output folder",
                        category: .saving,
                        metadata: [
                            "source": routedJob.sourceName,
                            "error": error.localizedDescription,
                            "final": routedJob.state.finalOutputURL?.lastPathComponent ?? "none"
                        ]
                    )
                    markCurrentSaveItem(
                        statusText: "Saving",
                        detailText: routedJob.saveGateMessage,
                        progress: completedProgressSnapshot(label: "Saving"),
                        isActive: true
                    )
                    state = .pendingSave(routedJob)
                    activeTask = nil
                    trace.finish("rerouted_internal_output", metadata: ["error": error.localizedDescription])
                    savePendingJob(routedJob, conflictResolution: .saveAsUnique)
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
                trace.finish("failed", metadata: ["error": error.localizedDescription])
            }
        }
    }

    private func pausePendingSaveForRewardedAd(_ job: PendingSaveJob) {
        var waitingJob = job
        waitingJob.saveGateMessage = "Watch a rewarded ad to save this completed video."
        updatePendingSaveJob(waitingJob)
        persistPendingSaveState(waitingJob.state)
        markCurrentSaveItem(
            statusText: "Watch Ad to Save",
            detailText: waitingJob.saveGateMessage,
            progress: completedProgressSnapshot(label: "Ready to Save"),
            isActive: true
        )
        state = .pendingSave(waitingJob)
        activeTask = nil
        Task { @MainActor [weak self] in
            await self?.refreshRewardedAdState(startPollingIfNeeded: true)
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

    private func requestSaveDestinationIfNeeded(for job: PendingSaveJob) {
        let routedJob = applySelectedFolderBatchDestination(to: job)
        if routedJob.state.saveDestinationWasChosen == true {
            updatePendingSaveJob(routedJob)
            state = .pendingSave(routedJob)
            if routedJob.state.saveDestination == .sourceFolder,
               routedJob.state.finalOutputURL == nil {
                let internalJob = reroutePendingSaveToInternalOutput(
                    routedJob,
                    reason: "missing restored final output path"
                )
                persistPendingSaveState(internalJob.state)
                updatePendingSaveJob(internalJob)
                state = .pendingSave(internalJob)
                activeTask = nil
                savePendingJob(internalJob)
                return
            }
            savePendingJob(routedJob)
            return
        }

        pendingSaveDestinationPrompt = PendingSaveDestinationPrompt(job: routedJob)
        updatePendingSaveJob(routedJob)
        markCurrentSaveItem(
            statusText: "Choose Save Location",
            detailText: "Choose Album or Folder before saving.",
            progress: completedProgressSnapshot(label: "Ready to Save"),
            isActive: true
        )
        state = .pendingSave(routedJob)
        activeTask = nil
        AppLogger.info(
            "Pending save destination prompt opened",
            category: .saving,
            metadata: [
                "source": routedJob.sourceName,
                "id": routedJob.id.uuidString
            ]
        )
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
        endEncodingActivity(statusText: "Save Complete", fractionCompleted: 1)
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
            let inspected = try await inspectVideoReusingCache(at: url)
            let asset = inspected.asset
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
            let isPreviewable = isPreviewableInCurrentBuild(asset: asset)
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
                    isEnabled: false,
                    isPreviewable: false
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
                    isEnabled: true,
                    isPreviewable: isPreviewable
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
                    isEnabled: false,
                    isPreviewable: isPreviewable
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
                isEnabled: false,
                isPreviewable: false
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
            allowsBusyState: allowsBusyState,
            preinspectedAsset: batch.itemStates[url]?.asset
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
        updateEncodingActivityForFolderBatch(statusText: "Saved", batch: batch)

        if let stopReason = batchStopReasonAfterCurrentItem() {
            batch.stopMessage = stopReason.batchStopMessage
            batch = batchWithRemainingItemsStopped(batch, reason: stopReason)
            folderBatch = batch
            updateEncodingActivityForFolderBatch(statusText: "Stopped", batch: batch)
            finishFolderBatch()
            return true
        }

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
        updateEncodingActivityForFolderBatch(statusText: "Failed", batch: batch)

        if let stopReason = batchStopReasonAfterCurrentItem() {
            batch.stopMessage = stopReason.batchStopMessage
            batch = batchWithRemainingItemsStopped(batch, reason: stopReason)
            folderBatch = batch
            updateEncodingActivityForFolderBatch(statusText: "Stopped", batch: batch)
            finishFolderBatch()
            return true
        }

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
                displayName: batch.stopMessage == nil ? "Folder complete" : "Folder stopped",
                destinationDescription: batch.folderName,
                detailOverride: folderCompletionMessage(for: batch)
            ))
        }
        endEncodingActivity(
            statusText: batch.stopMessage == nil ? "Folder complete" : "Folder stopped",
            fractionCompleted: finalFolderActivityFraction(for: batch)
        )
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

        if let reason = currentBatteryEncodingBlockReason() {
            blockEncodingStart(for: review, reason: reason)
            return
        }

        starWalletSnapshot = await environment.starWalletStore.currentSnapshot()
        guard starWalletSnapshot.balance > 0 else {
            AppLogger.info(
                "Starting encoding without stars; rewarded ad will be required before final save",
                category: .encoding,
                metadata: [
                    "name": review.source.displayName,
                    "balance": "\(starWalletSnapshot.balance)"
                ]
            )
            activeStarCharge = nil
            shouldAutoResumeBatchAfterStarEarn = false
            startEncoding(
                review: reviewWithSaveGate(.rewardedAdBeforeFinalSave, for: review),
                allowsBusyState: true
            )
            return
        }

        do {
            starWalletSnapshot = try await environment.starWalletStore.consumeStar(
                source: review.source.displayName
            )
            activeStarCharge = ActiveStarCharge(
                sourceURL: review.source.url,
                sourceName: review.source.displayName
            )
            shouldAutoResumeBatchAfterStarEarn = false
            startEncoding(
                review: reviewWithSaveGate(.none, for: review),
                allowsBusyState: true
            )
        } catch let error as StarWalletError {
            if case .insufficientStars = error {
                starWalletSnapshot = await environment.starWalletStore.currentSnapshot()
                AppLogger.info(
                    "Star balance changed before debit; continuing with rewarded save ad",
                    category: .encoding,
                    metadata: [
                        "name": review.source.displayName,
                        "balance": "\(starWalletSnapshot.balance)"
                    ]
                )
                activeStarCharge = nil
                shouldAutoResumeBatchAfterStarEarn = false
                startEncoding(
                    review: reviewWithSaveGate(.rewardedAdBeforeFinalSave, for: review),
                    allowsBusyState: true
                )
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

    private func reviewWithSaveGate(
        _ saveGate: TaptionSaveGate,
        for review: PreparedEncodingReview
    ) -> PreparedEncodingReview {
        var updatedReview = review
        updatedReview.job.plan.savePolicy.saveGate = saveGate
        return updatedReview
    }

    private func folderCompletionMessage(for batch: FolderEncodingBatch) -> String {
        var message: String
        if let stopMessage = batch.stopMessage {
            message = "Folder encoding stopped. \(batch.completedCount) of \(batch.totalCount) files were saved. \(stopMessage)"
        } else {
            message = "Folder encoding complete. \(batch.completedCount) of \(batch.totalCount) files were saved."
        }
        if batch.failedCount > 0 {
            message += " \(batch.failedCount) failed."
        }
        if let lastFailureMessage = batch.lastFailureMessage {
            message += " Last issue: \(lastFailureMessage)"
        }
        return message
    }

    private func finalFolderActivityFraction(for batch: FolderEncodingBatch) -> Double {
        guard batch.stopMessage != nil else {
            return 1
        }
        return Double(min(max(batch.currentIndex, 0), batch.totalCount)) / Double(max(batch.totalCount, 1))
    }

    private func batchStopReasonAfterCurrentItem() -> BatteryEncodingBlockReason? {
        let reason = deferredBatteryStopReason ?? currentBatteryEncodingBlockReason()
        deferredBatteryStopReason = nil
        return reason
    }

    private func batchWithRemainingItemsStopped(
        _ batch: FolderEncodingBatch,
        reason: BatteryEncodingBlockReason
    ) -> FolderEncodingBatch {
        var updatedBatch = batch
        for url in updatedBatch.fileURLs.dropFirst(updatedBatch.currentIndex) {
            var item = updatedBatch.itemStates[url] ?? .queued
            item.progress = nil
            item.statusText = "Stopped"
            item.detailText = reason.batchStopMessage
            item.isActive = false
            updatedBatch.itemStates[url] = item
        }
        return updatedBatch
    }

    private func startEncodingActivity(
        for review: PreparedEncodingReview,
        progress: EncodingProgressSnapshot
    ) {
        let snapshot = encodingActivitySnapshot(for: review, progress: progress)
        let backgroundSnapshot = backgroundSnapshot(from: snapshot)
        lastEncodingActivitySnapshot = snapshot
        Task { @MainActor [environment] in
            await environment.liveActivityCoordinator.start(snapshot: snapshot)
            await environment.backgroundCoordinator.updateBackgroundEncoding(
                planID: review.job.plan.id,
                snapshot: backgroundSnapshot
            )
        }
    }

    private func updateEncodingActivity(
        for review: PreparedEncodingReview,
        progress: EncodingProgressSnapshot,
        statusText: String? = nil
    ) {
        let snapshot = encodingActivitySnapshot(
            for: review,
            progress: progress,
            statusText: statusText
        )
        let backgroundSnapshot = backgroundSnapshot(from: snapshot)
        lastEncodingActivitySnapshot = snapshot
        Task { @MainActor [environment] in
            await environment.liveActivityCoordinator.update(snapshot: snapshot)
            await environment.backgroundCoordinator.updateBackgroundEncoding(
                planID: review.job.plan.id,
                snapshot: backgroundSnapshot
            )
        }
    }

    private func updateEncodingActivityForFolderBatch(
        statusText: String,
        batch: FolderEncodingBatch
    ) {
        let sessionID = activeEncodingActivitySessionID ?? UUID()
        activeEncodingActivitySessionID = sessionID
        let completedOrFailed = min(batch.completedCount + batch.failedCount, batch.totalCount)
        let fraction = Double(completedOrFailed) / Double(max(batch.totalCount, 1))
        let snapshot = TaptionEncodingActivitySnapshot(
            sessionID: sessionID.uuidString,
            statusText: statusText,
            sourceName: batch.folderName,
            mode: .folder,
            currentIndex: min(max(batch.currentIndex, 1), max(batch.totalCount, 1)),
            totalCount: batch.totalCount,
            fractionCompleted: fraction,
            elapsedSeconds: lastEncodingActivitySnapshot?.elapsedSeconds ?? 0,
            remainingSeconds: lastEncodingActivitySnapshot?.remainingSeconds,
            codecPathText: lastEncodingActivitySnapshot?.codecPathText ?? "Automatic Codec Path",
            outputText: lastEncodingActivitySnapshot?.outputText ?? selectedOutput.summary
        )
        lastEncodingActivitySnapshot = snapshot
        Task { @MainActor [environment] in
            await environment.liveActivityCoordinator.update(snapshot: snapshot)
        }
    }

    private func endEncodingActivity(
        statusText: String,
        fractionCompleted: Double
    ) {
        guard var snapshot = lastEncodingActivitySnapshot else {
            cancelEncodingActivity()
            return
        }
        snapshot.statusText = statusText
        snapshot.fractionCompleted = min(max(fractionCompleted, 0), 1)
        if snapshot.fractionCompleted >= 1 {
            snapshot.currentIndex = snapshot.totalCount
            snapshot.remainingSeconds = 0
        }
        lastEncodingActivitySnapshot = snapshot
        activeEncodingActivitySessionID = nil
        Task { @MainActor [environment] in
            await environment.liveActivityCoordinator.end(snapshot: snapshot, dismissalDelay: 12)
        }
    }

    private func cancelEncodingActivity() {
        activeEncodingActivitySessionID = nil
        lastEncodingActivitySnapshot = nil
        Task { @MainActor [environment] in
            await environment.liveActivityCoordinator.cancel()
        }
    }

    private func encodingActivitySnapshot(
        for review: PreparedEncodingReview,
        progress: EncodingProgressSnapshot,
        statusText: String? = nil
    ) -> TaptionEncodingActivitySnapshot {
        let isFolder = folderBatch != nil
        let sessionID: UUID
        if isFolder {
            sessionID = activeEncodingActivitySessionID ?? UUID()
            activeEncodingActivitySessionID = sessionID
        } else {
            sessionID = review.job.plan.id
            activeEncodingActivitySessionID = sessionID
        }

        let batch = folderBatch
        return TaptionEncodingActivitySnapshot(
            sessionID: sessionID.uuidString,
            statusText: statusText ?? progress.stageTitle,
            sourceName: batch?.folderName ?? review.source.displayName,
            mode: isFolder ? .folder : .single,
            currentIndex: batch.map { min(max($0.currentIndex + 1, 1), max($0.totalCount, 1)) } ?? 1,
            totalCount: batch?.totalCount ?? 1,
            fractionCompleted: progress.fractionCompleted,
            elapsedSeconds: progress.elapsedTime,
            remainingSeconds: progress.estimatedRemainingTime,
            codecPathText: isFolder ? (review.folderQueue?.statusText ?? progress.backendLabel) : review.videoInfo.codecPathTitle,
            outputText: review.videoInfo.outputSummary
        )
    }

    private func backgroundSnapshot(
        from snapshot: TaptionEncodingActivitySnapshot
    ) -> TaptionBackgroundEncodingSnapshot {
        let state = snapshot.contentState
        return TaptionBackgroundEncodingSnapshot(
            title: snapshot.title,
            subtitle: "\(state.percentText) \(state.statusText) - \(state.sourceName)",
            fractionCompleted: snapshot.fractionCompleted
        )
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
        isEnabled: Bool? = nil,
        isPreviewable: Bool? = nil
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
        if let isPreviewable {
            item.isPreviewable = isPreviewable
        }
        if isActive {
            batch.selectedURL = url
        }
        batch.itemStates[url] = item
        if item.isEnabled == false,
           !item.isPreviewable,
           batch.selectedURL == url {
            batch.selectedURL = batch.fileURLs.first { url in
                let item = batch.itemStates[url]
                return item?.isEnabled != false || item?.isPreviewable == true
            }
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
            } else if job.state.requiresRewardedAd {
                statusText = "Watch Ad to Save"
                detailText = job.saveGateMessage ?? "Watch a rewarded ad to save this completed video."
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
                thumbnailSourceURL: nil,
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

    private func selectedURLIsDirectory(_ url: URL) -> Bool {
        if url.hasDirectoryPath {
            return true
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory == true
    }

    private func filesPreviewBrowserTitle(for urls: [URL]) -> String {
        guard urls.count == 1,
              let firstURL = urls.first else {
            return "Selected files"
        }
        return firstURL.lastPathComponent
    }

    private func isPreviewableInCurrentBuild(asset: TaptionVideoAsset) -> Bool {
        guard let videoTrack = asset.videoTrack else {
            return false
        }

        guard !Self.previewKnownNoVideoOutputCodecs.contains(videoTrack.codec) else {
            return false
        }

        let decoder = SW_SoftwareCodecBackendRegistry.vlcSoftwareDecoder
        guard decoder.canDecodeVideo(videoTrack.codec) else {
            return false
        }

        if decoder.canReadContainer(asset.container) {
            return true
        }

        guard let url = asset.location.url else {
            return false
        }
        return asset.container != .unknown
            && SupportedVideoFileExtensions.contains(url.pathExtension)
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
            prepareEncodingFlow(
                source: review.source,
                allowsBusyState: true,
                preinspectedAsset: review.job.asset
            )
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
            item.isPreviewable = isPreviewableInCurrentBuild(asset: asset)
            item.statusText = info.isRouteEncodable ? "Queued" : info.readinessStatusText
            item.detailText = info.isRouteEncodable ? "\(routeSelection.displayTitle). Ready to encode." : info.readinessDetailText
            item.progress = nil
            item.isActive = false
            batch.itemStates[url] = item
        }

        batch.selectedURL = batch.fileURLs.first { url in
            let item = batch.itemStates[url]
            return item?.isEnabled != false || item?.isPreviewable == true
        }
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
        isEnabled: Bool,
        isPreviewable: Bool = false
    ) -> EncodingFileCardSnapshot {
        fileCard(
            sourceName: source.displayName,
            sourceKind: source.kind,
            thumbnailSourceURL: source.url,
            videoInfo: videoInfo,
            statusText: statusText,
            detailText: detailText,
            progress: progress,
            isActive: isActive,
            isSelected: isSelected,
            isEnabled: isEnabled,
            isPreviewable: isPreviewable
        )
    }

    private func fileCard(
        sourceName: String,
        sourceKind: HomeSourceKind,
        thumbnailSourceURL: URL? = nil,
        videoInfo: LoadedVideoInfo?,
        statusText: String,
        detailText: String?,
        progress: EncodingProgressSnapshot?,
        isActive: Bool,
        isSelected: Bool,
        isEnabled: Bool,
        isPreviewable: Bool = false
    ) -> EncodingFileCardSnapshot {
        EncodingFileCardSnapshot(
            id: sourceName,
            fileName: sourceName,
            sourceKind: sourceKind,
            thumbnailSourceURL: thumbnailSourceURL,
            videoInfo: videoInfo,
            statusText: statusText,
            detailText: detailText,
            progress: progress,
            isActive: isActive,
            isSelected: isSelected,
            isEnabled: isEnabled,
            isPreviewable: isPreviewable
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

    private func folderURLs(in folderURL: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .isPackageKey]
        return try FileManager.default
            .contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            .filter { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isDirectory == true,
                      values?.isHidden != true,
                      values?.isPackage != true else {
                    return false
                }
                return true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func refreshImportBrowser() {
        guard let mode = importBrowserMode else {
            clearImportBrowserState(stoppingAccess: false)
            return
        }

        guard let rootURL = importBrowserRootURL?.standardizedFileURL,
              var currentURL = importBrowserCurrentURL?.standardizedFileURL else {
            let roots = importBrowserRootFolders()
            importBrowserFolders = roots
            importBrowserFiles = []
            importBrowserContext = HomeImportBrowserContext(
                id: "locations-\(mode.rawValue)-\(roots.count)",
                mode: mode,
                rootFolderName: nil,
                currentFolderName: nil,
                pathText: mode.emptyTitle,
                folderCount: roots.count,
                fileCount: 0,
                selectedFileCount: 0,
                canGoBack: false,
                canGoUp: false
            )
            return
        }

        if !importBrowserURL(currentURL, isInsideRoot: rootURL) {
            currentURL = rootURL
            importBrowserCurrentURL = rootURL
            importBrowserHistory = []
        }

        do {
            let folders = try folderURLs(in: currentURL)
            let files = try videoFileURLs(in: currentURL)
            importBrowserSelectedFileURLs = importBrowserSelectedFileURLs.filter { selectedURL in
                importBrowserURL(selectedURL, isInsideRoot: rootURL)
                    && FileManager.default.fileExists(atPath: selectedURL.path)
            }
            let selectedPaths = Set(importBrowserSelectedFileURLs.map { $0.standardizedFileURL.path })

            importBrowserFolders = folders.map { folderURL in
                HomeImportBrowserFolderSnapshot(
                    id: folderURL.standardizedFileURL.path,
                    folderName: folderURL.lastPathComponent,
                    detailText: "Folder"
                )
            }
            importBrowserFiles = files.map { fileURL in
                let standardizedURL = fileURL.standardizedFileURL
                return HomeImportBrowserFileSnapshot(
                    id: standardizedURL.path,
                    fileName: fileURL.lastPathComponent,
                    detailText: fileSizeText(fileSizeInBytes(at: fileURL)),
                    thumbnailSourceURL: fileURL,
                    isSelected: selectedPaths.contains(standardizedURL.path)
                )
            }
            importBrowserContext = HomeImportBrowserContext(
                id: "\(mode.rawValue)-\(currentURL.path)-\(importBrowserSelectedFileURLs.count)",
                mode: mode,
                rootFolderName: rootURL.lastPathComponent,
                currentFolderName: currentURL.lastPathComponent,
                pathText: relativeImportBrowserPath(root: rootURL, current: currentURL),
                folderCount: folders.count,
                fileCount: files.count,
                selectedFileCount: importBrowserSelectedFileURLs.count,
                canGoBack: true,
                canGoUp: currentURL != rootURL
            )
        } catch {
            AppLogger.error(
                "Import browser refresh failed",
                category: .fileImport,
                metadata: [
                    "mode": mode.rawValue,
                    "folder": currentURL.lastPathComponent,
                    "error": error.localizedDescription
                ]
            )
            importBrowserFolders = []
            importBrowserFiles = []
            importBrowserContext = HomeImportBrowserContext(
                id: "\(mode.rawValue)-\(currentURL.path)-error",
                mode: mode,
                rootFolderName: rootURL.lastPathComponent,
                currentFolderName: currentURL.lastPathComponent,
                pathText: relativeImportBrowserPath(root: rootURL, current: currentURL),
                folderCount: 0,
                fileCount: 0,
                selectedFileCount: importBrowserSelectedFileURLs.count,
                canGoBack: true,
                canGoUp: currentURL != rootURL
            )
        }
    }

    private func importBrowserRootFolders() -> [HomeImportBrowserFolderSnapshot] {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return []
        }

        try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)

        var roots: [HomeImportBrowserFolderSnapshot] = [
            HomeImportBrowserFolderSnapshot(
                id: documentsURL.standardizedFileURL.path,
                folderName: "Taption Encoder Files",
                detailText: "Documents"
            )
        ]

        if let samplesURL = try? TaptionTestVideoSeeder.documentsSampleFolderURL(),
           fileManager.fileExists(atPath: samplesURL.path) {
            roots.append(HomeImportBrowserFolderSnapshot(
                id: samplesURL.standardizedFileURL.path,
                folderName: "Samples",
                detailText: "Bundled videos"
            ))
        }

        return roots
    }

    private func clearImportBrowserState(stoppingAccess: Bool) {
        importBrowserMode = nil
        importBrowserRootURL = nil
        importBrowserCurrentURL = nil
        importBrowserHistory = []
        importBrowserSelectedFileURLs = []
        importBrowserContext = nil
        importBrowserFolders = []
        importBrowserFiles = []
        if stoppingAccess {
            stopSecurityScopedAccess()
        }
    }

    private func relativeImportBrowserPath(root: URL, current: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let currentPath = current.standardizedFileURL.path
        guard currentPath != rootPath,
              currentPath.hasPrefix(rootPath + "/") else {
            return root.lastPathComponent
        }

        let suffix = currentPath
            .dropFirst(rootPath.count + 1)
            .split(separator: "/")
            .joined(separator: "/")
        guard !suffix.isEmpty else {
            return root.lastPathComponent
        }
        return "\(root.lastPathComponent)/\(suffix)"
    }

    private func importBrowserURL(_ url: URL, isInsideRoot rootURL: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
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

    private func rememberFolderBatchSaveDestinationIfNeeded(_ destination: TaptionSaveDestinationKind) {
        guard var batch = folderBatch else {
            return
        }
        batch.selectedSaveDestination = destination
        if destination == .sourceFolder,
           batch.sourceKind == .folder {
            batch.outputFolderURL = folderBatchOutputDirectoryURL(for: batch)
        }
        folderBatch = batch
    }

    private func applySelectedFolderBatchDestination(
        to job: PendingSaveJob
    ) -> PendingSaveJob {
        guard let batch = folderBatch,
              let selectedSaveDestination = batch.selectedSaveDestination else {
            return job
        }

        var updatedJob = job
        updatedJob.state.saveDestination = selectedSaveDestination
        updatedJob.state.saveDestinationWasChosen = true

        switch selectedSaveDestination {
        case .photosLibrary:
            updatedJob.state.finalOutputURL = nil
        case .sourceFolder:
            if let outputFolderURL = batch.outputFolderURL,
               let finalFileName = job.state.finalOutputURL?.lastPathComponent {
                updatedJob.state.finalOutputURL = outputFolderURL.appendingPathComponent(finalFileName)
                updatedJob.state.accessBookmarkData = makeSecurityScopedBookmarkData(
                    for: outputFolderURL.deletingLastPathComponent()
                )
                pendingSaveAccessURLs[updatedJob.id] = outputFolderURL.deletingLastPathComponent()
            }
        case .temporaryOnly:
            updatedJob.state.finalOutputURL = nil
        }

        return updatedJob
    }

    private func reroutePendingSaveToInternalOutput(
        _ job: PendingSaveJob,
        reason: String
    ) -> PendingSaveJob {
        var updatedJob = job
        updatedJob.state.saveDestination = .sourceFolder
        updatedJob.state.saveDestinationWasChosen = true
        updatedJob.state.accessBookmarkData = nil
        updatedJob.state.finalOutputURL = internalOutputURL(for: job)
        updatedJob.saveGateMessage = "Saving to Taption Encoder Outputs."
        pendingSaveAccessURLs[updatedJob.id] = TaptionEncoderStorageLocations.exportedVideosDirectoryURL
        AppLogger.info(
            "Pending save routed to in-app output folder",
            category: .saving,
            metadata: [
                "source": job.sourceName,
                "reason": reason,
                "final": updatedJob.state.finalOutputURL?.lastPathComponent ?? "none"
            ]
        )
        return updatedJob
    }

    private func internalOutputURL(for job: PendingSaveJob) -> URL {
        let fileName = job.state.finalOutputURL?.lastPathComponent
            ?? URL(fileURLWithPath: job.sourceName).lastPathComponent
        let resolvedFileName = fileName.isEmpty
            ? "Taption Output.\(selectedOutput.container.defaultFileExtension)"
            : fileName
        return TaptionEncoderStorageLocations.exportedVideosDirectoryURL
            .appendingPathComponent(resolvedFileName)
    }

    private func applySelectedFolderBatchDestination(
        to job: inout TaptionPreparedEncodingJob,
        source: HomeSelectedSource
    ) {
        guard source.kind == .folder,
              let batch = folderBatch,
              let selectedSaveDestination = batch.selectedSaveDestination else {
            return
        }

        job.plan.savePolicy.destination = selectedSaveDestination
        switch selectedSaveDestination {
        case .photosLibrary:
            job.plan.finalOutputURL = nil
        case .sourceFolder:
            if let outputFolderURL = batch.outputFolderURL {
                job.plan.finalOutputURL = folderBatchOutputURL(
                    for: source.url,
                    outputFolderURL: outputFolderURL,
                    container: job.plan.outputPolicy.container
                )
            }
        case .temporaryOnly:
            job.plan.finalOutputURL = nil
        }
    }

    private func folderBatchOutputDirectoryURL(for batch: FolderEncodingBatch) -> URL? {
        guard batch.sourceKind == .folder,
              let folderURL = batch.folderURL else {
            return nil
        }
        return folderURL
            .deletingLastPathComponent()
            .appendingPathComponent(folderURL.lastPathComponent + environment.configuration.outputSuffix, isDirectory: true)
    }

    private func folderBatchOutputURL(
        for sourceURL: URL,
        outputFolderURL: URL,
        container: TaptionVideoContainer
    ) -> URL {
        outputFolderURL
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + environment.configuration.outputSuffix)
            .appendingPathExtension(container.defaultFileExtension)
    }

    private func persistPendingSaveState(_ state: TaptionPendingSaveState) {
        Task { [environment] in
            do {
                try await environment.pendingSaveStore.savePendingState(state)
            } catch {
                AppLogger.error(
                    "Failed to persist pending save destination",
                    category: .saving,
                    metadata: [
                        "pendingSave": state.id.uuidString,
                        "error": error.localizedDescription
                    ]
                )
            }
        }
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
                "Writing final output to source folder",
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
                let writeResult = try writeFinalOutputFastPath(
                    temporaryURL: state.temporaryOutputURL,
                    destinationURL: finalOutputURL,
                    fileManager: fileManager
                )
                finalOutputURL = writeResult.url
            } catch where TaptionFinalSaveConflictError.isDestinationAlreadyExistsError(error) {
                AppLogger.warning(
                    "Final save write collided with an existing destination",
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
                    let writeResult = try writeFinalOutputFastPath(
                        temporaryURL: state.temporaryOutputURL,
                        destinationURL: uniqueURL,
                        fileManager: fileManager
                    )
                    finalOutputURL = writeResult.url
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

    private func writeFinalOutputFastPath(
        temporaryURL: URL,
        destinationURL: URL,
        fileManager: FileManager
    ) throws -> (url: URL, method: String) {
        let startedAt = Date()
        do {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            AppLogger.info(
                "Final output moved to destination",
                category: .saving,
                metadata: [
                    "final": destinationURL.lastPathComponent,
                    "method": "move",
                    "elapsedMs": TaptionEncodingPerformanceTrace.milliseconds(Date().timeIntervalSince(startedAt))
                ]
            )
            return (destinationURL, "move")
        } catch {
            AppLogger.warning(
                "Final output move fast path failed; falling back to copy",
                category: .saving,
                metadata: [
                    "final": destinationURL.lastPathComponent,
                    "error": error.localizedDescription
                ]
            )
            try fileManager.copyItem(at: temporaryURL, to: destinationURL)
            AppLogger.info(
                "Final output copied to destination",
                category: .saving,
                metadata: [
                    "final": destinationURL.lastPathComponent,
                    "method": "copy_after_move_fallback",
                    "elapsedMs": TaptionEncodingPerformanceTrace.milliseconds(Date().timeIntervalSince(startedAt))
                ]
            )
            return (destinationURL, "copy_after_move_fallback")
        }
    }

    private func overwriteFinalOutputOrSaveUnique(
        temporaryURL: URL,
        destinationURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        let startedAt = Date()
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
                metadata: [
                    "final": destinationURL.lastPathComponent,
                    "method": "replace",
                    "elapsedMs": TaptionEncodingPerformanceTrace.milliseconds(Date().timeIntervalSince(startedAt))
                ]
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
            AppLogger.info(
                "Final output copied after replace denial",
                category: .saving,
                metadata: [
                    "final": uniqueURL.lastPathComponent,
                    "method": "copy_after_replace_denied",
                    "elapsedMs": TaptionEncodingPerformanceTrace.milliseconds(Date().timeIntervalSince(startedAt))
                ]
            )
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

    private func restorablePendingStates(
        _ states: [TaptionPendingSaveState]
    ) -> [TaptionPendingSaveState] {
        states
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
