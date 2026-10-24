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

/// Decides whether a plan should skip encoding altogether and copy the compressed samples instead.
///
/// A stream copy keeps every frame byte for byte. It is the only genuinely lossless result, it finishes in
/// seconds instead of minutes, and it is *better* than re-encoding whenever the plan does not actually ask for
/// anything smaller than the source. The moment the plan asks for a different frame, frame rate, colour or a
/// smaller file, a copy would break that promise and encoding is the right path again.
enum TaptionLosslessCopyPlanner {
    static func isEligible(plan: TaptionEncodingPlan) -> Bool {
        guard plan.codecRoute?.sourceCodec == .hevc,
              plan.codecRoute?.outputCodec == .hevc,
              plan.outputPolicy.videoCodec == .hevc,
              [.mp4, .mov].contains(plan.outputPolicy.container),
              let requirements = plan.sourcePreservationRequirements else {
            return false
        }

        let options = plan.outputPolicy.advancedOptions

        if let targetSize = options.resizeTo,
           let sourceSize = requirements.displaySize,
           !sizesMatch(targetSize, sourceSize) {
            return false
        }
        if let targetFrameRate = options.frameRate {
            guard let sourceFrameRate = requirements.frameRate,
                  abs(targetFrameRate.value - sourceFrameRate.value) <= 0.1 else {
                return false
            }
        }
        if let color = options.color,
           color != requirements.color {
            return false
        }
        if let rotation = options.rotationDegrees,
           let sourceRotation = requirements.rotationDegrees,
           rotation != sourceRotation {
            return false
        }
        if let audioPlan = plan.audioPlan,
           !(audioPlan.shouldCopy && audioPlan.isRunnableInCurrentBuild) {
            return false
        }

        // Only when the requested size target is at least the source's own bitrate. Asking for a smaller file is
        // the whole point of an encoder, and a copy cannot deliver it.
        guard let sourceBitrate = requirements.targetBitrate,
              sourceBitrate > 0 else {
            return false
        }
        if let targetBitrate = options.targetBitrate,
           Double(targetBitrate) < Double(sourceBitrate) * 1.15 {
            return false
        }
        return true
    }

    private static func sizesMatch(_ lhs: TaptionPixelSize, _ rhs: TaptionPixelSize) -> Bool {
        abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
    }
}

/// Re-wraps a movie's compressed samples into a new container without decoding or re-encoding.
///
/// Both the reader output and the writer input use `nil` output settings, so every sample is passed through byte
/// for byte. The movie and video timescales are carried over so frame times and edit-list offsets stay exact, and
/// MOV keeps the source's metadata.
enum TaptionLosslessCopyExecutor {
    static func copy(
        sourceURL: URL,
        outputURL: URL,
        container: TaptionVideoContainer,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws {
        let startedAt = Date()
        let asset = AVURLAsset(url: sourceURL)
        let assetDuration = try await asset.load(.duration)
        let duration = assetDuration.seconds
        let tracks = try await asset.load(.tracks)

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(
            outputURL: outputURL,
            fileType: container == .mov ? .mov : .mp4
        )
        writer.shouldOptimizeForNetworkUse = false
        if assetDuration.timescale > 0 {
            writer.movieTimeScale = assetDuration.timescale
        }
        if container == .mov {
            writer.metadata = try await asset.load(.metadata)
        }

        var pipes: [Pipe] = []
        for track in tracks {
            let type = track.mediaType
            guard type == .video || type == .audio else { continue }
            let formats = try await track.load(.formatDescriptions)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { continue }

            let input = AVAssetWriterInput(
                mediaType: type,
                outputSettings: nil,
                sourceFormatHint: formats.first
            )
            input.expectsMediaDataInRealTime = false
            if type == .video {
                // The writer otherwise defaults to a 600 timescale, which rounds frame times like 1001/30000 s.
                let timescale = try await track.load(.naturalTimeScale)
                if timescale > 0 {
                    input.mediaTimeScale = timescale
                }
                input.transform = try await track.load(.preferredTransform)
            }
            if let tag = try? await track.load(.extendedLanguageTag) {
                input.extendedLanguageTag = tag
            }
            guard writer.canAdd(input) else { continue }

            reader.add(output)
            writer.add(input)
            pipes.append(Pipe(output: output, input: input, isVideo: type == .video))
        }
        guard !pipes.isEmpty else {
            throw TaptionVideoCoreError.exportFailed("There are no video or audio tracks to copy.")
        }

        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))

