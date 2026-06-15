import CLibVLC
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import VideoToolbox

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
    private let lock = NSLock()
    private var activeExports: [UUID: AVAssetExportSession] = [:]

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

        try FileManager.default.createDirectory(
            at: temporaryOutputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: temporaryOutputURL)

        let asset = AVURLAsset(url: sourceURL)
        let selectedMode = HEVCEncoderCapability.selectedMode(for: plan.encoderSelection.requestedMode)
        let startedAt = Date()

        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))

        do {
            let presetName = try selectHEVCPreset(for: asset)
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
                throw TaptionVideoCoreError.compatibleHEVCPresetUnavailable
            }

            let outputFileType = exportSession.supportedFileTypes.contains(.mp4)
                ? AVFileType.mp4
                : (exportSession.supportedFileTypes.first ?? .mov)
            exportSession.outputURL = temporaryOutputURL
            exportSession.outputFileType = outputFileType
            exportSession.shouldOptimizeForNetworkUse = true

            let exportSessionBox = ExportSessionBox(exportSession)
            setActiveExport(exportSession, for: plan.id)

            let progressTask = Task { [exportSessionBox] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    let rawProgress = Double(exportSessionBox.progress)
                    let fraction = min(max(rawProgress, 0.01), 0.99)
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining = fraction > 0.02
                        ? max(0, elapsed * (1 - fraction) / fraction)
                        : nil
                    progress(TaptionEncodingProgress(
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

            do {
                try await export(exportSessionBox)
                progressTask.cancel()
                removeActiveExport(for: plan.id)
            } catch {
                progressTask.cancel()
                removeActiveExport(for: plan.id)
                throw error
            }

            guard FileManager.default.fileExists(atPath: temporaryOutputURL.path) else {
                throw TaptionVideoCoreError.exportFailed("The H.265 output file was not created.")
            }

            progress(TaptionEncodingProgress(
                stage: .waitingForSaveGate,
                fractionCompleted: 1,
                elapsedTime: Date().timeIntervalSince(startedAt),
                estimatedRemainingTime: 0
            ))

            return TaptionEncodingResult(
                planID: plan.id,
                temporaryOutputURL: temporaryOutputURL,
                finalOutputURL: plan.finalOutputURL,
                usedBackend: selectedMode.backend,
                usedMode: selectedMode.mode
            )
        } catch is CancellationError {
            removeActiveExport(for: plan.id)
            try? FileManager.default.removeItem(at: temporaryOutputURL)
            throw CancellationError()
        } catch let nativeError {
            removeActiveExport(for: plan.id)
            try? FileManager.default.removeItem(at: temporaryOutputURL)
            do {
                let fallbackSelection = try await encodeWithSoftwareFallback(
                    asset: asset,
                    sourceURL: sourceURL,
                    outputURL: temporaryOutputURL,
                    progress: progress
                )

                guard FileManager.default.fileExists(atPath: temporaryOutputURL.path) else {
                    throw TaptionVideoCoreError.exportFailed("The software fallback output file was not created.")
                }

                progress(TaptionEncodingProgress(
                    stage: .waitingForSaveGate,
                    fractionCompleted: 1,
                    elapsedTime: Date().timeIntervalSince(startedAt),
                    estimatedRemainingTime: 0
                ))

                return TaptionEncodingResult(
                    planID: plan.id,
                    temporaryOutputURL: temporaryOutputURL,
                    finalOutputURL: plan.finalOutputURL,
                    usedBackend: fallbackSelection.backend,
                    usedMode: fallbackSelection.mode
                )
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: temporaryOutputURL)
                throw CancellationError()
            } catch {
                try? FileManager.default.removeItem(at: temporaryOutputURL)
                throw TaptionVideoCoreError.exportFailed(
                    "Automatic codec path failed. Native: \(nativeError.localizedDescription). Software fallback: \(error.localizedDescription)"
                )
            }
        }
    }

    func cancelEncoding(planID: UUID) async {
        let exportSession = activeExport(for: planID)
        exportSession?.cancelExport()
        removeActiveExport(for: planID)
    }

    private func encodeWithSoftwareFallback(
        asset: AVAsset,
        sourceURL: URL,
        outputURL: URL,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> HEVCEncoderCapability.Selection {
        let startedAt = Date()
        let configuration = try await SoftwareAV1HEVCTranscodeConfiguration.make(
            asset: asset,
            outputURL: outputURL
        )

        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0.02,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))

        try await SoftwareAV1HEVCTranscoder.transcode(
            sourceURL: sourceURL,
            configuration: configuration
        ) { fraction in
            let normalizedFraction = min(max(fraction, 0.02), 0.99)
            let elapsed = Date().timeIntervalSince(startedAt)
            let remaining = normalizedFraction > 0.02
                ? max(0, elapsed * (1 - normalizedFraction) / normalizedFraction)
                : nil
            progress(TaptionEncodingProgress(
                stage: .encoding,
                fractionCompleted: normalizedFraction,
                elapsedTime: elapsed,
                estimatedRemainingTime: remaining,
                currentFrame: Int64((Double(configuration.expectedFrameCount) * normalizedFraction).rounded()),
                totalFrames: Int64(configuration.expectedFrameCount)
            ))
        }

        return HEVCEncoderCapability.Selection(
            mode: .software,
            backend: .softwareAV1Decoder
        )
    }

    private func selectHEVCPreset(for asset: AVAsset) throws -> String {
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

    private func export(_ exportSessionBox: ExportSessionBox) async throws {
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

    private func setActiveExport(_ exportSession: AVAssetExportSession, for planID: UUID) {
        lock.lock()
        activeExports[planID] = exportSession
        lock.unlock()
    }

    private func activeExport(for planID: UUID) -> AVAssetExportSession? {
        lock.lock()
        let exportSession = activeExports[planID]
        lock.unlock()
        return exportSession
    }

    private func removeActiveExport(for planID: UUID) {
        lock.lock()
        activeExports.removeValue(forKey: planID)
        lock.unlock()
    }
}

private final class ExportSessionBox: @unchecked Sendable {
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

    func exportAsynchronously(completionHandler handler: @escaping @Sendable () -> Void) {
        session.exportAsynchronously(completionHandler: handler)
    }

    func cancelExport() {
        session.cancelExport()
    }
}

private struct SoftwareAV1HEVCTranscodeConfiguration {
    let targetSize: CGSize
    let frameDuration: CMTime
    let expectedFrameCount: Int
    let duration: CMTime
    let outputURL: URL
    let outputFileType: AVFileType

    static func make(asset: AVAsset, outputURL: URL) async throws -> SoftwareAV1HEVCTranscodeConfiguration {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw TaptionVideoCoreError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = Double(try await videoTrack.load(.nominalFrameRate))
        let duration = try await asset.load(.duration)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let displaySize = CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )
        let targetSize = evenSize(displaySize)
        let fps = normalizedFPS(nominalFrameRate)
        let durationSeconds = duration.seconds.isFinite ? max(duration.seconds, 0) : 0
        let expectedFrameCount = max(1, Int((durationSeconds * fps).rounded()))

        return SoftwareAV1HEVCTranscodeConfiguration(
            targetSize: targetSize,
            frameDuration: CMTime(seconds: 1.0 / fps, preferredTimescale: 600),
            expectedFrameCount: expectedFrameCount,
            duration: duration,
            outputURL: outputURL,
            outputFileType: .mp4
        )
    }

    private static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: CGFloat(evenDimension(size.width)),
            height: CGFloat(evenDimension(size.height))
        )
    }

    private static func evenDimension(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }

    private static func normalizedFPS(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return 30
        }
        return min(max(value, 1), 240)
    }
}

