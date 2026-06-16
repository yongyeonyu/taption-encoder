import Foundation

enum HomeSourceKind: String, Equatable {
    case files = "Files"
    case folder = "Folder"
    case photos = "Photos"
}

struct HomeSelectedSource: Identifiable, Equatable {
    var id: UUID
    var kind: HomeSourceKind
    var displayName: String
    var url: URL

    init(
        id: UUID = UUID(),
        kind: HomeSourceKind,
        displayName: String,
        url: URL
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.url = url
    }
}

struct StorageIssue: Equatable {
    var requiredBytes: Int64
    var availableBytes: Int64?
    var message: String
}

struct LoadedVideoInfo: Equatable {
    var fileName: String
    var inputSummary: String
    var resolution: String
    var frameRate: String
    var duration: String
    var audio: String
    var audioPathTitle: String = "Audio Path"
    var audioPathDetail: String = "Audio route has not been inspected yet."
    var audioOutputSummary: String = "Source"
    var fileSize: String
    var inputSupportTitle: String
    var inputSupportDetail: String
    var isInputSupportedNow: Bool
    var codecPathTitle: String
    var codecPathDetail: String
    var outputSummary: String
    var outputName: String
    var isRouteEncodable: Bool

    var readinessStatusText: String {
        if isRouteEncodable {
            return "Ready"
        }
        return "Not supported yet"
    }

    var readinessDetailText: String {
        if isRouteEncodable {
            return "Ready to encode."
        }
        if !isInputSupportedNow {
            return "Not supported yet. \(inputSupportDetail)"
        }
        return "Not supported yet. \(codecPathDetail)"
    }

    var codecPathBadge: String {
        switch codecPathTitle {
        case "Path HW":
            return "HW"
        case "Path SW":
            return "SW"
        case "Path HW/SW":
            return "HW/SW"
        case "Path SW Plan Ready":
            return "SW"
        case "Path SW Blocked":
            return "SW"
        case "Path Planned":
            return "SW"
        case "Path Unsupported":
            return "Unsupported"
        default:
            return codecPathTitle.replacingOccurrences(of: "Path ", with: "")
        }
    }

    var audioPathBadge: String {
        switch audioPathTitle {
        case "Audio Copy":
            return "Copy"
        case "Audio HW":
            return "HW"
        case "Audio SW":
            return "SW"
        case "Audio Blocked":
            return "Blocked"
        case "Audio Unsupported":
            return "Unsupported"
        case "No Audio":
            return "None"
        default:
            return audioPathTitle.replacingOccurrences(of: "Audio ", with: "")
        }
    }

    var isInputSupportedForCurrentBuild: Bool {
        isInputSupportedNow
    }

    var isCodecPathSupportedForCurrentBuild: Bool {
        switch codecPathBadge {
        case "HW", "SW", "HW/SW":
            return true
        default:
            return false
        }
    }

    var isAudioPathSupportedForCurrentBuild: Bool {
        switch audioPathBadge {
        case "HW", "SW", "Copy", "None":
            return true
        default:
            return false
        }
    }
}

struct LoadedAudioPathInfo: Equatable {
    var title: String
    var detail: String
    var outputSummary: String

    static func make(
        firstAudioTrack: TaptionAudioTrackInfo?,
        trackCount: Int,
        outputCodec requestedOutputCodec: TaptionAudioCodec? = nil,
        outputContainer: TaptionVideoContainer
    ) -> LoadedAudioPathInfo {
        guard let firstAudioTrack else {
            return LoadedAudioPathInfo(
                title: "No Audio",
                detail: "No audio track was detected.",
                outputSummary: "None"
            )
        }

        let outputCodec = outputCodec(
            for: firstAudioTrack.codec,
            requestedOutputCodec: requestedOutputCodec,
            outputContainer: outputContainer
        )
        let route = TaptionAudioCodecRoute(
            sourceCodec: firstAudioTrack.codec,
            outputCodec: outputCodec
        )
        let selection = TaptionAudioCodecRoutePlanner.selectRoute(
            sourceCodec: firstAudioTrack.codec,
            outputCodec: outputCodec,
            outputContainer: outputContainer
        )
        let readiness = TaptionAudioCodecExecutionReadinessReporter.item(
            for: route,
            outputContainer: outputContainer
        )

        return LoadedAudioPathInfo(
            title: title(for: readiness, selection: selection),
            detail: detail(
                route: route,
                selection: selection,
                readiness: readiness,
                trackCount: trackCount
            ),
            outputSummary: outputCodec.displayName
        )
    }

