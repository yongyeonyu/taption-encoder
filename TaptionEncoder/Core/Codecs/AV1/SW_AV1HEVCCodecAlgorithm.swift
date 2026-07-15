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
    let allowsLegacyFrameHoldToPreserveDuration: Bool
    let duration: CMTime
    let outputURL: URL
    let outputFileType: AVFileType
    let optimizationProfile: TaptionEncodingOptimizationProfile
    let color: TaptionColorDescription

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
        let allowsLegacyFrameHoldToPreserveDuration = videoTrack.codec == .quickTimeVideo

        return SW_AV1HEVCTranscodeConfiguration(
            targetSize: targetSize,
            targetBitrate: targetBitrate,
            frameDuration: CMTime(seconds: 1.0 / fps, preferredTimescale: 600),
            expectedFrameCount: expectedFrameCount,
            limitsToExpectedFrameCount: hasKnownDuration,
            allowsLegacyFrameHoldToPreserveDuration: allowsLegacyFrameHoldToPreserveDuration,
            duration: duration,
            outputURL: outputURL,
            outputFileType: avFileType(for: options.outputPolicy.container),
            optimizationProfile: options.outputPolicy.advancedOptions.optimizationProfile ?? .balanced,
            color: options.outputPolicy.advancedOptions.color ?? videoTrack.color
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

enum SW_AV1HEVCWriterColorProperties {
    static func make(for color: TaptionColorDescription) -> [String: String]? {
        guard let primaries = primariesValue(for: color.primaries),
              let transfer = transferValue(for: color.transfer) else {
            return nil
        }
        let matrix = matrixValue(for: color.matrix)
            ?? inferredMatrixValue(for: color.primaries)
        guard let matrix else { return nil }
        return [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix
        ]
    }

    private static func primariesValue(for primaries: TaptionColorPrimaries) -> String? {
        switch primaries {
        case .bt709:
            return AVVideoColorPrimaries_ITU_R_709_2
        case .bt2020:
            return AVVideoColorPrimaries_ITU_R_2020
        case .p3D65:
            return AVVideoColorPrimaries_P3_D65
        case .smpteC:
            return AVVideoColorPrimaries_SMPTE_C
        case .unknown:
            return nil
        }
    }

    private static func transferValue(for transfer: TaptionColorTransfer) -> String? {
        switch transfer {
        case .bt709:
            return AVVideoTransferFunction_ITU_R_709_2
        case .sRGB:
            return AVVideoTransferFunction_IEC_sRGB
        case .pq:
            return AVVideoTransferFunction_SMPTE_ST_2084_PQ
        case .hlg:
            return AVVideoTransferFunction_ITU_R_2100_HLG
        case .linear:
            return AVVideoTransferFunction_Linear
        case .unknown:
            return nil
        }
    }

    private static func matrixValue(for matrix: TaptionColorMatrix) -> String? {
        switch matrix {
        case .bt709:
            return AVVideoYCbCrMatrix_ITU_R_709_2
        case .bt2020NonConstantLuminance:
            return AVVideoYCbCrMatrix_ITU_R_2020
        case .smpte240M:
            return AVVideoYCbCrMatrix_ITU_R_601_4
        case .identity, .unknown:
            return nil
        }
    }

    private static func inferredMatrixValue(for primaries: TaptionColorPrimaries) -> String? {
        switch primaries {
        case .bt709, .p3D65:
            return AVVideoYCbCrMatrix_ITU_R_709_2
        case .bt2020:
            return AVVideoYCbCrMatrix_ITU_R_2020
        case .smpteC:
            return AVVideoYCbCrMatrix_ITU_R_601_4
        case .unknown:
            return nil
        }
    }
}

struct SW_AV1NativeAudioEncodingConfiguration {
    let sourceTrack: TaptionAudioTrackInfo
    let outputCodec: TaptionAudioCodec
    let sampleRate: Double
    let channelCount: Int
    let targetBitrate: Int

    var writerOutputSettings: [String: Any] {
        switch outputCodec {
        case .pcm:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        case .alac:
            return [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitDepthHintKey: 16
            ]
        default:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: targetBitrate
            ]
        }
    }

    static func make(
        asset: TaptionVideoAsset,
        request: TaptionCodecTranscodeRequest
    ) -> SW_AV1NativeAudioEncodingConfiguration? {
        guard request.options.preserveAudioWhenPossible,
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
            resolvedOptions.sampleRate ?? sourceTrack.sampleRate ?? 48_000,
            sourceCodec: sourceTrack.codec
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
            outputCodec: request.options.outputPolicy.audioCodec,
            sampleRate: sampleRate,
            channelCount: channelCount,
            targetBitrate: targetBitrate
        )
    }

    private static func normalizedSampleRate(
        _ value: Double,
        sourceCodec: TaptionAudioCodec
    ) -> Double {
        guard value.isFinite, value > 0 else {
            return 48_000
        }
        let minimumSampleRate: Double = sourceCodec == .amr ? 48_000 : 8_000
        return min(max(value.rounded(), minimumSampleRate), 96_000)
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

struct SW_AV1SoftwareTranscodeRunStats {
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

enum SW_DolbyVisionHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .dolbyVisionHEVC,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Dolby Vision H.265 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .dolbyVisionHEVC)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Dolby Vision H.265",
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

enum SW_RealVideo1HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .realVideo1,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "RealVideo 1.0 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .realVideo1)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "RealVideo 1.0",
            progress: progress
        )
    }
}

