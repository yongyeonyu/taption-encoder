import Foundation

struct TaptionAudioCodecAlgorithmDescriptor: Equatable {
    var route: TaptionAudioCodecRoute
    var mode: TaptionEncoderMode
    var backend: TaptionEncodingBackend
    var displayName: String

    init(
        route: TaptionAudioCodecRoute,
        mode: TaptionEncoderMode,
        backend: TaptionEncodingBackend,
        displayName: String
    ) {
        self.route = route
        self.mode = mode
        self.backend = backend
        self.displayName = displayName
    }

    var sourceCodec: TaptionAudioCodec {
        route.sourceCodec
    }

    var outputCodec: TaptionAudioCodec {
        route.outputCodec
    }
}

struct TaptionAudioCodecTranscodeOptions: Codable, Equatable {
    var outputCodec: TaptionAudioCodec
    var outputContainer: TaptionVideoContainer
    var preserveSourceQuality: Bool
    var preserveSampleRate: Bool
    var preserveChannelLayout: Bool
    var targetBitrate: Int?
    var sampleRate: Double?
    var channelCount: Int?

    init(
        outputCodec: TaptionAudioCodec = TaptionAudioCodecRoutePlanner.defaultOutputCodec,
        outputContainer: TaptionVideoContainer = .mp4,
        preserveSourceQuality: Bool = true,
        preserveSampleRate: Bool = true,
        preserveChannelLayout: Bool = true,
        targetBitrate: Int? = nil,
        sampleRate: Double? = nil,
        channelCount: Int? = nil
    ) {
        self.outputCodec = outputCodec
        self.outputContainer = outputContainer
        self.preserveSourceQuality = preserveSourceQuality
        self.preserveSampleRate = preserveSampleRate
        self.preserveChannelLayout = preserveChannelLayout
        self.targetBitrate = targetBitrate
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    static func preservingSource(
        outputCodec: TaptionAudioCodec = TaptionAudioCodecRoutePlanner.defaultOutputCodec,
        outputContainer: TaptionVideoContainer = .mp4
    ) -> TaptionAudioCodecTranscodeOptions {
        TaptionAudioCodecTranscodeOptions(
            outputCodec: outputCodec,
            outputContainer: outputContainer,
            preserveSourceQuality: true,
            preserveSampleRate: true,
            preserveChannelLayout: true,
            targetBitrate: nil,
            sampleRate: nil,
            channelCount: nil
        )
    }
}

enum TaptionSourcePreservingAudioOptionsResolver {
    static func resolvedOptions(
        for sourceTrack: TaptionAudioTrackInfo?,
        requestedOptions: TaptionAudioCodecTranscodeOptions
    ) -> TaptionAudioCodecTranscodeOptions {
        guard let sourceTrack else {
            return requestedOptions
        }

        var resolvedOptions = requestedOptions
        if requestedOptions.preserveSampleRate,
           requestedOptions.sampleRate == nil,
           let sampleRate = sourceTrack.sampleRate,
           sampleRate.isFinite,
           sampleRate > 0 {
            resolvedOptions.sampleRate = sampleRate
        }
        if requestedOptions.preserveChannelLayout,
           requestedOptions.channelCount == nil,
           let channelCount = sourceTrack.channelCount,
           channelCount > 0 {
            resolvedOptions.channelCount = channelCount
        }
        if requestedOptions.preserveSourceQuality,
           requestedOptions.targetBitrate == nil,
           let estimatedBitrate = sourceTrack.estimatedBitrate,
           estimatedBitrate > 0 {
            resolvedOptions.targetBitrate = estimatedBitrate
        }
        return resolvedOptions
    }
}

struct TaptionAudioCodecTranscodeRequest: Codable, Equatable {
    var sourceURL: URL
    var outputURL: URL
    var route: TaptionAudioCodecRoute
    var options: TaptionAudioCodecTranscodeOptions

    init(
        sourceURL: URL,
        outputURL: URL,
        route: TaptionAudioCodecRoute,
        options: TaptionAudioCodecTranscodeOptions = .preservingSource()
    ) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.route = route
        self.options = options
    }
}

struct TaptionAudioCodecTranscodeOutput: Codable, Equatable {
    var outputURL: URL
    var route: TaptionAudioCodecRoute
    var usedMode: TaptionEncoderMode
    var usedBackend: TaptionEncodingBackend
    var outputAudioCodec: TaptionAudioCodec
    var outputContainer: TaptionVideoContainer
}

