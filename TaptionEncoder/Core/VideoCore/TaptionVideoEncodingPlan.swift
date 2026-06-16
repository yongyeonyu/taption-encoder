import Foundation

enum TaptionEncodingInputKind: String, Codable, Equatable {
    case singleAsset
    case timelineProject
}

enum TaptionSaveDestinationKind: String, Codable, Equatable {
    case sourceFolder
    case photosLibrary
    case temporaryOnly
}

enum TaptionSaveGate: String, Codable, Equatable {
    case none
    case rewardedAdBeforeFinalSave
}

enum TaptionEncodingStage: String, Codable, Equatable {
    case queued
    case inspecting
    case preparing
    case encoding
    case waitingForSaveGate
    case saving
    case completed
    case cancelled
    case failed
}

struct TaptionAdvancedOutputOptions: Codable, Equatable {
    var resizeTo: TaptionPixelSize?
    var frameRate: TaptionRationalFrameRate?
    var targetBitrate: Int?
    var color: TaptionColorDescription?
    var rotationDegrees: Int?

    init(
        resizeTo: TaptionPixelSize? = nil,
        frameRate: TaptionRationalFrameRate? = nil,
        targetBitrate: Int? = nil,
        color: TaptionColorDescription? = nil,
        rotationDegrees: Int? = nil
    ) {
        self.resizeTo = resizeTo
        self.frameRate = frameRate
        self.targetBitrate = targetBitrate
        self.color = color
        self.rotationDegrees = rotationDegrees
    }

    static let preserveSource = TaptionAdvancedOutputOptions()
}

struct TaptionVideoOutputPolicy: Codable, Equatable {
    var videoCodec: TaptionVideoCodec
    var container: TaptionVideoContainer
    var profile: TaptionHEVCProfile
    var qualityPolicy: TaptionQualityPolicy
    var advancedOptions: TaptionAdvancedOutputOptions

    init(
        videoCodec: TaptionVideoCodec = .hevc,
        container: TaptionVideoContainer = .mp4,
        profile: TaptionHEVCProfile = .automatic,
        qualityPolicy: TaptionQualityPolicy = .preserveSourceVisuals,
        advancedOptions: TaptionAdvancedOutputOptions = .preserveSource
    ) {
        self.videoCodec = videoCodec
        self.container = container
        self.profile = profile
        self.qualityPolicy = qualityPolicy
        self.advancedOptions = advancedOptions
    }
}

typealias TaptionHEVCOutputPolicy = TaptionVideoOutputPolicy

enum TaptionSourcePreservingOutputPolicyResolver {
    static func resolvedPolicy(
        for asset: TaptionVideoAsset,
        requestedPolicy: TaptionVideoOutputPolicy
    ) -> TaptionVideoOutputPolicy {
        guard requestedPolicy.qualityPolicy == .preserveSourceVisuals,
              let videoTrack = asset.videoTrack else {
            return requestedPolicy
        }

        var resolvedPolicy = requestedPolicy
        resolvedPolicy.advancedOptions = resolvedOptions(
            for: videoTrack,
            requestedOptions: requestedPolicy.advancedOptions
        )
        return resolvedPolicy
    }

    static func resolvedOptions(
        for videoTrack: TaptionVideoTrackInfo,
        requestedOptions: TaptionAdvancedOutputOptions
    ) -> TaptionAdvancedOutputOptions {
        TaptionAdvancedOutputOptions(
            resizeTo: requestedOptions.resizeTo ?? videoTrack.displaySize,
            frameRate: requestedOptions.frameRate ?? videoTrack.nominalFrameRate,
            targetBitrate: requestedOptions.targetBitrate ?? videoTrack.estimatedBitrate,
            color: requestedOptions.color ?? videoTrack.color,
            rotationDegrees: requestedOptions.rotationDegrees ?? videoTrack.rotationDegrees
        )
    }
}

