import Foundation

struct TaptionAudioCodecRoute: Codable, Hashable {
    var sourceCodec: TaptionAudioCodec
    var outputCodec: TaptionAudioCodec

    init(sourceCodec: TaptionAudioCodec, outputCodec: TaptionAudioCodec) {
        self.sourceCodec = sourceCodec
        self.outputCodec = outputCodec
    }

    var displayName: String {
        "\(sourceCodec.displayName) to \(outputCodec.displayName)"
    }
}

enum TaptionAudioCodecRouteSupport: String, Codable, Equatable {
    case copy
    case nativeTranscode
    case softwareTranscode
    case planned
    case unsupported
}

struct TaptionAudioCodecRouteSelection: Codable, Equatable {
    var route: TaptionAudioCodecRoute
    var support: TaptionAudioCodecRouteSupport
    var decodeBackend: TaptionEncodingBackend?
    var encodeBackend: TaptionEncodingBackend?
    var shouldCopy: Bool
    var fixtureStatus: TaptionAudioFixtureStatus
    var reason: String

    var isSupportedNow: Bool {
        support == .copy || support == .nativeTranscode || support == .softwareTranscode
    }

    var shortDisplayName: String {
        switch support {
        case .copy:
            return "Copy"
        case .nativeTranscode:
            return "HW"
        case .softwareTranscode:
            return "SW"
        case .planned:
            return "Planned"
        case .unsupported:
            return "Unsupported"
        }
    }
}

enum TaptionAudioCodecRoutePlanner {
    static let defaultOutputCodec: TaptionAudioCodec = .aac

    static let universalAudioCodecs: [TaptionAudioCodec] = [
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

    static var plannedUniversalRoutes: Set<TaptionAudioCodecRoute> {
        Set(universalAudioCodecs.flatMap { sourceCodec in
            universalAudioCodecs.map { outputCodec in
                TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
            }
        })
    }

    static func selectRoute(
        sourceCodec: TaptionAudioCodec,
        outputCodec: TaptionAudioCodec = defaultOutputCodec,
        outputContainer: TaptionVideoContainer = .mp4,
        preserveWhenPossible: Bool = true
    ) -> TaptionAudioCodecRouteSelection {
        let route = TaptionAudioCodecRoute(
            sourceCodec: sourceCodec,
            outputCodec: outputCodec
        )
        let fixtureStatus = SW_AudioCodecSupportCatalog.fixtureStatus(for: sourceCodec)

        guard plannedUniversalRoutes.contains(route) else {
            return TaptionAudioCodecRouteSelection(
                route: route,
                support: .unsupported,
                decodeBackend: nil,
                encodeBackend: nil,
                shouldCopy: false,
                fixtureStatus: fixtureStatus,
                reason: "This audio codec route is not in the current roadmap."
            )
        }

        if preserveWhenPossible,
           sourceCodec == outputCodec,
           HW_AudioCodecCapabilityCatalog.canCopyWithoutTranscode(
                codec: sourceCodec,
                into: outputContainer
           ) {
            return TaptionAudioCodecRouteSelection(
                route: route,
                support: .copy,
                decodeBackend: nil,
                encodeBackend: nil,
                shouldCopy: true,
                fixtureStatus: fixtureStatus,
                reason: "The source audio can be copied into the selected output container."
            )
        }

        if HW_AudioCodecCapabilityCatalog.canNativeDecode(sourceCodec),
           HW_AudioCodecCapabilityCatalog.canNativeEncode(outputCodec) {
            return TaptionAudioCodecRouteSelection(
                route: route,
                support: .nativeTranscode,
                decodeBackend: .appleAVAssetExport,
                encodeBackend: .appleAVAssetExport,
                shouldCopy: false,
                fixtureStatus: fixtureStatus,
                reason: "Apple native audio decode and encode should handle this route."
            )
        }

        if SW_AudioCodecSupportCatalog.canSoftwareDecode(sourceCodec),
           HW_AudioCodecCapabilityCatalog.canNativeEncode(outputCodec) {
            return TaptionAudioCodecRouteSelection(
                route: route,
                support: .softwareTranscode,
                decodeBackend: .ffmpegFamily,
                encodeBackend: .appleAVAssetExport,
                shouldCopy: false,
                fixtureStatus: fixtureStatus,
                reason: "Software audio decode should feed an Apple-native output encoder."
            )
        }

        return TaptionAudioCodecRouteSelection(
            route: route,
            support: .planned,
            decodeBackend: SW_AudioCodecSupportCatalog.canSoftwareDecode(sourceCodec) ? .ffmpegFamily : nil,
            encodeBackend: HW_AudioCodecCapabilityCatalog.canNativeEncode(outputCodec) ? .appleAVAssetExport : .ffmpegFamily,
            shouldCopy: false,
            fixtureStatus: fixtureStatus,
            reason: "This audio route is represented but still needs an implementation decision."
        )
    }
}