private enum SoftwareAV1HEVCTranscoder {
    static func transcode(
        sourceURL: URL,
        configuration: SoftwareAV1HEVCTranscodeConfiguration,
        progressHandler: @escaping (Double) async -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: configuration.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: configuration.outputURL)

        let writer = try AVAssetWriter(
            outputURL: configuration.outputURL,
            fileType: configuration.outputFileType
        )
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: writerVideoOutputSettings(targetSize: configuration.targetSize)
        )
        videoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes(size: configuration.targetSize)
        )

        guard writer.canAdd(videoInput) else {
            throw NSError(
                domain: "TaptionEncoder",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey: "Failed to add the software AV1 H.265 video input."]
            )
        }
        writer.add(videoInput)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(
                domain: "TaptionEncoder",
                code: -101,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start the software AV1 H.265 writer."]
            )
        }
        writer.startSession(atSourceTime: .zero)

        let context = SoftwareAV1FrameWriterContext(
            writer: writer,
            videoInput: videoInput,
            adaptor: adaptor,
            targetSize: configuration.targetSize,
            frameDuration: configuration.frameDuration,
            expectedFrameCount: configuration.expectedFrameCount,
            progressHandler: progressHandler
        )
        let opaque = Unmanaged.passRetained(context).toOpaque()
        let instance = try makeInstance()
        let media = try makeMedia(sourceURL: sourceURL)
        guard let player = libvlc_media_player_new_from_media(instance, media) else {
            libvlc_media_release(media)
            libvlc_release(instance)
            Unmanaged<SoftwareAV1FrameWriterContext>.fromOpaque(opaque).release()
            throw NSError(
                domain: "TaptionEncoder",
                code: -102,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create the software AV1 decoder."]
            )
        }

        defer {
            context.requestCancellation()
            _ = libvlc_media_player_stop_async(player)
            waitForVLCQuiescence(player)
            libvlc_video_set_callbacks(player, nil, nil, nil, nil)
            context.clearDecodePool()
            libvlc_media_player_release(player)
            libvlc_media_release(media)
            libvlc_release(instance)
            Unmanaged<SoftwareAV1FrameWriterContext>.fromOpaque(opaque).release()
        }

        libvlc_video_set_callbacks(
            player,
            softwareAV1VLCLockCallback,
            softwareAV1VLCUnlockCallback,
            softwareAV1VLCDisplayCallback,
            opaque
        )
        libvlc_video_set_format_callbacks(
            player,
            softwareAV1VLCFormatCallback,
            softwareAV1VLCCleanupCallback
        )

        guard libvlc_media_player_play(player) == 0 else {
            throw NSError(
                domain: "TaptionEncoder",
                code: -103,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start the software AV1 decoder."]
            )
        }

        let startUptime = ProcessInfo.processInfo.systemUptime
        var stopRequested = false
        var sawAnyFrame = false
        var lastObservedFrameCount = 0
        var lastFrameProgressUptime = startUptime

        while true {
            try throwIfCancelled()

            if let error = context.snapshotError() {
                throw error
            }

            let frameCount = context.currentFrameCount
            if frameCount > 0 {
                sawAnyFrame = true
            }
            if frameCount != lastObservedFrameCount {
                lastObservedFrameCount = frameCount
                lastFrameProgressUptime = ProcessInfo.processInfo.systemUptime
            }

            if context.didReachExpectedFrameCount, !stopRequested {
                stopRequested = true
                _ = libvlc_media_player_stop_async(player)
            }

            let state = libvlc_media_player_get_state(player)
            if sawAnyFrame {
                let playbackPosition = libvlc_media_player_get_position(player)
                let playbackTimeMilliseconds = libvlc_media_player_get_time(player)
                let playbackTimeSeconds = playbackTimeMilliseconds > 0
                    ? Double(playbackTimeMilliseconds) / 1000.0
                    : 0
                let idleDuration = ProcessInfo.processInfo.systemUptime - lastFrameProgressUptime
                if (state == libvlc_Stopped || state == libvlc_Stopping),
                   idleDuration > max(0.5, configuration.frameDuration.seconds * 6) {
                    break
                }
                if stopRequested,
                   idleDuration > max(1.0, configuration.frameDuration.seconds * 12) {
                    break
                }
                let isNearPlaybackEnd = playbackPosition >= 0.995
                    || playbackTimeSeconds >= max(configuration.duration.seconds - 0.25, 0)
                if isNearPlaybackEnd,
                   idleDuration > max(0.5, configuration.frameDuration.seconds * 6) {
                    break
                }
            }

            if state == libvlc_Error {
                throw NSError(
                    domain: "TaptionEncoder",
                    code: -104,
                    userInfo: [NSLocalizedDescriptionKey: "Software AV1 decoding failed."]
                )
            }

            if !sawAnyFrame,
               ProcessInfo.processInfo.systemUptime - startUptime > 12 {
                throw NSError(
                    domain: "TaptionEncoder",
                    code: -105,
                    userInfo: [NSLocalizedDescriptionKey: "Software AV1 decoding did not produce frames."]
                )
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if let error = context.snapshotError() {
            throw error
        }
        try await context.finishWriting()
    }

    static func throwIfCancelled() throws {
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    private static func writerVideoOutputSettings(targetSize: CGSize) -> [String: Any] {
        let width = Int(max(targetSize.width.rounded(), 2))
        let height = Int(max(targetSize.height.rounded(), 2))
        let bitrate = max(Int(targetSize.width * targetSize.height * 6), 2_000_000)
        return [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate
            ]
        ]
    }

    private static func pixelBufferAttributes(size: CGSize) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(max(size.width.rounded(), 2)),
            kCVPixelBufferHeightKey as String: Int(max(size.height.rounded(), 2)),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
    }

    private static func makeInstance() throws -> OpaquePointer {
        let arguments = [
            "--no-video-title-show",
            "--no-snapshot-preview",
            "--avcodec-hw=none"
        ]
        let cArguments = arguments.map { strdup($0) }
        defer {
            for pointer in cArguments {
                free(pointer)
            }
        }

        let opaqueArguments = cArguments.map { UnsafePointer<CChar>($0) }
        let instance = opaqueArguments.withUnsafeBufferPointer { buffer -> OpaquePointer? in
            libvlc_new(Int32(buffer.count), buffer.baseAddress)
        }
        guard let instance else {
            throw NSError(
                domain: "TaptionEncoder",
                code: -106,
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize the software AV1 decoder."]
            )
        }
        return instance
    }

    private static func makeMedia(sourceURL: URL) throws -> OpaquePointer {
        let media: OpaquePointer?
        if sourceURL.isFileURL {
            media = sourceURL.path.withCString { libvlc_media_new_path($0) }
        } else {
            media = sourceURL.absoluteString.withCString { libvlc_media_new_location($0) }
        }

        guard let media else {
            throw NSError(
                domain: "TaptionEncoder",
                code: -107,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open the AV1 source in the software decoder."]
            )
        }

        libvlc_media_add_option(media, ":no-audio")
        libvlc_media_add_option(media, ":no-sub-autodetect-file")
        libvlc_media_add_option(media, ":no-snapshot-preview")
        libvlc_media_add_option(media, ":avcodec-hw=none")
        libvlc_media_add_option(media, ":no-drop-late-frames")
        libvlc_media_add_option(media, ":no-skip-frames")
        return media
    }

    private static func waitForVLCQuiescence(_ player: OpaquePointer) {
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        while ProcessInfo.processInfo.systemUptime < deadline {
            let state = libvlc_media_player_get_state(player)
            if (state == libvlc_Stopped || state == libvlc_Stopping || state == libvlc_Error),
               libvlc_media_player_has_vout(player) == 0 {
                return
            }
            usleep(20_000)
        }
    }
}

