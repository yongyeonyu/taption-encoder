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

            let inspectedAsset = TaptionVideoAsset(
                displayName: url.lastPathComponent,
                location: TaptionVideoAssetLocation(kind: .file, url: url),
                container: container(for: url),
                duration: duration.isFinite ? duration : nil,
                videoTrack: videoTrack,
                audioTracks: audioTrackInfo,
                fingerprint: fingerprint(for: url)
            )
            if shouldFallbackToSoftwareInspection(for: url, inspectedAsset: inspectedAsset) {
                let softwareAsset = try await SW_VLCMediaInspector().inspectVideo(at: url)
                return mergedSoftwareAsset(
                    softwareAsset,
                    fallbackAudioTracks: inspectedAsset.audioTracks,
                    fallbackDuration: inspectedAsset.duration
                )
            }
            return inspectedAsset
        } catch {
            guard shouldFallbackToSoftwareInspection(for: url, error: error) else {
                throw error
            }
            return try await SW_VLCMediaInspector().inspectVideo(at: url)
        }
    }

    private func mergedSoftwareAsset(
        _ softwareAsset: TaptionVideoAsset,
        fallbackAudioTracks: [TaptionAudioTrackInfo],
        fallbackDuration: TimeInterval?
    ) -> TaptionVideoAsset {
        guard softwareAsset.audioTracks.isEmpty || softwareAsset.duration == nil else {
            return softwareAsset
        }

        var mergedAsset = softwareAsset
        if mergedAsset.audioTracks.isEmpty {
            mergedAsset.audioTracks = fallbackAudioTracks
        }
        if mergedAsset.duration == nil {
            mergedAsset.duration = fallbackDuration
        }
        return mergedAsset
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
        case "mp4v", "fmp4":
            return .mpeg4Visual
        case "mp2v":
            return .mpeg2
        case "mp1v":
            return .mpeg1
        case "h263", "s263":
            return .h263
        case "h261":
            return .h261
        case "flv1":
            return .flashVideo
        case "mp42":
            return .microsoftMPEG4V2
        case "mp43", "div3", "div4", "div5", "mpg3":
            return .microsoftMPEG4V3
        case "jpeg", "dmb1", "mjpa", "mjpb", "mjpg":
            return .motionJPEG
        case "mjp2", "avj2":
            return .jpeg2000
        case "mjls":
            return .jpegLS
        case "ljpg":
            return .losslessJPEG
        case "jxlc":
            return .jpegXL
        case "rle":
            return .animation
        case "cvid":
            return .cinepak
        case "rpza":
            return .quickTimeVideo
        case "svq1":
            return .sorensonVideo
        case "svq3":
            return .sorensonVideo3
        case "theo", "thra":
            return .theora
        case "rv10":
            return .realVideo1
        case "rv20", "rv30", "rv40", "rv60":
            return .realVideo
        case "roq":
            return .roqVideo
        case "dvc":
            return .dv
        case "dvcp", "dvpp", "dv5n", "dv5p":
            return .dvcPro
        case "dvhp", "dvhq", "dvh6", "dvh5", "dvh3", "dvh2":
            return .dvcProHD
        case "wvc1", "vc1":
            return .vc1
        case "ap4x", "ap4h", "apch", "apcn", "apcs", "apco":
            return .proRes
        case "aprn", "aprh":
            return .proResRaw
        case "wmv1", "wmv2", "wmv3":
            return .wmv
        case "msvc", "cram":
            return .microsoftVideo1
        case "mrle", "msrl":
            return .microsoftRLE
        case "asv1":
            return .asusV1
        case "asv2":
            return .asusV2
        case "fsv1", "flashsv":
            return .flashScreenVideo
        case "fsv2", "flashsv2":
            return .flashScreenVideo2
        case "zmbv":
            return .zmbv
        case "cljr":
            return .cljr
        case "snow":
            return .snow
        case "ffv1":
            return .ffv1
        case "hfyu", "ffvh":
            return .huffYUV
        case "uly0", "uly2", "uly4", "ulrg", "ulra":
            return .utVideo
        case "magy":
            return .magicYUV
        case "cfhd":
            return .cineForm
        case "avdn", "dnxhd", "dnxhr":
            return .dnxhd
        case "png", "png1", "mpng":
            return .pngVideo
        case "r10k", "r10g":
            return .r10k
        case "v210":
            return .v210
        case "r210":
            return .r210
        case "y41p":
            return .y41p
        case "raw ", "raw", "rawv", "iyuv", "i420", "yuy2":
            return .rawVideo
        case "v410":
            return .v410
        case "v308":
            return .v308
        case "v408":
            return .v408
        case "yuv4":
            return .yuv4
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
            || nsError.code == -11829
    }

    private func shouldFallbackToSoftwareInspection(
        for url: URL,
        inspectedAsset: TaptionVideoAsset
    ) -> Bool {
        let container = TaptionVideoContainer.inferred(from: url)
        guard SW_SoftwareCodecBackendRegistry.vlcSoftwareDecoder.readableContainers.contains(container) else {
            return false
        }

        return inspectedAsset.videoTrack == nil
            || inspectedAsset.videoTrack?.codec == .unknown
    }
}

