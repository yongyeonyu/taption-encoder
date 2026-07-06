import Foundation

enum TaptionCodecTranscodingRegistryError: LocalizedError, Equatable {
    case routeNotImplemented(TaptionCodecRoute)
    case requestRouteMismatch(expected: TaptionCodecRoute, actual: TaptionCodecRoute)
    case algorithmUnavailable(route: TaptionCodecRoute, executionKind: TaptionCodecRouteExecutionKind)

    var errorDescription: String? {
        switch self {
        case .routeNotImplemented(let route):
            return "\(route.displayName) is planned but not implemented in this build."
        case .requestRouteMismatch(let expected, let actual):
            return "Codec request route mismatch. Expected \(expected.displayName), got \(actual.displayName)."
        case .algorithmUnavailable(let route, let executionKind):
            return "\(route.displayName) has no \(executionKind.shortDisplayName) algorithm in this build."
        }
    }
}

struct TaptionCodecTranscodingRegistry: @unchecked Sendable {
    var algorithms: [TaptionCodecTranscodingAlgorithmEntry]
    var plannedDescriptors: [TaptionCodecAlgorithmDescriptor]

    init(
        algorithms: [TaptionCodecTranscodingAlgorithmEntry],
        plannedDescriptors: [TaptionCodecAlgorithmDescriptor] = []
    ) {
        self.algorithms = algorithms
        self.plannedDescriptors = plannedDescriptors
    }

    static let live = makeLive()

    static func makeLive(
        softwareExecutor: SW_FFmpegCommandExecutor? = nil
    ) -> TaptionCodecTranscodingRegistry {
        var algorithms = [
            TaptionCodecTranscodingAlgorithmEntry(HW_AV1HEVCCodecAlgorithm.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_AV1HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_H264HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_HEVCHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_VP9HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_VP8HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_MPEG1HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_MPEG2HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_MPEG4VisualHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_H263HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_H261HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_FlashVideoHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_MicrosoftMPEG4V2HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_MicrosoftMPEG4V3HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_MotionJPEGHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_JPEG2000HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_JPEGLSHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_LosslessJPEGHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_AnimationHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_CinepakHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_SorensonVideoHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_SorensonVideo3HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_QuickTimeVideoHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_TheoraHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_RealVideo1HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_RealVideoHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_RoQVideoHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_WMVHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_MicrosoftVideo1HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_ASUSV1HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_ASUSV2HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_FlashScreenVideoHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_FlashScreenVideo2HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_ZMBVHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_CLJRHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_SnowHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_FFV1HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_HuffYUVHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_UtVideoHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_MagicYUVHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_DVCProHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_DVCProHDHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_DVHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_CineFormHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_DNxHDHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_PNGVideoHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_R10KHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_V308HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_V210HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_R210HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_V408HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_V410HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_MicrosoftRLEHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_QuickTimeGraphicsHEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_YUV4HEVCTranscoder.self),
            TaptionCodecTranscodingAlgorithmEntry(SW_RawVideoHEVCTranscoder.self)
        ] + HW_AppleHEVCCodecAlgorithm.nativeDescriptors.map { descriptor in
            TaptionCodecTranscodingAlgorithmEntry(
                descriptor: descriptor,
                transcode: { request, progress in
                    try await HW_AppleHEVCCodecAlgorithm.transcode(request: request, progress: progress)
                }
            )
        }

        var plannedDescriptors = SW_UniversalCodecTranscodeAlgorithm.plannedDescriptors
        if let softwareExecutor,
           softwareExecutor.readinessReport.isExecutableInCurrentBuild,
           softwareExecutor.runner != nil {
            let runtimeDescriptors = SW_UniversalCodecTranscodeAlgorithm.runtimeAlgorithmEntries(
                executor: SW_FFmpegVideoCodecTranscodeExecutor(executor: softwareExecutor)
            )
            let runtimeRoutes = Set(runtimeDescriptors.map(\.descriptor.route))
            algorithms += runtimeDescriptors
            plannedDescriptors.removeAll { runtimeRoutes.contains($0.route) }
        }

        return TaptionCodecTranscodingRegistry(
            algorithms: algorithms,
            plannedDescriptors: plannedDescriptors
        )
    }

    var descriptors: [TaptionCodecAlgorithmDescriptor] {
        algorithms.map(\.descriptor)
    }

    var allDescriptors: [TaptionCodecAlgorithmDescriptor] {
        descriptors + plannedDescriptors
    }

    func descriptors(for route: TaptionCodecRoute) -> [TaptionCodecAlgorithmDescriptor] {
        descriptors.filter { $0.route == route }
    }

    func plannedDescriptors(for route: TaptionCodecRoute) -> [TaptionCodecAlgorithmDescriptor] {
        plannedDescriptors.filter { $0.route == route }
    }

    func allDescriptors(for route: TaptionCodecRoute) -> [TaptionCodecAlgorithmDescriptor] {
        allDescriptors.filter { $0.route == route }
    }

    func preferredDescriptor(
        for route: TaptionCodecRoute,
        executionKind: TaptionCodecRouteExecutionKind
    ) -> TaptionCodecAlgorithmDescriptor? {
        algorithmOrder(for: executionKind).compactMap { mode in
            descriptors.first { $0.route == route && $0.mode == mode }
        }.first
    }

    func transcode(
        request: TaptionCodecTranscodeRequest,
        executionKind: TaptionCodecRouteExecutionKind,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        let routeSupport = TaptionCodecRegistry.support(for: request.route)
        guard routeSupport != .unsupported else {
            throw TaptionCodecTranscodingRegistryError.routeNotImplemented(request.route)
        }

        let candidates = algorithmOrder(for: executionKind).compactMap { mode in
            algorithms.first { $0.descriptor.route == request.route && $0.descriptor.mode == mode }
        }
        guard !candidates.isEmpty else {
            if routeSupport == .planned {
                throw TaptionCodecTranscodingRegistryError.routeNotImplemented(request.route)
            }
            throw TaptionCodecTranscodingRegistryError.algorithmUnavailable(
                route: request.route,
                executionKind: executionKind
            )
        }

        var lastError: Error?
        for candidate in candidates {
            do {
                AppLogger.info(
                    "Codec algorithm selected",
                    category: .encoding,
                    metadata: [
                        "route": candidate.descriptor.route.displayName,
                        "mode": candidate.descriptor.mode.rawValue,
                        "backend": candidate.descriptor.backend.rawValue
                    ]
                )
                return try await candidate.transcode(request, progress)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                AppLogger.error(
                    "Codec algorithm failed",
                    category: .encoding,
                    metadata: [
                        "route": candidate.descriptor.route.displayName,
                        "mode": candidate.descriptor.mode.rawValue,
                        "error": error.localizedDescription
                    ]
                )
            }
        }

        throw lastError ?? TaptionCodecTranscodingRegistryError.algorithmUnavailable(
            route: request.route,
            executionKind: executionKind
        )
    }

    private func algorithmOrder(
        for executionKind: TaptionCodecRouteExecutionKind
    ) -> [TaptionEncoderMode] {
        switch executionKind {
        case .hardware:
            return [.hardware, .software]
        case .mixed:
            return [.hardware, .software]
        case .software:
            return [.software]
        case .planned, .unsupported:
            return []
        }
    }
}