struct TaptionAudioTranscodePlan: Codable, Equatable {
    var trackIndex: Int
    var sourceTrack: TaptionAudioTrackInfo
    var routeSelection: TaptionAudioCodecRouteSelection
    var readiness: TaptionAudioCodecExecutionReadinessItem
    var options: TaptionAudioCodecTranscodeOptions
    var commandPlan: SW_FFmpegCommandPlan?

    var route: TaptionAudioCodecRoute {
        routeSelection.route
    }

    var shortDisplayName: String {
        routeSelection.shortDisplayName
    }

    var shouldCopy: Bool {
        routeSelection.shouldCopy
    }

    var isRunnableInCurrentBuild: Bool {
        readiness.isRunnableInCurrentBuild
    }
}

enum TaptionAudioTranscodePlanner {
    static func makeFirstTrackPlan(
        asset: TaptionVideoAsset,
        sourceURL: URL,
        outputURL: URL,
        outputCodec: TaptionAudioCodec = TaptionAudioCodecRoutePlanner.defaultOutputCodec,
        outputContainer: TaptionVideoContainer
    ) -> TaptionAudioTranscodePlan? {
        guard let sourceTrack = asset.audioTracks.first else {
            return nil
        }
        return makePlan(
            sourceTrack: sourceTrack,
            trackIndex: 0,
            sourceURL: sourceURL,
            outputURL: outputURL,
            outputCodec: outputCodec,
            outputContainer: outputContainer
        )
    }

    static func makePlan(
        sourceTrack: TaptionAudioTrackInfo,
        trackIndex: Int,
        sourceURL: URL,
        outputURL: URL,
        outputCodec: TaptionAudioCodec = TaptionAudioCodecRoutePlanner.defaultOutputCodec,
        outputContainer: TaptionVideoContainer
    ) -> TaptionAudioTranscodePlan {
        let routeSelection = TaptionAudioCodecRoutePlanner.selectRoute(
            sourceCodec: sourceTrack.codec,
            outputCodec: outputCodec,
            outputContainer: outputContainer
        )
        let readiness = TaptionAudioCodecExecutionReadinessReporter.item(
            for: routeSelection.route,
            outputContainer: outputContainer
        )
        let options = TaptionSourcePreservingAudioOptionsResolver.resolvedOptions(
            for: sourceTrack,
            requestedOptions: .preservingSource(
                outputCodec: outputCodec,
                outputContainer: outputContainer
            )
        )
        let commandPlan = makeCommandPlanIfAvailable(
            sourceURL: sourceURL,
            outputURL: outputURL,
            route: routeSelection.route,
            options: options,
            readiness: readiness
        )

        return TaptionAudioTranscodePlan(
            trackIndex: trackIndex,
            sourceTrack: sourceTrack,
            routeSelection: routeSelection,
            readiness: readiness,
            options: options,
            commandPlan: commandPlan
        )
    }

    private static func makeCommandPlanIfAvailable(
        sourceURL: URL,
        outputURL: URL,
        route: TaptionAudioCodecRoute,
        options: TaptionAudioCodecTranscodeOptions,
        readiness: TaptionAudioCodecExecutionReadinessItem
    ) -> SW_FFmpegCommandPlan? {
        guard readiness.hasCommandPlan else {
            return nil
        }
        return try? SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(
            request: TaptionAudioCodecTranscodeRequest(
                sourceURL: sourceURL,
                outputURL: outputURL,
                route: route,
                options: options
            )
        )
    }
}

protocol TaptionStaticAudioCodecTranscodingAlgorithm: Sendable {
    static func transcode(
        request: TaptionAudioCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionAudioCodecTranscodeOutput
}

enum TaptionAudioCodecExecutionReadiness: String, Codable, Equatable {
    case copyInCurrentBuild
    case nativeTranscodeInCurrentBuild
    case softwareBackendExecutable
    case commandPlanOnly
    case blockedMissingSoftwareEncoder
    case unsupported
}

struct TaptionAudioCodecExecutionReadinessItem: Codable, Equatable, Identifiable {
    var id: String {
        "\(route.sourceCodec.rawValue)-to-\(route.outputCodec.rawValue)-\(outputContainer.rawValue)"
    }

