@preconcurrency import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import VideoToolbox

enum TaptionHEVCWriterPerformanceHints {
    static let prioritizeEncodingSpeedKey =
        kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String
    static let realTimeKey = kVTCompressionPropertyKey_RealTime as String
    static let maximizePowerEfficiencyKey =
        kVTCompressionPropertyKey_MaximizePowerEfficiency as String
    static let sourceFrameCountKey = kVTCompressionPropertyKey_SourceFrameCount as String

    static func apply(
        to compressionProperties: inout [String: Any],
        optimizationProfile: TaptionEncodingOptimizationProfile,
        sourceFrameCount: Int? = nil
    ) {
        guard optimizationProfile == .performance else { return }
        compressionProperties[realTimeKey] = false
        compressionProperties[maximizePowerEfficiencyKey] = false
        if let sourceFrameCount, sourceFrameCount > 0 {
            compressionProperties[sourceFrameCountKey] = sourceFrameCount
        }
        #if targetEnvironment(simulator)
        return
        #else
        compressionProperties[prioritizeEncodingSpeedKey] = true
        #endif
    }
}

enum HW_AppleHEVCCodecAlgorithm {
    struct Selection {
        var mode: TaptionEncoderMode
        var backend: TaptionEncodingBackend
    }

    static var nativeSourceCodecs: [TaptionVideoCodec] {
        TaptionCodecRegistry.appleNativeHEVCHardwareSourceCodecs
            + TaptionCodecRegistry.appleNativeHEVCSoftwareSourceCodecs
    }

    static var nativeDescriptors: [TaptionCodecAlgorithmDescriptor] {
        TaptionCodecRegistry.appleNativeHEVCHardwareAlgorithmDescriptors
            + TaptionCodecRegistry.appleNativeHEVCSoftwareAlgorithmDescriptors
    }

    static func selectedMode(for requestedMode: TaptionEncoderMode) -> Selection {
        if hasHardwareHEVCEncoder {
            return Selection(mode: .hardware, backend: .appleVideoToolbox)
        }

        switch requestedMode {
        case .automatic, .hardware, .software:
            return Selection(mode: .software, backend: .appleAVAssetExport)
        }
    }

    static var hasHardwareHEVCEncoder: Bool {
        var encoderList: CFArray?
        guard VTCopyVideoEncoderList(nil, &encoderList) == noErr,
              let encoders = encoderList as? [[CFString: Any]] else {
            return false
        }

        return encoders.contains { encoder in
            guard let codecNumber = encoder[kVTVideoEncoderList_CodecType] as? NSNumber,
                  UInt32(truncating: codecNumber) == kCMVideoCodecType_HEVC else {
                return false
            }
            return (encoder[kVTVideoEncoderList_IsHardwareAccelerated] as? Bool) == true
        }
    }

