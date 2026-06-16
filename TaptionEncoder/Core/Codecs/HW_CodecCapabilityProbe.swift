import CoreMedia
import Foundation
import VideoToolbox

#if canImport(Darwin)
import Darwin
#endif

#if canImport(UIKit)
import UIKit
#endif

struct TaptionCodecHardwareCapability: Codable, Equatable, Identifiable {
    var id: String { videoCodec.rawValue }
    var videoCodec: TaptionVideoCodec
    var coreMediaCodecType: String?
    var hardwareDecodeSupported: Bool?
    var hardwareEncodeSupported: Bool?
    var encodeProbeStatus: Int32?
    var encoderIdentifier: String?
}

struct TaptionAudioCodecHardwareCapability: Codable, Equatable, Identifiable {
    var id: String { audioCodec.rawValue }
    var audioCodec: TaptionAudioCodec
    var nativeDecodeSupported: Bool
    var nativeEncodeSupported: Bool
    var mp4CopySupported: Bool
    var movCopySupported: Bool
}

struct TaptionDeviceCodecCapabilityReport: Codable, Equatable {
    var modelIdentifier: String
    var systemName: String
    var systemVersion: String
    var probeResolution: TaptionPixelSize
    var generatedAt: Date
    var videoCapabilities: [TaptionCodecHardwareCapability]
    var audioCapabilities: [TaptionAudioCodecHardwareCapability]
}

enum HW_CodecCapabilityProbe {
    static let defaultProbeSize = TaptionPixelSize(width: 1920, height: 1080)

    static let probedVideoCodecs: [TaptionVideoCodec] = [
        .h264,
        .hevc,
        .hevcWithAlpha,
        .dolbyVisionHEVC,
        .av1,
        .proRes,
        .proResRaw,
        .vp9,
        .mpeg4Visual,
        .mpeg2,
        .mpeg1,
        .h263,
        .jpeg,
        .jpegXL,
        .animation,
        .cinepak,
        .sorensonVideo,
        .sorensonVideo3,
        .dv,
        .dvcPro,
        .dvcProHD
    ]

    static var probedAudioCodecs: [TaptionAudioCodec] {
        TaptionAudioCodecRoutePlanner.universalAudioCodecs
    }

    static func makeReport(
        probeSize: TaptionPixelSize = defaultProbeSize,
        generatedAt: Date = Date()
    ) -> TaptionDeviceCodecCapabilityReport {
        TaptionDeviceCodecCapabilityReport(
            modelIdentifier: modelIdentifier,
            systemName: systemName,
            systemVersion: systemVersion,
            probeResolution: probeSize,
            generatedAt: generatedAt,
            videoCapabilities: probedVideoCodecs.map { capability(for: $0, probeSize: probeSize) },
            audioCapabilities: probedAudioCodecs.map(audioCapability(for:))
        )
    }

    static func hardwareDecodeSupported(for codec: TaptionVideoCodec) -> Bool? {
        guard let codecType = coreMediaCodecType(for: codec) else {
            return nil
        }
        return VTIsHardwareDecodeSupported(codecType)
    }

    static func capability(
        for codec: TaptionVideoCodec,
        probeSize: TaptionPixelSize = defaultProbeSize
    ) -> TaptionCodecHardwareCapability {
        guard let codecType = coreMediaCodecType(for: codec) else {
            return TaptionCodecHardwareCapability(
                videoCodec: codec,
                coreMediaCodecType: nil,
                hardwareDecodeSupported: nil,
                hardwareEncodeSupported: nil,
                encodeProbeStatus: nil,
                encoderIdentifier: nil
            )
        }

        let encodeProbe = hardwareEncodeProbe(codecType: codecType, probeSize: probeSize)
        return TaptionCodecHardwareCapability(
            videoCodec: codec,
            coreMediaCodecType: fourCharacterCodeString(codecType),
            hardwareDecodeSupported: VTIsHardwareDecodeSupported(codecType),
            hardwareEncodeSupported: encodeProbe.isSupported,
            encodeProbeStatus: encodeProbe.status,
            encoderIdentifier: encodeProbe.encoderIdentifier
        )
    }

