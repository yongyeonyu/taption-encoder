import Foundation

struct TaptionCodecRoute: Codable, Hashable {
    var sourceCodec: TaptionVideoCodec
    var outputCodec: TaptionVideoCodec

    init(sourceCodec: TaptionVideoCodec, outputCodec: TaptionVideoCodec) {
        self.sourceCodec = sourceCodec
        self.outputCodec = outputCodec
    }

    var isSameCodecReencode: Bool {
        sourceCodec == outputCodec
    }

    var displayName: String {
        "\(sourceCodec.displayName) to \(outputCodec.displayName)"
    }
}

struct TaptionCodecAlgorithmDescriptor: Equatable {
    var route: TaptionCodecRoute
    var mode: TaptionEncoderMode
    var backend: TaptionEncodingBackend
    var displayName: String

    init(
        route: TaptionCodecRoute,
        mode: TaptionEncoderMode,
        backend: TaptionEncodingBackend,
        displayName: String
    ) {
        self.route = route
        self.mode = mode
        self.backend = backend
        self.displayName = displayName
    }

    init(
        sourceCodec: TaptionVideoCodec,
        outputCodec: TaptionVideoCodec,
        mode: TaptionEncoderMode,
        backend: TaptionEncodingBackend,
        displayName: String
    ) {
        self.init(
            route: TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec),
            mode: mode,
            backend: backend,
            displayName: displayName
        )
    }

    var sourceCodec: TaptionVideoCodec {
        route.sourceCodec
    }

    var outputCodec: TaptionVideoCodec {
        route.outputCodec
    }
}

protocol TaptionCodecAlgorithm {
    static var descriptor: TaptionCodecAlgorithmDescriptor { get }
}

protocol TaptionStaticCodecTranscodingAlgorithm: TaptionCodecAlgorithm, Sendable {
    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput
}

struct TaptionCodecTranscodeOptions: Codable, Equatable {
    var outputPolicy: TaptionVideoOutputPolicy
    var preserveSourceVisualQuality: Bool
    var preserveAudioWhenPossible: Bool

    init(
        outputPolicy: TaptionVideoOutputPolicy = TaptionVideoOutputPolicy(),
        preserveSourceVisualQuality: Bool = true,
        preserveAudioWhenPossible: Bool = true
    ) {
        self.outputPolicy = outputPolicy
        self.preserveSourceVisualQuality = preserveSourceVisualQuality
        self.preserveAudioWhenPossible = preserveAudioWhenPossible
    }

    static func preservingSource(
        outputCodec: TaptionVideoCodec = .hevc,
        outputAudioCodec: TaptionAudioCodec = TaptionAudioCodecRoutePlanner.defaultOutputCodec,
        container: TaptionVideoContainer = .mp4
    ) -> TaptionCodecTranscodeOptions {
        TaptionCodecTranscodeOptions(
            outputPolicy: TaptionVideoOutputPolicy(
                videoCodec: outputCodec,
                audioCodec: outputAudioCodec,
                container: container,
                qualityPolicy: .preserveSourceVisuals,
                advancedOptions: .preserveSource
            )
        )
    }
}

struct TaptionCodecTranscodeRequest: Codable, Equatable {
    var sourceURL: URL
    var outputURL: URL
    var route: TaptionCodecRoute
    var options: TaptionCodecTranscodeOptions

    init(
        sourceURL: URL,
        outputURL: URL,
        route: TaptionCodecRoute,
        options: TaptionCodecTranscodeOptions = .preservingSource()
    ) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.route = route
        self.options = options
    }
}

struct TaptionCodecTranscodeOutput: Codable, Equatable {
    var outputURL: URL
    var route: TaptionCodecRoute
    var usedMode: TaptionEncoderMode
    var usedBackend: TaptionEncodingBackend
    var outputVideoCodec: TaptionVideoCodec
    var outputAudioTrackCount: Int
}

protocol TaptionCodecTranscodingAlgorithm: TaptionCodecAlgorithm {
    func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput
}

enum TaptionCodecRouteSupport: String, Codable, Equatable {
    case implemented
    case planned
    case unsupported
}

enum TaptionCodecRegistry {
    // The universal codec goal is all-to-all conversion, not only all-to-HEVC.
    // 1.0 exposes HEVC output first, while the core keeps source/output routes generic.
    static let universalProductContractName = "All-to-All Universal Codec Mesh"

    static let universalTranscodeCodecs: [TaptionVideoCodec] = [
        .av1,
        .hevc,
        .hevcWithAlpha,
        .dolbyVisionHEVC,
        .h264,
        .vp9,
        .vp8,
        .proRes,
        .proResRaw,
        .mpeg2,
        .mpeg1,
        .mpeg4Visual,
        .h263,
        .motionJPEG,
        .jpeg,
        .jpegXL,
        .animation,
        .cinepak,
        .sorensonVideo,
        .sorensonVideo3,
        .theora,
        .realVideo,
        .roqVideo,
        .dv,
        .dvcPro,
        .dvcProHD,
        .vc1,
        .wmv,
        .rawVideo
    ]