    private static func outputCodec(
        for sourceCodec: TaptionAudioCodec,
        requestedOutputCodec: TaptionAudioCodec?,
        outputContainer: TaptionVideoContainer
    ) -> TaptionAudioCodec {
        if let requestedOutputCodec {
            return requestedOutputCodec
        }
        if HW_AudioCodecCapabilityCatalog.canCopyWithoutTranscode(
            codec: sourceCodec,
            into: outputContainer
        ) {
            return sourceCodec
        }
        return TaptionAudioCodecRoutePlanner.defaultOutputCodec
    }

    private static func title(
        for readiness: TaptionAudioCodecExecutionReadinessItem,
        selection: TaptionAudioCodecRouteSelection
    ) -> String {
        switch readiness.readiness {
        case .copyInCurrentBuild:
            return "Audio Copy"
        case .nativeTranscodeInCurrentBuild:
            return "Audio HW"
        case .softwareBackendExecutable, .commandPlanOnly:
            return "Audio SW"
        case .blockedMissingSoftwareEncoder:
            return "Audio Blocked"
        case .unsupported:
            return selection.shortDisplayName == "Unsupported" ? "Audio Unsupported" : "Audio \(selection.shortDisplayName)"
        }
    }

    private static func detail(
        route: TaptionAudioCodecRoute,
        selection: TaptionAudioCodecRouteSelection,
        readiness: TaptionAudioCodecExecutionReadinessItem,
        trackCount: Int
    ) -> String {
        var parts = [
            "\(route.displayName).",
            readiness.blockingReason ?? selection.reason
        ]
        if trackCount > 1 {
            parts.append("Showing the first of \(trackCount) audio tracks.")
        }
        return parts.joined(separator: " ")
    }
}

enum TaptionOutputResolutionPreset: String, Codable, Equatable, CaseIterable {
    case source
    case uhd4k
    case qhd1440
    case fullHD
    case hd720
    case sd480

    var menuTitle: String {
        switch self {
        case .source:
            return "Source"
        case .uhd4k:
            return "4K"
        case .qhd1440:
            return "1440p"
        case .fullHD:
            return "1080p"
        case .hd720:
            return "720p"
        case .sd480:
            return "480p"
        }
    }

    var referenceSize: TaptionPixelSize? {
        switch self {
        case .source:
            return nil
        case .uhd4k:
            return TaptionPixelSize(width: 3840, height: 2160)
        case .qhd1440:
            return TaptionPixelSize(width: 2560, height: 1440)
        case .fullHD:
            return TaptionPixelSize(width: 1920, height: 1080)
        case .hd720:
            return TaptionPixelSize(width: 1280, height: 720)
        case .sd480:
            return TaptionPixelSize(width: 854, height: 480)
        }
    }
}

enum TaptionOutputSizePreset: String, Codable, Equatable, CaseIterable {
    case auto
    case manual

    var menuTitle: String {
        switch self {
        case .auto:
            return "Auto"
        case .manual:
            return "Manual"
        }
    }
}

struct TaptionOutputSelection: Identifiable, Equatable {
    var videoCodec: TaptionVideoCodec
    var audioCodec: TaptionAudioCodec
    var container: TaptionVideoContainer
    var resolutionPreset: TaptionOutputResolutionPreset
    var sizePreset: TaptionOutputSizePreset
    var targetSizeMB: Double?

    init(
        videoCodec: TaptionVideoCodec = .hevc,
        audioCodec: TaptionAudioCodec = TaptionAudioCodecRoutePlanner.defaultOutputCodec,
        container: TaptionVideoContainer = .mp4,
        resolutionPreset: TaptionOutputResolutionPreset = .source,
        sizePreset: TaptionOutputSizePreset = .auto,
        targetSizeMB: Double? = nil
    ) {
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.container = container
        self.resolutionPreset = resolutionPreset
        self.sizePreset = sizePreset
        self.targetSizeMB = targetSizeMB
    }