private struct SW_VLCMediaInspector: MediaInspecting {
    func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
        let media = try Media(url: url)
        configureParseOptions(on: media, sourceURL: url)
        do {
            _ = try await media.parse(timeout: .seconds(10))
        } catch {
            if let fallbackAsset = fallbackAsset(for: url) {
                return fallbackAsset
            }
            throw error
        }
        let tracks = media.tracks()
        let videoTrack = tracks
            .first(where: { $0.type == .video })
            .map { makeVideoTrackInfo(from: $0, url: url) }
            ?? fallbackVideoTrack(for: url)
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

    private func fallbackAsset(for url: URL) -> TaptionVideoAsset? {
        guard let videoTrack = fallbackVideoTrack(for: url) else {
            return nil
        }

        return TaptionVideoAsset(
            displayName: url.lastPathComponent,
            location: TaptionVideoAssetLocation(kind: .file, url: url),
            container: TaptionVideoContainer.inferred(from: url),
            duration: nil,
            videoTrack: videoTrack,
            audioTracks: [],
            fingerprint: fingerprint(for: url)
        )
    }

    private func fallbackVideoTrack(for url: URL) -> TaptionVideoTrackInfo? {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "h261" {
            return TaptionVideoTrackInfo(
                codec: .h261,
                naturalSize: TaptionPixelSize(width: 176, height: 144),
                displaySize: TaptionPixelSize(width: 176, height: 144),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 25),
                estimatedBitrate: nil,
                color: TaptionColorDescription(),
                rotationDegrees: 0
            )
        }

