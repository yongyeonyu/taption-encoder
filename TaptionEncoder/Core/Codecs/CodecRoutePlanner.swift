import Foundation

enum TaptionCodecRouteExecutionKind: String, Codable, Equatable {
    case hardware
    case software
    case mixed
    case planned
    case unsupported

    var shortDisplayName: String {
        switch self {
        case .hardware:
            return "HW"
        case .software:
            return "SW"
        case .mixed:
            return "HW/SW"
        case .planned:
            return "Planned"
        case .unsupported:
            return "Unsupported"
        }
    }
}

struct TaptionCodecRouteSelection: Codable, Equatable {
    var route: TaptionCodecRoute
    var requestedMode: TaptionEncoderMode
    var selectedMode: TaptionEncoderMode
    var decodeBackend: TaptionEncodingBackend?
    var encodeBackend: TaptionEncodingBackend?
    var executionKind: TaptionCodecRouteExecutionKind
    var support: TaptionCodecRouteSupport
    var reason: String

    var isEncodableNow: Bool {
        support == .implemented && executionKind != .unsupported
    }

    var displayTitle: String {
        "Path \(executionKind.shortDisplayName)"
    }

    var displayDetail: String {
        "\(route.displayName). \(reason)"
    }

    var encoderSelection: TaptionEncoderSelection {
        TaptionEncoderSelection(
            requestedMode: requestedMode,
            backend: encodeBackend ?? decodeBackend,
            reason: reason
        )
    }
}

struct TaptionCodecHardwareSupportProfile: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var hardwareDecodeCodecs: Set<TaptionVideoCodec>
    var hardwareEncodeCodecs: Set<TaptionVideoCodec>

    init(
        name: String,
        hardwareDecodeCodecs: Set<TaptionVideoCodec>,
        hardwareEncodeCodecs: Set<TaptionVideoCodec>
    ) {
        self.name = name
        self.hardwareDecodeCodecs = hardwareDecodeCodecs
        self.hardwareEncodeCodecs = hardwareEncodeCodecs
    }

    func canHardwareDecode(_ codec: TaptionVideoCodec) -> Bool {
        hardwareDecodeCodecs.contains(codec)
    }

    func canHardwareEncode(_ codec: TaptionVideoCodec) -> Bool {
        hardwareEncodeCodecs.contains(codec)
    }

    static func currentDevice(
        probeSize: TaptionPixelSize = HW_CodecCapabilityProbe.defaultProbeSize
    ) -> TaptionCodecHardwareSupportProfile {
        var decodeCodecs = Set<TaptionVideoCodec>()
        var encodeCodecs = Set<TaptionVideoCodec>()

        for codec in HW_CodecCapabilityProbe.probedVideoCodecs {
            if HW_CodecCapabilityProbe.hardwareDecodeSupported(for: codec) == true {
                decodeCodecs.insert(codec)
            }
            if HW_CodecCapabilityProbe.capability(for: codec, probeSize: probeSize).hardwareEncodeSupported == true {
                encodeCodecs.insert(codec)
            }
        }

        return TaptionCodecHardwareSupportProfile(
            name: "Current Device",
            hardwareDecodeCodecs: decodeCodecs,
            hardwareEncodeCodecs: encodeCodecs
        )
    }
}

extension TaptionCodecHardwareSupportProfile {
    static let softwareOnly = TaptionCodecHardwareSupportProfile(
        name: "software_only",
        hardwareDecodeCodecs: [],
        hardwareEncodeCodecs: []
    )

    static let h264OnlyHardware = TaptionCodecHardwareSupportProfile(
        name: "h264_only_hw",
        hardwareDecodeCodecs: [.h264],
        hardwareEncodeCodecs: [.h264]
    )

    static let h264HEVCHardware = TaptionCodecHardwareSupportProfile(
        name: "h264_hevc_hw",
        hardwareDecodeCodecs: [.h264, .hevc],
        hardwareEncodeCodecs: [.h264, .hevc]
    )

    static let proMediaHardware = TaptionCodecHardwareSupportProfile(
        name: "h264_hevc_prores_hw",
        hardwareDecodeCodecs: [.h264, .hevc, .hevcWithAlpha, .dolbyVisionHEVC, .proRes],
        hardwareEncodeCodecs: [.h264, .hevc, .hevcWithAlpha, .proRes]
    )

    static let av1DecodeHEVCEncodeHardware = TaptionCodecHardwareSupportProfile(
        name: "av1_decode_hevc_encode_hw",
        hardwareDecodeCodecs: [.h264, .hevc, .hevcWithAlpha, .dolbyVisionHEVC, .av1, .vp9, .proRes],
        hardwareEncodeCodecs: [.h264, .hevc, .hevcWithAlpha, .proRes]
    )

    static let simulationProfiles: [TaptionCodecHardwareSupportProfile] = [
        .softwareOnly,
        .h264OnlyHardware,
        .h264HEVCHardware,
        .proMediaHardware,
        .av1DecodeHEVCEncodeHardware
    ] + HW_AppleDeviceCodecProfiles.routeSimulationProfiles
        + HW_AppleDeviceCodecModelMatrix.routeSimulationProfiles
}

