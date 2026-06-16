import Foundation

struct SW_FFmpegCommandPlan: Codable, Equatable {
    var executableName: String
    var backend: TaptionEncodingBackend
    var sourceURL: URL
    var outputURL: URL
    var routeSummary: String
    var arguments: [String]
    var notes: [String]

    init(
        executableName: String = "ffmpeg",
        backend: TaptionEncodingBackend = .ffmpegFamily,
        sourceURL: URL,
        outputURL: URL,
        routeSummary: String,
        arguments: [String],
        notes: [String] = []
    ) {
        self.executableName = executableName
        self.backend = backend
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.routeSummary = routeSummary
        self.arguments = arguments
        self.notes = notes
    }
}

enum SW_FFmpegCodecCommandPlannerError: LocalizedError, Equatable {
    case videoRouteNotPlannable(TaptionCodecRoute)
    case audioRouteNotPlannable(TaptionAudioCodecRoute)
    case videoRequestRouteMismatch(expected: TaptionCodecRoute, actual: TaptionCodecRoute)
    case videoEncoderUnavailable(TaptionVideoCodec)
    case audioEncoderUnavailable(TaptionAudioCodec)
    case inputContainerUnavailable(TaptionVideoContainer)
    case outputContainerUnavailable(TaptionVideoContainer)
    case missingPlanSourceURL
    case missingPlanOutputURL
    case missingPlanVideoRoute

    var errorDescription: String? {
        switch self {
        case .videoRouteNotPlannable(let route):
            return "\(route.displayName) cannot be represented by the FFmpeg-family software command planner."
        case .audioRouteNotPlannable(let route):
            return "\(route.displayName) cannot be represented by the FFmpeg-family audio command planner."
        case .videoRequestRouteMismatch(let expected, let actual):
            return "Video codec command route mismatch. Expected \(expected.displayName), got \(actual.displayName)."
        case .videoEncoderUnavailable(let codec):
            return "\(codec.displayName) has no selected FFmpeg-family software encoder in this build plan."
        case .audioEncoderUnavailable(let codec):
            return "\(codec.displayName) has no selected FFmpeg-family software audio encoder in this build plan."
        case .inputContainerUnavailable(let container):
            if container == .unknown {
                return "Input container is unknown and cannot be read by the FFmpeg-family software command planner."
            }
            return "\(container.defaultFileExtension.uppercased()) input is not readable by the FFmpeg-family software command planner."
        case .outputContainerUnavailable(let container):
            return "\(container.defaultFileExtension.uppercased()) output is not writable by the FFmpeg-family software command planner."
        case .missingPlanSourceURL:
            return "The encoding plan does not include a source URL for the FFmpeg-family software command planner."
        case .missingPlanOutputURL:
            return "The encoding plan does not include a temporary output URL for the FFmpeg-family software command planner."
        case .missingPlanVideoRoute:
            return "The encoding plan does not include a video codec route for the FFmpeg-family software command planner."
        }
    }
}

enum SW_FFmpegCodecCommandPlanner {
    static var plannableVideoOutputCodecs: [TaptionVideoCodec] {
        videoEncoderNames.keys.sorted { $0.rawValue < $1.rawValue }
    }

    static var commandUnsupportedVideoOutputCodecs: [TaptionVideoCodec] {
        TaptionCodecRegistry.universalOutputCodecs
            .filter { videoEncoderName(for: $0) == nil }
            .sorted { $0.rawValue < $1.rawValue }
    }

    static var plannableAudioOutputCodecs: [TaptionAudioCodec] {
        audioEncoderNames.keys.sorted { $0.rawValue < $1.rawValue }
    }

    static var commandUnsupportedAudioOutputCodecs: [TaptionAudioCodec] {
        TaptionAudioCodecRoutePlanner.universalAudioCodecs
            .filter { audioEncoderName(for: $0) == nil }
            .sorted { $0.rawValue < $1.rawValue }
    }

