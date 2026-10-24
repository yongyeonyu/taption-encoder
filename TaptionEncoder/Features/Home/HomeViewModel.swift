import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

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
    private static let folderOutputBookmarkKey = "folderEncoding.outputDirectoryBookmark"

    @Published private(set) var state: HomeScreenState
    @Published private(set) var selectedOutput: TaptionOutputSelection
    @Published private(set) var multiFileEncodingPrompt: MultiFileEncodingPrompt?
    @Published private(set) var multiFileMergeUnavailableAlert: MultiFileMergeUnavailableAlert?
    @Published private(set) var pendingSaveDestinationPrompt: PendingSaveDestinationPrompt?
    @Published private(set) var savedFolderPrompt: SavedFolderPrompt?
    @Published private(set) var starWalletSnapshot: StarWalletSnapshot
    @Published private(set) var rewardedAdState: AdLoadState
    @Published private(set) var isWatchingStarAd: Bool
    @Published private(set) var activePreview: QueueVideoPreview?
    @Published private(set) var miniPlayerPreview: QueueVideoPreview?
    @Published private(set) var isStartingEncoding = false
    @Published private(set) var importBrowserContext: HomeImportBrowserContext?
    @Published private(set) var importBrowserFolders: [HomeImportBrowserFolderSnapshot]
    @Published private(set) var importBrowserFiles: [HomeImportBrowserFileSnapshot]
    @Published private(set) var folderPreviewContext: FolderPreviewContext? {
        didSet {
            if oldValue?.id != folderPreviewContext?.id {
                previewAddedToListURLs.removeAll()
            }
        }
    }
    @Published private var previewAddedToListURLs: [URL] = []
    @Published private var singleFilePreviewContext: SingleFilePreviewContext?
    @Published private(set) var batteryEncodingAlert: BatteryEncodingAlert?

    private let environment: AppEnvironment
    private let sourceDownloader: any VideoSourceDownloading
    private let photoVideoLoader: any PhotoVideoLoading
    private let resourceMonitor: EncodingResourceMonitoring
    private let batteryPowerMonitor: any BatteryPowerMonitoring
    private let batterySettingsProvider: () -> BatteryEncodingSettings
    private let previewFolderBookmarks: PreviewFolderBookmarkStore
    private var hasRequestedInitialFolderAccess = false
    private var activeTask: Task<Void, Never>?
    private var encodingStartTask: Task<Void, Never>?
    private var encodingStartOperationID: UUID?
    private var preparationOperationID: UUID?
    private var resourceMonitorTask: Task<Void, Never>?
    private var latestResourceUsage: EncodingResourceUsageSnapshot?
    private var folderBatch: FolderEncodingBatch?
    private var currentReview: PreparedEncodingReview?
    private var standaloneSelectedQueueIDs: Set<String> = []
    private var pendingSaveQueue: [PendingSaveJob] = []
    private var lastBatchFileCards: [EncodingFileCardSnapshot] = []
    private var selectionInspectionTask: Task<Void, Never>?
    private var previewInspectionTask: Task<Void, Never>?
    private var inspectedMediaCache = TaptionInspectedMediaCache()
    private var hasRestoredPendingSaves = false
    private var hasLoadedStarWallet = false
    private var pendingSaveAccessURLs: [UUID: URL] = [:]
    private let securityScopedAccess = SecurityScopedAccessStore()
    private var importBrowserMode: HomeImportBrowserMode?
    private var importBrowserRootURL: URL?
    private var importBrowserRootDisplayName: String?
    private var importBrowserCurrentURL: URL?
    private var importBrowserHistory: [URL] = []
    private var importBrowserSelectedFileURLs: Set<URL> = []
    private var activeStarCharge: ActiveStarCharge?

    private static let currentBuildPreviewBlockedVideoCodecs: Set<TaptionVideoCodec> = [
        .losslessJPEG,
        .microsoftRLE,
        .r10k,
        .r210,
        .snow
    ]
    private var shouldAutoResumeBatchAfterStarEarn = false
    private var hasConfirmedSeparateMultiFileEncoding = false
    private var rewardedAdStatePollingTask: Task<Void, Never>?
    private var rewardedAdPollingID: UUID?
    private var activeEncodingActivitySessionID: UUID?
    private var lastEncodingActivitySnapshot: TaptionEncodingActivitySnapshot?
    private var deferredBatteryStopReason: BatteryEncodingBlockReason?
    private var batteryObservationTokens: [NSObjectProtocol] = []
    private var isEncodingAdSuppressed = false
    private var activeBackgroundSavePlanIDs: Set<UUID> = []

    init(
        environment: AppEnvironment = .phase0,
        sourceDownloader: any VideoSourceDownloading = UbiquitousVideoDownloader(),
        batteryPowerMonitor: any BatteryPowerMonitoring = UIDeviceBatteryPowerMonitor(),
        batterySettingsProvider: @escaping () -> BatteryEncodingSettings = { BatteryEncodingSettings.load() },
        previewFolderDefaults: UserDefaults = .standard,
        photoVideoLoader: any PhotoVideoLoading = PhotoKitVideoLoader()
    ) {
        self.environment = environment
        self.sourceDownloader = sourceDownloader
        self.photoVideoLoader = photoVideoLoader
        self.resourceMonitor = environment.resourceMonitor
        self.batteryPowerMonitor = batteryPowerMonitor
        self.batterySettingsProvider = batterySettingsProvider
        self.previewFolderBookmarks = PreviewFolderBookmarkStore(defaults: previewFolderDefaults)
        let initialBatterySettings = batterySettingsProvider()
        self.selectedOutput = TaptionOutputSelection(
            videoCodec: environment.configuration.defaultOutputCodec,
            container: environment.configuration.defaultOutputContainer,
            optimizationProfile: initialBatterySettings.optimizationProfile
        )
        self.state = .idle
        self.multiFileEncodingPrompt = nil
        self.multiFileMergeUnavailableAlert = nil
        self.pendingSaveDestinationPrompt = nil
        self.savedFolderPrompt = nil
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
        encodingStartTask?.cancel()
        resourceMonitorTask?.cancel()
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

    var starBalanceDisplayText: String {
        starWalletSnapshot.badgeText
    }

    var canStartEncodingNow: Bool {
        guard !isStartingEncoding else { return false }
        guard let review = state.preparedEncodingReview else {
            return false
        }
        guard review.videoInfo.isRouteEncodable else {
            return false
        }
        return estimatedStartStarShortage == 0
    }

    func prepareFolderOutputDirectoryForStart(
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard var batch = folderBatch,
              batch.sourceKind == .folder else {
            return true
        }
        if batch.outputFolderURL != nil {
            return true
        }
        guard let bookmarkData = defaults.data(forKey: Self.folderOutputBookmarkKey),
              let outputFolderURL = resolveSecurityScopedAccessURL(from: bookmarkData),
              activateFolderOutputDirectory(outputFolderURL) else {
            defaults.removeObject(forKey: Self.folderOutputBookmarkKey)
            return false
        }

        batch.selectedSaveDestination = .sourceFolder
        batch.outputFolderURL = outputFolderURL.standardizedFileURL
        folderBatch = batch
        AppLogger.info(
            "Stored folder output directory restored",
            category: .saving,
            metadata: ["name": outputFolderURL.lastPathComponent]
        )
        return true
    }

    @discardableResult
    func selectFolderOutputDirectory(
        _ url: URL,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard var batch = folderBatch,
              batch.sourceKind == .folder,
              activateFolderOutputDirectory(url) else {
            AppLogger.warning(
                "Folder output directory selection rejected",
                category: .saving,
                metadata: ["name": url.lastPathComponent]
            )
            return false
        }

        let outputFolderURL = url.standardizedFileURL
        batch.selectedSaveDestination = .sourceFolder
        batch.outputFolderURL = outputFolderURL
        folderBatch = batch
        if let bookmarkData = makeSecurityScopedBookmarkData(for: outputFolderURL) {
            defaults.set(bookmarkData, forKey: Self.folderOutputBookmarkKey)
        } else {
            defaults.removeObject(forKey: Self.folderOutputBookmarkKey)
        }
        AppLogger.info(
            "Folder output directory selected",
            category: .saving,
            metadata: ["name": outputFolderURL.lastPathComponent]
        )
        return true
    }

    var startActionTitle: String {
        let starCost = estimatedStartStarCost
        guard starCost > 0 else {
            return "Start"
        }
        return "Start (\(formattedStarDelta(-starCost)))"
    }

    var convertActionTitle: String {
        let cost = estimatedStartStarCost
        guard cost > 0 else { return "Convert" }
        let videos = cost == 1 ? "1 video" : "\(cost) videos"
        let stars = cost == 1 ? "1 Star" : "\(cost) Stars"
        return "Convert \(videos) · \(stars)"
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
        !state.isBusy && !isStartingEncoding && !isWatchingStarAd
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
        return estimatedStartStarCost(for: review)
    }

    private var estimatedStartStarShortage: Int {
        startStarShortage(
            required: estimatedStartStarCost,
            available: starWalletSnapshot.balance
        )
    }

    private var shouldPromptForMultiFileEncodingMode: Bool {
        guard let folderBatch,
              folderBatch.sourceKind == .files,
              folderBatch.remainingEncodableFileCount > 1,
              !hasConfirmedSeparateMultiFileEncoding else {
            return false
        }
        return true
    }

    private func estimatedStartStarCost(for review: PreparedEncodingReview) -> Int {
        guard review.videoInfo.isRouteEncodable else {
            return 0
        }
        guard let folderBatch else {
            return 1
        }
        return max(folderBatch.remainingEncodableFileCount, 1)
    }

    private func startStarShortage(required: Int, available: Int) -> Int {
        max(required - available, 0)
    }

    private func blockEncodingStartForInsufficientStars(
        review: PreparedEncodingReview,
        requiredStarCount: Int,
        availableStarCount: Int
    ) {
        AppLogger.info(
            "Start encoding ignored because stars are insufficient",
            category: .encoding,
            metadata: [
                "name": review.source.displayName,
                "required": "\(requiredStarCount)",
                "available": "\(availableStarCount)",
                "shortage": "\(startStarShortage(required: requiredStarCount, available: availableStarCount))"
            ]
        )
        activeStarCharge = nil
        shouldAutoResumeBatchAfterStarEarn = false
        activeTask = nil
        state = .readyToStart(review)
    }

    private func resetMultiFileEncodingDecision() {
        multiFileEncodingPrompt = nil
        multiFileMergeUnavailableAlert = nil
        hasConfirmedSeparateMultiFileEncoding = false
    }

    private func applyFolderStarBudgetToCurrentBatchIfReady() {
        guard hasLoadedStarWallet,
              !state.isBusy,
              let batch = folderBatch else {
            return
        }
        folderBatch = applyFolderStarBudget(to: batch)
    }

    private func applyFolderStarBudget(to batch: FolderEncodingBatch) -> FolderEncodingBatch {
        guard hasLoadedStarWallet else {
            return batch
        }

        var remainingStarSlots = max(starWalletSnapshot.balance, 0)
        var updatedBatch = batch
        for url in updatedBatch.fileURLs {
            var item = updatedBatch.itemStates[url] ?? .queued
            guard item.videoInfo != nil || item.asset != nil else {
                updatedBatch.itemStates[url] = item
                continue
            }

            guard item.isRouteEncodable else {
                item.isEnabled = false
                item.isStarLimited = false
                updatedBatch.itemStates[url] = item
                continue
            }

            if remainingStarSlots > 0 {
                remainingStarSlots -= 1
                item.isEnabled = true
                item.isStarLimited = false
                if item.statusText == "Need Stars" {
                    item.statusText = item.isActive ? (item.videoInfo?.readinessStatusText ?? "Ready") : "Queued"
                    item.detailText = item.isActive
                        ? item.videoInfo?.readinessDetailText
                        : folderQueuedDetailText(for: item)
                }
            } else {
                item.progress = nil
                item.isActive = false
                item.isEnabled = false
                item.isStarLimited = true
                item.statusText = "Need Stars"
                item.detailText = "Move this video higher in the queue or add Stars to include it."
            }
            updatedBatch.itemStates[url] = item
        }

        updatedBatch.currentIndex = firstQueueIndex(for: updatedBatch)
        return updatedBatch
    }

    private func folderQueuedDetailText(for item: BatchItemRuntime) -> String? {
        guard let info = item.videoInfo else {
            return item.detailText
        }
        return "\(info.codecPathTitle). Ready to encode."
    }

    private func queueSelectableURL(in batch: FolderEncodingBatch) -> URL? {
        batch.fileURLs.first { url in
            let item = batch.itemStates[url]
            return item?.isStarLimited != true
                && (item?.isEnabled != false || item?.isPreviewable == true)
        } ?? batch.fileURLs.first
    }

    private func formattedStarDelta(_ delta: Int) -> String {
        let absoluteValue = abs(delta)
        let sign = delta < 0 ? "-" : "+"
        let noun = absoluteValue == 1 ? "Star" : "Stars"
        return "\(sign)\(absoluteValue) \(noun)"
    }

    var progressDetailText: String {
        switch state {
        case .readyToStart, .encoding:
            return "\(backgroundSummary) \(state.detail)"
        default:
            return state.detail
        }
    }

    var outputSummary: String {
        "\(selectedOutput.summary) / same folder + \(environment.configuration.outputSuffix)"
    }

    var selectedVideoCodecText: String {
        "Video: \(selectedOutput.videoCodec.displayName)"
    }

    var selectedAudioCodecText: String {
        "Audio: \(selectedOutput.audioCodec.displayName)"
    }

    var selectedEncodingOptimizationTitle: String {
        selectedOutput.optimizationProfile.menuTitle
    }

    var selectedEncodingOptimizationDetail: String {
        selectedOutput.optimizationProfile.detailText
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
        // Show the shape of the frame that will actually be written, so a fit/fill/stretch difference is visible
        // before the file is encoded.
        let size = selectedOutput.resolutionPreset.standardSize(for: sourceSize) ?? sourceSize
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
        HomeBackgroundReliabilityPresenter.message(
            currentOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            backgroundEncodingMinimumMajorVersion: environment.configuration.backgroundEncodingMinimumMajorVersion,
            liveActivitiesEnabled: environment.liveActivityCoordinator.areActivitiesEnabled
        )
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

    func selectEncodingOptimizationProfile(_ profile: TaptionEncodingOptimizationProfile) {
        guard selectedOutput.optimizationProfile != profile else {
            return
        }

        selectedOutput.optimizationProfile = profile
        AppLogger.info(
            "Encoding optimization profile selected",
            category: .ui,
            metadata: ["profile": profile.rawValue]
        )
        refreshPreparedSourceAfterOutputChange()
    }

    #if DEBUG
    func applyDebugEncodingOptimizationProfileIfRequested() {
        guard let requestedProfile = ProcessInfo.processInfo.environment["TAPTION_CODEC_PROBE_PROFILE"]
            ?? ProcessInfo.processInfo.environment["TAPTION_ENCODING_OPTIMIZATION_PROFILE"],
              let profile = TaptionEncodingOptimizationProfile.fromDebugString(requestedProfile) else {
            return
        }

        selectEncodingOptimizationProfile(profile)
        AppLogger.info(
            "Debug encoding optimization profile applied",
            category: .encoding,
            metadata: ["profile": profile.rawValue]
        )
    }
    #endif

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
        guard preset != .source,
              let size = preset.standardSize(
                for: selectedAssetForOutputConfiguration?.videoTrack?.displaySize
              ) else {
            return preset.menuTitle
        }
        let sizeText = "\(size.width)x\(size.height)"
        if resolutionPresetUpscales(preset) {
            return "\(preset.menuTitle) · \(sizeText) · Upscale"
        }
        return "\(preset.menuTitle) · \(sizeText)"
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
        // Every standard preset is now reachable. Refusing the presets that were larger than the source hid the
        // only way to turn an odd-sized video into 1080p or 4K, and the encoder can enlarge a picture perfectly
        // well. `resolutionPresetUpscales` marks the ones that enlarge so the menu can say so.
        true
    }

    func resolutionPresetUpscales(
        _ preset: TaptionOutputResolutionPreset,
        for asset: TaptionVideoAsset? = nil
    ) -> Bool {
        preset.upscales(sourceSize: (asset ?? selectedAssetForOutputConfiguration)?.videoTrack?.displaySize)
    }

    var selectedScaleMode: TaptionVideoScaleMode {
        selectedOutput.scaleMode
    }

    var selectedScaleModeDetail: String {
        selectedOutput.scaleMode.detailText
    }

    /// The fit/fill/stretch choice only exists when the target frame has a different shape than the source.
    var showsScaleModeControl: Bool {
        selectedOutput.resolutionPreset.needsScaleModeChoice(
            for: selectedAssetForOutputConfiguration?.videoTrack?.displaySize
        )
    }

    var selectedOutputFrameSizeText: String? {
        guard let size = selectedOutput.resolutionPreset.standardSize(
            for: selectedAssetForOutputConfiguration?.videoTrack?.displaySize
        ) else {
            return nil
        }
        return "\(size.width)x\(size.height)"
    }
    func selectScaleMode(_ mode: TaptionVideoScaleMode) {
        guard canChangeOutputSelection,
              selectedOutput.scaleMode != mode else {
            return
        }

        selectedOutput.scaleMode = mode
        AppLogger.info(
            "Output scale mode selected",
            category: .ui,
            metadata: ["scaleMode": mode.rawValue]
        )
        refreshPreparedSourceAfterOutputChange()
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
            state = .failed(HomeErrorPresenter.error(
                title: "Restore failed",
                summary: "The app could not restore pending save jobs.",
                recovery: "Open the completed output again or retry the save from the pending queue.",
                error: error
            ))
        }
    }

    func refreshStarsIfNeeded() async {
        if !hasLoadedStarWallet {
            hasLoadedStarWallet = true
        }
        starWalletSnapshot = await environment.starWalletStore.currentSnapshot()
        applyFolderStarBudgetToCurrentBatchIfReady()
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
            rewardedAdPollingID = nil
        }
    }

    private func startRewardedAdStatePolling() {
        rewardedAdStatePollingTask?.cancel()
        let operationID = UUID()
        rewardedAdPollingID = operationID
        let service = environment.starEarningService
        rewardedAdStatePollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let state = await service.prepareNextAd()
                guard !Task.isCancelled,
                      let shouldContinue = self?.applyPolledAdState(state, operationID: operationID) else { return }
                if !shouldContinue { break }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
            self?.finishAdPolling(operationID: operationID)
        }
    }

    private func applyPolledAdState(_ state: AdLoadState, operationID: UUID) -> Bool {
        guard rewardedAdPollingID == operationID else { return false }
        rewardedAdState = state
        return state != .ready && !isWatchingStarAd
    }

    private func finishAdPolling(operationID: UUID) {
        guard rewardedAdPollingID == operationID else { return }
        rewardedAdPollingID = nil
        rewardedAdStatePollingTask = nil
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
        guard !selectedURLs.isEmpty else {
            return
        }

        let folderURLs = selectedURLs.filter(selectedURLIsDirectory)
        let fileURLs = supportedVideoFileURLs(from: selectedURLs)
        let skippedFileCount = selectedURLs.count - folderURLs.count - fileURLs.count
        if skippedFileCount > 0 {
            AppLogger.info(
                "Unsupported files skipped from picker selection",
                category: .fileImport,
                metadata: ["count": "\(skippedFileCount)"]
            )
        }
        if !fileURLs.isEmpty {
            if fileURLs.count == 1 {
                startFilesFlow(url: fileURLs[0])
            } else {
                startFilesFlow(urls: fileURLs)
            }
            return
        }

        guard let folderURL = folderURLs.first else {
            AppLogger.warning(
                "Picker selection ignored because it contains no supported videos or folders",
                category: .fileImport
            )
            return
        }
        startFolderFlow(url: folderURL)
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
        openImportBrowserRoot(url: url, mode: mode, authorizedRootURL: nil)
    }

    func openImportBrowserRoot(url: URL, mode: HomeImportBrowserMode, authorizedRootURL: URL?) {
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
        standaloneSelectedQueueIDs.removeAll()
        resetMultiFileEncodingDecision()
        lastBatchFileCards = []
        folderPreviewContext = nil
        folderBatch = nil
        let standardizedURL = url.standardizedFileURL
        let authorizedRootURL = authorizedRootURL?.standardizedFileURL
        let scopedURLs = [authorizedRootURL, standardizedURL].compactMap { $0 }
        beginSecurityScopedAccessIfNeeded(for: scopedURLs)
        let scope = importBrowserNavigationScope(
            for: standardizedURL,
            authorizedRootURL: authorizedRootURL
        )
        importBrowserMode = mode
        importBrowserRootURL = scope.rootURL
        importBrowserRootDisplayName = scope.displayName
        importBrowserCurrentURL = standardizedURL
        importBrowserHistory = []
        importBrowserSelectedFileURLs = []
        selectAllImportBrowserFilesIfNeeded(in: standardizedURL)
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
        let nextURL = URL(fileURLWithPath: folder.id).standardizedFileURL
        importBrowserCurrentURL = nextURL
        selectAllImportBrowserFilesIfNeeded(in: nextURL)
        refreshImportBrowser()
    }

    func navigateImportBrowserBack() {
        guard let previousURL = importBrowserHistory.popLast() else {
            guard importBrowserRootURL != nil else {
                return
            }
            importBrowserRootURL = nil
            importBrowserRootDisplayName = nil
            importBrowserCurrentURL = nil
            importBrowserHistory = []
            importBrowserSelectedFileURLs = []
            stopSecurityScopedAccess()
            refreshImportBrowser()
            return
        }
        importBrowserCurrentURL = previousURL
        selectAllImportBrowserFilesIfNeeded(in: previousURL)
        refreshImportBrowser()
    }

    func navigateImportBrowserUp() {
        guard let rootURL = importBrowserRootURL?.standardizedFileURL,
              let currentURL = importBrowserCurrentURL?.standardizedFileURL,
              currentURL != rootURL else {
            guard importBrowserRootURL != nil else {
                return
            }
            importBrowserRootURL = nil
            importBrowserRootDisplayName = nil
            importBrowserCurrentURL = nil
            importBrowserHistory = []
            importBrowserSelectedFileURLs = []
            stopSecurityScopedAccess()
            refreshImportBrowser()
            return
        }

        let parentURL = currentURL.deletingLastPathComponent()
        guard importBrowserURL(parentURL, isInsideRoot: rootURL) else {
            return
        }
        importBrowserHistory.append(currentURL)
        importBrowserCurrentURL = parentURL
        selectAllImportBrowserFilesIfNeeded(in: parentURL)
        refreshImportBrowser()
    }

    func toggleImportBrowserFileSelection(id: String) {
        guard importBrowserMode != nil,
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
            let visibleFileURLs = Set(importBrowserFiles.map { URL(fileURLWithPath: $0.id).standardizedFileURL })
            let selectedURLs = importBrowserSelectedFileURLs
                .filter { visibleFileURLs.contains($0.standardizedFileURL) }
                .sorted {
                    $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
            guard !selectedURLs.isEmpty else {
                AppLogger.warning("Import browser folder import ignored because no files are selected", category: .fileImport)
                return
            }
            let rootURL = importBrowserRootURL
            clearImportBrowserState(stoppingAccess: false)
            openFolderSelectionPreviewBrowser(
                folderURL: currentURL,
                fileURLs: selectedURLs,
                securityScopedRootURL: rootURL
            )
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

        let selectedURLs = supportedVideoFileURLs(from: urls)
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
        standaloneSelectedQueueIDs.removeAll()
        resetMultiFileEncodingDecision()
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

    private func openFolderSelectionPreviewBrowser(
        folderURL: URL,
        fileURLs: [URL],
        securityScopedRootURL: URL?
    ) {
        AppLogger.info(
            "Folder selection preview browser requested",
            category: .folderImport,
            metadata: [
                "folder": folderURL.lastPathComponent,
                "count": "\(fileURLs.count)",
                "names": fileURLs.map(\.lastPathComponent).joined(separator: "|")
            ]
        )
        guard canStartNewSourceFlow() else {
            return
        }
        guard state.canSelectSource else {
            AppLogger.warning(
                "Folder selection preview browser ignored because source selection is disabled",
                category: .folderImport,
                metadata: ["state": "\(state)"]
            )
            return
        }

        let selectedURLs = fileURLs.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        guard !selectedURLs.isEmpty else {
            AppLogger.warning("Folder selection preview browser ignored because no files were selected", category: .folderImport)
            return
        }

        dismissPreview()
        activeTask?.cancel()
        selectionInspectionTask?.cancel()
        previewInspectionTask?.cancel()
        currentReview = nil
        standaloneSelectedQueueIDs.removeAll()
        resetMultiFileEncodingDecision()
        lastBatchFileCards = []
        folderPreviewContext = nil
        folderBatch = FolderEncodingBatch(
            folderURL: folderURL,
            folderName: folderURL.lastPathComponent,
            sourceKind: .folder,
            fileURLs: selectedURLs
        )
        let scopedURLs = ([securityScopedRootURL].compactMap { $0 } + [folderURL] + selectedURLs)
        beginSecurityScopedAccessIfNeeded(for: scopedURLs)
        folderPreviewContext = FolderPreviewContext(
            id: "\(folderURL.standardizedFileURL.absoluteString)-selected-\(UUID().uuidString)",
            folderName: folderURL.lastPathComponent,
            fileCount: selectedURLs.count
        )
        state = .idle
    }

    func openExternalPlayerFile(url: URL) {
        AppLogger.info(
            "External player file routed into queue flow",
            category: .fileImport,
            metadata: ["name": url.lastPathComponent]
        )
        startFilesFlow(
            url: url,
            autoStartAfterPrepare: false,
            autoOpenPreviewAfterPrepare: true
        )
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

    func openDebugFileAndAutoOpenPreview(url: URL) {
        AppLogger.info(
            "Debug file routed into auto-preview flow",
            category: .fileImport,
            metadata: ["name": url.lastPathComponent]
        )
        startFilesFlow(url: url, autoStartAfterPrepare: false, autoOpenPreviewAfterPrepare: true)
    }
    #endif

    func startFilesFlow(url: URL) {
        startFilesFlow(url: url, autoStartAfterPrepare: false)
    }

    private func startFilesFlow(
        url: URL,
        autoStartAfterPrepare: Bool,
        autoOpenPreviewAfterPrepare: Bool = false,
        securityScopedRootURL: URL? = nil,
        knownPreviewURLs: [URL]? = nil
    ) {
        AppLogger.info(
            "Single file flow started",
            category: .fileImport,
            metadata: [
                "name": url.lastPathComponent,
                "autoStart": "\(autoStartAfterPrepare)",
                "autoOpenPreview": "\(autoOpenPreviewAfterPrepare)"
            ]
        )
        guard state.canSelectSource, canStartNewSourceFlow() else {
            return
        }
        dismissPreview()
        selectionInspectionTask?.cancel()
        folderBatch = nil
        folderPreviewContext = nil
        currentReview = nil
        standaloneSelectedQueueIDs.removeAll()
        resetMultiFileEncodingDecision()
        lastBatchFileCards = []
        let source = HomeSelectedSource(
            kind: .files,
            displayName: url.lastPathComponent,
            url: url
        )
        let authorizedFolders = [securityScopedRootURL].compactMap { $0 } + storedPreviewFolderAccess(for: url)
        beginSecurityScopedAccessIfNeeded(for: authorizedFolders + [url, url.deletingLastPathComponent()])
        prepareSingleFilePreviewContext(for: url, knownURLs: knownPreviewURLs)
        prepareEncodingFlow(
            source: source,
            autoStartAfterPrepare: autoStartAfterPrepare,
            autoOpenPreviewAfterPrepare: autoOpenPreviewAfterPrepare
        )
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
        let selectedURLs = supportedVideoFileURLs(from: urls)
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
        standaloneSelectedQueueIDs.removeAll()
        resetMultiFileEncodingDecision()
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
        resetMultiFileEncodingDecision()
        lastBatchFileCards = []
        folderPreviewContext = nil
        folderBatch = nil
        let scopedURLs = ([securityScopedRootURL].compactMap { $0 } + [url])
        beginSecurityScopedAccessIfNeeded(for: scopedURLs)

        do {
            let fileURLs = try videoFileURLs(in: url)
            rememberPreviewFolderAccess(securityScopedRootURL ?? url)
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
            state = .failed(HomeErrorPresenter.error(
                title: "Folder failed",
                summary: "The selected folder could not be opened.",
                recovery: "Choose the folder again from Files and keep BOKKI Encoder open until the queue appears.",
                error: error
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
            state = .failed(HomeErrorPresenter.error(
                title: "Samples failed",
                summary: "The sample library could not be prepared.",
                recovery: "Reset the samples and try opening the sample library again.",
                error: error
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
        beginSecurityScopedAccessIfNeeded(for: [])
        selectionInspectionTask?.cancel()
        folderBatch = nil
        folderPreviewContext = nil
        currentReview = nil
        standaloneSelectedQueueIDs.removeAll()
        resetMultiFileEncodingDecision()
        lastBatchFileCards = []
        let source = HomeSelectedSource(
            kind: .photos,
            displayName: displayName,
            url: url
        )
        prepareEncodingFlow(source: source, autoOpenPreviewAfterPrepare: false)
    }

    func startPhotoLibraryFlow(_ selection: PhotoLibrarySelection) {
        guard state.canSelectSource, canStartNewSourceFlow() else { return }
        var seen: Set<String> = []
        let videos = selection.videos.filter { seen.insert($0.id).inserted }
        guard let selected = videos.first(where: { $0.id == selection.selectedID }) else { return }
        dismissPreview()
        activeTask?.cancel()
        selectionInspectionTask?.cancel()
        folderBatch = nil
        folderPreviewContext = nil
        currentReview = nil
        standaloneSelectedQueueIDs.removeAll()
        resetMultiFileEncodingDecision()
        lastBatchFileCards = []
        beginSecurityScopedAccessIfNeeded(for: [])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TaptionAlbumImports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let entries = videos.map { video in
            (directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(URL(fileURLWithPath: video.fileName).lastPathComponent), video)
        }
        guard let selectedURL = entries.first(where: { $0.1.id == selected.id })?.0 else { return }
        var context = SingleFilePreviewContext(initialURL: selectedURL, fileURLs: entries.map { $0.0 }, queuedURLs: [selectedURL])
        context.sourceKind = .photos
        context.sourceName = selection.albumName
        context.photoVideos = Dictionary(uniqueKeysWithValues: entries)
        singleFilePreviewContext = context
        let source = HomeSelectedSource(kind: .photos, displayName: selected.fileName, url: selectedURL)
        state = .importing(source)
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.photoVideoLoader.loadVideo(selected, to: selectedURL)
                guard !Task.isCancelled, self.singleFilePreviewContext?.id == context.id else { return }
                self.prepareEncodingFlow(source: source, autoOpenPreviewAfterPrepare: true,
                                         deferEncodingPreparationUntilStart: true, allowsBusyState: true)
            } catch is CancellationError {
                if self.singleFilePreviewContext?.id == context.id { self.state = .cancelled }
            } catch {
                guard !Task.isCancelled, self.singleFilePreviewContext?.id == context.id else { return }
                self.fail(message: error.localizedDescription)
            }
        }
    }

    private func sourceDisplayName(for url: URL) -> String {
        singleFilePreviewContext?.displayName(for: url) ?? url.lastPathComponent
    }

    func toggleQueueFileSelection(id: String) {
        guard !state.isBusy else {
            AppLogger.info("Queue selection ignored because encoder is busy", category: .ui)
            return
        }

        if var batch = folderBatch,
           let selectedURL = queueURL(for: id, in: batch) {
            if batch.multiSelectedURLs.contains(selectedURL) {
                batch.multiSelectedURLs.remove(selectedURL)
            } else {
                batch.multiSelectedURLs.insert(selectedURL)
            }
            folderBatch = batch
            objectWillChange.send()
            AppLogger.info(
                "Queue item selection toggled",
                category: .ui,
                metadata: [
                    "name": selectedURL.lastPathComponent,
                    "selectedCount": "\(batch.multiSelectedURLs.count)"
                ]
            )
            return
        }

        guard standaloneQueueMatches(id: id) else {
            AppLogger.warning("Queue selection ignored because item was not found", category: .ui)
            return
        }
        if standaloneSelectedQueueIDs.contains(id) {
            standaloneSelectedQueueIDs.remove(id)
        } else {
            standaloneSelectedQueueIDs.insert(id)
        }
        objectWillChange.send()
        AppLogger.info(
            "Standalone queue item selection toggled",
            category: .ui,
            metadata: ["id": id, "selectedCount": "\(standaloneSelectedQueueIDs.count)"]
        )
    }

    func moveQueueFiles(draggedID: String, before targetID: String) {
        guard !state.isBusy else {
            return
        }
        guard var batch = folderBatch,
              let draggedURL = queueURL(for: draggedID, in: batch),
              let targetURL = queueURL(for: targetID, in: batch),
              draggedURL != targetURL else {
            return
        }

        let movingURLs: [URL]
        if batch.multiSelectedURLs.contains(draggedURL) {
            movingURLs = batch.fileURLs.filter { batch.multiSelectedURLs.contains($0) }
        } else {
            movingURLs = [draggedURL]
        }
        guard !movingURLs.contains(targetURL) else {
            return
        }

        let originalMovingIndices = movingURLs.compactMap { batch.fileURLs.firstIndex(of: $0) }
        guard let firstMovingIndex = originalMovingIndices.min(),
              let targetOriginalIndex = batch.fileURLs.firstIndex(of: targetURL) else {
            return
        }

        var reorderedURLs = batch.fileURLs.filter { !movingURLs.contains($0) }
        guard let targetIndex = reorderedURLs.firstIndex(of: targetURL) else {
            return
        }
        let insertionIndex = targetOriginalIndex > firstMovingIndex ? targetIndex + 1 : targetIndex
        reorderedURLs.insert(contentsOf: movingURLs, at: insertionIndex)
        batch.fileURLs = reorderedURLs
        if singleFilePreviewContext != nil {
            singleFilePreviewContext?.queuedURLs = reorderedURLs
        }
        batch = applyFolderStarBudget(to: batch)
        batch.currentIndex = queueCurrentIndex(for: batch)
        folderBatch = batch
        objectWillChange.send()
    }

    func finishQueueMove() {
        guard !state.isBusy,
              var batch = folderBatch else {
            return
        }
        batch = applyFolderStarBudget(to: batch)
        batch.currentIndex = firstQueueIndex(for: batch)
        folderBatch = batch

        guard let currentURL = batch.currentFileURL,
              currentReview?.source.url != currentURL else {
            return
        }

        AppLogger.info(
            "Queue order committed",
            category: .ui,
            metadata: ["next": currentURL.lastPathComponent]
        )
        dismissPreview()
        currentReview = nil
        activeTask?.cancel()
        activeTask = nil
        prepareCurrentFolderItem(autoStartAfterPrepare: false, allowsBusyState: true)
    }

    func deleteQueueFile(id: String) {
        guard !state.isBusy else {
            AppLogger.info("Queue delete ignored because encoder is busy", category: .ui)
            return
        }

        if let batch = folderBatch,
           let targetURL = queueURL(for: id, in: batch) {
            let deleteURLs = batch.multiSelectedURLs.isEmpty
                ? [targetURL]
                : batch.fileURLs.filter { batch.multiSelectedURLs.contains($0) }
            deleteQueueURLs(deleteURLs)
            return
        }

        guard standaloneQueueMatches(id: id) else {
            AppLogger.warning("Queue delete ignored because item was not found", category: .ui)
            return
        }

        AppLogger.info("Standalone queue item deleted", category: .ui, metadata: ["id": id])
        dismissPreview()
        activeTask?.cancel()
        activeTask = nil
        currentReview = nil
        standaloneSelectedQueueIDs.removeAll()
        state = .idle
        stopSecurityScopedAccess()
    }

    func openPreviewForFileCard(id: String) {
        if let url = singleFilePreviewContext?.fileURLs.first(where: { $0.absoluteString == id }),
           openSingleFileSiblingPreview(url: url) { return }
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

    func openConnectedFilesFolder(_ folderURL: URL) {
        startFolderFlow(url: folderURL)
        guard folderPreviewContext != nil else { return }
        folderPreviewContext?.selectsSingleFile = true
        folderBatch?.sourceKind = .files
    }

    func selectFolderPreviewFile(id: String) {
        if folderPreviewContext?.selectsSingleFile == true,
           let batch = folderBatch, let folder = batch.folderURL,
           let url = batch.fileURLs.first(where: { $0.absoluteString == id }) {
            startFilesFlow(url: url, autoStartAfterPrepare: false,
                           autoOpenPreviewAfterPrepare: true, securityScopedRootURL: folder,
                           knownPreviewURLs: batch.fileURLs)
            return
        }
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
        miniPlayerPreview = nil
    }

    func isPreviewAddedToList(_ preview: QueueVideoPreview) -> Bool {
        if let context = singleFilePreviewContext, context.fileURLs.contains(preview.sourceURL) {
            return context.queuedURLs.contains(preview.sourceURL)
        }
        if folderPreviewContext != nil {
            return previewAddedToListURLs.contains(preview.sourceURL)
        }
        if let batch = folderBatch {
            return batch.fileURLs.contains(preview.sourceURL)
        }
        return (currentReview ?? state.preparedEncodingReview)?.source.url == preview.sourceURL
    }

    func canAddPreviewToList(_ preview: QueueVideoPreview) -> Bool {
        if let context = singleFilePreviewContext, context.fileURLs.contains(preview.sourceURL) {
            return activePreview?.id == preview.id && activePreview?.sourceURL == preview.sourceURL
                && !state.isBusy && state.canSelectSource && !context.queuedURLs.contains(preview.sourceURL)
        }
        guard activePreview?.id == preview.id,
              activePreview?.sourceURL == preview.sourceURL,
              !state.isBusy, state.canSelectSource,
              folderPreviewContext != nil,
              !isPreviewAddedToList(preview) else { return false }
        return folderBatch?.fileURLs.contains(preview.sourceURL) == true
    }

    @discardableResult
    func addPreviewToList(_ preview: QueueVideoPreview) -> Bool {
        guard canAddPreviewToList(preview) else { return false }
        if singleFilePreviewContext?.fileURLs.contains(preview.sourceURL) == true {
            singleFilePreviewContext?.queuedURLs.append(preview.sourceURL)
            return true
        }
        // Keep the browser and player alive. Membership changes must never
        // replace the current preview, seek, pause or prepare an encoding job.
        previewAddedToListURLs.append(preview.sourceURL)
        AppLogger.info("Preview added to conversion list", category: .ui,
                       metadata: ["name": preview.displayName])
        return true
    }

    func closePreviewFromPlayer() {
        guard activePreview != nil else { return }
        if let context = singleFilePreviewContext {
            dismissPreview()
            let existing = folderBatch?.fileURLs ?? [(currentReview ?? state.preparedEncodingReview)?.source.url].compactMap { $0 }
            guard existing != context.queuedURLs else { return }
            var batch = FolderEncodingBatch(folderURL: context.sourceKind == .photos ? nil : context.initialURL.deletingLastPathComponent(),
                folderName: context.sourceName ?? context.initialURL.deletingLastPathComponent().lastPathComponent,
                sourceKind: context.sourceKind, fileURLs: context.queuedURLs)
            for url in context.queuedURLs { batch.itemStates[url] = context.items[url] }
            folderBatch = batch
            currentReview = nil
            guard let first = batch.currentFileURL else { return }
            prepareEncodingFlow(source: HomeSelectedSource(kind: context.sourceKind, displayName: context.displayName(for: first), url: first),
                deferEncodingPreparationUntilStart: true, preinspectedAsset: context.items[first]?.asset)
            return
        }
        let browserBatch = folderPreviewContext == nil ? nil : folderBatch
        let addedURLs = previewAddedToListURLs
        dismissPreview()
        guard let batch = browserBatch, !addedURLs.isEmpty else { return }
        if let initial = addedURLs.first {
            var context = SingleFilePreviewContext(initialURL: initial, fileURLs: batch.fileURLs, queuedURLs: addedURLs)
            context.sourceKind = batch.sourceKind
            context.sourceName = batch.folderName
            context.items = batch.itemStates
            singleFilePreviewContext = context
        }

        var queuedBatch = FolderEncodingBatch(
            folderURL: batch.folderURL,
            folderName: batch.folderName,
            sourceKind: batch.sourceKind,
            fileURLs: addedURLs
        )
        for url in addedURLs { queuedBatch.itemStates[url] = batch.itemStates[url] }
        selectionInspectionTask?.cancel()
        selectionInspectionTask = nil
        folderBatch = queuedBatch
        folderPreviewContext = nil
        currentReview = nil
        resetMultiFileEncodingDecision()
        guard let firstURL = queuedBatch.currentFileURL else { return }
        prepareEncodingFlow(
            source: HomeSelectedSource(kind: batch.sourceKind,
                                       displayName: firstURL.lastPathComponent, url: firstURL),
            deferEncodingPreparationUntilStart: true,
            preinspectedAsset: queuedBatch.itemStates[firstURL]?.asset
        )
    }

    func minimizePreview(_ preview: QueueVideoPreview, snapshot: QueuePreviewPlaybackSnapshot? = nil) {
        guard activePreview?.id == preview.id else { return }
        previewInspectionTask?.cancel()
        previewInspectionTask = nil
        var handoffPreview = preview
        handoffPreview.playbackSnapshot = snapshot ?? preview.playbackSnapshot
        activePreview = nil
        miniPlayerPreview = handoffPreview
    }

    func dismissMiniPreview() {
        if let preview = miniPlayerPreview {
            AppLogger.info("Queue mini player closed", category: .ui,
                           metadata: ["name": preview.displayName])
        }
        miniPlayerPreview = nil
    }

    func restorePreview(_ preview: QueueVideoPreview, snapshot: QueuePreviewPlaybackSnapshot? = nil) {
        guard var handoffPreview = miniPlayerPreview, handoffPreview.id == preview.id else { return }
        handoffPreview.playbackSnapshot = snapshot ?? handoffPreview.playbackSnapshot
        AppLogger.info(
            "Queue mini player restored to full preview",
            category: .ui,
            metadata: ["name": preview.displayName]
        )
        presentPreview(handoffPreview)
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
            if !standaloneSelectedQueueIDs.isEmpty {
                standaloneSelectedQueueIDs.removeAll()
                objectWillChange.send()
                AppLogger.info("Standalone queue selections cleared by card tap", category: .ui)
                return
            }
            AppLogger.warning("File card selection ignored because item was not found", category: .ui)
            return
        }

        let item = batch.itemStates[selectedURL] ?? .queued
        let clearedSelectionCount = batch.multiSelectedURLs.count
        if clearedSelectionCount > 0 {
            batch.multiSelectedURLs.removeAll()
        }
        if !item.isEnabled {
            AppLogger.info(
                "Disabled file card selected",
                category: .ui,
                metadata: [
                    "name": selectedURL.lastPathComponent,
                    "status": item.statusText
                ]
            )
        }

        AppLogger.info(
            "File card selected",
            category: .ui,
            metadata: [
                "name": selectedURL.lastPathComponent,
                "clearedSelectionCount": "\(clearedSelectionCount)"
            ]
        )
        batch.selectedURL = selectedURL
        folderBatch = batch
        objectWillChange.send()

        guard item.videoInfo == nil,
              item.detailText == nil,
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
        guard !isStartingEncoding else { return }
        guard prepareFolderOutputDirectoryForStart() else {
            AppLogger.info(
                "Start encoding is waiting for a folder output directory",
                category: .saving
            )
            return
        }
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
        let requiredStarCount = estimatedStartStarCost(for: review)
        guard startStarShortage(
            required: requiredStarCount,
            available: starWalletSnapshot.balance
        ) == 0 else {
            blockEncodingStartForInsufficientStars(
                review: review,
                requiredStarCount: requiredStarCount,
                availableStarCount: starWalletSnapshot.balance
            )
            return
        }
        if shouldPromptForMultiFileEncodingMode {
            let fileCount = folderBatch?.remainingEncodableFileCount ?? 0
            multiFileEncodingPrompt = MultiFileEncodingPrompt(fileCount: fileCount)
            AppLogger.info(
                "Multi-file encoding prompt opened",
                category: .encoding,
                metadata: ["count": "\(fileCount)"]
            )
            return
        }
        dismissPreview()
        requestEncodingStart(for: review, autoResumeAfterStarEarn: false)
    }

    private func prepareSingleFilePreviewContext(for url: URL, knownURLs: [URL]? = nil) {
        guard url.isFileURL else { return }
        var context = SingleFilePreviewContext(initialURL: url, fileURLs: [url], queuedURLs: [url])
        if let knownURLs, knownURLs.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
            context.fileURLs = MediaFileIdentity.uniqueURLs(knownURLs).map {
                $0.standardizedFileURL == url.standardizedFileURL ? url : $0
            }
            singleFilePreviewContext = context
            return
        }
        do {
            context.fileURLs = try singleFilePreviewURLs(around: url)
        } catch {
            context.needsFolderAccess = true
            AppLogger.info("Single file preview needs folder access", category: .fileImport)
        }
        singleFilePreviewContext = context
    }

    func consumeInitialVideoFolderAccessRequest() -> Bool {
        guard case .idle = state, activePreview == nil, miniPlayerPreview == nil,
              folderPreviewContext == nil, fileCardSnapshots.isEmpty else { return false }
        guard !hasRequestedInitialFolderAccess, previewFolderBookmarks.authorizedFolders().isEmpty else { return false }
        hasRequestedInitialFolderAccess = true
        return true
    }

    /// The selected parent grant covers its descendants without importing them.
    func connectVideoFolder(_ folderURL: URL) -> String? {
        connectVideoFolders([folderURL])
    }

    var connectedVideoFolders: [URL] { previewFolderBookmarks.authorizedFolders() }

    /// A selection grants its descendants; it never grants unrelated device locations.
    func connectVideoFolders(_ folderURLs: [URL]) -> String? {
        guard !folderURLs.isEmpty else { return nil }
        guard folderURLs.allSatisfy(\.isFileURL) else { return "Choose folders containing your videos." }
        var seen: Set<URL> = []
        let folders = folderURLs.filter { seen.insert(MediaFileIdentity.canonicalURL($0)).inserted }
        let scoped = folders.filter { $0.startAccessingSecurityScopedResource() }
        defer { for folder in scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            for folder in folders {
                guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                    return "Choose folders containing your videos. No new folder access was saved."
                }
                _ = try videoFileURLs(in: folder)
            }
            guard previewFolderBookmarks.remember(folders) else {
                return "Folder access could not be saved. Try selecting the folders again."
            }
            return nil
        } catch {
            return "A selected folder could not be read. No new folder access was saved. Select your video folders again."
        }
    }

    /// Ask once per source flow, including when controls are initially hidden.
    /// Declining the request keeps playback and the manual information-menu action.
    func consumePreviewFolderAccessRequest(for previewID: String) -> Bool {
        guard let preview = activePreview, preview.id == previewID, preview.folderAccessURL != nil,
              let context = singleFilePreviewContext, context.sourceKind != .photos,
              context.initialURL == preview.sourceURL, context.needsFolderAccess,
              !context.hasRequestedFolderAccess else { return false }
        singleFilePreviewContext?.hasRequestedFolderAccess = true
        hasRequestedInitialFolderAccess = true
        return true
    }

    /// Retry a failed folder read using grants already held or explicitly saved.
    /// This never presents UI or obtains access to an unapproved directory.
    func restoreSingleFilePreviewNavigation(offset: Int) -> Bool {
        guard offset == -1 || offset == 1,
              let context = singleFilePreviewContext, context.needsFolderAccess,
              let currentURL = activePreview?.sourceURL, currentURL == context.initialURL else { return false }
        let folders = storedPreviewFolderAccess(for: currentURL)
        for folder in folders { securityScopedAccess.acquire(folder) }
        securityScopedAccess.acquire(currentURL.deletingLastPathComponent())
        do {
            let urls = try singleFilePreviewURLs(around: currentURL)
            singleFilePreviewContext?.fileURLs = urls
            singleFilePreviewContext?.needsFolderAccess = false
            activePreview?.playlist = singleFilePreviewContext?.playlist(for: currentURL)
            activePreview?.folderAccessURL = nil
            AppLogger.info("Preview folder navigation restored automatically", category: .fileImport,
                metadata: ["count": "\(urls.count)", "savedGrants": "\(folders.count)"])
            openAdjacentPreview(offset: offset)
            return true
        } catch {
            let failure = error as NSError
            AppLogger.warning("Preview folder navigation restore failed", category: .fileImport,
                metadata: ["domain": failure.domain, "code": "\(failure.code)", "savedGrants": "\(folders.count)"])
            return false
        }
    }

    private func previewFolder(_ folderURL: URL, contains fileURL: URL) -> Bool {
        MediaFileIdentity.folder(folderURL, contains: fileURL)
    }

    private func storedPreviewFolderAccess(for fileURL: URL) -> [URL] {
        previewFolderBookmarks.folders(containing: fileURL)
    }

    private func rememberPreviewFolderAccess(_ folderURL: URL) {
        previewFolderBookmarks.remember(folderURL)
    }

    private func singleFilePreviewURLs(around selectedURL: URL) throws -> [URL] {
        let selectedPath = selectedURL.standardizedFileURL.path
        var urls = try videoFileURLs(in: selectedURL.deletingLastPathComponent()).filter { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return true }
            return !type.conforms(to: .audio) || type.conforms(to: .movie)
        }.map { url in
            url.standardizedFileURL.path == selectedPath ? selectedURL : url
        }
        if !urls.contains(selectedURL) { urls.append(selectedURL) }
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// A Files URL can grant one document without granting its enclosing folder.
    /// Remember an explicitly connected folder without replacing playback.
    func authorizeSingleFilePreviewFolder(_ folderURL: URL, navigationOffset: Int) -> String? {
        guard let context = singleFilePreviewContext, context.needsFolderAccess,
              activePreview?.sourceURL == context.initialURL else { return nil }
        guard previewFolder(folderURL, contains: context.initialURL) else {
            return "Choose the folder containing this video."
        }
        securityScopedAccess.acquire(folderURL)
        do {
            let urls = try singleFilePreviewURLs(around: context.initialURL)
            singleFilePreviewContext?.fileURLs = urls
            singleFilePreviewContext?.needsFolderAccess = false
            activePreview?.playlist = singleFilePreviewContext?.playlist(for: context.initialURL)
            activePreview?.folderAccessURL = nil
            rememberPreviewFolderAccess(folderURL)
            if navigationOffset != 0 { openAdjacentPreview(offset: navigationOffset) }
            return nil
        } catch {
            return "This folder could not be read. Select the video's folder again."
        }
    }

    private func cacheSingleFilePreviewItem(url: URL, asset: TaptionVideoAsset, info: LoadedVideoInfo) {
        guard singleFilePreviewContext?.fileURLs.contains(url) == true else { return }
        var item = BatchItemRuntime.queued
        item.asset = asset
        item.videoInfo = info
        item.isRouteEncodable = info.isRouteEncodable
        item.isEnabled = info.isRouteEncodable
        item.isPreviewable = isPreviewableInCurrentBuild(asset: asset)
        singleFilePreviewContext?.items[url] = item
    }

    private func openSingleFileSiblingPreview(url: URL, navigationOffset: Int? = nil) -> Bool {
        guard let context = singleFilePreviewContext, context.fileURLs.contains(url) else { return false }
        guard canOpenFolderPreviewInCurrentState else { return true }
        previewInspectionTask?.cancel()
        if let review = currentReview ?? state.preparedEncodingReview, review.source.url == url,
           let preview = currentReviewPreview(for: url.absoluteString) {
            cacheSingleFilePreviewItem(url: url, asset: review.job.asset, info: review.videoInfo)
            presentPreview(preview)
            return true
        }
        previewInspectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let video = context.photoVideos[url] { try await self.photoVideoLoader.loadVideo(video, to: url) }
                try Task.checkCancellation()
                let inspected = try await self.inspectVideoReusingCache(at: url)
                guard !Task.isCancelled, self.singleFilePreviewContext?.id == context.id else { return }
                let asset = inspected.asset
                guard self.isPreviewableInCurrentBuild(asset: asset) else {
                    self.singleFilePreviewContext?.unavailableURLs.insert(url)
                    self.refreshSingleFilePlaylistAfterUnavailableItem(navigationOffset: navigationOffset)
                    return
                }
                let source = HomeSelectedSource(kind: context.sourceKind, displayName: context.displayName(for: url), url: url)
                let route = TaptionCodecRoutePlanner.selectRoute(for: asset,
                    outputCodec: self.selectedOutput.videoCodec, requestedMode: .automatic)
                let info = self.makeLoadedVideoInfo(source: source, asset: asset,
                    outputName: self.outputName(for: source), routeSelection: route)
                self.cacheSingleFilePreviewItem(url: url, asset: asset, info: info)
                self.presentPreview(QueueVideoPreview(id: url.absoluteString,
                    displayName: context.displayName(for: url), sourceURL: url, videoInfo: info,
                    displaySize: asset.videoTrack?.displaySize,
                    playlist: self.singleFilePreviewContext?.playlist(for: url),
                    usesNativePlayback: usesNativePlayback(for: asset)))
            } catch {
                guard !Task.isCancelled, self.singleFilePreviewContext?.id == context.id else { return }
                self.singleFilePreviewContext?.unavailableURLs.insert(url)
                self.refreshSingleFilePlaylistAfterUnavailableItem(navigationOffset: navigationOffset)
            }
        }
        return true
    }

    private func refreshSingleFilePlaylistAfterUnavailableItem(navigationOffset: Int?) {
        if let url = activePreview?.sourceURL {
            activePreview?.playlist = singleFilePreviewContext?.playlist(for: url)
        }
        if let navigationOffset { openAdjacentPreview(offset: navigationOffset) }
    }

    private func openBatchPreviewForFileCard(id: String, navigationOffset: Int? = nil) -> Bool {
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
            guard !Task.isCancelled else { return }
            if let preview = self.batchPreview(for: selectedURL) {
                self.presentPreview(preview)
            } else if let navigationOffset {
                // Uninspected browser files are candidates. If one cannot play,
                // keep the current player and advance past the failed candidate.
                if var current = self.activePreview, let batch = self.folderBatch {
                    current.playlist = self.batchPreviewPlaylist(for: current.sourceURL, in: batch)
                    self.activePreview = current
                }
                self.openAdjacentPreview(offset: navigationOffset)
            }
        }
        return true
    }

    private func openAdjacentPreview(offset: Int) {
        if let context = singleFilePreviewContext, let preview = activePreview,
           let index = context.candidates.firstIndex(of: preview.sourceURL), offset != 0 {
            let targetIndex = index + offset
            guard context.candidates.indices.contains(targetIndex) else { return }
            _ = openSingleFileSiblingPreview(url: context.candidates[targetIndex], navigationOffset: offset)
            return
        }
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
        _ = openBatchPreviewForFileCard(id: targetURL.absoluteString, navigationOffset: offset)
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
            displaySize: review.job.asset.videoTrack?.displaySize,
            playlist: singleFilePreviewContext?.playlist(for: review.source.url),
            folderAccessURL: singleFilePreviewContext?.sourceKind != .photos
                && singleFilePreviewContext?.initialURL == review.source.url
                && singleFilePreviewContext?.needsFolderAccess == true ? review.source.url.deletingLastPathComponent() : nil,
            usesNativePlayback: usesNativePlayback(for: review.job.asset)
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
            displayName: videoInfo.fileName,
            sourceURL: url,
            videoInfo: videoInfo,
            displaySize: item.asset?.videoTrack?.displaySize,
            playlist: batchPreviewPlaylist(for: url, in: batch),
            usesNativePlayback: item.asset.map(usesNativePlayback(for:)) ?? false
        )
    }

    /// The preview has two engines and the choice is not cosmetic: libVLC's iOS video output cannot
    /// decode tracks that carry a second sample description (Dolby Vision profile 8), and it does
    /// not carry HDR through, so those files go to `AVPlayer`. See
    /// `QueuePreviewPlaybackRoutePlanner` for the full rule.
    private func usesNativePlayback(for asset: TaptionVideoAsset) -> Bool {
        QueuePreviewPlaybackRoutePlanner.route(for: asset.videoTrack, container: asset.container) == .native
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
        if folderPreviewContext != nil, item.videoInfo == nil, item.isEnabled {
            return true
        }
        return item.isPreviewable
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
        if let review = currentReview ?? state.preparedEncodingReview, review.source.url == preview.sourceURL {
            cacheSingleFilePreviewItem(url: preview.sourceURL, asset: review.job.asset, info: preview.videoInfo)
        }
        dismissMiniPreview()
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
        guard !state.isBusy, !isStartingEncoding else {
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
        guard !state.isBusy, !isStartingEncoding else {
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
            applyFolderStarBudgetToCurrentBatchIfReady()

            if shouldAutoResumeBatchAfterStarEarn,
               let review = state.preparedEncodingReview,
               canStartEncodingNow {
                shouldAutoResumeBatchAfterStarEarn = false
                requestEncodingStart(
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

    func dismissSavedFolderPrompt() {
        guard savedFolderPrompt != nil else {
            return
        }
        AppLogger.info("Saved folder prompt dismissed", category: .saving)
        savedFolderPrompt = nil
    }

    func dismissMultiFileEncodingPrompt() {
        guard multiFileEncodingPrompt != nil else {
            return
        }
        AppLogger.info("Multi-file encoding prompt dismissed", category: .encoding)
        multiFileEncodingPrompt = nil
    }

    func chooseSeparateEncodingForMultiFilePrompt(prompt: MultiFileEncodingPrompt) {
        guard multiFileEncodingPrompt?.id == prompt.id else {
            return
        }
        AppLogger.info(
            "Multi-file encoding mode selected",
            category: .encoding,
            metadata: [
                "mode": "separate",
                "count": "\(prompt.fileCount)"
            ]
        )
        multiFileEncodingPrompt = nil
        hasConfirmedSeparateMultiFileEncoding = true
        startPreparedEncoding()
    }

    func chooseMergeEncodingForMultiFilePrompt(prompt: MultiFileEncodingPrompt) {
        guard multiFileEncodingPrompt?.id == prompt.id else {
            return
        }
        AppLogger.warning(
            "Multi-file merge requested but unavailable",
            category: .encoding,
            metadata: ["count": "\(prompt.fileCount)"]
        )
        multiFileEncodingPrompt = nil
        multiFileMergeUnavailableAlert = MultiFileMergeUnavailableAlert()
    }

    func dismissMultiFileMergeUnavailableAlert() {
        guard multiFileMergeUnavailableAlert != nil else {
            return
        }
        AppLogger.info("Multi-file merge unavailable alert dismissed", category: .encoding)
        multiFileMergeUnavailableAlert = nil
    }

    func openSavedFolder(prompt: SavedFolderPrompt) {
        guard savedFolderPrompt?.id == prompt.id else {
            return
        }
        savedFolderPrompt = nil
        AppLogger.info(
            "Saved folder open requested",
            category: .saving,
            metadata: [
                "folder": prompt.folderURL.lastPathComponent,
                "file": prompt.fileName
            ]
        )
        let didStartSecurityScope = prompt.folderURL.startAccessingSecurityScopedResource()
        UIApplication.shared.open(prompt.folderURL, options: [:]) { success in
            if didStartSecurityScope {
                prompt.folderURL.stopAccessingSecurityScopedResource()
            }
            if success {
                AppLogger.info(
                    "Saved folder open request accepted",
                    category: .saving,
                    metadata: ["folder": prompt.folderURL.lastPathComponent]
                )
            } else {
                AppLogger.warning(
                    "Saved folder open request failed",
                    category: .saving,
                    metadata: ["folder": prompt.folderURL.path]
                )
            }
        }
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
        invalidateEncodingStart()
        preparationOperationID = nil
        let pendingStatesToReset = resetPendingStates()
        dismissPreview()
        activeTask?.cancel()
        activeTask = nil
        stopResourceMonitoring()
        endEncodingAdSuppressionIfNeeded()
        selectionInspectionTask?.cancel()
        selectionInspectionTask = nil
        currentReview = nil
        standaloneSelectedQueueIDs.removeAll()
        activeStarCharge = nil
        shouldAutoResumeBatchAfterStarEarn = false
        cancelEncodingActivity()
        resetMultiFileEncodingDecision()
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

        Task { [store = environment.pendingSaveStore] in
            await PendingSaveCleanup.removeCapturedStates(pendingStatesToReset, from: store)
        }
    }

    func cancel() {
        if isStartingEncoding {
            invalidateEncodingStart()
            state = .cancelled
            return
        }
        guard state.canCancel else {
            AppLogger.info("Cancel ignored because state cannot cancel", category: .ui)
            return
        }
        AppLogger.warning("Cancel requested", category: .encoding)
        state = .cancelling
        stopResourceMonitoring()
        endEncodingActivity(
            statusText: "Cancelling",
            fractionCompleted: lastEncodingActivitySnapshot?.fractionCompleted ?? 0
        )
        activeTask?.cancel()
    }

    func fail(message: String) {
        fail(
            with: HomeErrorPresenter.messageError(
                title: "Import failed",
                summary: "The app could not import the selected video.",
                recovery: "Open the source again from Files or Photos.",
                diagnostic: message
            ),
            logMessage: message
        )
    }

    func fail(
        error: Error,
        summary: String = "The app could not import the selected video.",
        recovery: String = "Open the source again from Files or Photos."
    ) {
        fail(
            with: HomeErrorPresenter.error(
                title: "Import failed",
                summary: summary,
                recovery: recovery,
                error: error
            ),
            logMessage: error.localizedDescription
        )
    }

    private func fail(with error: HomeEncodingError, logMessage: String) {
        AppLogger.error(
            "Home flow failed",
            category: .app,
            metadata: ["message": logMessage]
        )
        dismissPreview()
        invalidateEncodingStart()
        preparationOperationID = nil
        activeTask?.cancel()
        activeTask = nil
        stopResourceMonitoring()
        endEncodingAdSuppressionIfNeeded()
        selectionInspectionTask?.cancel()
        selectionInspectionTask = nil
        currentReview = nil
        activeStarCharge = nil
        shouldAutoResumeBatchAfterStarEarn = false
        resetMultiFileEncodingDecision()
        endEncodingActivity(
            statusText: "Failed",
            fractionCompleted: lastEncodingActivitySnapshot?.fractionCompleted ?? 0
        )
        lastBatchFileCards = []
        folderPreviewContext = nil
        folderBatch = nil
        inspectedMediaCache.removeAll()
        state = .failed(error)
        stopSecurityScopedAccess()
    }

    private func inspectVideoReusingCache(
        at url: URL,
        preinspectedAsset: TaptionVideoAsset? = nil
    ) async throws -> (asset: TaptionVideoAsset, reusedCache: Bool) {
        try await sourceDownloader.ensureLocalVideo(at: url)
        try Task.checkCancellation()
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
        try Task.checkCancellation()
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

    /// The caller's intent for a preparation run, bundled so the stage helpers below can share it
    /// without repeating four flags in every signature.
    private struct PreparationRequest {
        let autoStartAfterPrepare: Bool
        let autoOpenPreviewAfterPrepare: Bool
        let deferEncodingPreparationUntilStart: Bool
        let allowsBusyState: Bool
    }

    /// What the inspection stage hands to the gates and to the ready stage.
    private struct PreparedEncodingJobResult {
        let job: TaptionPreparedEncodingJob
        let isPlaybackOnlyPreparation: Bool
    }

    /// The outcome of the checks that sit between job preparation and the ready state.
    private enum PreparationGateResult {
        /// Every check passed; preparation can move on to building the review.
        case proceed
        /// A check already put the UI into a terminal state; the task must stop here.
        case stopped
    }

    private func prepareEncodingFlow(
        source: HomeSelectedSource,
        autoStartAfterPrepare: Bool = false,
        autoOpenPreviewAfterPrepare: Bool = false,
        deferEncodingPreparationUntilStart: Bool = false,
        allowsBusyState: Bool = false,
        preinspectedAsset: TaptionVideoAsset? = nil
    ) {
        let request = PreparationRequest(
            autoStartAfterPrepare: autoStartAfterPrepare,
            autoOpenPreviewAfterPrepare: autoOpenPreviewAfterPrepare,
            deferEncodingPreparationUntilStart: deferEncodingPreparationUntilStart,
            allowsBusyState: allowsBusyState
        )
        guard let preparationID = beginPreparation(source: source, request: request) else {
            return
        }

        activeTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                if preparationOperationID == preparationID {
                    preparationOperationID = nil
                }
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
                let prepared = try await inspectAndBuildJob(
                    source: source,
                    request: request,
                    preinspectedAsset: preinspectedAsset,
                    preparationID: preparationID,
                    trace: trace
                )
                let gate = try runPreparationGates(
                    prepared,
                    source: source,
                    preparationID: preparationID,
                    trace: trace
                )
                guard gate == .proceed else {
                    return
                }
                finishPreparation(
                    prepared,
                    source: source,
                    request: request,
                    trace: trace
                )
            } catch is CancellationError {
                handlePreparationCancellation(
                    source: source,
                    preparationID: preparationID,
                    trace: trace
                )
            } catch TaptionVideoCoreError.insufficientStorage(let requiredBytes, let availableBytes) {
                handlePreparationStorageFailure(
                    requiredBytes: requiredBytes,
                    availableBytes: availableBytes,
                    source: source,
                    preparationID: preparationID,
                    trace: trace
                )
            } catch let error as TaptionVideoCoreError {
                handlePreparationFailure(
                    error,
                    source: source,
                    preparationID: preparationID,
                    trace: trace,
                    logMessage: "Prepare encoding failed with TaptionVideoCoreError"
                )
            } catch {
                handlePreparationFailure(
                    error,
                    source: source,
                    preparationID: preparationID,
                    trace: trace,
                    logMessage: "Prepare encoding failed"
                )
            }
        }
    }

    /// Validates that a preparation may start and puts the UI into the importing state.
    /// Returns the operation identifier the task must check against, or `nil` when another flow
    /// owns the screen and the request was rejected.
    private func beginPreparation(
        source: HomeSelectedSource,
        request: PreparationRequest
    ) -> UUID? {
        guard state.canSelectSource || request.autoStartAfterPrepare || request.allowsBusyState else {
            AppLogger.warning(
                "Prepare encoding ignored because state is busy",
                category: .encoding,
                metadata: [
                    "name": source.displayName,
                    "autoStart": "\(request.autoStartAfterPrepare)",
                    "allowsBusyState": "\(request.allowsBusyState)"
                ]
            )
            return nil
        }

        invalidateEncodingStart()
        let preparationID = UUID()
        preparationOperationID = preparationID
        AppLogger.info(
            "Prepare encoding started",
            category: .encoding,
            metadata: [
                "name": source.displayName,
                "kind": source.kind.rawValue,
                "autoStart": "\(request.autoStartAfterPrepare)"
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
        return preparationID
    }

    /// Inspects the source and builds the encoding job, which is the only stage that touches
    /// the media layer. Everything after this point works on an already prepared job.
    private func inspectAndBuildJob(
        source: HomeSelectedSource,
        request: PreparationRequest,
        preinspectedAsset: TaptionVideoAsset?,
        preparationID: UUID,
        trace: TaptionEncodingPerformanceTrace
    ) async throws -> PreparedEncodingJobResult {
        try checkPreparationOperation(preparationID)
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
        try checkPreparationOperation(preparationID)
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
        let isPlaybackOnlyPreparation = (request.autoOpenPreviewAfterPrepare || request.deferEncodingPreparationUntilStart)
            && !request.autoStartAfterPrepare
            && isPreviewableInCurrentBuild(asset: asset)
        var job: TaptionPreparedEncodingJob
        if isPlaybackOnlyPreparation {
            let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
                asset: asset,
                sourceURL: source.url,
                temporaryOutputURL: temporaryOutputURL,
                outputPolicy: selectedOutput.outputPolicy(for: asset),
                preferredMode: .automatic,
                savePolicy: savePolicy
            )
            job = TaptionPreparedEncodingJob(
                asset: asset,
                plan: plan,
                routeSelection: TaptionCodecRoutePlanner.selectRoute(
                    for: asset,
                    outputCodec: selectedOutput.videoCodec,
                    requestedMode: .automatic
                ),
                storageRequirement: TaptionStorageRequirement(
                    estimatedOutputBytes: plan.estimatedOutputBytes ?? 0,
                    requiredWorkingBytes: 0
                )
            )
            trace.mark("playback_prepared_storage_deferred")
        } else {
            job = try await core.prepareSingleAssetJob(
                asset: asset,
                sourceURL: source.url,
                temporaryOutputURL: temporaryOutputURL,
                outputPolicy: selectedOutput.outputPolicy(for: asset),
                preferredMode: .automatic,
                savePolicy: savePolicy
            )
        }
        try checkPreparationOperation(preparationID)
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
        return PreparedEncodingJobResult(
            job: job,
            isPlaybackOnlyPreparation: isPlaybackOnlyPreparation
        )
    }

    /// Runs the storage check UI and both blocking checks. A `.stopped` result means the caller
    /// must return immediately: the terminal state has already been published.
    private func runPreparationGates(
        _ prepared: PreparedEncodingJobResult,
        source: HomeSelectedSource,
        preparationID: UUID,
        trace: TaptionEncodingPerformanceTrace
    ) throws -> PreparationGateResult {
        let job = prepared.job
        let isPlaybackOnlyPreparation = prepared.isPlaybackOnlyPreparation
        try checkPreparationOperation(preparationID)
        if !isPlaybackOnlyPreparation {
            markBatchItem(
                source.url,
                statusText: "Checking Storage",
                detailText: "Confirming temporary and final output space.",
                progress: nil,
                isActive: true
            )
            state = .storageChecking(source)
            trace.mark(
                "storage_checked",
                metadata: [
                    "requiredBytes": "\(job.storageRequirement.requiredWorkingBytes)",
                    "availableBytes": job.storageRequirement.availableBytes.map(String.init) ?? "unknown",
                    "hasEnoughSpace": "\(job.storageRequirement.hasEnoughSpace)"
                ]
            )
        }

        let canEncodeSelectedOutput = job.routeSelection.isEncodableNow && selectedOutput.isImplementedNow
        guard isPlaybackOnlyPreparation || canEncodeSelectedOutput else {
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
                return .stopped
            }
            state = .failed(HomeEncodingError(
                title: "Encoding blocked",
                message: detail
            ))
            trace.finish("blocked", metadata: ["reason": detail])
            activeTask = nil
            stopSecurityScopedAccess()
            requestSessionEndAd(reason: .failedEncoding)
            return .stopped
        }

        guard isPlaybackOnlyPreparation || job.storageRequirement.hasEnoughSpace else {
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
                return .stopped
            }
            state = .storageBlocked(StorageIssue(
                requiredBytes: job.storageRequirement.requiredWorkingBytes,
                availableBytes: job.storageRequirement.availableBytes,
                message: storageMessage
            ))
            trace.finish("storage_blocked", metadata: ["reason": storageMessage])
            activeTask = nil
            return .stopped
        }

        return .proceed
    }

    /// Publishes the review and hands control to the start or preview step.
    private func finishPreparation(
        _ prepared: PreparedEncodingJobResult,
        source: HomeSelectedSource,
        request: PreparationRequest,
        trace: TaptionEncodingPerformanceTrace
    ) {
        let job = prepared.job
        let review = PreparedEncodingReview(
            source: source,
            job: job,
            videoInfo: makeLoadedVideoInfo(source: source, job: job),
            folderQueue: folderBatch?.snapshot(currentFileName: source.displayName),
            requiresEncodingPreparation: prepared.isPlaybackOnlyPreparation
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
        state = .readyToStart(review)
        if request.autoStartAfterPrepare {
            trace.finish("ready_auto_start")
            requestEncodingStart(
                for: review,
                autoResumeAfterStarEarn: true
            )
        } else {
            if let batch = folderBatch {
                folderBatch = applyFolderStarBudget(to: batch)
            }
            state = .readyToStart(review)
            trace.finish("ready")
            if request.autoOpenPreviewAfterPrepare {
                openPreviewAfterImportIfAvailable(for: review)
            }
        }
    }

    private func handlePreparationCancellation(
        source: HomeSelectedSource,
        preparationID: UUID,
        trace: TaptionEncodingPerformanceTrace
    ) {
        guard preparationOperationID == preparationID else {
            trace.finish("superseded")
            return
        }
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
    }

    private func handlePreparationStorageFailure(
        requiredBytes: Int64,
        availableBytes: Int64?,
        source: HomeSelectedSource,
        preparationID: UUID,
        trace: TaptionEncodingPerformanceTrace
    ) {
        guard preparationOperationID == preparationID else {
            trace.finish("superseded")
            return
        }
        let storageMessage = storageWarningMessage(
            requiredBytes: requiredBytes,
            availableBytes: availableBytes
        )
        logCodecBenchmarkProbeTerminalIfNeeded(
            status: "prepare_failed",
            sourceName: source.displayName,
            errorMessage: storageMessage
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
    }

    /// Shared by the typed and the untyped failure paths, which differed only in their log line.
    private func handlePreparationFailure(
        _ error: Error,
        source: HomeSelectedSource,
        preparationID: UUID,
        trace: TaptionEncodingPerformanceTrace,
        logMessage: String
    ) {
        guard preparationOperationID == preparationID else {
            trace.finish("superseded")
            return
        }
        logCodecBenchmarkProbeTerminalIfNeeded(
            status: "prepare_failed",
            sourceName: source.displayName,
            errorMessage: error.localizedDescription
        )
        AppLogger.error(
            logMessage,
            category: .encoding,
            metadata: [
                "name": source.displayName,
                "error": error.localizedDescription
            ]
        )
        let failure = HomeErrorPresenter.error(
            title: "Encoding failed",
            summary: "The app could not prepare this video for encoding.",
            recovery: "Choose another source or output setting, then try again.",
            error: error
        )
        let cardDetail = HomeErrorPresenter.cardDetail(
            summary: "The app could not prepare this video for encoding.",
            recovery: "Choose another source or output setting, then try again.",
            error: error
        )
        markBatchItem(
            source.url,
            statusText: "Failed",
            detailText: cardDetail,
            progress: nil,
            isActive: false
        )
        if handleFolderItemFailure(source: source, errorMessage: cardDetail) {
            trace.finish("failed", metadata: ["error": error.localizedDescription])
            return
        }
        state = .failed(failure)
        activeTask = nil
        stopSecurityScopedAccess()
        requestSessionEndAd(reason: .failedEncoding)
        trace.finish("failed", metadata: ["error": error.localizedDescription])
    }

    private func checkPreparationOperation(_ operationID: UUID) throws {
        try Task.checkCancellation()
        guard preparationOperationID == operationID else { throw CancellationError() }
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

        let optimizationProfile = encodingOptimizationProfile(for: review)
        AppLogger.info(
            "Encoding task started",
            category: .encoding,
            metadata: [
                "name": review.source.displayName,
                "plan": review.job.plan.id.uuidString,
                "optimizationProfile": optimizationProfile.rawValue
            ]
        )
        activeTask?.cancel()
        stopResourceMonitoring()
        currentReview = review
        deferredBatteryStopReason = nil
        beginEncodingAdSuppressionIfNeeded()
        let trace = TaptionEncodingPerformanceTrace(
            name: "home_encode_flow",
            category: .encoding,
            metadata: [
                "name": review.source.displayName,
                "plan": review.job.plan.id.uuidString,
                "route": review.job.plan.codecRoute?.displayName ?? "unknown",
                "optimizationProfile": optimizationProfile.rawValue
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
        startResourceMonitoring(sampleIntervalNanoseconds: optimizationProfile.resourceSampleIntervalNanoseconds)

        activeTask = Task(priority: taskPriority(for: optimizationProfile)) { [weak self] in
            guard let self else {
                return
            }

            let core = TaptionVideoCore(services: environment.videoCoreServices)
            var retainedBackgroundPlanID: UUID?
            do {
                var lastLoggedProgressBucket = -1
                let firstProgressLock = NSLock()
                var didMarkFirstProgress = false
                let result = try await core.encodePreparedJob(
                    review.job,
                    backgroundTaskCompletionPolicy: .callerManaged
                ) { [weak self] progress in
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
                retainedBackgroundPlanID = result.planID
                activeBackgroundSavePlanIDs.insert(result.planID)

                try Task.checkCancellation()
                trace.mark(
                    "encode_completed",
                    metadata: [
                        "mode": result.usedMode.rawValue,
                        "backend": result.usedBackend.rawValue,
                        "optimizationProfile": optimizationProfile.rawValue
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
                        "temporary": result.temporaryOutputURL.lastPathComponent,
                        "temporaryBytes": fileSizeInBytes(at: result.temporaryOutputURL).map(String.init) ?? "unknown",
                        "optimizationProfile": optimizationProfile.rawValue
                    ]
                )
                logCodecBenchmarkProbeCompletionIfNeeded(
                    sourceName: review.source.displayName,
                    result: result,
                    optimizationProfile: optimizationProfile
                )
                clearActiveStarCharge(for: review.source)
                let pendingJob = PendingSaveJob(
                    sourceName: review.source.displayName,
                    state: restorablePendingState
                )
                stopResourceMonitoring()
                endEncodingAdSuppressionIfNeeded()
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
                let didStartImmediateSave = requestSaveDestinationIfNeeded(for: pendingJob)
                if !didStartImmediateSave {
                    await completeBackgroundSaveLease(planID: result.planID)
                }
                retainedBackgroundPlanID = nil
            } catch is CancellationError {
                if let retainedBackgroundPlanID {
                    await completeBackgroundSaveLease(planID: retainedBackgroundPlanID)
                }
                AppLogger.warning(
                    "Encoding task cancelled",
                    category: .encoding,
                    metadata: ["name": review.source.displayName]
                )
                stopResourceMonitoring()
                endEncodingAdSuppressionIfNeeded()
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
                if let retainedBackgroundPlanID {
                    await completeBackgroundSaveLease(planID: retainedBackgroundPlanID)
                }
                logCodecBenchmarkProbeTerminalIfNeeded(
                    status: "encode_failed",
                    sourceName: review.source.displayName,
                    errorMessage: error.localizedDescription
                )
                AppLogger.error(
                    "Encoding task failed with TaptionVideoCoreError",
                    category: .encoding,
                    metadata: [
                        "name": review.source.displayName,
                        "error": error.localizedDescription
                    ]
                )
                stopResourceMonitoring()
                endEncodingAdSuppressionIfNeeded()
                refundActiveStarChargeIfNeeded(for: review.source)
                let failure = HomeErrorPresenter.error(
                    title: "Encoding failed",
                    summary: "The app could not finish encoding this video.",
                    recovery: "Keep the app open and try again. If it repeats, choose another source or output setting.",
                    error: error
                )
                let cardDetail = HomeErrorPresenter.cardDetail(
                    summary: "The app could not finish encoding this video.",
                    recovery: "Keep the app open and try again. If it repeats, choose another source or output setting.",
                    error: error
                )
                markBatchItem(
                    review.source.url,
                    videoInfo: review.videoInfo,
                    statusText: "Failed",
                    detailText: cardDetail,
                    progress: nil,
                    isActive: false
                )
                if handleFolderItemFailure(source: review.source, errorMessage: cardDetail) {
                    trace.finish("failed", metadata: ["error": error.localizedDescription])
                    return
                }
                state = .failed(failure)
                endEncodingActivity(statusText: "Failed", fractionCompleted: lastEncodingActivitySnapshot?.fractionCompleted ?? 0)
                activeTask = nil
                stopSecurityScopedAccess()
                requestSessionEndAd(reason: .failedEncoding)
                trace.finish("failed", metadata: ["error": error.localizedDescription])
            } catch {
                if let retainedBackgroundPlanID {
                    await completeBackgroundSaveLease(planID: retainedBackgroundPlanID)
                }
                logCodecBenchmarkProbeTerminalIfNeeded(
                    status: "encode_failed",
                    sourceName: review.source.displayName,
                    errorMessage: error.localizedDescription
                )
                AppLogger.error(
                    "Encoding task failed",
                    category: .encoding,
                    metadata: [
                        "name": review.source.displayName,
                        "error": error.localizedDescription
                    ]
                )
                stopResourceMonitoring()
                endEncodingAdSuppressionIfNeeded()
                refundActiveStarChargeIfNeeded(for: review.source)
                let failure = HomeErrorPresenter.error(
                    title: "Encoding failed",
                    summary: "The app could not finish encoding this video.",
                    recovery: "Keep the app open and try again. If it repeats, choose another source or output setting.",
                    error: error
                )
                let cardDetail = HomeErrorPresenter.cardDetail(
                    summary: "The app could not finish encoding this video.",
                    recovery: "Keep the app open and try again. If it repeats, choose another source or output setting.",
                    error: error
                )
                markBatchItem(
                    review.source.url,
                    videoInfo: review.videoInfo,
                    statusText: "Failed",
                    detailText: cardDetail,
                    progress: nil,
                    isActive: false
                )
                if handleFolderItemFailure(source: review.source, errorMessage: cardDetail) {
                    trace.finish("failed", metadata: ["error": error.localizedDescription])
                    return
                }
                state = .failed(failure)
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
                await completeBackgroundSaveLease(planID: workingJob.state.planID)
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
                logCodecBenchmarkProbeTerminalIfNeeded(
                    status: "save_failed",
                    sourceName: workingJob.sourceName,
                    errorMessage: error.localizedDescription
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
                await completeBackgroundSaveLease(planID: workingJob.state.planID)
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

    private func beginEncodingAdSuppressionIfNeeded() {
        guard !isEncodingAdSuppressed else {
            return
        }
        isEncodingAdSuppressed = true
        AdMobBootstrapper.beginFullScreenAdSuppression(reason: "encoding")
    }

    private func endEncodingAdSuppressionIfNeeded() {
        guard isEncodingAdSuppressed else {
            return
        }
        isEncodingAdSuppressed = false
        AdMobBootstrapper.endFullScreenAdSuppression(reason: "encoding")
    }

    @discardableResult
    private func requestSaveDestinationIfNeeded(for job: PendingSaveJob) -> Bool {
        let routedJob = applySelectedFolderBatchDestination(to: job)
        #if DEBUG
        if debugBenchmarkAllowsFreeEncoding, debugCodecProbeID != nil {
            let internalJob = reroutePendingSaveToInternalOutput(
                routedJob,
                reason: "debug codec probe"
            )
            persistPendingSaveState(internalJob.state)
            updatePendingSaveJob(internalJob)
            state = .pendingSave(internalJob)
            activeTask = nil
            AppLogger.info(
                "Debug codec probe output save started",
                category: .saving,
                metadata: [
                    "probeID": debugCodecProbeID ?? "none",
                    "source": internalJob.sourceName,
                    "final": internalJob.state.finalOutputURL?.lastPathComponent ?? "none"
                ]
            )
            savePendingJob(internalJob)
            return !internalJob.state.requiresRewardedAd
        }
        #endif
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
                return !internalJob.state.requiresRewardedAd
            }
            savePendingJob(routedJob)
            return !routedJob.state.requiresRewardedAd
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
        return false
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
        let completedFileSize = fileSizeInBytes(at: metadataURL) ?? fileSizeInBytes(at: completedOutputURL)
        let completedSaveDetail = completedSaveDetailMessage(
            savedURL: completedOutputURL,
            fileSizeBytes: completedFileSize
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
                "file": completedOutputURL.lastPathComponent,
                "size": fileSizeText(completedFileSize)
            ]
        )
        logCodecBenchmarkProbeTerminalIfNeeded(
            status: "saved",
            sourceName: job.sourceName,
            outputURL: completedOutputURL
        )
        markCurrentSaveItem(
            statusText: "Save Complete",
            detailText: nil,
            progress: completedProgressSnapshot(label: "Save Complete"),
            isActive: false
        )
        await completeBackgroundSaveLease(planID: job.state.planID)

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
            fileSizeBytes: completedFileSize
        ))
        savedFolderPrompt = makeSavedFolderPrompt(
            fileName: displayName,
            savedURL: completedOutputURL,
            saveDestination: job.state.saveDestination
        )
        endEncodingActivity(statusText: "Save Complete", fractionCompleted: 1)
        stopSecurityScopedAccess()
        activeTask = nil
    }

    private func completeBackgroundSaveLease(planID: UUID) async {
        guard activeBackgroundSavePlanIDs.remove(planID) != nil else {
            return
        }
        await environment.backgroundCoordinator.endBackgroundEncoding(planID: planID)
        AppLogger.info(
            "Background encoding lease completed after save handling",
            category: .encoding,
            metadata: ["plan": planID.uuidString]
        )
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
                state = .failed(HomeErrorPresenter.error(
                    title: "Folder failed",
                    summary: "The app could not prepare this folder queue.",
                    recovery: "Choose the folder again from Files, then retry the queue.",
                    error: error
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
            displayName: sourceDisplayName(for: url),
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
                detailText: HomeErrorPresenter.cardDetail(
                    summary: "This video could not be inspected.",
                    recovery: "Keep it in the queue for preview if available, or choose another source.",
                    error: error
                ),
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
            displayName: sourceDisplayName(for: url),
            url: url
        )
        prepareEncodingFlow(
            source: source,
            autoStartAfterPrepare: autoStartAfterPrepare,
            autoOpenPreviewAfterPrepare: false,
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
        let completedFolderPrompt = makeSavedFolderPrompt(for: batch)

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
        resetMultiFileEncodingDecision()
        activeTask = nil
        stopResourceMonitoring()
        endEncodingAdSuppressionIfNeeded()
        if let nextPendingJob = pendingSaveQueue.first {
            state = .pendingSave(nextPendingJob)
        } else {
            state = .completed(SavedOutput(
                displayName: batch.stopMessage == nil ? "Folder complete" : "Folder stopped",
                destinationDescription: batch.folderName,
                detailOverride: folderCompletionMessage(for: batch)
            ))
            savedFolderPrompt = completedFolderPrompt
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

    private func requestEncodingStart(
        for review: PreparedEncodingReview,
        autoResumeAfterStarEarn: Bool
    ) {
        guard encodingStartOperationID == nil,
              state.preparedEncodingReview?.job.plan.id == review.job.plan.id else { return }
        let operationID = UUID()
        encodingStartOperationID = operationID
        isStartingEncoding = true
        encodingStartTask = Task { @MainActor [weak self] in
            await self?.performEncodingStart(
                for: review,
                autoResumeAfterStarEarn: autoResumeAfterStarEarn,
                operationID: operationID
            )
        }
    }

    private func invalidateEncodingStart() {
        encodingStartOperationID = nil
        isStartingEncoding = false
        encodingStartTask?.cancel()
        encodingStartTask = nil
    }

    private func finishEncodingStart(operationID: UUID) {
        guard encodingStartOperationID == operationID else { return }
        encodingStartOperationID = nil
        encodingStartTask = nil
        isStartingEncoding = false
    }

    private func isCurrentEncodingStart(_ operationID: UUID, review: PreparedEncodingReview) -> Bool {
        !Task.isCancelled
            && encodingStartOperationID == operationID
            && state.preparedEncodingReview?.job.plan.id == review.job.plan.id
    }

    private func refundAbandonedEncodingStart(for review: PreparedEncodingReview) async {
        // The debit may have committed while Reset/source replacement cancelled
        // its caller. Compensate in a fresh, non-cancelled task; never clear the
        // active charge or encoder handle belonging to a newer operation.
        let wallet = environment.starWalletStore
        let refund = Task {
            _ = try await wallet.refundStar(source: review.source.displayName)
            return await wallet.currentSnapshot()
        }
        do {
            starWalletSnapshot = try await refund.value
            AppLogger.info("Abandoned encoding start Star refunded", category: .encoding,
                           metadata: ["source": review.source.displayName])
        } catch {
            AppLogger.error("Abandoned encoding start Star refund failed", category: .encoding,
                            metadata: ["source": review.source.displayName,
                                       "error": error.localizedDescription])
        }
    }

    private func performEncodingStart(
        for review: PreparedEncodingReview,
        autoResumeAfterStarEarn: Bool,
        operationID: UUID
    ) async {
        defer { finishEncodingStart(operationID: operationID) }
        guard isCurrentEncodingStart(operationID, review: review) else { return }
        if review.requiresEncodingPreparation {
            finishEncodingStart(operationID: operationID)
            prepareEncodingFlow(
                source: review.source,
                autoStartAfterPrepare: true,
                allowsBusyState: true,
                preinspectedAsset: review.job.asset
            )
            return
        }
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

        #if DEBUG
        if debugBenchmarkAllowsFreeEncoding {
            AppLogger.info(
                "Debug benchmark encoding start bypassed Star charge",
                category: .encoding,
                metadata: [
                    "name": review.source.displayName,
                    "plan": review.job.plan.id.uuidString,
                    "probeID": debugCodecProbeID ?? "none"
                ]
            )
            shouldAutoResumeBatchAfterStarEarn = false
            startEncoding(
                review: reviewWithSaveGate(.none, for: review),
                allowsBusyState: true
            )
            return
        }
        #endif

        let snapshot = await environment.starWalletStore.currentSnapshot()
        guard isCurrentEncodingStart(operationID, review: review) else { return }
        starWalletSnapshot = snapshot
        let requiredStarCount = estimatedStartStarCost(for: review)
        guard startStarShortage(
            required: requiredStarCount,
            available: starWalletSnapshot.balance
        ) == 0 else {
            blockEncodingStartForInsufficientStars(
                review: review,
                requiredStarCount: requiredStarCount,
                availableStarCount: starWalletSnapshot.balance
            )
            return
        }

        do {
            _ = try await environment.starWalletStore.consumeStar(
                source: review.source.displayName
            )
            guard isCurrentEncodingStart(operationID, review: review) else {
                await refundAbandonedEncodingStart(for: review)
                return
            }
            let chargedSnapshot = await environment.starWalletStore.currentSnapshot()
            guard isCurrentEncodingStart(operationID, review: review) else {
                await refundAbandonedEncodingStart(for: review)
                return
            }
            starWalletSnapshot = chargedSnapshot
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
            guard isCurrentEncodingStart(operationID, review: review) else { return }
            if case .insufficientStars = error {
                let snapshot = await environment.starWalletStore.currentSnapshot()
                guard isCurrentEncodingStart(operationID, review: review) else { return }
                starWalletSnapshot = snapshot
                blockEncodingStartForInsufficientStars(
                    review: review,
                    requiredStarCount: requiredStarCount,
                    availableStarCount: starWalletSnapshot.balance
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
            state = .failed(HomeErrorPresenter.error(
                title: "Star error",
                summary: "The app could not reserve a Star before encoding.",
                recovery: "Refresh Stars or watch an ad, then start again.",
                error: error
            ))
        } catch {
            guard isCurrentEncodingStart(operationID, review: review) else { return }
            AppLogger.error(
                "Star debit failed before encoding start",
                category: .encoding,
                metadata: [
                    "name": review.source.displayName,
                    "error": error.localizedDescription
                ]
            )
            state = .failed(HomeErrorPresenter.error(
                title: "Star error",
                summary: "The app could not reserve a Star before encoding.",
                recovery: "Refresh Stars or watch an ad, then start again.",
                error: error
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

    private func startResourceMonitoring(sampleIntervalNanoseconds: UInt64) {
        stopResourceMonitoring()
        let initialSample = resourceMonitor.sample()
        let decoratedInitialSample = runtimeWarningResourceUsage(
            initialSample,
            estimatedRemainingTime: currentEncodingEstimatedRemainingTime
        )
        latestResourceUsage = decoratedInitialSample
        updateCurrentEncodingProgressResourceUsage(decoratedInitialSample)
        let interval = max(sampleIntervalNanoseconds, 250_000_000)

        resourceMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled,
                      let self else {
                    return
                }
                let sample = self.resourceMonitor.sample()
                let decoratedSample = self.runtimeWarningResourceUsage(
                    sample,
                    estimatedRemainingTime: self.currentEncodingEstimatedRemainingTime
                )
                self.latestResourceUsage = decoratedSample
                self.updateCurrentEncodingProgressResourceUsage(decoratedSample)
            }
        }
    }

    private func encodingOptimizationProfile(for review: PreparedEncodingReview) -> TaptionEncodingOptimizationProfile {
        review.job.plan.outputPolicy.advancedOptions.optimizationProfile
            ?? selectedOutput.optimizationProfile
    }

    private func taskPriority(for profile: TaptionEncodingOptimizationProfile) -> TaskPriority {
        switch profile {
        case .batterySaver:
            return .utility
        case .balanced:
            return .userInitiated
        case .performance:
            return .high
        }
    }

    private func logCodecBenchmarkProbeCompletionIfNeeded(
        sourceName: String,
        result: TaptionEncodingResult,
        optimizationProfile: TaptionEncodingOptimizationProfile
    ) {
        #if DEBUG
        guard let probeID = debugCodecProbeID else {
            return
        }
        AppLogger.info(
            "Codec benchmark probe completed",
            category: .encoding,
            metadata: [
                "probeID": probeID,
                "source": sourceName,
                "plan": result.planID.uuidString,
                "mode": result.usedMode.rawValue,
                "backend": result.usedBackend.rawValue,
                "temporary": result.temporaryOutputURL.lastPathComponent,
                "temporaryBytes": fileSizeInBytes(at: result.temporaryOutputURL).map(String.init) ?? "unknown",
                "optimizationProfile": optimizationProfile.rawValue
            ]
        )
        #endif
    }

    private func logCodecBenchmarkProbeTerminalIfNeeded(
        status: String,
        sourceName: String,
        errorMessage: String? = nil,
        outputURL: URL? = nil
    ) {
        #if DEBUG
        guard let probeID = debugCodecProbeID else {
            return
        }
        AppLogger.info(
            "Codec benchmark probe terminal",
            category: .encoding,
            metadata: [
                "probeID": probeID,
                "source": sourceName,
                "status": status,
                "error": errorMessage ?? "none",
                "output": outputURL?.lastPathComponent ?? "none",
                "outputBytes": outputURL.flatMap(fileSizeInBytes(at:)).map(String.init) ?? "unknown"
            ]
        )
        #endif
    }

    #if DEBUG
    private var debugCodecProbeID: String? {
        ProcessInfo.processInfo.environment["TAPTION_CODEC_PROBE_ID"]
    }

    private var debugBenchmarkAllowsFreeEncoding: Bool {
        ProcessInfo.processInfo.environment["TAPTION_DEBUG_BENCHMARK_ALLOW_FREE_ENCODING"] == "1"
    }
    #endif

    private func stopResourceMonitoring() {
        resourceMonitorTask?.cancel()
        resourceMonitorTask = nil
        latestResourceUsage = nil
    }

    private func updateCurrentEncodingProgressResourceUsage(_ snapshot: EncodingResourceUsageSnapshot) {
        guard case .encoding(var progress) = state else {
            return
        }
        let decoratedSnapshot = runtimeWarningResourceUsage(
            snapshot,
            estimatedRemainingTime: progress.estimatedRemainingTime
        )
        latestResourceUsage = decoratedSnapshot
        progress.resourceUsage = decoratedSnapshot
        state = .encoding(progress)
    }

    private var currentEncodingEstimatedRemainingTime: TimeInterval? {
        guard case .encoding(let progress) = state else {
            return nil
        }
        return progress.estimatedRemainingTime
    }

    private func runtimeWarningResourceUsage(
        _ snapshot: EncodingResourceUsageSnapshot,
        estimatedRemainingTime: TimeInterval?
    ) -> EncodingResourceUsageSnapshot {
        let settings = batterySettingsProvider()
        var updatedSnapshot = snapshot
        updatedSnapshot.runtimeWarnings = EncodingRuntimeWarningEvaluator.warnings(
            resourceUsage: snapshot,
            powerSnapshot: runtimePowerSnapshot,
            batteryLimitPercent: settings.batteryLimitPercent,
            estimatedRemainingTime: estimatedRemainingTime,
            optimizationProfile: settings.optimizationProfile
        )
        return updatedSnapshot
    }

    private var runtimePowerSnapshot: EncodingRuntimePowerSnapshot {
        let snapshot = batteryPowerMonitor.currentSnapshot
        return EncodingRuntimePowerSnapshot(
            batteryPercent: snapshot.batteryPercent,
            isPowerConnected: snapshot.isPowerConnected,
            isPowerStateKnown: snapshot.isPowerStateKnown
        )
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
            outputSummary: review.videoInfo.outputSummary,
            resourceUsage: latestResourceUsage.map {
                runtimeWarningResourceUsage($0, estimatedRemainingTime: nil)
            }
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
                outputSummary: currentReview?.videoInfo.outputSummary,
                resourceUsage: latestResourceUsage.map {
                    runtimeWarningResourceUsage($0, estimatedRemainingTime: progress.estimatedRemainingTime)
                }
            )
        }

        return EncodingProgressSnapshot(
            stage: progress.stage,
            fractionCompleted: progress.fractionCompleted,
            elapsedTime: progress.elapsedTime,
            estimatedRemainingTime: progress.estimatedRemainingTime,
            backendLabel: currentReview?.videoInfo.codecPathTitle ?? "Automatic Codec Path",
            outputSummary: currentReview?.videoInfo.outputSummary,
            resourceUsage: latestResourceUsage.map {
                runtimeWarningResourceUsage($0, estimatedRemainingTime: progress.estimatedRemainingTime)
            }
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
            item.isRouteEncodable = isEnabled
            item.isStarLimited = false
        }
        if let isPreviewable {
            item.isPreviewable = isPreviewable
        }
        if isActive {
            for otherURL in batch.fileURLs where otherURL != url {
                guard var otherItem = batch.itemStates[otherURL],
                      otherItem.isActive else {
                    continue
                }
                otherItem.isActive = false
                if otherItem.statusText == otherItem.videoInfo?.readinessStatusText {
                    otherItem.statusText = otherItem.isEnabled ? "Queued" : otherItem.statusText
                    otherItem.detailText = otherItem.isEnabled
                        ? folderQueuedDetailText(for: otherItem)
                        : otherItem.detailText
                }
                batch.itemStates[otherURL] = otherItem
            }
            batch.selectedURL = url
        }
        batch.itemStates[url] = item
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

    private func queueURL(for id: String, in batch: FolderEncodingBatch) -> URL? {
        batch.fileURLs.first { url in
            url.absoluteString == id || url.lastPathComponent == id
        }
    }

    private func queueCurrentIndex(for batch: FolderEncodingBatch) -> Int {
        if let reviewURL = currentReview?.source.url,
           let reviewIndex = batch.fileURLs.firstIndex(of: reviewURL),
           let item = batch.itemStates[reviewURL],
           item.isEnabled,
           !item.isStarLimited {
            return reviewIndex
        }
        if let selectedURL = batch.selectedURL,
           let selectedIndex = batch.fileURLs.firstIndex(of: selectedURL),
           let item = batch.itemStates[selectedURL],
           item.isEnabled,
           !item.isStarLimited {
            return selectedIndex
        }
        return batch.fileURLs.firstIndex { url in
            let item = batch.itemStates[url]
            return item?.isEnabled == true && item?.isStarLimited != true
        } ?? 0
    }

    private func firstQueueIndex(for batch: FolderEncodingBatch) -> Int {
        batch.fileURLs.firstIndex { url in
            let item = batch.itemStates[url]
            return item?.isEnabled == true && item?.isStarLimited != true
        } ?? 0
    }

    private func standaloneQueueMatches(id: String) -> Bool {
        guard let review = currentReview ?? state.preparedEncodingReview else {
            return false
        }
        return id == review.source.displayName
            || id == review.source.url.absoluteString
            || id == review.source.id.uuidString
    }

    private func deleteQueueURLs(_ urls: [URL]) {
        guard var batch = folderBatch else {
            return
        }
        let deletingURLs = Set(urls)
        guard !deletingURLs.isEmpty else {
            return
        }

        AppLogger.info(
            "Queue items deleted",
            category: .ui,
            metadata: [
                "count": "\(deletingURLs.count)",
                "names": batch.fileURLs
                    .filter { deletingURLs.contains($0) }
                    .map(\.lastPathComponent)
                    .joined(separator: "|")
            ]
        )

        let removedActivePreview = activePreview.map { deletingURLs.contains($0.sourceURL) } ?? false
        batch.fileURLs.removeAll { deletingURLs.contains($0) }
        singleFilePreviewContext?.queuedURLs.removeAll { deletingURLs.contains($0) }
        for url in deletingURLs {
            batch.itemStates.removeValue(forKey: url)
        }
        batch.multiSelectedURLs.subtract(deletingURLs)

        if let selectedURL = batch.selectedURL,
           deletingURLs.contains(selectedURL) {
            batch.selectedURL = queueSelectableURL(in: batch)
        }

        guard !batch.fileURLs.isEmpty else {
            dismissPreview()
            activeTask?.cancel()
            activeTask = nil
            selectionInspectionTask?.cancel()
            selectionInspectionTask = nil
            previewInspectionTask?.cancel()
            previewInspectionTask = nil
            currentReview = nil
            folderBatch = nil
            state = .idle
            stopSecurityScopedAccess()
            objectWillChange.send()
            return
        }

        batch = applyFolderStarBudget(to: batch)
        batch.currentIndex = queueCurrentIndex(for: batch)
        folderBatch = batch
        if removedActivePreview {
            dismissPreview()
        }

        guard let currentURL = batch.currentFileURL,
              currentReview?.source.url != currentURL else {
            objectWillChange.send()
            return
        }

        dismissPreview()
        activeTask?.cancel()
        activeTask = nil
        currentReview = nil
        prepareCurrentFolderItem(autoStartAfterPrepare: false, allowsBusyState: true)
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

    private func supportedVideoFileURLs(from urls: [URL]) -> [URL] {
        MediaFileIdentity.uniqueURLs(urls)
            .filter {
                !selectedURLIsDirectory($0)
                    && SupportedVideoFileExtensions.contains($0.pathExtension)
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
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

        guard !Self.currentBuildPreviewBlockedVideoCodecs.contains(videoTrack.codec) else {
            return false
        }

        // Apple's native player handles HEVC Alpha composition in QuickTime files.
        // This preview route does not change the encoding route or alpha policy.
        if videoTrack.codec == .hevcWithAlpha {
            return asset.container == .mov
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
            item.isRouteEncodable = info.isRouteEncodable
            item.isStarLimited = false
            item.isPreviewable = isPreviewableInCurrentBuild(asset: asset)
            item.statusText = info.isRouteEncodable ? "Queued" : info.readinessStatusText
            item.detailText = info.isRouteEncodable ? "\(routeSelection.displayTitle). Ready to encode." : info.readinessDetailText
            item.progress = nil
            item.isActive = false
            batch.itemStates[url] = item
        }

        batch.selectedURL = queueSelectableURL(in: batch)
        folderBatch = applyFolderStarBudget(to: batch)
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
            isMultiSelected: standaloneQueueIsSelected(source),
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
        isMultiSelected: Bool = false,
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
            isMultiSelected: isMultiSelected,
            isEnabled: isEnabled,
            isPreviewable: isPreviewable
        )
    }

    private func standaloneQueueIsSelected(_ source: HomeSelectedSource) -> Bool {
        standaloneSelectedQueueIDs.contains(source.displayName)
            || standaloneSelectedQueueIDs.contains(source.url.absoluteString)
            || standaloneSelectedQueueIDs.contains(source.id.uuidString)
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
        LoadedVideoInfoFactory.make(source: source, asset: asset, outputName: outputName,
                                    selectedOutput: selectedOutput, routeSelection: routeSelection)
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

    private func fileSizeText(_ bytes: Int64?) -> String { MediaDisplayFormatting.byteCount(bytes) }

    private func formattedByteCount(_ bytes: Int64) -> String { MediaDisplayFormatting.byteCount(bytes) }

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

    private func folderContents(in folderURL: URL) throws -> FolderContentsScanResult {
        let result = try FolderContentsScanner.scan(folderURL: folderURL)
        AppLogger.info(
            "Folder contents scanned",
            category: .folderImport,
            metadata: [
                "folder": folderURL.lastPathComponent,
                "videoCount": "\(result.videoURLs.count)",
                "folderCount": "\(result.folderURLs.count)",
                "skippedNonVideoFileCount": "\(result.skippedNonVideoFileCount)"
            ]
        )
        return result
    }

    private func videoFileURLs(in folderURL: URL) throws -> [URL] {
        try folderContents(in: folderURL).videoURLs
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
            let contents = try folderContents(in: currentURL)
            let folders = contents.folderURLs
            let files = contents.videoURLs
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
            let rootDisplayName = importBrowserRootDisplayName ?? rootURL.lastPathComponent
            importBrowserContext = HomeImportBrowserContext(
                id: "\(mode.rawValue)-\(currentURL.path)-\(importBrowserSelectedFileURLs.count)",
                mode: mode,
                rootFolderName: rootDisplayName,
                currentFolderName: currentURL.lastPathComponent,
                pathText: relativeImportBrowserPath(
                    root: rootURL,
                    current: currentURL,
                    rootDisplayName: rootDisplayName
                ),
                folderCount: folders.count,
                fileCount: files.count,
                selectedFileCount: importBrowserSelectedFileURLs.count,
                canGoBack: true,
                canGoUp: true
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
            let rootDisplayName = importBrowserRootDisplayName ?? rootURL.lastPathComponent
            importBrowserContext = HomeImportBrowserContext(
                id: "\(mode.rawValue)-\(currentURL.path)-error",
                mode: mode,
                rootFolderName: rootDisplayName,
                currentFolderName: currentURL.lastPathComponent,
                pathText: relativeImportBrowserPath(
                    root: rootURL,
                    current: currentURL,
                    rootDisplayName: rootDisplayName
                ),
                folderCount: 0,
                fileCount: 0,
                selectedFileCount: importBrowserSelectedFileURLs.count,
                canGoBack: true,
                canGoUp: true
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
                folderName: "BOKKI Encoder Files",
                detailText: "On My iPhone"
            )
        ]

        if let samplesURL = try? TaptionTestVideoSeeder.documentsSampleFolderURL(),
           fileManager.fileExists(atPath: samplesURL.path) {
            roots.append(HomeImportBrowserFolderSnapshot(
                id: samplesURL.standardizedFileURL.path,
                folderName: "Samples",
                detailText: "BOKKI Encoder Files"
            ))
        }

        return roots
    }

    private func clearImportBrowserState(stoppingAccess: Bool) {
        importBrowserMode = nil
        importBrowserRootURL = nil
        importBrowserRootDisplayName = nil
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

    private func selectAllImportBrowserFilesIfNeeded(in folderURL: URL) {
        guard importBrowserMode == .folder else {
            return
        }

        let selectedURLs = (try? videoFileURLs(in: folderURL)) ?? []
        importBrowserSelectedFileURLs = Set(selectedURLs.map { $0.standardizedFileURL })
    }

    private func importBrowserNavigationScope(
        for url: URL,
        authorizedRootURL: URL? = nil
    ) -> (rootURL: URL, displayName: String) {
        let standardizedURL = url.standardizedFileURL
        if let authorizedRootURL = authorizedRootURL?.standardizedFileURL,
           importBrowserURL(standardizedURL, isInsideRoot: authorizedRootURL) {
            return (
                authorizedRootURL,
                importBrowserDisplayName(for: authorizedRootURL, fallback: "Files")
            )
        }

        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first?.standardizedFileURL,
              importBrowserURL(standardizedURL, isInsideRoot: documentsURL) else {
            return (standardizedURL, standardizedURL.lastPathComponent)
        }

        return (documentsURL, "BOKKI Encoder Files")
    }

    private func importBrowserDisplayName(for url: URL, fallback: String) -> String {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? fallback : name
    }

    private func relativeImportBrowserPath(
        root: URL,
        current: URL,
        rootDisplayName: String
    ) -> String {
        let rootPath = root.standardizedFileURL.path
        let currentPath = current.standardizedFileURL.path
        guard currentPath != rootPath,
              currentPath.hasPrefix(rootPath + "/") else {
            return rootDisplayName
        }

        let suffix = currentPath
            .dropFirst(rootPath.count + 1)
            .split(separator: "/")
            .joined(separator: "/")
        guard !suffix.isEmpty else {
            return rootDisplayName
        }
        return "\(rootDisplayName)/\(suffix)"
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
                    for: outputFolderURL
                )
                pendingSaveAccessURLs[updatedJob.id] = outputFolderURL
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
        fileSizeBytes: Int64?
    ) -> String {
        let fileName = savedURL.lastPathComponent
        return [
            "File: \(fileName)",
            "Size: \(fileSizeText(fileSizeBytes))"
        ].joined(separator: "\n")
    }

    private func makeSavedFolderPrompt(
        fileName: String,
        savedURL: URL,
        saveDestination: TaptionSaveDestinationKind
    ) -> SavedFolderPrompt? {
        switch saveDestination {
        case .sourceFolder, .temporaryOnly:
            return SavedFolderPrompt(
                fileName: fileName,
                folderURL: savedURL.deletingLastPathComponent()
            )
        case .photosLibrary:
            return nil
        }
    }

    private func makeSavedFolderPrompt(for batch: FolderEncodingBatch) -> SavedFolderPrompt? {
        guard batch.completedCount > 0,
              let outputFolderURL = batch.outputFolderURL else {
            return nil
        }
        return SavedFolderPrompt(
            fileName: outputFolderURL.lastPathComponent,
            folderURL: outputFolderURL
        )
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
        let usesFolderBatchNaming = folderBatch?.sourceKind == .folder
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
                        fileManager: fileManager,
                        usesParenthesizedCounter: usesFolderBatchNaming
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
                        fileManager: fileManager,
                        usesParenthesizedCounter: usesFolderBatchNaming
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
        fileManager: FileManager,
        usesParenthesizedCounter: Bool = false
    ) -> URL {
        let directoryURL = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension

        for index in 2...999 {
            let numberedBaseName = usesParenthesizedCounter
                ? "\(baseName) (\(index))"
                : "\(baseName) \(index)"
            let candidate = directoryURL
                .appendingPathComponent(numberedBaseName)
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

    private func resolveSecurityScopedAccessURL(from bookmarkData: Data?, withoutUI: Bool = false) -> URL? {
        guard let bookmarkData else {
            return nil
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: withoutUI ? [.withoutUI] : [],
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

    private func activateFolderOutputDirectory(_ url: URL) -> Bool {
        let outputFolderURL = url.standardizedFileURL
        let alreadyActive = securityScopedAccess.contains(outputFolderURL)
        securityScopedAccess.acquire(outputFolderURL)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: outputFolderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            if !alreadyActive { securityScopedAccess.release(outputFolderURL) }
            return false
        }
        return true
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
        invalidateEncodingStart()
        preparationOperationID = nil
        dismissMiniPreview()
        singleFilePreviewContext = nil
        securityScopedAccess.replace(with: urls)
        AppLogger.info(
            "Security scoped access started",
            category: .fileImport,
            metadata: [
                "requested": "\(urls.count)",
                "granted": "\(securityScopedAccess.count)",
                "names": urls.map(\.lastPathComponent).joined(separator: "|")
            ]
        )
    }

    private func stopSecurityScopedAccess() {
        singleFilePreviewContext = nil
        securityScopedAccess.releaseAll()
    }

    private func hasActiveSecurityScopedAccess(for url: URL) -> Bool {
        securityScopedAccess.contains(url)
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