        switch TaptionVideoContainer.inferred(from: url) {
        case .mpegProgramStream:
            return mpegVideoTrackInfo(for: url)
        default:
            return nil
        }
    }

    private func configureParseOptions(on media: Media, sourceURL: URL) {
        let fileExtension = sourceURL.pathExtension.lowercased()
        if ["avi", "mov", "qt", "h261"].contains(fileExtension) {
            media.addOption(":demux=avformat")
        }
        if fileExtension == "h261" {
            media.addOption(":avformat-format=h261")
        }
    }

    private func makeVideoTrackInfo(from track: Track, url: URL) -> TaptionVideoTrackInfo {
        let codec = videoCodec(from: track, url: url)
        let headerInfo = codec == .theora ? theoraHeaderInfo(for: url) : nil
        let headerSize = headerInfo?.size
        let parsedWidth = track.width.flatMap { $0 > 2 ? $0 : nil }
        let parsedHeight = track.height.flatMap { $0 > 2 ? $0 : nil }
        let width = max(parsedWidth ?? headerSize?.width ?? 0, 2)
        let height = max(parsedHeight ?? headerSize?.height ?? 0, 2)
        return TaptionVideoTrackInfo(
            codec: codec,
            naturalSize: TaptionPixelSize(width: width, height: height),
            displaySize: TaptionPixelSize(width: width, height: height),
            nominalFrameRate: frameRate(from: track.frameRate) ?? headerInfo?.frameRate,
            estimatedBitrate: track.bitrate > 0 ? track.bitrate : nil,
            color: TaptionColorDescription(),
            rotationDegrees: 0
        )
    }

    private struct TheoraHeaderInfo {
        var size: TaptionPixelSize
        var frameRate: TaptionRationalFrameRate?
    }

    private func theoraHeaderInfo(for url: URL) -> TheoraHeaderInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer {
            try? handle.close()
        }

        let data = handle.readData(ofLength: 128 * 1024)
        let bytes = [UInt8](data)
        let signature = Array("theora".utf8)
        guard let signatureStart = bytes.indices.first(where: { index in
            index > 0
                && bytes[index - 1] == 0x80
                && index + signature.count <= bytes.count
                && Array(bytes[index..<index + signature.count]) == signature
        }) else {
            return nil
        }

        let packetStart = signatureStart - 1
        guard packetStart + 30 <= bytes.count else {
            return nil
        }

        let pictureWidth = readUInt24(bytes, at: packetStart + 14)
        let pictureHeight = readUInt24(bytes, at: packetStart + 17)
        guard pictureWidth > 0,
              pictureHeight > 0 else {
            return nil
        }

        let frameRateNumerator = readUInt32(bytes, at: packetStart + 22)
        let frameRateDenominator = readUInt32(bytes, at: packetStart + 26)
        let frameRate: TaptionRationalFrameRate?
        if frameRateNumerator > 0, frameRateDenominator > 0 {
            frameRate = TaptionRationalFrameRate(
                numerator: Int(frameRateNumerator),
                denominator: Int(frameRateDenominator)
            )
        } else {
            frameRate = nil
        }

        return TheoraHeaderInfo(
            size: TaptionPixelSize(width: Int(pictureWidth), height: Int(pictureHeight)),
            frameRate: frameRate
        )
    }

    private func readUInt24(_ bytes: [UInt8], at index: Int) -> UInt32 {
        guard index + 2 < bytes.count else {
            return 0
        }
        return UInt32(bytes[index]) << 16
            | UInt32(bytes[index + 1]) << 8
            | UInt32(bytes[index + 2])
    }

    private func readUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        guard index + 3 < bytes.count else {
            return 0
        }
        return UInt32(bytes[index]) << 24
            | UInt32(bytes[index + 1]) << 16
            | UInt32(bytes[index + 2]) << 8
            | UInt32(bytes[index + 3])
    }

    private func videoCodec(from track: Track, url: URL) -> TaptionVideoCodec {
        let codec = videoCodec(from: track.codec)
        guard codec == .unknown else {
            return codec
        }

        let metadata = [
            track.name,
            track.trackDescription,
            url.deletingPathExtension().lastPathComponent
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if metadata.contains("snow") {
            return .snow
        }
        if metadata.contains("huffyuv") || metadata.contains("huff") {
            return .huffYUV
        }
        if metadata.contains("utvideo") || metadata.contains("ut video") {
            return .utVideo
        }
        if metadata.contains("vc-1") || metadata.contains("vc1") {
            return .vc1
        }
        if metadata.contains("realvideo 1.0") || metadata.contains("rv10") {
            return .realVideo1
        }
        if metadata.contains("realvideo") || metadata.contains("rv20") {
            return .realVideo
        }
        if metadata.contains("dvcpro") || metadata.contains("dv50") {
            return .dvcPro
        }
        if metadata.contains("dvvideo")
            || metadata.split(separator: " ").contains("dv") {
            return .dv
        }
        if metadata.contains("roq") {
            return .roqVideo
        }
        if metadata.contains("quicktime graphics") || metadata.contains("smc") {
            return .quickTimeGraphics
        }
        if metadata.contains("yuv4") {
            return .yuv4
        }
        if metadata.contains("msrle") || metadata.contains("microsoft rle") {
            return .microsoftRLE
        }
        if metadata.contains("magic") || metadata.contains("magy") {
            return .magicYUV
        }
        if metadata.contains("cfhd") || metadata.contains("cineform") {
            return .cineForm
        }
        if metadata.contains("dnx") {
            return .dnxhd
        }
        if metadata.contains("png video") || metadata.contains("png") {
            return .pngVideo
        }
        if metadata.contains("r10k") {
            return .r10k
        }
        if metadata.contains("r210") {
            return .r210
        }
        if metadata.contains("y41p") {
            return .y41p
        }
        if metadata.contains("rawvideo") || metadata.contains("raw video") {
            return .rawVideo
        }
        if metadata.contains("v410") {
            return .v410
        }
        if metadata.contains("v308") {
            return .v308
        }
        if metadata.contains("v408") {
            return .v408
        }
        return .unknown
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
        for fourCC in normalizedFourCCCandidates(codec) {
            switch fourCC {
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
            case "mp4v", "fmp4":
                return .mpeg4Visual
            case "mp2v", "mpeg":
                return .mpeg2
            case "mp1v":
                return .mpeg1
            case "h263", "s263":
                return .h263
            case "h261":
                return .h261
            case "flv1":
                return .flashVideo
            case "mp42":
                return .microsoftMPEG4V2
            case "mp43", "div3", "div4", "div5", "mpg3":
                return .microsoftMPEG4V3
            case "jpeg", "dmb1", "mjpg", "mjpa", "mjpb":
                return .motionJPEG
            case "mjp2", "avj2":
                return .jpeg2000
            case "mjls":
                return .jpegLS
            case "ljpg":
                return .losslessJPEG
            case "rle":
                return .animation
            case "cvid":
                return .cinepak
            case "rpza":
                return .quickTimeVideo
            case "smc":
                return .quickTimeGraphics
            case "svq1":
                return .sorensonVideo
            case "svq3":
                return .sorensonVideo3
            case "theo", "thra":
                return .theora
            case "rv10":
                return .realVideo1
            case "rv20", "rv30", "rv40", "rv60":
                return .realVideo
            case "roq":
                return .roqVideo
            case "dvc":
                return .dv
            case "dvcp", "dvpp", "dv5n", "dv5p":
                return .dvcPro
            case "dvhp", "dvhq", "dvh6", "dvh5", "dvh3", "dvh2":
                return .dvcProHD
            case "wvc1", "vc1":
                return .vc1
            case "ap4x", "ap4h", "apch", "apcn", "apcs", "apco":
                return .proRes
            case "aprn", "aprh":
                return .proResRaw
            case "wmv1", "wmv2", "wmv3":
                return .wmv
            case "msvc", "cram":
                return .microsoftVideo1
            case "mrle", "msrl":
                return .microsoftRLE
            case "asv1":
                return .asusV1
            case "asv2":
                return .asusV2
            case "fsv1", "flashsv":
                return .flashScreenVideo
            case "fsv2", "flashsv2":
                return .flashScreenVideo2
            case "zmbv":
                return .zmbv
            case "cljr":
                return .cljr
            case "snow":
                return .snow
            case "ffv1":
                return .ffv1
            case "hfyu", "ffvh":
                return .huffYUV
            case "uly0", "uly2", "uly4", "ulrg", "ulra":
                return .utVideo
            case "magy":
                return .magicYUV
            case "cfhd":
                return .cineForm
            case "avdn", "dnxhd", "dnxhr":
                return .dnxhd
            case "png", "png1", "mpng":
                return .pngVideo
            case "r10k", "r10g":
                return .r10k
            case "v210":
                return .v210
            case "r210":
                return .r210
            case "y41p":
                return .y41p
            case "raw ", "raw", "rawv", "iyuv", "i420", "yuy2":
                return .rawVideo
            case "v410":
                return .v410
            case "v308":
                return .v308
            case "v408":
                return .v408
            case "yuv4":
                return .yuv4
            default:
                continue
            }
        }
        return .unknown
    }

    private func audioCodec(from codec: Int) -> TaptionAudioCodec {
        switch UInt32(truncatingIfNeeded: codec) {
        case 0x0001:
            return .pcm
        case 0x0002, 0x0011:
            return .adpcm
        case 0x0006:
            return .aLaw
        case 0x0007:
            return .muLaw
        case 0x0050:
            return .mp2
        case 0x0055:
            return .mp3
        default:
            break
        }

        for fourCC in normalizedFourCCCandidates(codec) {
            switch fourCC {
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
                continue
            }
        }
        return .unknown
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
        normalizedFourCCCandidates(code).first ?? ""
    }

    private func normalizedFourCCCandidates(_ code: Int) -> [String] {
        let value = UInt32(truncatingIfNeeded: code)
        let littleEndian = fourCCString(bytes: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
        let bigEndian = fourCCString(bytes: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ])

        var candidates: [String] = []
        for candidate in [littleEndian, bigEndian] where !candidate.isEmpty && !candidates.contains(candidate) {
            candidates.append(candidate)
        }
        return candidates
    }

    private func fourCCString(bytes: [UInt8]) -> String {
        String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            .lowercased() ?? ""
    }

    private func mpegVideoTrackInfo(for url: URL) -> TaptionVideoTrackInfo? {
        guard let sequence = MPEGVideoSequenceHeaderParser.parse(url: url) else {
            return nil
        }

        return TaptionVideoTrackInfo(
            codec: sequence.codec,
            naturalSize: sequence.size,
            displaySize: sequence.size,
            nominalFrameRate: sequence.frameRate,
            estimatedBitrate: nil,
            color: TaptionColorDescription(),
            rotationDegrees: 0
        )
    }
}

