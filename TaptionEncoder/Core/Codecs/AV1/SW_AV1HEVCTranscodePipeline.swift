import AudioToolbox
import CLibVLC
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation

private final class SW_SendableSampleBufferBox: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer

    init(_ sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}

final class SW_AV1AudioWriterContext: @unchecked Sendable {
    private let audioInput: AVAssetWriterInput
    let sampleRate: Int
    let channelCount: Int
    private let bytesPerFrame: Int
    private let backpressureSleepMicroseconds: UInt32
    private let formatDescription: CMAudioFormatDescription
    private let stateLock = NSLock()
    private let writerQueue = DispatchQueue(label: "com.taption.encoder.av1-software.audio")
    private let sampleQueueSlots: DispatchSemaphore

    nonisolated(unsafe) private var currentSampleCountStorage: Int64 = 0
    nonisolated(unsafe) private var scheduledSampleCountStorage: Int64 = 0
    nonisolated(unsafe) private var pendingSampleBufferCountStorage = 0
    nonisolated(unsafe) private var sampleBufferCountStorage = 0
    nonisolated(unsafe) private var backpressureWaitCountStorage = 0
    nonisolated(unsafe) private var backpressureWaitMicrosecondsStorage: Int64 = 0
    nonisolated(unsafe) private var firstPTSMicrosecondsStorage: Int64?
    nonisolated(unsafe) private var didWriteAnySamplesStorage = false
    nonisolated(unsafe) private var didDrainStorage = false
    nonisolated(unsafe) private var pendingError: Error?
    nonisolated(unsafe) private var cancellationRequested = false

    init(
        audioInput: AVAssetWriterInput,
        configuration: SW_AV1NativeAudioEncodingConfiguration,
        maximumPendingSampleBufferCount: Int = 1,
        backpressureSleepMicroseconds: UInt32 = 2_000
    ) throws {
        self.audioInput = audioInput
        self.sampleRate = max(Int(configuration.sampleRate.rounded()), 8_000)
        self.channelCount = max(configuration.channelCount, 1)
        self.bytesPerFrame = self.channelCount * MemoryLayout<Int16>.size
        self.backpressureSleepMicroseconds = max(backpressureSleepMicroseconds, 100)
        self.sampleQueueSlots = DispatchSemaphore(value: max(maximumPendingSampleBufferCount, 1))
        self.formatDescription = try Self.makeFormatDescription(
            sampleRate: self.sampleRate,
            channelCount: self.channelCount,
            bytesPerFrame: self.bytesPerFrame
        )
    }