struct TaptionOutputNamingPolicy: Codable, Equatable {
    var suffix: String
    var replacesExistingExtension: Bool

    init(suffix: String = "_taption", replacesExistingExtension: Bool = true) {
        self.suffix = suffix
        self.replacesExistingExtension = replacesExistingExtension
    }

    func outputURL(for sourceURL: URL, container: TaptionVideoContainer) -> URL {
        let directoryURL = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent + suffix
        return directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(container.defaultFileExtension)
    }
}

struct TaptionSavePolicy: Codable, Equatable {
    var destination: TaptionSaveDestinationKind
    var saveGate: TaptionSaveGate
    var namingPolicy: TaptionOutputNamingPolicy
    var shouldRestorePendingSaveOnLaunch: Bool

    init(
        destination: TaptionSaveDestinationKind = .sourceFolder,
        saveGate: TaptionSaveGate = .rewardedAdBeforeFinalSave,
        namingPolicy: TaptionOutputNamingPolicy = TaptionOutputNamingPolicy(),
        shouldRestorePendingSaveOnLaunch: Bool = true
    ) {
        self.destination = destination
        self.saveGate = saveGate
        self.namingPolicy = namingPolicy
        self.shouldRestorePendingSaveOnLaunch = shouldRestorePendingSaveOnLaunch
    }
}

struct TaptionEncoderSelection: Codable, Equatable {
    var requestedMode: TaptionEncoderMode
    var backend: TaptionEncodingBackend?
    var reason: String

    init(
        requestedMode: TaptionEncoderMode = .automatic,
        backend: TaptionEncodingBackend? = nil,
        reason: String = "The app chooses hardware first and falls back automatically."
    ) {
        self.requestedMode = requestedMode
        self.backend = backend
        self.reason = reason
    }
}

struct TaptionEncodingInput: Codable, Equatable {
    var kind: TaptionEncodingInputKind
    var assetID: UUID?
    var projectID: UUID?

    init(kind: TaptionEncodingInputKind, assetID: UUID? = nil, projectID: UUID? = nil) {
        self.kind = kind
        self.assetID = assetID
        self.projectID = projectID
    }
}

struct TaptionEncodingPlan: Identifiable, Codable, Equatable {
    var id: UUID
    var input: TaptionEncodingInput
    var outputPolicy: TaptionVideoOutputPolicy
    var codecRoute: TaptionCodecRoute?
    var codecExecutionKind: TaptionCodecRouteExecutionKind?
    var videoCommandPlan: SW_FFmpegCommandPlan?
    var audioPlan: TaptionAudioTranscodePlan?
    var savePolicy: TaptionSavePolicy
    var encoderSelection: TaptionEncoderSelection
    var sourceURL: URL?
    var temporaryOutputURL: URL?
    var finalOutputURL: URL?

    init(
        id: UUID = UUID(),
        input: TaptionEncodingInput,
        outputPolicy: TaptionVideoOutputPolicy = TaptionVideoOutputPolicy(),
        codecRoute: TaptionCodecRoute? = nil,
        codecExecutionKind: TaptionCodecRouteExecutionKind? = nil,
        videoCommandPlan: SW_FFmpegCommandPlan? = nil,
        audioPlan: TaptionAudioTranscodePlan? = nil,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy(),
        encoderSelection: TaptionEncoderSelection = TaptionEncoderSelection(),
        sourceURL: URL? = nil,
        temporaryOutputURL: URL? = nil,
        finalOutputURL: URL? = nil
    ) {
        self.id = id
        self.input = input
        self.outputPolicy = outputPolicy
        self.codecRoute = codecRoute
        self.codecExecutionKind = codecExecutionKind
        self.videoCommandPlan = videoCommandPlan
        self.audioPlan = audioPlan
        self.savePolicy = savePolicy
        self.encoderSelection = encoderSelection
        self.sourceURL = sourceURL
        self.temporaryOutputURL = temporaryOutputURL
        self.finalOutputURL = finalOutputURL
    }
}

