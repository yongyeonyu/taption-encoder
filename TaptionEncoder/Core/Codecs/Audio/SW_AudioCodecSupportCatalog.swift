import Foundation

enum SW_AudioCodecSupportCatalog {
    static let softwareDecodeCodecs: Set<TaptionAudioCodec> = [
        .aac,
        .xheAAC,
        .pcm,
        .alac,
        .opus,
        .mp3,
        .mp2,
        .ac3,
        .eac3,
        .dts,
        .trueHD,
        .flac,
        .vorbis,
        .amr,
        .ilbc,
        .g722,
        .g723,
        .g726,
        .mlp,
        .tta,
        .nellymoser,
        .realAudio,
        .roqDPCM,
        .wavPack,
        .wma,
        .adpcm,
        .aLaw,
        .muLaw
    ]

    static let currentBuildVLCAACDecodeCodecs: Set<TaptionAudioCodec> = [
        .aac,
        .opus,
        .mp3,
        .vorbis
    ]

    static let fixtureCoveredCodecs: Set<TaptionAudioCodec> = [
        .aac,
        .pcm,
        .alac,
        .opus,
        .mp3,
        .mp2,
        .ac3,
        .eac3,
        .dts,
        .trueHD,
        .flac,
        .vorbis,
        .ilbc,
        .g722,
        .g723,
        .g726,
        .mlp,
        .tta,
        .nellymoser,
        .realAudio,
        .roqDPCM,
        .wavPack,
        .wma,
        .adpcm,
        .aLaw,
        .muLaw
    ]

    static let fixturePendingCodecs: Set<TaptionAudioCodec> = [
        .xheAAC,
        .amr
    ]

    static func canSoftwareDecode(_ codec: TaptionAudioCodec) -> Bool {
        softwareDecodeCodecs.contains(codec)
    }

    static func currentBuildBundledDecodeBackend(
        for sourceCodec: TaptionAudioCodec,
        outputCodec: TaptionAudioCodec,
        outputContainer: TaptionVideoContainer
    ) -> TaptionEncodingBackend? {
        guard outputCodec == .aac,
              outputContainer == .mp4,
              currentBuildVLCAACDecodeCodecs.contains(sourceCodec) else {
            return nil
        }
        return .softwareVLCDecoder
    }

    static func fixtureStatus(for codec: TaptionAudioCodec) -> TaptionAudioFixtureStatus {
        if fixtureCoveredCodecs.contains(codec) {
            return .generated
        }
        if fixturePendingCodecs.contains(codec) {
            return .pendingRealOrAlternateGenerator
        }
        return .notPlanned
    }
}

enum TaptionAudioFixtureStatus: String, Codable, Equatable {
    case generated
    case pendingRealOrAlternateGenerator
    case notPlanned
}
