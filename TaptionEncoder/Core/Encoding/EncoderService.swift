import Foundation

protocol EncoderServicing: TaptionVideoEncoding {}

struct FakeEncoderService: EncoderServicing {
    func encode(
        plan: TaptionEncodingPlan,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionEncodingResult {
        let totalSteps = 24
        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))

        for step in 1...totalSteps {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 120_000_000)

            let fraction = Double(step) / Double(totalSteps)
            let elapsed = Double(step) * 0.12
            let remaining = max(0, Double(totalSteps - step) * 0.12)
            progress(TaptionEncodingProgress(
                stage: step == totalSteps ? .waitingForSaveGate : .encoding,
                fractionCompleted: fraction,
                elapsedTime: elapsed,
                estimatedRemainingTime: remaining,
                currentFrame: Int64(step * 30),
                totalFrames: Int64(totalSteps * 30)
            ))
        }

        guard let temporaryOutputURL = plan.temporaryOutputURL else {
            throw TaptionVideoCoreError.missingTemporaryOutputURL
        }

        return TaptionEncodingResult(
            planID: plan.id,
            temporaryOutputURL: temporaryOutputURL,
            finalOutputURL: nil,
            usedBackend: plan.encoderSelection.backend ?? .simulatedHardware,
            usedMode: plan.encoderSelection.requestedMode
        )
    }

    func cancelEncoding(planID: UUID) async {}
}

final class AVFoundationHEVCEncoderService: EncoderServicing {
    private let registry: TaptionCodecTranscodingRegistry
    private let softwareExecutor: SW_FFmpegCommandExecutor

    init(
        registry: TaptionCodecTranscodingRegistry = .live,
        softwareExecutor: SW_FFmpegCommandExecutor = SW_FFmpegCommandExecutor()
    ) {
        self.registry = registry
        self.softwareExecutor = softwareExecutor
    }

    func encode(
        plan: TaptionEncodingPlan,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionEncodingResult {
        guard let sourceURL = plan.sourceURL else {
            throw TaptionVideoCoreError.missingSourceURL
        }
        guard let temporaryOutputURL = plan.temporaryOutputURL else {
            throw TaptionVideoCoreError.missingTemporaryOutputURL
        }
        guard let route = plan.codecRoute else {
            throw TaptionVideoCoreError.exportFailed("The codec route was not prepared.")
        }
        guard route.outputCodec == plan.outputPolicy.videoCodec else {
            throw TaptionCodecTranscodingRegistryError.requestRouteMismatch(
                expected: route,
                actual: TaptionCodecRoute(
                    sourceCodec: route.sourceCodec,
                    outputCodec: plan.outputPolicy.videoCodec
                )
            )
        }

        try FileManager.default.createDirectory(
            at: temporaryOutputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: temporaryOutputURL)

        let executionKind = plan.codecExecutionKind ?? .software
        let request = TaptionCodecTranscodeRequest(
            sourceURL: sourceURL,
            outputURL: temporaryOutputURL,
            route: route,
            options: TaptionCodecTranscodeOptions(
                outputPolicy: plan.outputPolicy,
                preserveSourceVisualQuality: true,
                preserveAudioWhenPossible: plan.audioPlan != nil
            )
        )
        AppLogger.info(
            "Codec transcode started",
            category: .encoding,
            metadata: [
                "plan": plan.id.uuidString,
                "source": sourceURL.lastPathComponent,
                "route": route.displayName,
                "audioRoute": plan.audioPlan?.route.displayName ?? "No audio",
                "audioPath": plan.audioPlan?.shortDisplayName ?? "None",
                "executionKind": executionKind.rawValue,
                "output": "\(plan.outputPolicy.videoCodec.displayName) / \(plan.outputPolicy.container.defaultFileExtension.uppercased())"
            ]
        )

        do {
            if shouldUseSoftwareCommandPlan(for: plan) {
                let output = try await executeSoftwareCodecRequest(
                    for: plan,
                    request: request,
                    progress: progress
                )
                return TaptionEncodingResult(
                    planID: plan.id,
                    temporaryOutputURL: output.outputURL,
                    finalOutputURL: plan.finalOutputURL,
                    usedBackend: output.usedBackend,
                    usedMode: output.usedMode
                )
            }

            guard plan.outputPolicy.videoCodec == .hevc,
                  plan.outputPolicy.container == .mp4 else {
                throw TaptionVideoCoreError.exportFailed(
                    "\(plan.outputPolicy.videoCodec.displayName) / \(plan.outputPolicy.container.defaultFileExtension.uppercased()) output is planned but not implemented in this build."
                )
            }

            let output = try await registry.transcode(
                request: request,
                executionKind: executionKind,
                progress: progress
            )

            guard FileManager.default.fileExists(atPath: temporaryOutputURL.path) else {
                throw TaptionVideoCoreError.exportFailed("The encoded output file was not created.")
            }

            AppLogger.info(
                "Codec transcode completed",
                category: .encoding,
                metadata: [
                    "plan": plan.id.uuidString,
                    "mode": output.usedMode.rawValue,
                    "backend": output.usedBackend.rawValue,
                    "temporary": temporaryOutputURL.lastPathComponent
                ]
            )

            return TaptionEncodingResult(
                planID: plan.id,
                temporaryOutputURL: temporaryOutputURL,
                finalOutputURL: plan.finalOutputURL,
                usedBackend: output.usedBackend,
                usedMode: output.usedMode
            )
        } catch is CancellationError {
            AppLogger.warning(
                "Codec transcode cancelled",
                category: .encoding,
                metadata: ["plan": plan.id.uuidString]
            )
            try? FileManager.default.removeItem(at: temporaryOutputURL)
            throw CancellationError()
        } catch {
            AppLogger.error(
                "Codec transcode failed",
                category: .encoding,
                metadata: [
                    "plan": plan.id.uuidString,
                    "route": route.displayName,
                    "error": error.localizedDescription
                ]
            )
            try? FileManager.default.removeItem(at: temporaryOutputURL)
            throw error
        }
    }

    func cancelEncoding(planID: UUID) async {
        AppLogger.warning(
            "Cancel encoding requested in AVFoundationHEVCEncoderService",
            category: .encoding,
            metadata: ["plan": planID.uuidString]
        )
    }

    private func shouldUseSoftwareCommandPlan(for plan: TaptionEncodingPlan) -> Bool {
        guard let executionKind = plan.codecExecutionKind,
              plan.videoCommandPlan != nil else {
            return false
        }
        return executionKind == .planned || executionKind == .software
    }

    private func executeSoftwareCodecRequest(
        for plan: TaptionEncodingPlan,
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        guard let commandPlan = plan.videoCommandPlan else {
            throw TaptionVideoCoreError.exportFailed("The software command plan was not prepared.")
        }
        AppLogger.info(
            "FFmpeg-family software codec request started",
            category: .encoding,
            metadata: [
                "plan": plan.id.uuidString,
                "route": commandPlan.routeSummary,
                "output": commandPlan.outputURL.lastPathComponent
            ]
        )
        let codecExecutor = SW_FFmpegVideoCodecTranscodeExecutor(
            executor: softwareExecutor
        )
        let output = try await codecExecutor.transcode(
            request: request,
            audioPlan: plan.audioPlan,
            progress: progress
        )
        AppLogger.info(
            "FFmpeg-family software codec request completed",
            category: .encoding,
            metadata: [
                "plan": plan.id.uuidString,
                "route": output.route.displayName,
                "backend": output.usedBackend.rawValue,
                "temporary": output.outputURL.lastPathComponent
            ]
        )
        return output
    }
}