private final class SoftwareAV1FrameWriterContext: @unchecked Sendable {
    nonisolated(unsafe) private let writer: AVAssetWriter
    nonisolated(unsafe) private let videoInput: AVAssetWriterInput
    nonisolated(unsafe) private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let targetSize: CGSize
    private let frameDuration: CMTime
    private let expectedFrameCount: Int
    nonisolated(unsafe) private let progressHandler: (Double) async -> Void
    private let stateLock = NSLock()
    private let writerQueue = DispatchQueue(label: "com.taption.encoder.software-av1.writer")

    nonisolated(unsafe) private var decodePool: CVPixelBufferPool?
    nonisolated(unsafe) private var currentFrameCountStorage = 0
    nonisolated(unsafe) private var didWriteAnyFrame = false
    nonisolated(unsafe) private var pendingError: Error?
    nonisolated(unsafe) private var cancellationRequested = false

    init(
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        targetSize: CGSize,
        frameDuration: CMTime,
        expectedFrameCount: Int,
        progressHandler: @escaping (Double) async -> Void
    ) {
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.targetSize = targetSize
        self.frameDuration = frameDuration
        self.expectedFrameCount = expectedFrameCount
        self.progressHandler = progressHandler
    }

    nonisolated var currentFrameCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentFrameCountStorage
    }

    nonisolated var didReachExpectedFrameCount: Bool {
        currentFrameCount >= expectedFrameCount
    }

    nonisolated func snapshotError() -> Error? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingError
    }

    nonisolated func requestCancellation() {
        stateLock.lock()
        cancellationRequested = true
        stateLock.unlock()
    }

    nonisolated func clearDecodePool() {
        stateLock.lock()
        decodePool = nil
        stateLock.unlock()
    }

    nonisolated func prepareDecodePoolFormat() -> (width: UInt32, height: UInt32, pitch: UInt32)? {
        let width = Int(max(targetSize.width.rounded(), 2))
        let height = Int(max(targetSize.height.rounded(), 2))

        let pool: CVPixelBufferPool? = {
            stateLock.lock()
            defer { stateLock.unlock() }
            if let decodePool {
                return decodePool
            }
            let poolAttributes: [String: Any] = [
                kCVPixelBufferPoolMinimumBufferCountKey as String: 6
            ]
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]

            var newPool: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                poolAttributes as CFDictionary,
                pixelBufferAttributes as CFDictionary,
                &newPool
            )
            guard status == kCVReturnSuccess else {
                return nil
            }
            decodePool = newPool
            return newPool
        }()

        guard let pool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else {
            return nil
        }
        let pitch = UInt32(CVPixelBufferGetBytesPerRow(pixelBuffer))
        return (width: UInt32(width), height: UInt32(height), pitch: pitch)
    }

    nonisolated func makeDecodePixelBuffer() -> CVPixelBuffer? {
        stateLock.lock()
        let pool = decodePool
        stateLock.unlock()
        guard let pool else { return nil }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess else {
            return nil
        }
        return pixelBuffer
    }

    nonisolated func appendDecodedPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        writerQueue.sync {
            stateLock.lock()
            let shouldAbort = cancellationRequested || pendingError != nil || currentFrameCountStorage >= expectedFrameCount
            stateLock.unlock()
            guard !shouldAbort else { return }

            while !videoInput.isReadyForMoreMediaData {
                stateLock.lock()
                let cancelled = cancellationRequested || pendingError != nil
                stateLock.unlock()
                if cancelled {
                    return
                }
                usleep(2_000)
            }

            stateLock.lock()
            let frameIndex = currentFrameCountStorage
            stateLock.unlock()

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                let error = writer.error ?? NSError(
                    domain: "TaptionEncoder",
                    code: -108,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to append a software-decoded AV1 frame."]
                )
                stateLock.lock()
                pendingError = error
                stateLock.unlock()
                return
            }

            stateLock.lock()
            currentFrameCountStorage += 1
            didWriteAnyFrame = true
            let progress = Double(currentFrameCountStorage) / Double(max(expectedFrameCount, 1))
            stateLock.unlock()
            Task {
                await progressHandler(min(max(progress, 0), 1))
            }
        }
    }

    nonisolated func finishWriting() async throws {
        let finishError: Error? = writerQueue.sync {
            stateLock.lock()
            let pending = pendingError
            let wroteAnyFrame = didWriteAnyFrame
            stateLock.unlock()

            if let pending {
                return pending
            }
            guard wroteAnyFrame else {
                return NSError(
                    domain: "TaptionEncoder",
                    code: -109,
                    userInfo: [NSLocalizedDescriptionKey: "Software AV1 decoding did not produce frames."]
                )
            }
            videoInput.markAsFinished()
            return nil
        }

        if let finishError {
            writer.cancelWriting()
            throw finishError
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }

        guard writer.status == .completed,
              FileManager.default.fileExists(atPath: writer.outputURL.path) else {
            throw writer.error ?? NSError(
                domain: "TaptionEncoder",
                code: -110,
                userInfo: [NSLocalizedDescriptionKey: "Software AV1 H.265 output was not finalized."]
            )
        }
    }
}