    nonisolated var didWriteAnySamples: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return didWriteAnySamplesStorage
    }

    nonisolated var didDrain: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return didDrainStorage
    }

    nonisolated var shouldAbort: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancellationRequested || pendingError != nil
    }

    nonisolated func snapshotError() -> Error? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingError
    }

    nonisolated func metricsSnapshot() -> (
        sampleBufferCount: Int,
        sampleCount: Int64,
        backpressureWaitCount: Int,
        backpressureWaitMicroseconds: Int64
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (
            sampleBufferCount: sampleBufferCountStorage,
            sampleCount: currentSampleCountStorage,
            backpressureWaitCount: backpressureWaitCountStorage,
            backpressureWaitMicroseconds: backpressureWaitMicrosecondsStorage
        )
    }

    nonisolated func requestCancellation() {
        stateLock.lock()
        cancellationRequested = true
        stateLock.unlock()
    }

    nonisolated func appendAudioSamples(
        _ samples: UnsafeRawPointer,
        sampleCount: UInt32,
        ptsMicroseconds: Int64
    ) {
        guard sampleCount > 0 else {
            return
        }

        let byteCount = Int(sampleCount) * bytesPerFrame

        while sampleQueueSlots.wait(timeout: .now() + .milliseconds(50)) != .success {
            stateLock.lock()
            let shouldAbort = cancellationRequested || pendingError != nil
            stateLock.unlock()
            if shouldAbort {
                return
            }
        }

        stateLock.lock()
        let shouldAbort = cancellationRequested || pendingError != nil
        if !shouldAbort {
            if firstPTSMicrosecondsStorage == nil {
                firstPTSMicrosecondsStorage = ptsMicroseconds
            }
            let baseline = firstPTSMicrosecondsStorage ?? ptsMicroseconds
            let fallbackMicroseconds = (scheduledSampleCountStorage * 1_000_000)
                / Int64(max(sampleRate, 1))
            let normalizedMicroseconds = max(ptsMicroseconds - baseline, fallbackMicroseconds)
            scheduledSampleCountStorage += Int64(sampleCount)
            pendingSampleBufferCountStorage += 1
            didDrainStorage = false
            stateLock.unlock()

            do {
                let sampleBuffer = try makeSampleBuffer(
                    samples: samples,
                    byteCount: byteCount,
                    sampleCount: Int(sampleCount),
                    presentationTime: CMTime(value: normalizedMicroseconds, timescale: 1_000_000)
                )
                enqueueSampleBuffer(sampleBuffer, sampleCount: Int(sampleCount))
            } catch {
                finishPendingSampleBuffer(error: error)
            }
        } else {
            stateLock.unlock()
            sampleQueueSlots.signal()
        }
    }

    private func enqueueSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        sampleCount: Int
    ) {
        let sampleBufferBox = SW_SendableSampleBufferBox(sampleBuffer)
        writerQueue.async { [self, sampleBufferBox] in
            defer { finishPendingSampleBuffer(error: nil) }

            stateLock.lock()
            let shouldAbort = cancellationRequested || pendingError != nil
            stateLock.unlock()
            guard !shouldAbort else { return }

            while !audioInput.isReadyForMoreMediaData {
                stateLock.lock()
                let cancelled = cancellationRequested || pendingError != nil
                backpressureWaitCountStorage += 1
                backpressureWaitMicrosecondsStorage += Int64(backpressureSleepMicroseconds)
                stateLock.unlock()
                if cancelled {
                    return
                }
                usleep(backpressureSleepMicroseconds)
            }

            guard audioInput.append(sampleBufferBox.sampleBuffer) else {
                stateLock.lock()
                pendingError = NSError(
                    domain: "TaptionEncoder",
                    code: -113,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to append bundled software audio samples."]
                )
                stateLock.unlock()
                return
            }

            stateLock.lock()
            currentSampleCountStorage += Int64(sampleCount)
            sampleBufferCountStorage += 1
            didWriteAnySamplesStorage = true
            stateLock.unlock()
        }
    }

    private func finishPendingSampleBuffer(error: Error?) {
        stateLock.lock()
        if pendingError == nil, let error {
            pendingError = error
        }
        pendingSampleBufferCountStorage = max(pendingSampleBufferCountStorage - 1, 0)
        stateLock.unlock()
        sampleQueueSlots.signal()
    }

    nonisolated func flush() {
        stateLock.lock()
        didDrainStorage = true
        stateLock.unlock()
    }

    nonisolated func markDrained() {
        stateLock.lock()
        didDrainStorage = true
        stateLock.unlock()
    }

    nonisolated func finishAudioInput() throws {
        let finishError: Error? = writerQueue.sync {
            stateLock.lock()
            let pending = pendingError
            let wroteAnySamples = didWriteAnySamplesStorage
            stateLock.unlock()

            if let pending {
                return pending
            }
            guard wroteAnySamples else {
                return NSError(
                    domain: "TaptionEncoder",
                    code: -114,
                    userInfo: [NSLocalizedDescriptionKey: "Bundled software audio decoding did not produce samples."]
                )
            }
            audioInput.markAsFinished()
            return nil
        }

        if let finishError {
            throw finishError
        }
    }

    private func makeSampleBuffer(
        samples: UnsafeRawPointer,
        byteCount: Int,
        sampleCount: Int,
        presentationTime: CMTime
    ) throws -> CMSampleBuffer {
        let blockBuffer = try Self.makeBlockBuffer(
            copying: samples,
            byteCount: byteCount
        )
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleSize = bytesPerFrame
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let sampleBuffer else {
            throw NSError(
                domain: "TaptionEncoder",
                code: -115,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create bundled software audio sample buffer."]
            )
        }
        return sampleBuffer
    }

    private static func makeFormatDescription(
        sampleRate: Int,
        channelCount: Int,
        bytesPerFrame: Int
    ) throws -> CMAudioFormatDescription {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var description: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &description
        )

        guard status == noErr, let description else {
            throw NSError(
                domain: "TaptionEncoder",
                code: -116,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create bundled software audio format description."]
            )
        }
        return description
    }

    private static func makeBlockBuffer(
        copying samples: UnsafeRawPointer,
        byteCount: Int
    ) throws -> CMBlockBuffer {
        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard createStatus == kCMBlockBufferNoErr,
              let blockBuffer else {
            throw NSError(
                domain: "TaptionEncoder",
                code: -117,
                userInfo: [NSLocalizedDescriptionKey: "Failed to allocate bundled software audio block buffer."]
            )
        }

        let replaceStatus = CMBlockBufferReplaceDataBytes(
            with: samples,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: byteCount
        )

        guard replaceStatus == kCMBlockBufferNoErr else {
            throw NSError(
                domain: "TaptionEncoder",
                code: -118,
                userInfo: [NSLocalizedDescriptionKey: "Failed to copy bundled software audio bytes into the block buffer."]
            )
        }

        return blockBuffer
    }
}

private final class SW_SendablePixelBufferBox: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer

    init(_ pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }
}