    var id: String {
        let sizeValue = targetSizeMB.map { String(Int($0.rounded())) } ?? "auto"
        return "\(videoCodec.rawValue)-\(audioCodec.rawValue)-\(container.rawValue)-\(resolutionPreset.rawValue)-\(sizePreset.rawValue)-\(sizeValue)"
    }

    func outputPolicy(for asset: TaptionVideoAsset? = nil) -> TaptionVideoOutputPolicy {
        TaptionVideoOutputPolicy(
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            container: container,
            profile: .automatic,
            qualityPolicy: .preserveSourceVisuals,
            advancedOptions: TaptionAdvancedOutputOptions(
                resizeTo: resolvedResizeTarget(for: asset?.videoTrack),
                targetBitrate: resolvedTargetBitrate(for: asset)
            )
        )
    }

    var summary: String {
        "\(videoCodec.shortDisplayName) + \(audioCodec.displayName) / \(container.defaultFileExtension.uppercased())"
    }

    var videoImplementationNote: String? {
        TaptionCodecOutputCatalog.implementationNote(
            videoCodec: videoCodec,
            container: container
        )
    }

    var audioImplementationNote: String? {
        TaptionAudioCodecOutputCatalog.implementationNote(
            audioCodec: audioCodec,
            container: container
        )
    }

    var implementationNote: String? {
        combinedDetailText
    }

    var implementationState: TaptionOutputImplementationState {
        combinedImplementationState(
            videoState: videoImplementationState,
            audioState: audioImplementationState
        )
    }

    var statusTitle: String {
        switch implementationState {
        case .implemented:
            return "Output Ready"
        case .commandPlanReady:
            return "Output Plan Ready"
        case .planned:
            return "Output Planned"
        case .unsupported:
            return "Output Unsupported"
        }
    }

    var detailText: String {
        if let combinedDetailText {
            return combinedDetailText
        }
        return "This exact output selection can run in the current build."
    }

    var videoImplementationState: TaptionOutputImplementationState {
        TaptionCodecOutputCatalog.implementationState(
            videoCodec: videoCodec,
            container: container
        )
    }

    var audioImplementationState: TaptionOutputImplementationState {
        TaptionAudioCodecOutputCatalog.implementationState(
            audioCodec: audioCodec,
            container: container
        )
    }

    var isImplementedNow: Bool {
        implementationState == .implemented
    }

    static let defaultSelection = TaptionOutputSelection()

    static var videoCodecOptions: [TaptionVideoCodec] {
        TaptionCodecOutputCatalog.selectableVideoCodecs
    }

    static var audioCodecOptions: [TaptionAudioCodec] {
        TaptionAudioCodecOutputCatalog.selectableAudioCodecs
    }

    static var containerOptions: [TaptionVideoContainer] {
        TaptionCodecOutputCatalog.selectableContainers
    }

    static var resolutionOptions: [TaptionOutputResolutionPreset] {
        TaptionOutputResolutionPreset.allCases
    }

    static var sizeOptions: [TaptionOutputSizePreset] {
        TaptionOutputSizePreset.allCases
    }

    private func combinedImplementationState(
        videoState: TaptionOutputImplementationState,
        audioState: TaptionOutputImplementationState
    ) -> TaptionOutputImplementationState {
        if videoState == .unsupported || audioState == .unsupported {
            return .unsupported
        }
        if videoState == .planned || audioState == .planned {
            return .planned
        }
        if videoState == .commandPlanReady || audioState == .commandPlanReady {
            return .commandPlanReady
        }
        return .implemented
    }

    private var combinedDetailText: String? {
        let notes = [videoImplementationNote, audioImplementationNote]
            .compactMap { $0 }
        guard !notes.isEmpty else {
            return nil
        }

        var uniqueNotes: [String] = []
        for note in notes where !uniqueNotes.contains(note) {
            uniqueNotes.append(note)
        }
        return uniqueNotes.joined(separator: " ")
    }

    private func resolvedResizeTarget(for track: TaptionVideoTrackInfo?) -> TaptionPixelSize? {
        guard resolutionPreset != .source else {
            return nil
        }

        let baseSize = baseResizeSize(for: track)
        guard let track else {
            return baseSize
        }

        return clampToSourceBounds(baseSize, sourceSize: track.displaySize)
    }