    static let firstReleaseOutputCodecs: [TaptionVideoCodec] = [
        .hevc
    ]

    static var universalSourceCodecs: [TaptionVideoCodec] {
        universalTranscodeCodecs
    }

    static var universalOutputCodecs: [TaptionVideoCodec] {
        universalTranscodeCodecs
    }

    static var universalRoutePairs: Set<TaptionCodecRoute> {
        Set(universalSourceCodecs.flatMap { sourceCodec in
            universalOutputCodecs.map { outputCodec in
                TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
            }
        })
    }

    static var universalRoutePairCount: Int {
        universalSourceCodecs.count * universalOutputCodecs.count
    }

    static let universalContractExampleRoutes: [TaptionCodecRoute] = [
        TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc),
        TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1),
        TaptionCodecRoute(sourceCodec: .av1, outputCodec: .h264),
        TaptionCodecRoute(sourceCodec: .hevc, outputCodec: .vp9),
        TaptionCodecRoute(sourceCodec: .vp9, outputCodec: .hevc),
        TaptionCodecRoute(sourceCodec: .h264, outputCodec: .h264)
    ]

    static let softwareImplementedRoutes: Set<TaptionCodecRoute> = [
        TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)
    ]

    static let appleNativeHEVCHardwareSourceCodecs: [TaptionVideoCodec] = [
        .h264,
        .hevc,
        .proRes
    ]

    static var appleNativeHEVCHardwareRoutes: Set<TaptionCodecRoute> {
        Set(appleNativeHEVCHardwareSourceCodecs.map {
            TaptionCodecRoute(sourceCodec: $0, outputCodec: .hevc)
        })
    }

    static var appleNativeHEVCHardwareAlgorithmDescriptors: [TaptionCodecAlgorithmDescriptor] {
        appleNativeHEVCHardwareSourceCodecs.map { sourceCodec in
            TaptionCodecAlgorithmDescriptor(
                sourceCodec: sourceCodec,
                outputCodec: .hevc,
                mode: .hardware,
                backend: .appleVideoToolbox,
                displayName: "\(sourceCodec.shortDisplayName) to H.265 Hardware"
            )
        }
    }

    static var hardwareImplementedRoutes: Set<TaptionCodecRoute> {
        softwareImplementedRoutes.union(appleNativeHEVCHardwareRoutes)
    }

    static var implementedRoutes: Set<TaptionCodecRoute> {
        softwareImplementedRoutes.union(hardwareImplementedRoutes)
    }

    static var implementedAlgorithmDescriptors: [TaptionCodecAlgorithmDescriptor] {
        [
        TaptionCodecAlgorithmDescriptor(
            sourceCodec: .av1,
            outputCodec: .hevc,
            mode: .hardware,
            backend: .appleVideoToolbox,
            displayName: "AV1 to H.265 Hardware"
        ),
        TaptionCodecAlgorithmDescriptor(
            sourceCodec: .av1,
            outputCodec: .hevc,
            mode: .software,
            backend: .softwareAV1Decoder,
            displayName: "AV1 to H.265 Software"
        )
        ] + appleNativeHEVCHardwareAlgorithmDescriptors
    }

    static var plannedUniversalRoutes: Set<TaptionCodecRoute> {
        universalRoutePairs
    }

    static func routeIsInUniversalContract(_ route: TaptionCodecRoute) -> Bool {
        plannedUniversalRoutes.contains(route)
    }

    static func support(for route: TaptionCodecRoute) -> TaptionCodecRouteSupport {
        if implementedRoutes.contains(route) {
            return .implemented
        }
        if plannedUniversalRoutes.contains(route) {
            return .planned
        }
        return .unsupported
    }

    static func implementedAlgorithmDescriptors(
        for route: TaptionCodecRoute
    ) -> [TaptionCodecAlgorithmDescriptor] {
        implementedAlgorithmDescriptors.filter { $0.route == route }
    }

    static func routeHasImplementedAlgorithm(
        _ route: TaptionCodecRoute,
        mode: TaptionEncoderMode
    ) -> Bool {
        implementedAlgorithmDescriptors.contains {
            $0.route == route && $0.mode == mode
        }
    }
}

