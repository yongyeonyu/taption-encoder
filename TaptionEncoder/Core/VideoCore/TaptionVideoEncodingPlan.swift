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

    init(
        resizeTo: TaptionPixelSize? = nil,
        frameRate: TaptionRationalFrameRate? = nil,
        targetBitrate: Int? = nil,
        color: TaptionColorDescription? = nil
    ) {
        self.resizeTo = resizeTo
        self.frameRate = frameRate
        self.targetBitrate = targetBitrate
        self.color = color
    }

    static let preserveSource = TaptionAdvancedOutputOptions()
}

struct TaptionHEVCOutputPolicy: Codable, Equatable {
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
        requestedMode: TaptionEncoderMode = .hardware,
        backend: TaptionEncodingBackend? = nil,
        reason: String = "Hardware encoding is recommended when available."
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
    var outputPolicy: TaptionHEVCOutputPolicy
    var savePolicy: TaptionSavePolicy
    var encoderSelection: TaptionEncoderSelection
    var sourceURL: URL?
    var temporaryOutputURL: URL?
    var finalOutputURL: URL?

    init(
        id: UUID = UUID(),
        input: TaptionEncodingInput,
        outputPolicy: TaptionHEVCOutputPolicy = TaptionHEVCOutputPolicy(),
        savePolicy: TaptionSavePolicy = TaptionSavePolicy(),
        encoderSelection: TaptionEncoderSelection = TaptionEncoderSelection(),
        sourceURL: URL? = nil,
        temporaryOutputURL: URL? = nil,
        finalOutputURL: URL? = nil
    ) {
        self.id = id
        self.input = input
        self.outputPolicy = outputPolicy
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

    init(
        id: UUID = UUID(),
        planID: UUID,
        temporaryOutputURL: URL,
        finalOutputURL: URL? = nil,
        saveDestination: TaptionSaveDestinationKind,
        requiresRewardedAd: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.planID = planID
        self.temporaryOutputURL = temporaryOutputURL
        self.finalOutputURL = finalOutputURL
        self.saveDestination = saveDestination
        self.requiresRewardedAd = requiresRewardedAd
        self.createdAt = createdAt
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
        preferredMode: TaptionEncoderMode = .hardware,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy()
    ) -> TaptionEncodingPlan {
        let outputPolicy = TaptionHEVCOutputPolicy(
            videoCodec: .hevc,
            container: .mp4,
            profile: .automatic,
            qualityPolicy: .preserveSourceVisuals,
            advancedOptions: .preserveSource
        )
        let finalURL = savePolicy.namingPolicy.outputURL(
            for: sourceURL,
            container: outputPolicy.container
        )
        return TaptionEncodingPlan(
            input: TaptionEncodingInput(kind: .singleAsset, assetID: asset.id),
            outputPolicy: outputPolicy,
            savePolicy: savePolicy,
            encoderSelection: TaptionEncoderSelection(requestedMode: preferredMode),
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryOutputURL,
            finalOutputURL: finalURL
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
                requestedMode: .hardware,
                backend: .appleVideoToolbox,
                reason: "Hardware encoding is recommended when available."
            )
        }

        if allowsSoftwareFallback {
            return TaptionEncoderSelection(
                requestedMode: .software,
                backend: .customSoftware,
                reason: "Software encoding keeps older devices supported."
            )
        }

        return TaptionEncoderSelection(
            requestedMode: .automatic,
            backend: nil,
            reason: "No compatible encoder was selected."
        )
    }
}
