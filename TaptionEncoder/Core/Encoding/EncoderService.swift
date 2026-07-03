@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

protocol EncoderServicing: TaptionVideoEncoding {}

protocol SourcePreservingOutputVerifying {
    func verify(
        plan: TaptionEncodingPlan,
        outputURL: URL
    ) async throws -> TaptionSourcePreservingOutputVerificationReport
}

struct AVFoundationSourcePreservingOutputVerifier: SourcePreservingOutputVerifying {
    private let visualQualityVerifier: SourcePreservingVisualQualityVerifying

    init(
        visualQualityVerifier: SourcePreservingVisualQualityVerifying = AVFoundationSourcePreservingVisualQualityVerifier()
    ) {
        self.visualQualityVerifier = visualQualityVerifier
    }

    func verify(
        plan: TaptionEncodingPlan,
        outputURL: URL
    ) async throws -> TaptionSourcePreservingOutputVerificationReport {
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: outputURL)
        var report = try TaptionSourcePreservingExecutionAudit.verifyOutput(
            plan: plan,
            outputAsset: outputAsset
        )
        let visualReport = try await visualQualityVerifier.verify(
            plan: plan,
            outputURL: outputURL
        )
        report.warnings += visualReport.warnings
        report.metadata.merge(visualReport.metadata, uniquingKeysWith: { _, newValue in newValue })
        return report
    }
}

protocol SourcePreservingVisualQualityVerifying {
    func verify(
        plan: TaptionEncodingPlan,
        outputURL: URL
    ) async throws -> TaptionSourcePreservingVisualQualityReport
}

struct AVFoundationSourcePreservingVisualQualityVerifier: SourcePreservingVisualQualityVerifying {
    func verify(
        plan: TaptionEncodingPlan,
        outputURL: URL
    ) async throws -> TaptionSourcePreservingVisualQualityReport {
        let outputSample = try await visualSample(
            at: outputURL,
            preferredDuration: plan.sourcePreservationRequirements?.duration
        )
        var sourceSample: TaptionVisualQualitySample?
        var sourceWarning: String?
        if let sourceURL = plan.sourceURL {
            do {
                sourceSample = try await visualSample(
                    at: sourceURL,
                    preferredDuration: plan.sourcePreservationRequirements?.duration
                )
            } catch {
                sourceWarning = "Source visual sample could not be generated: \(error.localizedDescription)"
            }
        } else {
            sourceWarning = "Source visual sample could not be generated because the source URL was missing."
        }

        var report = TaptionSourcePreservingVisualQualityComparator.verify(
            sourceSample: sourceSample,
            outputSample: outputSample
        )
        if let sourceWarning {
            report.warnings.append(sourceWarning)
        }
        guard report.isPassing else {
            throw TaptionVideoCoreError.exportFailed(
                "Source-preserving visual quality verification failed: \(report.failures.joined(separator: "; "))."
            )
        }
        return report
    }

    private func visualSample(
        at url: URL,
        preferredDuration: TimeInterval?
    ) async throws -> TaptionVisualQualitySample {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let sampleTime = sampleTime(
            duration: duration?.seconds,
            preferredDuration: preferredDuration
        )
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 96, height: 96)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.35, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.35, preferredTimescale: 600)

        let image = try await generatedImage(
            using: generator,
            at: sampleTime
        )
        return try visualSample(from: image)
    }

    private func generatedImage(
        using generator: AVAssetImageGenerator,
        at sampleTime: CMTime
    ) async throws -> CGImage {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                generator.generateCGImageAsynchronously(for: sampleTime) { image, _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: TaptionVideoCoreError.exportFailed("Visual quality sample image could not be generated."))
                    }
                }
            }
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
    }

    private func sampleTime(
        duration: TimeInterval?,
        preferredDuration: TimeInterval?
    ) -> CMTime {
        let candidateDuration = [duration, preferredDuration]
            .compactMap { $0 }
            .first { $0.isFinite && $0 > 0 }
        guard let candidateDuration else {
            return .zero
        }
        let seconds = min(max(candidateDuration * 0.5, 0), max(candidateDuration - 0.05, 0))
        return CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func visualSample(from image: CGImage) throws -> TaptionVisualQualitySample {
        let width = max(1, min(64, image.width))
        let height = max(1, min(64, image.height))
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TaptionVideoCoreError.exportFailed("Visual quality sample buffer could not be created.")
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var redSum = 0.0
        var greenSum = 0.0
        var blueSum = 0.0
        var lumaSum = 0.0
        var lumaSquaredSum = 0.0
        var nonBlackCount = 0
        let pixelCount = width * height

        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            redSum += red
            greenSum += green
            blueSum += blue
            lumaSum += luma
            lumaSquaredSum += luma * luma
            if luma > 0.035 {
                nonBlackCount += 1
            }
        }

        let divisor = Double(max(pixelCount, 1))
        let averageLuma = lumaSum / divisor
        let lumaVariance = max(0, lumaSquaredSum / divisor - averageLuma * averageLuma)
        return TaptionVisualQualitySample(
            width: image.width,
            height: image.height,
            averageRed: redSum / divisor,
            averageGreen: greenSum / divisor,
            averageBlue: blueSum / divisor,
            averageLuma: averageLuma,
            lumaStandardDeviation: sqrt(lumaVariance),
            nonBlackRatio: Double(nonBlackCount) / divisor
        )
    }
}