    var route: TaptionAudioCodecRoute
    var outputContainer: TaptionVideoContainer
    var readiness: TaptionAudioCodecExecutionReadiness
    var routeSelection: TaptionAudioCodecRouteSelection
    var decodeBackend: TaptionEncodingBackend?
    var encodeBackend: TaptionEncodingBackend?
    var commandBackend: TaptionEncodingBackend?
    var isRunnableInCurrentBuild: Bool
    var hasCommandPlan: Bool
    var blockingReason: String?
}

struct TaptionAudioCodecExecutionReadinessReport: Codable, Equatable {
    var outputContainer: TaptionVideoContainer
    var routeCount: Int
    var runnableInCurrentBuildRouteCount: Int
    var copyRouteCount: Int
    var nativeTranscodeRouteCount: Int
    var softwareBackendExecutableRouteCount: Int
    var commandPlanOnlyRouteCount: Int
    var blockedMissingSoftwareEncoderRouteCount: Int
    var unsupportedRouteCount: Int
    var commandPlannableOutputCodecs: [TaptionAudioCodec]
    var blockedOutputCodecs: [TaptionAudioCodec]
    var items: [TaptionAudioCodecExecutionReadinessItem]

    var allRoutesHaveExecutionPath: Bool {
        routeCount > 0 && unsupportedRouteCount == 0
    }

    var allRoutesRunnableInCurrentBuild: Bool {
        routeCount > 0 && runnableInCurrentBuildRouteCount == routeCount
    }
}

enum TaptionAudioCodecExecutionReadinessReporter {
    static func makeReport(
        outputContainer: TaptionVideoContainer = .mkv,
        broadSoftwareBackendExecutable: Bool = false
    ) -> TaptionAudioCodecExecutionReadinessReport {
        let items = TaptionAudioCodecRoutePlanner.plannedUniversalRoutes
            .map { route in
                makeItem(
                    route: route,
                    outputContainer: outputContainer,
                    broadSoftwareBackendExecutable: broadSoftwareBackendExecutable
                )
            }
            .sorted {
                if $0.route.sourceCodec.rawValue == $1.route.sourceCodec.rawValue {
                    return $0.route.outputCodec.rawValue < $1.route.outputCodec.rawValue
                }
                return $0.route.sourceCodec.rawValue < $1.route.sourceCodec.rawValue
            }
        let blockedOutputCodecs = Set(items.compactMap { item in
            item.readiness == .blockedMissingSoftwareEncoder ? item.route.outputCodec : nil
        }).sorted { $0.rawValue < $1.rawValue }

        return TaptionAudioCodecExecutionReadinessReport(
            outputContainer: outputContainer,
            routeCount: items.count,
            runnableInCurrentBuildRouteCount: items.filter(\.isRunnableInCurrentBuild).count,
            copyRouteCount: items.filter { $0.readiness == .copyInCurrentBuild }.count,
            nativeTranscodeRouteCount: items.filter { $0.readiness == .nativeTranscodeInCurrentBuild }.count,
            softwareBackendExecutableRouteCount: items.filter { $0.readiness == .softwareBackendExecutable }.count,
            commandPlanOnlyRouteCount: items.filter { $0.readiness == .commandPlanOnly }.count,
            blockedMissingSoftwareEncoderRouteCount: items.filter { $0.readiness == .blockedMissingSoftwareEncoder }.count,
            unsupportedRouteCount: items.filter { $0.readiness == .unsupported }.count,
            commandPlannableOutputCodecs: SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs,
            blockedOutputCodecs: blockedOutputCodecs,
            items: items
        )
    }

    static func item(
        for route: TaptionAudioCodecRoute,
        outputContainer: TaptionVideoContainer = .mkv,
        broadSoftwareBackendExecutable: Bool = false
    ) -> TaptionAudioCodecExecutionReadinessItem {
        makeItem(
            route: route,
            outputContainer: outputContainer,
            broadSoftwareBackendExecutable: broadSoftwareBackendExecutable
        )
    }