struct TaptionCodecMeshCoverageReport: Codable, Equatable {
    var contractName: String
    var videoSourceCodecCount: Int
    var videoOutputCodecCount: Int
    var expectedVideoRouteCount: Int
    var plannedVideoRouteCount: Int
    var executableVideoRouteCount: Int
    var plannedButNotExecutableVideoRouteCount: Int
    var sameCodecVideoRouteCount: Int
    var exampleVideoRoutes: [TaptionCodecRoute]
    var missingVideoRoutes: [TaptionCodecRoute]
    var missingVideoReverseRoutes: [TaptionCodecRoute]
    var softwareVideoOutputPlannableCodecCount: Int
    var softwareVideoOutputUnsupportedCodecs: [TaptionVideoCodec]
    var videoRunnableInCurrentBuildRouteCount: Int
    var videoCommandPlanOnlyRouteCount: Int
    var videoBlockedMissingSoftwareEncoderRouteCount: Int
    var videoBlockedOutputCodecs: [TaptionVideoCodec]
    var audioCodecCount: Int
    var expectedAudioRouteCount: Int
    var plannedAudioRouteCount: Int
    var supportedNowAudioRouteCount: Int
    var plannedOnlyAudioRouteCount: Int
    var sameCodecAudioRouteCount: Int
    var missingAudioRoutes: [TaptionAudioCodecRoute]
    var missingAudioReverseRoutes: [TaptionAudioCodecRoute]
    var softwareAudioOutputPlannableCodecCount: Int
    var softwareAudioOutputUnsupportedCodecs: [TaptionAudioCodec]
    var hardwareAudioDescriptorCount: Int
    var softwareAudioDescriptorCount: Int
    var audioRunnableInCurrentBuildRouteCount: Int
    var audioCommandPlanOnlyRouteCount: Int
    var audioBlockedMissingSoftwareEncoderRouteCount: Int
    var audioBlockedOutputCodecs: [TaptionAudioCodec]
    var broadSoftwareBackendDisplayName: String
    var broadSoftwareBackendRequiresLicenseReview: Bool

    var videoSourceAndOutputCatalogsAreSymmetric: Bool {
        videoSourceCodecCount == videoOutputCodecCount
            && missingVideoReverseRoutes.isEmpty
    }

    var videoMeshIsFullyPlanned: Bool {
        plannedVideoRouteCount == expectedVideoRouteCount
            && missingVideoRoutes.isEmpty
            && missingVideoReverseRoutes.isEmpty
    }

    var audioMeshIsFullyPlanned: Bool {
        plannedAudioRouteCount == expectedAudioRouteCount
            && missingAudioRoutes.isEmpty
            && missingAudioReverseRoutes.isEmpty
    }

    var planningCoverageIsPassing: Bool {
        videoSourceAndOutputCatalogsAreSymmetric
            && videoMeshIsFullyPlanned
            && audioMeshIsFullyPlanned
    }
}

enum TaptionUniversalCodecCompletionStage: String, Codable, Equatable {
    case launchRouteOnly
    case allToAllPlanningLocked
    case allToAllCommandPlansReady
    case allToAllExecutable
}

struct TaptionUniversalCodecCompletionAuditReport: Codable, Equatable {
    var contractName: String
    var stage: TaptionUniversalCodecCompletionStage
    var planningCoverageIsPassing: Bool
    var requiredBidirectionalVideoRoutes: [TaptionCodecRoute]
    var missingRequiredBidirectionalVideoRoutes: [TaptionCodecRoute]
    var videoRouteCount: Int
    var audioRouteCount: Int
    var videoCurrentBuildRunnableRouteCount: Int
    var audioCurrentBuildRunnableRouteCount: Int
    var videoPendingRuntimeRouteCount: Int
    var audioPendingRuntimeRouteCount: Int
    var videoCommandPlanOnlyRouteCount: Int
    var audioCommandPlanOnlyRouteCount: Int
    var videoBlockedMissingSoftwareEncoderRouteCount: Int
    var audioBlockedMissingSoftwareEncoderRouteCount: Int
    var videoBlockedOutputCodecs: [TaptionVideoCodec]
    var audioBlockedOutputCodecs: [TaptionAudioCodec]
    var videoOutputSelectionCount: Int
    var audioOutputSelectionCount: Int
    var videoOutputImplementedSelectionCount: Int
    var audioOutputImplementedSelectionCount: Int
    var videoOutputCommandPlanReadySelectionCount: Int
    var audioOutputCommandPlanReadySelectionCount: Int
    var videoOutputPlannedSelectionCount: Int
    var audioOutputPlannedSelectionCount: Int
    var videoOutputBlockedSelectionCount: Int
    var audioOutputBlockedSelectionCount: Int
    var videoOutputSelectionCoverageIsPassing: Bool
    var audioOutputSelectionCoverageIsPassing: Bool
    var outputSelectionCoverageIsPassing: Bool
    var broadSoftwareBackendDisplayName: String
    var broadSoftwareBackendBundled: Bool
    var broadSoftwareBackendExecutable: Bool
    var broadSoftwareBackendOpenGateCount: Int
    var broadSoftwareBackendRequiresLicenseReview: Bool