nonisolated private func softwareAV1FrameWriterContext(
    from opaque: UnsafeMutableRawPointer?
) -> SoftwareAV1FrameWriterContext? {
    guard let opaque else { return nil }
    return Unmanaged<SoftwareAV1FrameWriterContext>.fromOpaque(opaque).takeUnretainedValue()
}

nonisolated func softwareAV1VLCFormatCallback(
    opaque: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    chroma: UnsafeMutablePointer<CChar>?,
    width: UnsafeMutablePointer<UInt32>?,
    height: UnsafeMutablePointer<UInt32>?,
    pitches: UnsafeMutablePointer<UInt32>?,
    lines: UnsafeMutablePointer<UInt32>?
) -> UInt32 {
    guard let opaque,
          let contextOpaque = opaque.pointee,
          let context = softwareAV1FrameWriterContext(from: contextOpaque),
          let chroma,
          let width,
          let height,
          let pitches,
          let lines,
          let format = context.prepareDecodePoolFormat() else {
        return 0
    }

    width.pointee = format.width
    height.pointee = format.height
    pitches.pointee = format.pitch
    lines.pointee = format.height

    let bgra: (CChar, CChar, CChar, CChar) = (0x42, 0x47, 0x52, 0x41)
    chroma[0] = bgra.0
    chroma[1] = bgra.1
    chroma[2] = bgra.2
    chroma[3] = bgra.3
    return 6
}