struct TaptionPendingSaveState: Identifiable, Codable, Equatable {
    var id: UUID
    var planID: UUID
    var temporaryOutputURL: URL
    var finalOutputURL: URL?
    var saveDestination: TaptionSaveDestinationKind
    var requiresRewardedAd: Bool
    var createdAt: Date
    var accessBookmarkData: Data?
    var rewardedAdCompletedAt: Date?

    init(
        id: UUID = UUID(),
        planID: UUID,
        temporaryOutputURL: URL,
        finalOutputURL: URL? = nil,
        saveDestination: TaptionSaveDestinationKind,
        requiresRewardedAd: Bool,
        createdAt: Date = Date(),
        accessBookmarkData: Data? = nil,
        rewardedAdCompletedAt: Date? = nil
    ) {
        self.id = id
        self.planID = planID
        self.temporaryOutputURL = temporaryOutputURL
        self.finalOutputURL = finalOutputURL
        self.saveDestination = saveDestination
        self.requiresRewardedAd = requiresRewardedAd
        self.createdAt = createdAt
        self.accessBookmarkData = accessBookmarkData
        self.rewardedAdCompletedAt = rewardedAdCompletedAt
    }
}

struct TaptionEncodingProgress: Codable, Equatable {
    var stage: TaptionEncodingStage
    var fractionCompleted: Double
    var elapsedTime: TimeInterval
    var estimatedRemainingTime: TimeInterval?
    var currentFrame: Int64?
    var totalFrames: Int64?

    init(
        stage: TaptionEncodingStage,
        fractionCompleted: Double,
        elapsedTime: TimeInterval = 0,
        estimatedRemainingTime: TimeInterval? = nil,
        currentFrame: Int64? = nil,
        totalFrames: Int64? = nil
    ) {
        self.stage = stage
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.elapsedTime = max(0, elapsedTime)
        self.estimatedRemainingTime = estimatedRemainingTime
        self.currentFrame = currentFrame
        self.totalFrames = totalFrames
    }
}

struct TaptionStorageRequirement: Codable, Equatable {
    var estimatedOutputBytes: Int64
    var requiredWorkingBytes: Int64
    var availableBytes: Int64?

    init(
        estimatedOutputBytes: Int64,
        requiredWorkingBytes: Int64,
        availableBytes: Int64? = nil
    ) {
        self.estimatedOutputBytes = estimatedOutputBytes
        self.requiredWorkingBytes = requiredWorkingBytes
        self.availableBytes = availableBytes
    }

    var hasEnoughSpace: Bool {
        guard let availableBytes else {
            return true
        }
        return availableBytes >= requiredWorkingBytes
    }
}

struct TaptionEncodingResult: Codable, Equatable {
    var planID: UUID
    var temporaryOutputURL: URL
    var finalOutputURL: URL?
    var usedBackend: TaptionEncodingBackend
    var usedMode: TaptionEncoderMode
    var pendingSaveState: TaptionPendingSaveState?

    init(
        planID: UUID,
        temporaryOutputURL: URL,
        finalOutputURL: URL? = nil,
        usedBackend: TaptionEncodingBackend,
        usedMode: TaptionEncoderMode,
        pendingSaveState: TaptionPendingSaveState? = nil
    ) {
        self.planID = planID
        self.temporaryOutputURL = temporaryOutputURL
        self.finalOutputURL = finalOutputURL
        self.usedBackend = usedBackend
        self.usedMode = usedMode
        self.pendingSaveState = pendingSaveState
    }
}