    init(
        contractName: String,
        stage: TaptionUniversalCodecCompletionStage,
        planningCoverageIsPassing: Bool,
        requiredBidirectionalVideoRoutes: [TaptionCodecRoute],
        missingRequiredBidirectionalVideoRoutes: [TaptionCodecRoute],
        videoRouteCount: Int,
        audioRouteCount: Int,
        videoCurrentBuildRunnableRouteCount: Int,
        audioCurrentBuildRunnableRouteCount: Int,
        videoPendingRuntimeRouteCount: Int,
        audioPendingRuntimeRouteCount: Int,
        videoCommandPlanOnlyRouteCount: Int,
        audioCommandPlanOnlyRouteCount: Int,
        videoBlockedMissingSoftwareEncoderRouteCount: Int,
        audioBlockedMissingSoftwareEncoderRouteCount: Int,
        videoBlockedOutputCodecs: [TaptionVideoCodec],
        audioBlockedOutputCodecs: [TaptionAudioCodec],
        videoOutputSelectionCount: Int,
        audioOutputSelectionCount: Int,
        videoOutputImplementedSelectionCount: Int,
        audioOutputImplementedSelectionCount: Int,
        videoOutputCommandPlanReadySelectionCount: Int,
        audioOutputCommandPlanReadySelectionCount: Int,
        videoOutputPlannedSelectionCount: Int,
        audioOutputPlannedSelectionCount: Int,
        videoOutputBlockedSelectionCount: Int,
        audioOutputBlockedSelectionCount: Int,
        videoOutputSelectionCoverageIsPassing: Bool,
        audioOutputSelectionCoverageIsPassing: Bool,
        broadSoftwareBackendDisplayName: String,
        broadSoftwareBackendBundled: Bool,
        broadSoftwareBackendExecutable: Bool,
        broadSoftwareBackendOpenGateCount: Int,
        broadSoftwareBackendRequiresLicenseReview: Bool
    ) {
        self.contractName = contractName
        self.stage = stage
        self.planningCoverageIsPassing = planningCoverageIsPassing
        self.requiredBidirectionalVideoRoutes = requiredBidirectionalVideoRoutes
        self.missingRequiredBidirectionalVideoRoutes = missingRequiredBidirectionalVideoRoutes
        self.videoRouteCount = videoRouteCount
        self.audioRouteCount = audioRouteCount
        self.videoCurrentBuildRunnableRouteCount = videoCurrentBuildRunnableRouteCount
        self.audioCurrentBuildRunnableRouteCount = audioCurrentBuildRunnableRouteCount
        self.videoPendingRuntimeRouteCount = videoPendingRuntimeRouteCount
        self.audioPendingRuntimeRouteCount = audioPendingRuntimeRouteCount
        self.videoCommandPlanOnlyRouteCount = videoCommandPlanOnlyRouteCount
        self.audioCommandPlanOnlyRouteCount = audioCommandPlanOnlyRouteCount
        self.videoBlockedMissingSoftwareEncoderRouteCount = videoBlockedMissingSoftwareEncoderRouteCount
        self.audioBlockedMissingSoftwareEncoderRouteCount = audioBlockedMissingSoftwareEncoderRouteCount
        self.videoBlockedOutputCodecs = videoBlockedOutputCodecs
        self.audioBlockedOutputCodecs = audioBlockedOutputCodecs
        self.videoOutputSelectionCount = videoOutputSelectionCount
        self.audioOutputSelectionCount = audioOutputSelectionCount
        self.videoOutputImplementedSelectionCount = videoOutputImplementedSelectionCount
        self.audioOutputImplementedSelectionCount = audioOutputImplementedSelectionCount
        self.videoOutputCommandPlanReadySelectionCount = videoOutputCommandPlanReadySelectionCount
        self.audioOutputCommandPlanReadySelectionCount = audioOutputCommandPlanReadySelectionCount
        self.videoOutputPlannedSelectionCount = videoOutputPlannedSelectionCount
        self.audioOutputPlannedSelectionCount = audioOutputPlannedSelectionCount
        self.videoOutputBlockedSelectionCount = videoOutputBlockedSelectionCount
        self.audioOutputBlockedSelectionCount = audioOutputBlockedSelectionCount
        self.videoOutputSelectionCoverageIsPassing = videoOutputSelectionCoverageIsPassing
        self.audioOutputSelectionCoverageIsPassing = audioOutputSelectionCoverageIsPassing
        self.outputSelectionCoverageIsPassing = videoOutputSelectionCoverageIsPassing
            && audioOutputSelectionCoverageIsPassing
        self.broadSoftwareBackendDisplayName = broadSoftwareBackendDisplayName
        self.broadSoftwareBackendBundled = broadSoftwareBackendBundled
        self.broadSoftwareBackendExecutable = broadSoftwareBackendExecutable
        self.broadSoftwareBackendOpenGateCount = broadSoftwareBackendOpenGateCount
        self.broadSoftwareBackendRequiresLicenseReview = broadSoftwareBackendRequiresLicenseReview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outputReadinessCatalog = TaptionCodecOutputCatalog.makeReadinessReport()
        let audioOutputReadinessCatalog = TaptionAudioCodecOutputCatalog.makeReadinessReport()

        self.init(
            contractName: try container.decode(String.self, forKey: .contractName),
            stage: try container.decode(TaptionUniversalCodecCompletionStage.self, forKey: .stage),
            planningCoverageIsPassing: try container.decode(Bool.self, forKey: .planningCoverageIsPassing),
            requiredBidirectionalVideoRoutes: try container.decode([TaptionCodecRoute].self, forKey: .requiredBidirectionalVideoRoutes),
            missingRequiredBidirectionalVideoRoutes: try container.decode([TaptionCodecRoute].self, forKey: .missingRequiredBidirectionalVideoRoutes),
            videoRouteCount: try container.decode(Int.self, forKey: .videoRouteCount),
            audioRouteCount: try container.decode(Int.self, forKey: .audioRouteCount),
            videoCurrentBuildRunnableRouteCount: try container.decode(Int.self, forKey: .videoCurrentBuildRunnableRouteCount),
            audioCurrentBuildRunnableRouteCount: try container.decode(Int.self, forKey: .audioCurrentBuildRunnableRouteCount),
            videoPendingRuntimeRouteCount: try container.decode(Int.self, forKey: .videoPendingRuntimeRouteCount),
            audioPendingRuntimeRouteCount: try container.decode(Int.self, forKey: .audioPendingRuntimeRouteCount),
            videoCommandPlanOnlyRouteCount: try container.decode(Int.self, forKey: .videoCommandPlanOnlyRouteCount),
            audioCommandPlanOnlyRouteCount: try container.decode(Int.self, forKey: .audioCommandPlanOnlyRouteCount),
            videoBlockedMissingSoftwareEncoderRouteCount: try container.decode(Int.self, forKey: .videoBlockedMissingSoftwareEncoderRouteCount),
            audioBlockedMissingSoftwareEncoderRouteCount: try container.decode(Int.self, forKey: .audioBlockedMissingSoftwareEncoderRouteCount),
            videoBlockedOutputCodecs: try container.decode([TaptionVideoCodec].self, forKey: .videoBlockedOutputCodecs),
            audioBlockedOutputCodecs: try container.decode([TaptionAudioCodec].self, forKey: .audioBlockedOutputCodecs),
            videoOutputSelectionCount: try container.decodeIfPresent(Int.self, forKey: .videoOutputSelectionCount) ?? outputReadinessCatalog.outputSelectionCount,
            audioOutputSelectionCount: try container.decodeIfPresent(Int.self, forKey: .audioOutputSelectionCount) ?? audioOutputReadinessCatalog.outputSelectionCount,
            videoOutputImplementedSelectionCount: try container.decodeIfPresent(Int.self, forKey: .videoOutputImplementedSelectionCount) ?? outputReadinessCatalog.implementedOutputSelectionCount,
            audioOutputImplementedSelectionCount: try container.decodeIfPresent(Int.self, forKey: .audioOutputImplementedSelectionCount) ?? audioOutputReadinessCatalog.implementedOutputSelectionCount,
            videoOutputCommandPlanReadySelectionCount: try container.decodeIfPresent(Int.self, forKey: .videoOutputCommandPlanReadySelectionCount) ?? outputReadinessCatalog.commandPlanReadyOutputSelectionCount,
            audioOutputCommandPlanReadySelectionCount: try container.decodeIfPresent(Int.self, forKey: .audioOutputCommandPlanReadySelectionCount) ?? audioOutputReadinessCatalog.commandPlanReadyOutputSelectionCount,
            videoOutputPlannedSelectionCount: try container.decodeIfPresent(Int.self, forKey: .videoOutputPlannedSelectionCount) ?? outputReadinessCatalog.plannedOutputSelectionCount,
            audioOutputPlannedSelectionCount: try container.decodeIfPresent(Int.self, forKey: .audioOutputPlannedSelectionCount) ?? audioOutputReadinessCatalog.plannedOutputSelectionCount,
            videoOutputBlockedSelectionCount: try container.decodeIfPresent(Int.self, forKey: .videoOutputBlockedSelectionCount) ?? outputReadinessCatalog.unsupportedOutputSelectionCount,
            audioOutputBlockedSelectionCount: try container.decodeIfPresent(Int.self, forKey: .audioOutputBlockedSelectionCount) ?? audioOutputReadinessCatalog.unsupportedOutputSelectionCount,
            videoOutputSelectionCoverageIsPassing: try container.decodeIfPresent(Bool.self, forKey: .videoOutputSelectionCoverageIsPassing) ?? outputReadinessCatalog.outputSelectionCoverageIsPassing,
            audioOutputSelectionCoverageIsPassing: try container.decodeIfPresent(Bool.self, forKey: .audioOutputSelectionCoverageIsPassing) ?? audioOutputReadinessCatalog.outputSelectionCoverageIsPassing,
            broadSoftwareBackendDisplayName: try container.decode(String.self, forKey: .broadSoftwareBackendDisplayName),
            broadSoftwareBackendBundled: try container.decode(Bool.self, forKey: .broadSoftwareBackendBundled),
            broadSoftwareBackendExecutable: try container.decode(Bool.self, forKey: .broadSoftwareBackendExecutable),
            broadSoftwareBackendOpenGateCount: try container.decode(Int.self, forKey: .broadSoftwareBackendOpenGateCount),
            broadSoftwareBackendRequiresLicenseReview: try container.decode(Bool.self, forKey: .broadSoftwareBackendRequiresLicenseReview)
        )
    }

