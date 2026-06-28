import AudioToolbox
import CLibVLC
@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation

struct SW_AV1HEVCTranscodeConfiguration {
    let targetSize: CGSize
    let targetBitrate: Int
    let frameDuration: CMTime
    let expectedFrameCount: Int
    let limitsToExpectedFrameCount: Bool
    let duration: CMTime
    let outputURL: URL
    let outputFileType: AVFileType

    static func make(
        asset: TaptionVideoAsset,
        outputURL: URL,
        options: TaptionCodecTranscodeOptions = .preservingSource()
    ) throws -> SW_AV1HEVCTranscodeConfiguration {
        guard let videoTrack = asset.videoTrack else {
            throw TaptionVideoCoreError.noVideoTrack
        }

        let requestedSize = options.outputPolicy.advancedOptions.resizeTo.map {
            CGSize(width: $0.width, height: $0.height)
        }
        let displaySize = CGSize(
            width: CGFloat(max(videoTrack.displaySize.width, 2)),
            height: CGFloat(max(videoTrack.displaySize.height, 2))
        )
        let targetSize = evenSize(requestedSize ?? displaySize)
        let fps = normalizedFPS(
            options.outputPolicy.advancedOptions.frameRate?.value
                ?? videoTrack.nominalFrameRate?.value
                ?? 30
        )
        let targetBitrate = normalizedBitrate(
            options.outputPolicy.advancedOptions.targetBitrate,
            targetSize: targetSize
        )
        let hasKnownDuration = asset.duration.map { $0.isFinite && $0 > 0 } ?? false
        let durationSeconds = hasKnownDuration ? max(asset.duration ?? 0, 0) : 0
        let duration = CMTime(seconds: durationSeconds, preferredTimescale: 600)
        let progressDurationSeconds = hasKnownDuration ? durationSeconds : 1
        let expectedFrameCount = max(1, Int((progressDurationSeconds * fps).rounded()))

        return SW_AV1HEVCTranscodeConfiguration(
            targetSize: targetSize,
            targetBitrate: targetBitrate,
            frameDuration: CMTime(seconds: 1.0 / fps, preferredTimescale: 600),
            expectedFrameCount: expectedFrameCount,
            limitsToExpectedFrameCount: hasKnownDuration,
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

    private static func normalizedBitrate(
        _ requestedBitrate: Int?,
        targetSize: CGSize
    ) -> Int {
        if let requestedBitrate, requestedBitrate > 0 {
            return max(requestedBitrate, 300_000)
        }
        return max(Int(targetSize.width * targetSize.height * 6), 2_000_000)
    }
}

private struct SW_AV1NativeAudioEncodingConfiguration {
    let sourceTrack: TaptionAudioTrackInfo
    let sampleRate: Double
    let channelCount: Int
    let targetBitrate: Int

    var writerOutputSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVEncoderBitRateKey: targetBitrate
        ]
    }

    static func make(
        asset: TaptionVideoAsset,
        request: TaptionCodecTranscodeRequest
    ) -> SW_AV1NativeAudioEncodingConfiguration? {
        guard request.options.preserveAudioWhenPossible,
              request.options.outputPolicy.audioCodec == .aac,
              [.mp4, .mov].contains(request.options.outputPolicy.container),
              let sourceTrack = asset.audioTracks.first,
              SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: sourceTrack.codec,
                outputCodec: request.options.outputPolicy.audioCodec,
                outputContainer: request.options.outputPolicy.container
              ) == .softwareVLCDecoder else {
            return nil
        }

        let resolvedOptions = TaptionSourcePreservingAudioOptionsResolver.resolvedOptions(
            for: sourceTrack,
            requestedOptions: .preservingSource(
                outputCodec: request.options.outputPolicy.audioCodec,
                outputContainer: request.options.outputPolicy.container
            )
        )
        let sampleRate = normalizedSampleRate(
            resolvedOptions.sampleRate ?? sourceTrack.sampleRate ?? 48_000
        )
        let channelCount = normalizedChannelCount(
            resolvedOptions.channelCount ?? sourceTrack.channelCount ?? 2
        )
        let targetBitrate = normalizedBitrate(
            resolvedOptions.targetBitrate ?? sourceTrack.estimatedBitrate,
            sampleRate: sampleRate,
            channelCount: channelCount
        )

