import Foundation

enum TaptionUniversalSoftwareCodecError: LocalizedError, Equatable {
    case requestRouteMismatch(expected: TaptionCodecRoute, actual: TaptionCodecRoute)
    case routeNotPlannable(TaptionCodecRoute)
    case outputContainerUnavailable(TaptionVideoContainer)
    case backendNotBundled(TaptionEncodingBackend, TaptionCodecRoute)

    var errorDescription: String? {
        switch self {
        case .requestRouteMismatch(let expected, let actual):
            return "Codec request route mismatch. Expected \(expected.displayName), got \(actual.displayName)."
        case .routeNotPlannable(let route):
            return "\(route.displayName) is not covered by the universal software codec backend plan."
        case .outputContainerUnavailable(let container):
            return "\(container.defaultFileExtension.uppercased()) output is not writable by the universal software codec backend plan."
        case .backendNotBundled(let backend, let route):
            return "\(route.displayName) requires \(backend.rawValue), but that software codec backend is not bundled in this build."
        }
    }
}

enum SW_UniversalCodecTranscodeAlgorithm {
    static let backend = SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.backend

    static var plannedDescriptors: [TaptionCodecAlgorithmDescriptor] {
        TaptionCodecRegistry.plannedUniversalRoutes
            .filter { !TaptionCodecRegistry.implementedRoutes.contains($0) }
            .compactMap(descriptor)
            .sorted { lhs, rhs in
                if lhs.sourceCodec.rawValue == rhs.sourceCodec.rawValue {
                    return lhs.outputCodec.rawValue < rhs.outputCodec.rawValue
                }
                return lhs.sourceCodec.rawValue < rhs.sourceCodec.rawValue
            }
    }

    static func descriptor(for route: TaptionCodecRoute) -> TaptionCodecAlgorithmDescriptor? {
        guard canRepresent(route) else {
            return nil
        }
        return TaptionCodecAlgorithmDescriptor(
            route: route,
            mode: .software,
            backend: backend,
            displayName: "\(route.sourceCodec.shortDisplayName) to \(route.outputCodec.shortDisplayName) Software"
        )
    }

    static func canRepresent(_ route: TaptionCodecRoute) -> Bool {
        let profile = SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate
        return profile.canDecodeVideo(route.sourceCodec)
            && profile.canEncodeVideo(route.outputCodec)
    }

    static func validate(request: TaptionCodecTranscodeRequest) throws {
        let requestedRoute = TaptionCodecRoute(
            sourceCodec: request.route.sourceCodec,
            outputCodec: request.options.outputPolicy.videoCodec
        )
        guard requestedRoute == request.route else {
            throw TaptionUniversalSoftwareCodecError.requestRouteMismatch(
                expected: request.route,
                actual: requestedRoute
            )
        }
        guard canRepresent(request.route) else {
            throw TaptionUniversalSoftwareCodecError.routeNotPlannable(request.route)
        }

        let profile = SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate
        guard profile.canWriteContainer(request.options.outputPolicy.container) else {
            throw TaptionUniversalSoftwareCodecError.outputContainerUnavailable(
                request.options.outputPolicy.container
            )
        }
    }

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try validate(request: request)
        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))
        throw TaptionUniversalSoftwareCodecError.backendNotBundled(backend, request.route)
    }
}

struct SW_FFmpegVideoCodecTranscodeExecutor {
    var executor: SW_FFmpegCommandExecutor

    init(
        executor: SW_FFmpegCommandExecutor = SW_FFmpegCommandExecutor()
    ) {
        self.executor = executor
    }

    func transcode(
        request: TaptionCodecTranscodeRequest,
        audioPlan: TaptionAudioTranscodePlan? = nil,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_UniversalCodecTranscodeAlgorithm.validate(request: request)
        let commandPlan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: request,
            audioPlan: audioPlan
        )
        _ = try await executor.execute(commandPlan, progress: progress)

        return TaptionCodecTranscodeOutput(
            outputURL: commandPlan.outputURL,
            route: request.route,
            usedMode: .software,
            usedBackend: commandPlan.backend,
            outputVideoCodec: request.options.outputPolicy.videoCodec,
            outputAudioTrackCount: request.options.preserveAudioWhenPossible ? 1 : 0
        )
    }
}