enum TaptionCodecRoutePlanner {
    static func selectRoute(
        for asset: TaptionVideoAsset,
        outputCodec: TaptionVideoCodec = .hevc,
        requestedMode: TaptionEncoderMode = .automatic,
        hardwareSupport: TaptionCodecHardwareSupportProfile? = nil
    ) -> TaptionCodecRouteSelection {
        let hardwareSupport = hardwareSupport ?? .currentDevice()
        guard let videoTrack = asset.videoTrack else {
            return unsupportedSelection(
                route: TaptionCodecRoute(sourceCodec: .unknown, outputCodec: outputCodec),
                requestedMode: requestedMode,
                reason: "No readable video track was found."
            )
        }

        let route = TaptionCodecRoute(
            sourceCodec: videoTrack.codec,
            outputCodec: outputCodec
        )
        let support = TaptionCodecRegistry.support(for: route)

        switch support {
        case .implemented:
            return implementedSelection(
                route: route,
                requestedMode: requestedMode,
                hardwareSupport: hardwareSupport
            )
        case .planned:
            return TaptionCodecRouteSelection(
                route: route,
                requestedMode: requestedMode,
                selectedMode: .automatic,
                decodeBackend: plannedDecodeBackend(for: route.sourceCodec, hardwareSupport: hardwareSupport),
                encodeBackend: plannedEncodeBackend(for: route.outputCodec, hardwareSupport: hardwareSupport),
                executionKind: .planned,
                support: support,
                reason: "This route is planned for the universal codec update."
            )
        case .unsupported:
            return unsupportedSelection(
                route: route,
                requestedMode: requestedMode,
                reason: "This codec route is not in the current support roadmap."
            )
        }
    }

    private static func implementedSelection(
        route: TaptionCodecRoute,
        requestedMode: TaptionEncoderMode,
        hardwareSupport: TaptionCodecHardwareSupportProfile
    ) -> TaptionCodecRouteSelection {
        let hardwareDecode = hardwareSupport.canHardwareDecode(route.sourceCodec)
        let hardwareEncode = hardwareSupport.canHardwareEncode(route.outputCodec)

        switch requestedMode {
        case .hardware where hardwareDecode && hardwareEncode:
            return hardwareSelection(route: route, requestedMode: requestedMode)
        case .hardware:
            return mixedOrSoftwareSelection(
                route: route,
                requestedMode: requestedMode,
                hardwareEncode: hardwareEncode
            )
        case .software:
            return softwareSelection(
                route: route,
                requestedMode: requestedMode,
                reason: "Software path was requested and will preserve source visual quality where possible."
            )
        case .automatic:
            if hardwareDecode && hardwareEncode {
                return hardwareSelection(route: route, requestedMode: requestedMode)
            }
            return mixedOrSoftwareSelection(
                route: route,
                requestedMode: requestedMode,
                hardwareEncode: hardwareEncode
            )
        }
    }

    private static func hardwareSelection(
        route: TaptionCodecRoute,
        requestedMode: TaptionEncoderMode
    ) -> TaptionCodecRouteSelection {
        TaptionCodecRouteSelection(
            route: route,
            requestedMode: requestedMode,
            selectedMode: .hardware,
            decodeBackend: .appleAVAssetExport,
            encodeBackend: .appleVideoToolbox,
            executionKind: .hardware,
            support: .implemented,
            reason: "Hardware decode and hardware encode are available."
        )
    }

    private static func mixedOrSoftwareSelection(
        route: TaptionCodecRoute,
        requestedMode: TaptionEncoderMode,
        hardwareEncode: Bool
    ) -> TaptionCodecRouteSelection {
        if hardwareEncode {
            return TaptionCodecRouteSelection(
                route: route,
                requestedMode: requestedMode,
                selectedMode: .software,
                decodeBackend: softwareDecodeBackend(for: route.sourceCodec),
                encodeBackend: .appleVideoToolbox,
                executionKind: .mixed,
                support: .implemented,
                reason: "Hardware source decode is unavailable, so software decode will feed the hardware encoder."
            )
        }

        return softwareSelection(
            route: route,
            requestedMode: requestedMode,
            reason: "Hardware codec support is unavailable, so the software fallback will be used."
        )
    }

    private static func softwareSelection(
        route: TaptionCodecRoute,
        requestedMode: TaptionEncoderMode,
        reason: String
    ) -> TaptionCodecRouteSelection {
        TaptionCodecRouteSelection(
            route: route,
            requestedMode: requestedMode,
            selectedMode: .software,
            decodeBackend: softwareDecodeBackend(for: route.sourceCodec),
            encodeBackend: .customSoftware,
            executionKind: .software,
            support: .implemented,
            reason: reason
        )
    }

    private static func unsupportedSelection(
        route: TaptionCodecRoute,
        requestedMode: TaptionEncoderMode,
        reason: String
    ) -> TaptionCodecRouteSelection {
        TaptionCodecRouteSelection(
            route: route,
            requestedMode: requestedMode,
            selectedMode: .automatic,
            decodeBackend: nil,
            encodeBackend: nil,
            executionKind: .unsupported,
            support: .unsupported,
            reason: reason
        )
    }

    private static func plannedDecodeBackend(
        for codec: TaptionVideoCodec,
        hardwareSupport: TaptionCodecHardwareSupportProfile
    ) -> TaptionEncodingBackend? {
        if hardwareSupport.canHardwareDecode(codec) {
            return .appleAVAssetExport
        }
        if SW_CodecSupportCatalog.softwareFallbackPreferred(for: codec) {
            return softwareDecodeBackend(for: codec)
        }
        return nil
    }

    private static func plannedEncodeBackend(
        for codec: TaptionVideoCodec,
        hardwareSupport: TaptionCodecHardwareSupportProfile
    ) -> TaptionEncodingBackend? {
        if hardwareSupport.canHardwareEncode(codec) {
            return .appleVideoToolbox
        }
        return SW_SoftwareCodecBackendRegistry.preferredVideoEncodeBackend(for: codec)
    }

    private static func softwareDecodeBackend(for codec: TaptionVideoCodec) -> TaptionEncodingBackend {
        SW_SoftwareCodecBackendRegistry.preferredVideoDecodeBackend(for: codec) ?? .customSoftware
    }
}