        return SW_AV1NativeAudioEncodingConfiguration(
            sourceTrack: sourceTrack,
            sampleRate: sampleRate,
            channelCount: channelCount,
            targetBitrate: targetBitrate
        )
    }

    private static func normalizedSampleRate(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return 48_000
        }
        return min(max(value.rounded(), 8_000), 96_000)
    }

    private static func normalizedChannelCount(_ value: Int) -> Int {
        min(max(value, 1), 8)
    }

    private static func normalizedBitrate(
        _ value: Int?,
        sampleRate: Double,
        channelCount: Int
    ) -> Int {
        if let value, value > 0 {
            return min(max(value, 64_000), 768_000)
        }

        let perChannelBudget = sampleRate >= 48_000 ? 96_000 : 80_000
        return min(max(channelCount * perChannelBudget, 96_000), 512_000)
    }
}

private struct SW_AV1SoftwareTranscodeRunStats {
    var outputAudioTrackCount: Int
    var frameCount: Int
    var videoBackpressureWaitCount: Int
    var videoBackpressureWaitMicroseconds: Int64
    var audioSampleBufferCount: Int
    var audioSampleCount: Int64
    var audioBackpressureWaitCount: Int
    var audioBackpressureWaitMicroseconds: Int64
    var finishDurationMilliseconds: String
    var totalDurationMilliseconds: String
}

enum SW_AV1HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .av1,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "AV1 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try validate(request: request, sourceCodec: .av1)
        return try await transcodeToHEVC(
            request: request,
            sourceCodecLabel: "AV1",
            progress: progress
        )
    }
}

enum SW_H264HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .h264,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "H.264 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .h264)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "H.264",
            progress: progress
        )
    }
}

enum SW_HEVCHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .hevc,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "H.265 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .hevc)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "H.265 / HEVC",
            progress: progress
        )
    }
}

enum SW_VP9HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .vp9,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "VP9 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .vp9)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "VP9",
            progress: progress
        )
    }
}

enum SW_VP8HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .vp8,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "VP8 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .vp8)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "VP8",
            progress: progress
        )
    }
}

enum SW_MPEG2HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .mpeg2,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "MPEG-2 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .mpeg2)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "MPEG-2",
            progress: progress
        )
    }
}

enum SW_MPEG1HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .mpeg1,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "MPEG-1 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .mpeg1)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "MPEG-1",
            progress: progress
        )
    }
}

enum SW_MPEG4VisualHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .mpeg4Visual,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "MPEG-4 Visual to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .mpeg4Visual)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "MPEG-4 Visual",
            progress: progress
        )
    }
}

enum SW_H263HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .h263,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "H.263 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .h263)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "H.263",
            progress: progress
        )
    }
}

enum SW_H261HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .h261,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "H.261 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .h261)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "H.261",
            progress: progress
        )
    }
}

enum SW_FlashVideoHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .flashVideo,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Flash Video to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .flashVideo)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Flash Video",
            progress: progress
        )
    }
}

enum SW_MicrosoftMPEG4V2HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .microsoftMPEG4V2,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Microsoft MPEG-4 V2 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .microsoftMPEG4V2)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Microsoft MPEG-4 V2",
            progress: progress
        )
    }
}

enum SW_MicrosoftMPEG4V3HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .microsoftMPEG4V3,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Microsoft MPEG-4 V3 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .microsoftMPEG4V3)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Microsoft MPEG-4 V3",
            progress: progress
        )
    }
}

enum SW_MotionJPEGHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .motionJPEG,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Motion JPEG to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .motionJPEG)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Motion JPEG",
            progress: progress
        )
    }
}

enum SW_JPEG2000HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .jpeg2000,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "JPEG 2000 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .jpeg2000)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "JPEG 2000",
            progress: progress
        )
    }
}

enum SW_JPEGLSHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .jpegLS,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "JPEG-LS to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .jpegLS)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "JPEG-LS",
            progress: progress
        )
    }
}

enum SW_LosslessJPEGHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .losslessJPEG,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Lossless JPEG to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .losslessJPEG)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Lossless JPEG",
            progress: progress
        )
    }
}

enum SW_AnimationHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .animation,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Apple Animation to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .animation)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Apple Animation",
            progress: progress
        )
    }
}

enum SW_CinepakHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .cinepak,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Cinepak to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .cinepak)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Cinepak",
            progress: progress
        )
    }
}