struct DisabledSourcePreservingOutputVerifier: SourcePreservingOutputVerifying {
    func verify(
        plan: TaptionEncodingPlan,
        outputURL: URL
    ) async throws -> TaptionSourcePreservingOutputVerificationReport {
        TaptionSourcePreservingOutputVerificationReport(
            failures: [],
            warnings: ["Source-preserving output verification is disabled for this injected encoder path."],
            metadata: [
                "sourcePreservingOutput": "disabled",
                "output": outputURL.lastPathComponent,
                "plan": plan.id.uuidString
            ]
        )
    }
}

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
    private let outputVerifier: SourcePreservingOutputVerifying

    init(
        registry: TaptionCodecTranscodingRegistry = .live,
        softwareExecutor: SW_FFmpegCommandExecutor = SW_FFmpegCommandExecutor(),
        outputVerifier: SourcePreservingOutputVerifying = AVFoundationSourcePreservingOutputVerifier()
    ) {
        self.registry = registry
        self.softwareExecutor = softwareExecutor
        self.outputVerifier = outputVerifier
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
        try TaptionSourcePreservingExecutionAudit.validate(plan: plan)
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
        var startMetadata = [
            "plan": plan.id.uuidString,
            "source": sourceURL.lastPathComponent,
            "route": route.displayName,
            "audioRoute": plan.audioPlan?.route.displayName ?? "No audio",
            "audioPath": plan.audioPlan?.shortDisplayName ?? "None",
            "executionKind": executionKind.rawValue,
            "output": "\(plan.outputPolicy.videoCodec.displayName) / \(plan.outputPolicy.container.defaultFileExtension.uppercased())"
        ]
        startMetadata.merge(
            TaptionSourcePreservingExecutionAudit.logMetadata(for: plan),
            uniquingKeysWith: { _, newValue in newValue }
        )

        AppLogger.info(
            "Codec transcode started",
            category: .encoding,
            metadata: startMetadata
        )

        do {
            if shouldUseSoftwareCommandPlan(for: plan) {
                let output = try await executeSoftwareCodecRequest(
                    for: plan,
                    request: request,
                    progress: progress
                )
                try await verifyCompletedOutput(plan: plan, outputURL: output.outputURL)
                return TaptionEncodingResult(
                    planID: plan.id,
                    temporaryOutputURL: output.outputURL,
                    finalOutputURL: plan.finalOutputURL,
                    usedBackend: output.usedBackend,
                    usedMode: output.usedMode
                )
            }

            guard plan.outputPolicy.videoCodec == .hevc,
                  [.mp4, .mov].contains(plan.outputPolicy.container) else {
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
            try await verifyCompletedOutput(plan: plan, outputURL: temporaryOutputURL)

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
              let commandPlan = plan.videoCommandPlan else {
            return false
        }
        if executionKind == .planned {
            return true
        }
        guard executionKind == .software,
              let route = plan.codecRoute else {
            return false
        }

        guard let preferredDescriptor = registry.preferredDescriptor(
            for: route,
            executionKind: executionKind
        ) else {
            return true
        }

        return preferredDescriptor.backend == commandPlan.backend
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

    private func verifyCompletedOutput(
        plan: TaptionEncodingPlan,
        outputURL: URL
    ) async throws {
        let report = try await outputVerifier.verify(
            plan: plan,
            outputURL: outputURL
        )
        var metadata = report.metadata
        metadata["plan"] = plan.id.uuidString
        metadata["output"] = outputURL.lastPathComponent
        metadata["warnings"] = report.warnings.joined(separator: " | ")
        AppLogger.info(
            "Source-preserving output verification passed",
            category: .encoding,
            metadata: metadata
        )
    }
}
