import Foundation

enum TaptionVideoCoreVersion {
    static let current = 1
}

enum TaptionVideoCodec: String, Codable, Equatable, CaseIterable {
    case av1
    case hevc
    case hevcWithAlpha
    case dolbyVisionHEVC
    case h264
    case proRes
    case proResRaw
    case vp9
    case vp8
    case mpeg2
    case mpeg1
    case mpeg4Visual
    case h263
    case motionJPEG
    case jpeg
    case jpegXL
    case animation
    case cinepak
    case sorensonVideo
    case sorensonVideo3
    case theora
    case dv
    case dvcPro
    case dvcProHD
    case vc1
    case wmv
    case rawVideo
    case unknown

    var displayName: String {
        switch self {
        case .av1:
            return "AV1"
        case .hevc:
            return "H.265 / HEVC"
        case .hevcWithAlpha:
            return "H.265 / HEVC with Alpha"
        case .dolbyVisionHEVC:
            return "Dolby Vision HEVC"
        case .h264:
            return "H.264 / AVC"
        case .proRes:
            return "Apple ProRes"
        case .proResRaw:
            return "Apple ProRes RAW"
        case .vp9:
            return "VP9"
        case .vp8:
            return "VP8"
        case .mpeg2:
            return "MPEG-2"
        case .mpeg1:
            return "MPEG-1"
        case .mpeg4Visual:
            return "MPEG-4 Visual"
        case .h263:
            return "H.263"
        case .motionJPEG:
            return "Motion JPEG"
        case .jpeg:
            return "JPEG"
        case .jpegXL:
            return "JPEG XL"
        case .animation:
            return "Apple Animation"
        case .cinepak:
            return "Cinepak"
        case .sorensonVideo:
            return "Sorenson Video"
        case .sorensonVideo3:
            return "Sorenson Video 3"
        case .theora:
            return "Theora"
        case .dv:
            return "DV"
        case .dvcPro:
            return "DVCPro"
        case .dvcProHD:
            return "DVCPro HD"
        case .vc1:
            return "VC-1"
        case .wmv:
            return "Windows Media Video"
        case .rawVideo:
            return "Raw Video"
        case .unknown:
            return "Unknown"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .hevc:
            return "H.265"
        case .hevcWithAlpha:
            return "H.265 Alpha"
        case .dolbyVisionHEVC:
            return "Dolby HEVC"
        case .h264:
            return "H.264"
        case .mpeg4Visual:
            return "MPEG-4"
        case .motionJPEG:
            return "MJPEG"
        case .sorensonVideo:
            return "Sorenson"
        case .sorensonVideo3:
            return "Sorenson 3"
        case .rawVideo:
            return "Raw"
        case .unknown:
            return "Unknown"
        default:
            return displayName
        }
    }
}

enum TaptionAudioCodec: String, Codable, Equatable, CaseIterable {
    case aac
    case xheAAC
    case pcm
    case alac
    case opus
    case mp3
    case mp2
    case ac3
    case eac3
    case dts
    case trueHD
    case flac
    case vorbis
    case amr
    case ilbc
    case wavPack
    case wma
    case adpcm
    case aLaw
    case muLaw
    case unknown

    var displayName: String {
        switch self {
        case .aac:
            return "AAC"
        case .xheAAC:
            return "xHE-AAC"
        case .pcm:
            return "PCM"
        case .alac:
            return "Apple Lossless"
        case .opus:
            return "Opus"
        case .mp3:
            return "MP3"
        case .mp2:
            return "MP2"
        case .ac3:
            return "Dolby Digital"
        case .eac3:
            return "Dolby Digital Plus"
        case .dts:
            return "DTS"
        case .trueHD:
            return "Dolby TrueHD"
        case .flac:
            return "FLAC"
        case .vorbis:
            return "Vorbis"
        case .amr:
            return "AMR"
        case .ilbc:
            return "iLBC"
        case .wavPack:
            return "WavPack"
        case .wma:
            return "Windows Media Audio"
        case .adpcm:
            return "ADPCM"
        case .aLaw:
            return "A-law PCM"
        case .muLaw:
            return "mu-law PCM"
        case .unknown:
            return "Unknown"
        }
    }
}

enum TaptionVideoContainer: String, Codable, Equatable, CaseIterable {
    case mp4
    case mov
    case m4v
    case mkv
    case avi
    case webm
    case mxf
    case mpegTransportStream
    case mpegProgramStream
    case lrf
    case dv
    case ogg
    case flv
    case threeGP
    case threeGPP2
    case asf
    case wmv
    case rawElementaryStream
    case unknown