enum SW_SorensonVideoHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .sorensonVideo,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Sorenson Video to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .sorensonVideo)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Sorenson Video",
            progress: progress
        )
    }
}

enum SW_SorensonVideo3HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .sorensonVideo3,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Sorenson Video 3 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .sorensonVideo3)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Sorenson Video 3",
            progress: progress
        )
    }
}

enum SW_QuickTimeVideoHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .quickTimeVideo,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "QuickTime Video to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .quickTimeVideo)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "QuickTime Video",
            progress: progress
        )
    }
}

enum SW_TheoraHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .theora,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Theora to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .theora)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Theora",
            progress: progress
        )
    }
}

enum SW_WMVHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .wmv,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Windows Media Video to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .wmv)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Windows Media Video",
            progress: progress
        )
    }
}

enum SW_MicrosoftVideo1HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .microsoftVideo1,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Microsoft Video 1 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .microsoftVideo1)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Microsoft Video 1",
            progress: progress
        )
    }
}

enum SW_ASUSV1HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .asusV1,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "ASUS V1 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .asusV1)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "ASUS V1",
            progress: progress
        )
    }
}

enum SW_ASUSV2HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .asusV2,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "ASUS V2 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .asusV2)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "ASUS V2",
            progress: progress
        )
    }
}

enum SW_FlashScreenVideoHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .flashScreenVideo,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Flash Screen Video to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .flashScreenVideo)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Flash Screen Video",
            progress: progress
        )
    }
}

enum SW_FlashScreenVideo2HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .flashScreenVideo2,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Flash Screen Video 2 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .flashScreenVideo2)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Flash Screen Video 2",
            progress: progress
        )
    }
}

enum SW_ZMBVHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .zmbv,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "ZMBV to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .zmbv)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "ZMBV",
            progress: progress
        )
    }
}

enum SW_CLJRHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .cljr,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "CLJR to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .cljr)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "CLJR",
            progress: progress
        )
    }
}

enum SW_V410HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .v410,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "V410 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .v410)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "V410",
            progress: progress
        )
    }
}

enum SW_FFV1HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .ffv1,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "FFV1 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .ffv1)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "FFV1",
            progress: progress
        )
    }
}

enum SW_HuffYUVHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .huffYUV,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "HuffYUV to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .huffYUV)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "HuffYUV",
            progress: progress
        )
    }
}

enum SW_DVCProHDHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .dvcProHD,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "DVCPro HD to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .dvcProHD)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "DVCPro HD",
            progress: progress
        )
    }
}

enum SW_DVHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .dv,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "DV to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .dv)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "DV",
            progress: progress
        )
    }
}

enum SW_YUV4HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .yuv4,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "YUV4 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .yuv4)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "YUV4",
            progress: progress
        )
    }
}

enum SW_CineFormHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .cineForm,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "GoPro CineForm to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .cineForm)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "GoPro CineForm",
            progress: progress
        )
    }
}

enum SW_DNxHDHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .dnxhd,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "DNxHD to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .dnxhd)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "DNxHD",
            progress: progress
        )
    }
}

enum SW_V308HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .v308,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "V308 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .v308)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "V308",
            progress: progress
        )
    }
}

enum SW_V408HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .v408,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "V408 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .v408)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "V408",
            progress: progress
        )
    }
}

enum SW_V210HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .v210,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "V210 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .v210)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "V210",
            progress: progress
        )
    }
}