enum TaptionEncodingPlanner {
    static func makeSingleAssetHEVCPlan(
        asset: TaptionVideoAsset,
        sourceURL: URL,
        temporaryOutputURL: URL,
        preferredMode: TaptionEncoderMode = .automatic,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy()
    ) -> TaptionEncodingPlan {
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            container: .mp4,
            profile: .automatic,
            qualityPolicy: .preserveSourceVisuals,
            advancedOptions: .preserveSource
        )
        return makeSingleAssetPlan(
            asset: asset,
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryOutputURL,
            outputPolicy: outputPolicy,
            preferredMode: preferredMode,
            savePolicy: savePolicy
        )
    }

    static func makeSingleAssetPlan(
        asset: TaptionVideoAsset,
        sourceURL: URL,
        temporaryOutputURL: URL,
        outputPolicy: TaptionVideoOutputPolicy,
        preferredMode: TaptionEncoderMode = .automatic,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy()
    ) -> TaptionEncodingPlan {
        let resolvedOutputPolicy = TaptionSourcePreservingOutputPolicyResolver.resolvedPolicy(
            for: asset,
            requestedPolicy: outputPolicy
        )
        let finalURL = savePolicy.namingPolicy.outputURL(
            for: sourceURL,
            container: resolvedOutputPolicy.container
        )
        let routeSelection = TaptionCodecRoutePlanner.selectRoute(
            for: asset,
            outputCodec: resolvedOutputPolicy.videoCodec,
            requestedMode: preferredMode
        )
        let audioPlan = TaptionAudioTranscodePlanner.makeFirstTrackPlan(
            asset: asset,
            sourceURL: sourceURL,
            outputURL: temporaryOutputURL,
            outputContainer: resolvedOutputPolicy.container
        )
        let videoCommandPlan = makeVideoCommandPlanIfAvailable(
            sourceURL: sourceURL,
            outputURL: temporaryOutputURL,
            routeSelection: routeSelection,
            outputPolicy: resolvedOutputPolicy,
            audioPlan: audioPlan
        )
        return TaptionEncodingPlan(
            input: TaptionEncodingInput(kind: .singleAsset, assetID: asset.id),
            outputPolicy: resolvedOutputPolicy,
            codecRoute: routeSelection.route,
            codecExecutionKind: routeSelection.executionKind,
            videoCommandPlan: videoCommandPlan,
            audioPlan: audioPlan,
            savePolicy: savePolicy,
            encoderSelection: routeSelection.encoderSelection,
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryOutputURL,
            finalOutputURL: finalURL
        )
    }

    private static func makeVideoCommandPlanIfAvailable(
        sourceURL: URL,
        outputURL: URL,
        routeSelection: TaptionCodecRouteSelection,
        outputPolicy: TaptionVideoOutputPolicy,
        audioPlan: TaptionAudioTranscodePlan?
    ) -> SW_FFmpegCommandPlan? {
        let readiness = TaptionVideoCodecExecutionReadinessReporter.item(
            for: routeSelection.route,
            outputContainer: outputPolicy.container
        )
        guard readiness.hasCommandPlan else {
            return nil
        }

        return try? SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: sourceURL,
                outputURL: outputURL,
                route: routeSelection.route,
                options: TaptionCodecTranscodeOptions(
                    outputPolicy: outputPolicy,
                    preserveSourceVisualQuality: true,
                    preserveAudioWhenPossible: audioPlan != nil
                )
            ),
            audioPlan: audioPlan
        )
    }
}

enum TaptionEncoderRecommendation {
    static func recommendedSelection(
        canUseHardwareHEVC: Bool,
        allowsSoftwareFallback: Bool = true
    ) -> TaptionEncoderSelection {
        if canUseHardwareHEVC {
            return TaptionEncoderSelection(
                requestedMode: .automatic,
                backend: .appleVideoToolbox,
                reason: "Hardware encoding will be used automatically when available."
            )
        }

        if allowsSoftwareFallback {
            return TaptionEncoderSelection(
                requestedMode: .automatic,
                backend: .customSoftware,
                reason: "Software fallback will be used automatically when needed."
            )
        }

        return TaptionEncoderSelection(
            requestedMode: .automatic,
            backend: nil,
            reason: "No compatible encoder was selected."
        )
    }
}