    static func selectHEVCPreset(for asset: AVAsset) throws -> String {
        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let candidates = [
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPresetHEVC3840x2160,
            AVAssetExportPresetHEVC1920x1080
        ]

        guard let preset = candidates.first(where: { compatiblePresets.contains($0) }) else {
            throw TaptionVideoCoreError.compatibleHEVCPresetUnavailable
        }
        return preset
    }

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try validate(request: request)
        if [.jpeg, .jpegXL].contains(request.route.sourceCodec) {
            return try await transcodeAppleNativeStillImageVideo(
                request: request,
                progress: progress
            )
        }
        let optimizationProfile = request.options.outputPolicy.advancedOptions.optimizationProfile
            ?? .balanced
        if optimizationProfile == .performance,
           [.h264, .hevc, .proRes].contains(request.route.sourceCodec) {
            do {
                if let output = try await transcodeCompressedVideoWithReaderWriterIfEligible(
                    request: request,
                    progress: progress
                ) {
                    return output
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppLogger.warning(
                    "Apple native Max Performance reader/writer path failed; using export fallback",
                    category: .encoding,
                    metadata: [
                        "source": request.sourceURL.lastPathComponent,
                        "error": error.localizedDescription
                    ]
                )
                try? FileManager.default.removeItem(at: request.outputURL)
            }
        }
        let startedAt = Date()
        let trace = TaptionEncodingPerformanceTrace(
            name: "hw_hevc_transcode",
            category: .encoding,
            metadata: [
                "source": request.sourceURL.lastPathComponent,
                "route": request.route.displayName,
                "output": request.outputURL.lastPathComponent
            ]
        )
        let progressEmitter = EncodingProgressEmitter(progress: progress)
        do {
            let asset = AVURLAsset(url: request.sourceURL)
            let presetName = try selectHEVCPreset(for: asset)
            trace.mark(
                "preset_selected",
                metadata: [
                    "preset": presetName,
                    "optimizationProfile": optimizationProfile.rawValue
                ]
            )

            progressEmitter.submit(TaptionEncodingProgress(
                stage: .preparing,
                fractionCompleted: 0,
                elapsedTime: 0,
                estimatedRemainingTime: nil
            ), force: true)

            guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
                throw TaptionVideoCoreError.compatibleHEVCPresetUnavailable
            }

            let outputFileType = avFileType(
                for: request.options.outputPolicy.container,
                supportedFileTypes: exportSession.supportedFileTypes
            )
            exportSession.outputURL = request.outputURL
            exportSession.outputFileType = outputFileType
            exportSession.shouldOptimizeForNetworkUse = optimizationProfile != .performance
            exportSession.canPerformMultiplePassesOverSourceMediaData = false
            let resolvedTargetSize = try await resolvedTargetSize(
                for: request,
                asset: asset
            )
            exportSession.videoComposition = try await videoCompositionIfNeeded(
                for: asset,
                targetSize: resolvedTargetSize,
                targetFrameRate: request.options.outputPolicy.advancedOptions.frameRate
            )
            trace.mark(
                "export_session_configured",
                metadata: [
                    "fileType": outputFileType.rawValue,
                    "networkOptimized": "\(exportSession.shouldOptimizeForNetworkUse)"
                ]
            )

            let exportSessionBox = HW_AppleHEVCExportSessionBox(exportSession)
            let progressTask = Task { [exportSessionBox] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    let rawProgress = Double(exportSessionBox.progress)
                    let fraction = min(max(rawProgress, 0.01), 0.99)
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining = fraction > 0.02
                        ? max(0, elapsed * (1 - fraction) / fraction)
                        : nil
                    progressEmitter.submit(TaptionEncodingProgress(
                        stage: .encoding,
                        fractionCompleted: fraction,
                        elapsedTime: elapsed,
                        estimatedRemainingTime: remaining
                    ))

                    if exportSessionBox.status == .completed
                        || exportSessionBox.status == .failed
                        || exportSessionBox.status == .cancelled {
                        return
                    }
                }
            }
            defer {
                progressTask.cancel()
            }
            try await export(exportSessionBox)
            trace.mark("export_completed")

            progressEmitter.submit(TaptionEncodingProgress(
                stage: .waitingForSaveGate,
                fractionCompleted: 1,
                elapsedTime: Date().timeIntervalSince(startedAt),
                estimatedRemainingTime: 0
            ), force: true)
            let progressStats = progressEmitter.stats
            trace.finish(
                "completed",
                metadata: [
                    "progressObserved": "\(progressStats.observedCount)",
                    "progressEmitted": "\(progressStats.emittedCount)"
                ]
            )