enum SW_RealVideoHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .realVideo,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "RealVideo to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .realVideo)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "RealVideo",
            progress: progress
        )
    }
}

enum SW_RoQVideoHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .roqVideo,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "RoQ Video to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .roqVideo)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "RoQ Video",
            progress: progress
        )
    }
}

enum SW_VC1HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .vc1,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "VC-1 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .vc1)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "VC-1",
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

enum SW_DVCProHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .dvcPro,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "DVCPro to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .dvcPro)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "DVCPro",
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

enum SW_SnowHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .snow,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Snow to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .snow)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Snow",
            progress: progress
        )
    }
}

enum SW_UtVideoHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .utVideo,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Ut Video to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .utVideo)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Ut Video",
            progress: progress
        )
    }
}

enum SW_MagicYUVHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .magicYUV,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "MagicYUV to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .magicYUV)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "MagicYUV",
            progress: progress
        )
    }
}

enum SW_PNGVideoHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .pngVideo,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "PNG Video to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .pngVideo)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "PNG Video",
            progress: progress
        )
    }
}

enum SW_R10KHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .r10k,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "R10K to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .r10k)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "R10K",
            progress: progress
        )
    }
}

enum SW_R210HEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .r210,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "R210 to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .r210)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "R210",
            progress: progress
        )
    }
}

enum SW_Y41PHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .y41p,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Y41P to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .y41p)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Y41P",
            progress: progress
        )
    }
}

enum SW_MicrosoftRLEHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .microsoftRLE,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Microsoft RLE to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .microsoftRLE)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Microsoft RLE",
            progress: progress
        )
    }
}

enum SW_QuickTimeGraphicsHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .quickTimeGraphics,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "QuickTime Graphics to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .quickTimeGraphics)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "QuickTime Graphics",
            progress: progress
        )
    }
}

enum SW_RawVideoHEVCTranscoder: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .rawVideo,
        outputCodec: .hevc,
        mode: .software,
        backend: .softwareVLCDecoder,
        displayName: "Raw Video to H.265 Software"
    )

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try SW_AV1HEVCTranscoder.validate(request: request, sourceCodec: .rawVideo)
        return try await SW_AV1HEVCTranscoder.transcodeToHEVC(
            request: request,
            sourceCodecLabel: "Raw Video",
            progress: progress
        )
    }
}

extension SW_AV1HEVCTranscoder {
    static let bundledDecodeBridgePreferredSourceCodecs: Set<TaptionVideoCodec> = [
        .dv,
        .dvcPro,
        .losslessJPEG,
        .mpeg4Visual,
        .microsoftMPEG4V3,
        .microsoftRLE,
        .quickTimeGraphics,
        .r10k,
        .r210,
        .realVideo1,
        .realVideo,
        .snow,
        .utVideo,
        .wmv
    ]