    static func audioCapability(
        for codec: TaptionAudioCodec
    ) -> TaptionAudioCodecHardwareCapability {
        TaptionAudioCodecHardwareCapability(
            audioCodec: codec,
            nativeDecodeSupported: HW_AudioCodecCapabilityCatalog.canNativeDecode(codec),
            nativeEncodeSupported: HW_AudioCodecCapabilityCatalog.canNativeEncode(codec),
            mp4CopySupported: HW_AudioCodecCapabilityCatalog.canCopyWithoutTranscode(
                codec: codec,
                into: .mp4
            ),
            movCopySupported: HW_AudioCodecCapabilityCatalog.canCopyWithoutTranscode(
                codec: codec,
                into: .mov
            )
        )
    }

    private static func hardwareEncodeProbe(
        codecType: CMVideoCodecType,
        probeSize: TaptionPixelSize
    ) -> (isSupported: Bool?, status: Int32?, encoderIdentifier: String?) {
        guard let encoderSpecification = hardwareEncoderSpecification() else {
            return (nil, nil, nil)
        }

        var encoderID: CFString?
        var supportedProperties: CFDictionary?
        let status = VTCopySupportedPropertyDictionaryForEncoder(
            width: Int32(probeSize.width),
            height: Int32(probeSize.height),
            codecType: codecType,
            encoderSpecification: encoderSpecification,
            encoderIDOut: &encoderID,
            supportedPropertiesOut: &supportedProperties
        )
        return (
            status == noErr,
            Int32(status),
            encoderID.map { $0 as String }
        )
    }

    private static func hardwareEncoderSpecification() -> CFDictionary? {
        if #available(iOS 17.4, *) {
            return [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
            ] as CFDictionary
        }
        return nil
    }

    private static func coreMediaCodecType(for codec: TaptionVideoCodec) -> CMVideoCodecType? {
        switch codec {
        case .av1:
            return kCMVideoCodecType_AV1
        case .hevc:
            return kCMVideoCodecType_HEVC
        case .hevcWithAlpha:
            return kCMVideoCodecType_HEVCWithAlpha
        case .dolbyVisionHEVC:
            return kCMVideoCodecType_DolbyVisionHEVC
        case .h264:
            return kCMVideoCodecType_H264
        case .proRes:
            return kCMVideoCodecType_AppleProRes422
        case .proResRaw:
            return kCMVideoCodecType_AppleProResRAW
        case .vp9:
            return kCMVideoCodecType_VP9
        case .mpeg2:
            return kCMVideoCodecType_MPEG2Video
        case .mpeg1:
            return kCMVideoCodecType_MPEG1Video
        case .mpeg4Visual:
            return kCMVideoCodecType_MPEG4Video
        case .h263:
            return kCMVideoCodecType_H263
        case .jpeg, .motionJPEG:
            return kCMVideoCodecType_JPEG
        case .jpegXL:
            return kCMVideoCodecType_JPEG_XL
        case .animation:
            return kCMVideoCodecType_Animation
        case .cinepak:
            return kCMVideoCodecType_Cinepak
        case .sorensonVideo:
            return kCMVideoCodecType_SorensonVideo
        case .sorensonVideo3:
            return kCMVideoCodecType_SorensonVideo3
        case .dv:
            return kCMVideoCodecType_DVCNTSC
        case .dvcPro:
            return kCMVideoCodecType_DVCPro50NTSC
        case .dvcProHD:
            return kCMVideoCodecType_DVCPROHD720p60
        case .vp8, .theora, .realVideo, .roqVideo, .vc1, .wmv, .ffv1, .huffYUV, .utVideo, .magicYUV, .cineForm, .dnxhd, .pngVideo, .r10k, .v210, .rawVideo, .unknown:
            return nil
        }
    }

    private static func fourCharacterCodeString(_ code: FourCharCode) -> String {
        String(bytes: [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)) ?? "\(code)"
    }

    private static var modelIdentifier: String {
        #if canImport(Darwin)
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else {
                return
            }
            identifier.append(String(UnicodeScalar(UInt8(value))))
        }
        #else
        return "unknown"
        #endif
    }

    private static var systemName: String {
        #if canImport(UIKit)
        return UIDevice.current.systemName
        #else
        return "Unknown OS"
        #endif
    }

    private static var systemVersion: String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        return "unknown"
        #endif
    }
}
