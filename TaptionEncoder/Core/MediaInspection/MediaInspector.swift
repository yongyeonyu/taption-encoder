import AudioToolbox
import AVFoundation
import CoreMedia
import Foundation
import SwiftVLC

protocol MediaInspecting: TaptionVideoInspecting {}

struct FakeMediaInspector: MediaInspecting {
    func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
        TaptionVideoAsset(
            displayName: url.lastPathComponent,
            location: TaptionVideoAssetLocation(kind: .file, url: url),
            container: .unknown,
            duration: nil,
            videoTrack: TaptionVideoTrackInfo(
                codec: .av1,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30),
                estimatedBitrate: nil,
                color: TaptionColorDescription(),
                rotationDegrees: 0
            ),
            audioTracks: []
        )
    }
}

struct AVFoundationMediaInspector: MediaInspecting {
    func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
        do {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let videoTrack: TaptionVideoTrackInfo?
            if let firstVideoTrack = videoTracks.first {
                videoTrack = try await inspectVideoTrack(firstVideoTrack)
            } else {
                videoTrack = nil
            }
            let audioTrackInfo = try await audioTracks.asyncMap { try await inspectAudioTrack($0) }

            return TaptionVideoAsset(
                displayName: url.lastPathComponent,
                location: TaptionVideoAssetLocation(kind: .file, url: url),
                container: container(for: url),
                duration: duration.isFinite ? duration : nil,
                videoTrack: videoTrack,
                audioTracks: audioTrackInfo,
                fingerprint: fingerprint(for: url)
            )
        } catch {
            guard shouldFallbackToSoftwareInspection(for: url, error: error) else {
                throw error
            }
            return try await SW_VLCMediaInspector().inspectVideo(at: url)
        }
    }

    private func inspectVideoTrack(_ track: AVAssetTrack) async throws -> TaptionVideoTrackInfo {
        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let nominalFrameRate = try await track.load(.nominalFrameRate)
        let estimatedDataRate = try await track.load(.estimatedDataRate)
        let formatDescriptions = try await track.load(.formatDescriptions)
        let codec = codec(from: formatDescriptions)
        let displaySize = naturalSize.applying(preferredTransform)
        let normalizedDisplaySize = CGSize(
            width: abs(displaySize.width),
            height: abs(displaySize.height)
        )

        return TaptionVideoTrackInfo(
            codec: codec,
            naturalSize: TaptionPixelSize(
                width: Int(abs(naturalSize.width).rounded()),
                height: Int(abs(naturalSize.height).rounded())
            ),
            displaySize: TaptionPixelSize(
                width: Int(normalizedDisplaySize.width.rounded()),
                height: Int(normalizedDisplaySize.height.rounded())
            ),
            nominalFrameRate: frameRate(from: nominalFrameRate),
            estimatedBitrate: estimatedDataRate > 0 ? Int(estimatedDataRate) : nil,
            color: colorDescription(from: formatDescriptions),
            rotationDegrees: rotationDegrees(from: preferredTransform)
        )
    }

    private func inspectAudioTrack(_ track: AVAssetTrack) async throws -> TaptionAudioTrackInfo {
        let estimatedDataRate = try await track.load(.estimatedDataRate)
        let formatDescriptions = try await track.load(.formatDescriptions)
        let estimatedBitrate = estimatedDataRate > 0 ? Int(estimatedDataRate) : nil
        return TaptionAudioFormatDescriptionParser.trackInfo(
            from: formatDescriptions,
            estimatedBitrate: estimatedBitrate
        )
    }

    private func codec(from descriptions: [CMFormatDescription]) -> TaptionVideoCodec {
        guard let description = descriptions.first else {
            return .unknown
        }
        switch fourCharacterCode(CMFormatDescriptionGetMediaSubType(description)) {
        case "av01", "av1":
            return .av1
        case "hvc1", "hev1":
            return .hevc
        case "muxa":
            return .hevcWithAlpha
        case "dvh1", "dvhe":
            return .dolbyVisionHEVC
        case "avc1", "avc3":
            return .h264
        case "vp09":
            return .vp9
        case "vp08":
            return .vp8
        case "mp4v":
            return .mpeg4Visual
        case "mp2v":
            return .mpeg2
        case "mp1v":
            return .mpeg1
        case "h263":
            return .h263
        case "jpeg", "dmb1":
            return .jpeg
        case "mjpa", "mjpb":
            return .motionJPEG
        case "jxlc":
            return .jpegXL
        case "rle":
            return .animation
        case "cvid":
            return .cinepak
        case "svq1":
            return .sorensonVideo
        case "svq3":
            return .sorensonVideo3
        case "dvc":
            return .dv
        case "dvcp", "dvpp", "dv5n", "dv5p":
            return .dvcPro
        case "dvhp", "dvhq", "dvh6", "dvh5", "dvh3", "dvh2":
            return .dvcProHD
        case "ap4x", "ap4h", "apch", "apcn", "apcs", "apco":
            return .proRes
        case "aprn", "aprh":
            return .proResRaw
        default:
            return .unknown
        }
    }

    private func colorDescription(from descriptions: [CMFormatDescription]) -> TaptionColorDescription {
        guard let description = descriptions.first,
              let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] else {
            return TaptionColorDescription()
        }

        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
        let matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String

        return TaptionColorDescription(
            primaries: mapColorPrimaries(primaries),
            transfer: mapColorTransfer(transfer),
            matrix: mapColorMatrix(matrix),
            bitDepth: nil,
            isHDR: transfer == string(kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ)
                || transfer == string(kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG)
        )
    }

    private func frameRate(from value: Float) -> TaptionRationalFrameRate? {
        guard value.isFinite, value > 0 else {
            return nil
        }
        let scaled = Int((Double(value) * 1000).rounded())
        return TaptionRationalFrameRate(numerator: scaled, denominator: 1000)
    }

    private func rotationDegrees(from transform: CGAffineTransform) -> Int {
        let radians = atan2(transform.b, transform.a)
        let degrees = Int((radians * 180 / .pi).rounded())
        return (degrees + 360) % 360
    }

    private func container(for url: URL) -> TaptionVideoContainer {
        TaptionVideoContainer.inferred(from: url)
    }

    private func fingerprint(for url: URL) -> TaptionMediaFingerprint {
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]) else {
            return TaptionMediaFingerprint()
        }

        return TaptionMediaFingerprint(
            fileSize: values.fileSize.map(Int64.init),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            contentIdentifier: nil
        )
    }

    private func fourCharacterCode(_ code: FourCharCode) -> String {
        String(bytes: [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            .lowercased() ?? ""
    }

    private func mapColorPrimaries(_ value: String?) -> TaptionColorPrimaries {
        switch value {
        case string(kCMFormatDescriptionColorPrimaries_ITU_R_709_2):
            return .bt709
        case string(kCMFormatDescriptionColorPrimaries_ITU_R_2020):
            return .bt2020
        case string(kCMFormatDescriptionColorPrimaries_P3_D65):
            return .p3D65
        case string(kCMFormatDescriptionColorPrimaries_SMPTE_C):
            return .smpteC
        default:
            return .unknown
        }
    }

    private func mapColorTransfer(_ value: String?) -> TaptionColorTransfer {
        switch value {
        case string(kCMFormatDescriptionTransferFunction_ITU_R_709_2):
            return .bt709
        case string(kCMFormatDescriptionTransferFunction_sRGB):
            return .sRGB
        case string(kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ):
            return .pq
        case string(kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG):
            return .hlg
        default:
            return .unknown
        }
    }

    private func mapColorMatrix(_ value: String?) -> TaptionColorMatrix {
        switch value {
        case string(kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2):
            return .bt709
        case string(kCMFormatDescriptionYCbCrMatrix_ITU_R_2020):
            return .bt2020NonConstantLuminance
        case string(kCMFormatDescriptionYCbCrMatrix_SMPTE_240M_1995):
            return .smpte240M
        default:
            return .unknown
        }
    }

    private func string(_ value: CFString) -> String {
        value as String
    }

    private func shouldFallbackToSoftwareInspection(for url: URL, error: Error) -> Bool {
        let container = TaptionVideoContainer.inferred(from: url)
        guard SW_SoftwareCodecBackendRegistry.vlcSoftwareDecoder.readableContainers.contains(container) else {
            return false
        }

        let nsError = error as NSError
        guard nsError.domain == AVFoundationErrorDomain else {
            return false
        }

        return nsError.code == AVError.unknown.rawValue
            || nsError.code == AVError.fileFormatNotRecognized.rawValue
            || nsError.code == -11828
    }
}

private struct SW_VLCMediaInspector: MediaInspecting {
    func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
        let media = try Media(url: url)
        _ = try await media.parse(timeout: .seconds(10))
        let tracks = media.tracks()
        let videoTrack = tracks
            .first(where: { $0.type == .video })
            .map(makeVideoTrackInfo)
        let audioTracks = tracks
            .filter { $0.type == .audio }
            .map(makeAudioTrackInfo)

        return TaptionVideoAsset(
            displayName: url.lastPathComponent,
            location: TaptionVideoAssetLocation(kind: .file, url: url),
            container: TaptionVideoContainer.inferred(from: url),
            duration: media.duration.map { Double($0.milliseconds) / 1000.0 },
            videoTrack: videoTrack,
            audioTracks: audioTracks,
            fingerprint: fingerprint(for: url)
        )
    }

    private func makeVideoTrackInfo(from track: Track) -> TaptionVideoTrackInfo {
        let width = max(track.width ?? 0, 2)
        let height = max(track.height ?? 0, 2)
        return TaptionVideoTrackInfo(
            codec: videoCodec(from: track.codec),
            naturalSize: TaptionPixelSize(width: width, height: height),
            displaySize: TaptionPixelSize(width: width, height: height),
            nominalFrameRate: frameRate(from: track.frameRate),
            estimatedBitrate: track.bitrate > 0 ? track.bitrate : nil,
            color: TaptionColorDescription(),
            rotationDegrees: 0
        )
    }

    private func makeAudioTrackInfo(from track: Track) -> TaptionAudioTrackInfo {
        TaptionAudioTrackInfo(
            codec: audioCodec(from: track.codec),
            channelCount: track.channels,
            sampleRate: track.sampleRate.map(Double.init),
            estimatedBitrate: track.bitrate > 0 ? track.bitrate : nil
        )
    }

    private func videoCodec(from codec: Int) -> TaptionVideoCodec {
        switch normalizedFourCC(codec) {
        case "av01", "av1":
            return .av1
        case "vp80", "vp8":
            return .vp8
        case "vp90", "vp9":
            return .vp9
        case "h264", "avc1", "avc3":
            return .h264
        case "hevc", "hvc1", "hev1":
            return .hevc
        case "dvh1", "dvhe":
            return .dolbyVisionHEVC
        case "mp4v":
            return .mpeg4Visual
        case "mp2v", "mpeg":
            return .mpeg2
        case "mp1v":
            return .mpeg1
        case "h263":
            return .h263
        case "jpeg":
            return .jpeg
        case "mjpg":
            return .motionJPEG
        case "cvid":
            return .cinepak
        case "svq1":
            return .sorensonVideo
        case "svq3":
            return .sorensonVideo3
        case "dvc":
            return .dv
        case "dvcp", "dvpp", "dv5n", "dv5p":
            return .dvcPro
        case "dvhp", "dvhq", "dvh6", "dvh5", "dvh3", "dvh2":
            return .dvcProHD
        case "ap4x", "ap4h", "apch", "apcn", "apcs", "apco":
            return .proRes
        case "aprn", "aprh":
            return .proResRaw
        default:
            return .unknown
        }
    }

    private func audioCodec(from codec: Int) -> TaptionAudioCodec {
        switch normalizedFourCC(codec) {
        case "aac", "mp4a", "aach", "aacl":
            return .aac
        case "aace":
            return .xheAAC
        case "alac":
            return .alac
        case "opus":
            return .opus
        case "mp3", ".mp3":
            return .mp3
        case "mp2", ".mp2":
            return .mp2
        case "ac-3":
            return .ac3
        case "ec-3", "eac3":
            return .eac3
        case "dtsc", "dtsh", "dtsl", "dtsx":
            return .dts
        case "mlpa":
            return .trueHD
        case "flac":
            return .flac
        case "samr", "sawb":
            return .amr
        case "ilbc":
            return .ilbc
        case "lpcm", "sowt", "twos", "in24", "in32", "fl32", "fl64", "raw":
            return .pcm
        case "alaw":
            return .aLaw
        case "ulaw":
            return .muLaw
        case "vorb", "vrbs":
            return .vorbis
        case "wma1", "wma2", "wmap", "wmav":
            return .wma
        default:
            return .unknown
        }
    }

    private func frameRate(from value: Double?) -> TaptionRationalFrameRate? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        let scaled = Int((value * 1000).rounded())
        return TaptionRationalFrameRate(numerator: scaled, denominator: 1000)
    }

    private func fingerprint(for url: URL) -> TaptionMediaFingerprint {
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]) else {
            return TaptionMediaFingerprint()
        }

        return TaptionMediaFingerprint(
            fileSize: values.fileSize.map(Int64.init),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            contentIdentifier: nil
        )
    }

    private func normalizedFourCC(_ code: Int) -> String {
        let value = UInt32(truncatingIfNeeded: code)
        return String(bytes: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            .lowercased() ?? ""
    }
}