    private func baseResizeSize(for track: TaptionVideoTrackInfo?) -> TaptionPixelSize {
        if let referenceSize = resolutionPreset.referenceSize {
            guard let track else {
                return referenceSize
            }
            return fittedSize(
                sourceSize: track.displaySize,
                boundingSize: referenceSize
            )
        }

        return track?.displaySize ?? TaptionPixelSize(width: 1920, height: 1080)
    }

    private func clampToSourceBounds(
        _ size: TaptionPixelSize,
        sourceSize: TaptionPixelSize
    ) -> TaptionPixelSize {
        let maxWidth = max(2, evenDimension(Double(sourceSize.width)))
        let maxHeight = max(2, evenDimension(Double(sourceSize.height)))
        return TaptionPixelSize(
            width: min(size.width, maxWidth),
            height: min(size.height, maxHeight)
        )
    }

    private func fittedSize(
        sourceSize: TaptionPixelSize,
        boundingSize: TaptionPixelSize
    ) -> TaptionPixelSize {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              boundingSize.width > 0,
              boundingSize.height > 0 else {
            return boundingSize
        }

        let widthScale = Double(boundingSize.width) / Double(sourceSize.width)
        let heightScale = Double(boundingSize.height) / Double(sourceSize.height)
        let scale = min(widthScale, heightScale, 1)

        return TaptionPixelSize(
            width: max(2, evenDimension(Double(sourceSize.width) * scale)),
            height: max(2, evenDimension(Double(sourceSize.height) * scale))
        )
    }

    private func evenDimension(_ value: Double) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded - 1
    }

    private func resolvedTargetBitrate(for asset: TaptionVideoAsset?) -> Int? {
        guard sizePreset == .manual,
              let asset,
              let duration = asset.duration,
              duration.isFinite,
              duration > 0 else {
            return nil
        }

        let targetSizeMB = normalizedTargetSizeMB(for: asset)
        let totalBitBudget = Int((targetSizeMB * 8_000_000).rounded())
        let audioBitrate = estimatedAudioBitrate(for: asset)
        let targetBitrate = Int((Double(totalBitBudget) / duration).rounded()) - audioBitrate
        return max(targetBitrate, 300_000)
    }

    func normalizedTargetSizeMB(for asset: TaptionVideoAsset?) -> Double {
        let range = targetSizeRangeMB(for: asset)
        let suggested = targetSizeMB ?? suggestedTargetSizeMB(for: asset)
        return min(max(suggested, range.lowerBound), range.upperBound)
    }

    func suggestedTargetSizeMB(for asset: TaptionVideoAsset?) -> Double {
        if let fileSize = asset?.fingerprint.fileSize,
           fileSize > 0 {
            return max(1, Double(fileSize) / 1_000_000)
        }

        guard let asset,
              let duration = asset.duration,
              duration.isFinite,
              duration > 0 else {
            return 100
        }

        let videoBitrate = Double(asset.videoTrack?.estimatedBitrate ?? 4_000_000)
        let audioBitrate = Double(estimatedAudioBitrate(for: asset))
        return max(1, ((videoBitrate + audioBitrate) * duration) / 8_000_000)
    }

    func targetSizeRangeMB(for asset: TaptionVideoAsset?) -> ClosedRange<Double> {
        let suggested = suggestedTargetSizeMB(for: asset)
        let minimum = max(1, floor(suggested * 0.25))
        let maximum = max(minimum + 1, ceil(suggested * 1.75))
        return minimum...maximum
    }

    private func estimatedAudioBitrate(for asset: TaptionVideoAsset) -> Int {
        asset.audioTracks
            .compactMap(\.estimatedBitrate)
            .reduce(0, +)
    }
}

struct LoadedVideoPathInfo: Equatable {
    var title: String
    var detail: String
    var outputSummary: String
    var isRouteEncodable: Bool

    static func make(
        sourceCodec: TaptionVideoCodec,
        routeSelection: TaptionCodecRouteSelection,
        outputSelection: TaptionOutputSelection
    ) -> LoadedVideoPathInfo {
        let routeImplementationState = TaptionCodecOutputCatalog.routeImplementationState(
            sourceCodec: sourceCodec,
            outputCodec: outputSelection.videoCodec,
            container: outputSelection.container
        )
        let videoReadiness = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(
                sourceCodec: sourceCodec,
                outputCodec: outputSelection.videoCodec
            ),
            outputContainer: outputSelection.container
        )
        let detailParts = [
            routeSelection.displayDetail,
            videoReadiness.blockingReason,
            outputSelection.implementationNote
        ].compactMap { $0 }