    static func requestedDecoderPlaybackRate(
        optimizationProfile: TaptionEncodingOptimizationProfile,
        hasAudioOutput: Bool
    ) -> Float {
        hasAudioOutput ? 1 : optimizationProfile.softwareVideoOnlyDecoderPlaybackRate
    }

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
        if bundledDecodeBridgePreferredSourceCodecs.contains(request.route.sourceCodec) {
            AppLogger.info(
                "Using bundled decode bridge for validated legacy input",
                category: .encoding,
                metadata: [
                    "source": request.sourceURL.lastPathComponent,
                    "codec": request.route.sourceCodec.rawValue
                ]
            )
            return try await SW_FFmpegDecodeBridgeFallbackTranscoder.transcode(
                request: request,
                progress: progress
            )
        }

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
                try await Task.sleep(nanoseconds: 500_000_000)
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
                targetBitrate: configuration.targetBitrate,
                frameDuration: configuration.frameDuration,
                optimizationProfile: configuration.optimizationProfile,
                color: configuration.color
            )
        )
        videoInput.expectsMediaDataInRealTime = false
        if configuration.optimizationProfile == .performance {
            videoInput.performsMultiPassEncodingIfSupported = false
        }

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
            audioInput.expectsMediaDataInRealTime = true

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
                configuration: audioConfiguration,
                maximumPendingSampleBufferCount: configuration.optimizationProfile
                    .softwareAudioPipelineDepth,
                backpressureSleepMicroseconds: configuration.optimizationProfile
                    .writerBackpressureSleepMicroseconds
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
            allowsLegacyFrameHoldToPreserveDuration: configuration.allowsLegacyFrameHoldToPreserveDuration,
            progressFrameStride: configuration.optimizationProfile == .performance
                ? max(
                    1,
                    Int((0.5 / max(configuration.frameDuration.seconds, 0.001)).rounded())
                )
                : 1,
            maximumPendingFrameCount: configuration.optimizationProfile.softwareFramePipelineDepth,
            backpressureSleepMicroseconds: configuration.optimizationProfile.writerBackpressureSleepMicroseconds,
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
            libvlc_video_set_format_callbacks(player, nil, nil)
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

        let profilePlaybackRate = configuration.optimizationProfile.softwareVideoOnlyDecoderPlaybackRate
        let requestedPlaybackRate = requestedDecoderPlaybackRate(
            optimizationProfile: configuration.optimizationProfile,
            hasAudioOutput: audioContext != nil
        )
        let playbackRateStatus = requestedPlaybackRate > 1
            ? libvlc_media_player_set_rate(player, requestedPlaybackRate)
            : 0
        let reportedPlaybackRate = libvlc_media_player_get_rate(player)
        AppLogger.info(
            "Software \(sourceCodecLabel) decoder playback rate configured",
            category: .encoding,
            metadata: [
                "profileRate": String(format: "%.2f", profilePlaybackRate),
                "requestedRate": String(format: "%.2f", requestedPlaybackRate),
                "reportedRate": String(format: "%.2f", reportedPlaybackRate),
                "accepted": "\(playbackRateStatus == 0)",
                "limitedByAudioPreservation": "\(audioContext != nil && profilePlaybackRate > 1)"
            ]
        )

        let startUptime = ProcessInfo.processInfo.systemUptime
        var stopRequested = false
        var sawAnyFrame = false
        var lastObservedFrameCount = 0
        var lastFrameProgressUptime = startUptime
        var expectedFrameReachedUptime: TimeInterval?

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

            let audioDidDrainNow = audioContext?.didDrain ?? true
            let audioDidWriteSamplesNow = audioContext?.didWriteAnySamples ?? true
            if configuration.limitsToExpectedFrameCount,
               context.didReachExpectedFrameCount {
                let now = ProcessInfo.processInfo.systemUptime
                if expectedFrameReachedUptime == nil {
                    expectedFrameReachedUptime = now
                }
                let waitedForAudio = now - (expectedFrameReachedUptime ?? now)
                let audioReadyForStop = audioContext == nil
                    || audioDidWriteSamplesNow
                    || audioDidDrainNow
                    || waitedForAudio > max(2.0, configuration.frameDuration.seconds * 12)
                if audioReadyForStop,
                   !stopRequested {
                    stopRequested = true
                    _ = libvlc_media_player_stop_async(player)
                }
            }

            let state = libvlc_media_player_get_state(player)
            if sawAnyFrame {
                let audioDidDrain = audioDidDrainNow
                let audioDidWriteSamples = audioDidWriteSamplesNow
                let playbackPosition = libvlc_media_player_get_position(player)
                let playbackTimeMilliseconds = libvlc_media_player_get_time(player)
                let playbackTimeSeconds = playbackTimeMilliseconds > 0
                    ? Double(playbackTimeMilliseconds) / 1000.0
                    : 0
                let idleDuration = ProcessInfo.processInfo.systemUptime - lastFrameProgressUptime
                let settleDuration = max(1.0, configuration.frameDuration.seconds * 12)
                let stallDuration = max(8.0, configuration.frameDuration.seconds * 180)
                let audioNoSampleWaitExceeded = audioContext != nil
                    && !audioDidWriteSamples
                    && idleDuration > max(2.0, settleDuration)
                let audioReadyToFinish = audioDidDrain || (audioDidWriteSamples && idleDuration > settleDuration)
                if (state == libvlc_Stopped || state == libvlc_Stopping),
                   (audioReadyToFinish || audioNoSampleWaitExceeded),
                   idleDuration > max(0.5, configuration.frameDuration.seconds * 6) {
                    break
                }
                if stopRequested,
                   (audioReadyToFinish || audioNoSampleWaitExceeded),
                   idleDuration > settleDuration {
                    break
                }
                if configuration.limitsToExpectedFrameCount {
                    let isNearPlaybackEnd = playbackPosition >= 0.995
                        || playbackTimeSeconds >= max(configuration.duration.seconds - 0.25, 0)
                    if isNearPlaybackEnd,
                       (audioReadyToFinish || audioNoSampleWaitExceeded),
                       idleDuration > max(0.5, configuration.frameDuration.seconds * 6) {
                        break
                    }
                }
                if idleDuration > stallDuration {
                    if !stopRequested {
                        AppLogger.warning(
                            "Software \(sourceCodecLabel) decoder stopped producing frames; finalizing partial decoded stream",
                            category: .encoding,
                            metadata: [
                                "source": sourceURL.lastPathComponent,
                                "frames": "\(frameCount)",
                                "idleSeconds": String(format: "%.2f", idleDuration)
                            ]
                        )
                        stopRequested = true
                        _ = libvlc_media_player_stop_async(player)
                    } else {
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

            try await Task.sleep(
                nanoseconds: configuration.optimizationProfile
                    .softwareDecodePollingIntervalNanoseconds
            )
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
        targetBitrate: Int,
        frameDuration: CMTime,
        optimizationProfile: TaptionEncodingOptimizationProfile,
        color: TaptionColorDescription
    ) -> [String: Any] {
        let width = Int(max(targetSize.width.rounded(), 2))
        let height = Int(max(targetSize.height.rounded(), 2))
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: targetBitrate
        ]
        if optimizationProfile == .performance {
            let fps = frameDuration.seconds > 0 ? Int((1.0 / frameDuration.seconds).rounded()) : 30
            compressionProperties[AVVideoExpectedSourceFrameRateKey] = min(max(fps, 1), 240)
            compressionProperties[AVVideoAllowFrameReorderingKey] = false
            compressionProperties[AVVideoMaxKeyFrameIntervalKey] = min(max(fps, 1), 240)
        }
        TaptionHEVCWriterPerformanceHints.apply(
            to: &compressionProperties,
            optimizationProfile: optimizationProfile
        )
        var outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
        if let colorProperties = SW_AV1HEVCWriterColorProperties.make(for: color) {
            outputSettings[AVVideoColorPropertiesKey] = colorProperties
        }
        return outputSettings
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
        switch sourceURL.pathExtension.lowercased() {
        case "h261":
            libvlc_media_add_option(media, ":demux=avformat")
            libvlc_media_add_option(media, ":avformat-format=h261")
        case "vc1":
            libvlc_media_add_option(media, ":demux=avformat")
            libvlc_media_add_option(media, ":avformat-format=vc1")
        default:
            break
        }
        libvlc_media_add_option(media, ":no-sub-autodetect-file")
        libvlc_media_add_option(media, ":no-snapshot-preview")
        libvlc_media_add_option(media, ":avcodec-hw=none")
        libvlc_media_add_option(media, ":no-drop-late-frames")
        libvlc_media_add_option(media, ":no-skip-frames")
        return media
    }

    private static func waitForVLCQuiescence(_ player: OpaquePointer) {
        let deadline = ProcessInfo.processInfo.systemUptime + 2.5
        while ProcessInfo.processInfo.systemUptime < deadline {
            let state = libvlc_media_player_get_state(player)
            if state == libvlc_Stopped || state == libvlc_Error {
                return
            }
            usleep(20_000)
        }
    }
}
