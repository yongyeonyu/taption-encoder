import Foundation

enum TaptionUniversalAudioCodecError: LocalizedError, Equatable {
    case requestRouteMismatch(expected: TaptionAudioCodecRoute, actual: TaptionAudioCodecRoute)
    case routeNotPlannable(TaptionAudioCodecRoute)
    case outputContainerUnavailable(TaptionVideoContainer)
    case backendNotBundled(TaptionEncodingBackend, TaptionAudioCodecRoute)

    var errorDescription: String? {
        switch self {
        case .requestRouteMismatch(let expected, let actual):
            return "Audio codec request route mismatch. Expected \(expected.displayName), got \(actual.displayName)."
        case .routeNotPlannable(let route):
            return "\(route.displayName) is not represented by the universal software audio backend."
        case .outputContainerUnavailable(let container):
            return "\(container.defaultFileExtension.uppercased()) output is not writable by the planned software audio backend."
        case .backendNotBundled(let backend, let route):
            return "\(route.displayName) requires \(backend.rawValue), but that broad software audio backend is not bundled in this build."
        }
    }
}

enum SW_UniversalAudioCodecTranscodeAlgorithm: TaptionStaticAudioCodecTranscodingAlgorithm {
    static let backend: TaptionEncodingBackend = .ffmpegFamily

    static var plannedDescriptors: [TaptionAudioCodecAlgorithmDescriptor] {
        TaptionAudioCodecRoutePlanner.plannedUniversalRoutes
            .compactMap(descriptor(for:))
            .sorted {
                if $0.sourceCodec.rawValue == $1.sourceCodec.rawValue {
                    return $0.outputCodec.rawValue < $1.outputCodec.rawValue
                }
                return $0.sourceCodec.rawValue < $1.sourceCodec.rawValue
            }
    }

    static func descriptor(
        for route: TaptionAudioCodecRoute
    ) -> TaptionAudioCodecAlgorithmDescriptor? {
        guard canRepresent(route) else {
            return nil
        }
        return TaptionAudioCodecAlgorithmDescriptor(
            route: route,
            mode: .software,
            backend: backend,
            displayName: "\(route.displayName) Software"
        )
    }

    static func canRepresent(_ route: TaptionAudioCodecRoute) -> Bool {
        TaptionAudioCodecRoutePlanner.plannedUniversalRoutes.contains(route)
            && SW_SoftwareCodecBackendRegistry.canPlanSoftwareAudioRoute(route)
    }

    static func validate(
        request: TaptionAudioCodecTranscodeRequest
    ) throws {
        let requestedRoute = TaptionAudioCodecRoute(
            sourceCodec: request.route.sourceCodec,
            outputCodec: request.options.outputCodec
        )
        guard requestedRoute == request.route else {
            throw TaptionUniversalAudioCodecError.requestRouteMismatch(
                expected: request.route,
                actual: requestedRoute
            )
        }
        guard canRepresent(request.route) else {
            throw TaptionUniversalAudioCodecError.routeNotPlannable(request.route)
        }
        guard SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.canWriteContainer(request.options.outputContainer) else {
            throw TaptionUniversalAudioCodecError.outputContainerUnavailable(request.options.outputContainer)
        }
    }

    static func transcode(
        request: TaptionAudioCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionAudioCodecTranscodeOutput {
        try validate(request: request)
        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))
        throw TaptionUniversalAudioCodecError.backendNotBundled(backend, request.route)
    }
}

struct SW_FFmpegAudioCodecTranscodeExecutor {
    var executor: SW_FFmpegCommandExecutor

    init(
        executor: SW_FFmpegCommandExecutor = SW_FFmpegCommandExecutor()
    ) {
        self.executor = executor
    }

    func transcode(
        request: TaptionAudioCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionAudioCodecTranscodeOutput {
        try SW_UniversalAudioCodecTranscodeAlgorithm.validate(request: request)
        let commandPlan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(
            request: request
        )
        _ = try await executor.execute(commandPlan, progress: progress)

        return TaptionAudioCodecTranscodeOutput(
            outputURL: commandPlan.outputURL,
            route: request.route,
            usedMode: .software,
            usedBackend: commandPlan.backend,
            outputAudioCodec: request.options.outputCodec,
            outputContainer: request.options.outputContainer
        )
    }
}