final class SW_AV1FrameWriterContext: @unchecked Sendable {
    nonisolated(unsafe) private let writer: AVAssetWriter
    nonisolated(unsafe) private let videoInput: AVAssetWriterInput
    nonisolated(unsafe) private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let targetSize: CGSize
    private let frameDuration: CMTime
    private let expectedFrameCount: Int
    private let limitsToExpectedFrameCount: Bool
    private let allowsLegacyFrameHoldToPreserveDuration: Bool
    private let progressFrameStride: Int
    private let backpressureSleepMicroseconds: UInt32
    nonisolated(unsafe) private let progressHandler: (Double) -> Void
    private let stateLock = NSLock()
    private let writerQueue = DispatchQueue(label: "com.taption.encoder.av1-software.writer")
    private let frameQueueSlots: DispatchSemaphore

    nonisolated(unsafe) private var decodePool: CVPixelBufferPool?
    nonisolated(unsafe) private var lastPixelBufferStorage: CVPixelBuffer?
    nonisolated(unsafe) private var currentFrameCountStorage = 0
    nonisolated(unsafe) private var pendingFrameCountStorage = 0
    nonisolated(unsafe) private var backpressureWaitCountStorage = 0
    nonisolated(unsafe) private var backpressureWaitMicrosecondsStorage: Int64 = 0
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
        limitsToExpectedFrameCount: Bool,
        allowsLegacyFrameHoldToPreserveDuration: Bool,
        progressFrameStride: Int = 1,
        maximumPendingFrameCount: Int = 1,
        backpressureSleepMicroseconds: UInt32 = 2_000,
        progressHandler: @escaping (Double) -> Void
    ) {
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.targetSize = targetSize
        self.frameDuration = frameDuration
        self.expectedFrameCount = expectedFrameCount
        self.limitsToExpectedFrameCount = limitsToExpectedFrameCount
        self.allowsLegacyFrameHoldToPreserveDuration = allowsLegacyFrameHoldToPreserveDuration
        self.progressFrameStride = max(progressFrameStride, 1)
        self.backpressureSleepMicroseconds = max(backpressureSleepMicroseconds, 100)
        self.progressHandler = progressHandler
        self.frameQueueSlots = DispatchSemaphore(value: max(maximumPendingFrameCount, 1))
    }

    nonisolated var currentFrameCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentFrameCountStorage
    }

    nonisolated var didReachExpectedFrameCount: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return limitsToExpectedFrameCount
            && currentFrameCountStorage + pendingFrameCountStorage >= expectedFrameCount
    }

    nonisolated var shouldAbort: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancellationRequested || pendingError != nil
    }

    nonisolated func snapshotError() -> Error? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingError
    }

    nonisolated func metricsSnapshot() -> (
        frameCount: Int,
        backpressureWaitCount: Int,
        backpressureWaitMicroseconds: Int64
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (
            frameCount: currentFrameCountStorage,
            backpressureWaitCount: backpressureWaitCountStorage,
            backpressureWaitMicroseconds: backpressureWaitMicrosecondsStorage
        )
    }

    nonisolated func requestCancellation() {
        stateLock.lock()
        cancellationRequested = true
        stateLock.unlock()
    }

    nonisolated func clearDecodePool() {
        stateLock.lock()
        decodePool = nil
        lastPixelBufferStorage = nil
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
        while frameQueueSlots.wait(timeout: .now() + .milliseconds(50)) != .success {
            stateLock.lock()
            let shouldAbort = cancellationRequested || pendingError != nil
            stateLock.unlock()
            if shouldAbort {
                return
            }
        }

        stateLock.lock()
        let reachedFrameLimit = limitsToExpectedFrameCount
            && currentFrameCountStorage + pendingFrameCountStorage >= expectedFrameCount
        let shouldAbort = cancellationRequested || pendingError != nil || reachedFrameLimit
        if !shouldAbort {
            pendingFrameCountStorage += 1
        }
        stateLock.unlock()
        guard !shouldAbort else {
            frameQueueSlots.signal()
            return
        }

        let pixelBufferBox = SW_SendablePixelBufferBox(pixelBuffer)
        writerQueue.async { [self, pixelBufferBox] in
            defer {
                stateLock.lock()
                pendingFrameCountStorage = max(pendingFrameCountStorage - 1, 0)
                stateLock.unlock()
                frameQueueSlots.signal()
            }

            stateLock.lock()
            let shouldAbort = cancellationRequested || pendingError != nil
            stateLock.unlock()
            guard !shouldAbort else { return }

            while !videoInput.isReadyForMoreMediaData {
                stateLock.lock()
                let cancelled = cancellationRequested || pendingError != nil
                backpressureWaitCountStorage += 1
                backpressureWaitMicrosecondsStorage += Int64(backpressureSleepMicroseconds)
                stateLock.unlock()
                if cancelled {
                    return
                }
                usleep(backpressureSleepMicroseconds)
            }

            stateLock.lock()
            let frameIndex = currentFrameCountStorage
            stateLock.unlock()

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            guard adaptor.append(pixelBufferBox.pixelBuffer, withPresentationTime: presentationTime) else {
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
            lastPixelBufferStorage = pixelBufferBox.pixelBuffer
            let progress = Double(currentFrameCountStorage) / Double(max(expectedFrameCount, 1))
            let shouldReportProgress = currentFrameCountStorage == 1
                || currentFrameCountStorage % progressFrameStride == 0
            stateLock.unlock()
            if shouldReportProgress {
                progressHandler(min(max(progress, 0), 1))
            }
        }
    }

    nonisolated func finishVideoInput() throws {
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
            if let holdError = appendHeldFramesToExpectedDurationIfNeeded() {
                return holdError
            }
            videoInput.markAsFinished()
            return nil
        }

        if let finishError {
            throw finishError
        }
    }

    private func appendHeldFramesToExpectedDurationIfNeeded() -> Error? {
        stateLock.lock()
        let shouldHoldFrames = allowsLegacyFrameHoldToPreserveDuration
            && limitsToExpectedFrameCount
            && didWriteAnyFrame
            && currentFrameCountStorage < expectedFrameCount
            && pendingError == nil
            && !cancellationRequested
        let pixelBuffer = lastPixelBufferStorage
        stateLock.unlock()

        guard shouldHoldFrames,
              let pixelBuffer else {
            return nil
        }

        let holdStartedAt = ProcessInfo.processInfo.systemUptime
        let frameHoldTimeout = max(
            20.0,
            frameDuration.seconds * Double(max(expectedFrameCount - currentFrameCountStorage, 1)) * 4
        )
        while true {
            stateLock.lock()
            let shouldStop = cancellationRequested
                || pendingError != nil
                || currentFrameCountStorage >= expectedFrameCount
            stateLock.unlock()

            if shouldStop {
                stateLock.lock()
                let pending = pendingError
                stateLock.unlock()
                return pending
            }

            while !videoInput.isReadyForMoreMediaData {
                stateLock.lock()
                let cancelled = cancellationRequested || pendingError != nil
                backpressureWaitCountStorage += 1
                backpressureWaitMicrosecondsStorage += Int64(backpressureSleepMicroseconds)
                stateLock.unlock()
                if cancelled {
                    stateLock.lock()
                    let pending = pendingError
                    stateLock.unlock()
                    return pending
                }
                if ProcessInfo.processInfo.systemUptime - holdStartedAt > frameHoldTimeout {
                    return nil
                }
                usleep(backpressureSleepMicroseconds)
            }

            stateLock.lock()
            let frameIndex = currentFrameCountStorage
            stateLock.unlock()

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                let error = writer.error ?? NSError(
                    domain: "TaptionEncoder",
                    code: -119,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to append a held legacy software-decoded frame."]
                )
                stateLock.lock()
                pendingError = error
                stateLock.unlock()
                return error
            }

            stateLock.lock()
            currentFrameCountStorage += 1
            let progress = Double(currentFrameCountStorage) / Double(max(expectedFrameCount, 1))
            let shouldReportProgress = currentFrameCountStorage == 1
                || currentFrameCountStorage % progressFrameStride == 0
            stateLock.unlock()
            if shouldReportProgress {
                progressHandler(min(max(progress, 0), 1))
            }
        }
    }
}

nonisolated func av1SoftwareFrameWriterContext(
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

nonisolated func av1SoftwareAudioWriterContext(
    from opaque: UnsafeMutableRawPointer?
) -> SW_AV1AudioWriterContext? {
    guard let opaque else { return nil }
    return Unmanaged<SW_AV1AudioWriterContext>.fromOpaque(opaque).takeUnretainedValue()
}

nonisolated func av1SoftwareVLCAudioPlayCallback(
    opaque: UnsafeMutableRawPointer?,
    samples: UnsafeRawPointer?,
    count: UInt32,
    pts: Int64
) {
    guard let context = av1SoftwareAudioWriterContext(from: opaque),
          let samples else {
        return
    }
    context.appendAudioSamples(samples, sampleCount: count, ptsMicroseconds: pts)
}

nonisolated func av1SoftwareVLCAudioFlushCallback(
    opaque: UnsafeMutableRawPointer?,
    pts _: Int64
) {
    av1SoftwareAudioWriterContext(from: opaque)?.flush()
}

nonisolated func av1SoftwareVLCAudioDrainCallback(
    opaque: UnsafeMutableRawPointer?
) {
    av1SoftwareAudioWriterContext(from: opaque)?.markDrained()
}