    var universalPlanningIsLocked: Bool {
        planningCoverageIsPassing
            && outputSelectionCoverageIsPassing
            && missingRequiredBidirectionalVideoRoutes.isEmpty
    }

    var universalCommandPlanningIsComplete: Bool {
        universalPlanningIsLocked
            && videoBlockedMissingSoftwareEncoderRouteCount == 0
            && audioBlockedMissingSoftwareEncoderRouteCount == 0
    }

    var universalExecutionIsComplete: Bool {
        universalCommandPlanningIsComplete
            && broadSoftwareBackendExecutable
            && videoPendingRuntimeRouteCount == 0
            && audioPendingRuntimeRouteCount == 0
    }
}

enum TaptionUniversalCodecCompletionAuditor {
    static let requiredBidirectionalVideoRoutes: [TaptionCodecRoute] = [
        TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1),
        TaptionCodecRoute(sourceCodec: .av1, outputCodec: .h264),
        TaptionCodecRoute(sourceCodec: .hevc, outputCodec: .av1),
        TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc),
        TaptionCodecRoute(sourceCodec: .h264, outputCodec: .h264)
    ]

    static func makeReport(
        backendReadiness: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(),
        meshReport: TaptionCodecMeshCoverageReport = TaptionCodecMeshCoverageReporter.makeReport()
    ) -> TaptionUniversalCodecCompletionAuditReport {
        let broadSoftwareBackendExecutable = backendReadiness.isExecutableInCurrentBuild
        let videoExecutionReport = TaptionVideoCodecExecutionReadinessReporter.makeReport(
            outputContainer: .mkv,
            broadSoftwareBackendExecutable: broadSoftwareBackendExecutable
        )
        let audioExecutionReport = TaptionAudioCodecExecutionReadinessReporter.makeReport(
            outputContainer: .mkv,
            broadSoftwareBackendExecutable: broadSoftwareBackendExecutable
        )
        let outputReadinessCatalog = TaptionCodecOutputCatalog.makeReadinessReport()
        let audioOutputReadinessCatalog = TaptionAudioCodecOutputCatalog.makeReadinessReport()
        let missingRequiredRoutes = requiredBidirectionalVideoRoutes.filter {
            !TaptionCodecRegistry.plannedUniversalRoutes.contains($0)
        }
        let videoPendingRuntimeRouteCount = videoExecutionReport.routeCount
            - videoExecutionReport.runnableInCurrentBuildRouteCount
        let audioPendingRuntimeRouteCount = audioExecutionReport.routeCount
            - audioExecutionReport.runnableInCurrentBuildRouteCount
        let outputSelectionCoverageIsPassing = outputReadinessCatalog.outputSelectionCoverageIsPassing
            && audioOutputReadinessCatalog.outputSelectionCoverageIsPassing
        let planningIsLocked = meshReport.planningCoverageIsPassing
            && outputSelectionCoverageIsPassing
            && missingRequiredRoutes.isEmpty
        let commandPlanningIsComplete = planningIsLocked
            && videoExecutionReport.blockedMissingSoftwareEncoderRouteCount == 0
            && audioExecutionReport.blockedMissingSoftwareEncoderRouteCount == 0
        let executionIsComplete = commandPlanningIsComplete
            && broadSoftwareBackendExecutable
            && videoPendingRuntimeRouteCount == 0
            && audioPendingRuntimeRouteCount == 0

        return TaptionUniversalCodecCompletionAuditReport(
            contractName: TaptionCodecRegistry.universalProductContractName,
            stage: stage(
                planningIsLocked: planningIsLocked,
                commandPlanningIsComplete: commandPlanningIsComplete,
                executionIsComplete: executionIsComplete
            ),
            planningCoverageIsPassing: meshReport.planningCoverageIsPassing,
            requiredBidirectionalVideoRoutes: requiredBidirectionalVideoRoutes,
            missingRequiredBidirectionalVideoRoutes: meshReport
                .missingVideoRoutes
                .filter { requiredBidirectionalVideoRoutes.contains($0) }
                + missingRequiredRoutes,
            videoRouteCount: videoExecutionReport.routeCount,
            audioRouteCount: audioExecutionReport.routeCount,
            videoCurrentBuildRunnableRouteCount: videoExecutionReport.runnableInCurrentBuildRouteCount,
            audioCurrentBuildRunnableRouteCount: audioExecutionReport.runnableInCurrentBuildRouteCount,
            videoPendingRuntimeRouteCount: videoPendingRuntimeRouteCount,
            audioPendingRuntimeRouteCount: audioPendingRuntimeRouteCount,
            videoCommandPlanOnlyRouteCount: videoExecutionReport.commandPlanOnlyRouteCount,
            audioCommandPlanOnlyRouteCount: audioExecutionReport.commandPlanOnlyRouteCount,
            videoBlockedMissingSoftwareEncoderRouteCount: videoExecutionReport.blockedMissingSoftwareEncoderRouteCount,
            audioBlockedMissingSoftwareEncoderRouteCount: audioExecutionReport.blockedMissingSoftwareEncoderRouteCount,
            videoBlockedOutputCodecs: videoExecutionReport.blockedOutputCodecs,
            audioBlockedOutputCodecs: audioExecutionReport.blockedOutputCodecs,
            videoOutputSelectionCount: outputReadinessCatalog.outputSelectionCount,
            audioOutputSelectionCount: audioOutputReadinessCatalog.outputSelectionCount,
            videoOutputImplementedSelectionCount: outputReadinessCatalog.implementedOutputSelectionCount,
            audioOutputImplementedSelectionCount: audioOutputReadinessCatalog.implementedOutputSelectionCount,
            videoOutputCommandPlanReadySelectionCount: outputReadinessCatalog.commandPlanReadyOutputSelectionCount,
            audioOutputCommandPlanReadySelectionCount: audioOutputReadinessCatalog.commandPlanReadyOutputSelectionCount,
            videoOutputPlannedSelectionCount: outputReadinessCatalog.plannedOutputSelectionCount,
            audioOutputPlannedSelectionCount: audioOutputReadinessCatalog.plannedOutputSelectionCount,
            videoOutputBlockedSelectionCount: outputReadinessCatalog.unsupportedOutputSelectionCount,
            audioOutputBlockedSelectionCount: audioOutputReadinessCatalog.unsupportedOutputSelectionCount,
            videoOutputSelectionCoverageIsPassing: outputReadinessCatalog.outputSelectionCoverageIsPassing,
            audioOutputSelectionCoverageIsPassing: audioOutputReadinessCatalog.outputSelectionCoverageIsPassing,
            broadSoftwareBackendDisplayName: backendReadiness.displayName,
            broadSoftwareBackendBundled: backendReadiness.isBundledInCurrentBuild,
            broadSoftwareBackendExecutable: broadSoftwareBackendExecutable,
            broadSoftwareBackendOpenGateCount: backendReadiness.openGates.count,
            broadSoftwareBackendRequiresLicenseReview: meshReport.broadSoftwareBackendRequiresLicenseReview
        )
    }

    private static func stage(
        planningIsLocked: Bool,
        commandPlanningIsComplete: Bool,
        executionIsComplete: Bool
    ) -> TaptionUniversalCodecCompletionStage {
        if executionIsComplete {
            return .allToAllExecutable
        }
        if commandPlanningIsComplete {
            return .allToAllCommandPlansReady
        }
        if planningIsLocked {
            return .allToAllPlanningLocked
        }
        return .launchRouteOnly
    }
}