    var defaultFileExtension: String {
        switch self {
        case .mp4:
            return "mp4"
        case .mov:
            return "mov"
        case .m4v:
            return "m4v"
        case .mkv:
            return "mkv"
        case .avi:
            return "avi"
        case .webm:
            return "webm"
        case .mxf:
            return "mxf"
        case .mpegTransportStream:
            return "ts"
        case .mpegProgramStream:
            return "mpg"
        case .lrf:
            return "lrf"
        case .dv:
            return "dv"
        case .ogg:
            return "ogv"
        case .flv:
            return "flv"
        case .threeGP:
            return "3gp"
        case .threeGPP2:
            return "3g2"
        case .asf:
            return "asf"
        case .wmv:
            return "wmv"
        case .rawElementaryStream:
            return "h265"
        case .unknown:
            return "mp4"
        }
    }

    var supportedFileExtensions: [String] {
        switch self {
        case .mp4:
            return ["mp4"]
        case .mov:
            return ["mov", "qt"]
        case .m4v:
            return ["m4v"]
        case .mkv:
            return ["mkv"]
        case .avi:
            return ["avi", "divx"]
        case .webm:
            return ["webm"]
        case .mxf:
            return ["mxf"]
        case .mpegTransportStream:
            return ["ts", "mts", "m2ts", "m2t", "tp", "trp", "tod"]
        case .mpegProgramStream:
            return ["mpg", "mpeg", "mpe", "vob", "mod", "dat"]
        case .lrf:
            return ["lrf"]
        case .dv:
            return ["dv", "dif"]
        case .ogg:
            return ["ogg", "ogv", "ogm"]
        case .flv:
            return ["flv", "f4v"]
        case .threeGP:
            return ["3gp", "3gpp"]
        case .threeGPP2:
            return ["3g2", "3gpp2"]
        case .asf:
            return ["asf", "dvr-ms"]
        case .wmv:
            return ["wmv"]
        case .rawElementaryStream:
            return ["h264", "h265", "hevc", "264", "265", "ivf", "obu", "y4m", "av1", "h263", "m1v", "m2v", "vc1"]
        case .unknown:
            return []
        }
    }

    static func inferred(from url: URL) -> TaptionVideoContainer {
        inferred(fromFileExtension: url.pathExtension)
    }

    static func inferred(fromFileExtension fileExtension: String) -> TaptionVideoContainer {
        let normalizedExtension = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !normalizedExtension.isEmpty else {
            return .unknown
        }
        return allCases.first {
            $0.supportedFileExtensions.contains(normalizedExtension)
        } ?? .unknown
    }
}

enum TaptionEncoderMode: String, Codable, Equatable, CaseIterable {
    case automatic
    case hardware
    case software
}

enum TaptionEncodingBackend: String, Codable, Equatable, CaseIterable {
    case appleVideoToolbox
    case appleAVAssetExport
    case softwareAV1Decoder
    case ffmpegFamily
    case customSoftware
    case simulatedHardware
}

enum TaptionHEVCProfile: String, Codable, Equatable, CaseIterable {
    case main
    case main10
    case mainStillPicture
    case automatic
}

enum TaptionColorPrimaries: String, Codable, Equatable, CaseIterable {
    case bt709
    case bt2020
    case p3D65
    case smpteC
    case unknown
}

enum TaptionColorTransfer: String, Codable, Equatable, CaseIterable {
    case bt709
    case sRGB
    case pq
    case hlg
    case linear
    case unknown
}

enum TaptionColorMatrix: String, Codable, Equatable, CaseIterable {
    case bt709
    case bt2020NonConstantLuminance
    case smpte240M
    case identity
    case unknown
}

enum TaptionQualityPolicy: String, Codable, Equatable, CaseIterable {
    case preserveSourceVisuals
    case highQualityBalanced
    case custom
}

struct TaptionPixelSize: Codable, Equatable {
    var width: Int
    var height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    var isValid: Bool {
        width > 0 && height > 0
    }
}

struct TaptionRationalFrameRate: Codable, Equatable {
    var numerator: Int
    var denominator: Int

    init(numerator: Int, denominator: Int = 1) {
        self.numerator = numerator
        self.denominator = denominator == 0 ? 1 : denominator
    }

