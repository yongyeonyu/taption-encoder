import Foundation

enum TaptionVideoCoreVersion {
    static let current = 1
}

enum TaptionVideoCodec: String, Codable, Equatable, CaseIterable {
    case av1
    case hevc
    case h264
    case proRes
    case vp9
    case vp8
    case mpeg2
    case mpeg4Visual
    case theora
    case dv
    case unknown

    var displayName: String {
        switch self {
        case .av1:
            return "AV1"
        case .hevc:
            return "H.265 / HEVC"
        case .h264:
            return "H.264 / AVC"
        case .proRes:
            return "Apple ProRes"
        case .vp9:
            return "VP9"
        case .vp8:
            return "VP8"
        case .mpeg2:
            return "MPEG-2"
        case .mpeg4Visual:
            return "MPEG-4 Visual"
        case .theora:
            return "Theora"
        case .dv:
            return "DV"
        case .unknown:
            return "Unknown"
        }
    }
}

enum TaptionAudioCodec: String, Codable, Equatable, CaseIterable {
    case aac
    case pcm
    case alac
    case opus
    case mp3
    case ac3
    case eac3
    case flac
    case vorbis
    case unknown
}

enum TaptionVideoContainer: String, Codable, Equatable, CaseIterable {
    case mp4
    case mov
    case mkv
    case avi
    case webm
    case mxf
    case mpegTransportStream
    case mpegProgramStream
    case unknown

    var defaultFileExtension: String {
        switch self {
        case .mp4:
            return "mp4"
        case .mov:
            return "mov"
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
        case .unknown:
            return "mp4"
        }
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
