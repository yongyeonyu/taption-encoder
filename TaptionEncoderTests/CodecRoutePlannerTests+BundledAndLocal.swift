//
//  CodecRoutePlannerTests+BundledAndLocal.swift
//  Tests 5950-7867 of the original CodecRoutePlannerTests.swift, moved here
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
    func testSingleAssetPlanOmitsAudioPlanWhenSourceHasNoAudio() {
        let asset = TaptionVideoAsset(
            displayName: "silent-av1.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .av1,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: []
        )

        let plan = TaptionEncodingPlanner.makeSingleAssetHEVCPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/silent-av1.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/silent-av1_taption.mp4")
        )

        XCTAssertNil(plan.audioPlan)
    }

    func testSingleAssetSoftwareCommandPlanDisablesAudioWhenSourceHasNoAudio() throws {
        let asset = TaptionVideoAsset(
            displayName: "silent-vp9.webm",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .webm,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .vp9,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: []
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/silent-vp9.webm"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/silent-vp9_taption.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )

        let commandPlan = try SW_FFmpegCodecCommandPlanner.makeSingleAssetCommandPlan(plan: plan)

        XCTAssertTrue(commandPlan.arguments.contains("-an"))
        XCTAssertFalse(commandPlan.arguments.contains("0:a?"))
        XCTAssertNil(plan.audioPlan)
    }

    func testEncodingStateDetailUsesSelectedOutputSummary() {
        let progress = EncodingProgressSnapshot(
            stage: .encoding,
            fractionCompleted: 0.4,
            elapsedTime: 3,
            estimatedRemainingTime: 4,
            backendLabel: "Path SW",
            outputSummary: "H.264 / AVI"
        )

        let detail = HomeScreenState.encoding(progress).detail

        XCTAssertEqual(detail, "Path SW is converting the source to H.264 / AVI.")
        XCTAssertFalse(detail.contains("H.265"))
    }

    func testUnsupportedSourceCodecErrorSeparatesCurrentBuildFromUniversalRoadmap() {
        let message = TaptionVideoCoreError.unsupportedSourceCodec(.h264).localizedDescription
        let executableSummary = TaptionLaunchSupportCatalog.executableNowInputVideoCodecs
            .map(\.displayName)
            .joined(separator: ", ")

        XCTAssertTrue(message.contains("H.265 / MP4 or MOV output"))
        XCTAssertTrue(message.contains(executableSummary))
        XCTAssertTrue(message.contains("Hardware-gated inputs: Apple ProRes"))
        XCTAssertTrue(message.contains("Snow"))
        XCTAssertTrue(message.contains("Raw Video"))
        XCTAssertTrue(message.contains("H.264 / AVC"))
        XCTAssertTrue(message.contains("universal codec roadmap"))
        XCTAssertTrue(message.contains("not executable on the selected device/output path yet"))
    }

    func testLocalRealVP8WebMSampleCanPrepareHEVCJob() async throws {
        try requireLocalRealSampleProofs()

        let sampleURL = URL(fileURLWithPath: "/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/real_samples/Demo_Video_Tutorial_8s.webm")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local real-sample proof requires Demo_Video_Tutorial_8s.webm.")
        }

        let outputURL = temporaryTestURL(fileName: "Demo_Video_Tutorial_8s_hevc.mp4")
        let media = try Media(url: sampleURL)
        _ = try await media.parse(timeout: .seconds(10))
        let parsedTracks = media.tracks()
        let trackSummary = parsedTracks.map { track in
            "\(track.type):codec=\(track.codec):name=\(track.name):desc=\(track.trackDescription ?? "-")"
        }.joined(separator: " | ")
        let inspectedAsset = try await AVFoundationMediaInspector().inspectVideo(at: sampleURL)
        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: FakeEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )

        XCTAssertEqual(inspectedAsset.container, .webm)
        XCTAssertEqual(inspectedAsset.videoTrack?.codec, .vp8, trackSummary)
        XCTAssertEqual(inspectedAsset.audioTracks.first?.codec, .vorbis, trackSummary)

        let job = try await core.prepareSingleAssetHEVCJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL
        )

        XCTAssertEqual(job.asset.displayName, inspectedAsset.displayName)
        XCTAssertEqual(job.asset.location, inspectedAsset.location)
        XCTAssertEqual(job.asset.container, inspectedAsset.container)
        XCTAssertEqual(job.asset.duration, inspectedAsset.duration)
        XCTAssertEqual(job.asset.videoTrack, inspectedAsset.videoTrack)
        XCTAssertEqual(job.asset.audioTracks, inspectedAsset.audioTracks)
        XCTAssertEqual(job.asset.fingerprint, inspectedAsset.fingerprint)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .vp8, outputCodec: .hevc))
        XCTAssertEqual(job.routeSelection.executionKind, .mixed)
        XCTAssertEqual(job.routeSelection.selectedMode, .software)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.routeSelection.encodeBackend, .appleVideoToolbox)
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.plan.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(job.plan.outputPolicy.container, .mp4)
        XCTAssertEqual(job.plan.outputPolicy.audioCodec, .aac)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .vorbis, outputCodec: .aac))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.support, .softwareTranscode)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertEqual(job.plan.audioPlan?.readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
    }

    func testBundledVLCAudioDecodeFeedsAppleWriterForRepresentativeCurrentBuildCodecs() {
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .aac,
                outputCodec: .aac,
                outputContainer: .mp4
            ),
            .softwareVLCDecoder
        )
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .mp3,
                outputCodec: .aac,
                outputContainer: .mp4
            ),
            .softwareVLCDecoder
        )
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .opus,
                outputCodec: .pcm,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .opus,
                outputCodec: .alac,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .amr,
                outputCodec: .pcm,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .amr,
                outputCodec: .alac,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .ac3,
                outputCodec: .pcm,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .ac3,
                outputCodec: .alac,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .eac3,
                outputCodec: .pcm,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .eac3,
                outputCodec: .alac,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertNil(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .opus,
                outputCodec: .pcm,
                outputContainer: .mp4
            )
        )
        XCTAssertNil(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: .opus,
                outputCodec: .alac,
                outputContainer: .mp4
            )
        )

        for sourceCodec in [TaptionAudioCodec.opus, .vorbis, .amr] {
            let route = TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: .aac)
            let selection = TaptionAudioCodecRoutePlanner.selectRoute(
                sourceCodec: sourceCodec,
                outputCodec: .aac,
                outputContainer: .mp4,
                preserveWhenPossible: false
            )
            let readiness = TaptionAudioCodecExecutionReadinessReporter.item(
                for: route,
                outputContainer: .mp4
            )
            let preferredDescriptor = TaptionAudioCodecDescriptorRegistry(
                outputContainer: .mp4
            ).preferredDescriptor(for: route)

            XCTAssertEqual(selection.support, .softwareTranscode, sourceCodec.displayName)
            XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder, sourceCodec.displayName)
            XCTAssertEqual(selection.encodeBackend, .appleAVAssetExport, sourceCodec.displayName)
            XCTAssertEqual(readiness.readiness, .softwareBackendExecutable, sourceCodec.displayName)
            XCTAssertTrue(readiness.isRunnableInCurrentBuild, sourceCodec.displayName)
            XCTAssertFalse(readiness.hasCommandPlan, sourceCodec.displayName)
            XCTAssertEqual(readiness.commandBackend, .softwareVLCDecoder, sourceCodec.displayName)
            XCTAssertEqual(preferredDescriptor?.backend, .softwareVLCDecoder, sourceCodec.displayName)
        }

        for sourceCodec in [TaptionAudioCodec.opus, .vorbis, .amr, .ac3, .eac3] {
            for outputCodec in [TaptionAudioCodec.pcm, .alac] {
                let route = TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
                let selection = TaptionAudioCodecRoutePlanner.selectRoute(
                    sourceCodec: sourceCodec,
                    outputCodec: outputCodec,
                    outputContainer: .mov,
                    preserveWhenPossible: false
                )
                let readiness = TaptionAudioCodecExecutionReadinessReporter.item(
                    for: route,
                    outputContainer: .mov
                )
                let preferredDescriptor = TaptionAudioCodecDescriptorRegistry(
                    outputContainer: .mov
                ).preferredDescriptor(for: route)
                let message = "\(sourceCodec.displayName) to \(outputCodec.displayName)"

                XCTAssertEqual(selection.support, .softwareTranscode, message)
                XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder, message)
                XCTAssertEqual(selection.encodeBackend, .appleAVAssetExport, message)
                XCTAssertEqual(readiness.readiness, .softwareBackendExecutable, message)
                XCTAssertTrue(readiness.isRunnableInCurrentBuild, message)
                XCTAssertFalse(readiness.hasCommandPlan, message)
                XCTAssertEqual(readiness.commandBackend, .softwareVLCDecoder, message)
                XCTAssertEqual(preferredDescriptor?.backend, .softwareVLCDecoder, message)
            }
        }
    }

    func testBundledH264AC3SampleEncodesHEVCMOVWithPCMAudioOnSoftwarePath() async throws {
        try await assertBundledH264DolbySampleEncodesHEVCMOVOnSoftwarePath(
            sampleFileName: "H.264 AC3.mp4",
            expectedSourceAudioCodec: .ac3,
            outputAudioCodec: .pcm,
            outputFileName: "h264-ac3-hevc-pcm.mov"
        )
    }

    func testBundledH264AC3SampleEncodesHEVCMOVWithALACAudioOnSoftwarePath() async throws {
        try await assertBundledH264DolbySampleEncodesHEVCMOVOnSoftwarePath(
            sampleFileName: "H.264 AC3.mp4",
            expectedSourceAudioCodec: .ac3,
            outputAudioCodec: .alac,
            outputFileName: "h264-ac3-hevc-alac.mov"
        )
    }

    func testBundledH264EAC3SampleEncodesHEVCMOVWithPCMAudioOnSoftwarePath() async throws {
        try await assertBundledH264DolbySampleEncodesHEVCMOVOnSoftwarePath(
            sampleFileName: "H.264 EAC3.mp4",
            expectedSourceAudioCodec: .eac3,
            outputAudioCodec: .pcm,
            outputFileName: "h264-eac3-hevc-pcm.mov"
        )
    }

    func testBundledH264EAC3SampleEncodesHEVCMOVWithALACAudioOnSoftwarePath() async throws {
        try await assertBundledH264DolbySampleEncodesHEVCMOVOnSoftwarePath(
            sampleFileName: "H.264 EAC3.mp4",
            expectedSourceAudioCodec: .eac3,
            outputAudioCodec: .alac,
            outputFileName: "h264-eac3-hevc-alac.mov"
        )
    }

    internal func assertBundledH264DolbySampleEncodesHEVCMOVOnSoftwarePath(
        sampleFileName: String,
        expectedSourceAudioCodec: TaptionAudioCodec,
        outputAudioCodec: TaptionAudioCodec,
        outputFileName: String
    ) async throws {
        let sampleURL = bundledTestVideosURL().appendingPathComponent(sampleFileName)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled Dolby proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: outputFileName)
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            audioCodec: outputAudioCodec,
            container: .mov
        )
        let job = try await core.prepareSingleAssetJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            outputPolicy: outputPolicy,
            preferredMode: .software,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let actualSourceAudioCodec = try XCTUnwrap(job.asset.audioTracks.first?.codec)

        XCTAssertEqual(job.asset.container, .mp4)
        XCTAssertEqual(job.asset.videoTrack?.codec, .h264)
        XCTAssertEqual(actualSourceAudioCodec, expectedSourceAudioCodec)
        XCTAssertEqual(job.asset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
        XCTAssertEqual(job.asset.audioTracks.first?.channelCount, 2)
        XCTAssertEqual(job.plan.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(job.plan.outputPolicy.audioCodec, outputAudioCodec)
        XCTAssertEqual(job.plan.outputPolicy.container, .mov)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: expectedSourceAudioCodec, outputCodec: outputAudioCodec))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.support, .softwareTranscode)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.encodeBackend, .appleAVAssetExport)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertEqual(job.plan.audioPlan?.readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: expectedSourceAudioCodec,
                outputCodec: outputAudioCodec,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
        XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 44_100)
        XCTAssertEqual(job.plan.audioPlan?.options.channelCount, 2)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mov)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, outputAudioCodec)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 2)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testBundledTheoraOpusSampleEncodesHEVCMOVWithPCMAudio() async throws {
        try await assertBundledTheoraSampleEncodesHEVCMOV(
            sampleFileName: "Theora.ogv",
            expectedSourceAudioCodec: .opus,
            outputAudioCodec: .pcm,
            outputFileName: "theora-opus-hevc-pcm.mov"
        )
    }

    func testBundledTheoraOpusSampleEncodesHEVCMOVWithALACAudio() async throws {
        try await assertBundledTheoraSampleEncodesHEVCMOV(
            sampleFileName: "Theora.ogv",
            expectedSourceAudioCodec: .opus,
            outputAudioCodec: .alac,
            outputFileName: "theora-opus-hevc-alac.mov"
        )
    }

    func testBundledTheoraVorbisSampleEncodesHEVCMOVWithPCMAudio() async throws {
        try await assertBundledTheoraSampleEncodesHEVCMOV(
            sampleFileName: "Theora Vorbis.ogv",
            expectedSourceAudioCodec: .vorbis,
            outputAudioCodec: .pcm,
            outputFileName: "theora-vorbis-hevc-pcm.mov"
        )
    }

    func testBundledTheoraVorbisSampleEncodesHEVCMOVWithALACAudio() async throws {
        try await assertBundledTheoraSampleEncodesHEVCMOV(
            sampleFileName: "Theora Vorbis.ogv",
            expectedSourceAudioCodec: .vorbis,
            outputAudioCodec: .alac,
            outputFileName: "theora-vorbis-hevc-alac.mov"
        )
    }

    internal func assertBundledTheoraSampleEncodesHEVCMOV(
        sampleFileName: String,
        expectedSourceAudioCodec: TaptionAudioCodec,
        outputAudioCodec: TaptionAudioCodec,
        outputFileName: String
    ) async throws {
        let sampleURL = bundledTestVideosURL().appendingPathComponent(sampleFileName)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled Theora proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: outputFileName)
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            audioCodec: outputAudioCodec,
            container: .mov
        )
        let job = try await core.prepareSingleAssetJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            outputPolicy: outputPolicy,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let sourceAudioCodec = try XCTUnwrap(job.asset.audioTracks.first?.codec)

        XCTAssertEqual(job.asset.container, .ogg)
        XCTAssertEqual(job.asset.videoTrack?.codec, .theora)
        XCTAssertEqual(sourceAudioCodec, expectedSourceAudioCodec)
        XCTAssertEqual(job.asset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(job.asset.audioTracks.first?.channelCount, 2)
        XCTAssertEqual(job.plan.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(job.plan.outputPolicy.audioCodec, outputAudioCodec)
        XCTAssertEqual(job.plan.outputPolicy.container, .mov)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .theora, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: expectedSourceAudioCodec, outputCodec: outputAudioCodec))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.support, .softwareTranscode)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.encodeBackend, .appleAVAssetExport)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertEqual(job.plan.audioPlan?.readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertEqual(
            SW_AudioCodecSupportCatalog.currentBuildBundledDecodeBackend(
                for: expectedSourceAudioCodec,
                outputCodec: outputAudioCodec,
                outputContainer: .mov
            ),
            .softwareVLCDecoder
        )
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
        XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 48_000)
        XCTAssertEqual(job.plan.audioPlan?.options.channelCount, 2)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mov)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, outputAudioCodec)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 2)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testBundledFlashVideoMP3SampleEncodesHEVCMOVWithPCMAudio() async throws {
        try await assertBundledFlashVideoMP3SampleEncodesHEVCMOV(
            outputAudioCodec: .pcm,
            outputFileName: "flash-video-mp3-hevc-pcm.mov"
        )
    }

    func testBundledFlashVideoMP3SampleEncodesHEVCMOVWithALACAudio() async throws {
        try await assertBundledFlashVideoMP3SampleEncodesHEVCMOV(
            outputAudioCodec: .alac,
            outputFileName: "flash-video-mp3-hevc-alac.mov"
        )
    }

    internal func assertBundledFlashVideoMP3SampleEncodesHEVCMOV(
        outputAudioCodec: TaptionAudioCodec,
        outputFileName: String
    ) async throws {
        let sampleURL = bundledTestVideosURL().appendingPathComponent("Flash Video.flv")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled MP3 proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: outputFileName)
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            audioCodec: outputAudioCodec,
            container: .mov
        )
        let job = try await core.prepareSingleAssetJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            outputPolicy: outputPolicy,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let sourceAudioCodec = try XCTUnwrap(job.asset.audioTracks.first?.codec)

        XCTAssertEqual(job.asset.container, .flv)
        XCTAssertEqual(job.asset.videoTrack?.codec, .flashVideo)
        XCTAssertEqual(sourceAudioCodec, .mp3)
        XCTAssertEqual(job.asset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
        XCTAssertEqual(job.asset.audioTracks.first?.channelCount, 2)
        XCTAssertEqual(job.plan.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(job.plan.outputPolicy.audioCodec, outputAudioCodec)
        XCTAssertEqual(job.plan.outputPolicy.container, .mov)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .flashVideo, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .mp3, outputCodec: outputAudioCodec))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.support, .nativeTranscode)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.encodeBackend, .appleAVAssetExport)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .nativeTranscodeInCurrentBuild)
        XCTAssertNil(job.plan.audioPlan?.readiness.commandBackend)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
        XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 44_100)
        XCTAssertEqual(job.plan.audioPlan?.options.channelCount, 2)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mov)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, outputAudioCodec)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 2)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testBundledQuickTimeVideoAACSampleEncodesHEVCMOVWithPCMAudio() async throws {
        try await assertBundledQuickTimeVideoAACSampleEncodesHEVCMOV(
            outputAudioCodec: .pcm,
            outputFileName: "quicktime-video-aac-hevc-pcm.mov"
        )
    }

    func testBundledQuickTimeVideoAACSampleEncodesHEVCMOVWithALACAudio() async throws {
        try await assertBundledQuickTimeVideoAACSampleEncodesHEVCMOV(
            outputAudioCodec: .alac,
            outputFileName: "quicktime-video-aac-hevc-alac.mov"
        )
    }

    internal func assertBundledQuickTimeVideoAACSampleEncodesHEVCMOV(
        outputAudioCodec: TaptionAudioCodec,
        outputFileName: String
    ) async throws {
        let sampleURL = bundledTestVideosURL().appendingPathComponent("QuickTime Video.mov")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled AAC proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: outputFileName)
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            audioCodec: outputAudioCodec,
            container: .mov
        )
        let job = try await core.prepareSingleAssetJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            outputPolicy: outputPolicy,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let sourceAudioCodec = try XCTUnwrap(job.asset.audioTracks.first?.codec)

        XCTAssertEqual(job.asset.container, .mov)
        XCTAssertEqual(job.asset.videoTrack?.codec, .quickTimeVideo)
        XCTAssertEqual(sourceAudioCodec, .aac)
        XCTAssertEqual(job.asset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(job.asset.audioTracks.first?.channelCount, 2)
        XCTAssertEqual(job.plan.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(job.plan.outputPolicy.audioCodec, outputAudioCodec)
        XCTAssertEqual(job.plan.outputPolicy.container, .mov)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .quickTimeVideo, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: outputAudioCodec))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.support, .nativeTranscode)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.encodeBackend, .appleAVAssetExport)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .nativeTranscodeInCurrentBuild)
        XCTAssertNil(job.plan.audioPlan?.readiness.commandBackend)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
        XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 48_000)
        XCTAssertEqual(job.plan.audioPlan?.options.channelCount, 2)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mov)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, outputAudioCodec)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 2)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testBundledAMRWBH263SampleEncodesHEVCMOVWithPCMAudio() async throws {
        try await assertBundledAMRWBH263SampleEncodesHEVCMOV(
            outputAudioCodec: .pcm,
            outputFileName: "amr-wb-h263-hevc-pcm.mov"
        )
    }

    func testBundledAMRWBH263SampleEncodesHEVCMOVWithALACAudio() async throws {
        try await assertBundledAMRWBH263SampleEncodesHEVCMOV(
            outputAudioCodec: .alac,
            outputFileName: "amr-wb-h263-hevc-alac.mov"
        )
    }

    internal func assertBundledAMRWBH263SampleEncodesHEVCMOV(
        outputAudioCodec: TaptionAudioCodec,
        outputFileName: String
    ) async throws {
        let sampleURL = bundledTestVideosURL().appendingPathComponent("AMR-WB H.263.3gp")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled AMR-WB proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: outputFileName)
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            audioCodec: outputAudioCodec,
            container: .mov
        )
        let job = try await core.prepareSingleAssetJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            outputPolicy: outputPolicy,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let sourceAudioCodec = try XCTUnwrap(job.asset.audioTracks.first?.codec)

        XCTAssertEqual(job.asset.container, .threeGP)
        XCTAssertEqual(job.asset.videoTrack?.codec, .h263)
        XCTAssertEqual(sourceAudioCodec, .amr)
        XCTAssertEqual(job.asset.audioTracks.first?.sampleRate ?? 0, 16_000, accuracy: 1)
        XCTAssertEqual(job.asset.audioTracks.first?.channelCount, 1)
        XCTAssertEqual(job.plan.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(job.plan.outputPolicy.audioCodec, outputAudioCodec)
        XCTAssertEqual(job.plan.outputPolicy.container, .mov)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .h263, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .amr, outputCodec: outputAudioCodec))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.encodeBackend, .appleAVAssetExport)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertEqual(job.plan.audioPlan?.readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
        XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 48_000)
        XCTAssertEqual(job.plan.audioPlan?.options.channelCount, 1)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mov)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, outputAudioCodec)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 1)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testLocalRealVP8WebMSampleCanEncodeHEVCWithAACAudio() async throws {
        try requireLocalRealSampleProofs()

        let sampleURL = URL(fileURLWithPath: "/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/real_samples/Demo_Video_Tutorial_8s.webm")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local real-sample proof requires Demo_Video_Tutorial_8s.webm.")
        }

        let outputURL = temporaryTestURL(fileName: "Demo_Video_Tutorial_8s_actual_app_hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let job = try await core.prepareSingleAssetHEVCJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mp4)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testLocalRealVC1RawSampleUsesBundledFFmpegDecodeBridgeRoute() async throws {
        try requireLocalRealSampleProofs()

        let samplePath = ProcessInfo.processInfo.environment["TAPTION_VC1_SAMPLE_PATH"]
            ?? "/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/vc1_advanced_profile_2.vc1"
        let sampleURL = URL(fileURLWithPath: samplePath)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local VC-1 real-sample proof requires \(sampleURL.path).")
        }

        let outputURL = temporaryTestURL(fileName: "vc1-raw-actual-app-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let job = try await core.prepareSingleAssetJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )

        XCTAssertEqual(job.asset.container, .rawElementaryStream)
        XCTAssertEqual(job.asset.videoTrack?.codec, .vc1)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .vc1, outputCodec: .hevc))
        XCTAssertEqual(job.routeSelection.support, .implemented)
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertNotEqual(job.routeSelection.executionKind, .planned)
        XCTAssertEqual(job.routeSelection.decodeBackend, .ffmpegFamily)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path) == false)

        XCTAssertTrue(TaptionCodecTranscodingRegistry.live.plannedDescriptors(for: job.routeSelection.route).isEmpty)
        XCTAssertTrue(
            TaptionCodecTranscodingRegistry.live.descriptors(for: job.routeSelection.route)
                .contains { $0.backend == .ffmpegFamily && $0.mode == .software }
        )
    }

    func testLocalRealVC1WrappedPCMSamplePreservesAudioInMP4AndMOV() async throws {
        let bundledSamplePath = Bundle(for: type(of: self))
            .url(forResource: "vc1-pcm", withExtension: "avi")?
            .path
        let samplePath = ProcessInfo.processInfo.environment["TAPTION_VC1_AUDIO_SAMPLE_PATH"]
            ?? bundledSamplePath
            ?? "/tmp/taption-audio-review/vc1-pcm.avi"
        let sampleURL = URL(fileURLWithPath: samplePath)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local VC-1/PCM sample proof requires \(sampleURL.path).")
        }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )

        for container in [TaptionVideoContainer.mp4, .mov] {
            let outputURL = temporaryTestURL(
                fileName: "vc1-pcm-actual-app-hevc.\(container.defaultFileExtension)"
            )
            try? FileManager.default.removeItem(at: outputURL)
            defer { try? FileManager.default.removeItem(at: outputURL) }

            let job = try await core.prepareSingleAssetJob(
                sourceURL: sampleURL,
                temporaryOutputURL: outputURL,
                outputPolicy: TaptionVideoOutputPolicy(
                    videoCodec: .hevc,
                    audioCodec: .aac,
                    container: container
                ),
                savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
            )

            XCTAssertEqual(job.asset.container, .avi, container.rawValue)
            XCTAssertEqual(job.asset.videoTrack?.codec, .vc1, container.rawValue)
            XCTAssertEqual(job.asset.audioTracks.first?.codec, .pcm, container.rawValue)
            XCTAssertEqual(job.routeSelection.decodeBackend, .ffmpegFamily, container.rawValue)
            XCTAssertEqual(
                job.plan.audioPlan?.route,
                TaptionAudioCodecRoute(sourceCodec: .pcm, outputCodec: .aac),
                container.rawValue
            )

            let result = try await core.encodePreparedJob(job, progress: { _ in })
            let outputAsset = try await AVFoundationMediaInspector().inspectVideo(
                at: result.temporaryOutputURL
            )

            XCTAssertEqual(result.usedBackend, .ffmpegFamily, container.rawValue)
            XCTAssertEqual(outputAsset.container, container, container.rawValue)
            XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc, container.rawValue)
            XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac, container.rawValue)
            XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
            XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 1, container.rawValue)
            try await assertDecodedVideoSignalPresent(at: result.temporaryOutputURL)
            try await assertDecodedAudioSignalPresent(at: result.temporaryOutputURL)
        }
    }

    func testLocalRealQuickTimeRPZASampleEncodesWithLegacyFrameHoldDuration() async throws {
        try requireLocalRealSampleProofs()

        let samplePath = ProcessInfo.processInfo.environment["TAPTION_RPZA_SAMPLE_PATH"]
            ?? "/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/rpza_1701-D.mov"
        let sampleURL = URL(fileURLWithPath: samplePath)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local QuickTime RPZA real-sample proof requires \(sampleURL.path).")
        }

        let outputURL = temporaryTestURL(fileName: "rpza-actual-app-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let job = try await core.prepareSingleAssetHEVCJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        XCTAssertEqual(job.asset.container, .mov)
        XCTAssertEqual(job.asset.videoTrack?.codec, .quickTimeVideo)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .quickTimeVideo, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mp4)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.duration ?? 0, job.asset.duration ?? 0, accuracy: 0.55)
    }

    func testLocalRealY41PSampleUsesBundledFFmpegDecodeBridgeRoute() async throws {
        try requireLocalRealSampleProofs()

        let samplePath = ProcessInfo.processInfo.environment["TAPTION_Y41P_SAMPLE_PATH"]
            ?? "/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/y41p_from_internet_image.avi"
        let sampleURL = URL(fileURLWithPath: samplePath)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local Y41P real-sample proof requires \(sampleURL.path).")
        }

        let outputURL = temporaryTestURL(fileName: "y41p-actual-app-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let job = try await core.prepareSingleAssetJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        XCTAssertEqual(job.asset.container, .avi)
        XCTAssertEqual(job.asset.videoTrack?.codec, .y41p)
        XCTAssertEqual(job.asset.audioTracks.first?.codec, .pcm)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .y41p, outputCodec: .hevc))
        XCTAssertEqual(job.routeSelection.support, .implemented)
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertNotEqual(job.routeSelection.executionKind, .planned)
        XCTAssertEqual(job.routeSelection.decodeBackend, .ffmpegFamily)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path) == false)

        XCTAssertTrue(TaptionCodecTranscodingRegistry.live.plannedDescriptors(for: job.routeSelection.route).isEmpty)
        XCTAssertTrue(
            TaptionCodecTranscodingRegistry.live.descriptors(for: job.routeSelection.route)
                .contains { $0.backend == .ffmpegFamily && $0.mode == .software }
        )
    }

    func testLocalRealAMRNBH263SampleEncodesHEVCWithAACAudio() async throws {
        try requireLocalRealSampleProofs()

        let samplePath = ProcessInfo.processInfo.environment["TAPTION_AMR_NB_SAMPLE_PATH"]
            ?? "/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/amr_nb_h263_video.3gp"
        let sampleURL = URL(fileURLWithPath: samplePath)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local AMR-NB real-sample proof requires \(sampleURL.path).")
        }

        let outputURL = temporaryTestURL(fileName: "amr-nb-h263-actual-app-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let job = try await core.prepareSingleAssetHEVCJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        XCTAssertEqual(job.asset.container, .threeGP)
        XCTAssertEqual(job.asset.videoTrack?.codec, .h263)
        XCTAssertEqual(job.asset.audioTracks.first?.codec, .amr)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .h263, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .amr, outputCodec: .aac))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertEqual(job.plan.audioPlan?.readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
        XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 48_000)
        XCTAssertEqual(job.plan.sourcePreservationRequirements?.audioSampleRate, 48_000)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mp4)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testLocalRealAMRWBH263SampleEncodesHEVCWithAACAudio() async throws {
        try requireLocalRealSampleProofs()

        let samplePath = ProcessInfo.processInfo.environment["TAPTION_AMR_WB_SAMPLE_PATH"]
            ?? "/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-07/sample_videos/amr_wb_h263_video.3gp"
        let sampleURL = URL(fileURLWithPath: samplePath)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local AMR-WB real-sample proof requires \(sampleURL.path).")
        }

        let outputURL = temporaryTestURL(fileName: "amr-wb-h263-current-app-block.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let job = try await core.prepareSingleAssetHEVCJob(
            sourceURL: sampleURL,
            temporaryOutputURL: outputURL,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let sourceAudioCodec = try XCTUnwrap(job.asset.audioTracks.first?.codec)

        XCTAssertEqual(job.asset.container, .threeGP)
        XCTAssertEqual(job.asset.videoTrack?.codec, .h263)
        XCTAssertEqual(sourceAudioCodec, .amr)
        XCTAssertEqual(job.asset.audioTracks.first?.sampleRate ?? 0, 16_000, accuracy: 1)
        XCTAssertEqual(job.asset.audioTracks.first?.channelCount, 1)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .h263, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .amr, outputCodec: .aac))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertEqual(job.plan.audioPlan?.readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
        XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 48_000)
        XCTAssertEqual(job.plan.audioPlan?.options.channelCount, 1)
        XCTAssertEqual(job.plan.sourcePreservationRequirements?.audioSampleRate, 48_000)
        XCTAssertEqual(job.plan.sourcePreservationRequirements?.audioChannelCount, 1)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mp4)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 1)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testLocalRealXHEAACSampleEncodesHEVCWithNativeAACAudio() async throws {
        let bundledSamplePath = Bundle(for: type(of: self))
            .url(forResource: "xhe-aac-hevc-video", withExtension: "mp4")?
            .path
        let samplePath = ProcessInfo.processInfo.environment["TAPTION_XHE_AAC_SAMPLE_PATH"]
            ?? bundledSamplePath
            ?? "/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/xhe_aac_hevc_video.mp4"
        let sampleURL = URL(fileURLWithPath: samplePath)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local xHE-AAC real-sample proof requires \(sampleURL.path).")
        }

        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: AVFoundationMediaInspector(),
                encoder: AVFoundationHEVCEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )

        for container in [TaptionVideoContainer.mp4, .mov] {
            let outputURL = temporaryTestURL(
                fileName: "xhe-aac-hevc-actual-app-hevc.\(container.defaultFileExtension)"
            )
            try? FileManager.default.removeItem(at: outputURL)
            defer { try? FileManager.default.removeItem(at: outputURL) }

            let job = try await core.prepareSingleAssetJob(
                sourceURL: sampleURL,
                temporaryOutputURL: outputURL,
                outputPolicy: TaptionVideoOutputPolicy(
                    videoCodec: .hevc,
                    audioCodec: .aac,
                    container: container
                ),
                savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
            )
            XCTAssertEqual(job.asset.container, .mp4, container.rawValue)
            XCTAssertEqual(job.asset.videoTrack?.codec, .hevc, container.rawValue)
            XCTAssertEqual(job.asset.audioTracks.first?.codec, .xheAAC, container.rawValue)
            XCTAssertEqual(job.asset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
            XCTAssertEqual(job.asset.audioTracks.first?.channelCount, 2, container.rawValue)
            XCTAssertEqual(
                job.routeSelection.route,
                TaptionCodecRoute(sourceCodec: .hevc, outputCodec: .hevc),
                container.rawValue
            )
            XCTAssertTrue(job.routeSelection.isEncodableNow, container.rawValue)
            XCTAssertEqual(
                job.plan.audioPlan?.route,
                TaptionAudioCodecRoute(sourceCodec: .xheAAC, outputCodec: .aac),
                container.rawValue
            )
            XCTAssertEqual(job.plan.audioPlan?.routeSelection.support, .nativeTranscode, container.rawValue)
            XCTAssertEqual(
                job.plan.audioPlan?.readiness.readiness,
                .nativeTranscodeInCurrentBuild,
                container.rawValue
            )
            XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false, container.rawValue)
            XCTAssertNil(job.plan.audioPlan?.commandPlan, container.rawValue)
            XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 44_100, container.rawValue)
            XCTAssertEqual(
                job.plan.sourcePreservationRequirements?.audioSampleRate,
                44_100,
                container.rawValue
            )

            let result = try await core.encodePreparedJob(job, progress: { _ in })
            let outputAsset = try await AVFoundationMediaInspector().inspectVideo(
                at: result.temporaryOutputURL
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
            XCTAssertEqual(result.usedBackend, .appleVideoToolbox, container.rawValue)
            XCTAssertEqual(result.usedMode, .hardware, container.rawValue)
            XCTAssertEqual(outputAsset.container, container, container.rawValue)
            XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc, container.rawValue)
            XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac, container.rawValue)
            XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
            XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 2, container.rawValue)
            try await assertDecodedAudioSignalPresent(
                at: result.temporaryOutputURL,
                minimumPeakAmplitude: 1
            )
        }
    }

    func testEncodePreparedJobCreatesPendingSaveStateWithoutSaveAdWhenSaveGateIsNone() async throws {
        let outputURL = temporaryTestURL(fileName: "encoded.mp4")
        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: FakeMediaInspector(),
                encoder: FakeEncoderService(),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate()
            )
        )
        let job = try await core.prepareSingleAssetHEVCJob(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            temporaryOutputURL: outputURL,
            savePolicy: TaptionSavePolicy(destination: .sourceFolder, saveGate: .none)
        )

        let result = try await core.encodePreparedJob(job, progress: { _ in })

        XCTAssertEqual(result.pendingSaveState?.temporaryOutputURL, outputURL)
        XCTAssertEqual(result.pendingSaveState?.saveDestination, .sourceFolder)
        XCTAssertEqual(result.pendingSaveState?.requiresRewardedAd, false)
    }

    func testCallerManagedBackgroundTaskStaysActiveUntilExplicitCompletion() async throws {
        let outputURL = temporaryTestURL(fileName: "caller-managed-background.mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let backgroundCoordinator = RecordingBackgroundEncodingCoordinator()
        let core = TaptionVideoCore(
            services: TaptionVideoCoreServices(
                inspector: FakeMediaInspector(),
                encoder: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                storageChecker: FakeStorageChecker(),
                pendingSaveStore: FakePendingSaveStore(),
                saveGateAuthorizer: FakeAdGate(),
                backgroundCoordinator: backgroundCoordinator
            )
        )
        let job = try await core.prepareSingleAssetHEVCJob(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            temporaryOutputURL: outputURL,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )

        let result = try await core.encodePreparedJob(
            job,
            backgroundTaskCompletionPolicy: .callerManaged,
            progress: { _ in }
        )
        let beganBeforeCompletion = await backgroundCoordinator.recordedBeginPlanIDs()
        let endedBeforeCompletion = await backgroundCoordinator.recordedEndPlanIDs()

        XCTAssertEqual(beganBeforeCompletion, [result.planID])
        XCTAssertTrue(endedBeforeCompletion.isEmpty)

        await core.completeBackgroundEncoding(planID: result.planID)

        let endedAfterCompletion = await backgroundCoordinator.recordedEndPlanIDs()
        XCTAssertEqual(endedAfterCompletion, [result.planID])
    }

    func testAudioCodecRoutesCoverEveryPlannedSourceToAAC() {
        for sourceCodec in TaptionAudioCodecRoutePlanner.universalAudioCodecs {
            let selection = TaptionAudioCodecRoutePlanner.selectRoute(
                sourceCodec: sourceCodec,
                outputCodec: .aac,
                outputContainer: .mp4
            )

            XCTAssertNotEqual(selection.support, .unsupported, sourceCodec.rawValue)
            XCTAssertTrue(selection.isSupportedNow, sourceCodec.rawValue)
        }
    }

    func testUniversalAudioCodecMatrixCoversEverySourceAndOutputPair() {
        let expectedRouteCount = TaptionAudioCodecRoutePlanner.universalAudioCodecs.count
            * TaptionAudioCodecRoutePlanner.universalAudioCodecs.count

        XCTAssertEqual(TaptionAudioCodecRoutePlanner.plannedUniversalRoutes.count, expectedRouteCount)

        for sourceCodec in TaptionAudioCodecRoutePlanner.universalAudioCodecs {
            for outputCodec in TaptionAudioCodecRoutePlanner.universalAudioCodecs {
                let selection = TaptionAudioCodecRoutePlanner.selectRoute(
                    sourceCodec: sourceCodec,
                    outputCodec: outputCodec,
                    outputContainer: .mp4
                )
                XCTAssertNotEqual(
                    selection.support,
                    .unsupported,
                    "\(sourceCodec.rawValue) -> \(outputCodec.rawValue)"
                )
            }
        }
    }

    func testUniversalAudioSoftwareAlgorithmCatalogCoversEveryPlannedRoute() {
        let descriptors = SW_UniversalAudioCodecTranscodeAlgorithm.plannedDescriptors
        let descriptorRoutes = Set(descriptors.map(\.route))

        XCTAssertEqual(descriptorRoutes, TaptionAudioCodecRoutePlanner.plannedUniversalRoutes)
        XCTAssertTrue(descriptors.allSatisfy { $0.mode == .software })
        XCTAssertTrue(descriptors.allSatisfy { $0.backend == .ffmpegFamily })
    }

    func testAudioDescriptorRegistrySeparatesHardwareSoftwareAndBlockedRoutes() {
        let registry = TaptionAudioCodecDescriptorRegistry.live
        let copyRoute = TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .aac)
        let nativeRoute = TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .pcm)
        let softwareRoute = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let blockedRoute = TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .xheAAC)

        XCTAssertTrue(registry.hardwareDescriptors.allSatisfy { $0.mode == .hardware })
        XCTAssertTrue(registry.hardwareDescriptors.allSatisfy { $0.backend == .appleAVAssetExport })
        XCTAssertTrue(registry.softwareDescriptors.allSatisfy { $0.mode == .software })
        XCTAssertTrue(registry.softwareDescriptors.allSatisfy { $0.backend == .ffmpegFamily })

        let copyDescriptor = registry.preferredDescriptor(for: copyRoute)
        XCTAssertEqual(copyDescriptor?.mode, .hardware)
        XCTAssertEqual(copyDescriptor?.backend, .appleAVAssetExport)
        XCTAssertEqual(copyDescriptor?.displayName, "AAC Copy")

        let nativeDescriptor = registry.preferredDescriptor(for: nativeRoute)
        XCTAssertEqual(nativeDescriptor?.mode, .hardware)
        XCTAssertEqual(nativeDescriptor?.backend, .appleAVAssetExport)
        XCTAssertTrue(nativeDescriptor?.displayName.contains("Apple Native") == true)

        let softwareDescriptor = registry.preferredDescriptor(for: softwareRoute)
        XCTAssertEqual(softwareDescriptor?.mode, .software)
        XCTAssertEqual(softwareDescriptor?.backend, .ffmpegFamily)

        XCTAssertNil(registry.preferredDescriptor(for: blockedRoute))
        XCTAssertTrue(registry.descriptors(for: copyRoute).contains { $0.mode == .hardware })
        XCTAssertTrue(registry.descriptors(for: copyRoute).contains { $0.mode == .software })
    }

    func testLoadedAudioPathInfoSummarizesFileCardAudioRoutes() {
        let noAudio = LoadedAudioPathInfo.make(
            firstAudioTrack: nil,
            trackCount: 0,
            outputContainer: .mp4
        )
        let copy = LoadedAudioPathInfo.make(
            firstAudioTrack: TaptionAudioTrackInfo(codec: .aac),
            trackCount: 1,
            outputContainer: .mp4
        )
        let native = LoadedAudioPathInfo.make(
            firstAudioTrack: TaptionAudioTrackInfo(codec: .xheAAC),
            trackCount: 1,
            outputContainer: .mp4
        )
        let software = LoadedAudioPathInfo.make(
            firstAudioTrack: TaptionAudioTrackInfo(codec: .opus),
            trackCount: 2,
            outputContainer: .mp4
        )
        let selectedSoftware = LoadedAudioPathInfo.make(
            firstAudioTrack: TaptionAudioTrackInfo(codec: .opus),
            trackCount: 1,
            outputCodec: .flac,
            outputContainer: .mp4
        )
        let unsupported = LoadedAudioPathInfo.make(
            firstAudioTrack: TaptionAudioTrackInfo(codec: .unknown),
            trackCount: 1,
            outputContainer: .mp4
        )

        XCTAssertEqual(noAudio.title, "No Audio")
        XCTAssertEqual(noAudio.outputSummary, "None")

        XCTAssertEqual(copy.title, "Audio Copy")
        XCTAssertEqual(copy.outputSummary, "AAC")
        XCTAssertTrue(copy.detail.contains("AAC to AAC"))

        XCTAssertEqual(native.title, "Audio HW")
        XCTAssertEqual(native.outputSummary, "AAC")
        XCTAssertTrue(native.detail.contains("xHE-AAC to AAC"))

        XCTAssertEqual(software.title, "Audio SW")
        XCTAssertEqual(software.outputSummary, "AAC")
        XCTAssertTrue(software.detail.contains("Opus to AAC"))
        XCTAssertTrue(software.detail.contains("first of 2 audio tracks"))

        XCTAssertEqual(selectedSoftware.title, "Audio SW")
        XCTAssertEqual(selectedSoftware.outputSummary, "FLAC")
        XCTAssertTrue(selectedSoftware.detail.contains("Opus to FLAC"))

        XCTAssertEqual(unsupported.title, "Audio Unsupported")
        XCTAssertEqual(unsupported.outputSummary, "AAC")
    }

    func testLoadedVideoPathInfoSummarizesCurrentAndBlockedRoutes() {
        let implemented = LoadedVideoPathInfo.make(
            sourceCodec: .av1,
            routeSelection: selectRoute(
                sourceCodec: .av1,
                outputCodec: .hevc,
                profile: .softwareOnly
            ),
            outputSelection: TaptionOutputSelection(videoCodec: .hevc, container: .mp4)
        )
        let bundledBridge = LoadedVideoPathInfo.make(
            sourceCodec: .vc1,
            routeSelection: selectRoute(
                sourceCodec: .vc1,
                outputCodec: .hevc,
                profile: .softwareOnly
            ),
            outputSelection: TaptionOutputSelection(videoCodec: .hevc, container: .mp4)
        )
        let unsupported = LoadedVideoPathInfo.make(
            sourceCodec: .h264,
            routeSelection: selectRoute(
                sourceCodec: .h264,
                outputCodec: .proResRaw,
                profile: .h264HEVCHardware
            ),
            outputSelection: TaptionOutputSelection(videoCodec: .proResRaw, container: .mkv)
        )

        XCTAssertEqual(implemented.title, "Path SW")
        XCTAssertEqual(implemented.outputSummary, "H.265 / HEVC")
        XCTAssertTrue(implemented.isRouteEncodable, "\(implemented)")
        XCTAssertTrue(implemented.detail.contains("software fallback"), implemented.detail)

        XCTAssertEqual(bundledBridge.title, "Path SW")
        XCTAssertEqual(bundledBridge.outputSummary, "H.265 / HEVC")
        XCTAssertTrue(bundledBridge.isRouteEncodable)
        XCTAssertTrue(bundledBridge.detail.contains("software fallback"))

        XCTAssertEqual(unsupported.title, "Path Unsupported")
        XCTAssertEqual(unsupported.outputSummary, "Apple ProRes RAW")
        XCTAssertFalse(unsupported.isRouteEncodable)
        XCTAssertTrue(unsupported.detail.contains("Apple ProRes RAW / MKV output is not in the current codec roadmap"))
    }

    func testLoadedVideoPathInfoMarksProResRawAppleNativeRouteReady() {
        let readyRoute = selectRoute(
            sourceCodec: .proResRaw,
            outputCodec: .hevc,
            profile: appleProfile("apple_a19pro_av1_decode_prores_raw")
        )
        let ready = LoadedVideoPathInfo.make(
            sourceCodec: .proResRaw,
            routeSelection: readyRoute,
            outputSelection: TaptionOutputSelection(videoCodec: .hevc, container: .mp4)
        )

        XCTAssertEqual(ready.title, "Path HW/SW")
        XCTAssertEqual(ready.outputSummary, "H.265 / HEVC")
        XCTAssertTrue(ready.isRouteEncodable)
        XCTAssertEqual(readyRoute.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(readyRoute.encodeBackend, .appleVideoToolbox)
        XCTAssertTrue(
            ready.detail.contains("Apple ProRes RAW to H.265 / HEVC"),
            ready.detail
        )
        XCTAssertTrue(ready.detail.contains("Hardware decode is available"))
        XCTAssertTrue(ready.detail.contains("hardware encoder"))
    }

    func testLoadedVideoPathInfoMarksAppleNativeHEVCHardwareRoutesReady() {
        for sourceCodec in TaptionCodecRegistry.appleNativeHEVCHardwareSourceCodecs {
            let routeSelection = selectRoute(
                sourceCodec: sourceCodec,
                outputCodec: .hevc,
                profile: appleProfile("apple_ipad_m3_m4_av1_prores")
            )
            let info = LoadedVideoPathInfo.make(
                sourceCodec: sourceCodec,
                routeSelection: routeSelection,
                outputSelection: TaptionOutputSelection(videoCodec: .hevc, container: .mp4)
            )

            XCTAssertEqual(routeSelection.support, .implemented, sourceCodec.rawValue)
            XCTAssertEqual(routeSelection.executionKind, .hardware, sourceCodec.rawValue)
            XCTAssertTrue(routeSelection.isEncodableNow, sourceCodec.rawValue)
            XCTAssertEqual(info.title, "Path HW", sourceCodec.rawValue)
            XCTAssertEqual(info.outputSummary, "H.265 / HEVC", sourceCodec.rawValue)
            XCTAssertTrue(info.isRouteEncodable, "\(sourceCodec.rawValue) should be ready in the home queue card.")
        }
    }

    func testLoadedVideoPathInfoKeepsAppleNativeHEVCRouteDisabledWithoutRequiredHardware() {
        let routeSelection = selectRoute(
            sourceCodec: .proRes,
            outputCodec: .hevc,
            profile: .h264HEVCHardware
        )
        let info = LoadedVideoPathInfo.make(
            sourceCodec: .proRes,
            routeSelection: routeSelection,
            outputSelection: TaptionOutputSelection(videoCodec: .hevc, container: .mp4)
        )

        XCTAssertEqual(routeSelection.support, .planned)
        XCTAssertEqual(routeSelection.executionKind, .planned)
        XCTAssertFalse(routeSelection.isEncodableNow)
        XCTAssertEqual(info.title, "Path Planned")
        XCTAssertFalse(info.isRouteEncodable)
        XCTAssertTrue(info.detail.contains("planned"), info.detail)
    }

    func testLoadedVideoInfoReadinessStatusTextDistinguishesPlannedStates() {
        var info = LoadedVideoInfo(
            fileName: "sample.mp4",
            inputSummary: "H.264 / MP4",
            resolution: "1920x1080",
            frameRate: "30 fps",
            duration: "00:01",
            audio: "AAC",
            fileSize: "1 MB",
            inputSupportTitle: "Input Supported",
            inputSupportDetail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV.",
            isInputSupportedNow: true,
            codecPathTitle: "Path SW Plan Ready",
            codecPathDetail: "Command plan only.",
            outputSummary: "H.265 / MP4",
            outputName: "sample_taption.mp4",
            isRouteEncodable: false
        )

        XCTAssertEqual(info.readinessStatusText, "Not supported yet")
        XCTAssertEqual(info.readinessDetailText, "Not supported yet. Command plan only.")

        info.codecPathTitle = "Path SW Blocked"
        XCTAssertEqual(info.readinessStatusText, "Not supported yet")

        info.codecPathTitle = "Path Unsupported"
        XCTAssertEqual(info.readinessStatusText, "Not supported yet")

        info.isInputSupportedNow = false
        info.inputSupportDetail = "Unknown input codec is not supported in the current launch build."
        XCTAssertEqual(
            info.readinessDetailText,
            "Not supported yet. Unknown input codec is not supported in the current launch build."
        )

        info.isRouteEncodable = true
        XCTAssertEqual(info.readinessStatusText, "Ready")
        XCTAssertEqual(info.readinessDetailText, "Ready to encode.")
    }

    func testUniversalAudioTranscodeRequestDefaultsPreserveSourceQuality() {
        let request = TaptionAudioCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac),
            options: .preservingSource(outputCodec: .flac, outputContainer: .mp4)
        )

        XCTAssertEqual(request.options.outputCodec, .flac)
        XCTAssertEqual(request.options.outputContainer, .mp4)
        XCTAssertTrue(request.options.preserveSourceQuality)
        XCTAssertTrue(request.options.preserveSampleRate)
        XCTAssertTrue(request.options.preserveChannelLayout)
        XCTAssertNil(request.options.targetBitrate)
        XCTAssertNil(request.options.sampleRate)
        XCTAssertNil(request.options.channelCount)
    }

    func testSourcePreservingAudioOptionsResolverFillsTrackDefaults() {
        let sourceTrack = TaptionAudioTrackInfo(
            codec: .opus,
            channelCount: 6,
            sampleRate: 48_000,
            estimatedBitrate: 512_000
        )
        let options = TaptionSourcePreservingAudioOptionsResolver.resolvedOptions(
            for: sourceTrack,
            requestedOptions: .preservingSource(outputCodec: .aac, outputContainer: .mp4)
        )

        XCTAssertEqual(options.sampleRate, 48_000)
        XCTAssertEqual(options.channelCount, 6)
        XCTAssertEqual(options.targetBitrate, 512_000)
    }

    func testSourcePreservingAudioOptionsResolverRaisesAMRSampleRateForCurrentAppleWriters() {
        let sourceTrack = TaptionAudioTrackInfo(
            codec: .amr,
            channelCount: 1,
            sampleRate: 8_000,
            estimatedBitrate: 12_200
        )
        let cases: [(TaptionAudioCodec, TaptionVideoContainer)] = [
            (.aac, .mp4),
            (.pcm, .mov),
            (.alac, .mov)
        ]

        for (outputCodec, outputContainer) in cases {
            let options = TaptionSourcePreservingAudioOptionsResolver.resolvedOptions(
                for: sourceTrack,
                requestedOptions: .preservingSource(outputCodec: outputCodec, outputContainer: outputContainer)
            )

            XCTAssertEqual(options.sampleRate, 48_000, outputCodec.displayName)
            XCTAssertEqual(options.channelCount, 1, outputCodec.displayName)
            XCTAssertEqual(options.targetBitrate, 12_200, outputCodec.displayName)
        }
    }

    func testSourcePreservingAudioOptionsResolverUsesAppleXHEAACWriterRateForAAC() {
        let sourceTrack = TaptionAudioTrackInfo(
            codec: .xheAAC,
            channelCount: 2,
            sampleRate: 48_000,
            estimatedBitrate: 24_000
        )
        let options = TaptionSourcePreservingAudioOptionsResolver.resolvedOptions(
            for: sourceTrack,
            requestedOptions: .preservingSource(outputCodec: .aac, outputContainer: .mp4)
        )

        XCTAssertEqual(options.sampleRate, 44_100)
        XCTAssertEqual(options.channelCount, 2)
        XCTAssertEqual(options.targetBitrate, 24_000)
    }

    func testSourcePreservingAudioOptionsResolverKeepsExplicitOverrides() {
        let sourceTrack = TaptionAudioTrackInfo(
            codec: .opus,
            channelCount: 6,
            sampleRate: 48_000,
            estimatedBitrate: 512_000
        )
        let explicitOptions = TaptionAudioCodecTranscodeOptions(
            outputCodec: .aac,
            outputContainer: .mp4,
            preserveSourceQuality: true,
            preserveSampleRate: true,
            preserveChannelLayout: true,
            targetBitrate: 192_000,
            sampleRate: 44_100,
            channelCount: 2
        )
        let options = TaptionSourcePreservingAudioOptionsResolver.resolvedOptions(
            for: sourceTrack,
            requestedOptions: explicitOptions
        )

        XCTAssertEqual(options, explicitOptions)
    }

    func testAudioFormatDescriptionParserExtractsCodecSampleRateAndChannels() throws {
        let description = try makeAudioDescription(
            formatID: kAudioFormatMPEG4AAC,
            sampleRate: 48_000,
            channelCount: 6,
            framesPerPacket: 1024
        )

        let info = TaptionAudioFormatDescriptionParser.trackInfo(
            from: [description],
            estimatedBitrate: 512_000
        )

        XCTAssertEqual(info.codec, .aac)
        XCTAssertEqual(info.sampleRate, 48_000)
        XCTAssertEqual(info.channelCount, 6)
        XCTAssertEqual(info.estimatedBitrate, 512_000)
    }

    func testAudioFormatDescriptionParserRecognizesUSACAsXHEAAC() throws {
        let description = try makeAudioDescription(
            formatID: kAudioFormatMPEGD_USAC,
            sampleRate: 48_000,
            channelCount: 2,
            framesPerPacket: 2048
        )

        let info = TaptionAudioFormatDescriptionParser.trackInfo(
            from: [description],
            estimatedBitrate: 24_000
        )

        XCTAssertEqual(info.codec, .xheAAC)
        XCTAssertEqual(info.sampleRate, 48_000)
        XCTAssertEqual(info.channelCount, 2)
        XCTAssertEqual(info.estimatedBitrate, 24_000)
    }

    func testAudioFormatDescriptionParserHandlesLinearPCM() throws {
        let description = try makeAudioDescription(
            formatID: kAudioFormatLinearPCM,
            sampleRate: 44_100,
            channelCount: 2,
            formatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            bytesPerPacket: 4,
            framesPerPacket: 1,
            bytesPerFrame: 4,
            bitsPerChannel: 16
        )

        let info = TaptionAudioFormatDescriptionParser.trackInfo(
            from: [description],
            estimatedBitrate: nil
        )

        XCTAssertEqual(info.codec, .pcm)
        XCTAssertEqual(info.sampleRate, 44_100)
        XCTAssertEqual(info.channelCount, 2)
        XCTAssertNil(info.estimatedBitrate)
    }

    func testAudioFormatDescriptionParserKeepsMissingDescriptionUnknown() {
        let info = TaptionAudioFormatDescriptionParser.trackInfo(
            from: [],
            estimatedBitrate: nil
        )

        XCTAssertEqual(info.codec, .unknown)
        XCTAssertNil(info.sampleRate)
        XCTAssertNil(info.channelCount)
        XCTAssertNil(info.estimatedBitrate)
    }

    func testUniversalAudioSoftwareAlgorithmReportsBundledBackendMissingUntilImplementationLands() async {
        let route = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let request = TaptionAudioCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.webm"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: route,
            options: .preservingSource(outputCodec: .flac, outputContainer: .mp4)
        )

        do {
            _ = try await SW_UniversalAudioCodecTranscodeAlgorithm.transcode(
                request: request,
                progress: { _ in }
            )
            XCTFail("Universal software audio transcode should stay unavailable until the broad backend is bundled.")
        } catch let error as TaptionUniversalAudioCodecError {
            XCTAssertEqual(error, .backendNotBundled(.ffmpegFamily, route))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFFmpegAudioCodecTranscodeExecutorBlocksUntilReadinessGatesClose() async throws {
        let route = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let request = TaptionAudioCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.webm"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: route,
            options: .preservingSource(outputCodec: .flac, outputContainer: .mp4)
        )
        let audioExecutor = SW_FFmpegAudioCodecTranscodeExecutor(
            executor: SW_FFmpegCommandExecutor(
                readinessReport: SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(),
                runner: FakeFFmpegCommandRunner { _ in
                    XCTFail("Runner should not execute while broad software backend gates are open.")
                    return SW_FFmpegCommandRunResult(exitCode: 0)
                }
            )
        )

        do {
            _ = try await audioExecutor.transcode(request: request, progress: { _ in })
            XCTFail("Audio executor should block until the broad software backend is executable.")
        } catch let error as SW_FFmpegCommandExecutionError {
            guard case .backendNotExecutable(let openGates) = error else {
                XCTFail("Unexpected execution error: \(error)")
                return
            }
            XCTAssertEqual(Set(openGates), Set(TaptionSoftwareCodecBackendReadinessGate.allCases))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFFmpegAudioCodecTranscodeExecutorRunsThroughInjectedRunnerWhenReady() async throws {
        let outputURL = temporaryTestURL(fileName: "opus-to-flac.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let route = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let request = TaptionAudioCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.webm"),
            outputURL: outputURL,
            route: route,
            options: .preservingSource(outputCodec: .flac, outputContainer: .mp4)
        )
        let audioExecutor = SW_FFmpegAudioCodecTranscodeExecutor(
            executor: SW_FFmpegCommandExecutor(
                readinessReport: readyBroadSoftwareBackendReport(),
                runner: FakeFFmpegCommandRunner { commandPlan in
                    XCTAssertEqual(commandPlan.routeSummary, route.displayName)
                    XCTAssertTrue(commandPlan.arguments.contains("flac"))
                    try FileManager.default.createDirectory(
                        at: commandPlan.outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data("fake audio output".utf8).write(to: commandPlan.outputURL)
                    return SW_FFmpegCommandRunResult(exitCode: 0, stdout: "audio encoded", stderr: "size=1kB")
                }
            )
        )
        var progressStages: [TaptionEncodingStage] = []

        let output = try await audioExecutor.transcode(request: request) { progress in
            progressStages.append(progress.stage)
        }

        XCTAssertEqual(output.outputURL, outputURL)
        XCTAssertEqual(output.route, route)
        XCTAssertEqual(output.usedMode, .software)
        XCTAssertEqual(output.usedBackend, .ffmpegFamily)
        XCTAssertEqual(output.outputAudioCodec, .flac)
        XCTAssertEqual(output.outputContainer, .mp4)
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testUniversalAudioCommandPlanBuildsTranscodeAndCopyRoutes() throws {
        let opusToFLAC = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let opusPlan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(
            request: TaptionAudioCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/opus.webm"),
                outputURL: URL(fileURLWithPath: "/tmp/flac.mp4"),
                route: opusToFLAC,
                options: .preservingSource(outputCodec: .flac, outputContainer: .mp4)
            )
        )
        let aacRoute = TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .aac)
        let aacPlan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(
            request: TaptionAudioCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/aac.mp4"),
                outputURL: URL(fileURLWithPath: "/tmp/aac-copy.mp4"),
                route: aacRoute,
                options: .preservingSource(outputCodec: .aac, outputContainer: .mp4)
            )
        )

        XCTAssertEqual(opusPlan.routeSummary, opusToFLAC.displayName)
        XCTAssertTrue(opusPlan.arguments.contains("flac"))
        XCTAssertTrue(opusPlan.arguments.contains("/tmp/flac.mp4"))

        XCTAssertEqual(aacPlan.routeSummary, aacRoute.displayName)
        XCTAssertTrue(aacPlan.arguments.contains("copy"))
        XCTAssertTrue(aacPlan.notes.contains("Audio can be copied without transcoding."))
    }

    func testUniversalAudioCommandPlanAppliesSourcePreservingAudioOptions() throws {
        let route = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .aac)
        let sourceTrack = TaptionAudioTrackInfo(
            codec: .opus,
            channelCount: 6,
            sampleRate: 48_000,
            estimatedBitrate: 512_000
        )
        let options = TaptionSourcePreservingAudioOptionsResolver.resolvedOptions(
            for: sourceTrack,
            requestedOptions: .preservingSource(outputCodec: .aac, outputContainer: .mp4)
        )

        let plan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(
            request: TaptionAudioCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/opus.webm"),
                outputURL: URL(fileURLWithPath: "/tmp/aac.mp4"),
                route: route,
                options: options
            )
        )

        XCTAssertTrue(plan.arguments.contains("aac"))
        XCTAssertTrue(plan.arguments.contains("-ar"))
        XCTAssertTrue(plan.arguments.contains("48000"))
        XCTAssertTrue(plan.arguments.contains("-ac"))
        XCTAssertTrue(plan.arguments.contains("6"))
        XCTAssertTrue(plan.arguments.contains("-b:a"))
        XCTAssertTrue(plan.arguments.contains("512000"))
    }

}
