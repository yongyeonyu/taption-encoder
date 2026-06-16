import CLibVLC
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation

struct SW_AV1HEVCTranscodeConfiguration {
    let targetSize: CGSize
    let frameDuration: CMTime
    let expectedFrameCount: Int
    let duration: CMTime
    let outputURL: URL
    let outputFileType: AVFileType

    static func make(
        asset: AVAsset,
        outputURL: URL,
        options: TaptionCodecTranscodeOptions = .preservingSource()
    ) async throws -> SW_AV1HEVCTranscodeConfiguration {
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
        let requestedSize = options.outputPolicy.advancedOptions.resizeTo.map {
            CGSize(width: $0.width, height: $0.height)
        }
        let targetSize = evenSize(requestedSize ?? displaySize)
        let fps = normalizedFPS(options.outputPolicy.advancedOptions.frameRate?.value ?? nominalFrameRate)
        let durationSeconds = duration.seconds.isFinite ? max(duration.seconds, 0) : 0
        let expectedFrameCount = max(1, Int((durationSeconds * fps).rounded()))

        return SW_AV1HEVCTranscodeConfiguration(
            targetSize: targetSize,
            frameDuration: CMTime(seconds: 1.0 / fps, preferredTimescale: 600),
            expectedFrameCount: expectedFrameCount,
            duration: duration,
            outputURL: outputURL,
            outputFileType: avFileType(for: options.outputPolicy.container)
        )
    }