    static func makeSingleAssetCommandPlan(
        plan: TaptionEncodingPlan
    ) throws -> SW_FFmpegCommandPlan {
        if let videoCommandPlan = plan.videoCommandPlan {
            return videoCommandPlan
        }
        guard let sourceURL = plan.sourceURL else {
            throw SW_FFmpegCodecCommandPlannerError.missingPlanSourceURL
        }
        guard let outputURL = plan.temporaryOutputURL else {
            throw SW_FFmpegCodecCommandPlannerError.missingPlanOutputURL
        }
        guard let route = plan.codecRoute else {
            throw SW_FFmpegCodecCommandPlannerError.missingPlanVideoRoute
        }

        return try makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: sourceURL,
                outputURL: outputURL,
                route: route,
                options: TaptionCodecTranscodeOptions(
                    outputPolicy: plan.outputPolicy,
                    preserveSourceVisualQuality: true,
                    preserveAudioWhenPossible: plan.audioPlan != nil
                )
            ),
            audioPlan: plan.audioPlan
        )
    }

    static func makeVideoCommandPlan(
        request: TaptionCodecTranscodeRequest,
        audioPlan: TaptionAudioTranscodePlan?
    ) throws -> SW_FFmpegCommandPlan {
        try makeVideoCommandPlan(
            request: request,
            audioRouteSelection: audioPlan?.routeSelection,
            audioOptions: audioPlan?.options
        )
    }

    static func makeVideoCommandPlan(
        request: TaptionCodecTranscodeRequest,
        audioRouteSelection: TaptionAudioCodecRouteSelection? = nil,
        audioOptions: TaptionAudioCodecTranscodeOptions? = nil
    ) throws -> SW_FFmpegCommandPlan {
        try validateVideoRequest(request)
        try validateSourceContainer(for: request.sourceURL)
        guard SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.canWriteContainer(
            request.options.outputPolicy.container
        ) else {
            throw SW_FFmpegCodecCommandPlannerError.outputContainerUnavailable(
                request.options.outputPolicy.container
            )
        }
        guard let videoEncoder = videoEncoderName(for: request.route.outputCodec) else {
            throw SW_FFmpegCodecCommandPlannerError.videoEncoderUnavailable(request.route.outputCodec)
        }

        var arguments = [
            "-hide_banner",
            "-y",
            "-i", request.sourceURL.path,
            "-map", "0:v:0"
        ]

        if request.options.preserveAudioWhenPossible {
            arguments += ["-map", "0:a?"]
        } else {
            arguments += ["-an"]
        }

        arguments += videoFilterArguments(for: request.options.outputPolicy.advancedOptions)
        arguments += ["-c:v", videoEncoder]
        arguments += videoQualityArguments(
            for: request.route.outputCodec,
            options: request.options.outputPolicy.advancedOptions
        )
        arguments += videoPixelFormatArguments(
            for: request.route.outputCodec,
            options: request.options.outputPolicy.advancedOptions
        )
        arguments += videoColorArguments(
            for: request.options.outputPolicy.advancedOptions.color
        )

        if request.options.preserveAudioWhenPossible {
            arguments += try audioArguments(
                for: audioRouteSelection,
                options: audioOptions
            )
        }

        arguments += containerArguments(for: request.options.outputPolicy.container)
        arguments += videoRotationMetadataArguments(
            for: request.options.outputPolicy.advancedOptions.rotationDegrees
        )
        arguments.append(request.outputURL.path)

        return SW_FFmpegCommandPlan(
            sourceURL: request.sourceURL,
            outputURL: request.outputURL,
            routeSummary: request.route.displayName,
            arguments: arguments,
            notes: [
                "Preserve source visual quality unless explicit advanced options override it.",
                "Run this plan only after the FFmpeg-family backend is bundled and license-reviewed."
            ]
        )
    }

    static func makeAudioCommandPlan(
        request: TaptionAudioCodecTranscodeRequest
    ) throws -> SW_FFmpegCommandPlan {
        try SW_UniversalAudioCodecTranscodeAlgorithm.validate(request: request)
        try validateSourceContainer(for: request.sourceURL)
        guard SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.canWriteContainer(
            request.options.outputContainer
        ) else {
            throw SW_FFmpegCodecCommandPlannerError.outputContainerUnavailable(
                request.options.outputContainer
            )
        }

        let canCopy = request.route.sourceCodec == request.route.outputCodec
            && HW_AudioCodecCapabilityCatalog.canCopyWithoutTranscode(
                codec: request.route.sourceCodec,
                into: request.options.outputContainer
            )
        let encoderName: String
        if canCopy {
            encoderName = "copy"
        } else {
            guard let plannedEncoderName = audioEncoderName(for: request.route.outputCodec) else {
                throw SW_FFmpegCodecCommandPlannerError.audioEncoderUnavailable(request.route.outputCodec)
            }
            encoderName = plannedEncoderName
        }

        var arguments = [
            "-hide_banner",
            "-y",
            "-i", request.sourceURL.path,
            "-vn",
            "-map", "0:a:0?",
            "-c:a", encoderName
        ]
        if encoderName != "copy" {
            arguments += audioTranscodeArguments(for: request.options)
        }
        arguments += containerArguments(for: request.options.outputContainer)
        arguments.append(request.outputURL.path)

        return SW_FFmpegCommandPlan(
            sourceURL: request.sourceURL,
            outputURL: request.outputURL,
            routeSummary: request.route.displayName,
            arguments: arguments,
            notes: [
                canCopy ? "Audio can be copied without transcoding." : "Audio will be transcoded by the FFmpeg-family backend.",
                "Run this plan only after the FFmpeg-family backend is bundled and license-reviewed."
            ]
        )
    }

    static func videoEncoderName(for codec: TaptionVideoCodec) -> String? {
        videoEncoderNames[codec]
    }

    static func audioEncoderName(for codec: TaptionAudioCodec) -> String? {
        audioEncoderNames[codec]
    }

    private static func validateVideoRequest(
        _ request: TaptionCodecTranscodeRequest
    ) throws {
        let actualRoute = TaptionCodecRoute(
            sourceCodec: request.route.sourceCodec,
            outputCodec: request.options.outputPolicy.videoCodec
        )
        guard actualRoute == request.route else {
            throw SW_FFmpegCodecCommandPlannerError.videoRequestRouteMismatch(
                expected: request.route,
                actual: actualRoute
            )
        }
        guard SW_UniversalCodecTranscodeAlgorithm.canRepresent(request.route) else {
            throw SW_FFmpegCodecCommandPlannerError.videoRouteNotPlannable(request.route)
        }
    }

    private static func validateSourceContainer(for sourceURL: URL) throws {
        let inputContainer = TaptionVideoContainer.inferred(from: sourceURL)
        guard SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.canReadContainer(inputContainer) else {
            throw SW_FFmpegCodecCommandPlannerError.inputContainerUnavailable(inputContainer)
        }
    }

    private static func audioArguments(
        for selection: TaptionAudioCodecRouteSelection?,
        options: TaptionAudioCodecTranscodeOptions? = nil
    ) throws -> [String] {
        guard let selection else {
            return ["-c:a", "copy"]
        }
        if selection.shouldCopy {
            return ["-c:a", "copy"]
        }
        guard let encoderName = audioEncoderName(for: selection.route.outputCodec) else {
            throw SW_FFmpegCodecCommandPlannerError.audioEncoderUnavailable(selection.route.outputCodec)
        }
        var arguments = ["-c:a", encoderName]
        if let options {
            arguments += audioTranscodeArguments(for: options)
        }
        return arguments
    }

    private static func videoFilterArguments(
        for options: TaptionAdvancedOutputOptions
    ) -> [String] {
        guard let resizeTo = options.resizeTo,
              resizeTo.isValid else {
            return []
        }
        return ["-vf", "scale=\(resizeTo.width):\(resizeTo.height)"]
    }

    private static func videoQualityArguments(
        for codec: TaptionVideoCodec,
        options: TaptionAdvancedOutputOptions
    ) -> [String] {
        var arguments: [String] = []
        if let frameRate = options.frameRate {
            arguments += ["-r", frameRateArgument(frameRate)]
        }
        if let targetBitrate = options.targetBitrate {
            arguments += ["-b:v", "\(targetBitrate)"]
            return arguments
        }

        switch codec {
        case .hevc, .h264:
            arguments += ["-crf", "18", "-preset", "medium"]
        case .av1:
            arguments += ["-crf", "24", "-preset", "6"]
        case .vp9, .vp8:
            arguments += ["-crf", "30", "-b:v", "0"]
        case .proRes:
            arguments += ["-profile:v", "3"]
        case .ffv1:
            arguments += ["-level", "3"]
        case .dnxhd:
            arguments += ["-profile:v", "dnxhr_lb"]
        case .huffYUV, .utVideo, .magicYUV, .cineForm, .pngVideo, .r10k, .v210, .r210, .v410, .y41p, .microsoftRLE, .quickTimeGraphics, .v308, .v408, .yuv4, .microsoftVideo1, .quickTimeVideo, .jpeg2000, .jpegLS, .losslessJPEG, .zmbv, .cljr, .rawVideo:
            break
        default:
            arguments += ["-q:v", "2"]
        }
        return arguments
    }

    private static func videoPixelFormatArguments(
        for codec: TaptionVideoCodec,
        options: TaptionAdvancedOutputOptions
    ) -> [String] {
        switch codec {
        case .ffv1, .utVideo, .magicYUV:
            return ["-pix_fmt", "yuv420p"]
        case .huffYUV, .dnxhd:
            return ["-pix_fmt", "yuv422p"]
        case .cineForm, .proRes:
            return ["-pix_fmt", "yuv422p10le"]
        case .pngVideo:
            return ["-pix_fmt", "rgb24"]
        case .r10k:
            return ["-pix_fmt", "gbrp10le"]
        case .v210:
            return ["-pix_fmt", "yuv422p10le"]
        case .r210:
            return ["-pix_fmt", "gbrp10le"]
        case .v410:
            return ["-pix_fmt", "yuv444p10le"]
        case .y41p, .cljr:
            return ["-pix_fmt", "yuv411p"]
        case .microsoftRLE, .quickTimeGraphics:
            return ["-pix_fmt", "rgb24"]
        case .microsoftVideo1:
            return ["-pix_fmt", "rgb555le"]
        case .quickTimeVideo:
            return ["-pix_fmt", "rgb555be"]
        case .sorensonVideo:
            return ["-pix_fmt", "yuv410p"]
        case .flashScreenVideo, .flashScreenVideo2, .zmbv, .jpeg2000, .jpegLS:
            return ["-pix_fmt", "rgb24"]
        case .losslessJPEG:
            return ["-pix_fmt", "yuvj420p"]
        case .v308:
            return ["-pix_fmt", "yuv444p"]
        case .v408:
            return ["-pix_fmt", "yuva444p"]
        case .yuv4:
            return ["-pix_fmt", "yuv420p"]
        default:
            break
        }

        guard let bitDepth = options.color?.bitDepth,
              bitDepth >= 10 else {
            return []
        }

        switch codec {
        case .hevc, .h264, .av1, .vp9:
            return ["-pix_fmt", "yuv420p10le"]
        default:
            return []
        }
    }

    private static func videoColorArguments(
        for color: TaptionColorDescription?
    ) -> [String] {
        guard let color else {
            return []
        }

        var arguments: [String] = []
        if let primaries = ffmpegColorPrimaries(color.primaries) {
            arguments += ["-color_primaries", primaries]
        }
        if let transfer = ffmpegColorTransfer(color.transfer) {
            arguments += ["-color_trc", transfer]
        }
        if let matrix = ffmpegColorMatrix(color.matrix) {
            arguments += ["-colorspace", matrix]
        }
        return arguments
    }

    private static func videoRotationMetadataArguments(
        for rotationDegrees: Int?
    ) -> [String] {
        guard let rotationDegrees else {
            return []
        }
        let normalizedRotation = ((rotationDegrees % 360) + 360) % 360
        guard normalizedRotation != 0 else {
            return []
        }
        return ["-metadata:s:v:0", "rotate=\(normalizedRotation)"]
    }

    private static func audioTranscodeArguments(
        for options: TaptionAudioCodecTranscodeOptions
    ) -> [String] {
        var arguments: [String] = []
        if let sampleRate = options.sampleRate,
           options.preserveSampleRate,
           sampleRate.isFinite,
           sampleRate > 0 {
            arguments += ["-ar", audioSampleRateArgument(sampleRate)]
        }
        if let channelCount = options.channelCount,
           options.preserveChannelLayout,
           channelCount > 0 {
            arguments += ["-ac", "\(channelCount)"]
        }
        if let targetBitrate = options.targetBitrate {
            arguments += ["-b:a", "\(targetBitrate)"]
        }
        return arguments
    }

    private static func containerArguments(
        for container: TaptionVideoContainer
    ) -> [String] {
        switch container {
        case .mp4, .mov, .m4v:
            return ["-map_metadata", "0", "-movflags", "+faststart"]
        default:
            return ["-map_metadata", "0"]
        }
    }

    private static func frameRateArgument(
        _ frameRate: TaptionRationalFrameRate
    ) -> String {
        if frameRate.denominator == 1 {
            return "\(frameRate.numerator)"
        }
        return "\(frameRate.numerator)/\(frameRate.denominator)"
    }

    private static func audioSampleRateArgument(_ sampleRate: Double) -> String {
        if sampleRate.rounded() == sampleRate {
            return "\(Int(sampleRate))"
        }
        return String(format: "%.3f", sampleRate)
    }

    private static func ffmpegColorPrimaries(
        _ primaries: TaptionColorPrimaries
    ) -> String? {
        switch primaries {
        case .bt709:
            return "bt709"
        case .bt2020:
            return "bt2020"
        case .p3D65:
            return "smpte432"
        case .smpteC:
            return "smpte170m"
        case .unknown:
            return nil
        }
    }

    private static func ffmpegColorTransfer(
        _ transfer: TaptionColorTransfer
    ) -> String? {
        switch transfer {
        case .bt709:
            return "bt709"
        case .sRGB:
            return "iec61966-2-1"
        case .pq:
            return "smpte2084"
        case .hlg:
            return "arib-std-b67"
        case .linear:
            return "linear"
        case .unknown:
            return nil
        }
    }

    private static func ffmpegColorMatrix(
        _ matrix: TaptionColorMatrix
    ) -> String? {
        switch matrix {
        case .bt709:
            return "bt709"
        case .bt2020NonConstantLuminance:
            return "bt2020nc"
        case .smpte240M:
            return "smpte240m"
        case .identity:
            return "gbr"
        case .unknown:
            return nil
        }
    }

    private static let videoEncoderNames: [TaptionVideoCodec: String] = [
        .av1: "libsvtav1",
        .hevc: "libx265",
        .h264: "libx264",
        .vp9: "libvpx-vp9",
        .vp8: "libvpx",
        .proRes: "prores_ks",
        .mpeg2: "mpeg2video",
        .mpeg1: "mpeg1video",
        .mpeg4Visual: "mpeg4",
        .h263: "h263",
        .h261: "h261",
        .flashVideo: "flv",
        .microsoftMPEG4V2: "msmpeg4v2",
        .microsoftMPEG4V3: "msmpeg4",
        .motionJPEG: "mjpeg",
        .jpeg: "mjpeg",
        .jpeg2000: "jpeg2000",
        .jpegLS: "jpegls",
        .losslessJPEG: "ljpeg",
        .animation: "qtrle",
        .cinepak: "cinepak",
        .sorensonVideo: "svq1",
        .quickTimeVideo: "rpza",
        .realVideo1: "rv10",
        .realVideo: "rv20",
        .roqVideo: "roqvideo",
        .dv: "dvvideo",
        .dvcPro: "dvvideo",
        .dvcProHD: "dvvideo",
        .wmv: "wmv2",
        .microsoftVideo1: "msvideo1",
        .asusV1: "asv1",
        .asusV2: "asv2",
        .flashScreenVideo: "flashsv",
        .flashScreenVideo2: "flashsv2",
        .zmbv: "zmbv",
        .cljr: "cljr",
        .snow: "snow",
        .ffv1: "ffv1",
        .huffYUV: "huffyuv",
        .utVideo: "utvideo",
        .magicYUV: "magicyuv",
        .cineForm: "cfhd",
        .dnxhd: "dnxhd",
        .pngVideo: "png",
        .r10k: "r10k",
        .v210: "v210",
        .r210: "r210",
        .v410: "v410",
        .y41p: "y41p",
        .microsoftRLE: "msrle",
        .quickTimeGraphics: "smc",
        .v308: "v308",
        .v408: "v408",
        .yuv4: "yuv4",
        .rawVideo: "rawvideo"
    ]

    private static let audioEncoderNames: [TaptionAudioCodec: String] = [
        .aac: "aac",
        .pcm: "pcm_s16le",
        .alac: "alac",
        .opus: "libopus",
        .mp3: "libmp3lame",
        .mp2: "mp2",
        .ac3: "ac3",
        .eac3: "eac3",
        .dts: "dca",
        .trueHD: "truehd",
        .flac: "flac",
        .vorbis: "vorbis",
        .ilbc: "ilbc_at",
        .g722: "g722",
        .g723: "g723_1",
        .g726: "g726",
        .mlp: "mlp",
        .tta: "tta",
        .realAudio: "real_144",
        .wavPack: "wavpack",
        .wma: "wmav2",
        .adpcm: "adpcm_ima_wav",
        .aLaw: "pcm_alaw",
        .muLaw: "pcm_mulaw"
    ]
}