enum TaptionAudioFormatDescriptionParser {
    static func trackInfo(
        from descriptions: [CMFormatDescription],
        estimatedBitrate: Int?
    ) -> TaptionAudioTrackInfo {
        let description = firstAudioDescription(from: descriptions)
        return TaptionAudioTrackInfo(
            codec: codec(from: descriptions),
            channelCount: channelCount(from: description),
            sampleRate: sampleRate(from: description),
            estimatedBitrate: estimatedBitrate
        )
    }

    static func codec(from descriptions: [CMFormatDescription]) -> TaptionAudioCodec {
        guard let description = descriptions.first else {
            return .unknown
        }
        switch fourCharacterCode(CMFormatDescriptionGetMediaSubType(description)) {
        case "aac", "aach", "aacl":
            return .aac
        case "aace":
            return .xheAAC
        case "alac":
            return .alac
        case "opus":
            return .opus
        case ".mp3", "mp3":
            return .mp3
        case ".mp2", "mp2":
            return .mp2
        case "ac-3":
            return .ac3
        case "ec-3":
            return .eac3
        case "dtsc", "dtsh", "dtsl", "dtsx":
            return .dts
        case "mlpa":
            return .trueHD
        case "flac":
            return .flac
        case "samr", "sawb":
            return .amr
        case "ilbc":
            return .ilbc
        case "lpcm", "sowt", "twos", "in24", "in32", "fl32", "fl64", "raw":
            return .pcm
        case "alaw":
            return .aLaw
        case "ulaw":
            return .muLaw
        default:
            return .unknown
        }
    }

    static func channelCount(from description: CMFormatDescription?) -> Int? {
        guard let streamDescription = streamBasicDescription(from: description) else {
            return nil
        }
        let count = Int(streamDescription.mChannelsPerFrame)
        return count > 0 ? count : nil
    }

    static func sampleRate(from description: CMFormatDescription?) -> Double? {
        guard let streamDescription = streamBasicDescription(from: description) else {
            return nil
        }
        let rate = streamDescription.mSampleRate
        return rate.isFinite && rate > 0 ? rate : nil
    }

    private static func firstAudioDescription(from descriptions: [CMFormatDescription]) -> CMFormatDescription? {
        descriptions.first { CMFormatDescriptionGetMediaType($0) == kCMMediaType_Audio }
            ?? descriptions.first
    }

    private static func streamBasicDescription(
        from description: CMFormatDescription?
    ) -> AudioStreamBasicDescription? {
        guard let description,
              CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
              let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
            return nil
        }
        return pointer.pointee
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        String(bytes: [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ], encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            .lowercased() ?? ""
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        values.reserveCapacity(count)
        for element in self {
            let value = try await transform(element)
            values.append(value)
        }
        return values
    }
}
