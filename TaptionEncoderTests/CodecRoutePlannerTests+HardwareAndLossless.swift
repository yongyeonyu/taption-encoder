//
//  CodecRoutePlannerTests+HardwareAndLossless.swift
//  Tests 17388-18343 of the original CodecRoutePlannerTests.swift, moved here
//  unchanged. The name is the two leading subjects of the tests in this
//  range, counted from the test names.
//

import AVFoundation
import AudioToolbox
import CoreImage
import CoreMedia
import SwiftUI
import SwiftVLC
import UIKit
import XCTest
@testable import Taption_Encoder

extension CodecRoutePlannerTests {
    // MARK: - Lossless copy

    func testLosslessCopyIsUsedOnlyWhenThePlanChangesNothingAndAsksForNoSmallerFile() {
        let hevcSource = makeAsset(
            sourceCodec: .hevc,
            displaySize: TaptionPixelSize(width: 1920, height: 1080),
            videoBitrate: 8_000_000
        )

        func plan(targetBitrate: Int?, resizeTo: TaptionPixelSize?, source: TaptionVideoAsset) -> TaptionEncodingPlan {
            TaptionEncodingPlanner.makeSingleAssetPlan(
                asset: source,
                sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
                temporaryOutputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
                outputPolicy: TaptionVideoOutputPolicy(
                    videoCodec: .hevc,
                    container: .mp4,
                    advancedOptions: TaptionAdvancedOutputOptions(
                        resizeTo: resizeTo,
                        targetBitrate: targetBitrate
                    )
                )
            )
        }

        XCTAssertTrue(
            TaptionLosslessCopyPlanner.isEligible(
                plan: plan(targetBitrate: 12_000_000, resizeTo: nil, source: hevcSource)
            )
        )
        // Asking for a smaller file is the whole point of an encoder: a copy cannot deliver it.
        XCTAssertFalse(
            TaptionLosslessCopyPlanner.isEligible(
                plan: plan(targetBitrate: 4_000_000, resizeTo: nil, source: hevcSource)
            )
        )
        // A different frame is not a copy.
        XCTAssertFalse(
            TaptionLosslessCopyPlanner.isEligible(
                plan: plan(
                    targetBitrate: 12_000_000,
                    resizeTo: TaptionPixelSize(width: 1280, height: 720),
                    source: hevcSource
                )
            )
        )
        // A different source codec is not a copy either.
        XCTAssertFalse(
            TaptionLosslessCopyPlanner.isEligible(
                plan: plan(
                    targetBitrate: 40_000_000,
                    resizeTo: nil,
                    source: makeAsset(
                        sourceCodec: .h264,
                        displaySize: TaptionPixelSize(width: 1920, height: 1080),
                        videoBitrate: 8_000_000
                    )
                )
            )
        )
    }

    internal func makeAsset(
        sourceCodec: TaptionVideoCodec,
        displaySize: TaptionPixelSize = TaptionPixelSize(width: 1920, height: 1080),
        frameRate: TaptionRationalFrameRate = TaptionRationalFrameRate(numerator: 30),
        videoBitrate: Int? = nil,
        color: TaptionColorDescription = TaptionColorDescription(),
        duration: TimeInterval = 1,
        fileSize: Int64 = 1_000_000,
        fingerprint: TaptionMediaFingerprint? = nil
    ) -> TaptionVideoAsset {
        TaptionVideoAsset(
            displayName: "\(sourceCodec.rawValue).mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            duration: duration,
            videoTrack: TaptionVideoTrackInfo(
                codec: sourceCodec,
                naturalSize: displaySize,
                displaySize: displaySize,
                nominalFrameRate: frameRate,
                estimatedBitrate: videoBitrate,
                color: color
            ),
            audioTracks: [
                TaptionAudioTrackInfo(
                    codec: .aac,
                    channelCount: 2,
                    sampleRate: 48_000
                )
            ],
            fingerprint: fingerprint ?? TaptionMediaFingerprint(fileSize: fileSize)
        )
    }