            let usesAppleNativeSoftwareDecode = TaptionCodecRegistry
                .appleNativeHEVCSoftwareSourceCodecs
                .contains(request.route.sourceCodec)
            return TaptionCodecTranscodeOutput(
                outputURL: request.outputURL,
                route: request.route,
                usedMode: usesAppleNativeSoftwareDecode ? .software : .hardware,
                usedBackend: usesAppleNativeSoftwareDecode ? .appleAVAssetExport : .appleVideoToolbox,
                outputVideoCodec: request.options.outputPolicy.videoCodec,
                outputAudioTrackCount: 1
            )
        } catch is CancellationError {
            trace.finish("cancelled")
            throw CancellationError()
        } catch {
            if request.route.sourceCodec == .proResRaw {
                trace.mark(
                    "apple_export_failed_using_bundled_decode_bridge",
                    metadata: ["error": error.localizedDescription]
                )
                do {
                    let output = try await SW_FFmpegDecodeBridgeFallbackTranscoder.transcode(
                        request: request,
                        progress: progress
                    )
                    trace.finish("completed_with_bundled_decode_bridge")
                    return output
                } catch {
                    trace.finish(
                        "failed",
                        metadata: ["bridgeError": error.localizedDescription]
                    )
                    throw error
                }
            }
            trace.finish("failed", metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    private static func validate(request: TaptionCodecTranscodeRequest) throws {
        guard request.route.outputCodec == .hevc,
              request.options.outputPolicy.videoCodec == .hevc else {
            throw TaptionCodecTranscodingRegistryError.requestRouteMismatch(
                expected: request.route,
                actual: TaptionCodecRoute(
                    sourceCodec: request.route.sourceCodec,
                    outputCodec: request.options.outputPolicy.videoCodec
                )
            )
        }
        guard request.route.sourceCodec == .av1
                || nativeSourceCodecs.contains(request.route.sourceCodec) else {
            throw TaptionCodecTranscodingRegistryError.routeNotImplemented(request.route)
        }
    }

    private static func transcodeCompressedVideoWithReaderWriterIfEligible(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput? {
        let outputPolicy = request.options.outputPolicy
        guard requestsCompressedVideoReaderWriterFastPath(request) else {
            return nil
        }

        let asset = AVURLAsset(url: request.sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard videoTracks.count == 1,
              let videoTrack = videoTracks.first else {
            return nil
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let timeRange = try await videoTrack.load(.timeRange)
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        guard !formatDescriptions.contains(where: formatDescriptionIsHDR) else {
            return nil
        }
        let displayedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displayedSize = CGSize(width: abs(displayedRect.width), height: abs(displayedRect.height))
        let width = Int(naturalSize.width.rounded())
        let height = Int(naturalSize.height.rounded())
        guard width >= 2,
              height >= 2,
              width.isMultiple(of: 2),
              height.isMultiple(of: 2),
              displayedSize.width > 0,
              displayedSize.height > 0 else {
            return nil
        }

        if let requestedSize = outputPolicy.advancedOptions.resizeTo {
            let requestedCGSize = CGSize(width: requestedSize.width, height: requestedSize.height)
            guard sizesAreEquivalent(requestedCGSize, displayedSize) else {
                return nil
            }
        }
        if let requestedFrameRate = outputPolicy.advancedOptions.frameRate?.value,
           requestedFrameRate.isFinite,
           requestedFrameRate > 0,
           nominalFrameRate.isFinite,
           nominalFrameRate > 0,
           abs(requestedFrameRate - Double(nominalFrameRate)) > 0.1 {
            return nil
        }
        if let requestedRotation = outputPolicy.advancedOptions.rotationDegrees,
           normalizedRotationDegrees(requestedRotation) != rotationDegrees(from: preferredTransform) {
            return nil
        }
        let allAudioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioTrack: AVAssetTrack?
        let audioFormatHint: CMFormatDescription?
        if request.options.preserveAudioWhenPossible {
            guard allAudioTracks.count <= 1 else { return nil }
            audioTrack = allAudioTracks.first
            if let audioTrack {
                let formatDescriptions = try await audioTrack.load(.formatDescriptions)
                guard let formatDescription = formatDescriptions.first,
                      CMFormatDescriptionGetMediaSubType(formatDescription) == kAudioFormatMPEG4AAC else {
                    return nil
                }
                audioFormatHint = formatDescription
            } else {
                audioFormatHint = nil
            }
        } else {
            audioTrack = nil
            audioFormatHint = nil
        }

        let startedAt = Date()
        let trace = TaptionEncodingPerformanceTrace(
            name: "hw_compressed_hevc_reader_writer",
            category: .encoding,
            metadata: [
                "source": request.sourceURL.lastPathComponent,
                "output": request.outputURL.lastPathComponent,
                "size": "\(width)x\(height)",
                "audioPassthrough": "\(audioTrack != nil)"
            ]
        )
        let progressEmitter = EncodingProgressEmitter(progress: progress)
        progressEmitter.submit(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ), force: true)

        try FileManager.default.createDirectory(
            at: request.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: request.outputURL)

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw TaptionVideoCoreError.exportFailed("Apple native fast-path video reader output could not be added.")
        }
        reader.add(videoOutput)

        let audioOutput = audioTrack.map { track in
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            output.alwaysCopiesSampleData = false
            return output
        }
        if let audioOutput {
            guard reader.canAdd(audioOutput) else {
                throw TaptionVideoCoreError.exportFailed("Apple native fast-path audio reader output could not be added.")
            }
            reader.add(audioOutput)
        }

        let writer = try AVAssetWriter(
            outputURL: request.outputURL,
            fileType: avFileType(for: outputPolicy.container, supportedFileTypes: [.mp4, .mov])
        )
        let frameRate = normalizedFrameRate(Double(nominalFrameRate))
        let targetBitrate = outputPolicy.advancedOptions.targetBitrate
            ?? max(2_000_000, Int(Double(width * height) * frameRate * 0.25))
        let sourceFrameCount = max(
            1,
            Int((timeRange.duration.seconds * frameRate).rounded())
        )
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
            AVVideoExpectedSourceFrameRateKey: Int(frameRate.rounded()),
            AVVideoAllowFrameReorderingKey: false,
            AVVideoMaxKeyFrameIntervalKey: Int(frameRate.rounded()),
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel
        ]
        TaptionHEVCWriterPerformanceHints.apply(
            to: &compressionProperties,
            optimizationProfile: .performance,
            sourceFrameCount: sourceFrameCount
        )
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compressionProperties
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        videoInput.performsMultiPassEncodingIfSupported = false
        videoInput.transform = preferredTransform
        guard writer.canAdd(videoInput) else {
            throw TaptionVideoCoreError.exportFailed("Apple native fast-path HEVC writer input could not be added.")
        }
        writer.add(videoInput)

        let audioInput = audioFormatHint.map { formatHint in
            AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: nil,
                sourceFormatHint: formatHint
            )
        }
        if let audioInput {
            audioInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(audioInput) else {
                throw TaptionVideoCoreError.exportFailed("Apple native fast-path AAC passthrough input could not be added.")
            }
            writer.add(audioInput)
        }
        writer.shouldOptimizeForNetworkUse = false

        guard writer.startWriting() else {
            throw writer.error ?? TaptionVideoCoreError.exportFailed("Apple native fast-path writer could not start.")
        }
        writer.startSession(atSourceTime: timeRange.start)
        guard reader.startReading() else {
            writer.cancelWriting()
            throw reader.error ?? TaptionVideoCoreError.exportFailed("Apple native fast-path reader could not start.")
        }

        do {
            async let videoFrameCount = appendReaderWriterVideoSamples(
                output: videoOutput,
                input: videoInput,
                writer: writer,
                timeRange: timeRange,
                progressFrameStride: max(1, Int((frameRate / 2).rounded())),
                startedAt: startedAt,
                progressEmitter: progressEmitter
            )
            async let audioSampleBufferCount = appendReaderWriterAudioSamples(
                output: audioOutput,
                input: audioInput,
                writer: writer
            )
            let counts = try await (videoFrameCount, audioSampleBufferCount)
            guard reader.status == .completed else {
                throw reader.error ?? TaptionVideoCoreError.exportFailed("Apple native fast-path reader did not complete.")
            }
            guard counts.0 > 0 else {
                throw TaptionVideoCoreError.exportFailed("Apple native fast-path reader produced no video frames.")
            }

            await writer.finishWriting()
            guard writer.status == .completed,
                  FileManager.default.fileExists(atPath: request.outputURL.path) else {
                throw writer.error ?? TaptionVideoCoreError.exportFailed("Apple native fast-path writer did not finish.")
            }

            progressEmitter.submit(TaptionEncodingProgress(
                stage: .waitingForSaveGate,
                fractionCompleted: 1,
                elapsedTime: Date().timeIntervalSince(startedAt),
                estimatedRemainingTime: 0,
                currentFrame: Int64(counts.0),
                totalFrames: Int64(counts.0)
            ), force: true)
            trace.finish(
                "completed",
                metadata: [
                    "videoFrames": "\(counts.0)",
                    "audioSampleBuffers": "\(counts.1)",
                    "bitrate": "\(targetBitrate)"
                ]
            )
            return TaptionCodecTranscodeOutput(
                outputURL: request.outputURL,
                route: request.route,
                usedMode: .hardware,
                usedBackend: .appleVideoToolbox,
                outputVideoCodec: .hevc,
                outputAudioTrackCount: audioInput == nil ? 0 : 1
            )
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: request.outputURL)
            trace.finish("failed", metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    static func requestsCompressedVideoReaderWriterFastPath(_ request: TaptionCodecTranscodeRequest) -> Bool {
        let policy = request.options.outputPolicy
        let profile = policy.advancedOptions.optimizationProfile ?? .balanced
        let color = policy.advancedOptions.color
        return [.h264, .hevc, .proRes].contains(request.route.sourceCodec)
            && profile == .performance
            && [.mp4, .mov].contains(policy.container)
            && policy.audioCodec == .aac
            && policy.profile != .main10
            && color?.isHDR != true
            && (color?.bitDepth ?? 8) <= 8
    }

    private static func appendReaderWriterVideoSamples(
        output: AVAssetReaderTrackOutput,
        input: AVAssetWriterInput,
        writer: AVAssetWriter,
        timeRange: CMTimeRange,
        progressFrameStride: Int,
        startedAt: Date,
        progressEmitter: EncodingProgressEmitter
    ) async throws -> Int {
        var frameCount = 0
        let durationSeconds = timeRange.duration.seconds
        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                if writer.status == .failed || writer.status == .cancelled {
                    throw writer.error ?? TaptionVideoCoreError.exportFailed("Apple native fast-path video writer stopped.")
                }
                try await Task.sleep(nanoseconds: 100_000)
            }
            guard input.append(sampleBuffer) else {
                throw writer.error ?? TaptionVideoCoreError.exportFailed("Apple native fast-path video frame append failed.")
            }
            frameCount += 1
            guard frameCount == 1 || frameCount % progressFrameStride == 0 else {
                continue
            }
            let presentationSeconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                - timeRange.start.seconds
            let fraction = durationSeconds.isFinite && durationSeconds > 0
                ? min(max(presentationSeconds / durationSeconds, 0.01), 0.99)
                : min(Double(frameCount) / 1_000.0, 0.99)
            let elapsed = Date().timeIntervalSince(startedAt)
            let remaining = fraction > 0.02 ? max(0, elapsed * (1 - fraction) / fraction) : nil
            progressEmitter.submit(TaptionEncodingProgress(
                stage: .encoding,
                fractionCompleted: fraction,
                elapsedTime: elapsed,
                estimatedRemainingTime: remaining,
                currentFrame: Int64(frameCount),
                totalFrames: nil
            ))
        }
        input.markAsFinished()
        return frameCount
    }

    private static func appendReaderWriterAudioSamples(
        output: AVAssetReaderTrackOutput?,
        input: AVAssetWriterInput?,
        writer: AVAssetWriter
    ) async throws -> Int {
        guard let output, let input else { return 0 }
        var sampleBufferCount = 0
        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                if writer.status == .failed || writer.status == .cancelled {
                    throw writer.error ?? TaptionVideoCoreError.exportFailed("Apple native fast-path audio writer stopped.")
                }
                try await Task.sleep(nanoseconds: 250_000)
            }
            guard input.append(sampleBuffer) else {
                throw writer.error ?? TaptionVideoCoreError.exportFailed("Apple native fast-path audio append failed.")
            }
            sampleBufferCount += 1
        }
        input.markAsFinished()
        return sampleBufferCount
    }

    private static func normalizedFrameRate(_ value: Double) -> Double {
        guard value.isFinite, value >= 1, value <= 240 else { return 30 }
        return value
    }

    private static func normalizedRotationDegrees(_ value: Int) -> Int {
        ((value % 360) + 360) % 360
    }

    private static func rotationDegrees(from transform: CGAffineTransform) -> Int {
        let radians = atan2(transform.b, transform.a)
        return normalizedRotationDegrees(Int((radians * 180 / .pi).rounded()))
    }

    private static func formatDescriptionIsHDR(_ description: CMFormatDescription) -> Bool {
        guard let rawExtensions = CMFormatDescriptionGetExtensions(description) else {
            return false
        }
        let extensions = rawExtensions as NSDictionary
        guard let transferFunction = extensions[
            kCMFormatDescriptionExtension_TransferFunction
        ] as? String else {
            return false
        }
        return transferFunction == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
            || transferFunction == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
    }

    private static func transcodeAppleNativeStillImageVideo(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        let startedAt = Date()
        let asset = AVURLAsset(url: request.sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw TaptionVideoCoreError.exportFailed("The Apple native still-image video has no video track.")
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        guard naturalSize.width > 0,
              naturalSize.height > 0 else {
            throw TaptionVideoCoreError.exportFailed("The Apple native still-image video has invalid dimensions.")
        }

        try FileManager.default.createDirectory(
            at: request.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: request.outputURL)

        let usesCompressedStillImageSamples = request.route.sourceCodec == .jpegXL
        let reader: AVAssetReader?
        let readerOutput: AVAssetReaderTrackOutput?
        if !usesCompressedStillImageSamples {
            do {
                reader = try AVAssetReader(asset: asset)
            } catch {
                throw TaptionVideoCoreError.exportFailed(
                    "The Apple native still-image reader could not be created: \(error.localizedDescription)"
                )
            }
            let trackOutput = AVAssetReaderTrackOutput(
                track: videoTrack,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
            )
            trackOutput.alwaysCopiesSampleData = false
            readerOutput = trackOutput
            guard reader?.canAdd(trackOutput) == true else {
                throw TaptionVideoCoreError.exportFailed("The Apple native still-image decoder could not be attached.")
            }
            reader?.add(trackOutput)
        } else {
            reader = nil
            readerOutput = nil
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(
                outputURL: request.outputURL,
                fileType: avFileType(
                    for: request.options.outputPolicy.container,
                    supportedFileTypes: [.mp4, .mov]
                )
            )
        } catch {
            throw TaptionVideoCoreError.exportFailed(
                "The Apple native still-image H.265 writer could not be created: \(error.localizedDescription)"
            )
        }
        let width = max(2, Int(naturalSize.width.rounded()))
        let height = max(2, Int(naturalSize.height.rounded()))
        let targetBitrate = request.options.outputPolicy.advancedOptions.targetBitrate
            ?? max(1_000_000, width * height * 5)
        let optimizationProfile = request.options.outputPolicy.advancedOptions.optimizationProfile
            ?? .balanced
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: writerVideoOutputSettings(
                width: width,
                height: height,
                targetBitrate: targetBitrate,
                optimizationProfile: optimizationProfile
            )
        )
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = preferredTransform
        let writerAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(writerInput) else {
            throw TaptionVideoCoreError.exportFailed("The H.265 writer could not accept Apple native decoded frames.")
        }
        writer.add(writerInput)
        writer.shouldOptimizeForNetworkUse = optimizationProfile != .performance

        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))
        guard writer.startWriting() else {
            throw writer.error ?? TaptionVideoCoreError.exportFailed("The H.265 writer could not start.")
        }
        writer.startSession(atSourceTime: .zero)
        if let reader,
           !reader.startReading() {
            writer.cancelWriting()
            throw reader.error ?? TaptionVideoCoreError.exportFailed("The Apple native still-image decoder could not start.")
        }

        do {
            let duration = try await asset.load(.duration).seconds
            var frameCount = 0
            if usesCompressedStillImageSamples {
                guard try await videoTrack.load(.canProvideSampleCursors),
                      let cursor = videoTrack.makeSampleCursorAtFirstSampleInDecodeOrder() else {
                    throw TaptionVideoCoreError.exportFailed("The JPEG XL track cannot provide sample locations.")
                }
                while true {
                    try Task.checkCancellation()
                    while !writerInput.isReadyForMoreMediaData {
                        try Task.checkCancellation()
                        try await Task.sleep(nanoseconds: 5_000_000)
                    }
                    guard let pixelBufferPool = writerAdaptor.pixelBufferPool else {
                        throw TaptionVideoCoreError.exportFailed("The H.265 writer pixel buffer pool is unavailable.")
                    }
                    let sampleRange = cursor.currentSampleStorageRange
                    guard sampleRange.offset >= 0,
                          sampleRange.length > 0 else {
                        throw TaptionVideoCoreError.exportFailed("The JPEG XL sample is not stored contiguously.")
                    }
                    let sampleURL = cursor.currentChunkStorageURL ?? request.sourceURL
                    let data = try readCompressedStillImageData(
                        at: sampleURL,
                        offset: UInt64(sampleRange.offset),
                        length: Int(sampleRange.length)
                    )
                    let pixelBuffer = try decodeCompressedStillImageData(
                        data,
                        pixelBufferPool: pixelBufferPool,
                        width: width,
                        height: height
                    )
                    let presentationTime = cursor.presentationTimeStamp
                    guard writerAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                        throw writer.error ?? TaptionVideoCoreError.exportFailed("A decoded JPEG XL frame could not be appended.")
                    }
                    frameCount += 1
                    submitStillImageProgress(
                        presentationTime: presentationTime,
                        duration: duration,
                        frameCount: frameCount,
                        startedAt: startedAt,
                        progress: progress
                    )
                    guard cursor.stepInDecodeOrder(byCount: 1) == 1 else {
                        break
                    }
                }
            } else {
                while let sampleBuffer = readerOutput?.copyNextSampleBuffer() {
                    try Task.checkCancellation()
                    while !writerInput.isReadyForMoreMediaData {
                        try Task.checkCancellation()
                        try await Task.sleep(nanoseconds: 5_000_000)
                    }
                    guard let pixelBufferPool = writerAdaptor.pixelBufferPool else {
                        throw TaptionVideoCoreError.exportFailed("The H.265 writer pixel buffer pool is unavailable.")
                    }
                    let pixelBuffer = try decodeStillImageSample(
                        sampleBuffer,
                        pixelBufferPool: pixelBufferPool,
                        width: width,
                        height: height
                    )
                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    guard writerAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                        throw writer.error ?? TaptionVideoCoreError.exportFailed("A decoded still-image frame could not be appended.")
                    }
                    frameCount += 1
                    submitStillImageProgress(
                        presentationTime: presentationTime,
                        duration: duration,
                        frameCount: frameCount,
                        startedAt: startedAt,
                        progress: progress
                    )
                }
            }
            if let reader,
               reader.status != .completed {
                throw reader.error ?? TaptionVideoCoreError.exportFailed("Apple native still-image decoding did not complete.")
            }
            guard frameCount > 0 else {
                throw TaptionVideoCoreError.exportFailed("Apple native still-image decoding produced no frames.")
            }

            writerInput.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw writer.error ?? TaptionVideoCoreError.exportFailed("H.265 still-image video writing did not complete.")
            }
            progress(TaptionEncodingProgress(
                stage: .waitingForSaveGate,
                fractionCompleted: 1,
                elapsedTime: Date().timeIntervalSince(startedAt),
                estimatedRemainingTime: 0,
                currentFrame: Int64(frameCount),
                totalFrames: Int64(frameCount)
            ))
        } catch {
            reader?.cancelReading()
            writerInput.markAsFinished()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: request.outputURL)
            throw error
        }

        return TaptionCodecTranscodeOutput(
            outputURL: request.outputURL,
            route: request.route,
            usedMode: .software,
            usedBackend: .appleAVAssetExport,
            outputVideoCodec: .hevc,
            outputAudioTrackCount: 0
        )
    }

    private static func writerVideoOutputSettings(
        width: Int,
        height: Int,
        targetBitrate: Int,
        optimizationProfile: TaptionEncodingOptimizationProfile
    ) -> [String: Any] {
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate,
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel
        ]
        TaptionHEVCWriterPerformanceHints.apply(
            to: &compressionProperties,
            optimizationProfile: optimizationProfile
        )
        var outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        outputSettings[AVVideoCompressionPropertiesKey] = compressionProperties
        return outputSettings
    }

    private static func submitStillImageProgress(
        presentationTime: CMTime,
        duration: Double,
        frameCount: Int,
        startedAt: Date,
        progress: (TaptionEncodingProgress) -> Void
    ) {
        let presentationSeconds = presentationTime.seconds
        let fraction = duration.isFinite && duration > 0
            ? min(max(presentationSeconds / duration, 0.01), 0.99)
            : min(0.99, Double(frameCount) / 100.0)
        progress(TaptionEncodingProgress(
            stage: .encoding,
            fractionCompleted: fraction,
            elapsedTime: Date().timeIntervalSince(startedAt),
            estimatedRemainingTime: nil,
            currentFrame: Int64(frameCount),
            totalFrames: nil
        ))
    }

    private static func decodeStillImageSample(
        _ sampleBuffer: CMSampleBuffer,
        pixelBufferPool: CVPixelBufferPool,
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            return imageBuffer
        }
        let data = try compressedStillImageData(from: sampleBuffer)
        return try decodeCompressedStillImageData(
            data,
            pixelBufferPool: pixelBufferPool,
            width: width,
            height: height
        )
    }

    private static func decodeCompressedStillImageData(
        _ data: Data,
        pixelBufferPool: CVPixelBufferPool,
        width: Int,
        height: Int
    ) throws -> CVPixelBuffer {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw TaptionVideoCoreError.exportFailed("ImageIO could not decode the still-image video sample.")
        }

        var optionalPixelBuffer: CVPixelBuffer?
        let pixelBufferStatus = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            pixelBufferPool,
            &optionalPixelBuffer
        )
        guard pixelBufferStatus == kCVReturnSuccess,
              let pixelBuffer = optionalPixelBuffer else {
            throw TaptionVideoCoreError.exportFailed("A still-image decode pixel buffer could not be created.")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                    | CGImageAlphaInfo.premultipliedFirst.rawValue
              ) else {
            throw TaptionVideoCoreError.exportFailed("The still-image decode drawing context could not be created.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private static func readCompressedStillImageData(
        at url: URL,
        offset: UInt64,
        length: Int
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: length),
              data.count == length else {
            throw TaptionVideoCoreError.exportFailed("The compressed still-image sample could not be read completely.")
        }
        return data
    }

    private static func compressedStillImageData(
        from sampleBuffer: CMSampleBuffer
    ) throws -> Data {
        if let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            let dataLength = CMBlockBufferGetDataLength(dataBuffer)
            var data = Data(count: dataLength)
            let copyStatus = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(
                    dataBuffer,
                    atOffset: 0,
                    dataLength: dataLength,
                    destination: bytes.baseAddress!
                )
            }
            guard copyStatus == kCMBlockBufferNoErr else {
                throw TaptionVideoCoreError.exportFailed("The compressed still-image sample could not be copied.")
            }
            return data
        }

        var attachmentMode = kCMAttachmentMode_ShouldNotPropagate
        guard let referenceURLAttachment = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_SampleReferenceURL,
            attachmentModeOut: &attachmentMode
        ),
        let byteOffsetAttachment = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_SampleReferenceByteOffset,
            attachmentModeOut: &attachmentMode
        ) else {
            let attachments = CMCopyDictionaryOfAttachments(
                allocator: kCFAllocatorDefault,
                target: sampleBuffer,
                attachmentMode: kCMAttachmentMode_ShouldNotPropagate
            )
            throw TaptionVideoCoreError.exportFailed(
                "The still-image video sample has no compressed data or sample reference. Attachments: \(String(describing: attachments))"
            )
        }
        let referenceURL = referenceURLAttachment as! NSURL as URL
        let byteOffset = byteOffsetAttachment as! NSNumber
        let dataLength = CMSampleBufferGetTotalSampleSize(sampleBuffer)
        guard dataLength > 0 else {
            throw TaptionVideoCoreError.exportFailed("The still-image sample reference has no byte length.")
        }

        let handle = try FileHandle(forReadingFrom: referenceURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: byteOffset.uint64Value)
        guard let data = try handle.read(upToCount: dataLength),
              data.count == dataLength else {
            throw TaptionVideoCoreError.exportFailed("The still-image sample reference could not be read completely.")
        }
        return data
    }

    private static func videoCompositionIfNeeded(
        for asset: AVAsset,
        targetSize: TaptionPixelSize?,
        targetFrameRate: TaptionRationalFrameRate?
    ) async throws -> AVMutableVideoComposition? {
        guard targetSize?.isValid == true || targetFrameRate != nil else {
            return nil
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            return nil
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let displayedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let displayedSize = CGSize(
            width: abs(displayedRect.width),
            height: abs(displayedRect.height)
        )
        guard displayedSize.width > 0,
              displayedSize.height > 0 else {
            return nil
        }

        let renderSize: CGSize
        if let targetSize,
           targetSize.isValid {
            renderSize = evenSize(CGSize(
                width: CGFloat(targetSize.width),
                height: CGFloat(targetSize.height)
            ))
        } else {
            renderSize = evenSize(displayedSize)
        }

        let targetFrameRateValue = targetFrameRate?.value
        let frameRateShouldChange = targetFrameRateValue.map { target in
            target.isFinite
                && target > 0
                && nominalFrameRate.isFinite
                && nominalFrameRate > 0
                && abs(Double(nominalFrameRate) - target) > 0.1
        } ?? false
        let sizeShouldChange = !sizesAreEquivalent(displayedSize, renderSize)

        guard renderSize.width > 0,
              renderSize.height > 0,
              sizeShouldChange || frameRateShouldChange else {
            return nil
        }

        let scale = min(
            renderSize.width / displayedSize.width,
            renderSize.height / displayedSize.height
        )
        let scaledSize = CGSize(
            width: displayedSize.width * scale,
            height: displayedSize.height * scale
        )
        let originTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -displayedRect.minX, y: -displayedRect.minY)
        )
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let centeringTransform = CGAffineTransform(
            translationX: (renderSize.width - scaledSize.width) / 2,
            y: (renderSize.height - scaledSize.height) / 2
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(
            originTransform
                .concatenating(scaleTransform)
                .concatenating(centeringTransform),
            at: .zero
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = frameDuration(for: targetFrameRateValue ?? Double(nominalFrameRate))
        composition.instructions = [instruction]
        return composition
    }

    private static func resolvedTargetSize(
        for request: TaptionCodecTranscodeRequest,
        asset: AVAsset
    ) async throws -> TaptionPixelSize? {
        if let requestedSize = request.options.outputPolicy.advancedOptions.resizeTo {
            return requestedSize
        }
        guard request.route.sourceCodec == .proResRaw,
              let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let displayedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let width = abs(displayedRect.width)
        let height = abs(displayedRect.height)
        guard width > 0,
              height > 0,
              (width > 3_840 || height > 2_160) else {
            return nil
        }

        let scale = min(3_840 / width, 2_160 / height)
        let targetWidth = max(2, Int((width * scale).rounded(.down)) / 2 * 2)
        let targetHeight = max(2, Int((height * scale).rounded(.down)) / 2 * 2)
        return TaptionPixelSize(width: targetWidth, height: targetHeight)
    }

    private static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: CGFloat(evenDimension(size.width)),
            height: CGFloat(evenDimension(size.height))
        )
    }

    private static func evenDimension(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded - 1
    }

    private static func sizesAreEquivalent(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width.rounded() - rhs.width.rounded()) < 1
            && abs(lhs.height.rounded() - rhs.height.rounded()) < 1
    }

    private static func frameDuration(for nominalFrameRate: Double) -> CMTime {
        guard nominalFrameRate.isFinite,
              nominalFrameRate > 0 else {
            return CMTime(value: 1, timescale: 30)
        }
        return CMTime(seconds: 1.0 / nominalFrameRate, preferredTimescale: 600)
    }

    private static func export(_ exportSessionBox: HW_AppleHEVCExportSessionBox) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                exportSessionBox.exportAsynchronously {
                    switch exportSessionBox.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .failed:
                        continuation.resume(throwing: exportSessionBox.error ?? TaptionVideoCoreError.exportFailed("H.265 export failed."))
                    default:
                        continuation.resume(throwing: TaptionVideoCoreError.exportFailed("H.265 export ended with status \(exportSessionBox.status.rawValue)."))
                    }
                }
            }
        } onCancel: {
            exportSessionBox.cancelExport()
        }
    }

    private static func avFileType(
        for container: TaptionVideoContainer,
        supportedFileTypes: [AVFileType]
    ) -> AVFileType {
        let preferred: AVFileType
        switch container {
        case .mov:
            preferred = .mov
        case .m4v:
            preferred = .m4v
        default:
            preferred = .mp4
        }
        if supportedFileTypes.contains(preferred) {
            return preferred
        }
        if supportedFileTypes.contains(.mp4) {
            return .mp4
        }
        return supportedFileTypes.first ?? .mov
    }
}

private final class HW_AppleHEVCExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }

    var progress: Float {
        session.progress
    }

    var status: AVAssetExportSession.Status {
        session.status
    }

    var error: Error? {
        session.error
    }

    func exportAsynchronously(completionHandler: @escaping () -> Void) {
        session.exportAsynchronously(completionHandler: completionHandler)
    }

    func cancelExport() {
        session.cancelExport()
    }
}