        guard reader.startReading() else {
            throw reader.error ?? TaptionVideoCoreError.exportFailed("The source could not be read for a lossless copy.")
        }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? TaptionVideoCoreError.exportFailed("The lossless copy output could not be created.")
        }
        writer.startSession(atSourceTime: .zero)

        let emitter = EncodingProgressEmitter(
            coalescer: EncodingProgressCoalescer(minimumFractionDelta: 0.01, minimumTimeInterval: 0.25),
            progress: { snapshot in
                var reported = snapshot
                reported.elapsedTime = Date().timeIntervalSince(startedAt)
                progress(reported)
            }
        )

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let group = DispatchGroup()
                for pipe in pipes {
                    group.enter()
                    let queue = DispatchQueue(label: "taption.losslessCopy.\(pipe.input.mediaType.rawValue)")
                    pipe.input.requestMediaDataWhenReady(on: queue) {
                        while pipe.input.isReadyForMoreMediaData {
                            guard let sample = pipe.output.copyNextSampleBuffer() else {
                                pipe.input.markAsFinished()
                                group.leave()
                                return
                            }
                            if pipe.isVideo, duration > 0 {
                                let seconds = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                                if seconds.isFinite {
                                    emitter.submit(TaptionEncodingProgress(
                                        stage: .encoding,
                                        fractionCompleted: min(max(seconds / duration, 0), 0.99)
                                    ))
                                }
                            }
                            if !pipe.input.append(sample) {
                                pipe.input.markAsFinished()
                                group.leave()
                                return
                            }
                        }
                    }
                }
                group.notify(queue: .global()) {
                    continuation.resume()
                }
            }
        } onCancel: {
            reader.cancelReading()
        }

        if reader.status == .cancelled || Task.isCancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw reader.error ?? TaptionVideoCoreError.exportFailed("The source could not be read for a lossless copy.")
        }

        await writer.finishWriting()
        guard writer.status == .completed,
              FileManager.default.fileExists(atPath: outputURL.path) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw writer.error ?? TaptionVideoCoreError.exportFailed("The lossless copy could not be finished.")
        }

        progress(TaptionEncodingProgress(
            stage: .waitingForSaveGate,
            fractionCompleted: 1,
            elapsedTime: Date().timeIntervalSince(startedAt),
            estimatedRemainingTime: 0
        ))
    }

    private struct Pipe: @unchecked Sendable {
        let output: AVAssetReaderTrackOutput
        let input: AVAssetWriterInput
        let isVideo: Bool
    }
}

struct DisabledSourcePreservingOutputVerifier: SourcePreservingOutputVerifying {    func verify(
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
        try Task.checkCancellation()
        try MediaFileIdentity.validateEncodingOutput(source: sourceURL, temporary: temporaryOutputURL)
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
        if FileManager.default.fileExists(atPath: temporaryOutputURL.path) {
            try FileManager.default.removeItem(at: temporaryOutputURL)
        }

        let executionKind = plan.codecExecutionKind ?? .software
        try TaptionSourcePreservingExecutionAudit.validate(plan: plan)

        if TaptionLosslessCopyPlanner.isEligible(plan: plan),
           !shouldUseSoftwareCommandPlan(for: plan) {
            do {
                try await TaptionLosslessCopyExecutor.copy(
                    sourceURL: sourceURL,
                    outputURL: temporaryOutputURL,
                    container: plan.outputPolicy.container,
                    progress: progress
                )
                try await verifyCompletedOutput(plan: plan, outputURL: temporaryOutputURL)
                AppLogger.info(
                    "Lossless stream copy completed",
                    category: .encoding,
                    metadata: [
                        "plan": plan.id.uuidString,
                        "source": sourceURL.lastPathComponent,
                        "output": temporaryOutputURL.lastPathComponent
                    ]
                )
                return TaptionEncodingResult(
                    planID: plan.id,
                    temporaryOutputURL: temporaryOutputURL,
                    finalOutputURL: plan.finalOutputURL,
                    usedBackend: .appleVideoToolbox,
                    usedMode: .hardware,
                    usedLosslessCopy: true
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppLogger.warning(
                    "Lossless stream copy failed; encoding instead",
                    category: .encoding,
                    metadata: [
                        "plan": plan.id.uuidString,
                        "error": error.localizedDescription
                    ]
                )
                try? FileManager.default.removeItem(at: temporaryOutputURL)
            }
        }

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
        if let sourceCodec = plan.codecRoute?.sourceCodec,
           TaptionCodecRegistry.bundledFFmpegDecodeBridgeSourceCodecs.contains(sourceCodec) {
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