        return LoadedVideoPathInfo(
            title: title(
                routeSelection: routeSelection,
                routeImplementationState: routeImplementationState,
                videoReadiness: videoReadiness
            ),
            detail: detailParts.joined(separator: " "),
            outputSummary: outputSelection.summary,
            isRouteEncodable: routeSelection.isEncodableNow
                && routeImplementationState == .implemented
        )
    }

    private static func title(
        routeSelection: TaptionCodecRouteSelection,
        routeImplementationState: TaptionOutputImplementationState,
        videoReadiness: TaptionVideoCodecExecutionReadinessItem
    ) -> String {
        switch routeImplementationState {
        case .implemented:
            return routeSelection.displayTitle
        case .commandPlanReady:
            return "Path \(planReadyPathDisplayName(for: videoReadiness)) Plan Ready"
        case .planned:
            if videoReadiness.readiness == .blockedMissingSoftwareEncoder {
                return "Path SW Blocked"
            }
            return "Path Planned"
        case .unsupported:
            return "Path Unsupported"
        }
    }

    private static func planReadyPathDisplayName(
        for videoReadiness: TaptionVideoCodecExecutionReadinessItem
    ) -> String {
        if videoReadiness.commandBackend == .ffmpegFamily {
            return TaptionCodecRouteExecutionKind.software.shortDisplayName
        }
        return videoReadiness.routeSelection.executionKind.shortDisplayName
    }
}

struct EncodingFileCardSnapshot: Identifiable, Equatable {
    var id: String
    var fileName: String
    var sourceKind: HomeSourceKind
    var videoInfo: LoadedVideoInfo?
    var statusText: String
    var detailText: String?
    var progress: EncodingProgressSnapshot?
    var isActive: Bool
    var isSelected: Bool
    var isEnabled: Bool
}

struct FolderQueueSnapshot: Equatable {
    var folderName: String
    var currentIndex: Int
    var totalCount: Int
    var completedCount: Int
    var failedCount: Int
    var currentFileName: String?

    var positionText: String {
        guard totalCount > 0 else {
            return "0/0"
        }
        return "\(min(currentIndex + 1, totalCount))/\(totalCount)"
    }

    var statusText: String {
        var parts = ["Folder \(positionText)"]
        parts.append("\(completedCount) encoded")
        if failedCount > 0 {
            parts.append("\(failedCount) failed")
        }
        return parts.joined(separator: " · ")
    }
}

struct PreparedEncodingReview: Equatable {
    var source: HomeSelectedSource
    var job: TaptionPreparedEncodingJob
    var videoInfo: LoadedVideoInfo
    var folderQueue: FolderQueueSnapshot?

    init(
        source: HomeSelectedSource,
        job: TaptionPreparedEncodingJob,
        videoInfo: LoadedVideoInfo,
        folderQueue: FolderQueueSnapshot? = nil
    ) {
        self.source = source
        self.job = job
        self.videoInfo = videoInfo
        self.folderQueue = folderQueue
    }
}

struct EncodingProgressSnapshot: Equatable {
    var stage: TaptionEncodingStage
    var fractionCompleted: Double
    var elapsedTime: TimeInterval
    var estimatedRemainingTime: TimeInterval?
    var backendLabel: String
    var outputSummary: String?

    init(
        stage: TaptionEncodingStage,
        fractionCompleted: Double,
        elapsedTime: TimeInterval,
        estimatedRemainingTime: TimeInterval?,
        backendLabel: String,
        outputSummary: String? = nil
    ) {
        self.stage = stage
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.elapsedTime = max(0, elapsedTime)
        self.estimatedRemainingTime = estimatedRemainingTime
        self.backendLabel = backendLabel
        self.outputSummary = outputSummary
    }

    var percentText: String {
        "\(Int((fractionCompleted * 100).rounded()))%"
    }

    var stageTitle: String {
        switch stage {
        case .queued:
            return "Queued"
        case .inspecting:
            return "Inspecting"
        case .preparing:
            return "Preparing"
        case .encoding:
            return "Encoding"
        case .waitingForSaveGate:
            return "Waiting to save"
        case .saving:
            return "Saving"
        case .completed:
            return "Complete"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        }
    }