private struct MPEGVideoSequenceHeaderParser {
    struct SequenceInfo {
        let codec: TaptionVideoCodec
        let size: TaptionPixelSize
        let frameRate: TaptionRationalFrameRate?
    }

    static func parse(url: URL) -> SequenceInfo? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }
        return parse(data: data)
    }

    private static func parse(data: Data) -> SequenceInfo? {
        let bytes = [UInt8](data.prefix(4 * 1_024 * 1_024))
        guard let sequenceHeaderIndex = firstStartCodeIndex(0xB3, in: bytes),
              sequenceHeaderIndex + 7 < bytes.count else {
            return nil
        }

        let payloadIndex = sequenceHeaderIndex + 4
        let width = Int(bytes[payloadIndex]) << 4
            | Int(bytes[payloadIndex + 1] >> 4)
        let height = Int(bytes[payloadIndex + 1] & 0x0F) << 8
            | Int(bytes[payloadIndex + 2])
        let frameRateCode = Int(bytes[payloadIndex + 3] & 0x0F)
        let hasSequenceExtension = containsSequenceExtension(
            in: bytes,
            after: sequenceHeaderIndex + 8
        )

        return SequenceInfo(
            codec: hasSequenceExtension ? .mpeg2 : .mpeg1,
            size: TaptionPixelSize(width: max(width, 2), height: max(height, 2)),
            frameRate: frameRate(for: frameRateCode)
        )
    }

    private static func containsSequenceExtension(
        in bytes: [UInt8],
        after startIndex: Int
    ) -> Bool {
        var index = max(startIndex, 0)
        while index + 4 < bytes.count {
            guard bytes[index] == 0x00,
                  bytes[index + 1] == 0x00,
                  bytes[index + 2] == 0x01 else {
                index += 1
                continue
            }
            let startCode = bytes[index + 3]
            if startCode == 0xB5 {
                return bytes[index + 4] >> 4 == 0x01
            }
            if startCode == 0x00 || startCode == 0xB3 {
                return false
            }
            index += 4
        }
        return false
    }

    private static func firstStartCodeIndex(_ code: UInt8, in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else {
            return nil
        }

        var index = 0
        while index + 3 < bytes.count {
            if bytes[index] == 0x00,
               bytes[index + 1] == 0x00,
               bytes[index + 2] == 0x01,
               bytes[index + 3] == code {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func frameRate(for code: Int) -> TaptionRationalFrameRate? {
        switch code {
        case 1:
            return TaptionRationalFrameRate(numerator: 24_000, denominator: 1_001)
        case 2:
            return TaptionRationalFrameRate(numerator: 24)
        case 3:
            return TaptionRationalFrameRate(numerator: 25)
        case 4:
            return TaptionRationalFrameRate(numerator: 30_000, denominator: 1_001)
        case 5:
            return TaptionRationalFrameRate(numerator: 30)
        case 6:
            return TaptionRationalFrameRate(numerator: 50)
        case 7:
            return TaptionRationalFrameRate(numerator: 60_000, denominator: 1_001)
        case 8:
            return TaptionRationalFrameRate(numerator: 60)
        default:
            return nil
        }
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
