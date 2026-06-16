import Foundation

enum HW_AudioCodecCapabilityCatalog {
    static let nativeDecodeCodecs: Set<TaptionAudioCodec> = [
        .aac,
        .xheAAC,
        .pcm,
        .aLaw,
        .muLaw,
        .alac,
        .mp3,
        .ac3,
        .eac3,
        .flac
    ]

    static let nativeEncodeCodecs: Set<TaptionAudioCodec> = [
        .aac,
        .pcm,
        .aLaw,
        .muLaw,
        .alac
    ]

    static func canNativeDecode(_ codec: TaptionAudioCodec) -> Bool {
        nativeDecodeCodecs.contains(codec)
    }

    static func canNativeEncode(_ codec: TaptionAudioCodec) -> Bool {
        nativeEncodeCodecs.contains(codec)
    }

    static func canCopyWithoutTranscode(
        codec: TaptionAudioCodec,
        into container: TaptionVideoContainer
    ) -> Bool {
        switch container {
        case .mp4, .m4v:
            return [.aac, .ac3, .eac3, .mp3].contains(codec)
        case .mov:
            return [.aac, .pcm, .aLaw, .muLaw, .alac, .mp3, .ac3, .eac3].contains(codec)
        case .mkv:
            return codec != .unknown
        case .webm:
            return [.opus, .vorbis].contains(codec)
        case .avi:
            return [.pcm, .aLaw, .muLaw, .mp3, .adpcm].contains(codec)
        case .mpegProgramStream, .mpegTransportStream:
            return [.aac, .mp2, .mp3, .ac3, .eac3].contains(codec)
        case .ogg:
            return [.opus, .vorbis, .flac].contains(codec)
        case .asf, .wmv:
            return [.wma, .pcm].contains(codec)
        default:
            return false
        }
    }
}

enum HW_AudioCodecAlgorithmCatalog {
    static func descriptors(
        outputContainer: TaptionVideoContainer = .mkv
    ) -> [TaptionAudioCodecAlgorithmDescriptor] {
        TaptionAudioCodecRoutePlanner.plannedUniversalRoutes
            .compactMap { descriptor(for: $0, outputContainer: outputContainer) }
            .sorted {
                if $0.sourceCodec.rawValue == $1.sourceCodec.rawValue {
                    return $0.outputCodec.rawValue < $1.outputCodec.rawValue
                }
                return $0.sourceCodec.rawValue < $1.sourceCodec.rawValue
            }
    }

    static func descriptor(
        for route: TaptionAudioCodecRoute,
        outputContainer: TaptionVideoContainer = .mkv
    ) -> TaptionAudioCodecAlgorithmDescriptor? {
        let selection = TaptionAudioCodecRoutePlanner.selectRoute(
            sourceCodec: route.sourceCodec,
            outputCodec: route.outputCodec,
            outputContainer: outputContainer
        )
        switch selection.support {
        case .copy:
            return TaptionAudioCodecAlgorithmDescriptor(
                route: route,
                mode: .hardware,
                backend: .appleAVAssetExport,
                displayName: "\(route.sourceCodec.displayName) Copy"
            )
        case .nativeTranscode:
            return TaptionAudioCodecAlgorithmDescriptor(
                route: route,
                mode: .hardware,
                backend: .appleAVAssetExport,
                displayName: "\(route.displayName) Apple Native"
            )
        case .softwareTranscode, .planned, .unsupported:
            return nil
        }
    }
}