    internal func makeAudioDescription(
        formatID: AudioFormatID,
        sampleRate: Double,
        channelCount: UInt32,
        formatFlags: AudioFormatFlags = 0,
        bytesPerPacket: UInt32 = 0,
        framesPerPacket: UInt32 = 0,
        bytesPerFrame: UInt32 = 0,
        bitsPerChannel: UInt32 = 0
    ) throws -> CMFormatDescription {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: formatID,
            mFormatFlags: formatFlags,
            mBytesPerPacket: bytesPerPacket,
            mFramesPerPacket: framesPerPacket,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: bitsPerChannel,
            mReserved: 0
        )
        var description: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &description
        )

        XCTAssertEqual(status, noErr)
        return try XCTUnwrap(description)
    }

    internal func syntheticDeviceCodecReport(
        modelIdentifier: String,
        decodeCodecs: Set<TaptionVideoCodec>,
        encodeCodecs: Set<TaptionVideoCodec>
    ) -> TaptionDeviceCodecCapabilityReport {
        let probedCodecs = Set(HW_CodecCapabilityProbe.probedVideoCodecs)
            .union(decodeCodecs)
            .union(encodeCodecs)
        return TaptionDeviceCodecCapabilityReport(
            modelIdentifier: modelIdentifier,
            systemName: "iOS",
            systemVersion: "26.0",
            probeResolution: TaptionPixelSize(width: 1920, height: 1080),
            generatedAt: Date(timeIntervalSince1970: 0),
            videoCapabilities: probedCodecs
                .sorted { $0.rawValue < $1.rawValue }
                .map { codec in
                    TaptionCodecHardwareCapability(
                        videoCodec: codec,
                        coreMediaCodecType: codec.rawValue,
                        hardwareDecodeSupported: decodeCodecs.contains(codec),
                        hardwareEncodeSupported: encodeCodecs.contains(codec),
                        encodeProbeStatus: encodeCodecs.contains(codec) ? 0 : -1,
                        encoderIdentifier: encodeCodecs.contains(codec) ? "test.hardware.\(codec.rawValue)" : nil
                    )
                },
            audioCapabilities: []
        )
    }

    internal func appleProfile(_ id: String) -> TaptionCodecHardwareSupportProfile {
        guard let profile = HW_AppleDeviceCodecProfiles.profile(id: id) else {
            XCTFail("Missing Apple device codec profile: \(id)")
            return .softwareOnly
        }
        return profile.hardwareSupportProfile
    }

    internal func appleModelProfile(_ identifier: String) -> TaptionCodecHardwareSupportProfile {
        guard let profile = HW_AppleDeviceCodecModelMatrix.hardwareSupportProfile(identifier: identifier) else {
            XCTFail("Missing Apple device model codec profile: \(identifier)")
            return .softwareOnly
        }
        return profile
    }

    internal func containerSort(
        _ lhs: TaptionVideoContainer,
        _ rhs: TaptionVideoContainer
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - Device-only encoder evidence

    // These two need a real HEVC encoder, so they are skipped in the simulator and run on a device:
    //   xcodebuild test-without-building -destination 'platform=iOS,id=<UDID>' \
    //     -only-testing:TaptionEncoderTests/CodecRoutePlannerTests/testHardwareEncodePlacesTheFrameAccordingToTheScaleMode

    func testHardwareEncodePlacesTheFrameAccordingToTheScaleMode() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Needs a device HEVC encoder.")
        #else
        let directory = try makeEvidenceDirectory(named: "scale-mode")
        defer { try? FileManager.default.removeItem(at: directory) }

        // A 4:3 source in a 16:9 frame: the three placements have to look different at the frame's left edge.
        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await writeEvidenceVideo(
            size: CGSize(width: 640, height: 480),
            seconds: 1.2,
            fill: .white,
            to: sourceURL
        )

        func encode(_ mode: TaptionVideoScaleMode) async throws -> URL {
            let outputURL = directory.appendingPathComponent("out-\(mode.rawValue).mp4")
            _ = try await HW_AppleHEVCCodecAlgorithm.transcode(
                request: TaptionCodecTranscodeRequest(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    route: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc),
                    options: TaptionCodecTranscodeOptions(
                        outputPolicy: TaptionVideoOutputPolicy(
                            videoCodec: .hevc,
                            container: .mp4,
                            advancedOptions: TaptionAdvancedOutputOptions(
                                resizeTo: TaptionPixelSize(width: 1280, height: 720),
                                targetBitrate: 4_000_000,
                                scaleMode: mode
                            )
                        ),
                        preserveAudioWhenPossible: false
                    )
                ),
                progress: { _ in }
            )
            return outputURL
        }

        let fit = try await encode(.fit)
        let fill = try await encode(.fill)
        let stretch = try await encode(.stretch)

        // Every mode still has to produce the frame that was asked for.
        for url in [fit, fill, stretch] {
            let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
            XCTAssertEqual(
                try XCTUnwrap(track).naturalSize,
                CGSize(width: 1280, height: 720),
                "\(url.lastPathComponent) did not come out at the requested frame"
            )
        }

        let fitEdge = try await averagePixelValue(in: fit, x: 4, y: 360)
        let fillEdge = try await averagePixelValue(in: fill, x: 4, y: 360)
        let stretchEdge = try await averagePixelValue(in: stretch, x: 4, y: 360)
        print("SCALE-MODE EVIDENCE left-edge(0-255) fit=\(fitEdge) fill=\(fillEdge) stretch=\(stretchEdge)")

        XCTAssertLessThan(fitEdge, 40, "fit should leave a black bar beside the 4:3 picture")
        XCTAssertGreaterThan(fillEdge, 200, "fill should put picture at the frame's edge")
        XCTAssertGreaterThan(stretchEdge, 200, "stretch should put picture at the frame's edge")
        #endif
    }

    func testHardwareEncodeUsesTheRequestedBitrate() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Needs a device HEVC encoder.")
        #else
        let directory = try makeEvidenceDirectory(named: "bitrate")
        defer { try? FileManager.default.removeItem(at: directory) }

        // Noise, because a flat picture would compress to almost nothing at any bitrate setting and the test would
        // pass even if the number never reached the encoder.
        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await writeEvidenceVideo(
            size: CGSize(width: 640, height: 480),
            seconds: 1.5,
            fill: .noise,
            to: sourceURL
        )

        func encodedFileSize(bitrate: Int) async throws -> Int {
            let outputURL = directory.appendingPathComponent("out-\(bitrate).mp4")
            _ = try await HW_AppleHEVCCodecAlgorithm.transcode(
                request: TaptionCodecTranscodeRequest(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    route: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc),
                    options: TaptionCodecTranscodeOptions(
                        outputPolicy: TaptionVideoOutputPolicy(
                            videoCodec: .hevc,
                            container: .mp4,
                            advancedOptions: TaptionAdvancedOutputOptions(targetBitrate: bitrate)
                        ),
                        // No audio, on purpose: this used to be the case that quietly left this path entirely.
                        preserveAudioWhenPossible: false
                    )
                ),
                progress: { _ in }
            )
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            return (attributes[.size] as? NSNumber)?.intValue ?? 0
        }

        let small = try await encodedFileSize(bitrate: 700_000)
        let large = try await encodedFileSize(bitrate: 9_000_000)
        print("BITRATE EVIDENCE 700kbps=\(small)B 9Mbps=\(large)B ratio=\(Double(large) / Double(max(small, 1)))")

        XCTAssertGreaterThan(small, 0)
        // The export-session fallback ignored the number entirely, so both sizes used to land on the preset's
        // value. A factor of two is far below the 12.8x asked for, so it only passes if the bitrate took effect.
        XCTAssertGreaterThan(
            large,
            small * 2,
            "the plan's bitrate has to reach the encoder (small=\(small) large=\(large))"
        )
        #endif
    }

    /// HDR and 10-bit sources used to be turned away from the sized writer, which handed the plan's bitrate back to
    /// a preset table. They are now written as Main 10 with the source's own colour tags — so both the bitrate and
    /// the colour survive, which is what this pins down.
    func testSizedWriterKeepsHDRAndTheBitrateForA10BitSource() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Needs a device HEVC 10-bit encoder; the simulator encoder ignores the profile and the bitrate.")
        #else
        let directory = try makeEvidenceDirectory(named: "hdr-bitrate")
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("hlg-source.mp4")
        try await writeHLGEvidenceVideo(
            size: CGSize(width: 640, height: 360),
            seconds: 1.5,
            to: sourceURL
        )

        // If the fixture is not actually HDR, everything below would pass for the wrong reason.
        let sourceAsset = try await AVFoundationMediaInspector().inspectVideo(at: sourceURL)
        let sourceColor = try XCTUnwrap(sourceAsset.videoTrack?.color)
        XCTAssertEqual(sourceColor.bitDepth, 10)
        XCTAssertEqual(sourceColor.primaries, .bt2020)
        XCTAssertEqual(sourceColor.transfer, .hlg)
        XCTAssertTrue(sourceColor.isHDR)

        func encode(_ bitrate: Int) async throws -> URL {
            let outputURL = directory.appendingPathComponent("hdr-\(bitrate).mp4")
            _ = try await HW_AppleHEVCCodecAlgorithm.transcode(
                request: TaptionCodecTranscodeRequest(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    route: TaptionCodecRoute(sourceCodec: .hevc, outputCodec: .hevc),
                    options: TaptionCodecTranscodeOptions(
                        outputPolicy: TaptionVideoOutputPolicy(
                            videoCodec: .hevc,
                            container: .mp4,
                            // Exactly what `TaptionSourcePreservingOutputPolicyResolver` hands over in the app:
                            // the source's own colour, because the user asked for nothing in particular. Passing
                            // nothing here instead would have hidden the fact that the old guard turned this away.
                            advancedOptions: TaptionAdvancedOutputOptions(
                                targetBitrate: bitrate,
                                color: sourceColor
                            )
                        ),
                        preserveAudioWhenPossible: false
                    )
                ),
                progress: { _ in }
            )
            return outputURL
        }

        let smallURL = try await encode(700_000)
        let largeURL = try await encode(9_000_000)

        for url in [smallURL, largeURL] {
            let asset = try await AVFoundationMediaInspector().inspectVideo(at: url)
            XCTAssertEqual(asset.videoTrack?.codec, .hevc, url.lastPathComponent)
            // The whole point: the extra precision and the HDR tags have to come out the other side.
            XCTAssertEqual(asset.videoTrack?.color.bitDepth, 10, "\(url.lastPathComponent) lost the 10-bit depth")
            XCTAssertEqual(asset.videoTrack?.color.transfer, .hlg, url.lastPathComponent)
            XCTAssertEqual(asset.videoTrack?.color.primaries, .bt2020, url.lastPathComponent)
            XCTAssertTrue(asset.videoTrack?.color.isHDR ?? false, url.lastPathComponent)
            XCTAssertEqual(asset.videoTrack?.displaySize, TaptionPixelSize(width: 640, height: 360))
        }

        func byteCount(_ url: URL) throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.intValue ?? 0
        }
        let smallBytes = try byteCount(smallURL)
        let largeBytes = try byteCount(largeURL)
        print("HDR BITRATE EVIDENCE 700kbps=\(smallBytes)B 9Mbps=\(largeBytes)B")
        XCTAssertGreaterThan(
            largeBytes,
            smallBytes * 2,
            "the bitrate has to reach the encoder for an HDR source too (small=\(smallBytes) large=\(largeBytes))"
        )
        #endif
    }

    func testHardwareEncodeUsesTheRequestedBitrateForAnAV1Source() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Needs a device AV1 decoder.")
        #else
        // The fixture is pushed into the app container before the run, because an AV1 file cannot be produced by
        // this app or by the test bundle itself:
        //   ffmpeg -f lavfi -i "testsrc2=size=640x480:rate=30:duration=1.5" \
        //     -c:v libsvtav1 -preset 10 -crf 40 -pix_fmt yuv420p /tmp/av1-fixture.mp4
        //   xcrun devicectl device copy to --domain-type=appDataContainer \
        //     --domain-identifier=com.taption.encoder --source=/tmp/av1-fixture.mp4 \
        //     --destination=Documents/av1-fixture.mp4
        let documents = try XCTUnwrap(
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        )
        let sourceURL = documents.appendingPathComponent("av1-fixture.mp4")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: sourceURL.path),
            "Push the AV1 fixture into the app container first."
        )

        let directory = try makeEvidenceDirectory(named: "av1-bitrate")
        defer { try? FileManager.default.removeItem(at: directory) }

        func encodedFileSize(bitrate: Int) async throws -> Int {
            let outputURL = directory.appendingPathComponent("out-\(bitrate).mp4")
            _ = try await HW_AV1HEVCCodecAlgorithm.transcode(
                request: TaptionCodecTranscodeRequest(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    route: TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc),
                    options: TaptionCodecTranscodeOptions(
                        outputPolicy: TaptionVideoOutputPolicy(
                            videoCodec: .hevc,
                            container: .mp4,
                            advancedOptions: TaptionAdvancedOutputOptions(targetBitrate: bitrate)
                        ),
                        preserveAudioWhenPossible: false
                    )
                ),
                progress: { _ in }
            )
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            return (attributes[.size] as? NSNumber)?.intValue ?? 0
        }

        let small = try await encodedFileSize(bitrate: 700_000)
        let large = try await encodedFileSize(bitrate: 9_000_000)
        print("AV1 BITRATE EVIDENCE 700kbps=\(small)B 9Mbps=\(large)B ratio=\(Double(large) / Double(max(small, 1)))")

        XCTAssertGreaterThan(small, 0)
        XCTAssertGreaterThan(
            large,
            small * 2,
            "the plan's bitrate has to reach an AV1 encode too (small=\(small) large=\(large))"
        )
        #endif
    }

    internal func makeEvidenceDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    internal enum EvidenceFill {
        case white
        case noise
    }

    /// The compressed samples of the video track, exactly as stored in the file.
    internal func encodedVideoSampleData(at url: URL) async throws -> [Data] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var samples: [Data] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &pointer
            ) == kCMBlockBufferNoErr,
                  let pointer,
                  length > 0 else {
                continue
            }
            samples.append(Data(bytes: pointer, count: length))
        }
        return samples
    }

    internal func writeEvidenceVideo(
        size: CGSize,
        seconds: Double,
        fill: EvidenceFill,
        to url: URL,
        withPCMAudio: Bool = false
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = Int(size.width)
        let height = Int(size.height)
        let frameRate: Int32 = 30
        let fileType: AVFileType = url.pathExtension.lowercased() == "mov" ? .mov : .mp4
        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else {
            throw NSError(
                domain: "TaptionEncoderTests",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not add the fixture video input."]
            )
        }
        writer.add(input)

        // Linear PCM audio: the codec the sized writer has to re-encode rather than pass through.
        let audioInput: AVAssetWriterInput? = withPCMAudio
            ? AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 44_100.0,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ]
            )
            : nil
        if let audioInput {
            audioInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(audioInput) else {
                throw NSError(
                    domain: "TaptionEncoderTests",
                    code: -7,
                    userInfo: [NSLocalizedDescriptionKey: "Could not add the fixture audio input."]
                )
            }
            writer.add(audioInput)
        }

        guard writer.startWriting() else {
            throw writer.error ?? NSError(
                domain: "TaptionEncoderTests",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Could not start the fixture writer."]
            )
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(seconds * Double(frameRate)))
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw NSError(
                    domain: "TaptionEncoderTests",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "The fixture pixel buffer pool is missing."]
                )
            }
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer else {
                throw NSError(
                    domain: "TaptionEncoderTests",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create a fixture frame."]
                )
            }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
                let bytes = base.assumingMemoryBound(to: UInt8.self)
                switch fill {
                case .white:
                    memset(bytes, 0xFF, stride * height)
                case .noise:
                    // A different pattern on every frame, so the encoder cannot reuse the previous picture.
                    var seed = UInt32(truncatingIfNeeded: 0x1234_5678 &+ UInt32(index) &* 7919)
                    for y in 0..<height {
                        let row = bytes.advanced(by: y * stride)
                        for x in 0..<width {
                            seed = seed &* 1_664_525 &+ 1_013_904_223
                            let value = UInt8(truncatingIfNeeded: seed >> 16)
                            row[x * 4] = value
                            row[x * 4 + 1] = value
                            row[x * 4 + 2] = value
                            row[x * 4 + 3] = 255
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            guard adaptor.append(
                pixelBuffer,
                withPresentationTime: CMTime(value: CMTimeValue(index), timescale: frameRate)
            ) else {
                throw writer.error ?? NSError(
                    domain: "TaptionEncoderTests",
                    code: -5,
                    userInfo: [NSLocalizedDescriptionKey: "Could not append a fixture frame."]
                )
            }
        }

        if let audioInput {
            try await appendPCMToneAudio(
                to: audioInput,
                seconds: seconds,
                sampleRate: 44_100,
                writer: writer
            )
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(
                domain: "TaptionEncoderTests",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "The fixture writer did not finish."]
            )
        }
    }

    /// Writes a 10-bit BT.2020/HLG fixture, the shape a phone HDR recording has.
    ///
    /// The picture is noise on purpose: a flat colour compresses to almost nothing at any bitrate, so a bitrate
    /// assertion against a flat fixture passes without the bitrate ever reaching the encoder.
    internal func writeHLGEvidenceVideo(
        size: CGSize,
        seconds: Double,
        to url: URL
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let width = Int(size.width)
        let height = Int(size.height)
        let frameRate: Int32 = 30
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel,
                    // The fixture has to be encoded at a high bitrate of its own. At the writer's default it
                    // comes out around 250 kbps, and a blurred source is easy enough to re-encode that the
                    // encoder underspends both targets and the two outputs land on the same size.
                    AVVideoAverageBitRateKey: 20_000_000
                ]
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else {
            throw NSError(
                domain: "TaptionEncoderTests",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: "Could not add the HDR fixture video input."]
            )
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(
                domain: "TaptionEncoderTests",
                code: -12,
                userInfo: [NSLocalizedDescriptionKey: "Could not start the HDR fixture writer."]
            )
        }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(seconds * Double(frameRate)))
        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else {
                throw NSError(
                    domain: "TaptionEncoderTests",
                    code: -13,
                    userInfo: [NSLocalizedDescriptionKey: "The HDR fixture pixel buffer pool is missing."]
                )
            }
            var pixelBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
                  let pixelBuffer else {
                throw NSError(
                    domain: "TaptionEncoderTests",
                    code: -14,
                    userInfo: [NSLocalizedDescriptionKey: "Could not create an HDR fixture frame."]
                )
            }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
                let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
                var seed = UInt32(truncatingIfNeeded: 0x0BAD_F00D &+ UInt32(index) &* 7919)
                for y in 0..<height {
                    let row = lumaBase.advanced(by: y * lumaStride).assumingMemoryBound(to: UInt16.self)
                    for x in 0..<width {
                        seed = seed &* 1_664_525 &+ 1_013_904_223
                        // Video-range 10-bit luma, so the values are legal for a limited-range file.
                        row[x] = UInt16(64 + (seed >> 16) % 876)
                    }
                }
            }
            if let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
                let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
                let chromaWidth = (width + 1) / 2
                for y in 0..<((height + 1) / 2) {
                    let row = chromaBase.advanced(by: y * chromaStride).assumingMemoryBound(to: UInt16.self)
                    for x in 0..<chromaWidth {
                        row[x * 2] = 512
                        row[x * 2 + 1] = 512
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            guard adaptor.append(
                pixelBuffer,
                withPresentationTime: CMTime(value: CMTimeValue(index), timescale: frameRate)
            ) else {
                throw writer.error ?? NSError(
                    domain: "TaptionEncoderTests",
                    code: -15,
                    userInfo: [NSLocalizedDescriptionKey: "Could not append an HDR fixture frame."]
                )
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? NSError(
                domain: "TaptionEncoderTests",
                code: -16,
                userInfo: [NSLocalizedDescriptionKey: "The HDR fixture writer did not finish."]
            )
        }
    }

    /// Writes a mono 16-bit PCM tone, so the fixture carries real audio the encoder has to deal with.
    internal func appendPCMToneAudio(
        to input: AVAssetWriterInput,
        seconds: Double,
        sampleRate: Double,
        writer: AVAssetWriter
    ) async throws {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw NSError(
                domain: "TaptionEncoderTests",
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: "Could not describe the fixture PCM format."]
            )
        }

        let timescale = CMTimeScale(sampleRate)
        let totalFrames = max(1, Int(seconds * sampleRate))
        let chunkFrames = 1_024
        var written = 0
        while written < totalFrames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
                if writer.status == .failed || writer.status == .cancelled {
                    throw writer.error ?? NSError(
                        domain: "TaptionEncoderTests",
                        code: -9,
                        userInfo: [NSLocalizedDescriptionKey: "The fixture writer stopped during audio."]
                    )
                }
            }
            let frames = min(chunkFrames, totalFrames - written)
            let byteCount = frames * MemoryLayout<Int16>.size
            var samples = [Int16](repeating: 0, count: frames)
            for index in 0..<frames {
                let phase = 2 * Double.pi * 440 * Double(written + index) / sampleRate
                samples[index] = Int16(sin(phase) * 12_000)
            }

            var blockBuffer: CMBlockBuffer?
            let blockStatus = samples.withUnsafeBytes { raw -> OSStatus in
                var created: CMBlockBuffer?
                let createStatus = CMBlockBufferCreateWithMemoryBlock(
                    allocator: kCFAllocatorDefault,
                    memoryBlock: nil,
                    blockLength: byteCount,
                    blockAllocator: kCFAllocatorDefault,
                    customBlockSource: nil,
                    offsetToData: 0,
                    dataLength: byteCount,
                    flags: 0,
                    blockBufferOut: &created
                )
                guard createStatus == kCMBlockBufferNoErr, let created else {
                    return createStatus
                }
                let copyStatus = CMBlockBufferReplaceDataBytes(
                    with: raw.baseAddress!,
                    blockBuffer: created,
                    offsetIntoDestination: 0,
                    dataLength: byteCount
                )
                blockBuffer = created
                return copyStatus
            }
            guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
                throw NSError(
                    domain: "TaptionEncoderTests",
                    code: -10,
                    userInfo: [NSLocalizedDescriptionKey: "Could not build a fixture audio block."]
                )
            }

            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: timescale),
                presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: timescale),
                decodeTimeStamp: .invalid
            )
            var sampleBuffer: CMSampleBuffer?
            let sampleStatus = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: blockBuffer,
                formatDescription: formatDescription,
                sampleCount: frames,
                sampleTimingEntryCount: 1,
                sampleTimingArray: &timing,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer
            )
            guard sampleStatus == noErr,
                  let sampleBuffer,
                  input.append(sampleBuffer) else {
                throw NSError(
                    domain: "TaptionEncoderTests",
                    code: -11,
                    userInfo: [NSLocalizedDescriptionKey: "Could not append fixture audio."]
                )
            }
            written += frames
        }
        input.markAsFinished()
    }

    /// Average of the RGB channels at one point of the fifth frame, on a 0...255 scale.
    internal func averagePixelValue(in url: URL, x: Int, y: Int) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? NSError(
                domain: "TaptionEncoderTests",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "Could not read the encoded file back."]
            )
        }
        defer { reader.cancelReading() }

        // Skip the first frames: the opening keyframe is not necessarily representative of the placement.
        var sampleBuffer = output.copyNextSampleBuffer()
        for _ in 0..<4 {
            sampleBuffer = output.copyNextSampleBuffer()
        }
        guard let sampleBuffer,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw NSError(
                domain: "TaptionEncoderTests",
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: "The encoded file produced no frames."]
            )
        }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        guard let base = CVPixelBufferGetBaseAddress(imageBuffer) else {
            throw NSError(
                domain: "TaptionEncoderTests",
                code: -9,
                userInfo: [NSLocalizedDescriptionKey: "The decoded frame has no base address."]
            )
        }
        let stride = CVPixelBufferGetBytesPerRow(imageBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let sampleX = min(max(x, 0), width - 1)
        let sampleY = min(max(y, 0), height - 1)
        let offset = sampleY * stride + sampleX * 4
        // BGRA.
        return (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / 3
    }
}