    var value: Double {
        Double(numerator) / Double(denominator)
    }
}

struct TaptionColorDescription: Codable, Equatable {
    var primaries: TaptionColorPrimaries
    var transfer: TaptionColorTransfer
    var matrix: TaptionColorMatrix
    var bitDepth: Int?
    var isHDR: Bool

    init(
        primaries: TaptionColorPrimaries = .unknown,
        transfer: TaptionColorTransfer = .unknown,
        matrix: TaptionColorMatrix = .unknown,
        bitDepth: Int? = nil,
        isHDR: Bool = false
    ) {
        self.primaries = primaries
        self.transfer = transfer
        self.matrix = matrix
        self.bitDepth = bitDepth
        self.isHDR = isHDR
    }
}

struct TaptionVideoTrackInfo: Codable, Equatable {
    var codec: TaptionVideoCodec
    var naturalSize: TaptionPixelSize
    var displaySize: TaptionPixelSize
    var nominalFrameRate: TaptionRationalFrameRate?
    var estimatedBitrate: Int?
    var color: TaptionColorDescription
    var rotationDegrees: Int

    init(
        codec: TaptionVideoCodec,
        naturalSize: TaptionPixelSize,
        displaySize: TaptionPixelSize,
        nominalFrameRate: TaptionRationalFrameRate? = nil,
        estimatedBitrate: Int? = nil,
        color: TaptionColorDescription = TaptionColorDescription(),
        rotationDegrees: Int = 0
    ) {
        self.codec = codec
        self.naturalSize = naturalSize
        self.displaySize = displaySize
        self.nominalFrameRate = nominalFrameRate
        self.estimatedBitrate = estimatedBitrate
        self.color = color
        self.rotationDegrees = rotationDegrees
    }
}

struct TaptionAudioTrackInfo: Codable, Equatable {
    var codec: TaptionAudioCodec
    var channelCount: Int?
    var sampleRate: Double?
    var estimatedBitrate: Int?

    init(
        codec: TaptionAudioCodec,
        channelCount: Int? = nil,
        sampleRate: Double? = nil,
        estimatedBitrate: Int? = nil
    ) {
        self.codec = codec
        self.channelCount = channelCount
        self.sampleRate = sampleRate
        self.estimatedBitrate = estimatedBitrate
    }
}

struct TaptionMediaFingerprint: Codable, Equatable {
    var fileSize: Int64?
    var creationDate: Date?
    var modificationDate: Date?
    var contentIdentifier: String?

    init(
        fileSize: Int64? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        contentIdentifier: String? = nil
    ) {
        self.fileSize = fileSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.contentIdentifier = contentIdentifier
    }
}

enum TaptionVideoAssetLocationKind: String, Codable, Equatable {
    case file
    case photos
    case temporary
    case unknown
}

struct TaptionVideoAssetLocation: Codable, Equatable {
    var kind: TaptionVideoAssetLocationKind
    var url: URL?
    var photosLocalIdentifier: String?
    var securityScopedBookmark: Data?

    init(
        kind: TaptionVideoAssetLocationKind,
        url: URL? = nil,
        photosLocalIdentifier: String? = nil,
        securityScopedBookmark: Data? = nil
    ) {
        self.kind = kind
        self.url = url
        self.photosLocalIdentifier = photosLocalIdentifier
        self.securityScopedBookmark = securityScopedBookmark
    }
}

struct TaptionVideoAsset: Identifiable, Codable, Equatable {
    var id: UUID
    var displayName: String
    var location: TaptionVideoAssetLocation
    var container: TaptionVideoContainer
    var duration: TimeInterval?
    var videoTrack: TaptionVideoTrackInfo?
    var audioTracks: [TaptionAudioTrackInfo]
    var fingerprint: TaptionMediaFingerprint

    init(
        id: UUID = UUID(),
        displayName: String,
        location: TaptionVideoAssetLocation,
        container: TaptionVideoContainer = .unknown,
        duration: TimeInterval? = nil,
        videoTrack: TaptionVideoTrackInfo? = nil,
        audioTracks: [TaptionAudioTrackInfo] = [],
        fingerprint: TaptionMediaFingerprint = TaptionMediaFingerprint()
    ) {
        self.id = id
        self.displayName = displayName
        self.location = location
        self.container = container
        self.duration = duration
        self.videoTrack = videoTrack
        self.audioTracks = audioTracks
        self.fingerprint = fingerprint
    }
}