nonisolated func softwareAV1VLCCleanupCallback(opaque: UnsafeMutableRawPointer?) {
    softwareAV1FrameWriterContext(from: opaque)?.clearDecodePool()
}

nonisolated func softwareAV1VLCLockCallback(
    opaque: UnsafeMutableRawPointer?,
    planes: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> UnsafeMutableRawPointer? {
    guard let context = softwareAV1FrameWriterContext(from: opaque),
          let planes,
          let pixelBuffer = context.makeDecodePixelBuffer() else {
        return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    planes[0] = CVPixelBufferGetBaseAddress(pixelBuffer)
    return Unmanaged.passRetained(pixelBuffer as AnyObject).toOpaque()
}

nonisolated func softwareAV1VLCUnlockCallback(
    opaque _: UnsafeMutableRawPointer?,
    picture: UnsafeMutableRawPointer?,
    planes _: UnsafePointer<UnsafeMutableRawPointer?>?
) {
    guard let picture else { return }
    let pixelBuffer = Unmanaged<AnyObject>.fromOpaque(picture).takeUnretainedValue() as! CVPixelBuffer
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
}

nonisolated func softwareAV1VLCDisplayCallback(
    opaque: UnsafeMutableRawPointer?,
    picture: UnsafeMutableRawPointer?
) {
    guard let picture,
          let context = softwareAV1FrameWriterContext(from: opaque) else {
        return
    }
    let pixelBuffer = Unmanaged<AnyObject>.fromOpaque(picture).takeRetainedValue() as! CVPixelBuffer
    context.appendDecodedPixelBuffer(pixelBuffer)
}

private enum HEVCEncoderCapability {
    struct Selection {
        var mode: TaptionEncoderMode
        var backend: TaptionEncodingBackend
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

    private static var hasHardwareHEVCEncoder: Bool {
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
}