    static let empty = EncodingProgressSnapshot(
        stage: .queued,
        fractionCompleted: 0,
        elapsedTime: 0,
        estimatedRemainingTime: nil,
        backendLabel: "Automatic Codec Path",
        outputSummary: nil
    )
}

struct CompletedTemporaryOutput: Equatable {
    var planID: UUID
    var sourceName: String
    var temporaryOutputURL: URL
    var finalOutputURL: URL?
    var pendingSaveState: TaptionPendingSaveState
    var usedEncoderMode: TaptionEncoderMode
    var usedBackend: TaptionEncodingBackend
}

struct PendingSaveJob: Identifiable, Equatable {
    var id: UUID
    var sourceName: String
    var state: TaptionPendingSaveState
    var saveGateMessage: String?

    init(
        sourceName: String,
        state: TaptionPendingSaveState,
        saveGateMessage: String? = nil
    ) {
        self.id = state.id
        self.sourceName = sourceName
        self.state = state
        self.saveGateMessage = saveGateMessage
    }
}

struct PendingSaveConflictPrompt: Identifiable, Equatable {
    var id: UUID {
        job.id
    }

    var job: PendingSaveJob
    var existingURL: URL
    var suggestedURL: URL

    var message: String {
        "A file named \(existingURL.lastPathComponent) already exists. Overwrite it or save this output as \(suggestedURL.lastPathComponent)."
    }
}

struct SavedOutput: Equatable {
    var displayName: String
    var destinationDescription: String
    var detailOverride: String?

    init(
        displayName: String,
        destinationDescription: String,
        detailOverride: String? = nil
    ) {
        self.displayName = displayName
        self.destinationDescription = destinationDescription
        self.detailOverride = detailOverride
    }
}

struct HomeEncodingError: Equatable {
    var title: String
    var message: String
}