    private static func makeItem(
        route: TaptionAudioCodecRoute,
        outputContainer: TaptionVideoContainer,
        broadSoftwareBackendExecutable: Bool
    ) -> TaptionAudioCodecExecutionReadinessItem {
        let selection = TaptionAudioCodecRoutePlanner.selectRoute(
            sourceCodec: route.sourceCodec,
            outputCodec: route.outputCodec,
            outputContainer: outputContainer
        )

        guard selection.support != .unsupported else {
            return item(
                route: route,
                outputContainer: outputContainer,
                selection: selection,
                readiness: .unsupported,
                commandBackend: nil,
                isRunnableInCurrentBuild: false,
                hasCommandPlan: false,
                blockingReason: selection.reason
            )
        }

        if selection.shouldCopy {
            return item(
                route: route,
                outputContainer: outputContainer,
                selection: selection,
                readiness: .copyInCurrentBuild,
                commandBackend: nil,
                isRunnableInCurrentBuild: true,
                hasCommandPlan: true,
                blockingReason: nil
            )
        }

        if selection.support == .nativeTranscode {
            return item(
                route: route,
                outputContainer: outputContainer,
                selection: selection,
                readiness: .nativeTranscodeInCurrentBuild,
                commandBackend: nil,
                isRunnableInCurrentBuild: true,
                hasCommandPlan: false,
                blockingReason: nil
            )
        }

        guard SW_FFmpegCodecCommandPlanner.audioEncoderName(for: route.outputCodec) != nil else {
            return item(
                route: route,
                outputContainer: outputContainer,
                selection: selection,
                readiness: .blockedMissingSoftwareEncoder,
                commandBackend: nil,
                isRunnableInCurrentBuild: false,
                hasCommandPlan: false,
                blockingReason: "\(route.outputCodec.displayName) has no selected software audio encoder in the current command plan."
            )
        }

        return item(
            route: route,
            outputContainer: outputContainer,
            selection: selection,
            readiness: broadSoftwareBackendExecutable ? .softwareBackendExecutable : .commandPlanOnly,
            commandBackend: .ffmpegFamily,
            isRunnableInCurrentBuild: broadSoftwareBackendExecutable,
            hasCommandPlan: true,
            blockingReason: broadSoftwareBackendExecutable
                ? nil
                : "The FFmpeg-family backend command can be planned, but the backend is not bundled in this build."
        )
    }

    private static func item(
        route: TaptionAudioCodecRoute,
        outputContainer: TaptionVideoContainer,
        selection: TaptionAudioCodecRouteSelection,
        readiness: TaptionAudioCodecExecutionReadiness,
        commandBackend: TaptionEncodingBackend?,
        isRunnableInCurrentBuild: Bool,
        hasCommandPlan: Bool,
        blockingReason: String?
    ) -> TaptionAudioCodecExecutionReadinessItem {
        TaptionAudioCodecExecutionReadinessItem(
            route: route,
            outputContainer: outputContainer,
            readiness: readiness,
            routeSelection: selection,
            decodeBackend: selection.decodeBackend,
            encodeBackend: selection.encodeBackend,
            commandBackend: commandBackend,
            isRunnableInCurrentBuild: isRunnableInCurrentBuild,
            hasCommandPlan: hasCommandPlan,
            blockingReason: blockingReason
        )
    }
}

struct TaptionAudioCodecDescriptorRegistry: Equatable {
    var outputContainer: TaptionVideoContainer
    var broadSoftwareBackendExecutable: Bool

    init(
        outputContainer: TaptionVideoContainer = .mkv,
        broadSoftwareBackendExecutable: Bool = false
    ) {
        self.outputContainer = outputContainer
        self.broadSoftwareBackendExecutable = broadSoftwareBackendExecutable
    }

    static let live = TaptionAudioCodecDescriptorRegistry()

    var hardwareDescriptors: [TaptionAudioCodecAlgorithmDescriptor] {
        HW_AudioCodecAlgorithmCatalog.descriptors(outputContainer: outputContainer)
    }

    var softwareDescriptors: [TaptionAudioCodecAlgorithmDescriptor] {
        SW_UniversalAudioCodecTranscodeAlgorithm.plannedDescriptors
    }

    var allDescriptors: [TaptionAudioCodecAlgorithmDescriptor] {
        hardwareDescriptors + softwareDescriptors
    }

    func descriptors(
        for route: TaptionAudioCodecRoute
    ) -> [TaptionAudioCodecAlgorithmDescriptor] {
        allDescriptors.filter { $0.route == route }
    }

    func preferredDescriptor(
        for route: TaptionAudioCodecRoute
    ) -> TaptionAudioCodecAlgorithmDescriptor? {
        let readiness = TaptionAudioCodecExecutionReadinessReporter.item(
            for: route,
            outputContainer: outputContainer,
            broadSoftwareBackendExecutable: broadSoftwareBackendExecutable
        )
        switch readiness.readiness {
        case .copyInCurrentBuild, .nativeTranscodeInCurrentBuild:
            return HW_AudioCodecAlgorithmCatalog.descriptor(
                for: route,
                outputContainer: outputContainer
            )
        case .softwareBackendExecutable, .commandPlanOnly:
            return SW_UniversalAudioCodecTranscodeAlgorithm.descriptor(for: route)
        case .blockedMissingSoftwareEncoder, .unsupported:
            return nil
        }
    }
}
