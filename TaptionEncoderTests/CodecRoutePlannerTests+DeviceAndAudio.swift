//
//  CodecRoutePlannerTests+DeviceAndAudio.swift
//  Tests 7868-9731 of the original CodecRoutePlannerTests.swift, moved here
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
    func testVideoExecutionReadinessReportSeparatesCurrentBuildCommandPlansAndUnsupportedRoutes() {
        let report = TaptionVideoCodecExecutionReadinessReporter.makeReport(outputContainer: .mp4)
        let expectedRouteCount = TaptionCodecRegistry.universalSourceCodecs.count
            * TaptionCodecRegistry.universalOutputCodecs.count

        XCTAssertEqual(report.routeCount, expectedRouteCount)
        XCTAssertTrue(report.allRoutesHaveExecutionPath)
        XCTAssertFalse(report.allRoutesRunnableInCurrentBuild)
        XCTAssertEqual(report.runnableInCurrentBuildRouteCount, TaptionCodecRegistry.softwareImplementedRoutes.count)
        XCTAssertEqual(report.implementedRouteCount, TaptionCodecRegistry.softwareImplementedRoutes.count)
        XCTAssertGreaterThan(report.commandPlanOnlyRouteCount, 0)
        XCTAssertEqual(report.blockedMissingSoftwareEncoderRouteCount, 0)
        XCTAssertEqual(
            Set(report.blockedOutputCodecs),
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs)
        )

        let implementedItem = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc),
            outputContainer: .mp4
        )
        XCTAssertEqual(implementedItem.readiness, .implementedInCurrentBuild)
        XCTAssertTrue(implementedItem.isRunnableInCurrentBuild)
        XCTAssertTrue(implementedItem.hasCommandPlan)

        let motionJPEGItem = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .motionJPEG, outputCodec: .hevc),
            outputContainer: .mp4
        )
        XCTAssertEqual(motionJPEGItem.readiness, .implementedInCurrentBuild)
        XCTAssertTrue(motionJPEGItem.isRunnableInCurrentBuild)
        XCTAssertTrue(motionJPEGItem.hasCommandPlan)

        let wmvItem = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .wmv, outputCodec: .hevc),
            outputContainer: .mp4
        )
        XCTAssertEqual(wmvItem.readiness, .implementedInCurrentBuild)
        XCTAssertTrue(wmvItem.isRunnableInCurrentBuild)
        XCTAssertTrue(wmvItem.hasCommandPlan)

        for codec in [TaptionVideoCodec.microsoftVideo1, .asusV1, .asusV2, .flashScreenVideo, .flashScreenVideo2, .zmbv, .cljr, .ffv1] {
            let item = TaptionVideoCodecExecutionReadinessReporter.item(
                for: TaptionCodecRoute(sourceCodec: codec, outputCodec: .hevc),
                outputContainer: .mp4
            )
            XCTAssertEqual(item.readiness, .implementedInCurrentBuild, codec.displayName)
            XCTAssertTrue(item.isRunnableInCurrentBuild, codec.displayName)
            XCTAssertTrue(item.hasCommandPlan, codec.displayName)
        }

        let bundledBridgeItem = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .vc1, outputCodec: .hevc),
            outputContainer: .mp4
        )
        XCTAssertEqual(bundledBridgeItem.readiness, .implementedInCurrentBuild)
        XCTAssertTrue(bundledBridgeItem.isRunnableInCurrentBuild)
        XCTAssertTrue(bundledBridgeItem.hasCommandPlan)
        XCTAssertEqual(bundledBridgeItem.commandBackend, .ffmpegFamily)

        let unsupportedItem = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .unknown, outputCodec: .hevc),
            outputContainer: .mp4
        )
        XCTAssertEqual(unsupportedItem.readiness, .unsupported)
        XCTAssertFalse(unsupportedItem.isRunnableInCurrentBuild)
        XCTAssertFalse(unsupportedItem.hasCommandPlan)
        XCTAssertTrue(unsupportedItem.blockingReason?.contains("not in the current support roadmap") == true)
    }

    func testVideoExecutionReadinessReportPromotesCommandPlansWhenBroadBackendShips() {
        let item = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .proRes, outputCodec: .hevc),
            outputContainer: .mp4,
            broadSoftwareBackendExecutable: true
        )
        let report = TaptionVideoCodecExecutionReadinessReporter.makeReport(
            outputContainer: .mp4,
            broadSoftwareBackendExecutable: true
        )

        XCTAssertEqual(item.readiness, .softwareBackendExecutable)
        XCTAssertTrue(item.isRunnableInCurrentBuild)
        XCTAssertTrue(item.hasCommandPlan)
        XCTAssertEqual(report.commandPlanOnlyRouteCount, 0)
        XCTAssertGreaterThan(report.softwareBackendExecutableRouteCount, 0)
        XCTAssertTrue(report.allRoutesRunnableInCurrentBuild)
        XCTAssertEqual(
            Set(report.blockedOutputCodecs),
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs)
        )
    }

    func testAudioExecutionReadinessReportSeparatesCurrentBuildCommandPlansAndEncoderGaps() {
        let report = TaptionAudioCodecExecutionReadinessReporter.makeReport(outputContainer: .mp4)
        let expectedRouteCount = TaptionAudioCodecRoutePlanner.universalAudioCodecs.count
            * TaptionAudioCodecRoutePlanner.universalAudioCodecs.count

        XCTAssertEqual(report.routeCount, expectedRouteCount)
        XCTAssertTrue(report.allRoutesHaveExecutionPath)
        XCTAssertFalse(report.allRoutesRunnableInCurrentBuild)
        XCTAssertEqual(
            Set(report.blockedOutputCodecs),
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs)
        )

        let copyItem = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .aac),
            outputContainer: .mp4
        )
        XCTAssertEqual(copyItem.readiness, .copyInCurrentBuild)
        XCTAssertTrue(copyItem.isRunnableInCurrentBuild)
        XCTAssertTrue(copyItem.hasCommandPlan)

        let nativeItem = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .pcm),
            outputContainer: .mp4
        )
        XCTAssertEqual(nativeItem.readiness, .nativeTranscodeInCurrentBuild)
        XCTAssertTrue(nativeItem.isRunnableInCurrentBuild)
        XCTAssertFalse(nativeItem.hasCommandPlan)

        let commandOnlyItem = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac),
            outputContainer: .mp4
        )
        XCTAssertEqual(commandOnlyItem.readiness, .commandPlanOnly)
        XCTAssertFalse(commandOnlyItem.isRunnableInCurrentBuild)
        XCTAssertTrue(commandOnlyItem.hasCommandPlan)
        XCTAssertEqual(commandOnlyItem.commandBackend, .ffmpegFamily)

        let blockedItem = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .xheAAC),
            outputContainer: .mp4
        )
        XCTAssertEqual(blockedItem.readiness, .blockedMissingSoftwareEncoder)
        XCTAssertFalse(blockedItem.isRunnableInCurrentBuild)
        XCTAssertFalse(blockedItem.hasCommandPlan)
        XCTAssertTrue(blockedItem.blockingReason?.contains("xHE-AAC") == true)
    }

    func testAudioExecutionReadinessReportPromotesCommandPlansWhenBroadBackendShips() {
        let item = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac),
            outputContainer: .mp4,
            broadSoftwareBackendExecutable: true
        )
        let report = TaptionAudioCodecExecutionReadinessReporter.makeReport(
            outputContainer: .mp4,
            broadSoftwareBackendExecutable: true
        )

        XCTAssertEqual(item.readiness, .softwareBackendExecutable)
        XCTAssertTrue(item.isRunnableInCurrentBuild)
        XCTAssertTrue(item.hasCommandPlan)
        XCTAssertEqual(report.commandPlanOnlyRouteCount, 0)
        XCTAssertGreaterThan(report.softwareBackendExecutableRouteCount, 0)
        XCTAssertFalse(report.allRoutesRunnableInCurrentBuild)
        XCTAssertEqual(
            Set(report.blockedOutputCodecs),
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs)
        )
    }

    func testUniversalAudioCommandPlannerTracksEveryOutputCodecAsPlannableOrGap() {
        let represented = Set(SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs)
            .union(SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs)

        XCTAssertEqual(represented, Set(TaptionAudioCodecRoutePlanner.universalAudioCodecs))
        XCTAssertTrue(SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs.contains(.opus))
        XCTAssertTrue(SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs.contains(.flac))
        XCTAssertTrue(SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs.contains(.xheAAC))
        XCTAssertTrue(SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs.contains(.amr))
    }

    func testUniversalAudioCommandPlannerBuildsEveryPlannableSourceOutputPair() throws {
        for sourceCodec in TaptionAudioCodecRoutePlanner.universalAudioCodecs {
            for outputCodec in SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs {
                let route = TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
                let request = TaptionAudioCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/audio-\(sourceCodec.rawValue).mkv"),
                    outputURL: URL(fileURLWithPath: "/tmp/audio-\(outputCodec.rawValue).mp4"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, outputContainer: .mp4)
                )

                let plan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: request)

                XCTAssertEqual(plan.backend, .ffmpegFamily, route.displayName)
                XCTAssertEqual(plan.routeSummary, route.displayName, route.displayName)
                XCTAssertTrue(plan.arguments.contains("-c:a"), route.displayName)
                XCTAssertEqual(
                    plan.arguments.last,
                    "/tmp/audio-\(outputCodec.rawValue).mp4",
                    route.displayName
                )
            }
        }
    }

    func testUniversalAudioCommandPlannerRejectsEveryUnsupportedOutputCodec() {
        for sourceCodec in TaptionAudioCodecRoutePlanner.universalAudioCodecs {
            for outputCodec in SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs {
                let route = TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
                let request = TaptionAudioCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/audio-\(sourceCodec.rawValue).mkv"),
                    outputURL: URL(fileURLWithPath: "/tmp/audio-\(outputCodec.rawValue).mp4"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, outputContainer: .mp4)
                )

                XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: request), route.displayName) { error in
                    XCTAssertEqual(
                        error as? SW_FFmpegCodecCommandPlannerError,
                        .audioEncoderUnavailable(outputCodec),
                        route.displayName
                    )
                }
            }
        }
    }

    func testUniversalAudioCommandPlannerReportsEncoderGaps() {
        let route = TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .xheAAC)
        let request = TaptionAudioCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: route,
            options: .preservingSource(outputCodec: .xheAAC, outputContainer: .mp4)
        )

        XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: request)) { error in
            XCTAssertEqual(
                error as? SW_FFmpegCodecCommandPlannerError,
                .audioEncoderUnavailable(.xheAAC)
            )
        }
    }

    func testAudioCodecCopyKeepsCompatibleAACInMP4() {
        let selection = TaptionAudioCodecRoutePlanner.selectRoute(
            sourceCodec: .aac,
            outputCodec: .aac,
            outputContainer: .mp4
        )

        XCTAssertEqual(selection.support, .copy)
        XCTAssertTrue(selection.shouldCopy)
        XCTAssertNil(selection.decodeBackend)
        XCTAssertNil(selection.encodeBackend)
    }

    func testAudioCodecSoftwareDecodeFeedsAACForOpus() {
        let selection = TaptionAudioCodecRoutePlanner.selectRoute(
            sourceCodec: .opus,
            outputCodec: .aac,
            outputContainer: .mp4
        )

        XCTAssertEqual(selection.support, .softwareTranscode)
        XCTAssertFalse(selection.shouldCopy)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .appleAVAssetExport)
    }

    func testDeviceCodecReportIncludesAudioNativeCapabilities() {
        let report = HW_CodecCapabilityProbe.makeReport(
            probeSize: TaptionPixelSize(width: 1280, height: 720),
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let audioCapabilities = Dictionary(
            uniqueKeysWithValues: report.audioCapabilities.map { ($0.audioCodec, $0) }
        )

        XCTAssertEqual(report.audioCapabilities.count, TaptionAudioCodecRoutePlanner.universalAudioCodecs.count)
        XCTAssertEqual(audioCapabilities[.aac]?.nativeDecodeSupported, true)
        XCTAssertEqual(audioCapabilities[.aac]?.nativeEncodeSupported, true)
        XCTAssertEqual(audioCapabilities[.aac]?.mp4CopySupported, true)
        XCTAssertEqual(audioCapabilities[.opus]?.nativeDecodeSupported, false)
        XCTAssertEqual(audioCapabilities[.opus]?.nativeEncodeSupported, false)
        XCTAssertEqual(audioCapabilities[.opus]?.mp4CopySupported, false)
    }

    func testCaptureRuntimeDeviceCodecReportWhenRequested() throws {
        let snapshot = HW_DeviceCodecReportStore.makeSnapshot()
        let data = try HW_DeviceCodecReportStore.encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = HW_DeviceCodecReportStore.fileName(for: snapshot)
        attachment.lifetime = .keepAlways
        add(attachment)

        if snapshot.report.modelIdentifier != "arm64" {
            print("TAPTION_DEVICE_CODEC_REPORT_JSON_BEGIN")
            print(json)
            print("TAPTION_DEVICE_CODEC_REPORT_JSON_END")
        }

        XCTAssertFalse(snapshot.report.modelIdentifier.isEmpty)
        XCTAssertFalse(snapshot.report.videoCapabilities.isEmpty)
        XCTAssertFalse(snapshot.report.audioCapabilities.isEmpty)
        XCTAssertEqual(snapshot.report.probeResolution, HW_CodecCapabilityProbe.defaultProbeSize)
        XCTAssertEqual(snapshot.launchInputReadinessCatalog?.outputVideoCodec, .hevc)
        XCTAssertEqual(snapshot.launchInputReadinessCatalog?.outputContainers, [.mp4, .mov])
    }

    func testDeviceCodecReportReconcilesKnownModelWithStaticMatrix() {
        let expectedDecode: Set<TaptionVideoCodec> = [
            .h264,
            .hevc,
            .hevcWithAlpha,
            .dolbyVisionHEVC,
            .av1,
            .proRes
        ]
        let expectedEncode: Set<TaptionVideoCodec> = [
            .h264,
            .hevc,
            .proRes
        ]
        let report = syntheticDeviceCodecReport(
            modelIdentifier: "iPhone16,1",
            decodeCodecs: expectedDecode,
            encodeCodecs: expectedEncode
        )

        let reconciliation = HW_DeviceCodecReportReconciler.reconcile(report: report)

        XCTAssertEqual(report.modelDisplayName, "iPhone 15 Pro (iPhone16,1)")
        XCTAssertTrue(reconciliation.isKnownModel)
        XCTAssertTrue(reconciliation.isConsistentWithStaticMatrix)
        XCTAssertEqual(reconciliation.matchedMarketingName, "iPhone 15 Pro")
        XCTAssertEqual(reconciliation.matchedProfileID, "apple_a17pro_av1_decode")
        XCTAssertEqual(Set(reconciliation.expectedHardwareDecodeCodecs), expectedDecode)
        XCTAssertEqual(Set(reconciliation.expectedHardwareEncodeCodecs), expectedEncode)
        XCTAssertTrue(reconciliation.missingExpectedDecodeCodecs.isEmpty)
        XCTAssertTrue(reconciliation.unexpectedDecodeCodecs.isEmpty)
    }

    func testDeviceCodecReportDisplaysIPhone14ProMarketingName() {
        let report = syntheticDeviceCodecReport(
            modelIdentifier: "iPhone15,2",
            decodeCodecs: [.h264, .hevc, .proRes],
            encodeCodecs: [.h264, .hevc, .proRes]
        )

        XCTAssertEqual(report.modelDisplayName, "iPhone 14 Pro (iPhone15,2)")
    }

    func testDeviceCodecReportReconciliationFlagsUnknownAndDivergentReports() {
        let unknownReport = syntheticDeviceCodecReport(
            modelIdentifier: "iPhone99,99",
            decodeCodecs: [.h264],
            encodeCodecs: [.h264]
        )
        let divergentReport = syntheticDeviceCodecReport(
            modelIdentifier: "iPad7,11",
            decodeCodecs: [.h264, .hevc],
            encodeCodecs: []
        )

        let unknown = HW_DeviceCodecReportReconciler.reconcile(report: unknownReport)
        let divergent = HW_DeviceCodecReportReconciler.reconcile(report: divergentReport)

        XCTAssertFalse(unknown.isKnownModel)
        XCTAssertFalse(unknown.isConsistentWithStaticMatrix)
        XCTAssertEqual(unknown.statusSummary, "Runtime model is not in the static matrix yet.")

        XCTAssertTrue(divergent.isKnownModel)
        XCTAssertFalse(divergent.isConsistentWithStaticMatrix)
        XCTAssertEqual(divergent.matchedProfileID, "apple_ipados18_legacy_a10_h264")
        XCTAssertEqual(divergent.missingExpectedEncodeCodecs, [.h264])
        XCTAssertEqual(divergent.unexpectedDecodeCodecs, [.hevc])
    }

    func testDeviceCodecReportArchiveSummaryFindsUnknownAndDivergentSnapshots() {
        let matchingSnapshot = HW_DeviceCodecReportSnapshot(
            id: "matching-known",
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 0),
            report: syntheticDeviceCodecReport(
                modelIdentifier: "iPhone16,1",
                decodeCodecs: [
                    .h264,
                    .hevc,
                    .hevcWithAlpha,
                    .dolbyVisionHEVC,
                    .av1,
                    .proRes
                ],
                encodeCodecs: [
                    .h264,
                    .hevc,
                    .proRes
                ]
            ),
            routeSimulationSummary: HW_CodecRouteSimulator.summary(),
            staticMatrixReconciliation: nil
        )
        let unknownSnapshot = HW_DeviceCodecReportSnapshot(
            id: "unknown-model",
            schemaVersion: 2,
            createdAt: Date(timeIntervalSince1970: 1),
            report: syntheticDeviceCodecReport(
                modelIdentifier: "iPhone99,99",
                decodeCodecs: [.h264],
                encodeCodecs: [.h264]
            ),
            routeSimulationSummary: HW_CodecRouteSimulator.summary(),
            staticMatrixReconciliation: nil
        )
        let divergentSnapshot = HW_DeviceCodecReportSnapshot(
            id: "divergent-known",
            schemaVersion: 2,
            createdAt: Date(timeIntervalSince1970: 2),
            report: syntheticDeviceCodecReport(
                modelIdentifier: "iPad7,11",
                decodeCodecs: [.h264, .hevc],
                encodeCodecs: []
            ),
            routeSimulationSummary: HW_CodecRouteSimulator.summary(),
            staticMatrixReconciliation: nil
        )

        let summary = HW_DeviceCodecReportArchiveAnalyzer.summarize([
            unknownSnapshot,
            matchingSnapshot,
            divergentSnapshot
        ])

        XCTAssertEqual(summary.snapshotCount, 3)
        XCTAssertEqual(summary.knownModelSnapshotCount, 2)
        XCTAssertEqual(summary.unknownModelIdentifiers, ["iPhone99,99"])
        XCTAssertEqual(summary.consistentSnapshotIDs, ["matching-known"])
        XCTAssertEqual(summary.divergentSnapshotIDs, ["divergent-known"])
        XCTAssertTrue(summary.hasSnapshots)
        XCTAssertTrue(summary.needsStaticMatrixUpdates)
        XCTAssertEqual(summary.divergences.count, 1)
        XCTAssertEqual(summary.divergences.first?.snapshotID, "divergent-known")
        XCTAssertEqual(summary.divergences.first?.matchedProfileID, "apple_ipados18_legacy_a10_h264")
        XCTAssertEqual(summary.divergences.first?.missingExpectedEncodeCodecs, [.h264])
        XCTAssertEqual(summary.divergences.first?.unexpectedDecodeCodecs, [.hevc])
    }

    func testDeviceCodecReportStoreRoundTripsSnapshotJSON() throws {
        let report = HW_CodecCapabilityProbe.makeReport(
            probeSize: TaptionPixelSize(width: 1280, height: 720),
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let summary = HW_CodecRouteSimulator.summary()
        let snapshot = HW_DeviceCodecReportStore.makeSnapshot(
            report: report,
            routeSimulationSummary: summary,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let data = try HW_DeviceCodecReportStore.encode(snapshot)
        let decoded = try HW_DeviceCodecReportStore.decode(data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaVersion, HW_DeviceCodecReportSnapshot.currentSchemaVersion)
        XCTAssertEqual(decoded.universalCodecCompletionAudit?.stage, .allToAllPlanningLocked)
        XCTAssertTrue(decoded.universalCodecCompletionAudit?.universalPlanningIsLocked == true)
        XCTAssertTrue(decoded.universalCodecCompletionAudit?.outputSelectionCoverageIsPassing == true)
        XCTAssertEqual(
            decoded.universalCodecCompletionAudit?.videoOutputSelectionCount,
            decoded.outputReadinessCatalog?.outputSelectionCount
        )
        XCTAssertEqual(
            decoded.universalCodecCompletionAudit?.audioOutputSelectionCount,
            decoded.audioOutputReadinessCatalog?.outputSelectionCount
        )
        XCTAssertEqual(decoded.outputReadinessCatalog?.defaultOutputState, .implemented)
        XCTAssertTrue(decoded.outputReadinessCatalog?.outputSelectionCoverageIsPassing == true)
        XCTAssertEqual(decoded.audioOutputReadinessCatalog?.defaultOutputState, .implemented)
        XCTAssertTrue(decoded.audioOutputReadinessCatalog?.outputSelectionCoverageIsPassing == true)
        XCTAssertEqual(
            decoded.launchInputReadinessCatalog,
            TaptionLaunchSupportCatalog.makeInputReadinessReport()
        )
        XCTAssertEqual(decoded.launchInputReadinessCatalog?.outputVideoCodec, .hevc)
        XCTAssertEqual(decoded.launchInputReadinessCatalog?.outputContainers, [.mp4, .mov])
        XCTAssertTrue(decoded.launchInputReadinessCatalog?.executableNowVideoCodecs.contains(.h261) == true)
        XCTAssertFalse(decoded.launchInputReadinessCatalog?.plannedVideoCodecs.contains(.h261) == true)
        for codec in [TaptionVideoCodec.realVideo1, .realVideo, .flashVideo, .microsoftMPEG4V2, .microsoftMPEG4V3, .jpeg2000, .jpegLS, .losslessJPEG, .animation, .cinepak, .sorensonVideo, .sorensonVideo3, .quickTimeVideo, .theora, .roqVideo, .microsoftVideo1, .asusV1, .asusV2, .flashScreenVideo, .flashScreenVideo2, .zmbv, .cljr, .snow, .ffv1, .huffYUV, .utVideo, .magicYUV, .dvcPro, .dvcProHD, .dv, .cineForm, .dnxhd, .pngVideo, .r10k, .v308, .v210, .r210, .v408, .v410, .microsoftRLE, .quickTimeGraphics, .yuv4, .rawVideo] {
            XCTAssertTrue(decoded.launchInputReadinessCatalog?.executableNowVideoCodecs.contains(codec) == true, codec.displayName)
            XCTAssertFalse(decoded.launchInputReadinessCatalog?.plannedVideoCodecs.contains(codec) == true, codec.displayName)
        }
        XCTAssertTrue(decoded.launchInputReadinessCatalog?.executableNowVideoCodecs.contains(.vc1) == true)
        XCTAssertFalse(decoded.launchInputReadinessCatalog?.plannedVideoCodecs.contains(.vc1) == true)
        XCTAssertTrue(decoded.launchInputReadinessCatalog?.executableNowVideoCodecs.contains(.y41p) == true)
        XCTAssertFalse(decoded.launchInputReadinessCatalog?.plannedVideoCodecs.contains(.y41p) == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"routeSimulationSummary\"") == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"staticMatrixReconciliation\"") == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"universalCodecCompletionAudit\"") == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"launchInputReadinessCatalog\"") == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"outputSelectionCoverageIsPassing\"") == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"outputReadinessCatalog\"") == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"audioOutputReadinessCatalog\"") == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"videoCapabilities\"") == true)
    }

    func testDeviceCodecReportStoreDecodesLegacyCompletionAuditWithoutSelectorFields() throws {
        let snapshot = HW_DeviceCodecReportStore.makeSnapshot(
            report: HW_CodecCapabilityProbe.makeReport(
                probeSize: TaptionPixelSize(width: 1280, height: 720),
                generatedAt: Date(timeIntervalSince1970: 0)
            ),
            routeSimulationSummary: HW_CodecRouteSimulator.summary(),
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let data = try HW_DeviceCodecReportStore.encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var audit = try XCTUnwrap(
            object["universalCodecCompletionAudit"] as? [String: Any]
        )
        [
            "videoOutputSelectionCount",
            "audioOutputSelectionCount",
            "videoOutputImplementedSelectionCount",
            "audioOutputImplementedSelectionCount",
            "videoOutputCommandPlanReadySelectionCount",
            "audioOutputCommandPlanReadySelectionCount",
            "videoOutputPlannedSelectionCount",
            "audioOutputPlannedSelectionCount",
            "videoOutputBlockedSelectionCount",
            "audioOutputBlockedSelectionCount",
            "videoOutputSelectionCoverageIsPassing",
            "audioOutputSelectionCoverageIsPassing"
        ].forEach {
            audit.removeValue(forKey: $0)
        }
        object["universalCodecCompletionAudit"] = audit

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try HW_DeviceCodecReportStore.decode(legacyData)

        XCTAssertEqual(decoded.universalCodecCompletionAudit?.stage, .allToAllPlanningLocked)
        XCTAssertTrue(decoded.universalCodecCompletionAudit?.outputSelectionCoverageIsPassing == true)
        XCTAssertEqual(
            decoded.universalCodecCompletionAudit?.videoOutputSelectionCount,
            TaptionCodecOutputCatalog.makeReadinessReport().outputSelectionCount
        )
        XCTAssertEqual(
            decoded.universalCodecCompletionAudit?.audioOutputSelectionCount,
            TaptionAudioCodecOutputCatalog.makeReadinessReport().outputSelectionCount
        )
    }

    func testDeviceCodecReportStoreSavesAndLoadsSnapshots() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HWDeviceCodecReportStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let report = HW_CodecCapabilityProbe.makeReport(
            probeSize: TaptionPixelSize(width: 640, height: 360),
            generatedAt: Date(timeIntervalSince1970: 1)
        )
        let snapshot = HW_DeviceCodecReportStore.makeSnapshot(
            report: report,
            routeSimulationSummary: HW_CodecRouteSimulator.summary(),
            createdAt: Date(timeIntervalSince1970: 1)
        )

        let fileURL = try HW_DeviceCodecReportStore.save(
            snapshot: snapshot,
            to: directoryURL
        )
        let loadedSnapshots = try HW_DeviceCodecReportStore.loadSnapshots(
            from: directoryURL
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(fileURL.lastPathComponent.hasPrefix("hw-codec-report-"))
        XCTAssertEqual(loadedSnapshots, [snapshot])
        XCTAssertEqual(loadedSnapshots.first?.universalCodecCompletionAudit?.contractName, "All Inputs to H.265 Codec Mesh")
        XCTAssertTrue(loadedSnapshots.first?.universalCodecCompletionAudit?.outputSelectionCoverageIsPassing == true)
        XCTAssertEqual(loadedSnapshots.first?.outputReadinessCatalog?.defaultOutputCodec, .hevc)
        XCTAssertTrue(loadedSnapshots.first?.outputReadinessCatalog?.outputSelectionCoverageIsPassing == true)
        XCTAssertEqual(loadedSnapshots.first?.audioOutputReadinessCatalog?.defaultOutputCodec, .aac)
        XCTAssertTrue(loadedSnapshots.first?.audioOutputReadinessCatalog?.outputSelectionCoverageIsPassing == true)
    }

    func testAudioFixtureCoverageTracksPendingCodecs() {
        XCTAssertEqual(SW_AudioCodecSupportCatalog.fixtureStatus(for: .aac), .generated)
        XCTAssertEqual(SW_AudioCodecSupportCatalog.fixtureStatus(for: .opus), .generated)
        XCTAssertEqual(SW_AudioCodecSupportCatalog.fixtureStatus(for: .xheAAC), .pendingRealOrAlternateGenerator)
        XCTAssertEqual(SW_AudioCodecSupportCatalog.fixtureStatus(for: .amr), .pendingRealOrAlternateGenerator)
    }

    func testSoftwareBackendRegistryCoversUniversalVideoDecodeAndEncodeTargets() {
        for codec in TaptionCodecRegistry.universalSourceCodecs {
            XCTAssertNotNil(
                SW_SoftwareCodecBackendRegistry.preferredVideoDecodeBackend(for: codec),
                "Missing SW decode backend for \(codec.rawValue)"
            )
        }
        XCTAssertEqual(
            SW_SoftwareCodecBackendRegistry.preferredVideoDecodeBackend(for: .vc1),
            .ffmpegFamily
        )
        XCTAssertEqual(
            SW_SoftwareCodecBackendRegistry.currentExecutableVideoDecodeBackend(for: .vc1),
            .ffmpegFamily
        )
        XCTAssertEqual(
            SW_SoftwareCodecBackendRegistry.preferredVideoDecodeBackend(for: .y41p),
            .ffmpegFamily
        )
        XCTAssertEqual(
            SW_SoftwareCodecBackendRegistry.currentExecutableVideoDecodeBackend(for: .y41p),
            .ffmpegFamily
        )

        for codec in TaptionCodecRegistry.universalOutputCodecs {
            XCTAssertNotNil(
                SW_SoftwareCodecBackendRegistry.preferredVideoEncodeBackend(for: codec),
                "Missing SW encode backend for \(codec.rawValue)"
            )
        }
    }

    func testSoftwareBackendRegistryCoversUniversalAudioDecodeAndEncodeTargets() {
        for codec in TaptionAudioCodecRoutePlanner.universalAudioCodecs {
            XCTAssertEqual(
                SW_SoftwareCodecBackendRegistry.preferredAudioDecodeBackend(for: codec),
                .ffmpegFamily
            )
            XCTAssertEqual(
                SW_SoftwareCodecBackendRegistry.preferredAudioEncodeBackend(for: codec),
                .ffmpegFamily
            )
        }
    }

    func testBroadSoftwareBackendReadinessKeepsCurrentBuildPlanningOnly() {
        let report = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()

        XCTAssertEqual(report.backend, .ffmpegFamily)
        XCTAssertFalse(report.isBundledInCurrentBuild)
        XCTAssertFalse(report.isExecutableInCurrentBuild)
        XCTAssertTrue(report.mustRemainPlanningOnly)
        XCTAssertFalse(report.canPromoteToExecutableBackend)
        XCTAssertEqual(
            Set(report.openGates),
            Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
        )
        XCTAssertEqual(report.videoDecodeCodecCount, TaptionCodecRegistry.universalSourceCodecs.count)
        XCTAssertEqual(report.videoEncodeCodecCount, TaptionCodecRegistry.universalOutputCodecs.count)
        XCTAssertEqual(report.audioDecodeCodecCount, TaptionAudioCodecRoutePlanner.universalAudioCodecs.count)
        XCTAssertEqual(report.audioEncodeCodecCount, TaptionAudioCodecRoutePlanner.universalAudioCodecs.count)
        XCTAssertEqual(report.plannedVideoRouteCount, TaptionCodecRegistry.plannedUniversalRoutes.count)
        XCTAssertEqual(report.plannedAudioRouteCount, TaptionAudioCodecRoutePlanner.plannedUniversalRoutes.count)
        XCTAssertTrue(report.commandUnsupportedVideoOutputCodecs.isEmpty)
        XCTAssertTrue(report.commandUnsupportedAudioOutputCodecs.contains(.xheAAC))
    }

    func testBroadSoftwareBackendReadinessGatesHaveDisplayNames() {
        let displayNames = TaptionSoftwareCodecBackendReadinessGate.allCases
            .map(\.displayName)

        XCTAssertEqual(displayNames.count, TaptionSoftwareCodecBackendReadinessGate.allCases.count)
        XCTAssertTrue(displayNames.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(displayNames.contains("License review"))
        XCTAssertTrue(displayNames.contains("Open-source notice generation"))
        XCTAssertTrue(displayNames.contains("Old-device performance proof"))
    }

    func testFFmpegFamilyBackendEngineeringReviewKeepsExecutionBlocked() throws {
        let review = TaptionSoftwareCodecBackendReviewCatalog.currentFFmpegFamilyReview

        XCTAssertEqual(review.backend, .ffmpegFamily)
        XCTAssertEqual(review.statusDate, "2026-07-11")
        XCTAssertFalse(review.approvedForExecution)
        XCTAssertTrue(review.satisfiedGates.isEmpty)
        XCTAssertEqual(
            Set(review.openGates),
            Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
        )
        XCTAssertTrue(review.reviewedSourceURLs.contains("https://www.ffmpeg.org/legal.html"))
        XCTAssertTrue(review.reviewedSourceURLs.contains("https://developer.apple.com/app-store/review/guidelines/"))
        XCTAssertTrue(review.reviewedSourceURLs.contains("https://www2.iis.fraunhofer.de/AAC/xhe-aac.html"))
        XCTAssertTrue(review.reviewedSourceURLs.contains("https://www.etsi.org/resources/intellectual-property-rights/"))
        XCTAssertTrue(review.conclusion.contains("planning-only"))

        let licenseFinding = try XCTUnwrap(
            review.findings.first { $0.gate == .licenseReview }
        )
        XCTAssertEqual(licenseFinding.status, .open)
        XCTAssertTrue(licenseFinding.summary.contains("libx265"))
        XCTAssertTrue(licenseFinding.summary.contains("libx264"))
        XCTAssertTrue(licenseFinding.requiredEvidence.contains {
            $0.contains("--enable-gpl") && $0.contains("--enable-nonfree")
        })

        let appStoreFinding = try XCTUnwrap(
            review.findings.first { $0.gate == .appStorePolicyReview }
        )
        XCTAssertEqual(appStoreFinding.status, .open)
        XCTAssertTrue(appStoreFinding.summary.contains("self-contained"))
        XCTAssertTrue(appStoreFinding.requiredEvidence.contains {
            $0.contains("No runtime code download")
        })

        let audioFinding = try XCTUnwrap(
            review.findings.first { $0.gate == .audioSignalRegressionProof }
        )
        XCTAssertEqual(audioFinding.status, .open)
        XCTAssertTrue(audioFinding.summary.contains("xHE-AAC"))
        XCTAssertTrue(audioFinding.summary.contains("Y41P PCM"))
        XCTAssertTrue(audioFinding.summary.contains("no AMR-WB+ decoder"))
        XCTAssertTrue(audioFinding.requiredEvidence.contains {
            $0.contains("IPR") && $0.contains("counsel approval")
        })
    }

    func testVC1Y41PBackendDecisionSelectsSourceBuiltLGPLDecodeBridge() throws {
        let decision = TaptionFFmpegFamilyBackendDecisionCatalog.currentVC1Y41PDecision
        let selected = try XCTUnwrap(decision.selectedCandidate)

        XCTAssertEqual(decision.statusDate, "2026-07-11")
        XCTAssertEqual(selected.id, "source-built-lgpl-ffmpeg-decode-bridge")
        XCTAssertEqual(selected.status, .selected)
        XCTAssertTrue(selected.runnerShape.contains("in-process library bridge"))
        XCTAssertTrue(decision.selectedOutputPolicy.contains("H.265 / HEVC MP4/MOV"))
        XCTAssertTrue(decision.selectedOutputPolicy.contains("Do not add non-H.265 outputs"))
        XCTAssertTrue(decision.sourceURLs.contains("https://www.ffmpeg.org/legal.html"))
        XCTAssertTrue(decision.sourceURLs.contains("https://github.com/arthenica/ffmpeg-kit/wiki/License"))
        XCTAssertTrue(decision.proofBoundary.contains("iOS simulator and connected-iPad real-decoder execution proof"))
        XCTAssertTrue(decision.proofBoundary.contains("Y41P PCM audio preservation to AAC"))
        XCTAssertTrue(decision.proofBoundary.contains("not formal legal approval"))
        XCTAssertTrue(decision.proofBoundary.contains("not App Review approval"))
        XCTAssertTrue(decision.proofBoundary.contains("not public-release proof"))

        let rejectedIDs = Set(
            decision.candidates
                .filter { $0.status == .rejected }
                .map(\.id)
        )
        XCTAssertTrue(rejectedIDs.contains("prebuilt-or-archived-ffmpegkit"))
        XCTAssertTrue(rejectedIDs.contains("downloaded-ffmpeg-binary-or-plugin"))
    }

    func testFFmpegFamilyBackendReviewDoesNotCloseReadinessGates() {
        let review = TaptionSoftwareCodecBackendReviewCatalog.currentFFmpegFamilyReview
        let report = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(
            isBundledInCurrentBuild: true,
            satisfiedGates: Set(review.satisfiedGates)
        )

        XCTAssertFalse(report.isExecutableInCurrentBuild)
        XCTAssertFalse(report.canPromoteToExecutableBackend)
        XCTAssertTrue(report.mustRemainPlanningOnly)
        XCTAssertEqual(
            Set(report.openGates),
            Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
        )
    }

    func testOpenSourceNoticeCatalogSeparatesShippedToolingAndPlanningOnlyCandidates() {
        let readinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
        let shipped = TaptionOpenSourceNoticeCatalog.shippedComponents
        let tooling = TaptionOpenSourceNoticeCatalog.localDevelopmentTooling
        let candidates = TaptionOpenSourceNoticeCatalog.planningOnlyCandidates(
            readinessReport: readinessReport
        )
        let allEntries = TaptionOpenSourceNoticeCatalog.allEntries(
            readinessReport: readinessReport
        )

        XCTAssertTrue(shipped.allSatisfy(\.isShippedInCurrentBuild))
        XCTAssertTrue(shipped.allSatisfy(\.requiresFinalLicenseText))
        XCTAssertTrue(shipped.allSatisfy(\.hasFinalLicenseText))
        XCTAssertEqual(Set(shipped.map(\.category)), [.shippedComponent])
        XCTAssertTrue(shipped.contains { $0.relatedBackend == .softwareVLCDecoder })
        XCTAssertEqual(
            Set(shipped.map(\.id)),
            Set([
                "swiftvlc",
                "libvlc",
                "ffmpeg-lgpl-decode-bridge",
                "google-mobile-ads",
                "google-user-messaging-platform"
            ])
        )

        XCTAssertTrue(tooling.allSatisfy { !$0.isShippedInCurrentBuild })
        XCTAssertTrue(tooling.allSatisfy { !$0.requiresFinalLicenseText })
        XCTAssertTrue(tooling.allSatisfy(\.hasFinalLicenseText))
        XCTAssertEqual(Set(tooling.map(\.category)), [.localDevelopmentTooling])

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.category, .planningOnlyCandidate)
        XCTAssertEqual(candidates.first?.relatedBackend, .ffmpegFamily)
        XCTAssertEqual(candidates.first?.isShippedInCurrentBuild, false)
        XCTAssertEqual(candidates.first?.requiresFinalLicenseText, false)
        XCTAssertEqual(candidates.first?.hasFinalLicenseText, true)
        XCTAssertEqual(allEntries.count, shipped.count + tooling.count + candidates.count)
    }

    func testOpenSourceNoticesMatchResolvedThirdPartyPackagePins() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resolvedURL = rootURL.appendingPathComponent(
            "TaptionEncoder.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        )
        let data = try Data(contentsOf: resolvedURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pins = try XCTUnwrap(json["pins"] as? [[String: Any]])
        let pinsByIdentity = Dictionary(uniqueKeysWithValues: pins.compactMap { pin in
            (pin["identity"] as? String).map { ($0, pin) }
        })
        let expectations: [(identity: String, noticeID: String, version: String, revision: String)] = [
            (
                "swiftvlc",
                "swiftvlc",
                "0.10.1",
                "58d1f3a8fc1366b2ffcd4748203a52d8410b7da2"
            ),
            (
                "swift-package-manager-google-mobile-ads",
                "google-mobile-ads",
                "13.5.0",
                "166a2dcff33c893b22e4bfccbbdd0ed00a248c24"
            ),
            (
                "swift-package-manager-google-user-messaging-platform",
                "google-user-messaging-platform",
                "3.1.0",
                "13b248eaa73b7826f0efb1bcf455e251d65ecb1b"
            )
        ]

        XCTAssertEqual(Set(pinsByIdentity.keys), Set(expectations.map(\.identity)))

        let noticesByID = Dictionary(
            uniqueKeysWithValues: TaptionOpenSourceNoticeCatalog.shippedComponents.map { ($0.id, $0) }
        )
        for expectation in expectations {
            let pin = try XCTUnwrap(pinsByIdentity[expectation.identity])
            let state = try XCTUnwrap(pin["state"] as? [String: Any])
            XCTAssertEqual(state["version"] as? String, expectation.version)
            XCTAssertEqual(state["revision"] as? String, expectation.revision)

            let notice = try XCTUnwrap(noticesByID[expectation.noticeID])
            let noticeText = try XCTUnwrap(TaptionOpenSourceNoticeTextLoader.licenseText(for: notice))
            XCTAssertTrue(noticeText.contains(expectation.version), expectation.noticeID)
            XCTAssertTrue(noticeText.contains(expectation.revision), expectation.noticeID)
        }
    }

    func testOpenSourceNoticeReadinessBlocksBundledCandidateWithoutLicenseText() {
        let currentReport = TaptionOpenSourceNoticeCatalog.readinessReport()
        let bundledCandidateReport = TaptionOpenSourceNoticeCatalog.readinessReport(
            readinessReport: SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(
                isBundledInCurrentBuild: true,
                satisfiedGates: Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
            )
        )

        XCTAssertTrue(currentReport.isReadyForReleaseNotices)
        XCTAssertTrue(currentReport.missingFinalLicenseTextEntries.isEmpty)
        XCTAssertFalse(currentReport.isReadyForPublicDistribution)
        XCTAssertEqual(
            Set(currentReport.missingDistributionMaterialEntries.map(\.id)),
            Set(["libvlc", "ffmpeg-lgpl-decode-bridge"])
        )

        XCTAssertFalse(bundledCandidateReport.isReadyForReleaseNotices)
        XCTAssertFalse(bundledCandidateReport.isReadyForPublicDistribution)
        XCTAssertEqual(bundledCandidateReport.missingFinalLicenseTextEntries.count, 1)
        XCTAssertEqual(
            bundledCandidateReport.missingFinalLicenseTextEntries.first?.id,
            "ffmpeg-family-broad-codec-backend"
        )
        XCTAssertEqual(
            bundledCandidateReport.missingFinalLicenseTextEntries.first?.relatedBackend,
            .ffmpegFamily
        )
    }

    func testOpenSourceNoticeLicenseTextResourcesAreBundledAndReadable() throws {
        let resourceReport = TaptionOpenSourceNoticeCatalog.bundleResourceReport(bundle: .main)
        let missingIDs = resourceReport.missingResourceEntries.map(\.id).joined(separator: ", ")
        let emptyIDs = resourceReport.emptyResourceEntries.map(\.id).joined(separator: ", ")

        XCTAssertTrue(
            resourceReport.isReadyForBundledResources,
            "Missing license resources: \(missingIDs). Empty license resources: \(emptyIDs)."
        )
        XCTAssertEqual(
            resourceReport.entriesRequiringFinalLicenseText.count,
            TaptionOpenSourceNoticeCatalog.shippedComponents.count
        )

        for entry in TaptionOpenSourceNoticeCatalog.shippedComponents {
            let licenseText = TaptionOpenSourceNoticeTextLoader.licenseText(for: entry, bundle: .main)
            XCTAssertNotNil(licenseText, entry.id)
            XCTAssertFalse(licenseText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, entry.id)
        }

        let lgplEntries = TaptionOpenSourceNoticeCatalog.shippedComponents.filter {
            $0.distributionMaterialRequirement == .lgplStaticLinking
        }
        XCTAssertEqual(
            Set(lgplEntries.map(\.id)),
            Set(["libvlc", "ffmpeg-lgpl-decode-bridge"])
        )
        for entry in lgplEntries {
            XCTAssertTrue(
                entry.supplementalLicenseTextResourcePaths.contains("OpenSourceNotices/LGPL-2.1.txt"),
                entry.id
            )
            XCTAssertTrue(
                TaptionOpenSourceNoticeTextLoader.licenseText(for: entry, bundle: .main)?
                    .contains("GNU LESSER GENERAL PUBLIC LICENSE") == true,
                entry.id
            )
        }

        let libVLC = TaptionOpenSourceNoticeCatalog.shippedComponents.first { $0.id == "libvlc" }
        XCTAssertTrue(
            libVLC?.supplementalLicenseTextResourcePaths.contains(
                "OpenSourceNotices/libVLC-Contrib-Licenses.txt"
            ) == true
        )
        XCTAssertTrue(
            TaptionOpenSourceNoticeTextLoader.licenseText(for: try XCTUnwrap(libVLC), bundle: .main)?
                .contains("libVLC iOS Static Contrib Notices") == true
        )
    }

    func testLibVLCComplianceInventoryPinsExactSourceInputsAndBlocksPublicRelease() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let complianceURL = rootURL.appendingPathComponent("Vendor/OpenSourceCompliance")
        let provenanceURL = complianceURL.appendingPathComponent("libvlc-ios-provenance.json")
        let manifestURL = complianceURL.appendingPathComponent("libvlc-ios-contrib-manifest.tsv")
        let noticesURL = rootURL.appendingPathComponent(
            "TaptionEncoder/OpenSourceNotices/libVLC-Contrib-Licenses.txt"
        )
        let relinkScriptURL = complianceURL.appendingPathComponent("prepare_relink_materials.sh")
        let distributionGateURL = complianceURL.appendingPathComponent(
            "verify_public_distribution_gate.sh"
        )
        let pendingApprovalURL = complianceURL.appendingPathComponent(
            "legal-approval.pending.json"
        )

        let provenanceData = try Data(contentsOf: provenanceURL)
        let provenanceObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: provenanceData) as? [String: Any]
        )
        let swiftVLC = try XCTUnwrap(provenanceObject["swiftVLC"] as? [String: Any])
        let libVLC = try XCTUnwrap(provenanceObject["libVLC"] as? [String: Any])
        let gateState = try XCTUnwrap(provenanceObject["gateState"] as? [String: Any])

        XCTAssertEqual(provenanceObject["schemaVersion"] as? Int, 2)
        XCTAssertEqual(swiftVLC["version"] as? String, "0.10.1")
        XCTAssertEqual(
            swiftVLC["revision"] as? String,
            "58d1f3a8fc1366b2ffcd4748203a52d8410b7da2"
        )
        XCTAssertEqual(
            libVLC["revision"] as? String,
            "c833c4be000b426d73ff4324bec574065f00e3df"
        )
        let swiftVLCLocalPatches = try XCTUnwrap(
            libVLC["swiftVLCLocalPatches"] as? [[String: String]]
        )
        XCTAssertEqual(swiftVLCLocalPatches.count, 4)
        XCTAssertEqual(libVLC["contribTargetCount"] as? Int, 57)
        XCTAssertEqual(libVLC["contribSourceArchiveCount"] as? Int, 56)
        let contribTargets = try XCTUnwrap(libVLC["contribTargets"] as? [String])
        XCTAssertEqual(contribTargets.count, 57)
        XCTAssertTrue(contribTargets.contains("ffmpeg"))
        XCTAssertFalse(contribTargets.contains("x264"))
        XCTAssertFalse(contribTargets.contains("x265"))
        XCTAssertFalse(contribTargets.contains("dvdcss"))
        XCTAssertFalse(contribTargets.contains("faad2"))
        XCTAssertEqual(
            gateState["formalLegalApproval"] as? String,
            "external-approval-required"
        )
        XCTAssertEqual(
            gateState["publicDistribution"] as? String,
            "blocked-until-all-external-and-release-artifact-gates-pass"
        )

        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let manifestLines = manifestText.split(separator: "\n").map(String.init)
        XCTAssertEqual(manifestLines.count, 57)
        XCTAssertEqual(
            manifestLines.first,
            "archive\tsha512\trole\tlicense_files\treview_status"
        )

        let rows = manifestLines.dropFirst().map { $0.split(separator: "\t").map(String.init) }
        XCTAssertTrue(rows.allSatisfy { $0.count == 5 })
        XCTAssertTrue(rows.allSatisfy { row in
            row[1].range(of: "^[0-9a-f]{128}$", options: .regularExpression) != nil
        })
        XCTAssertEqual(Set(rows.map { $0[0] }).count, 56)
        XCTAssertTrue(rows.allSatisfy { $0[4] == "technical-inventory-only" })
        XCTAssertFalse(rows.contains { $0[0].contains("x264") })
        XCTAssertFalse(rows.contains { $0[0].contains("x265") })
        XCTAssertFalse(rows.contains { $0[0].contains("dvdcss") })
        XCTAssertFalse(rows.contains { $0[0].contains("faad") })

        let noticesText = try String(contentsOf: noticesURL, encoding: .utf8)
        XCTAssertTrue(noticesText.contains("Source archive: ffmpeg-8.0.tar.xz"))
        XCTAssertTrue(noticesText.contains("Source archive: libvpx-1.15.2.tar.gz"))
        XCTAssertFalse(noticesText.contains("Source archive: jinja-3.1.2.tar.gz"))
        XCTAssertFalse(noticesText.contains("Source archive: markupsafe-2.1.1.tar.gz"))

        let relinkScript = try String(contentsOf: relinkScriptURL, encoding: .utf8)
        XCTAssertTrue(relinkScript.contains("TaptionEncoder-AppObjects.tar.xz"))
        XCTAssertTrue(relinkScript.contains("it is not a mandatory gate input"))
        XCTAssertTrue(relinkScript.contains("Mach-O.*object"))
        XCTAssertTrue(relinkScript.contains("-lvlc"))
        XCTAssertTrue(relinkScript.contains("-lTaptionFFmpegDecodeBridge"))

        let distributionGate = try String(contentsOf: distributionGateURL, encoding: .utf8)
        XCTAssertTrue(distributionGate.contains("--distribution-ipa"))
        XCTAssertTrue(distributionGate.contains("Apple Distribution"))
        XCTAssertTrue(distributionGate.contains("distributionIPASHA256"))
        XCTAssertTrue(distributionGate.contains("candidate-external-legal-review-required"))

        let approvalData = try Data(contentsOf: pendingApprovalURL)
        let approvalObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: approvalData) as? [String: Any]
        )
        XCTAssertEqual(approvalObject["status"] as? String, "pending")
        XCTAssertEqual(approvalObject["distributionIPASHA256"] as? String, "")
    }

    func testFFmpegBridgeRebuildRecipeKeepsNarrowDecodeAndHEVCOutputPolicy() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildScriptURL = rootURL.appendingPathComponent(
            "Vendor/FFmpegLGPLDecodeBridge/build_ffmpeg_lgpl_decode_bridge.sh"
        )
        let provenanceURL = rootURL.appendingPathComponent(
            "Vendor/OpenSourceCompliance/libvlc-ios-provenance.json"
        )
        let buildScript = try String(contentsOf: buildScriptURL, encoding: .utf8)
        let provenance = try String(contentsOf: provenanceURL, encoding: .utf8)

        XCTAssertTrue(buildScript.contains("--disable-everything"))
        XCTAssertTrue(buildScript.contains("--enable-demuxer=vc1,avi,mov"))
        let decoderLine = try XCTUnwrap(buildScript.split(separator: "\n").first { $0.contains("--enable-decoder=") })
        let decoderArgument = try XCTUnwrap(decoderLine.components(separatedBy: "--enable-decoder=").last)
        let decoders = Set(decoderArgument.split(separator: ",").map(String.init))
        XCTAssertTrue(decoders.isSuperset(of: ["vc1", "vc1image", "y41p", "rawvideo", "pcm_s16le", "prores_raw"]))
        XCTAssertFalse(buildScript.contains("--enable-gpl"))
        XCTAssertFalse(buildScript.contains("--enable-nonfree"))
        XCTAssertTrue(provenance.contains("H.265 / HEVC only in MP4 or MOV"))
    }

    func testReleaseConfigurationAndDistributionGateKeepBinaryHardening() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectURL = rootURL.appendingPathComponent("TaptionEncoder.xcodeproj/project.pbxproj")
        let gateURL = rootURL.appendingPathComponent(
            "Vendor/OpenSourceCompliance/verify_public_distribution_gate.sh"
        )
        let loggerURL = rootURL.appendingPathComponent(
            "TaptionEncoder/Core/Diagnostics/AppLogger.swift"
        )
        let projectText = try String(contentsOf: projectURL, encoding: .utf8)
        let gateText = try String(contentsOf: gateURL, encoding: .utf8)
        let loggerText = try String(contentsOf: loggerURL, encoding: .utf8)

        for requiredSetting in [
            "COPY_PHASE_STRIP = YES;",
            "DEAD_CODE_STRIPPING = YES;",
            "DEPLOYMENT_POSTPROCESSING = YES;",
            "ENABLE_TESTABILITY = NO;",
            "GCC_INLINES_ARE_PRIVATE_EXTERN = YES;",
            "GCC_SYMBOLS_PRIVATE_EXTERN = YES;",
            "LLVM_LTO = YES_THIN;",
            "STRIP_INSTALLED_PRODUCT = YES;",
            "STRIP_STYLE = all;",
            "STRIP_SWIFT_SYMBOLS = YES;",
            "SWIFT_COMPILATION_MODE = wholemodule;",
            "SWIFT_OPTIMIZATION_LEVEL = \"-O\";",
            "SWIFT_REFLECTION_METADATA_LEVEL = \"without-names\";",
            "SWIFT_SERIALIZE_DEBUGGING_OPTIONS = NO;"
        ] {
            XCTAssertTrue(projectText.contains(requiredSetting), requiredSetting)
        }

        XCTAssertTrue(gateText.contains("app and dSYM UUIDs do not match"))
        XCTAssertTrue(gateText.contains("verify_no_local_build_paths"))
        XCTAssertTrue(
            gateText.contains(
                "verify_no_local_build_paths \"$APP_DIR\" \"Release app bundle\""
            )
        )
        XCTAssertTrue(
            gateText.contains(
                "verify_no_local_build_paths \"$DIST_APP_DIR\" \"Distribution IPA app bundle\""
            )
        )
        XCTAssertTrue(gateText.contains("exposes a local build/source path"))
        XCTAssertTrue(gateText.contains("unexpectedly contains a dSYM bundle"))
        XCTAssertTrue(gateText.contains("compiler, object, archive, or interface artifacts"))
        XCTAssertTrue(gateText.contains("get-task-allow"))
        XCTAssertTrue(loggerText.contains("#if DEBUG"))
        XCTAssertTrue(loggerText.contains("source: nil"))
        XCTAssertTrue(loggerText.contains("let sourceText = source.map"))
    }

    func testHelpOpenSourceSectionShowsShippedComponentsWithoutInternalPlanning() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeMenuSheetView.swift")
        let menuText = try String(contentsOf: menuURL, encoding: .utf8)
        let sheetStart = try XCTUnwrap(menuText.range(of: "private struct OpenSourceNoticesContentView"))
        let sectionStart = try XCTUnwrap(
            menuText.range(
                of: "private struct OpenSourceNoticeSection",
                range: sheetStart.upperBound..<menuText.endIndex
            )
        )
        let sheetText = String(menuText[sheetStart.lowerBound..<sectionStart.lowerBound])

        XCTAssertTrue(sheetText.contains("shippedComponents"))
        XCTAssertTrue(sheetText.contains("shippedNotices"))
        XCTAssertFalse(sheetText.contains("localDevelopmentTooling"))
        XCTAssertFalse(sheetText.contains("planningOnlyCandidates"))
        XCTAssertFalse(sheetText.contains("readinessReport"))
        XCTAssertFalse(menuText.contains("BroadCodecBackendNoticeCard"))
    }

    func testBroadSoftwareBackendReadinessCanPromoteOnlyAfterAllGatesClose() {
        let blockedReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(
            isBundledInCurrentBuild: true,
            satisfiedGates: [.licenseReview]
        )
        let readyReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(
            isBundledInCurrentBuild: true,
            satisfiedGates: Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
        )

        XCTAssertFalse(blockedReport.isExecutableInCurrentBuild)
        XCTAssertTrue(blockedReport.mustRemainPlanningOnly)
        XCTAssertTrue(blockedReport.openGates.contains(.appStorePolicyReview))

        XCTAssertTrue(readyReport.isExecutableInCurrentBuild)
        XCTAssertTrue(readyReport.canPromoteToExecutableBackend)
        XCTAssertFalse(readyReport.mustRemainPlanningOnly)
        XCTAssertTrue(readyReport.openGates.isEmpty)
    }

    func testFFmpegCommandExecutorBlocksUntilReadinessGatesClose() async throws {
        let commandPlan = try makeH261ToHEVCCommandPlan()
        let executor = SW_FFmpegCommandExecutor(
            readinessReport: SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(),
            runner: FakeFFmpegCommandRunner { _ in
                XCTFail("Runner should not execute while readiness gates are open.")
                return SW_FFmpegCommandRunResult(exitCode: 0)
            }
        )

        do {
            _ = try await executor.execute(commandPlan, progress: { _ in })
            XCTFail("Executor should block until the broad software backend is executable.")
        } catch let error as SW_FFmpegCommandExecutionError {
            guard case .backendNotExecutable(let openGates) = error else {
                XCTFail("Unexpected execution error: \(error)")
                return
            }
            XCTAssertEqual(Set(openGates), Set(TaptionSoftwareCodecBackendReadinessGate.allCases))
            XCTAssertTrue(openGates.contains(.licenseReview))
            XCTAssertTrue(openGates.contains(.appStorePolicyReview))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFFmpegCommandExecutorRunsThroughInjectedRunnerWhenReady() async throws {
        let outputURL = temporaryTestURL(fileName: "universal-command-output.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let commandPlan = try makeH261ToHEVCCommandPlan(outputURL: outputURL)
        let executor = SW_FFmpegCommandExecutor(
            readinessReport: readyBroadSoftwareBackendReport(),
            runner: FakeFFmpegCommandRunner { plan in
                try FileManager.default.createDirectory(
                    at: plan.outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("fake encoded output".utf8).write(to: plan.outputURL)
                return SW_FFmpegCommandRunResult(
                    exitCode: 0,
                    stdout: "encoded \(plan.routeSummary)",
                    stderr: "frame=42"
                )
            }
        )
        var progressStages: [TaptionEncodingStage] = []

        let result = try await executor.execute(commandPlan) { progress in
            progressStages.append(progress.stage)
        }

        XCTAssertEqual(result.commandPlan, commandPlan)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.outputURL, outputURL)
        XCTAssertTrue(result.didCreateOutput)
        XCTAssertEqual(result.stdoutTail, "encoded \(commandPlan.routeSummary)")
        XCTAssertEqual(result.stderrTail, "frame=42")
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testBundledFFmpegDecodeBridgeEncodesVC1RawAndY41PToHEVCMP4MOVInAppRuntime() async throws {
        struct BridgeCase: Sendable {
            var fixtureResourceName: String
            var fixtureExtension: String
            var sourceCodec: TaptionVideoCodec
            var sourceContainer: TaptionVideoContainer
            var outputContainer: TaptionVideoContainer
            var outputFileName: String
            var size: TaptionPixelSize
            var expectedDisplaySize: TaptionPixelSize
            var frameRate: TaptionRationalFrameRate
            var expectedDuration: TimeInterval
            var expectsAudio: Bool
        }

        let cases = [
            BridgeCase(
                fixtureResourceName: "VC-1 Raw",
                fixtureExtension: "vc1",
                sourceCodec: .vc1,
                sourceContainer: .rawElementaryStream,
                outputContainer: .mp4,
                outputFileName: "vc1-raw-ffmpeg-bridge-hevc.mp4",
                size: TaptionPixelSize(width: 720, height: 480),
                expectedDisplaySize: TaptionPixelSize(width: 873, height: 480),
                frameRate: TaptionRationalFrameRate(numerator: 30),
                expectedDuration: 46.0 / 25.0,
                expectsAudio: false
            ),
            BridgeCase(
                fixtureResourceName: "VC-1 Raw",
                fixtureExtension: "vc1",
                sourceCodec: .vc1,
                sourceContainer: .rawElementaryStream,
                outputContainer: .mov,
                outputFileName: "vc1-raw-ffmpeg-bridge-hevc.mov",
                size: TaptionPixelSize(width: 720, height: 480),
                expectedDisplaySize: TaptionPixelSize(width: 873, height: 480),
                frameRate: TaptionRationalFrameRate(numerator: 30),
                expectedDuration: 46.0 / 25.0,
                expectsAudio: false
            ),
            BridgeCase(
                fixtureResourceName: "Y41P",
                fixtureExtension: "avi",
                sourceCodec: .y41p,
                sourceContainer: .avi,
                outputContainer: .mp4,
                outputFileName: "y41p-ffmpeg-bridge-hevc.mp4",
                size: TaptionPixelSize(width: 160, height: 120),
                expectedDisplaySize: TaptionPixelSize(width: 75, height: 120),
                frameRate: TaptionRationalFrameRate(numerator: 25),
                expectedDuration: 1,
                expectsAudio: true
            ),
            BridgeCase(
                fixtureResourceName: "Y41P",
                fixtureExtension: "avi",
                sourceCodec: .y41p,
                sourceContainer: .avi,
                outputContainer: .mov,
                outputFileName: "y41p-ffmpeg-bridge-hevc.mov",
                size: TaptionPixelSize(width: 160, height: 120),
                expectedDisplaySize: TaptionPixelSize(width: 75, height: 120),
                frameRate: TaptionRationalFrameRate(numerator: 25),
                expectedDuration: 1,
                expectsAudio: true
            )
        ]

        for bridgeCase in cases {
            let sourceURL = try bundledTestFixtureURL(
                resourceName: bridgeCase.fixtureResourceName,
                extension: bridgeCase.fixtureExtension
            )
            let outputURL = temporaryTestURL(fileName: bridgeCase.outputFileName)
            try? FileManager.default.removeItem(at: outputURL)
            defer { try? FileManager.default.removeItem(at: outputURL) }

            let asset = TaptionVideoAsset(
                displayName: sourceURL.lastPathComponent,
                location: TaptionVideoAssetLocation(kind: .file),
                container: bridgeCase.sourceContainer,
                duration: bridgeCase.expectedDuration,
                videoTrack: TaptionVideoTrackInfo(
                    codec: bridgeCase.sourceCodec,
                    naturalSize: bridgeCase.size,
                    displaySize: bridgeCase.size,
                    nominalFrameRate: bridgeCase.frameRate,
                    estimatedBitrate: 2_000_000
                ),
                audioTracks: bridgeCase.expectsAudio
                    ? [
                        TaptionAudioTrackInfo(
                            codec: .pcm,
                            channelCount: 1,
                            sampleRate: 44_100
                        )
                    ]
                    : []
            )
            let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
                asset: asset,
                sourceURL: sourceURL,
                temporaryOutputURL: outputURL,
                outputPolicy: TaptionVideoOutputPolicy(
                    videoCodec: .hevc,
                    audioCodec: .aac,
                    container: bridgeCase.outputContainer,
                    advancedOptions: TaptionAdvancedOutputOptions(
                        optimizationProfile: .performance
                    )
                ),
                savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
            )
            let commandPlan = try XCTUnwrap(plan.videoCommandPlan, bridgeCase.sourceCodec.rawValue)
            XCTAssertEqual(commandPlan.backend, .ffmpegFamily)
            XCTAssertEqual(plan.codecRoute, TaptionCodecRoute(sourceCodec: bridgeCase.sourceCodec, outputCodec: .hevc))
            XCTAssertTrue(
                [.mixed, .software].contains(plan.codecExecutionKind),
                bridgeCase.sourceCodec.rawValue
            )

            let service = AVFoundationHEVCEncoderService(
                softwareExecutor: SW_FFmpegCommandExecutor(
                    readinessReport: readyBroadSoftwareBackendReport(),
                    runner: FakeFFmpegCommandRunner { _ in
                        XCTFail("Bundled bridge routes must bypass the broad backend runner.")
                        return SW_FFmpegCommandRunResult(exitCode: 1)
                    }
                ),
                outputVerifier: DisabledSourcePreservingOutputVerifier()
            )
            let startedAt = ProcessInfo.processInfo.systemUptime
            let result = try await service.encode(plan: plan, progress: { _ in })
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)
            print(
                "TAPTION_BRIDGE_PERF_RESULT codec=\(bridgeCase.sourceCodec.rawValue) "
                    + "container=\(bridgeCase.outputContainer.rawValue) "
                    + "elapsed=\(String(format: "%.3f", elapsed))"
            )

            XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path), bridgeCase.sourceCodec.rawValue)
            XCTAssertEqual(result.usedBackend, .ffmpegFamily)
            XCTAssertEqual(result.usedMode, .software)
            XCTAssertEqual(outputAsset.container, bridgeCase.outputContainer)
            XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
            XCTAssertEqual(outputAsset.videoTrack?.displaySize, bridgeCase.expectedDisplaySize)
            try await assertDecodedVideoSignalPresent(at: result.temporaryOutputURL)
            if bridgeCase.expectsAudio {
                XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac)
                XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
                XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 1)
                try await assertDecodedAudioSignalPresent(at: result.temporaryOutputURL)
            } else {
                XCTAssertTrue(outputAsset.audioTracks.isEmpty)
            }
            XCTAssertEqual(outputAsset.duration ?? 0, bridgeCase.expectedDuration, accuracy: 0.35)
        }
    }

    /// The bundled decode bridge never runs the planned command line, so its `-vf` resize was inert and a source
    /// that was not already a standard frame kept its own size. Every legacy codec routed through the bridge then
    /// failed the output check with `resolution expected … but got …`.
    func testBundledFFmpegDecodeBridgeHonoursAStandardResolutionRequest() async throws {
        struct BridgeResizeCase: Sendable {
            var target: TaptionPixelSize
            var scaleMode: TaptionVideoScaleMode
            var outputFileName: String
        }

        let sourceURL = try bundledTestFixtureURL(resourceName: "VC-1 Raw", extension: "vc1")
        // 720×480 coded, 873×480 displayed: the source is anamorphic, so this also covers folding the sample
        // aspect ratio into the placement instead of carrying it into the output.
        let cases = [
            BridgeResizeCase(
                target: TaptionPixelSize(width: 1280, height: 720),
                scaleMode: .fit,
                outputFileName: "vc1-bridge-resize-fit-720p.mp4"
            ),
            BridgeResizeCase(
                target: TaptionPixelSize(width: 640, height: 480),
                scaleMode: .fill,
                outputFileName: "vc1-bridge-resize-fill-480p.mp4"
            ),
            BridgeResizeCase(
                target: TaptionPixelSize(width: 320, height: 240),
                scaleMode: .stretch,
                outputFileName: "vc1-bridge-resize-stretch-240p.mp4"
            )
        ]

        for bridgeCase in cases {
            let outputURL = temporaryTestURL(fileName: bridgeCase.outputFileName)
            try? FileManager.default.removeItem(at: outputURL)
            defer { try? FileManager.default.removeItem(at: outputURL) }

            let request = TaptionCodecTranscodeRequest(
                sourceURL: sourceURL,
                outputURL: outputURL,
                route: TaptionCodecRoute(sourceCodec: .vc1, outputCodec: .hevc),
                options: TaptionCodecTranscodeOptions(
                    outputPolicy: TaptionVideoOutputPolicy(
                        videoCodec: .hevc,
                        audioCodec: .aac,
                        container: .mp4,
                        advancedOptions: TaptionAdvancedOutputOptions(
                            resizeTo: bridgeCase.target,
                            optimizationProfile: .performance,
                            scaleMode: bridgeCase.scaleMode
                        )
                    ),
                    preserveAudioWhenPossible: false
                )
            )

            let result = try await SW_FFmpegDecodeBridgeFallbackTranscoder.transcode(
                request: request,
                progress: { _ in }
            )
            let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: outputURL)
            let label = "\(bridgeCase.scaleMode.rawValue) \(bridgeCase.target.width)x\(bridgeCase.target.height)"

            XCTAssertEqual(result.usedBackend, .ffmpegFamily, label)
            XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc, label)
            XCTAssertEqual(outputAsset.videoTrack?.displaySize, bridgeCase.target, label)
            // Square pixels in the output: the picture was placed in the requested frame, so the source's
            // sample aspect ratio must not stretch it again.
            XCTAssertEqual(outputAsset.videoTrack?.naturalSize, bridgeCase.target, label)
            XCTAssertEqual(outputAsset.duration ?? 0, 46.0 / 25.0, accuracy: 0.35, label)
            try await assertDecodedVideoSignalPresent(at: outputURL)
        }
    }

    /// The reported failure, end to end: a legacy codec whose frame is not a standard one was asked for 1080p,
    /// produced a source-sized file, and then failed the output check with
    /// `resolution expected 1920x1080 but got 720x480`.
    func testLegacyCodecSourcePassesTheOutputCheckAfterAStandardResolutionRequest() async throws {
        let sourceURL = try bundledTestFixtureURL(resourceName: "VC-1 Raw", extension: "vc1")
        let outputURL = temporaryTestURL(fileName: "vc1-bridge-1080p-verified.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let asset = TaptionVideoAsset(
            displayName: sourceURL.lastPathComponent,
            location: TaptionVideoAssetLocation(kind: .file),
            container: .rawElementaryStream,
            duration: 46.0 / 25.0,
            videoTrack: TaptionVideoTrackInfo(
                codec: .vc1,
                naturalSize: TaptionPixelSize(width: 720, height: 480),
                displaySize: TaptionPixelSize(width: 720, height: 480),
                // The fixture really is 25 fps (46 frames over 1.84 s); the audit compares against this value.
                nominalFrameRate: TaptionRationalFrameRate(numerator: 25),
                estimatedBitrate: 2_000_000
            ),
            audioTracks: []
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: sourceURL,
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(
                videoCodec: .hevc,
                audioCodec: .aac,
                container: .mp4,
                advancedOptions: TaptionAdvancedOutputOptions(
                    resizeTo: TaptionPixelSize(width: 1920, height: 1080),
                    optimizationProfile: .performance,
                    scaleMode: .fit
                )
            ),
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let service = AVFoundationHEVCEncoderService(
            softwareExecutor: SW_FFmpegCommandExecutor(
                readinessReport: readyBroadSoftwareBackendReport(),
                runner: FakeFFmpegCommandRunner { _ in
                    XCTFail("Bundled bridge routes must bypass the broad backend runner.")
                    return SW_FFmpegCommandRunResult(exitCode: 1)
                }
            ),
            outputVerifier: DisabledSourcePreservingOutputVerifier()
        )

        let result = try await service.encode(plan: plan, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)
        XCTAssertEqual(
            outputAsset.videoTrack?.displaySize,
            TaptionPixelSize(width: 1920, height: 1080)
        )

        // The audit that raised the user-visible error. It has to accept the intentional frame change.
        let report = try TaptionSourcePreservingExecutionAudit.verifyOutput(
            plan: plan,
            outputAsset: outputAsset
        )
        XCTAssertTrue(
            report.failures.isEmpty,
            report.failures.joined(separator: "; ")
        )
        try await assertDecodedVideoSignalPresent(at: result.temporaryOutputURL)
    }

    /// The lossless path was only covered on its planner side. This runs the copy itself: the encoded samples
    /// have to arrive byte for byte, because that is the entire promise of the feature.
    func testLosslessCopyCarriesTheEncodedSamplesThroughUnchanged() async throws {
        let sourceURL = temporaryTestURL(fileName: "lossless-copy-source.mp4")
        let outputURL = temporaryTestURL(fileName: "lossless-copy-output.mp4")
        try? FileManager.default.removeItem(at: sourceURL)
        try? FileManager.default.removeItem(at: outputURL)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try await writeEvidenceVideo(
            size: CGSize(width: 320, height: 240),
            seconds: 1,
            fill: .noise,
            to: sourceURL
        )

        var reportedFractions: [Double] = []
        try await TaptionLosslessCopyExecutor.copy(
            sourceURL: sourceURL,
            outputURL: outputURL,
            container: .mp4,
            progress: { reportedFractions.append($0.fractionCompleted) }
        )

        let sourceAsset = try await AVFoundationMediaInspector().inspectVideo(at: sourceURL)
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: outputURL)
        XCTAssertEqual(outputAsset.videoTrack?.codec, sourceAsset.videoTrack?.codec)
        XCTAssertEqual(outputAsset.videoTrack?.displaySize, sourceAsset.videoTrack?.displaySize)
        XCTAssertEqual(outputAsset.duration ?? 0, sourceAsset.duration ?? 0, accuracy: 0.02)
        XCTAssertFalse(reportedFractions.isEmpty)

        let sourceSamples = try await encodedVideoSampleData(at: sourceURL)
        let outputSamples = try await encodedVideoSampleData(at: outputURL)
        XCTAssertEqual(outputSamples.count, sourceSamples.count)
        XCTAssertEqual(outputSamples, sourceSamples)
    }

    /// A source whose audio is not AAC used to send the whole file back to `AVAssetExportSession`, which ignores
    /// the bitrate the plan derived. The writer now decodes the audio to PCM and encodes it to AAC instead.
    func testSizedWriterEncodeKeepsTheExplicitBitrateForANonAACSource() async throws {
        let directory = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("pcm-audio-source.mov")
        try await writeEvidenceVideo(
            size: CGSize(width: 1280, height: 720),
            seconds: 1.2,
            fill: .noise,
            to: sourceURL,
            withPCMAudio: true
        )

        let sourceAsset = try await AVFoundationMediaInspector().inspectVideo(at: sourceURL)
        XCTAssertEqual(sourceAsset.audioTracks.first?.codec, .pcm)
        XCTAssertEqual(sourceAsset.audioTracks.count, 1)

        func encode(bitrate: Int, fileName: String) async throws -> (url: URL, output: TaptionCodecTranscodeOutput) {
            let outputURL = directory.appendingPathComponent(fileName)
            let output = try await HW_AppleHEVCCodecAlgorithm.transcode(
                request: TaptionCodecTranscodeRequest(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    route: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc),
                    options: TaptionCodecTranscodeOptions(
                        outputPolicy: TaptionVideoOutputPolicy(
                            videoCodec: .hevc,
                            audioCodec: .aac,
                            container: .mp4,
                            advancedOptions: TaptionAdvancedOutputOptions(targetBitrate: bitrate)
                        ),
                        preserveAudioWhenPossible: true
                    )
                ),
                progress: { _ in }
            )
            return (outputURL, output)
        }

        let low = try await encode(bitrate: 700_000, fileName: "non-aac-low.mp4")
        let high = try await encode(bitrate: 9_000_000, fileName: "non-aac-high.mp4")

        for run in [low, high] {
            let asset = try await AVFoundationMediaInspector().inspectVideo(at: run.url)
            XCTAssertEqual(asset.videoTrack?.codec, .hevc, run.url.lastPathComponent)
            XCTAssertEqual(asset.audioTracks.count, 1, run.url.lastPathComponent)
            XCTAssertEqual(asset.audioTracks.first?.codec, .aac, run.url.lastPathComponent)
            XCTAssertEqual(asset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
            XCTAssertEqual(asset.audioTracks.first?.channelCount, 1)
            XCTAssertEqual(run.output.outputAudioTrackCount, 1)
            XCTAssertEqual(run.output.usedMode, .hardware)
        }

        // A source that already carries AAC still has to be copied through untouched, which is the other branch
        // of the same plan. The file produced above is a HEVC + AAC source, so it doubles as the input here.
        let passthroughURL = directory.appendingPathComponent("aac-passthrough.mp4")
        let passthrough = try await HW_AppleHEVCCodecAlgorithm.transcode(
            request: TaptionCodecTranscodeRequest(
                sourceURL: low.url,
                outputURL: passthroughURL,
                route: TaptionCodecRoute(sourceCodec: .hevc, outputCodec: .hevc),
                options: TaptionCodecTranscodeOptions(
                    outputPolicy: TaptionVideoOutputPolicy(
                        videoCodec: .hevc,
                        audioCodec: .aac,
                        container: .mp4,
                        advancedOptions: TaptionAdvancedOutputOptions(targetBitrate: 2_000_000)
                    ),
                    preserveAudioWhenPossible: true
                )
            ),
            progress: { _ in }
        )
        let passthroughAsset = try await AVFoundationMediaInspector().inspectVideo(at: passthroughURL)
        XCTAssertEqual(passthroughAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(passthroughAsset.videoTrack?.displaySize, TaptionPixelSize(width: 1280, height: 720))
        XCTAssertEqual(passthroughAsset.audioTracks.count, 1)
        XCTAssertEqual(passthroughAsset.audioTracks.first?.codec, .aac)
        XCTAssertEqual(passthroughAsset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
        XCTAssertEqual(passthrough.outputAudioTrackCount, 1)

        // The export-session fallback ignores the requested bitrate entirely, so two very different sizes are the
        // proof that this path ran rather than fell back. The simulator's HEVC encoder does not honour the average
        // bitrate at all (it spends ~16 Mbps on 720p noise whatever is asked for), so this check only means
        // something on a device — the audio assertions above hold in both places.
        #if !targetEnvironment(simulator)
        func byteCount(_ url: URL) throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.size] as? NSNumber)?.intValue ?? 0
        }
        let lowBytes = try byteCount(low.url)
        let highBytes = try byteCount(high.url)
        XCTAssertGreaterThan(
            highBytes,
            lowBytes * 2,
            "low=\(lowBytes) high=\(highBytes) — the bitrate did not reach the encoder"
        )
        #endif
    }

    func testBundledY41PProfilesPreserveVideoAudioSignals() async throws {
        let sourceURL = try bundledTestFixtureURL(resourceName: "Y41P", extension: "avi")
        for profile in [TaptionEncodingOptimizationProfile.balanced, .performance] {
            let outputURL = temporaryTestURL(
                fileName: "y41p-\(profile.rawValue)-hevc.mp4"
            )
            try? FileManager.default.removeItem(at: outputURL)
            defer { try? FileManager.default.removeItem(at: outputURL) }

            let request = TaptionCodecTranscodeRequest(
                sourceURL: sourceURL,
                outputURL: outputURL,
                route: TaptionCodecRoute(sourceCodec: .y41p, outputCodec: .hevc),
                options: TaptionCodecTranscodeOptions(
                    outputPolicy: TaptionVideoOutputPolicy(
                        videoCodec: .hevc,
                        audioCodec: .aac,
                        container: .mp4,
                        advancedOptions: TaptionAdvancedOutputOptions(
                            optimizationProfile: profile
                        )
                    ),
                    preserveAudioWhenPossible: true
                )
            )

            let result = try await SW_FFmpegDecodeBridgeFallbackTranscoder.transcode(
                request: request,
                progress: { _ in }
            )
            let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: outputURL)

            XCTAssertEqual(result.usedBackend, .ffmpegFamily, profile.rawValue)
            XCTAssertEqual(result.outputAudioTrackCount, 1, profile.rawValue)
            XCTAssertEqual(outputAsset.container, .mp4, profile.rawValue)
            XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc, profile.rawValue)
            XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac, profile.rawValue)
            XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 1, profile.rawValue)
            let outputAudioTracks = try await AVURLAsset(url: outputURL).loadTracks(withMediaType: .audio)
            let outputAudioTrack = try XCTUnwrap(outputAudioTracks.first, profile.rawValue)
            let outputAudioTimeRange = try await outputAudioTrack.load(.timeRange)
            XCTAssertEqual(
                outputAudioTimeRange.duration.seconds,
                outputAsset.duration ?? 0,
                accuracy: 0.1,
                profile.rawValue
            )
            try await assertDecodedVideoSignalPresent(at: outputURL)
            try await assertDecodedAudioSignalPresent(at: outputURL)
        }
    }

    func testEncoderServiceFailsWhenSourcePreservingOutputVerificationFails() async throws {
        let outputURL = temporaryTestURL(fileName: "h261-to-hevc-verification-fails.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        var plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: makeAsset(sourceCodec: .h261),
            sourceURL: URL(fileURLWithPath: "/tmp/h261-source.avi"),
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        plan.codecExecutionKind = .software
        let route = try XCTUnwrap(plan.codecRoute)
        let preparedCommandPlan = try XCTUnwrap(plan.videoCommandPlan)
        XCTAssertEqual(plan.codecExecutionKind, .software)
        let registry = TaptionCodecTranscodingRegistry(
            algorithms: [
                TaptionCodecTranscodingAlgorithmEntry(
                    descriptor: TaptionCodecAlgorithmDescriptor(
                        route: route,
                        mode: .software,
                        backend: preparedCommandPlan.backend,
                        displayName: "test command backend"
                    ),
                    transcode: { _, _ in
                        throw TaptionVideoCoreError.exportFailed(
                            "The command executor should handle this test route."
                        )
                    }
                )
            ]
        )
        let executor = SW_FFmpegCommandExecutor(
            readinessReport: readyBroadSoftwareBackendReport(),
            runner: FakeFFmpegCommandRunner { commandPlan in
                try FileManager.default.createDirectory(
                    at: commandPlan.outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("encoded output with bad metadata".utf8).write(to: commandPlan.outputURL)
                return SW_FFmpegCommandRunResult(exitCode: 0, stderr: "frame=12")
            }
        )
        let verificationError = TaptionVideoCoreError.exportFailed(
            "Source-preserving output verification failed: audio track was missing from the output."
        )
        let outputVerifier = RecordingSourcePreservingOutputVerifier(result: .failure(verificationError))
        let service = AVFoundationHEVCEncoderService(
            registry: registry,
            softwareExecutor: executor,
            outputVerifier: outputVerifier
        )

        do {
            _ = try await service.encode(plan: plan, progress: { _ in })
            XCTFail("Source-preserving output verification failure should fail the encode.")
        } catch {
            XCTAssertEqual(error as? TaptionVideoCoreError, verificationError)
        }

        XCTAssertEqual(outputVerifier.calls, [
            RecordingSourcePreservingOutputVerifier.Call(planID: plan.id, outputURL: outputURL)
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testEncoderServiceKeepsPreparedNoAudioSoftwareCommandPlan() async throws {
        let outputURL = temporaryTestURL(fileName: "silent-h261-to-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let silentAsset = TaptionVideoAsset(
            displayName: "silent-h261.avi",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .avi,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .h261,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: []
        )
        var plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: silentAsset,
            sourceURL: URL(fileURLWithPath: "/tmp/silent-h261-source.avi"),
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        plan.codecExecutionKind = .software
        let route = try XCTUnwrap(plan.codecRoute)
        let preparedCommandPlan = try XCTUnwrap(plan.videoCommandPlan)
        XCTAssertEqual(plan.codecExecutionKind, .software)
        let registry = TaptionCodecTranscodingRegistry(
            algorithms: [
                TaptionCodecTranscodingAlgorithmEntry(
                    descriptor: TaptionCodecAlgorithmDescriptor(
                        route: route,
                        mode: .software,
                        backend: preparedCommandPlan.backend,
                        displayName: "test command backend"
                    ),
                    transcode: { _, _ in
                        throw TaptionVideoCoreError.exportFailed(
                            "The command executor should handle this test route."
                        )
                    }
                )
            ]
        )
        let executor = SW_FFmpegCommandExecutor(
            readinessReport: readyBroadSoftwareBackendReport(),
            runner: FakeFFmpegCommandRunner { commandPlan in
                XCTAssertEqual(commandPlan, preparedCommandPlan)
                XCTAssertTrue(commandPlan.arguments.contains("-an"))
                XCTAssertFalse(commandPlan.arguments.contains("0:a?"))
                try FileManager.default.createDirectory(
                    at: commandPlan.outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("encoded silent output".utf8).write(to: commandPlan.outputURL)
                return SW_FFmpegCommandRunResult(exitCode: 0, stderr: "frame=10")
            }
        )
        let service = AVFoundationHEVCEncoderService(
            registry: registry,
            softwareExecutor: executor,
            outputVerifier: DisabledSourcePreservingOutputVerifier()
        )

        let result = try await service.encode(plan: plan, progress: { _ in })

        XCTAssertNil(plan.audioPlan)
        XCTAssertEqual(result.temporaryOutputURL, outputURL)
        XCTAssertEqual(result.usedBackend, .ffmpegFamily)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

}