extension SW_AV1HEVCTranscoder {
    static func validate(
        request: TaptionCodecTranscodeRequest,
        sourceCodec: TaptionVideoCodec
    ) throws {
        let actualRoute = TaptionCodecRoute(
            sourceCodec: sourceCodec,
            outputCodec: request.options.outputPolicy.videoCodec
        )
        guard request.route == TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: .hevc),
              request.options.outputPolicy.videoCodec == .hevc else {
            throw TaptionCodecTranscodingRegistryError.requestRouteMismatch(
                expected: TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: .hevc),
                actual: actualRoute
            )
        }
    }

    static func transcodeToHEVC(
        request: TaptionCodecTranscodeRequest,
        sourceCodecLabel: String,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        let startedAt = Date()
        let trace = TaptionEncodingPerformanceTrace(
            name: "software_hevc_transcode",
            category: .encoding,
            metadata: [
                "source": request.sourceURL.lastPathComponent,
                "route": request.route.displayName,
                "codec": sourceCodecLabel,
                "output": request.outputURL.lastPathComponent
            ]
        )
        let progressEmitter = EncodingProgressEmitter(progress: progress)
        do {
            let asset = try await AVFoundationMediaInspector().inspectVideo(at: request.sourceURL)
            trace.mark(
                "inspection_complete",
                metadata: [
                    "duration": asset.duration.map { String(format: "%.3f", $0) } ?? "unknown",
                    "audioTracks": "\(asset.audioTracks.count)"
                ]
            )
            let configuration = try SW_AV1HEVCTranscodeConfiguration.make(
                asset: asset,
                outputURL: request.outputURL,
                options: request.options
            )
            let audioConfiguration = SW_AV1NativeAudioEncodingConfiguration.make(
                asset: asset,
                request: request
            )

            progressEmitter.submit(TaptionEncodingProgress(
                stage: .preparing,
                fractionCompleted: 0.02,
                elapsedTime: 0,
                estimatedRemainingTime: nil
            ), force: true)

            let runStats: SW_AV1SoftwareTranscodeRunStats
            do {
                runStats = try await transcode(
                    sourceURL: request.sourceURL,
                    configuration: configuration,
                    audioConfiguration: audioConfiguration,
                    sourceCodecLabel: sourceCodecLabel
                ) { fraction in
                    let normalizedFraction = min(max(fraction, 0.02), 0.99)
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining = normalizedFraction > 0.02
                        ? max(0, elapsed * (1 - normalizedFraction) / normalizedFraction)
                        : nil
                    progressEmitter.submit(TaptionEncodingProgress(
                        stage: .encoding,
                        fractionCompleted: normalizedFraction,
                        elapsedTime: elapsed,
                        estimatedRemainingTime: remaining,
                        currentFrame: Int64((Double(configuration.expectedFrameCount) * normalizedFraction).rounded()),
                        totalFrames: Int64(configuration.expectedFrameCount)
                    ))
                }
            } catch let error as NSError where isNoFrameDecodeTimeout(error) {
                AppLogger.warning(
                    "Software \(sourceCodecLabel) decoder produced no frames; retrying with a fresh decoder",
                    category: .encoding,
                    metadata: ["source": request.sourceURL.lastPathComponent]
                )
                progressEmitter.submit(TaptionEncodingProgress(
                    stage: .preparing,
                    fractionCompleted: 0.02,
                    elapsedTime: Date().timeIntervalSince(startedAt),
                    estimatedRemainingTime: nil
                ), force: true)
                runStats = try await transcode(
                    sourceURL: request.sourceURL,
                    configuration: configuration,
                    audioConfiguration: audioConfiguration,
                    sourceCodecLabel: sourceCodecLabel
                ) { fraction in
                    let normalizedFraction = min(max(fraction, 0.02), 0.99)
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining = normalizedFraction > 0.02
                        ? max(0, elapsed * (1 - normalizedFraction) / normalizedFraction)
                        : nil
                    progressEmitter.submit(TaptionEncodingProgress(
                        stage: .encoding,
                        fractionCompleted: normalizedFraction,
                        elapsedTime: elapsed,
                        estimatedRemainingTime: remaining,
                        currentFrame: Int64((Double(configuration.expectedFrameCount) * normalizedFraction).rounded()),
                        totalFrames: Int64(configuration.expectedFrameCount)
                    ))
                }
            }

            progressEmitter.submit(TaptionEncodingProgress(
                stage: .waitingForSaveGate,
                fractionCompleted: 1,
                elapsedTime: Date().timeIntervalSince(startedAt),
                estimatedRemainingTime: 0,
                currentFrame: Int64(configuration.expectedFrameCount),
                totalFrames: Int64(configuration.expectedFrameCount)
            ), force: true)
            let progressStats = progressEmitter.stats
            trace.finish(
                "completed",
                metadata: [
                    "frames": "\(runStats.frameCount)",
                    "progressObserved": "\(progressStats.observedCount)",
                    "progressEmitted": "\(progressStats.emittedCount)",
                    "videoBackpressureWaits": "\(runStats.videoBackpressureWaitCount)",
                    "videoBackpressureMs": TaptionEncodingPerformanceTrace.milliseconds(
                        Double(runStats.videoBackpressureWaitMicroseconds) / 1_000_000.0
                    ),
                    "audioSampleBuffers": "\(runStats.audioSampleBufferCount)",
                    "audioSamples": "\(runStats.audioSampleCount)",
                    "audioBackpressureWaits": "\(runStats.audioBackpressureWaitCount)",
                    "audioBackpressureMs": TaptionEncodingPerformanceTrace.milliseconds(
                        Double(runStats.audioBackpressureWaitMicroseconds) / 1_000_000.0
                    ),
                    "finishMs": runStats.finishDurationMilliseconds,
                    "totalMs": runStats.totalDurationMilliseconds
                ]
            )

            return TaptionCodecTranscodeOutput(
                outputURL: request.outputURL,
                route: request.route,
                usedMode: .software,
                usedBackend: .softwareVLCDecoder,
                outputVideoCodec: request.options.outputPolicy.videoCodec,
                outputAudioTrackCount: runStats.outputAudioTrackCount
            )
        } catch is CancellationError {
            trace.finish("cancelled")
            throw CancellationError()
        } catch {
            trace.finish("failed", metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    private static func transcode(
        sourceURL: URL,
        configuration: SW_AV1HEVCTranscodeConfiguration,
        audioConfiguration: SW_AV1NativeAudioEncodingConfiguration?,
        sourceCodecLabel: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> SW_AV1SoftwareTranscodeRunStats {
        let pipelineStartedAt = Date()
        AppLogger.info(
            "Software \(sourceCodecLabel) transcode pipeline starting",
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
            outputSettings: writerVideoOutputSettings(
                targetSize: configuration.targetSize,
                targetBitrate: configuration.targetBitrate
            )
        )
        videoInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes(size: configuration.targetSize)
        )
        let audioContext: SW_AV1AudioWriterContext?

        guard writer.canAdd(videoInput) else {
            AppLogger.error("Software \(sourceCodecLabel) writer could not add video input", category: .encoding)
            throw NSError(
                domain: "TaptionEncoder",
                code: -100,
                userInfo: [NSLocalizedDescriptionKey: "Failed to add the software \(sourceCodecLabel) H.265 video input."]
            )
        }
        writer.add(videoInput)

        if let audioConfiguration {
            let audioInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioConfiguration.writerOutputSettings
            )
            audioInput.expectsMediaDataInRealTime = false

            guard writer.canAdd(audioInput) else {
                AppLogger.error(
                    "Software \(sourceCodecLabel) writer could not add audio input",
                    category: .encoding
                )
                throw NSError(
                    domain: "TaptionEncoder",
                    code: -111,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to add the bundled software audio input."]
                )
            }

            writer.add(audioInput)
            audioContext = try SW_AV1AudioWriterContext(
                audioInput: audioInput,
                configuration: audioConfiguration
            )
        } else {
            audioContext = nil
        }

        guard writer.startWriting() else {
            AppLogger.error(
                "Software \(sourceCodecLabel) writer failed to start",
                category: .encoding,
                metadata: ["error": writer.error?.localizedDescription ?? "unknown"]
            )
            throw writer.error ?? NSError(
                domain: "TaptionEncoder",
                code: -101,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start the software \(sourceCodecLabel) H.265 writer."]
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
            limitsToExpectedFrameCount: configuration.limitsToExpectedFrameCount,
            progressHandler: progressHandler
        )
        let videoOpaque = Unmanaged.passRetained(context).toOpaque()
        let audioOpaque = audioContext.map { Unmanaged.passRetained($0).toOpaque() }
        let instance = try makeInstance()
        let media = try makeMedia(sourceURL: sourceURL, allowsAudio: audioContext != nil)
        guard let player = libvlc_media_player_new_from_media(instance, media) else {
            AppLogger.error("Software \(sourceCodecLabel) decoder player creation failed", category: .encoding)
            libvlc_media_release(media)
            libvlc_release(instance)
            if let audioOpaque {
                Unmanaged<SW_AV1AudioWriterContext>.fromOpaque(audioOpaque).release()
            }
            Unmanaged<SW_AV1FrameWriterContext>.fromOpaque(videoOpaque).release()
            throw NSError(
                domain: "TaptionEncoder",
                code: -102,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create the software \(sourceCodecLabel) decoder."]
            )
        }

        defer {
            context.requestCancellation()
            audioContext?.requestCancellation()
            _ = libvlc_media_player_stop_async(player)
            waitForVLCQuiescence(player)
            libvlc_video_set_callbacks(player, nil, nil, nil, nil)
            context.clearDecodePool()
            libvlc_media_player_release(player)
            libvlc_media_release(media)
            libvlc_release(instance)
            if let audioOpaque {
                Unmanaged<SW_AV1AudioWriterContext>.fromOpaque(audioOpaque).release()
            }
            Unmanaged<SW_AV1FrameWriterContext>.fromOpaque(videoOpaque).release()
        }

        libvlc_video_set_callbacks(
            player,
            av1SoftwareVLCLockCallback,
            av1SoftwareVLCUnlockCallback,
            av1SoftwareVLCDisplayCallback,
            videoOpaque
        )
        libvlc_video_set_format_callbacks(
            player,
            av1SoftwareVLCFormatCallback,
            av1SoftwareVLCCleanupCallback
        )
        if let audioContext, let audioOpaque {
            libvlc_audio_set_callbacks(
                player,
                av1SoftwareVLCAudioPlayCallback,
                nil,
                nil,
                av1SoftwareVLCAudioFlushCallback,
                av1SoftwareVLCAudioDrainCallback,
                audioOpaque
            )
            "S16N".withCString { format in
                libvlc_audio_set_format(
                    player,
                    format,
                    UInt32(audioContext.sampleRate),
                    UInt32(audioContext.channelCount)
                )
            }
        }

        guard libvlc_media_player_play(player) == 0 else {
            AppLogger.error("Software \(sourceCodecLabel) decoder failed to start playback", category: .encoding)
            throw NSError(
                domain: "TaptionEncoder",
                code: -103,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start the software \(sourceCodecLabel) decoder."]
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
            if let error = audioContext?.snapshotError() {
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

            if audioContext == nil,
               configuration.limitsToExpectedFrameCount,
               context.didReachExpectedFrameCount,
               !stopRequested {
                stopRequested = true
                _ = libvlc_media_player_stop_async(player)
            }

            let state = libvlc_media_player_get_state(player)
            if sawAnyFrame {
                let audioDidDrain = audioContext?.didDrain ?? true
                let playbackPosition = libvlc_media_player_get_position(player)
                let playbackTimeMilliseconds = libvlc_media_player_get_time(player)
                let playbackTimeSeconds = playbackTimeMilliseconds > 0
                    ? Double(playbackTimeMilliseconds) / 1000.0
                    : 0
                let idleDuration = ProcessInfo.processInfo.systemUptime - lastFrameProgressUptime
                if (state == libvlc_Stopped || state == libvlc_Stopping),
                   audioDidDrain,
                   idleDuration > max(0.5, configuration.frameDuration.seconds * 6) {
                    break
                }
                if stopRequested,
                   audioDidDrain,
                   idleDuration > max(1.0, configuration.frameDuration.seconds * 12) {
                    break
                }
                if configuration.limitsToExpectedFrameCount {
                    let isNearPlaybackEnd = playbackPosition >= 0.995
                        || playbackTimeSeconds >= max(configuration.duration.seconds - 0.25, 0)
                    if isNearPlaybackEnd,
                       audioDidDrain,
                       idleDuration > max(0.5, configuration.frameDuration.seconds * 6) {
                        break
                    }
                }
            }

            if state == libvlc_Error {
                AppLogger.error(
                    "Software \(sourceCodecLabel) decoder entered error state",
                    category: .encoding,
                    metadata: ["source": sourceURL.lastPathComponent]
                )
                throw NSError(
                    domain: "TaptionEncoder",
                    code: -104,
                    userInfo: [NSLocalizedDescriptionKey: "Software \(sourceCodecLabel) decoding failed."]
                )
            }

            if !sawAnyFrame,
               ProcessInfo.processInfo.systemUptime - startUptime > 12 {
                AppLogger.error(
                    "Software \(sourceCodecLabel) decoder produced no frames before timeout",
                    category: .encoding,
                    metadata: ["source": sourceURL.lastPathComponent]
                )
                throw NSError(
                    domain: "TaptionEncoder",
                    code: -105,
                    userInfo: [NSLocalizedDescriptionKey: "Software \(sourceCodecLabel) decoding did not produce frames."]
                )
            }

            try await Task.sleep(nanoseconds: 50_000_000)
        }

        if let error = context.snapshotError() {
            AppLogger.error(
                "Software \(sourceCodecLabel) writer context reported error",
                category: .encoding,
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }
        if let error = audioContext?.snapshotError() {
            AppLogger.error(
                "Software audio writer context reported error",
                category: .encoding,
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }

        try context.finishVideoInput()
        try audioContext?.finishAudioInput()
        let finishStartedAt = Date()
        try await finishWriter(writer)
        let finishDuration = Date().timeIntervalSince(finishStartedAt)
        let videoMetrics = context.metricsSnapshot()
        let audioMetrics = audioContext?.metricsSnapshot()
        AppLogger.info(
            "Software \(sourceCodecLabel) transcode pipeline completed",
            category: .encoding,
            metadata: [
                "source": sourceURL.lastPathComponent,
                "output": configuration.outputURL.lastPathComponent,
                "frames": "\(videoMetrics.frameCount)",
                "videoBackpressureWaits": "\(videoMetrics.backpressureWaitCount)",
                "audioSampleBuffers": "\(audioMetrics?.sampleBufferCount ?? 0)"
            ]
        )
        return SW_AV1SoftwareTranscodeRunStats(
            outputAudioTrackCount: audioContext?.didWriteAnySamples == true ? 1 : 0,
            frameCount: videoMetrics.frameCount,
            videoBackpressureWaitCount: videoMetrics.backpressureWaitCount,
            videoBackpressureWaitMicroseconds: videoMetrics.backpressureWaitMicroseconds,
            audioSampleBufferCount: audioMetrics?.sampleBufferCount ?? 0,
            audioSampleCount: audioMetrics?.sampleCount ?? 0,
            audioBackpressureWaitCount: audioMetrics?.backpressureWaitCount ?? 0,
            audioBackpressureWaitMicroseconds: audioMetrics?.backpressureWaitMicroseconds ?? 0,
            finishDurationMilliseconds: TaptionEncodingPerformanceTrace.milliseconds(finishDuration),
            totalDurationMilliseconds: TaptionEncodingPerformanceTrace.milliseconds(
                Date().timeIntervalSince(pipelineStartedAt)
            )
        )
    }

    private static func throwIfCancelled() throws {
        if Task.isCancelled {
            throw CancellationError()
        }
    }

    private static func isNoFrameDecodeTimeout(_ error: NSError) -> Bool {
        error.domain == "TaptionEncoder" && error.code == -105
    }

    private static func writerVideoOutputSettings(
        targetSize: CGSize,
        targetBitrate: Int
    ) -> [String: Any] {
        let width = Int(max(targetSize.width.rounded(), 2))
        let height = Int(max(targetSize.height.rounded(), 2))
        return [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate
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

    private static func finishWriter(_ writer: AVAssetWriter) async throws {
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

    private static func makeMedia(sourceURL: URL, allowsAudio: Bool) throws -> OpaquePointer {
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

        if !allowsAudio {
            libvlc_media_add_option(media, ":no-audio")
        }
        if sourceURL.pathExtension.lowercased() == "h261" {
            libvlc_media_add_option(media, ":demux=avformat")
            libvlc_media_add_option(media, ":avformat-format=h261")
        }
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

private final class SW_AV1AudioWriterContext: @unchecked Sendable {
    private let audioInput: AVAssetWriterInput
    let sampleRate: Int
    let channelCount: Int
    private let bytesPerFrame: Int
    private let formatDescription: CMAudioFormatDescription
    private let stateLock = NSLock()
    private let writerQueue = DispatchQueue(label: "com.taption.encoder.av1-software.audio")

    nonisolated(unsafe) private var currentSampleCountStorage: Int64 = 0
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
        configuration: SW_AV1NativeAudioEncodingConfiguration
    ) throws {
        self.audioInput = audioInput
        self.sampleRate = max(Int(configuration.sampleRate.rounded()), 8_000)
        self.channelCount = max(configuration.channelCount, 1)
        self.bytesPerFrame = self.channelCount * MemoryLayout<Int16>.size
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
        let sampleData = Data(bytes: samples, count: byteCount)

        writerQueue.sync {
            stateLock.lock()
            let shouldAbort = cancellationRequested || pendingError != nil
            stateLock.unlock()
            guard !shouldAbort else { return }

            while !audioInput.isReadyForMoreMediaData {
                stateLock.lock()
                let cancelled = cancellationRequested || pendingError != nil
                backpressureWaitCountStorage += 1
                backpressureWaitMicrosecondsStorage += 2_000
                stateLock.unlock()
                if cancelled {
                    return
                }
                usleep(2_000)
            }

            do {
                let presentationTime = makePresentationTime(
                    ptsMicroseconds: ptsMicroseconds
                )
                let sampleBuffer = try makeSampleBuffer(
                    data: sampleData,
                    sampleCount: Int(sampleCount),
                    presentationTime: presentationTime
                )
                guard audioInput.append(sampleBuffer) else {
                    throw NSError(
                        domain: "TaptionEncoder",
                        code: -113,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to append bundled software audio samples."]
                    )
                }

                stateLock.lock()
                currentSampleCountStorage += Int64(sampleCount)
                sampleBufferCountStorage += 1
                didWriteAnySamplesStorage = true
                didDrainStorage = false
                stateLock.unlock()
            } catch {
                stateLock.lock()
                pendingError = error
                stateLock.unlock()
            }
        }
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

    private func makePresentationTime(
        ptsMicroseconds: Int64
    ) -> CMTime {
        stateLock.lock()
        if firstPTSMicrosecondsStorage == nil {
            firstPTSMicrosecondsStorage = ptsMicroseconds
        }
        let baseline = firstPTSMicrosecondsStorage ?? ptsMicroseconds
        let fallbackMicroseconds = (currentSampleCountStorage * 1_000_000) / Int64(max(sampleRate, 1))
        stateLock.unlock()

        let normalizedMicroseconds = max(ptsMicroseconds - baseline, fallbackMicroseconds)
        return CMTime(value: normalizedMicroseconds, timescale: 1_000_000)
    }

    private func makeSampleBuffer(
        data: Data,
        sampleCount: Int,
        presentationTime: CMTime
    ) throws -> CMSampleBuffer {
        let blockBuffer = try Self.makeBlockBuffer(from: data)
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
        from data: Data
    ) throws -> CMBlockBuffer {
        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
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

        let replaceStatus = data.withUnsafeBytes { rawBuffer in
            CMBlockBufferReplaceDataBytes(
                with: rawBuffer.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }

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

private final class SW_AV1FrameWriterContext: @unchecked Sendable {
    nonisolated(unsafe) private let writer: AVAssetWriter
    nonisolated(unsafe) private let videoInput: AVAssetWriterInput
    nonisolated(unsafe) private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let targetSize: CGSize
    private let frameDuration: CMTime
    private let expectedFrameCount: Int
    private let limitsToExpectedFrameCount: Bool
    nonisolated(unsafe) private let progressHandler: (Double) -> Void
    private let stateLock = NSLock()
    private let writerQueue = DispatchQueue(label: "com.taption.encoder.av1-software.writer")

    nonisolated(unsafe) private var decodePool: CVPixelBufferPool?
    nonisolated(unsafe) private var currentFrameCountStorage = 0
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
        progressHandler: @escaping (Double) -> Void
    ) {
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.targetSize = targetSize
        self.frameDuration = frameDuration
        self.expectedFrameCount = expectedFrameCount
        self.limitsToExpectedFrameCount = limitsToExpectedFrameCount
        self.progressHandler = progressHandler
    }

    nonisolated var currentFrameCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return currentFrameCountStorage
    }

    nonisolated var didReachExpectedFrameCount: Bool {
        limitsToExpectedFrameCount && currentFrameCount >= expectedFrameCount
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
            let reachedFrameLimit = limitsToExpectedFrameCount
                && currentFrameCountStorage >= expectedFrameCount
            let shouldAbort = cancellationRequested || pendingError != nil || reachedFrameLimit
            stateLock.unlock()
            guard !shouldAbort else { return }

            while !videoInput.isReadyForMoreMediaData {
                stateLock.lock()
                let cancelled = cancellationRequested || pendingError != nil
                backpressureWaitCountStorage += 1
                backpressureWaitMicrosecondsStorage += 2_000
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
            progressHandler(min(max(progress, 0), 1))
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
            videoInput.markAsFinished()
            return nil
        }

        if let finishError {
            throw finishError
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

nonisolated private func av1SoftwareAudioWriterContext(
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