    private static func avFileType(for container: TaptionVideoContainer) -> AVFileType {
        switch container {
        case .mov:
            return .mov
        case .m4v:
            return .m4v
        default:
            return .mp4
        }
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

enum SW_AV1HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .av1,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareAV1Decoder,
        displayName: "AV1 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        let startedAt = Date()
        let asset = AVURLAsset(url: request.sourceURL)
        let configuration = try await SW_AV1HEVCTranscodeConfiguration.make(
            asset: asset,
            outputURL: request.outputURL,
            options: request.options
        )

        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0.02,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))

        try await transcode(
            sourceURL: request.sourceURL,
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

        progress(TaptionEncodingProgress(
            stage: .waitingForSaveGate,
            fractionCompleted: 1,
            elapsedTime: Date().timeIntervalSince(startedAt),
            estimatedRemainingTime: 0,
            currentFrame: Int64(configuration.expectedFrameCount),
            totalFrames: Int64(configuration.expectedFrameCount)
        ))

        return TaptionCodecTranscodeOutput(
            outputURL: request.outputURL,
            route: request.route,
            usedMode: .software,
            usedBackend: .softwareAV1Decoder,
            outputVideoCodec: request.options.outputPolicy.videoCodec,
            outputAudioTrackCount: 0
        )
    }

    static func transcode(
        sourceURL: URL,
        configuration: SW_AV1HEVCTranscodeConfiguration,
        progressHandler: @escaping (Double) async -> Void
    ) async throws {
        AppLogger.info(
            "Software AV1 transcode pipeline starting",
            category: .encoding,
            metadata: ["source": sourceURL.lastPathComponent]
        )
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
            AppLogger.error("Software AV1 writer could not add video input", category: .encoding)
            throw NSError(
                domain: "TaptionEncoder",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey: "Failed to add the software AV1 H.265 video input."]
            )
        }
        writer.add(videoInput)
        guard writer.startWriting() else {
            AppLogger.error(
                "Software AV1 writer failed to start",
                category: .encoding,
                metadata: ["error": writer.error?.localizedDescription ?? "unknown"]
            )
            throw writer.error ?? NSError(
                domain: "TaptionEncoder",
                code: -101,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start the software AV1 H.265 writer."]
            )
        }
        writer.startSession(atSourceTime: .zero)

        let context = SW_AV1FrameWriterContext(
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
            AppLogger.error("Software AV1 decoder player creation failed", category: .encoding)
            libvlc_media_release(media)
            libvlc_release(instance)
            Unmanaged<SW_AV1FrameWriterContext>.fromOpaque(opaque).release()
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
            Unmanaged<SW_AV1FrameWriterContext>.fromOpaque(opaque).release()
        }

        libvlc_video_set_callbacks(
            player,
            av1SoftwareVLCLockCallback,
            av1SoftwareVLCUnlockCallback,
            av1SoftwareVLCDisplayCallback,
            opaque
        )
        libvlc_video_set_format_callbacks(
            player,
            av1SoftwareVLCFormatCallback,
            av1SoftwareVLCCleanupCallback
        )

        guard libvlc_media_player_play(player) == 0 else {
            AppLogger.error("Software AV1 decoder failed to start playback", category: .encoding)
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
                AppLogger.error(
                    "Software AV1 decoder entered error state",
                    category: .encoding,
                    metadata: ["source": sourceURL.lastPathComponent]
                )
                throw NSError(
                    domain: "TaptionEncoder",
                    code: -104,
                    userInfo: [NSLocalizedDescriptionKey: "Software AV1 decoding failed."]
                )
            }

            if !sawAnyFrame,
               ProcessInfo.processInfo.systemUptime - startUptime > 12 {
                AppLogger.error(
                    "Software AV1 decoder produced no frames before timeout",
                    category: .encoding,
                    metadata: ["source": sourceURL.lastPathComponent]
                )
                throw NSError(
                    domain: "TaptionEncoder",
                    code: -105,
                    userInfo: [NSLocalizedDescriptionKey: "Software AV1 decoding did not produce frames."]
                )
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if let error = context.snapshotError() {
            AppLogger.error(
                "Software AV1 writer context reported error",
                category: .encoding,
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }
        try await context.finishWriting()
        AppLogger.info(
            "Software AV1 transcode pipeline completed",
            category: .encoding,
            metadata: [
                "source": sourceURL.lastPathComponent,
                "output": configuration.outputURL.lastPathComponent
            ]
        )
    }

    private static func throwIfCancelled() throws {
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

private final class SW_AV1FrameWriterContext: @unchecked Sendable {
    nonisolated(unsafe) private let writer: AVAssetWriter
    nonisolated(unsafe) private let videoInput: AVAssetWriterInput
    nonisolated(unsafe) private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let targetSize: CGSize
    private let frameDuration: CMTime
    private let expectedFrameCount: Int
    nonisolated(unsafe) private let progressHandler: (Double) async -> Void
    private let stateLock = NSLock()
    private let writerQueue = DispatchQueue(label: "com.taption.encoder.av1-software.writer")

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

nonisolated private func av1SoftwareFrameWriterContext(
    from opaque: UnsafeMutableRawPointer?
) -> SW_AV1FrameWriterContext? {
    guard let opaque else { return nil }
    return Unmanaged<SW_AV1FrameWriterContext>.fromOpaque(opaque).takeUnretainedValue()
}

nonisolated func av1SoftwareVLCFormatCallback(
    opaque: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    chroma: UnsafeMutablePointer<CChar>?,
    width: UnsafeMutablePointer<UInt32>?,
    height: UnsafeMutablePointer<UInt32>?,
    pitches: UnsafeMutablePointer<UInt32>?,
    lines: UnsafeMutablePointer<UInt32>?
) -> UInt32 {
    guard let opaque,
          let contextOpaque = opaque.pointee,
          let context = av1SoftwareFrameWriterContext(from: contextOpaque),
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

nonisolated func av1SoftwareVLCCleanupCallback(opaque: UnsafeMutableRawPointer?) {
    av1SoftwareFrameWriterContext(from: opaque)?.clearDecodePool()
}

nonisolated func av1SoftwareVLCLockCallback(
    opaque: UnsafeMutableRawPointer?,
    planes: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> UnsafeMutableRawPointer? {
    guard let context = av1SoftwareFrameWriterContext(from: opaque),
          let planes,
          let pixelBuffer = context.makeDecodePixelBuffer() else {
        return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    planes[0] = CVPixelBufferGetBaseAddress(pixelBuffer)
    return Unmanaged.passRetained(pixelBuffer as AnyObject).toOpaque()
}

nonisolated func av1SoftwareVLCUnlockCallback(
    opaque _: UnsafeMutableRawPointer?,
    picture: UnsafeMutableRawPointer?,
    planes _: UnsafePointer<UnsafeMutableRawPointer?>?
) {
    guard let picture else { return }
    let pixelBuffer = Unmanaged<AnyObject>.fromOpaque(picture).takeUnretainedValue() as! CVPixelBuffer
    CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
}

nonisolated func av1SoftwareVLCDisplayCallback(
    opaque: UnsafeMutableRawPointer?,
    picture: UnsafeMutableRawPointer?
) {
    guard let picture,
          let context = av1SoftwareFrameWriterContext(from: opaque) else {
        return
    }
    let pixelBuffer = Unmanaged<AnyObject>.fromOpaque(picture).takeRetainedValue() as! CVPixelBuffer
    context.appendDecodedPixelBuffer(pixelBuffer)
}
