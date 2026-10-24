//
//  CodecRoutePlannerTests+SingleAndOutput.swift
//  Tests 4005-5949 of the original CodecRoutePlannerTests.swift, moved here
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
    func testPerformanceOutputPolicyRaisesBitrateAndCarriesProfile() {
        let asset = makeAsset(
            sourceCodec: .h264,
            displaySize: TaptionPixelSize(width: 1920, height: 1080),
            frameRate: TaptionRationalFrameRate(numerator: 30)
        )
        let balancedPolicy = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            optimizationProfile: .balanced
        ).outputPolicy(for: asset)
        let performancePolicy = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            optimizationProfile: .performance
        ).outputPolicy(for: asset)

        XCTAssertEqual(performancePolicy.advancedOptions.optimizationProfile, .performance)
        XCTAssertNil(performancePolicy.advancedOptions.resizeTo)
        XCTAssertNil(performancePolicy.advancedOptions.frameRate)
        XCTAssertGreaterThan(
            performancePolicy.advancedOptions.targetBitrate ?? 0,
            balancedPolicy.advancedOptions.targetBitrate ?? Int.max
        )
        XCTAssertLessThan(
            TaptionEncodingOptimizationProfile.performance.resourceSampleIntervalNanoseconds,
            TaptionEncodingOptimizationProfile.balanced.resourceSampleIntervalNanoseconds
        )
        XCTAssertLessThan(
            TaptionEncodingOptimizationProfile.performance.softwareDecodePollingIntervalNanoseconds,
            TaptionEncodingOptimizationProfile.balanced.softwareDecodePollingIntervalNanoseconds
        )
        XCTAssertEqual(
            TaptionEncodingOptimizationProfile.batterySaver.softwareDecodePollingIntervalNanoseconds,
            50_000_000
        )
        XCTAssertEqual(
            TaptionEncodingOptimizationProfile.performance.softwareDecodePollingIntervalNanoseconds,
            10_000_000
        )
        XCTAssertEqual(TaptionEncodingOptimizationProfile.batterySaver.softwareFramePipelineDepth, 1)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.balanced.softwareFramePipelineDepth, 3)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.performance.softwareFramePipelineDepth, 6)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.batterySaver.softwareAudioPipelineDepth, 8)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.balanced.softwareAudioPipelineDepth, 8)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.performance.softwareAudioPipelineDepth, 12)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.batterySaver.softwareVideoOnlyDecoderPlaybackRate, 1)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.balanced.softwareVideoOnlyDecoderPlaybackRate, 2)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.performance.softwareVideoOnlyDecoderPlaybackRate, 4)
        XCTAssertLessThan(
            TaptionEncodingOptimizationProfile.performance.writerBackpressureSleepMicroseconds,
            TaptionEncodingOptimizationProfile.balanced.writerBackpressureSleepMicroseconds
        )
    }

    func testHEVCWriterPerformanceHintOnlyAppliesToMaxPerformance() {
        for profile in [
            TaptionEncodingOptimizationProfile.batterySaver,
            .balanced,
            .performance
        ] {
            var compressionProperties: [String: Any] = [:]
            TaptionHEVCWriterPerformanceHints.apply(
                to: &compressionProperties,
                optimizationProfile: profile
            )
            let speedHint = compressionProperties[
                TaptionHEVCWriterPerformanceHints.prioritizeEncodingSpeedKey
            ] as? Bool
            let realTime = compressionProperties[
                TaptionHEVCWriterPerformanceHints.realTimeKey
            ] as? Bool
            let maximizePowerEfficiency = compressionProperties[
                TaptionHEVCWriterPerformanceHints.maximizePowerEfficiencyKey
            ] as? Bool
            XCTAssertEqual(realTime, profile == .performance ? false : nil, profile.rawValue)
            XCTAssertEqual(
                maximizePowerEfficiency,
                profile == .performance ? false : nil,
                profile.rawValue
            )
            #if targetEnvironment(simulator)
            XCTAssertNil(speedHint, profile.rawValue)
            #else
            XCTAssertEqual(speedHint, profile == .performance ? true : nil, profile.rawValue)
            #endif
        }

        var performanceProperties: [String: Any] = [:]
        TaptionHEVCWriterPerformanceHints.apply(
            to: &performanceProperties,
            optimizationProfile: .performance,
            sourceFrameCount: 240
        )
        XCTAssertEqual(
            performanceProperties[TaptionHEVCWriterPerformanceHints.sourceFrameCountKey] as? Int,
            240
        )
    }

    func testSoftwareDecoderPlaybackRateAcceleratesOnlyVideoOnlyOutputs() {
        XCTAssertEqual(
            SW_AV1HEVCTranscoder.requestedDecoderPlaybackRate(
                optimizationProfile: .batterySaver,
                hasAudioOutput: false
            ),
            1
        )
        XCTAssertEqual(
            SW_AV1HEVCTranscoder.requestedDecoderPlaybackRate(
                optimizationProfile: .balanced,
                hasAudioOutput: false
            ),
            2
        )
        XCTAssertEqual(
            SW_AV1HEVCTranscoder.requestedDecoderPlaybackRate(
                optimizationProfile: .performance,
                hasAudioOutput: false
            ),
            4
        )
        for profile in TaptionEncodingOptimizationProfile.allCases {
            XCTAssertEqual(
                SW_AV1HEVCTranscoder.requestedDecoderPlaybackRate(
                    optimizationProfile: profile,
                    hasAudioOutput: true
                ),
                1,
                profile.rawValue
            )
        }
    }

    func testLocalProResPerformanceSampleMeasuresBalancedAndMaxPerformance() async throws {
        let bundledURL = Bundle(for: CodecRoutePlannerTests.self).url(
            forResource: "Performance ProRes AAC",
            withExtension: "mov"
        )
        let sourceTreeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Performance ProRes AAC.mov")
        guard let sourceURL = bundledURL
                ?? (FileManager.default.fileExists(atPath: sourceTreeURL.path) ? sourceTreeURL : nil) else {
            throw XCTSkip("Local ProRes performance sample is not bundled in source-only checkouts.")
        }

        let sourceAsset = try await AVFoundationMediaInspector().inspectVideo(at: sourceURL)
        XCTAssertEqual(sourceAsset.videoTrack?.codec, .proRes)
        XCTAssertEqual(sourceAsset.audioTracks.first?.codec, .aac)
        let sourceDuration = try XCTUnwrap(sourceAsset.duration)

        var elapsedByProfile: [String: TimeInterval] = [:]
        for profile in [TaptionEncodingOptimizationProfile.balanced, .performance] {
            let outputURL = temporaryTestURL(
                fileName: "prores-aac-\(profile.rawValue)-hevc.mp4"
            )
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
                sourceURL: sourceURL,
                temporaryOutputURL: outputURL,
                outputPolicy: TaptionVideoOutputPolicy(
                    videoCodec: .hevc,
                    audioCodec: .aac,
                    container: .mp4,
                    advancedOptions: TaptionAdvancedOutputOptions(
                        optimizationProfile: profile
                    )
                ),
                savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
            )

            let startedAt = ProcessInfo.processInfo.systemUptime
            let result = try await core.encodePreparedJob(job, progress: { _ in })
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let outputAsset = try await AVFoundationMediaInspector().inspectVideo(
                at: result.temporaryOutputURL
            )

            XCTAssertEqual(result.usedBackend, .appleVideoToolbox, profile.rawValue)
            XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc, profile.rawValue)
            XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac, profile.rawValue)
            XCTAssertEqual(outputAsset.duration ?? 0, sourceDuration, accuracy: 0.35, profile.rawValue)
            try await assertDecodedVideoSignalPresent(at: result.temporaryOutputURL)
            try await assertDecodedAudioSignalPresent(at: result.temporaryOutputURL)
            elapsedByProfile[profile.rawValue] = elapsed
            print(
                "TAPTION_PRORES_PERF_RESULT profile=\(profile.rawValue) "
                    + "elapsed=\(String(format: "%.3f", elapsed)) "
                    + "sourceDuration=\(String(format: "%.3f", sourceDuration)) "
                    + "realtimeFactor=\(String(format: "%.3f", sourceDuration / max(elapsed, 0.001)))"
            )
        }

        let balancedElapsed = try XCTUnwrap(elapsedByProfile[TaptionEncodingOptimizationProfile.balanced.rawValue])
        let performanceElapsed = try XCTUnwrap(elapsedByProfile[TaptionEncodingOptimizationProfile.performance.rawValue])
        print(
            "TAPTION_PRORES_PERF_COMPARISON performanceToBalanced="
                + String(format: "%.3f", performanceElapsed / max(balancedElapsed, 0.001))
        )
    }

    func testCompressedVideoReaderWriterFastPathRequiresEligibleMaxPerformanceOutput() {
        var request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc),
            options: TaptionCodecTranscodeOptions(
                outputPolicy: TaptionVideoOutputPolicy(
                    videoCodec: .hevc,
                    audioCodec: .aac,
                    container: .mp4,
                    advancedOptions: TaptionAdvancedOutputOptions(
                        color: TaptionColorDescription(bitDepth: 8, isHDR: false),
                        optimizationProfile: .performance
                    )
                )
            )
        )

        XCTAssertTrue(HW_AppleHEVCCodecAlgorithm.requestsCompressedVideoReaderWriterFastPath(request))
        request.options.outputPolicy.container = .mov
        XCTAssertTrue(HW_AppleHEVCCodecAlgorithm.requestsCompressedVideoReaderWriterFastPath(request))

        request.options.outputPolicy.container = .mp4
        request.route.sourceCodec = .hevc
        XCTAssertTrue(HW_AppleHEVCCodecAlgorithm.requestsCompressedVideoReaderWriterFastPath(request))
        request.route.sourceCodec = .proRes
        XCTAssertTrue(HW_AppleHEVCCodecAlgorithm.requestsCompressedVideoReaderWriterFastPath(request))
        request.route.sourceCodec = .h264

        request.options.outputPolicy.advancedOptions.optimizationProfile = .balanced
        XCTAssertFalse(HW_AppleHEVCCodecAlgorithm.requestsCompressedVideoReaderWriterFastPath(request))
        request.options.outputPolicy.advancedOptions.optimizationProfile = .performance
        request.options.outputPolicy.advancedOptions.color = TaptionColorDescription(bitDepth: 10, isHDR: true)
        XCTAssertFalse(HW_AppleHEVCCodecAlgorithm.requestsCompressedVideoReaderWriterFastPath(request))
        request.options.outputPolicy.advancedOptions.color = TaptionColorDescription(bitDepth: 8, isHDR: false)
        request.options.outputPolicy.audioCodec = .alac
        XCTAssertFalse(HW_AppleHEVCCodecAlgorithm.requestsCompressedVideoReaderWriterFastPath(request))
        request.options.outputPolicy.audioCodec = .aac
        request.options.outputPolicy.profile = .main10
        XCTAssertFalse(HW_AppleHEVCCodecAlgorithm.requestsCompressedVideoReaderWriterFastPath(request))
    }

    func testOutputCatalogSeparatesImplementedCommandPlanReadyPlannedAndUnsupportedOutputs() {
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .hevc, container: .mp4),
            .implemented
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .h264, container: .mp4),
            .unsupported
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .hevc, container: .mov),
            .implemented
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .proResRaw, container: .mkv),
            .unsupported
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .hevc, container: .mkv),
            .unsupported
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .unknown, container: .mp4),
            .unsupported
        )
    }

    func testOutputSelectionDetailSummarizesImplementedCommandPlanAndPlannedStates() {
        let implemented = TaptionOutputSelection(
            videoCodec: .hevc,
            audioCodec: .aac,
            container: .mp4
        )
        let commandPlanReady = TaptionOutputSelection(
            videoCodec: .hevc,
            audioCodec: .flac,
            container: .mp4
        )
        let planned = TaptionOutputSelection(
            videoCodec: .hevc,
            audioCodec: .xheAAC,
            container: .mp4
        )
        let unsupported = TaptionOutputSelection(
            videoCodec: .hevc,
            audioCodec: .xheAAC,
            container: .mkv
        )

        XCTAssertEqual(implemented.statusTitle, "Output Ready")
        XCTAssertEqual(implemented.detailText, "This exact output selection can run in the current build.")

        XCTAssertEqual(commandPlanReady.statusTitle, "Output Plan Ready")
        XCTAssertTrue(commandPlanReady.detailText.contains("FLAC / MP4 audio output has a software command plan"))

        XCTAssertEqual(planned.statusTitle, "Output Planned")
        XCTAssertTrue(planned.detailText.contains("xHE-AAC / MP4 audio output is planned"))

        XCTAssertEqual(unsupported.statusTitle, "Output Unsupported")
        XCTAssertTrue(unsupported.detailText.contains("H.265 / MKV output is not in the current codec roadmap"))
        XCTAssertTrue(unsupported.detailText.contains("xHE-AAC / MKV audio output is not in the current codec roadmap"))
    }

    func testLoadedVideoInfoExposesCodecAndAudioPathBadges() {
        var info = LoadedVideoInfo(
            fileName: "sample.mp4",
            inputSummary: "AV1 / MP4",
            resolution: "1920x1080",
            frameRate: "30 fps",
            duration: "00:01",
            audio: "Opus",
            audioPathTitle: "Audio SW",
            audioPathDetail: "Software audio decode should feed an Apple-native output encoder.",
            audioOutputSummary: "AAC",
            fileSize: "1 MB",
            inputSupportTitle: "Input Supported",
            inputSupportDetail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV.",
            isInputSupportedNow: true,
            codecPathTitle: "Path HW/SW",
            codecPathDetail: "AV1 to H.265 / HEVC. Hardware encode is used with software decode fallback.",
            outputSummary: "H.265 + AAC / MP4",
            outputName: "sample_taption.mp4",
            isRouteEncodable: true
        )

        XCTAssertEqual(info.codecPathBadge, "HW/SW")
        XCTAssertEqual(info.audioPathBadge, "SW")

        info.codecPathTitle = "Path SW Plan Ready"
        info.audioPathTitle = "Audio Copy"
        XCTAssertEqual(info.codecPathBadge, "SW Plan")
        XCTAssertEqual(info.audioPathBadge, "Copy")

        info.codecPathTitle = "Path Unsupported"
        info.audioPathTitle = "No Audio"
        XCTAssertEqual(info.codecPathBadge, "Unsupported")
        XCTAssertEqual(info.audioPathBadge, "None")
    }

    func testLoadedVideoInfoExposesCurrentBuildSupportFlags() {
        let supportedInfo = LoadedVideoInfo(
            fileName: "supported.mp4",
            inputSummary: "AV1 / MP4",
            resolution: "1920x1080",
            frameRate: "30 fps",
            duration: "00:30",
            audio: "AAC",
            audioPathTitle: "Audio Copy",
            audioPathDetail: "Audio can be copied.",
            audioOutputSummary: "AAC",
            fileSize: "9 MB",
            inputSupportTitle: "Input Supported",
            inputSupportDetail: "Supported now.",
            isInputSupportedNow: true,
            codecPathTitle: "Path HW/SW",
            codecPathDetail: "Mixed route is available.",
            outputSummary: "HEVC + AAC / MP4",
            outputName: "supported_taption.mp4",
            isRouteEncodable: true
        )
        let unsupportedInfo = LoadedVideoInfo(
            fileName: "unsupported.avi",
            inputSummary: "Unknown / AVI",
            resolution: "1920x1080",
            frameRate: "30 fps",
            duration: "00:30",
            audio: "PCM",
            audioPathTitle: "Audio Unsupported",
            audioPathDetail: "Audio route is not available.",
            audioOutputSummary: "AAC",
            fileSize: "9 MB",
            inputSupportTitle: "Input Container Unsupported",
            inputSupportDetail: "AVI is not supported in the current launch build.",
            isInputSupportedNow: false,
            codecPathTitle: "Path Unsupported",
            codecPathDetail: "No current route is available.",
            outputSummary: "HEVC + AAC / MP4",
            outputName: "unsupported_taption.mp4",
            isRouteEncodable: false
        )

        XCTAssertTrue(supportedInfo.isInputSupportedForCurrentBuild)
        XCTAssertTrue(supportedInfo.isCodecPathSupportedForCurrentBuild)
        XCTAssertTrue(supportedInfo.isAudioPathSupportedForCurrentBuild)

        XCTAssertFalse(unsupportedInfo.isInputSupportedForCurrentBuild)
        XCTAssertFalse(unsupportedInfo.isCodecPathSupportedForCurrentBuild)
        XCTAssertFalse(unsupportedInfo.isAudioPathSupportedForCurrentBuild)
    }

    @MainActor
    func testOrientationControllerKeepsIPhonePortraitAndAllowsIPadLandscape() {
        let controller = AppOrientationController.shared
        let expectedHomeOrientations = AppOrientationController.homeOrientations(
            for: UIDevice.current.userInterfaceIdiom
        )

        controller.restorePortrait(requestGeometryUpdate: false)
        XCTAssertEqual(controller.supportedOrientations, expectedHomeOrientations)
        XCTAssertEqual(AppOrientationController.homeOrientations(for: .phone), .portrait)
        let padOrientations = AppOrientationController.homeOrientations(for: .pad)
        XCTAssertTrue(padOrientations.contains(.portrait))
        XCTAssertTrue(padOrientations.contains(.landscapeLeft))
        XCTAssertTrue(padOrientations.contains(.landscapeRight))

        controller.activatePreviewOrientations(requestGeometryUpdate: false)
        XCTAssertTrue(controller.supportedOrientations.contains(.portrait))
        XCTAssertTrue(controller.supportedOrientations.contains(.landscapeLeft))
        XCTAssertTrue(controller.supportedOrientations.contains(.landscapeRight))

        controller.restorePortrait(requestGeometryUpdate: false)
        XCTAssertEqual(controller.supportedOrientations, expectedHomeOrientations)
    }

    func testQueuePreviewPlaybackMathFormatsAndClampsControls() {
        XCTAssertEqual(QueuePreviewPlaybackMath.formattedSeconds(nil), "--:--")
        XCTAssertEqual(QueuePreviewPlaybackMath.formattedSeconds(65), "01:05")
        XCTAssertEqual(QueuePreviewPlaybackMath.formattedSeconds(3661), "1:01:01")

        XCTAssertEqual(QueuePreviewPlaybackMath.clampedPosition(-0.4), 0)
        XCTAssertEqual(QueuePreviewPlaybackMath.clampedPosition(1.4), 1)
        XCTAssertFalse(QueuePreviewPlaybackMath.hasUsableTimeline(durationSeconds: nil))
        XCTAssertFalse(QueuePreviewPlaybackMath.hasUsableTimeline(durationSeconds: 0))
        XCTAssertTrue(QueuePreviewPlaybackMath.hasUsableTimeline(durationSeconds: 5))
        XCTAssertEqual(
            QueuePreviewPlaybackMath.displayedSliderPosition(
                playerPosition: 1,
                isScrubbing: false,
                scrubberPosition: 0.6,
                dragSeekPreviewPosition: nil,
                durationSeconds: nil
            ),
            0
        )
        XCTAssertEqual(
            QueuePreviewPlaybackMath.displayedSliderPosition(
                playerPosition: 0.4,
                isScrubbing: false,
                scrubberPosition: 0.6,
                dragSeekPreviewPosition: nil,
                durationSeconds: 5
            ),
            0.4
        )
        XCTAssertEqual(
            QueuePreviewPlaybackMath.displayedSliderPosition(
                playerPosition: 0.4,
                isScrubbing: true,
                scrubberPosition: 0.6,
                dragSeekPreviewPosition: nil,
                durationSeconds: 5
            ),
            0.6
        )
        XCTAssertEqual(
            QueuePreviewPlaybackMath.horizontalDragPosition(
                startPosition: 0.5,
                translation: 100,
                containerWidth: 400
            ),
            0.75
        )
        XCTAssertEqual(
            QueuePreviewPlaybackMath.horizontalDragPosition(
                startPosition: 0.1,
                translation: -200,
                containerWidth: 400
            ),
            0
        )
        XCTAssertEqual(
            QueuePreviewPlaybackMath.verticalAdjustmentDelta(
                translation: -50,
                containerHeight: 200
            ),
            0.25,
            accuracy: 0.0001
        )
    }

    func testPreviewBottomBarSwipeNavigatesOneFileAndRespectsBoundaries() {
        let middle = QueueVideoPreviewPlaylist(currentIndex: 1, totalCount: 3,
            previousID: "first", previousName: "First.mp4", nextID: "last", nextName: "Last.mp4")
        XCTAssertEqual(QueuePreviewBarNavigation.destination(translation: CGSize(width: -100, height: 5), playlist: middle, isEnabled: true), .next)
        XCTAssertEqual(QueuePreviewBarNavigation.destination(translation: CGSize(width: 100, height: -5), playlist: middle, isEnabled: true), .previous)
        var first = middle
        first.currentIndex = 0
        first.previousID = nil
        XCTAssertNil(QueuePreviewBarNavigation.destination(translation: CGSize(width: 100, height: 0), playlist: first, isEnabled: true))
        var last = middle
        last.currentIndex = 2
        last.nextID = nil
        XCTAssertNil(QueuePreviewBarNavigation.destination(translation: CGSize(width: -100, height: 0), playlist: last, isEnabled: true))
        XCTAssertNil(QueuePreviewBarNavigation.destination(translation: CGSize(width: -100, height: 0), playlist: nil, isEnabled: true))
        XCTAssertNil(QueuePreviewBarNavigation.destination(translation: CGSize(width: -100, height: 0), playlist: middle, isEnabled: false))
    }

    func testPreviewBottomBarIgnoresTapJitterVerticalAndInvalidDrags() {
        let playlist = QueueVideoPreviewPlaylist(currentIndex: 1, totalCount: 3,
            previousID: "first", previousName: nil, nextID: "last", nextName: nil)
        for translation in [CGSize.zero, CGSize(width: 12, height: 0), CGSize(width: -43, height: 0),
                            CGSize(width: 44, height: 80), CGSize(width: -60, height: 55),
                            CGSize(width: CGFloat.nan, height: 0), CGSize(width: 100, height: CGFloat.infinity)] {
            XCTAssertNil(QueuePreviewBarNavigation.destination(translation: translation, playlist: playlist, isEnabled: true))
        }
    }

    func testSingleFileSwipeReportsMissingFolderAccessWithoutNavigation() {
        XCTAssertEqual(QueuePreviewBarNavigation.destination(translation: CGSize(width: -80, height: 4), playlist: nil, isEnabled: true, needsFolderAccess: true), .folderAccessRequired)
        XCTAssertEqual(QueuePreviewBarNavigation.destination(translation: CGSize(width: 80, height: 4), playlist: nil, isEnabled: true, needsFolderAccess: true), .folderAccessRequired)
        XCTAssertNil(QueuePreviewBarNavigation.destination(translation: CGSize(width: 10, height: 0), playlist: nil, isEnabled: true, needsFolderAccess: true))
        XCTAssertNil(QueuePreviewBarNavigation.destination(translation: CGSize(width: 80, height: 0), playlist: nil, isEnabled: false, needsFolderAccess: true))
    }

    func testQueuePreviewBackgroundTapHidesControlsWhenReadyAndIdle() {
        let cases: [(loading: Bool, error: Bool, visible: Bool, scrubbing: Bool, dragging: Bool, hides: Bool)] = [
            (false, false, true, false, false, true),
            (false, false, false, false, false, false),
            (true, false, true, false, false, false),
            (false, true, true, false, false, false),
            (false, false, true, true, false, false),
            (false, false, true, false, true, false)
        ]
        for scenario in cases {
            XCTAssertEqual(
                QueuePreviewControlsVisibilityPolicy.shouldHideOnBackgroundTap(
                    isLoading: scenario.loading,
                    hasPlaybackError: scenario.error,
                    areControlsVisible: scenario.visible,
                    isScrubbing: scenario.scrubbing,
                    isDragging: scenario.dragging
                ),
                scenario.hides
            )
        }
    }

    func testOutputSummaryKeepsCodecLabelsSmall() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let outputSummaryURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Encoding/OutputSummaryView.swift")
        let outputSummaryText = try String(contentsOf: outputSummaryURL, encoding: .utf8)
        let codecLineStart = try XCTUnwrap(outputSummaryText.range(of: "private func codecLine"))
        let codecLineText = String(outputSummaryText[codecLineStart.lowerBound...])

        XCTAssertTrue(codecLineText.contains(".font(.caption2.weight(.semibold))"))
        XCTAssertFalse(codecLineText.contains(".caption.weight(.semibold)"))
    }

    func testQueuePreviewPlayerUsesPictureInPictureSurfaceAndBannerOnlyAds() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let previewViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Preview/QueuePreviewViews.swift")
        let previewViewText = try String(contentsOf: previewViewURL, encoding: .utf8)
        let previewStart = try XCTUnwrap(
            previewViewText.range(of: "struct QueueVideoPreviewView: View")
        )
        let previewEnd = try XCTUnwrap(
            previewViewText.range(of: "struct QueueMiniPlayerView: View")
        )
        let previewText = String(previewViewText[previewStart.lowerBound..<previewEnd.lowerBound])

        XCTAssertTrue(previewText.contains("PiPVideoView("))
        XCTAssertTrue(previewText.contains("controller: $pipController"))
        XCTAssertTrue(previewText.contains("startsAutomaticallyFromInline: false"))
        XCTAssertTrue(previewText.contains("managesAudioSession: false"))
        XCTAssertFalse(previewText.contains("Button(action: togglePictureInPicture)"))
        XCTAssertTrue(previewText.contains("pipController.start()"))
        XCTAssertTrue(previewText.contains("Queue preview Picture in Picture requested on current player"))
        XCTAssertTrue(previewText.contains(".onChange(of: pipController?.isActive)"))
        XCTAssertTrue(previewText.contains("onPictureInPictureActiveChanged(isActive)"))
        XCTAssertFalse(previewText.contains("onPictureInPictureHome"))
        XCTAssertFalse(previewText.contains("Queue preview Picture in Picture home requested"))
        XCTAssertTrue(previewText.contains("startDebugAutoPictureInPictureIfRequested(operationID:"))
        XCTAssertTrue(previewText.contains("TAPTION_AUTO_START_PIP"))
        XCTAssertTrue(previewText.contains("nativeValidationProbe"))
        XCTAssertTrue(previewText.contains("TAPTION_PIP_PROBE_ID"))
        XCTAssertTrue(previewText.contains("beginVideoPlaybackAdSuppressionIfNeeded()"))
        XCTAssertTrue(previewText.contains("endVideoPlaybackAdSuppressionIfNeeded()"))
        XCTAssertTrue(previewViewText.contains("import MediaPlayer"))
        XCTAssertTrue(previewText.contains("@StateObject private var systemVolumeController = QueuePreviewSystemVolumeController()"))
        XCTAssertTrue(previewText.contains("QueuePreviewSystemVolumeBridgeView(controller: systemVolumeController)"))
        XCTAssertTrue(previewText.contains("return .volume(startValue: systemVolumeController.volume)"))
        XCTAssertTrue(previewText.contains("setPreviewOutputVolume(volume)"))
        XCTAssertTrue(previewViewText.contains("final class QueuePreviewSystemVolumeController"))
        XCTAssertTrue(previewViewText.contains("MPVolumeView"))
        XCTAssertTrue(previewViewText.contains("outputVolume"))
        XCTAssertTrue(previewViewText.contains("volumeSlider.sendActions(for: .valueChanged)"))
        XCTAssertTrue(previewText.contains("AdMobBannerSlotView("))
        XCTAssertFalse(previewText.localizedCaseInsensitiveContains("rewarded"))
        XCTAssertFalse(previewText.localizedCaseInsensitiveContains("interstitial"))
        XCTAssertFalse(previewText.localizedCaseInsensitiveContains("appOpen"))
    }

    func testProtectedAppFlowsSuppressFullScreenAdsUntilTheyClose() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let adProvidersURL = rootURL.appendingPathComponent("TaptionEncoder/Core/Ads/AdProviders.swift")
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let viewModelURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeViewModel.swift")
        let adProvidersText = try String(contentsOf: adProvidersURL, encoding: .utf8)
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
        let viewModelText = try String(contentsOf: viewModelURL, encoding: .utf8)

        XCTAssertTrue(adProvidersText.contains("activeVideoPlaybackSuppressionCount"))
        XCTAssertTrue(adProvidersText.contains("activeCriticalFlowSuppressionCount"))
        XCTAssertTrue(adProvidersText.contains("beginVideoPlaybackAdSuppression(reason:"))
        XCTAssertTrue(adProvidersText.contains("endVideoPlaybackAdSuppression(reason:"))
        XCTAssertTrue(adProvidersText.contains("beginFullScreenAdSuppression(reason:"))
        XCTAssertTrue(adProvidersText.contains("endFullScreenAdSuppression(reason:"))
        XCTAssertTrue(adProvidersText.contains("activeVideoPlaybackSuppressionCount + activeCriticalFlowSuppressionCount"))
        XCTAssertTrue(adProvidersText.contains("shouldSkipNonBannerAdRequest(placement: String, action: String)"))
        XCTAssertTrue(adProvidersText.contains("Non-banner ad request skipped during protected app flow"))
        XCTAssertTrue(adProvidersText.contains("placement: \"rewarded\", action: \"load\""))
        XCTAssertTrue(adProvidersText.contains("placement: \"interstitial\", action: \"load\""))
        XCTAssertTrue(adProvidersText.contains("placement: \"appOpen\", action: \"load\""))
        XCTAssertTrue(adProvidersText.contains("placement: \"allNonBanner\", action: \"preload\""))
        XCTAssertTrue(adProvidersText.contains("placement: \"allNonBanner\", action: \"refreshOnActive\""))
        XCTAssertTrue(adProvidersText.contains("placement: \"appOpen\", action: \"showAppOpen\""))
        XCTAssertTrue(adProvidersText.contains("App open ad skipped for external playback"))
        XCTAssertTrue(homeViewText.contains("beginDocumentPickerAdSuppressionIfNeeded(reason:"))
        XCTAssertTrue(homeViewText.contains("beginPhotosPickerAdSuppressionIfNeeded()"))
        XCTAssertTrue(viewModelText.contains("beginEncodingAdSuppressionIfNeeded()"))
        XCTAssertTrue(viewModelText.contains("endEncodingAdSuppressionIfNeeded()"))
    }

    func testQueuePreviewCanMinimizeIntoBannerOnlyFloatingPlayer() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let previewViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Preview/QueuePreviewViews.swift")
        let viewModelURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeViewModel.swift")
        let progressViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Encoding/EncodingProgressView.swift")
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
        let previewViewText = try String(contentsOf: previewViewURL, encoding: .utf8)
        let viewModelText = try String(contentsOf: viewModelURL, encoding: .utf8)
        let progressViewText = try String(contentsOf: progressViewURL, encoding: .utf8)

        XCTAssertTrue(homeViewText.contains("viewModel.miniPlayerPreview"))
        XCTAssertTrue(viewModelText.contains("@Published private(set) var miniPlayerPreview: QueueVideoPreview?"))
        XCTAssertTrue(homeViewText.contains("viewModel.minimizePreview(preview, snapshot: snapshot)"))
        XCTAssertTrue(homeViewText.contains("@State private var isPreviewPictureInPictureActive = false"))
        XCTAssertFalse(homeViewText.contains("autoStartMiniPlayerPiPPreviewID"))
        XCTAssertTrue(homeViewText.contains("QueueMiniPlayerView("))
        XCTAssertTrue(homeViewText.contains("queueVideoPreviewOverlay(preview: preview)"))
        XCTAssertTrue(homeViewText.contains("onMinimize:"))
        XCTAssertTrue(homeViewText.contains("onPictureInPictureActiveChanged:"))
        XCTAssertFalse(homeViewText.contains("onPictureInPictureHome:"))
        XCTAssertTrue(previewViewText.contains("minimizePreview()"))
        XCTAssertTrue(previewViewText.contains("Queue preview minimized to floating player"))
        XCTAssertTrue(previewViewText.contains("Queue preview Picture in Picture requested on current player"))
        XCTAssertFalse(previewViewText.contains("Queue preview Picture in Picture home requested"))
        XCTAssertFalse(previewViewText.contains("Image(systemName: \"arrow.down.right.and.arrow.up.left\")"))
        XCTAssertTrue(previewViewText.contains("TAPTION_AUTO_MINIMIZE_PREVIEW"))
        XCTAssertTrue(previewViewText.contains("Debug auto mini player requested"))
        XCTAssertTrue(previewViewText.contains("Button(action: expandPreview)"))
        XCTAssertTrue(previewViewText.contains("Button(action: togglePictureInPicture)"))
        XCTAssertTrue(previewViewText.contains("Queue mini player PiP requested"))
        XCTAssertTrue(previewViewText.contains("Queue mini player PiP exit requested"))
        XCTAssertTrue(previewViewText.contains("Queue mini player PiP ignored because controller is unavailable"))
        XCTAssertFalse(previewViewText.contains("Queue mini player auto PiP requested"))
        XCTAssertFalse(previewViewText.contains("Queue mini player auto PiP state checked"))
        XCTAssertFalse(previewViewText.contains("autoStartPictureInPicture"))
        XCTAssertFalse(previewViewText.contains("onAutoPictureInPictureHandled"))
        XCTAssertTrue(previewViewText.contains(".onChange(of: preview.id)"))
        XCTAssertTrue(previewViewText.contains("resetControlsForPreviewSwitch()"))
        XCTAssertFalse(homeViewText.contains(".id(preview.id)"))
        XCTAssertFalse(homeViewText.contains(".fullScreenCover("))
        XCTAssertTrue(homeViewText.contains(".zIndex(isPreviewPictureInPictureActive ? 30 : 0)"))
        XCTAssertTrue(homeViewText.contains("queueVideoPreviewOverlay(preview: preview)"))
        XCTAssertTrue(homeViewText.contains(".zIndex(20)"))
        XCTAssertTrue(homeViewText.contains("viewModel.restorePreview(preview, snapshot: snapshot)"))
        XCTAssertTrue(previewViewText.contains("queueMiniPlayer"))
        XCTAssertTrue(homeViewText.contains("viewModel.activePreview != nil && !isPreviewPictureInPictureActive"))
        XCTAssertTrue(homeViewText.contains("showsPlaybackActions: !isFullScreenVideoPlaybackActive"))
        XCTAssertTrue(homeViewText.contains("showsWorkAction: showsPlaybackActions"))
        XCTAssertTrue(homeViewText.contains("showsWatchAdAction: false"))
        XCTAssertTrue(previewViewText.contains("beginVideoPlaybackAdSuppressionIfNeeded()"))
        XCTAssertTrue(previewViewText.contains("endVideoPlaybackAdSuppressionIfNeeded()"))
        XCTAssertTrue(viewModelText.contains("func restorePreview(_ preview: QueueVideoPreview, snapshot:"))
        XCTAssertTrue(progressViewText.contains("var showsWorkAction: Bool = true"))
        XCTAssertTrue(progressViewText.contains("var showsWatchAdAction: Bool = true"))
        XCTAssertTrue(progressViewText.contains("showsWorkAction\n            && (!state.isBusy"))
        XCTAssertTrue(progressViewText.contains("if showsWatchAdAction {\n                        watchAdButton"))
    }

    @MainActor
    func testDocumentPickerHandoffAcceptsBothCallbackOrdersAndRejectsStaleResults() throws {
        let urls = [URL(fileURLWithPath: "/selected", isDirectory: true)]
        for dismissalFirst in [false, true] {
            let handoff = HomeDocumentPickerHandoff()
            handoff.begin(.folder)
            let id = try XCTUnwrap(handoff.requestID)
            if dismissalFirst { XCTAssertNil(handoff.didDismiss()) }
            let received = handoff.receive(.success(urls), requestID: id)
            if !dismissalFirst { XCTAssertNil(received) }
            let completed = try XCTUnwrap(dismissalFirst ? received : handoff.didDismiss())
            XCTAssertEqual(completed.0, .folder)
            XCTAssertEqual(try completed.1.get(), urls)
            XCTAssertNil(handoff.didDismiss())
            XCTAssertNil(handoff.receive(.success(urls), requestID: id))
            handoff.begin(.files)
            let nextID = try XCTUnwrap(handoff.requestID)
            XCTAssertNil(handoff.receive(.success(urls), requestID: id), "A dismissed picker cannot replace the new request")
            XCTAssertNil(handoff.receive(.success([]), requestID: nextID))
            let cancelled = try XCTUnwrap(handoff.didDismiss())
            XCTAssertEqual(cancelled.0, .files)
            XCTAssertTrue(try cancelled.1.get().isEmpty)
        }
    }

    @MainActor
    func testNativeDocumentPickerUsesVideosForFilesAndDirectoriesForFolders() throws {
        let location = try XCTUnwrap(VideoDocumentPicker.localDocumentsDirectory())
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.appendingPathComponent("Videos").path))
        for mode in [HomeSystemDocumentPickerMode.files, .folder, .outputFolder] {
            let picker = VideoDocumentPicker(contentTypes: mode.allowedContentTypes,
                allowsMultipleSelection: mode.allowsMultipleSelection, directoryURL: location,
                accessibilityIdentifier: "test.picker", onPick: { _ in }, onCancel: {}).makePicker()
            let typeIdentifiers = mode.allowedContentTypes.map(\.identifier)
            XCTAssertEqual(picker.directoryURL, location)
            XCTAssertEqual(picker.documentPickerMode, .open)
            if mode == .files {
                XCTAssertTrue(picker.allowsMultipleSelection)
                XCTAssertFalse(typeIdentifiers.contains(UTType.folder.identifier))
                XCTAssertTrue(typeIdentifiers.contains(UTType.mpeg4Movie.identifier))
                XCTAssertTrue(typeIdentifiers.contains(UTType.quickTimeMovie.identifier))
            } else {
                XCTAssertFalse(picker.allowsMultipleSelection)
                XCTAssertEqual(typeIdentifiers, [UTType.folder.identifier])
            }
        }
    }

    @MainActor
    func testNativeDocumentPickerUpdatePreservesNavigationAndCompletesOnce() {
        let initial = URL(fileURLWithPath: "/initial", isDirectory: true)
        let navigated = URL(fileURLWithPath: "/other-location", isDirectory: true)
        let selected = [navigated.appendingPathComponent("a.mp4"), navigated.appendingPathComponent("b.mp4")]
        var picks: [[URL]] = []
        var cancels = 0
        var view = VideoDocumentPicker(contentTypes: [.movie], allowsMultipleSelection: true,
            directoryURL: initial, accessibilityIdentifier: "test.picker", onPick: { _ in XCTFail("Stale callback") }, onCancel: {})
        let picker = view.makePicker()
        let coordinator = view.makeCoordinator()
        picker.directoryURL = navigated
        view.onPick = { picks.append($0) }
        view.onCancel = { cancels += 1 }
        view.updatePicker(picker, coordinator: coordinator)
        XCTAssertEqual(picker.directoryURL, navigated, "SwiftUI refresh must not reset the active location")
        coordinator.documentPicker(picker, didPickDocumentsAt: selected)
        coordinator.documentPickerWasCancelled(picker)
        coordinator.documentPicker(picker, didPickDocumentsAt: selected)
        XCTAssertEqual(picks, [selected])
        XCTAssertEqual(cancels, 0)
        let cancelled = view.makeCoordinator()
        cancelled.documentPickerWasCancelled(picker)
        cancelled.documentPickerWasCancelled(picker)
        cancelled.documentPicker(picker, didPickDocumentsAt: selected)
        XCTAssertEqual(picks, [selected])
        XCTAssertEqual(cancels, 1)
    }

    func testFileAndFolderButtonsUseDistinctSystemPickers() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let loadedFilesURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/LoadedFilesPanelView.swift")
        let sourceActionBarURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/SourceActionBar.swift")
        let stateURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeScreenState.swift")
        let projectURL = rootURL.appendingPathComponent("TaptionEncoder.xcodeproj/project.pbxproj")
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
        let pickerText = try String(contentsOf: rootURL.appendingPathComponent("TaptionEncoder/Features/Preview/QueuePreviewModalPresenters.swift"), encoding: .utf8)
        let loadedFilesText = try String(contentsOf: loadedFilesURL, encoding: .utf8)
        let sourceActionBarText = try String(contentsOf: sourceActionBarURL, encoding: .utf8)
        let stateText = try String(contentsOf: stateURL, encoding: .utf8)
        let projectText = try String(contentsOf: projectURL, encoding: .utf8)
        let sourceBarStart = try XCTUnwrap(homeViewText.range(of: "SourceActionBar("))
        let sourceBarEnd = try XCTUnwrap(
            homeViewText[sourceBarStart.lowerBound...].range(of: "\n        )\n    }")
        )
        let sourceBarText = String(homeViewText[sourceBarStart.lowerBound..<sourceBarEnd.lowerBound])

        XCTAssertTrue(homeViewText.contains("@State private var activeImportBrowser: HomeImportBrowserMode?"))
        XCTAssertTrue(homeViewText.contains("@State private var didCompleteImportBrowserSelection = false"))
        XCTAssertFalse(homeViewText.contains("@State private var importBrowserPermissionMode"))
        XCTAssertFalse(homeViewText.contains("@State private var isImportBrowserLocationPickerPresented"))
        XCTAssertFalse(homeViewText.contains("@State private var didRequestStartupImportBrowserAccess"))
        XCTAssertTrue(homeViewText.contains("@State private var activeSystemDocumentPicker: HomeSystemDocumentPickerMode?"))
        XCTAssertTrue(homeViewText.contains("enum HomeSystemDocumentPickerMode: String"))
        XCTAssertTrue(homeViewText.contains("case files"))
        XCTAssertTrue(homeViewText.contains("case folder"))
        XCTAssertTrue(homeViewText.contains("case outputFolder"))
        XCTAssertTrue(homeViewText.contains("import UniformTypeIdentifiers"))
        XCTAssertFalse(homeViewText.contains("@State private var pendingImportPicker"))
        XCTAssertTrue(sourceBarText.contains("onFiles: openFilesImportBrowser"))
        XCTAssertTrue(sourceBarText.contains("onFolder: openFolderImportBrowser"))
        XCTAssertFalse(homeViewText.contains("requestImportBrowserLocationAccess(for:"))
        XCTAssertFalse(homeViewText.contains("requestStartupImportBrowserAccessIfNeeded()"))
        XCTAssertTrue(homeViewText.contains("activeSystemDocumentPicker = .files"))
        XCTAssertTrue(homeViewText.contains("activeSystemDocumentPicker = .folder"))
        XCTAssertFalse(homeViewText.contains(".fileImporter("))
        XCTAssertTrue(homeViewText.contains(".sheet(item: $activeSystemDocumentPicker"))
        XCTAssertTrue(homeViewText.contains("VideoDocumentPicker(contentTypes: mode.allowedContentTypes"))
        XCTAssertTrue(pickerText.contains("UIDocumentPickerViewController("))
        XCTAssertTrue(pickerText.contains("forOpeningContentTypes: contentTypes"))
        XCTAssertTrue(homeViewText.contains("return ImportableVideoTypes.all"))
        XCTAssertTrue(homeViewText.contains("return [.folder]"))
        XCTAssertTrue(homeViewText.contains("allowsMultipleSelection: mode.allowsMultipleSelection"))
        XCTAssertTrue(pickerText.contains("UIDocumentPickerDelegate"))
        XCTAssertTrue(pickerText.contains("documentPicker("))
        XCTAssertTrue(pickerText.contains("documentPickerWasCancelled"))
        XCTAssertTrue(homeViewText.contains("handleSystemDocumentPickerResult"))
        XCTAssertTrue(homeViewText.contains("handleFilePickerResult"))
        XCTAssertTrue(homeViewText.contains("handleFolderPickerResult"))
        XCTAssertTrue(homeViewText.contains("handleOutputFolderPickerResult"))
        XCTAssertTrue(homeViewText.contains("prepareFolderOutputDirectoryForStart"))
        XCTAssertTrue(homeViewText.contains("selectFolderOutputDirectory"))
        XCTAssertTrue(homeViewText.contains("viewModel.openExternalPlayerFile(url: file)"))
        XCTAssertTrue(homeViewText.contains("viewModel.startFilesFlow(urls: selectedURLs)"))
        XCTAssertTrue(homeViewText.contains("viewModel.handleFolderPickerSelection(urls: [folderURL])"))
        XCTAssertFalse(sourceBarText.contains("onSamples"))
        XCTAssertFalse(sourceBarText.contains("openSampleLibrary()"))
        XCTAssertFalse(sourceBarText.contains("activeSystemDocumentPicker = .files"))
        XCTAssertFalse(sourceBarText.contains("activeSystemDocumentPicker = .folder"))
        XCTAssertFalse(sourceActionBarText.contains("var onSamples"))
        XCTAssertFalse(sourceActionBarText.contains("title: \"Sample\""))
        XCTAssertFalse(sourceActionBarText.contains("title: \"Reset\""))
        XCTAssertTrue(homeViewText.contains("Label(\"Reset\", systemImage: \"arrow.counterclockwise\")"))
        XCTAssertTrue(homeViewText.contains("Button(\"Clear All\", action: resetHome)"))
        XCTAssertTrue(homeViewText.contains("HomeImportBrowserView("))
        XCTAssertFalse(homeViewText.contains("onRequestLocationAccess:"))
        XCTAssertFalse(homeViewText.contains("requestImportBrowserLocationAccess(for:"))
        XCTAssertTrue(homeViewText.contains("handleFolderPickerResult"))
        XCTAssertTrue(homeViewText.contains("handleImportBrowserDismiss"))
        XCTAssertFalse(homeViewText.contains("presentPendingImportPickerIfNeeded"))
        XCTAssertFalse(homeViewText.contains("openImportBrowserLocation"))
        XCTAssertFalse(homeViewText.contains("PendingSaveExportPicker("))
        XCTAssertFalse(homeViewText.contains("recoverFolderAccessForPendingSave(url:"))
        let exitButtonStart = try XCTUnwrap(homeViewText.range(of: "private func exitButton"))
        let exitButtonEnd = try XCTUnwrap(homeViewText[exitButtonStart.lowerBound...].range(of: "\n    private func outputSelector"))
        let exitButtonText = String(homeViewText[exitButtonStart.lowerBound..<exitButtonEnd.lowerBound])
        XCTAssertFalse(exitButtonText.contains(".background(Color(red: 1.0, green: 0.30, blue: 0.34).opacity(0.16))"))
        XCTAssertTrue(exitButtonText.contains(".foregroundStyle(TaptionTheme.accentButtonText)"))
        XCTAssertTrue(exitButtonText.contains(".background(TaptionTheme.coral)"))
        XCTAssertTrue(exitButtonText.contains(".padding(.horizontal, TaptionTheme.cardContentPadding)"))
        let homeContentStart = try XCTUnwrap(homeViewText.range(of: "private func homeContent("))
        let homeContentEnd = try XCTUnwrap(homeViewText[homeContentStart.lowerBound...].range(of: "\n    private func sourceControls"))
        let homeContentText = String(homeViewText[homeContentStart.lowerBound..<homeContentEnd.lowerBound])
        XCTAssertFalse(homeContentText.contains("exitButton(metrics: metrics)"))
        XCTAssertTrue(homeViewText.contains("Label(\"Exit\", systemImage: \"xmark.circle\")"))
        XCTAssertFalse(projectText.contains("VideoDocumentPicker.swift"))
        XCTAssertTrue(homeViewText.contains("viewModel.navigateImportBrowserIntoFolder(id: $0)"))
        XCTAssertTrue(homeViewText.contains("onBack: { viewModel.navigateImportBrowserUp() }"))
        XCTAssertFalse(homeViewText.contains("onBack: { viewModel.navigateImportBrowserBack() }"))
        XCTAssertTrue(homeViewText.contains("viewModel.navigateImportBrowserUp()"))
        XCTAssertTrue(homeViewText.contains("viewModel.toggleImportBrowserFileSelection(id: $0)"))
        XCTAssertTrue(homeViewText.contains("viewModel.importFromImportBrowser()"))
        XCTAssertTrue(stateText.contains("enum HomeImportBrowserMode: String, Identifiable, Equatable"))
        XCTAssertTrue(stateText.contains("return \"On My iPhone\""))
        XCTAssertTrue(stateText.contains("struct HomeImportBrowserContext: Identifiable, Equatable"))
        XCTAssertTrue(stateText.contains("struct HomeImportBrowserFolderSnapshot: Identifiable, Equatable"))
        XCTAssertTrue(stateText.contains("struct HomeImportBrowserFileSnapshot: Identifiable, Equatable"))
        XCTAssertTrue(loadedFilesText.contains("struct HomeImportBrowserView: View"))
        XCTAssertTrue(loadedFilesText.contains("GridItem(.flexible(minimum: 82)"))
        XCTAssertTrue(loadedFilesText.contains("ImportBrowserBackButton("))
        XCTAssertTrue(loadedFilesText.contains("ImportBrowserToolbarButton("))
        XCTAssertTrue(loadedFilesText.contains("ImportBrowserExplorerStyle.navigationBar"))
        XCTAssertTrue(loadedFilesText.contains("ImportBrowserExplorerStyle.blueAccent"))
        XCTAssertTrue(loadedFilesText.contains(".simultaneousGesture(backSwipeGesture)"))
        XCTAssertTrue(loadedFilesText.contains("DragGesture(minimumDistance: 24"))
        XCTAssertTrue(loadedFilesText.contains("guard context?.canGoUp == true"))
        XCTAssertTrue(loadedFilesText.contains("Image(systemName: \"chevron.left\")"))
        XCTAssertTrue(loadedFilesText.contains("ImportBrowserFolderArtwork(systemBadge: nil)"))
        XCTAssertFalse(loadedFilesText.contains("HomeImportBrowserLocationAccessTileView"))
        XCTAssertFalse(loadedFilesText.contains("folder.badge.plus"))
        XCTAssertTrue(loadedFilesText.contains("HomeImportBrowserFolderTileView("))
        XCTAssertTrue(loadedFilesText.contains("HomeImportBrowserFileTileView("))
        XCTAssertFalse(loadedFilesText.contains("var onRequestLocationAccess"))
        XCTAssertFalse(loadedFilesText.contains("var onUp: () -> Void"))
        XCTAssertFalse(loadedFilesText.contains("Text(\"Add Location\")"))
        XCTAssertFalse(loadedFilesText.contains("Choose files root"))
        XCTAssertFalse(loadedFilesText.contains("onChooseLocation"))
        XCTAssertTrue(loadedFilesText.contains("Label(mode.importTitle, systemImage: mode == .files ? \"checkmark.circle.fill\" : \"tray.and.arrow.down.fill\")"))

        let appSourceDirectoryURL = rootURL.appendingPathComponent("TaptionEncoder")
        let appSourceURLs = try FileManager.default.subpathsOfDirectory(atPath: appSourceDirectoryURL.path)
            .filter { $0.hasSuffix(".swift") }
            .map { appSourceDirectoryURL.appendingPathComponent($0) }
        let appSourceText = try appSourceURLs
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        XCTAssertTrue(appSourceText.contains("UIDocumentPickerViewController"))
        XCTAssertTrue(appSourceText.contains("UIDocumentPickerDelegate"))
        XCTAssertFalse(appSourceText.contains("fileImporter"))
        XCTAssertFalse(appSourceText.contains("fileExporter"))
        XCTAssertFalse(appSourceText.contains("PendingSaveExportPrompt"))
        XCTAssertFalse(appSourceText.contains("PendingFolderAccessPrompt"))
        XCTAssertFalse(appSourceText.contains("recoverFolderAccessForPendingSave"))
    }

    func testExternalVideoOpenSuppressesAppOpenAdsBeforePreviewRouting() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let appURL = rootURL.appendingPathComponent("TaptionEncoder/TaptionEncoderApp.swift")
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
        let appText = try String(contentsOf: appURL, encoding: .utf8)
        let openURLStart = try XCTUnwrap(homeViewText.range(of: ".onOpenURL { url in"))
        let openURLEnd = try XCTUnwrap(
            homeViewText[openURLStart.lowerBound...].range(of: "\n        .onReceive(")
        )
        let openURLText = String(homeViewText[openURLStart.lowerBound..<openURLEnd.lowerBound])
        let handlerStart = try XCTUnwrap(homeViewText.range(of: "private func handleExternalVideoOpen"))
        let handlerEnd = try XCTUnwrap(
            homeViewText[handlerStart.lowerBound...].range(of: "\n    #if DEBUG")
        )
        let handlerText = String(homeViewText[handlerStart.lowerBound..<handlerEnd.lowerBound])
        let suppressionRange = try XCTUnwrap(
            handlerText.range(of: "AdMobBootstrapper.suppressAppOpenAdsForExternalPlayback()")
        )
        let miniPlayerClearRange = try XCTUnwrap(
            handlerText.range(of: "clearMiniPlayerForNewSource(reason: \"externalVideoOpen\")")
        )
        let previewRoutingRange = try XCTUnwrap(
            handlerText.range(of: "viewModel.openExternalPlayerFile(url: url)")
        )

        XCTAssertTrue(openURLText.contains("handleExternalVideoOpen(url: url, source: \"scene\")"))
        XCTAssertTrue(
            homeViewText.contains(".onReceive(NotificationCenter.default.publisher(for: .taptionExternalVideoOpenRequested))")
        )
        XCTAssertTrue(homeViewText.contains("drainPendingExternalVideoOpens(source: \"delegate\")"))
        XCTAssertTrue(homeViewText.contains("drainPendingExternalVideoOpens(source: \"pending\")"))
        XCTAssertTrue(homeViewText.contains("for url in ExternalVideoOpenInbox.drainPendingURLs()"))
        XCTAssertTrue(homeViewText.contains("Duplicate external video URL ignored"))
        XCTAssertTrue(homeViewText.contains("Queue mini player cleared for new source"))
        XCTAssertLessThan(miniPlayerClearRange.lowerBound, suppressionRange.lowerBound)
        XCTAssertLessThan(suppressionRange.lowerBound, previewRoutingRange.lowerBound)
        XCTAssertTrue(appText.contains("static let taptionExternalVideoOpenRequested"))
        XCTAssertTrue(appText.contains("enum ExternalVideoOpenInbox"))
        XCTAssertTrue(appText.contains("@MainActor\nfinal class AppDelegate"))
        XCTAssertTrue(appText.contains("let canHandleURL = ExternalVideoOpenPolicy.canHandle(url: url)"))
        XCTAssertFalse(appText.contains("Task { @MainActor in\n                AdMobBootstrapper.suppressAppOpenAdsForExternalPlayback()"))
        XCTAssertTrue(appText.contains("ExternalVideoOpenInbox.enqueue(url)"))
        XCTAssertTrue(appText.contains("NotificationCenter.default.post(name: .taptionExternalVideoOpenRequested"))
        XCTAssertTrue(appText.contains("return canHandleURL"))
    }

    func testExternalVideoPlayerFlowVerifierCoversRealOpenURLPath() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = rootURL.appendingPathComponent("Scripts/verify_external_video_player_flow.sh")
        let scriptText = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(scriptText.contains("xcrun simctl openurl"))
        XCTAssertFalse(scriptText.contains("SIMCTL_CHILD_TAPTION_AUTO_MINIMIZE_PREVIEW=1"))
        XCTAssertTrue(scriptText.contains("TAPTION_EXTERNAL_PLAYER_VERIFY_MODE"))
        XCTAssertTrue(scriptText.contains("external-video-player-flow-$MODE.log"))
        XCTAssertTrue(scriptText.contains("external-video-player-flow-$MODE.png"))
        XCTAssertTrue(scriptText.contains("xcrun simctl terminate \"$DEVICE\" \"$BUNDLE_ID\""))
        XCTAssertTrue(scriptText.contains("External video URL opened"))
        XCTAssertTrue(scriptText.contains("source=scene"))
        XCTAssertTrue(scriptText.contains("External player file routed into queue flow"))
        XCTAssertTrue(scriptText.contains("Security scoped access started"))
        XCTAssertTrue(scriptText.contains("Prepare encoding ready"))
        XCTAssertTrue(scriptText.contains("external video file open unexpectedly started preview playback"))
        XCTAssertTrue(scriptText.contains("external video file open queued without playback"))
        XCTAssertTrue(scriptText.contains("xcrun simctl io \"$DEVICE\" screenshot"))
    }

    func testExternalPlayerRegistrationVerifierCoversInstalledDocumentOwnership() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = rootURL.appendingPathComponent("Scripts/verify_external_player_registration.sh")
        let scriptText = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(scriptText.contains("TaptionEncoder/Info.plist"))
        XCTAssertTrue(scriptText.contains("TAPTION_ENCODER_APP_PATH"))
        XCTAssertTrue(scriptText.contains("CFBundleDocumentTypes"))
        XCTAssertTrue(scriptText.contains("\"LSHandlerRank\""))
        XCTAssertTrue(scriptText.contains("\"Owner\""))
        XCTAssertTrue(scriptText.contains("\"CFBundleTypeRole\""))
        XCTAssertTrue(scriptText.contains("\"Viewer\""))
        XCTAssertTrue(scriptText.contains("\"LSSupportsOpeningDocumentsInPlace\""))
        XCTAssertTrue(scriptText.contains("\"UIFileSharingEnabled\""))
        XCTAssertTrue(scriptText.contains("\"UISupportsDocumentBrowser\""))
        XCTAssertTrue(scriptText.contains("\"com.taption.legacy-video\""))
        XCTAssertTrue(scriptText.contains("\"public.movie\""))
        XCTAssertTrue(scriptText.contains("\"public.video\""))
        XCTAssertTrue(scriptText.contains("external player registration verified"))
    }

    func testPictureInPictureProbeVerifierCoversSimulatorAndDeviceLaunches() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = rootURL.appendingPathComponent("Scripts/verify_picture_in_picture_probe.sh")
        let scriptText = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(scriptText.contains("TAPTION_PREVIEW_SAMPLE_NAME"))
        XCTAssertTrue(scriptText.contains("TAPTION_AUTO_START_PIP"))
        XCTAssertTrue(scriptText.contains("TAPTION_PIP_PROBE_ID"))
        XCTAssertTrue(scriptText.contains("xcrun simctl launch --terminate-running-process"))
        XCTAssertTrue(scriptText.contains("xcrun devicectl device process launch"))
        XCTAssertTrue(scriptText.contains("--environment-variables"))
        XCTAssertTrue(scriptText.contains("requested_pattern=\"Debug auto PiP requested .*probeID=$PROBE_ID\""))
        XCTAssertTrue(scriptText.contains("possible_pattern=\"Debug auto PiP requested .*possible=true .*probeID=$PROBE_ID\""))
        XCTAssertTrue(scriptText.contains("active_pattern=\"Debug auto PiP state checked .*active=true .*probeID=$PROBE_ID\""))
        XCTAssertTrue(scriptText.contains("TAPTION_PIP_REQUIRE_ACTIVE"))
        XCTAssertTrue(scriptText.contains("picture-in-picture-probe.log"))
    }

    func testDeviceCodecCapabilitiesExposeInstalledDeviceSupportFlags() {
        let supportedVideo = TaptionCodecHardwareCapability(
            videoCodec: .hevc,
            coreMediaCodecType: "hvc1",
            hardwareDecodeSupported: true,
            hardwareEncodeSupported: false,
            encodeProbeStatus: 0,
            encoderIdentifier: "hevc"
        )
        let unsupportedVideo = TaptionCodecHardwareCapability(
            videoCodec: .mpeg4Visual,
            coreMediaCodecType: "mp4v",
            hardwareDecodeSupported: false,
            hardwareEncodeSupported: false,
            encodeProbeStatus: nil,
            encoderIdentifier: nil
        )
        let appSupportedSoftwareVideo = TaptionCodecHardwareCapability(
            videoCodec: .av1,
            coreMediaCodecType: "av01",
            hardwareDecodeSupported: false,
            hardwareEncodeSupported: false,
            encodeProbeStatus: nil,
            encoderIdentifier: nil
        )
        let appSupportedSoftwareEncodeVideo = TaptionCodecHardwareCapability(
            videoCodec: .h264,
            coreMediaCodecType: "avc1",
            hardwareDecodeSupported: false,
            hardwareEncodeSupported: false,
            encodeProbeStatus: nil,
            encoderIdentifier: nil
        )
        let supportedAudio = TaptionAudioCodecHardwareCapability(
            audioCodec: .aac,
            nativeDecodeSupported: true,
            nativeEncodeSupported: true,
            mp4CopySupported: true,
            movCopySupported: true
        )
        let unsupportedAudio = TaptionAudioCodecHardwareCapability(
            audioCodec: .unknown,
            nativeDecodeSupported: false,
            nativeEncodeSupported: false,
            mp4CopySupported: false,
            movCopySupported: false
        )

        XCTAssertTrue(supportedVideo.isSupportedOnInstalledDevice)
        XCTAssertFalse(unsupportedVideo.isSupportedOnInstalledDevice)
        XCTAssertTrue(supportedAudio.isSupportedOnInstalledDevice)
        XCTAssertFalse(unsupportedAudio.isSupportedOnInstalledDevice)

        XCTAssertTrue(appSupportedSoftwareVideo.isInputSupportedByCurrentBuildOnInstalledDevice)
        XCTAssertFalse(appSupportedSoftwareVideo.isSupportedOnInstalledDevice)
        XCTAssertTrue(appSupportedSoftwareVideo.shouldHighlightInDeviceInfo)

        XCTAssertTrue(appSupportedSoftwareEncodeVideo.isInputSupportedByCurrentBuildOnInstalledDevice)
        XCTAssertTrue(appSupportedSoftwareEncodeVideo.shouldHighlightInDeviceInfo)

        XCTAssertTrue(supportedAudio.isInputSupportedByCurrentBuild)
        XCTAssertTrue(supportedAudio.shouldHighlightInDeviceInfo)
        XCTAssertFalse(unsupportedAudio.isInputSupportedByCurrentBuild)
        XCTAssertFalse(unsupportedAudio.shouldHighlightInDeviceInfo)
    }

    func testOutputReadinessCatalogReportSummarizesSelectorMatrix() {
        let report = TaptionCodecOutputCatalog.makeReadinessReport()
        let expectedOutputSelectionCount = TaptionCodecOutputCatalog.selectableVideoCodecs.count
            * TaptionCodecOutputCatalog.selectableContainers.count

        XCTAssertEqual(report.videoCodecCount, TaptionCodecOutputCatalog.selectableVideoCodecs.count)
        XCTAssertEqual(report.containerCount, TaptionCodecOutputCatalog.selectableContainers.count)
        XCTAssertEqual(report.outputSelectionCount, expectedOutputSelectionCount)
        XCTAssertEqual(report.items.count, expectedOutputSelectionCount)
        XCTAssertTrue(report.stateCountsAreConsistent)
        XCTAssertTrue(report.outputSelectionCoverageIsPassing)
        XCTAssertEqual(report.defaultOutputCodec, .hevc)
        XCTAssertEqual(report.defaultOutputContainer, .mp4)
        XCTAssertEqual(report.defaultOutputState, .implemented)
        XCTAssertEqual(report.firstReleaseOutputCodecs, TaptionCodecRegistry.firstReleaseOutputCodecs)
        XCTAssertEqual(report.implementedOutputSelectionCount, 2)
        XCTAssertEqual(report.commandPlanReadyOutputSelectionCount, 0)
        XCTAssertEqual(report.plannedOutputSelectionCount, 0)
        XCTAssertEqual(report.unsupportedOutputSelectionCount, 0)

        let currentBuildItem = report.items.first {
            $0.videoCodec == .hevc && $0.container == .mp4
        }
        let movBuildItem = report.items.first {
            $0.videoCodec == .hevc && $0.container == .mov
        }
        XCTAssertEqual(currentBuildItem?.state, .implemented)
        XCTAssertNil(currentBuildItem?.note)
        XCTAssertEqual(movBuildItem?.state, .implemented)
        XCTAssertNil(movBuildItem?.note)
    }

    func testAudioOutputReadinessCatalogReportSummarizesSelectorMatrix() {
        let report = TaptionAudioCodecOutputCatalog.makeReadinessReport()
        let expectedOutputSelectionCount = TaptionAudioCodecOutputCatalog.selectableAudioCodecs.count
            * TaptionAudioCodecOutputCatalog.selectableContainers.count

        XCTAssertEqual(report.audioCodecCount, TaptionAudioCodecOutputCatalog.selectableAudioCodecs.count)
        XCTAssertEqual(report.containerCount, TaptionAudioCodecOutputCatalog.selectableContainers.count)
        XCTAssertEqual(report.outputSelectionCount, expectedOutputSelectionCount)
        XCTAssertEqual(report.items.count, expectedOutputSelectionCount)
        XCTAssertTrue(report.stateCountsAreConsistent)
        XCTAssertTrue(report.outputSelectionCoverageIsPassing)
        XCTAssertEqual(report.defaultOutputCodec, .aac)
        XCTAssertEqual(report.defaultOutputContainer, .mp4)
        XCTAssertEqual(report.defaultOutputState, .implemented)
        XCTAssertEqual(report.implementedOutputSelectionCount, 4)
        XCTAssertGreaterThan(report.commandPlanReadyOutputSelectionCount, 0)
        XCTAssertGreaterThan(report.plannedOutputSelectionCount, 0)
        XCTAssertEqual(report.unsupportedOutputSelectionCount, 0)

        let currentBuildItem = report.items.first {
            $0.audioCodec == .aac && $0.container == .mp4
        }
        let movBuildItem = report.items.first {
            $0.audioCodec == .aac && $0.container == .mov
        }
        let commandPlanItem = report.items.first {
            $0.audioCodec == .opus && $0.container == .mp4
        }
        let pcmMovBuildItem = report.items.first {
            $0.audioCodec == .pcm && $0.container == .mov
        }
        let alacMovBuildItem = report.items.first {
            $0.audioCodec == .alac && $0.container == .mov
        }
        let plannedItem = report.items.first {
            $0.audioCodec == .xheAAC && $0.container == .mp4
        }

        XCTAssertEqual(currentBuildItem?.state, .implemented)
        XCTAssertNil(currentBuildItem?.note)
        XCTAssertEqual(movBuildItem?.state, .implemented)
        XCTAssertNil(movBuildItem?.note)
        XCTAssertEqual(pcmMovBuildItem?.state, .implemented)
        XCTAssertNil(pcmMovBuildItem?.note)
        XCTAssertEqual(alacMovBuildItem?.state, .implemented)
        XCTAssertNil(alacMovBuildItem?.note)
        XCTAssertEqual(commandPlanItem?.state, .commandPlanReady)
        XCTAssertTrue(commandPlanItem?.note?.contains("software command plan") == true)
        XCTAssertEqual(plannedItem?.state, .planned)
        XCTAssertTrue(plannedItem?.note?.contains("universal codec update") == true)
    }

    func testLaunchSupportCatalogMatchesCurrentLaunchContract() {
        let expectedExecutableNowVideoCodecs: [TaptionVideoCodec] = [
            .av1, .hevcWithAlpha, .dolbyVisionHEVC, .vp9, .vp8,
            .mpeg1, .mpeg2, .mpeg4Visual, .h263, .h261,
            .flashVideo, .microsoftMPEG4V2, .microsoftMPEG4V3, .motionJPEG,
            .jpeg, .jpeg2000, .jpegLS, .losslessJPEG, .jpegXL, .animation, .cinepak,
            .sorensonVideo, .sorensonVideo3, .quickTimeVideo, .theora,
            .realVideo1, .realVideo, .roqVideo, .wmv,
            .microsoftVideo1, .asusV1, .asusV2, .flashScreenVideo,
            .flashScreenVideo2, .zmbv, .cljr, .snow, .ffv1, .huffYUV,
            .utVideo, .magicYUV, .dvcPro, .dvcProHD, .vc1, .dv, .cineForm, .dnxhd,
            .pngVideo, .r10k, .v308, .v210, .r210, .v408, .v410,
            .microsoftRLE, .quickTimeGraphics, .yuv4, .rawVideo, .y41p,
            .h264, .hevc, .proResRaw
        ]
        let expectedSupportedInputVideoCodecs = expectedExecutableNowVideoCodecs.map {
            TaptionLaunchInputVideoSupportItem(codec: $0, availability: .availableNow)
        } + [
            TaptionLaunchInputVideoSupportItem(codec: .proRes, availability: .availableOnSupportedHardware)
        ]

        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputVideoCodecs,
            expectedSupportedInputVideoCodecs
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputVideoSummary,
            expectedSupportedInputVideoCodecs.map { $0.codec.displayName }.joined(separator: ", ")
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputContainers,
            [.mp4, .mov, .m4v, .mkv, .avi, .webm, .flv, .ogg, .mpegTransportStream, .mxf, .mpegProgramStream, .lrf, .dv, .threeGP, .threeGPP2, .asf, .wmv, .nut, .roq, .realMedia, .rawElementaryStream]
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputContainerSummary,
            "MP4, MOV, QT, M4V, MKV, AVI, DIVX, WEBM, FLV, F4V, OGG, OGV, OGM, TS, MTS, M2TS, M2T, TP, TRP, TOD, MXF, MPG, MPEG, MPE, VOB, MOD, DAT, LRF, DV, DIF, 3GP, 3GPP, 3G2, 3GPP2, ASF, DVR-MS, WMV, NUT, ROQ, RM, RMVB, H264, H265, HEVC, 264, 265, IVF, OBU, Y4M, AV1, H263, H261, M1V, M2V, VC1"
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.executableNowInputVideoCodecs,
            expectedExecutableNowVideoCodecs
        )
        XCTAssertTrue(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.isEmpty)
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.hardwareGatedInputVideoCodecs,
            [.proRes]
        )
        XCTAssertFalse(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.contains(.h261))
        for codec in expectedExecutableNowVideoCodecs {
            XCTAssertFalse(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.contains(codec), codec.displayName)
        }
        XCTAssertFalse(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.contains(.av1))
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedOutputContainerSummary,
            "MP4, MOV"
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.makeInputReadinessReport(),
            TaptionLaunchInputReadinessReport(
                executableNowVideoCodecs: expectedExecutableNowVideoCodecs,
                hardwareGatedVideoCodecs: [.proRes],
                plannedVideoCodecs: TaptionLaunchSupportCatalog.plannedInputVideoCodecs,
                inputContainers: TaptionLaunchSupportCatalog.supportedInputContainers,
                outputVideoCodec: .hevc,
                outputContainers: [.mp4, .mov]
            )
        )
        XCTAssertFalse(TaptionLaunchSupportCatalog.supportedInputVideoNote.contains("H.264 / AVC"))
        XCTAssertFalse(TaptionLaunchSupportCatalog.supportedInputVideoNote.contains("H.265 / HEVC"))
        XCTAssertTrue(
            TaptionLaunchSupportCatalog.supportedInputVideoNote.contains("Apple ProRes")
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputContainerNote,
            "The current launch build imports Apple-readable containers plus selected software-inspected inputs such as MKV, WebM, FLV, OGG/OGV, AVI, MXF, MPEG transport and program streams, DJI LRF, NUT, 3GP, 3G2, ASF/WMV, and raw elementary streams."
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.plannedInputVideoNote,
            "There are no roadmap-only input codecs outside the current launch build."
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .mp4, videoCodec: .av1),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .avi, videoCodec: .mpeg4Visual),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .mp4, videoCodec: .vp9),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .webm, videoCodec: .vp8),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .mpegProgramStream, videoCodec: .mpeg2),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .mpegProgramStream, videoCodec: .mpeg1),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .threeGP, videoCodec: .h263),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .avi, videoCodec: .motionJPEG),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .wmv, videoCodec: .wmv),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .mp4, videoCodec: .h264),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .mp4, videoCodec: .h261),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
            )
        )
        for input in [
            (TaptionVideoContainer.flv, TaptionVideoCodec.flashVideo),
            (.avi, .microsoftMPEG4V2),
            (.avi, .microsoftMPEG4V3),
            (.mov, .jpeg2000),
            (.mov, .jpegLS),
            (.avi, .losslessJPEG),
            (.mov, .animation),
            (.mov, .cinepak),
            (.mov, .sorensonVideo),
            (.mov, .sorensonVideo3),
            (.mov, .quickTimeVideo),
            (.ogg, .theora)
        ] {
            XCTAssertEqual(
                TaptionLaunchSupportCatalog.diagnoseInput(container: input.0, videoCodec: input.1),
                TaptionLaunchInputSupportDiagnosis(
                    state: .supported,
                    title: "Input Supported",
                    detail: "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
                ),
                input.1.displayName
            )
        }
        XCTAssertEqual(TaptionLaunchSupportCatalog.supportedOutput.videoCodec, .hevc)
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedOutput.audioCodec,
            TaptionAudioCodecRoutePlanner.defaultOutputCodec
        )
        XCTAssertEqual(TaptionLaunchSupportCatalog.supportedOutput.container, .mp4)
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(
                videoCodec: TaptionLaunchSupportCatalog.supportedOutput.videoCodec,
                container: TaptionLaunchSupportCatalog.supportedOutput.container
            ),
            .implemented
        )
        XCTAssertEqual(
            TaptionAudioCodecOutputCatalog.implementationState(
                audioCodec: TaptionLaunchSupportCatalog.supportedOutput.audioCodec,
                container: TaptionLaunchSupportCatalog.supportedOutput.container
            ),
            .implemented
        )
    }

    func testRuntimeLaunchReadinessSplitsNowByCurrentDevicePath() {
        let oldestSupportedProfile = appleModelProfile("iPad7,11")
        let oldestReport = TaptionLaunchSupportCatalog.makeRuntimeInputReadinessReport(
            hardwareSupport: oldestSupportedProfile
        )
        let hevcHardwareReport = TaptionLaunchSupportCatalog.makeRuntimeInputReadinessReport(
            hardwareSupport: .h264HEVCHardware
        )

        XCTAssertTrue(oldestReport.nowMixedVideoCodecs.contains(.h264))
        XCTAssertTrue(oldestReport.nowSoftwareVideoCodecs.contains(.hevc))
        XCTAssertFalse(oldestReport.needsHardwareVideoCodecs.contains(.h264))
        XCTAssertFalse(oldestReport.needsHardwareVideoCodecs.contains(.hevc))
        XCTAssertTrue(oldestReport.needsHardwareVideoCodecs.contains(.proRes))
        XCTAssertTrue(hevcHardwareReport.nowHardwareVideoCodecs.contains(.h264))
        XCTAssertTrue(hevcHardwareReport.nowHardwareVideoCodecs.contains(.hevc))
    }

    func testOutputCatalogCombinesRouteAndContainerReadiness() {
        XCTAssertEqual(
            TaptionCodecOutputCatalog.routeImplementationState(
                sourceCodec: .av1,
                outputCodec: .hevc,
                container: .mp4
            ),
            .implemented
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.routeImplementationState(
                sourceCodec: .av1,
                outputCodec: .hevc,
                container: .mov
            ),
            .implemented
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.routeImplementationState(
                sourceCodec: .h264,
                outputCodec: .av1,
                container: .mkv
            ),
            .unsupported
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.routeImplementationState(
                sourceCodec: .av1,
                outputCodec: .h264,
                container: .mp4
            ),
            .unsupported
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.routeImplementationState(
                sourceCodec: .h261,
                outputCodec: .hevc,
                container: .mp4
            ),
            .implemented
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.routeImplementationState(
                sourceCodec: .unknown,
                outputCodec: .hevc,
                container: .mp4
            ),
            .unsupported
        )
    }

    func testGenericSingleAssetPlanKeepsSelectedOutputPolicy() throws {
        let asset = makeAsset(sourceCodec: .av1)
        let sourceURL = URL(fileURLWithPath: "/tmp/input.mp4")
        let temporaryURL = URL(fileURLWithPath: "/tmp/output.mov")
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            container: .mov,
            profile: .automatic,
            qualityPolicy: .preserveSourceVisuals,
            advancedOptions: .preserveSource
        )

        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryURL,
            outputPolicy: outputPolicy
        )

        XCTAssertEqual(plan.outputPolicy.videoCodec, outputPolicy.videoCodec)
        XCTAssertEqual(plan.outputPolicy.audioCodec, outputPolicy.audioCodec)
        XCTAssertEqual(plan.outputPolicy.container, outputPolicy.container)
        XCTAssertEqual(plan.outputPolicy.profile, outputPolicy.profile)
        XCTAssertEqual(plan.outputPolicy.qualityPolicy, outputPolicy.qualityPolicy)
        XCTAssertEqual(plan.outputPolicy.advancedOptions.resizeTo, TaptionPixelSize(width: 1920, height: 1080))
        XCTAssertEqual(plan.outputPolicy.advancedOptions.frameRate, TaptionRationalFrameRate(numerator: 30))
        XCTAssertEqual(plan.outputPolicy.advancedOptions.color, TaptionColorDescription())
        XCTAssertEqual(plan.outputPolicy.advancedOptions.rotationDegrees, 0)
        XCTAssertEqual(plan.codecRoute, TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc))
        XCTAssertEqual(plan.codecExecutionKind, .mixed)
        XCTAssertEqual(plan.finalOutputURL?.path, "/tmp/input_taption.mov")
        XCTAssertEqual(plan.encoderSelection.requestedMode, .automatic)
        XCTAssertEqual(plan.videoCommandPlan?.routeSummary, "AV1 to H.265 / HEVC")
        XCTAssertTrue(plan.videoCommandPlan?.arguments.contains("libx265") == true)
        XCTAssertEqual(
            try SW_FFmpegCodecCommandPlanner.makeSingleAssetCommandPlan(plan: plan),
            plan.videoCommandPlan
        )
    }

    func testCurrentHEVCMOVSelectionKeepsMOVOutputURLsAndAudioPlan() throws {
        let asset = makeAsset(sourceCodec: .av1)
        let sourceURL = URL(fileURLWithPath: "/tmp/input.mp4")
        let temporaryURL = URL(fileURLWithPath: "/tmp/output.mov")
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            container: .mov
        )

        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryURL,
            outputPolicy: outputPolicy
        )

        XCTAssertEqual(plan.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(plan.outputPolicy.audioCodec, .aac)
        XCTAssertEqual(plan.outputPolicy.container, .mov)
        XCTAssertEqual(plan.temporaryOutputURL?.path, "/tmp/output.mov")
        XCTAssertEqual(plan.finalOutputURL?.path, "/tmp/input_taption.mov")
        XCTAssertEqual(plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .aac))
        XCTAssertEqual(plan.audioPlan?.routeSelection.support, .copy)
        XCTAssertTrue(plan.audioPlan?.isRunnableInCurrentBuild == true)
    }

    func testAV1SoftwareHEVCConfigurationUsesMOVFileTypeWhenSelected() throws {
        let asset = makeAsset(sourceCodec: .av1)
        let outputURL = URL(fileURLWithPath: "/tmp/output.mov")

        let configuration = try SW_AV1HEVCTranscodeConfiguration.make(
            asset: asset,
            outputURL: outputURL,
            options: .preservingSource(outputCodec: .hevc, container: .mov)
        )

        XCTAssertEqual(configuration.outputURL, outputURL)
        XCTAssertEqual(configuration.outputFileType, .mov)
    }

    func testAV1SoftwareHEVCConfigurationPreservesSourceColorMetadata() throws {
        let sourceColor = TaptionColorDescription(
            primaries: .bt709,
            transfer: .bt709,
            matrix: .bt709,
            bitDepth: 8,
            isHDR: false
        )
        let asset = makeAsset(sourceCodec: .av1, color: sourceColor)

        let configuration = try SW_AV1HEVCTranscodeConfiguration.make(
            asset: asset,
            outputURL: URL(fileURLWithPath: "/tmp/av1-color.mp4")
        )

        XCTAssertEqual(configuration.color, sourceColor)
    }

    func testAV1SoftwareHEVCWriterCreatesCompleteBT709ColorProperties() throws {
        let properties = try XCTUnwrap(SW_AV1HEVCWriterColorProperties.make(
            for: TaptionColorDescription(
                primaries: .bt709,
                transfer: .bt709,
                matrix: .bt709
            )
        ))

        XCTAssertEqual(properties[AVVideoColorPrimariesKey], AVVideoColorPrimaries_ITU_R_709_2)
        XCTAssertEqual(properties[AVVideoTransferFunctionKey], AVVideoTransferFunction_ITU_R_709_2)
        XCTAssertEqual(properties[AVVideoYCbCrMatrixKey], AVVideoYCbCrMatrix_ITU_R_709_2)
    }

    func testSoftwareHEVCWriterInfersBT601MatrixForSMPTEColor() throws {
        let properties = try XCTUnwrap(SW_AV1HEVCWriterColorProperties.make(
            for: TaptionColorDescription(
                primaries: .smpteC,
                transfer: .bt709,
                matrix: .unknown
            )
        ))

        XCTAssertEqual(properties[AVVideoColorPrimariesKey], AVVideoColorPrimaries_SMPTE_C)
        XCTAssertEqual(properties[AVVideoTransferFunctionKey], AVVideoTransferFunction_ITU_R_709_2)
        XCTAssertEqual(properties[AVVideoYCbCrMatrixKey], AVVideoYCbCrMatrix_ITU_R_601_4)
    }

    func testAV1SoftwareHEVCWriterOmitsIncompleteColorProperties() {
        XCTAssertNil(SW_AV1HEVCWriterColorProperties.make(
            for: TaptionColorDescription(
                primaries: .bt709,
                transfer: .unknown,
                matrix: .bt709
            )
        ))
    }

    func testFFmpegDecodeBridgeWriterPreservesNonSquarePixelAspectRatio() throws {
        let properties = try XCTUnwrap(
            SW_FFmpegDecodeBridgeWriterMetadata.pixelAspectRatio(
                horizontalSpacing: 352,
                verticalSpacing: 427
            )
        )

        XCTAssertEqual(properties[AVVideoPixelAspectRatioHorizontalSpacingKey] as? Int, 352)
        XCTAssertEqual(properties[AVVideoPixelAspectRatioVerticalSpacingKey] as? Int, 427)
        XCTAssertNil(SW_FFmpegDecodeBridgeWriterMetadata.pixelAspectRatio(
            horizontalSpacing: 1,
            verticalSpacing: 1
        ))
    }

    func testFFmpegDecodeBridgeGeometrySeparatesCodedAndDisplaySize() {
        let snowGeometry = SW_FFmpegDecodeBridgeVideoGeometry(
            codedSize: TaptionPixelSize(width: 240, height: 136),
            sampleAspectRatioHorizontalSpacing: 136,
            sampleAspectRatioVerticalSpacing: 135
        )
        XCTAssertEqual(snowGeometry.codedSize, TaptionPixelSize(width: 240, height: 136))
        XCTAssertEqual(snowGeometry.displaySize, TaptionPixelSize(width: 242, height: 136))

        let palDVGeometry = SW_FFmpegDecodeBridgeVideoGeometry(
            codedSize: TaptionPixelSize(width: 720, height: 576),
            sampleAspectRatioHorizontalSpacing: 16,
            sampleAspectRatioVerticalSpacing: 15
        )
        XCTAssertEqual(palDVGeometry.codedSize, TaptionPixelSize(width: 720, height: 576))
        XCTAssertEqual(palDVGeometry.displaySize, TaptionPixelSize(width: 768, height: 576))

        let vc1Geometry = SW_FFmpegDecodeBridgeVideoGeometry(
            codedSize: TaptionPixelSize(width: 720, height: 480),
            sampleAspectRatioHorizontalSpacing: 40,
            sampleAspectRatioVerticalSpacing: 33
        )
        XCTAssertEqual(vc1Geometry.displaySize, TaptionPixelSize(width: 873, height: 480))

        let y41pGeometry = SW_FFmpegDecodeBridgeVideoGeometry(
            codedSize: TaptionPixelSize(width: 160, height: 120),
            sampleAspectRatioHorizontalSpacing: 225,
            sampleAspectRatioVerticalSpacing: 481
        )
        XCTAssertEqual(y41pGeometry.displaySize, TaptionPixelSize(width: 75, height: 120))
    }

    func testFFmpegDecodeBridgeWriterEndsAtLongestSourceDuration() throws {
        let endTime = try XCTUnwrap(
            SW_FFmpegDecodeBridgeWriterMetadata.sessionEndTime(
                videoDurationSeconds: 5,
                audioDurationSeconds: 5.024
            )
        )

        XCTAssertEqual(endTime.seconds, 5.024, accuracy: 0.001)
        XCTAssertNil(SW_FFmpegDecodeBridgeWriterMetadata.sessionEndTime(
            videoDurationSeconds: 0,
            audioDurationSeconds: nil
        ))
    }

    /// A frame-rate ceiling has to be reachable for rates that are not a whole divisor of the source's rate,
    /// because the UI only ever offers a ceiling (battery saver asks for 30) and sources run at 50, 48 and 60.
    func testDecodedFrameDecimationKeepsTheRequestedRate() {
        func keptCount(ratio: Double, frameCount: Int) -> Int {
            (0..<frameCount).reduce(into: 0) { kept, index in
                if SW_AV1FrameWriterContext.keepsDecodedFrame(index: index, ratio: ratio) {
                    kept += 1
                }
            }
        }

        // Half the frames for 60 → 30, and the first frame is always kept so the clip does not start empty.
        XCTAssertEqual(keptCount(ratio: 0.5, frameCount: 1_000), 500)
        XCTAssertEqual(keptCount(ratio: 0.6, frameCount: 1_000), 600)
        XCTAssertEqual(keptCount(ratio: 0.8, frameCount: 1_000), 800)
        XCTAssertTrue(SW_AV1FrameWriterContext.keepsDecodedFrame(index: 0, ratio: 0.5))
        // No ceiling means nothing is dropped.
        XCTAssertEqual(keptCount(ratio: 1, frameCount: 240), 240)
    }

    func testFFmpegDecodeBridgeWriterHoldsLastFrameThroughDeclaredDuration() {
        XCTAssertEqual(
            SW_FFmpegDecodeBridgeWriterMetadata.expectedFrameCount(
                durationSeconds: 5,
                frameRate: 1,
                maximumFrameCount: 0
            ),
            5
        )
        XCTAssertEqual(
            SW_FFmpegDecodeBridgeWriterMetadata.expectedFrameCount(
                durationSeconds: 5,
                frameRate: 1,
                maximumFrameCount: 3
            ),
            3
        )
    }

    func testKnownDeviceFailuresPreferBundledDecodeBridge() {
        XCTAssertEqual(
            SW_AV1HEVCTranscoder.bundledDecodeBridgePreferredSourceCodecs,
            Set([
                .dv,
                .dvcPro,
                .losslessJPEG,
                .mpeg4Visual,
                .microsoftMPEG4V3,
                .microsoftRLE,
                .quickTimeGraphics,
                .r10k,
                .r210,
                .realVideo1,
                .realVideo,
                .snow,
                .utVideo,
                .wmv
            ])
        )
    }

    func testQuickTimeVideoSoftwareHEVCConfigurationAllowsLegacyFrameHold() throws {
        let rpzaAsset = makeAsset(
            sourceCodec: .quickTimeVideo,
            displaySize: TaptionPixelSize(width: 160, height: 120),
            frameRate: TaptionRationalFrameRate(numerator: 21, denominator: 2),
            duration: 2.666667
        )
        let av1Asset = makeAsset(sourceCodec: .av1)

        let rpzaConfiguration = try SW_AV1HEVCTranscodeConfiguration.make(
            asset: rpzaAsset,
            outputURL: URL(fileURLWithPath: "/tmp/rpza.mp4"),
            options: .preservingSource(outputCodec: .hevc, container: .mp4)
        )
        let av1Configuration = try SW_AV1HEVCTranscodeConfiguration.make(
            asset: av1Asset,
            outputURL: URL(fileURLWithPath: "/tmp/av1.mp4"),
            options: .preservingSource(outputCodec: .hevc, container: .mp4)
        )

        XCTAssertTrue(rpzaConfiguration.allowsLegacyFrameHoldToPreserveDuration)
        XCTAssertEqual(rpzaConfiguration.expectedFrameCount, 28)
        XCTAssertFalse(av1Configuration.allowsLegacyFrameHoldToPreserveDuration)
    }

    func testSoftwareHEVCConfigurationDoesNotFrameLimitUnknownDurationSources() throws {
        let asset = makeAsset(
            sourceCodec: .h261,
            displaySize: TaptionPixelSize(width: 176, height: 144),
            duration: 0
        )
        let unknownDurationAsset = TaptionVideoAsset(
            displayName: asset.displayName,
            location: asset.location,
            container: .rawElementaryStream,
            duration: nil,
            videoTrack: asset.videoTrack,
            audioTracks: [],
            fingerprint: asset.fingerprint
        )

        let configuration = try SW_AV1HEVCTranscodeConfiguration.make(
            asset: unknownDurationAsset,
            outputURL: URL(fileURLWithPath: "/tmp/h261.mp4"),
            options: .preservingSource(outputCodec: .hevc, container: .mp4)
        )

        XCTAssertFalse(configuration.limitsToExpectedFrameCount)
        XCTAssertGreaterThan(configuration.expectedFrameCount, 1)
        XCTAssertEqual(configuration.duration.seconds, 0)
    }

    func testSingleAssetPlanUsesSelectedAudioOutputCodec() throws {
        let asset = TaptionVideoAsset(
            displayName: "vp9-opus.webm",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .webm,
            duration: 2,
            videoTrack: TaptionVideoTrackInfo(
                codec: .vp9,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: [
                TaptionAudioTrackInfo(
                    codec: .opus,
                    channelCount: 2,
                    sampleRate: 48_000,
                    estimatedBitrate: 192_000
                )
            ]
        )
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            audioCodec: .flac,
            container: .mp4
        )

        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/vp9-opus.webm"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/vp9-opus_taption.mp4"),
            outputPolicy: outputPolicy
        )

        XCTAssertEqual(plan.outputPolicy.audioCodec, .flac)
        XCTAssertEqual(plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac))
        XCTAssertEqual(plan.audioPlan?.options.outputCodec, .flac)
        XCTAssertEqual(plan.audioPlan?.options.outputContainer, .mp4)
        XCTAssertTrue(plan.audioPlan?.commandPlan?.arguments.contains("flac") == true)
        XCTAssertTrue(plan.videoCommandPlan?.arguments.contains("flac") == true)
    }

    func testSingleAssetPlanCarriesSourcePreservingAudioTranscodePlan() {
        let asset = TaptionVideoAsset(
            displayName: "vp9-opus.webm",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .webm,
            duration: 2,
            videoTrack: TaptionVideoTrackInfo(
                codec: .vp9,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: [
                TaptionAudioTrackInfo(
                    codec: .opus,
                    channelCount: 6,
                    sampleRate: 48_000,
                    estimatedBitrate: 512_000
                )
            ]
        )

        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/vp9-opus.webm"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/vp9-opus_taption.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )

        let audioPlan = plan.audioPlan
        XCTAssertEqual(audioPlan?.trackIndex, 0)
        XCTAssertEqual(audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .aac))
        XCTAssertEqual(audioPlan?.routeSelection.support, .softwareTranscode)
        XCTAssertEqual(audioPlan?.shortDisplayName, "SW")
        XCTAssertEqual(audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertTrue(audioPlan?.isRunnableInCurrentBuild == true)
        XCTAssertEqual(audioPlan?.options.sampleRate, 48_000)
        XCTAssertEqual(audioPlan?.options.channelCount, 6)
        XCTAssertEqual(audioPlan?.options.targetBitrate, 512_000)
        XCTAssertEqual(audioPlan?.readiness.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(audioPlan?.readiness.encodeBackend, .appleAVAssetExport)
        XCTAssertNil(audioPlan?.commandPlan)
    }

    func testSingleAssetSoftwareCommandPlanUsesAudioPlanPreservingOptions() throws {
        let asset = TaptionVideoAsset(
            displayName: "vp9-opus.webm",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .webm,
            duration: 2,
            videoTrack: TaptionVideoTrackInfo(
                codec: .vp9,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: [
                TaptionAudioTrackInfo(
                    codec: .opus,
                    channelCount: 6,
                    sampleRate: 48_000,
                    estimatedBitrate: 512_000
                )
            ]
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/vp9-opus.webm"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/vp9-opus_taption.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )

        let commandPlan = try SW_FFmpegCodecCommandPlanner.makeSingleAssetCommandPlan(plan: plan)

        XCTAssertEqual(commandPlan, plan.videoCommandPlan)
        XCTAssertEqual(commandPlan.routeSummary, "VP9 to H.265 / HEVC")
        XCTAssertTrue(commandPlan.arguments.contains("-map"))
        XCTAssertTrue(commandPlan.arguments.contains("0:a?"))
        XCTAssertTrue(commandPlan.arguments.contains("libx265"))
        XCTAssertTrue(commandPlan.arguments.contains("-c:a"))
        XCTAssertTrue(commandPlan.arguments.contains("aac"))
        XCTAssertTrue(commandPlan.arguments.contains("-ar"))
        XCTAssertTrue(commandPlan.arguments.contains("48000"))
        XCTAssertTrue(commandPlan.arguments.contains("-ac"))
        XCTAssertTrue(commandPlan.arguments.contains("6"))
        XCTAssertTrue(commandPlan.arguments.contains("-b:a"))
        XCTAssertTrue(commandPlan.arguments.contains("512000"))
        XCTAssertFalse(commandPlan.arguments.contains("-an"))
    }

    func testSingleAssetPlanOmitsVideoCommandPlanWhenOutputEncoderIsMissing() {
        let asset = makeAsset(sourceCodec: .h264)

        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/h264.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/h264-proresraw.mov"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .proResRaw, container: .mov)
        )

        XCTAssertEqual(plan.codecRoute, TaptionCodecRoute(sourceCodec: .h264, outputCodec: .proResRaw))
        XCTAssertEqual(plan.codecExecutionKind, .unsupported)
        XCTAssertNil(plan.videoCommandPlan)
    }

    func testSingleAssetPlanCarriesAudioCopyPlanWhenContainerAllowsIt() {
        let asset = makeAsset(sourceCodec: .h264)

        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/h264-aac.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/h264-aac_taption.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )

        XCTAssertEqual(plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .aac))
        XCTAssertEqual(plan.audioPlan?.routeSelection.support, .copy)
        XCTAssertEqual(plan.audioPlan?.readiness.readiness, .copyInCurrentBuild)
        XCTAssertTrue(plan.audioPlan?.shouldCopy == true)
        XCTAssertTrue(plan.audioPlan?.isRunnableInCurrentBuild == true)
        XCTAssertTrue(plan.audioPlan?.commandPlan?.arguments.contains("copy") == true)
    }

}