enum TaptionCodecMeshCoverageReporter {
    static func makeReport() -> TaptionCodecMeshCoverageReport {
        let videoSourceCodecs = TaptionCodecRegistry.universalSourceCodecs
        let videoOutputCodecs = TaptionCodecRegistry.universalOutputCodecs
        let expectedVideoRoutes = videoSourceCodecs.flatMap { sourceCodec in
            videoOutputCodecs.map { outputCodec in
                TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
            }
        }
        let missingVideoRoutes = expectedVideoRoutes.filter {
            TaptionCodecRegistry.support(for: $0) == .unsupported
        }
        let missingVideoReverseRoutes = expectedVideoRoutes.filter { route in
            !TaptionCodecRegistry.plannedUniversalRoutes.contains(
                TaptionCodecRoute(
                    sourceCodec: route.outputCodec,
                    outputCodec: route.sourceCodec
                )
            )
        }
        let videoExecutionReport = TaptionVideoCodecExecutionReadinessReporter.makeReport(
            outputContainer: .mkv
        )

        let audioCodecs = TaptionAudioCodecRoutePlanner.universalAudioCodecs
        let expectedAudioRoutes = audioCodecs.flatMap { sourceCodec in
            audioCodecs.map { outputCodec in
                TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
            }
        }
        let audioSelections = expectedAudioRoutes.map {
            TaptionAudioCodecRoutePlanner.selectRoute(
                sourceCodec: $0.sourceCodec,
                outputCodec: $0.outputCodec,
                outputContainer: .mp4
            )
        }
        let missingAudioRoutes = expectedAudioRoutes.filter {
            !TaptionAudioCodecRoutePlanner.plannedUniversalRoutes.contains($0)
        }
        let missingAudioReverseRoutes = expectedAudioRoutes.filter { route in
            !TaptionAudioCodecRoutePlanner.plannedUniversalRoutes.contains(
                TaptionAudioCodecRoute(
                    sourceCodec: route.outputCodec,
                    outputCodec: route.sourceCodec
                )
            )
        }
        let audioExecutionReport = TaptionAudioCodecExecutionReadinessReporter.makeReport(
            outputContainer: .mkv
        )
        let audioDescriptorRegistry = TaptionAudioCodecDescriptorRegistry()

        return TaptionCodecMeshCoverageReport(
            contractName: TaptionCodecRegistry.universalProductContractName,
            videoSourceCodecCount: videoSourceCodecs.count,
            videoOutputCodecCount: videoOutputCodecs.count,
            expectedVideoRouteCount: expectedVideoRoutes.count,
            plannedVideoRouteCount: TaptionCodecRegistry.plannedUniversalRoutes.count,
            executableVideoRouteCount: videoExecutionReport.runnableInCurrentBuildRouteCount,
            plannedButNotExecutableVideoRouteCount: expectedVideoRoutes.count - videoExecutionReport.runnableInCurrentBuildRouteCount,
            sameCodecVideoRouteCount: expectedVideoRoutes.filter(\.isSameCodecReencode).count,
            exampleVideoRoutes: TaptionCodecRegistry.universalContractExampleRoutes,
            missingVideoRoutes: sortVideoRoutes(missingVideoRoutes),
            missingVideoReverseRoutes: sortVideoRoutes(missingVideoReverseRoutes),
            softwareVideoOutputPlannableCodecCount: SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs.count,
            softwareVideoOutputUnsupportedCodecs: SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs,
            videoRunnableInCurrentBuildRouteCount: videoExecutionReport.runnableInCurrentBuildRouteCount,
            videoCommandPlanOnlyRouteCount: videoExecutionReport.commandPlanOnlyRouteCount,
            videoBlockedMissingSoftwareEncoderRouteCount: videoExecutionReport.blockedMissingSoftwareEncoderRouteCount,
            videoBlockedOutputCodecs: videoExecutionReport.blockedOutputCodecs,
            audioCodecCount: audioCodecs.count,
            expectedAudioRouteCount: expectedAudioRoutes.count,
            plannedAudioRouteCount: TaptionAudioCodecRoutePlanner.plannedUniversalRoutes.count,
            supportedNowAudioRouteCount: audioSelections.filter(\.isSupportedNow).count,
            plannedOnlyAudioRouteCount: audioSelections.filter { $0.support == .planned }.count,
            sameCodecAudioRouteCount: expectedAudioRoutes.filter { $0.sourceCodec == $0.outputCodec }.count,
            missingAudioRoutes: sortAudioRoutes(missingAudioRoutes),
            missingAudioReverseRoutes: sortAudioRoutes(missingAudioReverseRoutes),
            softwareAudioOutputPlannableCodecCount: SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs.count,
            softwareAudioOutputUnsupportedCodecs: SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs,
            hardwareAudioDescriptorCount: audioDescriptorRegistry.hardwareDescriptors.count,
            softwareAudioDescriptorCount: audioDescriptorRegistry.softwareDescriptors.count,
            audioRunnableInCurrentBuildRouteCount: audioExecutionReport.runnableInCurrentBuildRouteCount,
            audioCommandPlanOnlyRouteCount: audioExecutionReport.commandPlanOnlyRouteCount,
            audioBlockedMissingSoftwareEncoderRouteCount: audioExecutionReport.blockedMissingSoftwareEncoderRouteCount,
            audioBlockedOutputCodecs: audioExecutionReport.blockedOutputCodecs,
            broadSoftwareBackendDisplayName: SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.displayName,
            broadSoftwareBackendRequiresLicenseReview: SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.requiresLicenseReview
        )
    }

    private static func sortVideoRoutes(
        _ routes: [TaptionCodecRoute]
    ) -> [TaptionCodecRoute] {
        routes.sorted {
            if $0.sourceCodec.rawValue == $1.sourceCodec.rawValue {
                return $0.outputCodec.rawValue < $1.outputCodec.rawValue
            }
            return $0.sourceCodec.rawValue < $1.sourceCodec.rawValue
        }
    }

    private static func sortAudioRoutes(
        _ routes: [TaptionAudioCodecRoute]
    ) -> [TaptionAudioCodecRoute] {
        routes.sorted {
            if $0.sourceCodec.rawValue == $1.sourceCodec.rawValue {
                return $0.outputCodec.rawValue < $1.outputCodec.rawValue
            }
            return $0.sourceCodec.rawValue < $1.sourceCodec.rawValue
        }
    }
}