enum HomeScreenState: Equatable {
    case idle
    case importing(HomeSelectedSource)
    case inspecting(HomeSelectedSource)
    case storageChecking(HomeSelectedSource)
    case storageBlocked(StorageIssue)
    case readyToStart(PreparedEncodingReview)
    case encoding(EncodingProgressSnapshot)
    case cancelling
    case waitingForReward(CompletedTemporaryOutput)
    case pendingSave(PendingSaveJob)
    case saving(PendingSaveJob)
    case completed(SavedOutput)
    case failed(HomeEncodingError)
    case cancelled

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .importing:
            return "Importing"
        case .inspecting:
            return "Inspecting"
        case .storageChecking:
            return "Checking storage"
        case .storageBlocked:
            return "Storage needed"
        case .readyToStart:
            return "Ready to encode"
        case .encoding(let progress):
            return progress.stageTitle
        case .cancelling:
            return "Cancelling"
        case .waitingForReward:
            return "Ready to save"
        case .pendingSave:
            return "Pending save"
        case .saving:
            return "Saving"
        case .completed:
            return "Complete"
        case .failed(let error):
            return error.title
        case .cancelled:
            return "Cancelled"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "Choose a video to begin."
        case .importing(let source):
            return "Importing \(source.displayName)."
        case .inspecting(let source):
            return "Reading codec and track details for \(source.displayName)."
        case .storageChecking:
            return "Checking temporary and final output space."
        case .storageBlocked(let issue):
            return issue.message
        case .readyToStart(let review):
            if !review.videoInfo.isRouteEncodable {
                return review.videoInfo.readinessDetailText
            }
            if let folderQueue = review.folderQueue {
                return "\(folderQueue.statusText). Review the first video, then start sequential \(review.videoInfo.outputSummary) encoding."
            }
            return "Review the video info, then start \(review.videoInfo.outputSummary) encoding."
        case .encoding(let progress):
            if let outputSummary = progress.outputSummary {
                return "\(progress.backendLabel) is converting the source to \(outputSummary)."
            }
            return "\(progress.backendLabel) is converting the source to the selected output."
        case .cancelling:
            return "Stopping the current job."
        case .waitingForReward(let output):
            return "Save Path: \((output.finalOutputURL ?? output.temporaryOutputURL).path)"
        case .pendingSave(let job):
            if let message = job.saveGateMessage {
                return message
            }
            return "Save Path: \((job.state.finalOutputURL ?? job.state.temporaryOutputURL).path)"
        case .saving(let job):
            if job.state.requiresRewardedAd {
                return "Saving \(job.sourceName)."
            }
            return "Saving \(job.sourceName). Rewarded ad already completed."
        case .completed(let output):
            if let detailOverride = output.detailOverride {
                return detailOverride
            }
            return "\(output.displayName) saved to \(output.destinationDescription)."
        case .failed(let error):
            return error.message
        case .cancelled:
            return "The encoding job was cancelled."
        }
    }

    var isBusy: Bool {
        switch self {
        case .importing, .inspecting, .storageChecking, .encoding, .cancelling, .saving:
            return true
        case .idle, .storageBlocked, .readyToStart, .waitingForReward, .pendingSave, .completed, .failed, .cancelled:
            return false
        }
    }

    var canSelectSource: Bool {
        !isBusy
    }

    var canCancel: Bool {
        switch self {
        case .importing, .inspecting, .storageChecking, .encoding:
            return true
        case .idle, .storageBlocked, .readyToStart, .cancelling, .waitingForReward, .pendingSave, .saving, .completed, .failed, .cancelled:
            return false
        }
    }

    var canStartEncoding: Bool {
        if case .readyToStart(let review) = self {
            return review.videoInfo.isRouteEncodable
        }
        return false
    }

    var canReset: Bool {
        switch self {
        case .idle, .importing, .inspecting, .storageChecking, .encoding, .cancelling, .saving:
            return false
        case .storageBlocked, .readyToStart, .waitingForReward, .pendingSave, .completed, .failed, .cancelled:
            return true
        }
    }

    var selectedSourceName: String? {
        switch self {
        case .importing(let source), .inspecting(let source), .storageChecking(let source):
            return source.displayName
        case .readyToStart(let review):
            return review.source.displayName
        case .waitingForReward(let output):
            return output.sourceName
        case .pendingSave(let job), .saving(let job):
            return job.sourceName
        case .completed(let output):
            return output.displayName
        case .idle, .storageBlocked, .encoding, .cancelling, .failed, .cancelled:
            return nil
        }
    }

    var progress: EncodingProgressSnapshot? {
        switch self {
        case .encoding(let progress):
            return progress
        case .waitingForReward:
            return EncodingProgressSnapshot(
                stage: .waitingForSaveGate,
                fractionCompleted: 1,
                elapsedTime: 0,
                estimatedRemainingTime: 0,
                backendLabel: "Encoder",
                outputSummary: nil
            )
        case .saving:
            return EncodingProgressSnapshot(
                stage: .saving,
                fractionCompleted: 1,
                elapsedTime: 0,
                estimatedRemainingTime: 0,
                backendLabel: "Encoder",
                outputSummary: nil
            )
        case .completed:
            return EncodingProgressSnapshot(
                stage: .completed,
                fractionCompleted: 1,
                elapsedTime: 0,
                estimatedRemainingTime: 0,
                backendLabel: "Encoder",
                outputSummary: nil
            )
        case .idle, .importing, .inspecting, .storageChecking, .storageBlocked, .readyToStart, .cancelling, .pendingSave, .failed, .cancelled:
            return nil
        }
    }

    var completedTemporaryOutput: CompletedTemporaryOutput? {
        switch self {
        case .waitingForReward(let output):
            return output
        case .idle, .importing, .inspecting, .storageChecking, .storageBlocked, .readyToStart, .encoding, .cancelling, .pendingSave, .saving, .completed, .failed, .cancelled:
            return nil
        }
    }

    var pendingSaveJob: PendingSaveJob? {
        switch self {
        case .pendingSave(let job), .saving(let job):
            return job
        case .idle, .importing, .inspecting, .storageChecking, .storageBlocked, .readyToStart, .encoding, .cancelling, .waitingForReward, .completed, .failed, .cancelled:
            return nil
        }
    }

    var preparedEncodingReview: PreparedEncodingReview? {
        switch self {
        case .readyToStart(let review):
            return review
        case .idle, .importing, .inspecting, .storageChecking, .storageBlocked, .encoding, .cancelling, .waitingForReward, .pendingSave, .saving, .completed, .failed, .cancelled:
            return nil
        }
    }

    var videoInfo: LoadedVideoInfo? {
        preparedEncodingReview?.videoInfo
    }
}
