import AVFoundation
import AudioToolbox
import CoreMedia
import SwiftVLC
import XCTest
@testable import Taption_Encoder

final class CodecRoutePlannerTests: XCTestCase {
    func testAV1ToHEVCUsesSoftwareWhenNoHardwareIsAvailable() {
        let selection = selectAV1ToHEVC(profile: .softwareOnly)

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .software)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testAV1ToHEVCUsesMixedPathWhenOnlyHEVCEncodeHardwareExists() {
        let selection = selectAV1ToHEVC(profile: .h264HEVCHardware)

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .mixed)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .appleVideoToolbox)
    }

    func testAV1ToHEVCUsesHardwareWhenDecodeAndEncodeHardwareExist() {
        let selection = selectAV1ToHEVC(profile: .av1DecodeHEVCEncodeHardware)

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .hardware)
        XCTAssertEqual(selection.selectedMode, .hardware)
        XCTAssertEqual(selection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(selection.encodeBackend, .appleVideoToolbox)
    }

    func testVP9ToHEVCUsesSoftwareWhenNoHardwareIsAvailable() {
        let selection = selectRoute(
            sourceCodec: .vp9,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .software)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testVP8ToHEVCUsesSoftwareWhenNoHardwareIsAvailable() {
        let selection = selectRoute(
            sourceCodec: .vp8,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .software)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testMPEG2ToHEVCUsesSoftwareWhenNoHardwareIsAvailable() {
        let selection = selectRoute(
            sourceCodec: .mpeg2,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .software)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testMPEG4VisualToHEVCUsesSoftwareWhenNoHardwareIsAvailable() {
        let selection = selectRoute(
            sourceCodec: .mpeg4Visual,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .software)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testDolbyVisionHEVCToHEVCUsesHardwareWhenHardwarePathIsAvailable() {
        let selection = selectRoute(
            sourceCodec: .dolbyVisionHEVC,
            outputCodec: .hevc,
            profile: .proMediaHardware
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .hardware)
        XCTAssertEqual(selection.selectedMode, .hardware)
        XCTAssertEqual(selection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(selection.encodeBackend, .appleVideoToolbox)
    }

    func testHEVCWithAlphaToHEVCUsesHardwareWhenHardwarePathIsAvailable() {
        let selection = selectRoute(
            sourceCodec: .hevcWithAlpha,
            outputCodec: .hevc,
            profile: .proMediaHardware
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .hardware)
        XCTAssertEqual(selection.selectedMode, .hardware)
        XCTAssertEqual(selection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(selection.encodeBackend, .appleVideoToolbox)
    }

    func testDolbyVisionHEVCToHEVCStaysPlannedWithoutRequiredHardwarePath() {
        let selection = selectRoute(
            sourceCodec: .dolbyVisionHEVC,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .planned)
        XCTAssertFalse(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .planned)
        XCTAssertEqual(selection.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(selection.encodeBackend, .ffmpegFamily)
    }

    func testHEVCWithAlphaToHEVCStaysPlannedWithoutRequiredHardwarePath() {
        let selection = selectRoute(
            sourceCodec: .hevcWithAlpha,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .planned)
        XCTAssertFalse(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .planned)
        XCTAssertEqual(selection.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(selection.encodeBackend, .ffmpegFamily)
    }

    func testProResRawToHEVCStaysSampleGatedEvenWhenHardwarePathExists() {
        let selection = selectRoute(
            sourceCodec: .proResRaw,
            outputCodec: .hevc,
            profile: appleProfile("apple_a19pro_av1_decode_prores_raw")
        )

        XCTAssertEqual(selection.support, .planned)
        XCTAssertFalse(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .planned)
        XCTAssertEqual(selection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(selection.encodeBackend, .appleVideoToolbox)
        XCTAssertTrue(selection.reason.contains("real-world sample proof"))
        XCTAssertTrue(selection.reason.contains("runtime verification"))
    }

    func testProResRawToHEVCExplainsSampleGateWithoutHardwarePath() {
        let selection = selectRoute(
            sourceCodec: .proResRaw,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .planned)
        XCTAssertFalse(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .planned)
        XCTAssertEqual(selection.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(selection.encodeBackend, .ffmpegFamily)
        XCTAssertTrue(selection.reason.contains("real-world sample proof"))
        XCTAssertFalse(selection.reason.contains("runtime verification"))
    }

    func testPlannedUniversalRoutesRemainVisibleButNotEncodable() {
        let h264ToAV1 = selectRoute(
            sourceCodec: .h264,
            outputCodec: .av1,
            profile: .h264HEVCHardware
        )
        let av1ToH264 = selectRoute(
            sourceCodec: .av1,
            outputCodec: .h264,
            profile: .av1DecodeHEVCEncodeHardware
        )

        XCTAssertEqual(h264ToAV1.support, .planned)
        XCTAssertEqual(h264ToAV1.executionKind, .planned)
        XCTAssertFalse(h264ToAV1.isEncodableNow)
        XCTAssertEqual(h264ToAV1.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(h264ToAV1.encodeBackend, .ffmpegFamily)

        XCTAssertEqual(av1ToH264.support, .planned)
        XCTAssertEqual(av1ToH264.executionKind, .planned)
        XCTAssertFalse(av1ToH264.isEncodableNow)
        XCTAssertEqual(av1ToH264.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(av1ToH264.encodeBackend, .appleVideoToolbox)
    }

    func testAllToAllRoutePlanningPrefersHardwareBackendsPerCodecSide() {
        for profile in TaptionCodecHardwareSupportProfile.simulationProfiles {
            for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
                for outputCodec in TaptionCodecRegistry.universalOutputCodecs {
                    let selection = selectRoute(
                        sourceCodec: sourceCodec,
                        outputCodec: outputCodec,
                        profile: profile
                    )

                    XCTAssertNotEqual(selection.support, .unsupported, "\(profile.name) \(sourceCodec.rawValue) -> \(outputCodec.rawValue)")

                    if profile.canHardwareDecode(sourceCodec) {
                        XCTAssertEqual(
                            selection.decodeBackend,
                            .appleAVAssetExport,
                            "\(profile.name) should prefer HW decode for \(sourceCodec.rawValue) -> \(outputCodec.rawValue)"
                        )
                    }

                    if profile.canHardwareEncode(outputCodec) {
                        XCTAssertEqual(
                            selection.encodeBackend,
                            .appleVideoToolbox,
                            "\(profile.name) should prefer HW encode for \(sourceCodec.rawValue) -> \(outputCodec.rawValue)"
                        )
                    }
                }
            }
        }
    }

    func testUniversalCodecMatrixCoversEverySourceAndOutputPair() {
        let expectedRouteCount = TaptionCodecRegistry.universalSourceCodecs.count
            * TaptionCodecRegistry.universalOutputCodecs.count

        XCTAssertEqual(TaptionCodecRegistry.plannedUniversalRoutes.count, expectedRouteCount)

        for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
            for outputCodec in TaptionCodecRegistry.universalOutputCodecs {
                let route = TaptionCodecRoute(
                    sourceCodec: sourceCodec,
                    outputCodec: outputCodec
                )
                XCTAssertNotEqual(
                    TaptionCodecRegistry.support(for: route),
                    .unsupported,
                    "\(sourceCodec.rawValue) -> \(outputCodec.rawValue)"
                )
            }
        }
    }

    func testUniversalSourceAndOutputCodecCatalogsStaySymmetric() {
        XCTAssertEqual(
            TaptionCodecRegistry.universalSourceCodecs,
            TaptionCodecRegistry.universalOutputCodecs,
            "Universal source and output catalog order should stay aligned so UI selectors and route-matrix reports cannot drift."
        )
        XCTAssertEqual(
            Set(TaptionCodecRegistry.universalSourceCodecs),
            Set(TaptionCodecRegistry.universalOutputCodecs),
            "Universal conversion is an all-to-all codec mesh. A codec added as input must also be considered as output unless it is intentionally removed from the universal contract."
        )
    }

    func testUniversalCodecContractKeepsRepresentativeAllToAllRoutes() {
        let examples = Set(TaptionCodecRegistry.universalContractExampleRoutes)

        XCTAssertEqual(TaptionCodecRegistry.universalProductContractName, "All-to-All Universal Codec Mesh")
        XCTAssertEqual(
            TaptionCodecRegistry.universalRoutePairCount,
            TaptionCodecRegistry.universalSourceCodecs.count * TaptionCodecRegistry.universalOutputCodecs.count
        )
        XCTAssertEqual(TaptionCodecRegistry.universalRoutePairs.count, TaptionCodecRegistry.universalRoutePairCount)

        let h264ToAV1 = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let av1ToH264 = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .h264)
        let sameCodecReencode = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .h264)

        XCTAssertTrue(examples.contains(h264ToAV1))
        XCTAssertTrue(examples.contains(av1ToH264))
        XCTAssertTrue(examples.contains(sameCodecReencode))
        XCTAssertTrue(TaptionCodecRegistry.routeIsInUniversalContract(h264ToAV1))
        XCTAssertTrue(TaptionCodecRegistry.routeIsInUniversalContract(av1ToH264))
        XCTAssertTrue(TaptionCodecRegistry.routeIsInUniversalContract(sameCodecReencode))
        XCTAssertTrue(sameCodecReencode.isSameCodecReencode)
    }

    func testCodecMeshCoverageReportSummarizesUniversalPlanningState() {
        let report = TaptionCodecMeshCoverageReporter.makeReport()
        let expectedVideoRoutes = TaptionCodecRegistry.universalSourceCodecs.count
            * TaptionCodecRegistry.universalOutputCodecs.count
        let expectedAudioRoutes = TaptionAudioCodecRoutePlanner.universalAudioCodecs.count
            * TaptionAudioCodecRoutePlanner.universalAudioCodecs.count

        XCTAssertEqual(report.contractName, TaptionCodecRegistry.universalProductContractName)
        XCTAssertTrue(report.planningCoverageIsPassing)
        XCTAssertTrue(report.videoMeshIsFullyPlanned)
        XCTAssertTrue(report.audioMeshIsFullyPlanned)
        XCTAssertEqual(report.expectedVideoRouteCount, expectedVideoRoutes)
        XCTAssertEqual(report.plannedVideoRouteCount, expectedVideoRoutes)
        XCTAssertEqual(report.executableVideoRouteCount, TaptionCodecRegistry.softwareImplementedRoutes.count)
        XCTAssertEqual(report.plannedButNotExecutableVideoRouteCount, expectedVideoRoutes - TaptionCodecRegistry.softwareImplementedRoutes.count)
        XCTAssertEqual(report.sameCodecVideoRouteCount, TaptionCodecRegistry.universalSourceCodecs.count)
        XCTAssertEqual(report.exampleVideoRoutes, TaptionCodecRegistry.universalContractExampleRoutes)
        XCTAssertTrue(report.missingVideoRoutes.isEmpty)
        XCTAssertTrue(report.missingVideoReverseRoutes.isEmpty)
        XCTAssertEqual(report.expectedAudioRouteCount, expectedAudioRoutes)
        XCTAssertEqual(report.plannedAudioRouteCount, expectedAudioRoutes)
        XCTAssertEqual(report.sameCodecAudioRouteCount, TaptionAudioCodecRoutePlanner.universalAudioCodecs.count)
        XCTAssertTrue(report.missingAudioRoutes.isEmpty)
        XCTAssertTrue(report.missingAudioReverseRoutes.isEmpty)
        XCTAssertEqual(report.softwareVideoOutputPlannableCodecCount, SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs.count)
        XCTAssertEqual(report.softwareAudioOutputPlannableCodecCount, SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs.count)
        XCTAssertEqual(report.videoRunnableInCurrentBuildRouteCount, TaptionCodecRegistry.softwareImplementedRoutes.count)
        XCTAssertEqual(
            report.videoRunnableInCurrentBuildRouteCount
                + report.videoCommandPlanOnlyRouteCount
                + report.videoBlockedMissingSoftwareEncoderRouteCount,
            expectedVideoRoutes
        )
        XCTAssertEqual(
            Set(report.videoBlockedOutputCodecs),
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs)
        )
        XCTAssertEqual(report.hardwareAudioDescriptorCount, HW_AudioCodecAlgorithmCatalog.descriptors().count)
        XCTAssertEqual(report.softwareAudioDescriptorCount, SW_UniversalAudioCodecTranscodeAlgorithm.plannedDescriptors.count)
        XCTAssertEqual(
            report.audioRunnableInCurrentBuildRouteCount
                + report.audioCommandPlanOnlyRouteCount
                + report.audioBlockedMissingSoftwareEncoderRouteCount,
            expectedAudioRoutes
        )
        XCTAssertEqual(
            Set(report.audioBlockedOutputCodecs),
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs)
        )
        XCTAssertGreaterThan(report.audioRunnableInCurrentBuildRouteCount, 0)
        XCTAssertGreaterThan(report.audioCommandPlanOnlyRouteCount, 0)
        XCTAssertGreaterThan(report.audioBlockedMissingSoftwareEncoderRouteCount, 0)
        XCTAssertTrue(report.softwareVideoOutputUnsupportedCodecs.contains(.proResRaw))
        XCTAssertTrue(report.softwareAudioOutputUnsupportedCodecs.contains(.xheAAC))
        XCTAssertTrue(report.broadSoftwareBackendRequiresLicenseReview)
    }

    func testUniversalCodecCompletionAuditLocksAllToAllFinalGoal() {
        let report = TaptionUniversalCodecCompletionAuditor.makeReport()
        let outputReadinessCatalog = TaptionCodecOutputCatalog.makeReadinessReport()
        let audioOutputReadinessCatalog = TaptionAudioCodecOutputCatalog.makeReadinessReport()
        let h264ToAV1 = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let av1ToH264 = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .h264)
        let sameCodecReencode = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .h264)

        XCTAssertEqual(report.contractName, "All-to-All Universal Codec Mesh")
        XCTAssertEqual(report.stage, .allToAllPlanningLocked)
        XCTAssertTrue(report.universalPlanningIsLocked)
        XCTAssertFalse(report.universalCommandPlanningIsComplete)
        XCTAssertFalse(report.universalExecutionIsComplete)
        XCTAssertTrue(report.requiredBidirectionalVideoRoutes.contains(h264ToAV1))
        XCTAssertTrue(report.requiredBidirectionalVideoRoutes.contains(av1ToH264))
        XCTAssertTrue(report.requiredBidirectionalVideoRoutes.contains(sameCodecReencode))
        XCTAssertTrue(report.missingRequiredBidirectionalVideoRoutes.isEmpty)
        XCTAssertEqual(report.videoRouteCount, TaptionCodecRegistry.universalRoutePairCount)
        XCTAssertEqual(
            report.audioRouteCount,
            TaptionAudioCodecRoutePlanner.universalAudioCodecs.count
                * TaptionAudioCodecRoutePlanner.universalAudioCodecs.count
        )
        XCTAssertEqual(report.videoCurrentBuildRunnableRouteCount, TaptionCodecRegistry.softwareImplementedRoutes.count)
        XCTAssertGreaterThan(report.videoPendingRuntimeRouteCount, 0)
        XCTAssertGreaterThan(report.audioPendingRuntimeRouteCount, 0)
        XCTAssertGreaterThan(report.videoCommandPlanOnlyRouteCount, 0)
        XCTAssertGreaterThan(report.audioCommandPlanOnlyRouteCount, 0)
        XCTAssertGreaterThan(report.videoBlockedMissingSoftwareEncoderRouteCount, 0)
        XCTAssertGreaterThan(report.audioBlockedMissingSoftwareEncoderRouteCount, 0)
        XCTAssertTrue(report.outputSelectionCoverageIsPassing)
        XCTAssertEqual(report.videoOutputSelectionCount, outputReadinessCatalog.outputSelectionCount)
        XCTAssertEqual(report.audioOutputSelectionCount, audioOutputReadinessCatalog.outputSelectionCount)
        XCTAssertEqual(report.videoOutputImplementedSelectionCount, outputReadinessCatalog.implementedOutputSelectionCount)
        XCTAssertEqual(report.audioOutputImplementedSelectionCount, audioOutputReadinessCatalog.implementedOutputSelectionCount)
        XCTAssertEqual(report.videoOutputCommandPlanReadySelectionCount, outputReadinessCatalog.commandPlanReadyOutputSelectionCount)
        XCTAssertEqual(report.audioOutputCommandPlanReadySelectionCount, audioOutputReadinessCatalog.commandPlanReadyOutputSelectionCount)
        XCTAssertEqual(report.videoOutputPlannedSelectionCount, outputReadinessCatalog.plannedOutputSelectionCount)
        XCTAssertEqual(report.audioOutputPlannedSelectionCount, audioOutputReadinessCatalog.plannedOutputSelectionCount)
        XCTAssertEqual(report.videoOutputBlockedSelectionCount, outputReadinessCatalog.unsupportedOutputSelectionCount)
        XCTAssertEqual(report.audioOutputBlockedSelectionCount, audioOutputReadinessCatalog.unsupportedOutputSelectionCount)
        XCTAssertTrue(report.videoOutputSelectionCoverageIsPassing)
        XCTAssertTrue(report.audioOutputSelectionCoverageIsPassing)
        XCTAssertEqual(
            Set(report.videoBlockedOutputCodecs),
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs)
        )
        XCTAssertEqual(
            Set(report.audioBlockedOutputCodecs),
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs)
        )
        XCTAssertFalse(report.broadSoftwareBackendBundled)
        XCTAssertFalse(report.broadSoftwareBackendExecutable)
        XCTAssertGreaterThan(report.broadSoftwareBackendOpenGateCount, 0)
        XCTAssertTrue(report.broadSoftwareBackendRequiresLicenseReview)
    }

    func testUniversalCodecMatrixKeepsReverseRoutesForEveryPair() {
        for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
            for outputCodec in TaptionCodecRegistry.universalOutputCodecs where sourceCodec != outputCodec {
                let forwardRoute = TaptionCodecRoute(
                    sourceCodec: sourceCodec,
                    outputCodec: outputCodec
                )
                let reverseRoute = TaptionCodecRoute(
                    sourceCodec: outputCodec,
                    outputCodec: sourceCodec
                )

                XCTAssertTrue(
                    TaptionCodecRegistry.plannedUniversalRoutes.contains(forwardRoute),
                    "Missing forward route \(sourceCodec.rawValue) -> \(outputCodec.rawValue)"
                )
                XCTAssertTrue(
                    TaptionCodecRegistry.plannedUniversalRoutes.contains(reverseRoute),
                    "Missing reverse route \(outputCodec.rawValue) -> \(sourceCodec.rawValue)"
                )
                XCTAssertNotEqual(
                    TaptionCodecRegistry.support(for: forwardRoute),
                    .unsupported,
                    "Forward route became unsupported: \(sourceCodec.rawValue) -> \(outputCodec.rawValue)"
                )
                XCTAssertNotEqual(
                    TaptionCodecRegistry.support(for: reverseRoute),
                    .unsupported,
                    "Reverse route became unsupported: \(outputCodec.rawValue) -> \(sourceCodec.rawValue)"
                )
            }
        }
    }

    func testAppleDeviceProfilesSelectExpectedAV1ToHEVCPath() {
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleProfile("apple_ipados18_legacy_a10_h264")).executionKind,
            .software
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleProfile("apple_a15_a16_h264_hevc")).executionKind,
            .mixed
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleProfile("apple_a17pro_av1_decode")).executionKind,
            .hardware
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleProfile("apple_ipad_m3_m4_av1_prores")).executionKind,
            .hardware
        )
    }

    func testAppleDeviceModelMatrixMapsRuntimeIdentifiersToProfiles() {
        let models = HW_AppleDeviceCodecModelMatrix.all
        let identifiers = models.map(\.modelIdentifier)
        let coverage = HW_AppleDeviceCodecModelMatrix.coverageReport(models: models)

        XCTAssertEqual(models.count, 93)
        XCTAssertEqual(coverage.modelCount, 93)
        XCTAssertEqual(coverage.iPhoneModelCount, 35)
        XCTAssertEqual(coverage.iPadModelCount, 58)
        XCTAssertEqual(coverage.profileChipFamilyMismatchCount, 0)
        XCTAssertEqual(coverage.av1HardwareDecodeModelCount, 22)
        XCTAssertEqual(coverage.hevcHardwareEncodeModelCount, 91)
        XCTAssertEqual(coverage.h264OnlyModelCount, 2)
        XCTAssertEqual(coverage.proResHardwareEncodeModelCount, 32)
        XCTAssertEqual(coverage.identifierFamilyCounts["iPhone18"], 5)
        XCTAssertEqual(coverage.profileCounts["apple_a19_av1_decode"], 2)
        XCTAssertEqual(coverage.profileCounts["apple_a19pro_av1_decode"], 1)
        XCTAssertEqual(coverage.profileCounts["apple_a19pro_av1_decode_prores_raw"], 2)
        XCTAssertTrue(coverage.isPassing)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(HW_AppleDeviceCodecModelMatrix.missingProfileIDs.isEmpty)
        XCTAssertEqual(
            HW_AppleDeviceCodecModelMatrix.model(identifier: "iPhone16,1")?.profileID,
            "apple_a17pro_av1_decode"
        )
        XCTAssertEqual(
            HW_AppleDeviceCodecModelMatrix.model(identifier: "iPad7,11")?.profileID,
            "apple_ipados18_legacy_a10_h264"
        )
        XCTAssertEqual(
            HW_AppleDeviceCodecModelMatrix.model(identifier: "iPad11,6")?.profileID,
            "apple_ios18_a12_h264_hevc"
        )
        XCTAssertEqual(
            HW_AppleDeviceCodecModelMatrix.model(identifier: "iPad11,7")?.profileID,
            "apple_ios18_a12_h264_hevc"
        )
        XCTAssertEqual(
            HW_AppleDeviceCodecModelMatrix.model(identifier: "iPad16,3")?.profileID,
            "apple_ipad_m3_m4_av1_prores"
        )
        XCTAssertEqual(
            HW_AppleDeviceCodecModelMatrix.model(identifier: "iPhone18,1")?.profileID,
            "apple_a19pro_av1_decode_prores_raw"
        )
        XCTAssertEqual(
            HW_AppleDeviceCodecModelMatrix.model(identifier: "iPhone18,3")?.profileID,
            "apple_a19_av1_decode"
        )
        XCTAssertEqual(
            HW_AppleDeviceCodecModelMatrix.model(identifier: "iPhone18,4")?.profileID,
            "apple_a19pro_av1_decode"
        )
    }

    func testAppleDeviceModelRowsMatchProfileChipFamilies() {
        for model in HW_AppleDeviceCodecModelMatrix.all {
            guard let profile = model.profile else {
                XCTFail("\(model.modelIdentifier) references missing profile \(model.profileID)")
                continue
            }

            XCTAssertTrue(
                profile.chipFamilies.contains(model.chipFamily),
                "\(model.modelIdentifier) \(model.marketingName) uses \(model.chipFamily) but maps to \(profile.id) with chips \(profile.chipFamilies.joined(separator: ", "))"
            )
        }
    }

    func testAppleDeviceModelMatrixSelectsExpectedAV1ToHEVCPath() {
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleModelProfile("iPad7,11")).executionKind,
            .software
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleModelProfile("iPhone15,4")).executionKind,
            .mixed
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleModelProfile("iPhone16,1")).executionKind,
            .hardware
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleModelProfile("iPhone17,3")).executionKind,
            .hardware
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleModelProfile("iPhone18,1")).executionKind,
            .hardware
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleModelProfile("iPhone18,3")).executionKind,
            .hardware
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleModelProfile("iPhone18,4")).executionKind,
            .hardware
        )
        XCTAssertEqual(
            selectAV1ToHEVC(profile: appleModelProfile("iPad16,3")).executionKind,
            .hardware
        )
    }

    func testAppleDeviceRouteSimulatorCoversEveryProfileAndUniversalRoute() {
        let rows = HW_CodecRouteSimulator.rows()
        let summary = HW_CodecRouteSimulator.summary(rows: rows)
        let expectedProfileCount = TaptionCodecHardwareSupportProfile.simulationProfiles.count
        let expectedRouteCount = TaptionCodecRegistry.universalSourceCodecs.count
            * TaptionCodecRegistry.universalOutputCodecs.count

        XCTAssertEqual(summary.profileCount, expectedProfileCount)
        XCTAssertEqual(summary.sourceCodecCount, TaptionCodecRegistry.universalSourceCodecs.count)
        XCTAssertEqual(summary.outputCodecCount, TaptionCodecRegistry.universalOutputCodecs.count)
        XCTAssertEqual(summary.routeCountPerProfile, expectedRouteCount)
        XCTAssertEqual(summary.rowCount, expectedProfileCount * expectedRouteCount)
        XCTAssertEqual(summary.implementedRowCount, rows.filter(\.isEncodableNow).count)
        XCTAssertGreaterThanOrEqual(
            summary.implementedRowCount,
            expectedProfileCount * TaptionCodecRegistry.softwareImplementedRoutes.count
        )
        XCTAssertLessThan(
            summary.implementedRowCount,
            expectedProfileCount * TaptionCodecRegistry.implementedRoutes.count
        )
        XCTAssertEqual(summary.plannedRowCount, summary.rowCount - summary.implementedRowCount)
        XCTAssertEqual(summary.unsupportedRowCount, 0)
        XCTAssertEqual(summary.hardwareDecodePreferenceViolationCount, 0)
        XCTAssertEqual(summary.hardwareEncodePreferenceViolationCount, 0)
        XCTAssertTrue(summary.isPassing)
        XCTAssertTrue(summary.av1ToHEVCPathSummary.contains("HW"))
        XCTAssertTrue(summary.av1ToHEVCPathSummary.contains("HW/SW"))
        XCTAssertTrue(summary.av1ToHEVCPathSummary.contains("SW"))
        XCTAssertTrue(HW_CodecRouteSimulator.validationFailures(rows: rows).isEmpty)
    }

    func testAppleDeviceRouteSimulatorIncludesModelIdentifierProfiles() {
        let simulatedProfileNames = Set(TaptionCodecHardwareSupportProfile.simulationProfiles.map(\.name))
        let modelProfileNames = Set(HW_AppleDeviceCodecModelMatrix.routeSimulationProfiles.map(\.name))

        XCTAssertEqual(modelProfileNames.count, HW_AppleDeviceCodecModelMatrix.all.count)
        XCTAssertTrue(modelProfileNames.isSubset(of: simulatedProfileNames))
        XCTAssertTrue(simulatedProfileNames.contains("iPhone16,1"))
        XCTAssertTrue(simulatedProfileNames.contains("iPhone18,1"))
        XCTAssertTrue(simulatedProfileNames.contains("iPhone18,5"))
        XCTAssertTrue(simulatedProfileNames.contains("iPad16,3"))
    }

    func testImplementedRoutesRespectDeviceHardwareAvailability() {
        for profile in TaptionCodecHardwareSupportProfile.simulationProfiles {
            for route in TaptionCodecRegistry.implementedRoutes {
                let selection = selectRoute(
                    sourceCodec: route.sourceCodec,
                    outputCodec: route.outputCodec,
                    profile: profile
                )
                let hasSoftwareFallback = TaptionCodecRegistry.routeHasImplementedAlgorithm(
                    route,
                    mode: .software
                )
                let hasHardwarePath = TaptionCodecRegistry.routeHasImplementedAlgorithm(
                    route,
                    mode: .hardware
                )
                    && profile.canHardwareDecode(route.sourceCodec)
                    && profile.canHardwareEncode(route.outputCodec)

                if hasSoftwareFallback || hasHardwarePath {
                    XCTAssertEqual(selection.support, .implemented, "\(profile.name) \(route.displayName)")
                    XCTAssertTrue(selection.isEncodableNow, "\(profile.name) \(route.displayName)")
                    XCTAssertNotEqual(selection.executionKind, .planned, "\(profile.name) \(route.displayName)")
                } else {
                    XCTAssertEqual(selection.support, .planned, "\(profile.name) \(route.displayName)")
                    XCTAssertFalse(selection.isEncodableNow, "\(profile.name) \(route.displayName)")
                    XCTAssertEqual(selection.executionKind, .planned, "\(profile.name) \(route.displayName)")
                }
                XCTAssertNotEqual(selection.executionKind, .unsupported, profile.name)
            }
        }
    }

    func testImplementedRoutesExposeExpectedAlgorithmDescriptors() {
        for route in TaptionCodecRegistry.implementedRoutes {
            let descriptors = TaptionCodecRegistry.implementedAlgorithmDescriptors(for: route)
            let modes = Set(descriptors.map(\.mode))

            XCTAssertFalse(descriptors.isEmpty, "\(route.displayName) is missing algorithm descriptors")
            XCTAssertTrue(descriptors.allSatisfy { $0.route == route })
            if TaptionCodecRegistry.hardwareImplementedRoutes.contains(route) {
                XCTAssertTrue(modes.contains(.hardware), "\(route.displayName) is missing a HW algorithm")
            }
            if TaptionCodecRegistry.softwareImplementedRoutes.contains(route) {
                XCTAssertTrue(modes.contains(.software), "\(route.displayName) is missing a SW algorithm")
            }
        }
    }

    func testLiveTranscodingRegistryExposesImplementedAlgorithms() {
        let route = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)
        let descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: route)
        let modes = Set(descriptors.map(\.mode))
        let h264Route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)
        let h264Descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: h264Route)
        let alphaRoute = TaptionCodecRoute(sourceCodec: .hevcWithAlpha, outputCodec: .hevc)
        let alphaDescriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: alphaRoute)
        let dolbyRoute = TaptionCodecRoute(sourceCodec: .dolbyVisionHEVC, outputCodec: .hevc)
        let dolbyDescriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: dolbyRoute)
        let mpeg2Route = TaptionCodecRoute(sourceCodec: .mpeg2, outputCodec: .hevc)
        let mpeg2Descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: mpeg2Route)
        let mpeg4Route = TaptionCodecRoute(sourceCodec: .mpeg4Visual, outputCodec: .hevc)
        let mpeg4Descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: mpeg4Route)

        XCTAssertEqual(descriptors.count, 2)
        XCTAssertTrue(modes.contains(.hardware))
        XCTAssertTrue(modes.contains(.software))
        XCTAssertEqual(h264Descriptors.count, 1)
        XCTAssertEqual(h264Descriptors.first?.mode, .hardware)
        XCTAssertEqual(h264Descriptors.first?.backend, .appleVideoToolbox)
        XCTAssertEqual(alphaDescriptors.count, 1)
        XCTAssertEqual(alphaDescriptors.first?.mode, .hardware)
        XCTAssertEqual(alphaDescriptors.first?.backend, .appleVideoToolbox)
        XCTAssertEqual(dolbyDescriptors.count, 1)
        XCTAssertEqual(dolbyDescriptors.first?.mode, .hardware)
        XCTAssertEqual(dolbyDescriptors.first?.backend, .appleVideoToolbox)
        XCTAssertEqual(mpeg2Descriptors.count, 1)
        XCTAssertEqual(mpeg2Descriptors.first?.mode, .software)
        XCTAssertEqual(mpeg2Descriptors.first?.backend, .softwareVLCDecoder)
        XCTAssertEqual(mpeg4Descriptors.count, 1)
        XCTAssertEqual(mpeg4Descriptors.first?.mode, .software)
        XCTAssertEqual(mpeg4Descriptors.first?.backend, .softwareVLCDecoder)
    }

    func testLiveTranscodingRegistryPrefersHardwareForHardwareExecution() {
        let route = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)
        let descriptor = TaptionCodecTranscodingRegistry.live.preferredDescriptor(
            for: route,
            executionKind: .hardware
        )

        XCTAssertEqual(descriptor?.mode, .hardware)
        XCTAssertEqual(descriptor?.backend, .appleVideoToolbox)
    }

    func testLiveTranscodingRegistryPrefersHardwareForMixedExecution() {
        let route = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)
        let descriptor = TaptionCodecTranscodingRegistry.live.preferredDescriptor(
            for: route,
            executionKind: .mixed
        )

        XCTAssertEqual(descriptor?.mode, .hardware)
        XCTAssertEqual(descriptor?.backend, .appleVideoToolbox)
    }

    func testLiveTranscodingRegistryExecutesHardwareFirstForMixedExecution() async throws {
        let route = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)
        let outputURL = temporaryTestURL(fileName: "mixed-first-hevc.mkv")
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/mixed-input.av1"),
            outputURL: outputURL,
            route: route
        )
        actor ExecutionOrderRecorder {
            private var executionOrder: [TaptionEncoderMode] = []

            func append(_ mode: TaptionEncoderMode) {
                executionOrder.append(mode)
            }

            func value() -> [TaptionEncoderMode] {
                executionOrder
            }
        }
        let executionOrderRecorder = ExecutionOrderRecorder()
        let expectedError = NSError(domain: "TaptionEncoderTests", code: 1)

        let hardwareDescriptor = TaptionCodecAlgorithmDescriptor(
            route: route,
            mode: .hardware,
            backend: .appleVideoToolbox,
            displayName: "hardware av1->hevc"
        )
        let softwareDescriptor = TaptionCodecAlgorithmDescriptor(
            route: route,
            mode: .software,
            backend: .softwareVLCDecoder,
            displayName: "software av1->hevc"
        )
        let hardwareEntry = TaptionCodecTranscodingAlgorithmEntry(
            descriptor: hardwareDescriptor,
            transcode: { _, _ in
                await executionOrderRecorder.append(.hardware)
                return TaptionCodecTranscodeOutput(
                    outputURL: outputURL,
                    route: route,
                    usedMode: .hardware,
                    usedBackend: .appleVideoToolbox,
                    outputVideoCodec: .hevc,
                    outputAudioTrackCount: 0
                )
            }
        )
        let softwareEntry = TaptionCodecTranscodingAlgorithmEntry(
            descriptor: softwareDescriptor,
            transcode: { _, _ in
                await executionOrderRecorder.append(.software)
                throw expectedError
            }
        )
        let registry = TaptionCodecTranscodingRegistry(
            algorithms: [hardwareEntry, softwareEntry],
            plannedDescriptors: []
        )

        _ = try await registry.transcode(
            request: request,
            executionKind: .mixed
        ) { _ in }

        let executionOrder = await executionOrderRecorder.value()
        XCTAssertEqual(executionOrder, [.hardware])
    }

    func testUniversalSoftwareAlgorithmCatalogCoversEveryNonImplementedRoute() {
        let descriptors = SW_UniversalCodecTranscodeAlgorithm.plannedDescriptors
        let descriptorRoutes = Set(descriptors.map(\.route))
        let expectedRoutes = TaptionCodecRegistry.plannedUniversalRoutes
            .subtracting(TaptionCodecRegistry.implementedRoutes)

        XCTAssertEqual(descriptorRoutes, expectedRoutes)
        XCTAssertTrue(descriptors.allSatisfy { $0.mode == .software })
        XCTAssertTrue(descriptors.allSatisfy { $0.backend == .ffmpegFamily })
    }

    func testLiveRegistryKeepsPlannedSoftwareDescriptorsSeparateFromExecutableAlgorithms() {
        let plannedRoute = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)

        XCTAssertTrue(TaptionCodecTranscodingRegistry.live.descriptors(for: plannedRoute).isEmpty)
        XCTAssertEqual(
            TaptionCodecTranscodingRegistry.live.plannedDescriptors(for: plannedRoute).first?.backend,
            .ffmpegFamily
        )
        XCTAssertEqual(
            TaptionCodecTranscodingRegistry.live.allDescriptors(for: plannedRoute).first?.route,
            plannedRoute
        )
    }

    func testConfiguredLiveRegistryPromotesPlannedSoftwareRoutesWhenBackendIsExecutable() {
        let plannedRoute = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let registry = TaptionCodecTranscodingRegistry.makeLive(
            softwareExecutor: SW_FFmpegCommandExecutor(
                readinessReport: readyBroadSoftwareBackendReport(),
                runner: FakeFFmpegCommandRunner { commandPlan in
                    XCTAssertEqual(commandPlan.routeSummary, plannedRoute.displayName)
                    return SW_FFmpegCommandRunResult(exitCode: 0)
                },
                validateOutputFileExists: false
            )
        )

        let runtimeDescriptor = registry.descriptors(for: plannedRoute).first

        XCTAssertEqual(runtimeDescriptor?.route, plannedRoute)
        XCTAssertEqual(runtimeDescriptor?.mode, .software)
        XCTAssertEqual(runtimeDescriptor?.backend, .ffmpegFamily)
        XCTAssertNil(registry.plannedDescriptors(for: plannedRoute).first)
        XCTAssertEqual(registry.preferredDescriptor(for: plannedRoute, executionKind: .software)?.backend, .ffmpegFamily)
    }

    func testConfiguredLiveRegistryCanTranscodePlannedSoftwareRouteWhenBackendIsExecutable() async throws {
        let outputURL = temporaryTestURL(fileName: "runtime-registry-h264-to-av1.mkv")
        try? FileManager.default.removeItem(at: outputURL)
        let plannedRoute = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let registry = TaptionCodecTranscodingRegistry.makeLive(
            softwareExecutor: SW_FFmpegCommandExecutor(
                readinessReport: readyBroadSoftwareBackendReport(),
                runner: FakeFFmpegCommandRunner { commandPlan in
                    XCTAssertEqual(commandPlan.routeSummary, plannedRoute.displayName)
                    XCTAssertTrue(commandPlan.arguments.contains("libsvtav1"))
                    try FileManager.default.createDirectory(
                        at: commandPlan.outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data("runtime registry output".utf8).write(to: commandPlan.outputURL)
                    return SW_FFmpegCommandRunResult(exitCode: 0, stdout: "ok", stderr: "frame=6")
                }
            )
        )
        var progressStages: [TaptionEncodingStage] = []

        let output = try await registry.transcode(
            request: TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/runtime-registry-input.mp4"),
                outputURL: outputURL,
                route: plannedRoute,
                options: .preservingSource(outputCodec: .av1, container: .mkv)
            ),
            executionKind: .software
        ) { progress in
            progressStages.append(progress.stage)
        }

        XCTAssertEqual(output.route, plannedRoute)
        XCTAssertEqual(output.outputURL, outputURL)
        XCTAssertEqual(output.usedMode, .software)
        XCTAssertEqual(output.usedBackend, .ffmpegFamily)
        XCTAssertEqual(output.outputVideoCodec, .av1)
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testUniversalSoftwareAlgorithmReportsBundledBackendMissingUntilImplementationLands() async {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
            route: route,
            options: .preservingSource(outputCodec: .av1, container: .mkv)
        )

        do {
            _ = try await SW_UniversalCodecTranscodeAlgorithm.transcode(
                request: request,
                progress: { _ in }
            )
            XCTFail("Universal software transcode should stay unavailable until the broad backend is bundled.")
        } catch let error as TaptionUniversalSoftwareCodecError {
            XCTAssertEqual(error, .backendNotBundled(.ffmpegFamily, route))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFFmpegVideoCodecTranscodeExecutorBlocksUntilReadinessGatesClose() async throws {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
            route: route,
            options: .preservingSource(outputCodec: .av1, container: .mkv)
        )
        let videoExecutor = SW_FFmpegVideoCodecTranscodeExecutor(
            executor: SW_FFmpegCommandExecutor(
                readinessReport: SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(),
                runner: FakeFFmpegCommandRunner { _ in
                    XCTFail("Runner should not execute while broad software backend gates are open.")
                    return SW_FFmpegCommandRunResult(exitCode: 0)
                }
            )
        )

        do {
            _ = try await videoExecutor.transcode(request: request, progress: { _ in })
            XCTFail("Video executor should block until the broad software backend is executable.")
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

    func testFFmpegVideoCodecTranscodeExecutorRunsThroughInjectedRunnerWhenReady() async throws {
        let outputURL = temporaryTestURL(fileName: "h264-to-av1.mkv")
        try? FileManager.default.removeItem(at: outputURL)
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: outputURL,
            route: route,
            options: .preservingSource(outputCodec: .av1, container: .mkv)
        )
        let videoExecutor = SW_FFmpegVideoCodecTranscodeExecutor(
            executor: SW_FFmpegCommandExecutor(
                readinessReport: readyBroadSoftwareBackendReport(),
                runner: FakeFFmpegCommandRunner { commandPlan in
                    XCTAssertEqual(commandPlan.routeSummary, route.displayName)
                    XCTAssertTrue(commandPlan.arguments.contains("libsvtav1"))
                    try FileManager.default.createDirectory(
                        at: commandPlan.outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data("fake video output".utf8).write(to: commandPlan.outputURL)
                    return SW_FFmpegCommandRunResult(exitCode: 0, stdout: "video encoded", stderr: "frame=8")
                }
            )
        )
        var progressStages: [TaptionEncodingStage] = []

        let output = try await videoExecutor.transcode(request: request) { progress in
            progressStages.append(progress.stage)
        }

        XCTAssertEqual(output.outputURL, outputURL)
        XCTAssertEqual(output.route, route)
        XCTAssertEqual(output.usedMode, .software)
        XCTAssertEqual(output.usedBackend, .ffmpegFamily)
        XCTAssertEqual(output.outputVideoCodec, .av1)
        XCTAssertEqual(output.outputAudioTrackCount, 1)
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testUniversalVideoCommandPlanBuildsAllToAllReverseRoutes() throws {
        let h264ToAV1 = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let av1ToH264 = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .h264)
        let h264ToAV1Plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/h264.mp4"),
                outputURL: URL(fileURLWithPath: "/tmp/av1.mkv"),
                route: h264ToAV1,
                options: .preservingSource(outputCodec: .av1, container: .mkv)
            )
        )
        let av1ToH264Plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/av1.webm"),
                outputURL: URL(fileURLWithPath: "/tmp/h264.mp4"),
                route: av1ToH264,
                options: .preservingSource(outputCodec: .h264, container: .mp4)
            )
        )

        XCTAssertEqual(h264ToAV1Plan.backend, .ffmpegFamily)
        XCTAssertEqual(h264ToAV1Plan.routeSummary, h264ToAV1.displayName)
        XCTAssertTrue(h264ToAV1Plan.arguments.contains("libsvtav1"))
        XCTAssertTrue(h264ToAV1Plan.arguments.contains("/tmp/av1.mkv"))

        XCTAssertEqual(av1ToH264Plan.routeSummary, av1ToH264.displayName)
        XCTAssertTrue(av1ToH264Plan.arguments.contains("libx264"))
        XCTAssertTrue(av1ToH264Plan.arguments.contains("+faststart"))
    }

    func testUniversalVideoCommandPlanAppliesAdvancedOutputOptions() throws {
        let route = TaptionCodecRoute(sourceCodec: .vp9, outputCodec: .h264)
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .h264,
            container: .mp4,
            profile: .automatic,
            qualityPolicy: .preserveSourceVisuals,
            advancedOptions: TaptionAdvancedOutputOptions(
                resizeTo: TaptionPixelSize(width: 1280, height: 720),
                frameRate: TaptionRationalFrameRate(numerator: 30000, denominator: 1001),
                targetBitrate: 8_000_000,
                color: TaptionColorDescription(
                    primaries: .bt2020,
                    transfer: .hlg,
                    matrix: .bt2020NonConstantLuminance,
                    bitDepth: 10,
                    isHDR: true
                ),
                rotationDegrees: 90
            )
        )
        let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/vp9.webm"),
                outputURL: URL(fileURLWithPath: "/tmp/h264.mp4"),
                route: route,
                options: TaptionCodecTranscodeOptions(outputPolicy: outputPolicy)
            )
        )

        XCTAssertTrue(plan.arguments.contains("scale=1280:720"))
        XCTAssertTrue(plan.arguments.contains("30000/1001"))
        XCTAssertTrue(plan.arguments.contains("8000000"))
        XCTAssertTrue(plan.arguments.contains("libx264"))
        XCTAssertTrue(plan.arguments.contains("yuv420p10le"))
        XCTAssertTrue(plan.arguments.contains("bt2020"))
        XCTAssertTrue(plan.arguments.contains("arib-std-b67"))
        XCTAssertTrue(plan.arguments.contains("bt2020nc"))
        XCTAssertTrue(plan.arguments.contains("rotate=90"))
    }

    func testUniversalVideoCommandPlannerTracksEveryOutputCodecAsPlannableOrGap() {
        let represented = Set(SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs)
            .union(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs)

        XCTAssertEqual(represented, Set(TaptionCodecRegistry.universalOutputCodecs))
        XCTAssertTrue(SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs.contains(.av1))
        XCTAssertTrue(SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs.contains(.h264))
        XCTAssertTrue(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs.contains(.proResRaw))
        XCTAssertTrue(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs.contains(.jpegXL))
    }

    func testUniversalVideoCommandPlannerBuildsEveryPlannableSourceOutputPair() throws {
        for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
            for outputCodec in SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs {
                let route = TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
                let request = TaptionCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/input-\(sourceCodec.rawValue).mkv"),
                    outputURL: URL(fileURLWithPath: "/tmp/output-\(outputCodec.rawValue).mkv"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, container: .mkv)
                )

                let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

                XCTAssertEqual(plan.backend, .ffmpegFamily, route.displayName)
                XCTAssertEqual(plan.routeSummary, route.displayName, route.displayName)
                XCTAssertTrue(plan.arguments.contains("-c:v"), route.displayName)
                XCTAssertEqual(
                    plan.arguments.last,
                    "/tmp/output-\(outputCodec.rawValue).mkv",
                    route.displayName
                )
            }
        }
    }

    func testUniversalVideoCommandPlannerAcceptsEveryReadableInputContainer() throws {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)

        for inputContainer in SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.readableContainers.sorted(by: containerSort) {
            let request = TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.\(inputContainer.defaultFileExtension)"),
                outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
                route: route,
                options: .preservingSource(outputCodec: .av1, container: .mkv)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

            XCTAssertEqual(plan.sourceURL.pathExtension, inputContainer.defaultFileExtension, inputContainer.rawValue)
            XCTAssertEqual(plan.routeSummary, route.displayName, inputContainer.rawValue)
        }
    }

    func testUniversalVideoCommandPlannerAcceptsEveryWritableOutputContainer() throws {
        let route = TaptionCodecRoute(sourceCodec: .vp9, outputCodec: .h264)

        for outputContainer in SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.writableContainers.sorted(by: containerSort) {
            let request = TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.webm"),
                outputURL: URL(fileURLWithPath: "/tmp/output.\(outputContainer.defaultFileExtension)"),
                route: route,
                options: .preservingSource(outputCodec: .h264, container: outputContainer)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

            XCTAssertEqual(
                plan.arguments.last,
                "/tmp/output.\(outputContainer.defaultFileExtension)",
                outputContainer.rawValue
            )
        }
    }

    func testUniversalAudioCommandPlannerAcceptsEveryReadableInputContainer() throws {
        let route = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)

        for inputContainer in SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.readableContainers.sorted(by: containerSort) {
            let request = TaptionAudioCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/audio.\(inputContainer.defaultFileExtension)"),
                outputURL: URL(fileURLWithPath: "/tmp/audio-output.mkv"),
                route: route,
                options: .preservingSource(outputCodec: .flac, outputContainer: .mkv)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: request)

            XCTAssertEqual(plan.sourceURL.pathExtension, inputContainer.defaultFileExtension, inputContainer.rawValue)
            XCTAssertEqual(plan.routeSummary, route.displayName, inputContainer.rawValue)
        }
    }

    func testUniversalCommandPlannerRejectsUnknownInputContainer() {
        let videoRoute = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let videoRequest = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.notmedia"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
            route: videoRoute,
            options: .preservingSource(outputCodec: .av1, container: .mkv)
        )
        let audioRoute = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let audioRequest = TaptionAudioCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/audio.notmedia"),
            outputURL: URL(fileURLWithPath: "/tmp/audio-output.mkv"),
            route: audioRoute,
            options: .preservingSource(outputCodec: .flac, outputContainer: .mkv)
        )

        XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: videoRequest)) { error in
            XCTAssertEqual(
                error as? SW_FFmpegCodecCommandPlannerError,
                .inputContainerUnavailable(.unknown)
            )
        }
        XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: audioRequest)) { error in
            XCTAssertEqual(
                error as? SW_FFmpegCodecCommandPlannerError,
                .inputContainerUnavailable(.unknown)
            )
        }
    }

    func testVideoContainerInferenceCoversLegacyAndRawAliases() {
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "qt"), .mov)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "mts"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m2ts"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m2t"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "tp"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "trp"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "tod"), .mpegTransportStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "mpe"), .mpegProgramStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "vob"), .mpegProgramStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "mod"), .mpegProgramStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "dat"), .mpegProgramStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "divx"), .avi)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "lrf"), .lrf)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "dif"), .dv)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "ogv"), .ogg)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "ogm"), .ogg)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "f4v"), .flv)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "3gpp"), .threeGP)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "3g2"), .threeGPP2)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "3gpp2"), .threeGPP2)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "dvr-ms"), .asf)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "nut"), .nut)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "roq"), .roq)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "rm"), .realMedia)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "rmvb"), .realMedia)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "av1"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "hevc"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "264"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "265"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "h263"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m1v"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m2v"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "vc1"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "notmedia"), .unknown)
    }

    func testUniversalVideoCommandPlannerAcceptsRepresentativeReadableAliases() throws {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        let aliases: [(fileExtension: String, container: TaptionVideoContainer)] = [
            ("divx", .avi),
            ("m2t", .mpegTransportStream),
            ("tp", .mpegTransportStream),
            ("trp", .mpegTransportStream),
            ("tod", .mpegTransportStream),
            ("mpe", .mpegProgramStream),
            ("mod", .mpegProgramStream),
            ("dat", .mpegProgramStream),
            ("dif", .dv),
            ("ogm", .ogg),
            ("3gpp", .threeGP),
            ("3gpp2", .threeGPP2),
            ("dvr-ms", .asf),
            ("nut", .nut),
            ("roq", .roq),
            ("rm", .realMedia),
            ("rmvb", .realMedia),
            ("264", .rawElementaryStream),
            ("265", .rawElementaryStream),
            ("av1", .rawElementaryStream),
            ("h263", .rawElementaryStream),
            ("m1v", .rawElementaryStream),
            ("m2v", .rawElementaryStream),
            ("vc1", .rawElementaryStream)
        ]

        for alias in aliases {
            let request = TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.\(alias.fileExtension)"),
                outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
                route: route,
                options: .preservingSource(outputCodec: .av1, container: .mkv)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

            XCTAssertEqual(
                TaptionVideoContainer.inferred(fromFileExtension: alias.fileExtension),
                alias.container,
                alias.fileExtension
            )
            XCTAssertEqual(plan.sourceURL.pathExtension, alias.fileExtension, alias.fileExtension)
            XCTAssertEqual(plan.routeSummary, route.displayName, alias.fileExtension)
        }
    }

    func testImportableVideoTypesMatchCurrentLaunchInputContainers() throws {
        let launchExtensions = Set(
            TaptionLaunchSupportCatalog.supportedInputContainers
                .flatMap(\.supportedFileExtensions)
        )
        let pickerExtensions = Set(ImportableVideoTypes.fileExtensions)

        XCTAssertEqual(pickerExtensions, launchExtensions)
        XCTAssertEqual(SupportedVideoFileExtensions.fileExtensionSet, launchExtensions)

        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = rootURL
            .appendingPathComponent("TaptionEncoder/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let declarations = try XCTUnwrap(
            plist["UTImportedTypeDeclarations"] as? [[String: Any]]
        )
        let plistExtensions = Set(
            declarations.flatMap { declaration -> [String] in
                guard let tagSpecification = declaration["UTTypeTagSpecification"] as? [String: Any],
                      let fileExtensions = tagSpecification["public.filename-extension"] as? [String] else {
                    return []
                }
                return fileExtensions
            }
        )

        XCTAssertTrue(
            plistExtensions.isSuperset(of: launchExtensions),
            "Missing Info.plist video extensions: \(launchExtensions.subtracting(plistExtensions).sorted().joined(separator: ", "))"
        )
        XCTAssertTrue(SupportedVideoFileExtensions.contains(".mp4"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("qt"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("M4V"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("avi"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("webm"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("DAT"))
        XCTAssertFalse(SupportedVideoFileExtensions.contains(".m2t"))
        XCTAssertFalse(SupportedVideoFileExtensions.contains("dif"))
        XCTAssertFalse(ImportableVideoTypes.fileExtensions.contains("lrf"))
        XCTAssertFalse(ImportableVideoTypes.fileExtensions.contains("dvr-ms"))
        XCTAssertFalse(ImportableVideoTypes.fileExtensions.contains("vc1"))
    }

    func testUniversalVideoCommandPlannerRejectsEveryUnsupportedOutputCodec() {
        for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
            for outputCodec in SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs {
                let route = TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
                let request = TaptionCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/input-\(sourceCodec.rawValue).mkv"),
                    outputURL: URL(fileURLWithPath: "/tmp/output-\(outputCodec.rawValue).mkv"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, container: .mkv)
                )

                XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request), route.displayName) { error in
                    XCTAssertEqual(
                        error as? SW_FFmpegCodecCommandPlannerError,
                        .videoEncoderUnavailable(outputCodec),
                        route.displayName
                    )
                }
            }
        }
    }

    func testUniversalVideoCommandPlannerReportsEncoderGaps() {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .proResRaw)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mov"),
            route: route,
            options: .preservingSource(outputCodec: .proResRaw, container: .mov)
        )

        XCTAssertThrowsError(try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)) { error in
            XCTAssertEqual(
                error as? SW_FFmpegCodecCommandPlannerError,
                .videoEncoderUnavailable(.proResRaw)
            )
        }
    }

    func testCodecTranscodeRequestDefaultsPreserveSourceQuality() {
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)
        )

        XCTAssertEqual(request.options.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(request.options.outputPolicy.container, .mp4)
        XCTAssertEqual(request.options.outputPolicy.qualityPolicy, .preserveSourceVisuals)
        XCTAssertEqual(request.options.outputPolicy.advancedOptions, .preserveSource)
        XCTAssertTrue(request.options.preserveSourceVisualQuality)
        XCTAssertTrue(request.options.preserveAudioWhenPossible)
    }

    func testSourcePreservingOutputResolverFillsEmptyOptionsFromSourceTrack() {
        let sourceColor = TaptionColorDescription(
            primaries: .bt2020,
            transfer: .hlg,
            matrix: .bt2020NonConstantLuminance,
            bitDepth: 10,
            isHDR: true
        )
        let track = TaptionVideoTrackInfo(
            codec: .av1,
            naturalSize: TaptionPixelSize(width: 3840, height: 2160),
            displaySize: TaptionPixelSize(width: 2160, height: 3840),
            nominalFrameRate: TaptionRationalFrameRate(numerator: 60000, denominator: 1001),
            estimatedBitrate: 82_000_000,
            color: sourceColor,
            rotationDegrees: 90
        )
        let asset = TaptionVideoAsset(
            displayName: "hdr-portrait-av1.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            videoTrack: track
        )

        let policy = TaptionSourcePreservingOutputPolicyResolver.resolvedPolicy(
            for: asset,
            requestedPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )

        XCTAssertEqual(policy.videoCodec, .hevc)
        XCTAssertEqual(policy.container, .mp4)
        XCTAssertEqual(policy.qualityPolicy, .preserveSourceVisuals)
        XCTAssertEqual(policy.advancedOptions.resizeTo, track.displaySize)
        XCTAssertEqual(policy.advancedOptions.frameRate, track.nominalFrameRate)
        XCTAssertEqual(policy.advancedOptions.targetBitrate, track.estimatedBitrate)
        XCTAssertEqual(policy.advancedOptions.color, sourceColor)
        XCTAssertEqual(policy.advancedOptions.rotationDegrees, 90)
    }

    func testSourcePreservingOutputResolverKeepsExplicitAdvancedOptions() {
        let track = TaptionVideoTrackInfo(
            codec: .av1,
            naturalSize: TaptionPixelSize(width: 3840, height: 2160),
            displaySize: TaptionPixelSize(width: 3840, height: 2160),
            nominalFrameRate: TaptionRationalFrameRate(numerator: 60),
            estimatedBitrate: 82_000_000,
            color: TaptionColorDescription(primaries: .bt2020, transfer: .pq, matrix: .bt2020NonConstantLuminance, bitDepth: 10, isHDR: true),
            rotationDegrees: 0
        )
        let explicitOptions = TaptionAdvancedOutputOptions(
            resizeTo: TaptionPixelSize(width: 1280, height: 720),
            frameRate: TaptionRationalFrameRate(numerator: 24),
            targetBitrate: 6_000_000,
            color: TaptionColorDescription(primaries: .bt709, transfer: .bt709, matrix: .bt709, bitDepth: 8, isHDR: false),
            rotationDegrees: 180
        )
        let asset = TaptionVideoAsset(
            displayName: "custom-output.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            videoTrack: track
        )
        let requestedPolicy = TaptionVideoOutputPolicy(
            videoCodec: .h264,
            container: .mkv,
            qualityPolicy: .preserveSourceVisuals,
            advancedOptions: explicitOptions
        )

        let policy = TaptionSourcePreservingOutputPolicyResolver.resolvedPolicy(
            for: asset,
            requestedPolicy: requestedPolicy
        )

        XCTAssertEqual(policy.advancedOptions, explicitOptions)
    }

    func testOutputSelectionOnlyMarksCurrentImplementedOutputAsRunnable() {
        XCTAssertTrue(TaptionOutputSelection(videoCodec: .hevc, container: .mp4).isImplementedNow)
        XCTAssertTrue(TaptionOutputSelection(videoCodec: .hevc, container: .mov).isImplementedNow)
        XCTAssertFalse(TaptionOutputSelection(videoCodec: .h264, container: .mp4).isImplementedNow)
        XCTAssertFalse(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .opus, container: .mp4).isImplementedNow)
    }

    func testOutputSelectionResolutionPresetBuildsResizePolicy() {
        let selection = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            resolutionPreset: .hd720
        )

        let policy = selection.outputPolicy(for: makeAsset(sourceCodec: .h264))

        XCTAssertEqual(policy.advancedOptions.resizeTo, TaptionPixelSize(width: 1280, height: 720))
    }

    func testOutputSelectionResolutionPresetPreservesPortraitOrientation() {
        let selection = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            resolutionPreset: .hd720
        )

        let policy = selection.outputPolicy(
            for: makeAsset(
                sourceCodec: .h264,
                displaySize: TaptionPixelSize(width: 1080, height: 1920)
            )
        )

        XCTAssertEqual(policy.advancedOptions.resizeTo, TaptionPixelSize(width: 720, height: 1280))
    }

    func testOutputCatalogSeparatesImplementedCommandPlanReadyPlannedAndUnsupportedOutputs() {
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .hevc, container: .mp4),
            .implemented
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .h264, container: .mp4),
            .commandPlanReady
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .hevc, container: .mov),
            .implemented
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.implementationState(videoCodec: .proResRaw, container: .mkv),
            .planned
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
            videoCodec: .av1,
            audioCodec: .flac,
            container: .mkv
        )
        let planned = TaptionOutputSelection(
            videoCodec: .proResRaw,
            audioCodec: .xheAAC,
            container: .mkv
        )

        XCTAssertEqual(implemented.statusTitle, "Output Ready")
        XCTAssertEqual(implemented.detailText, "This exact output selection can run in the current build.")

        XCTAssertEqual(commandPlanReady.statusTitle, "Output Plan Ready")
        XCTAssertTrue(commandPlanReady.detailText.contains("AV1 / MKV output has a software command plan"))
        XCTAssertTrue(commandPlanReady.detailText.contains("FLAC / MKV audio output has a software command plan"))

        XCTAssertEqual(planned.statusTitle, "Output Planned")
        XCTAssertTrue(planned.detailText.contains("Apple ProRes RAW / MKV output is planned"))
        XCTAssertTrue(planned.detailText.contains("xHE-AAC / MKV audio output is planned"))
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
            inputSupportDetail: "The current launch build can inspect this input container and codec.",
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
        let supportedAudio = TaptionAudioCodecHardwareCapability(
            audioCodec: .aac,
            nativeDecodeSupported: true,
            nativeEncodeSupported: true,
            mp4CopySupported: true,
            movCopySupported: true
        )
        let unsupportedAudio = TaptionAudioCodecHardwareCapability(
            audioCodec: .xheAAC,
            nativeDecodeSupported: false,
            nativeEncodeSupported: false,
            mp4CopySupported: false,
            movCopySupported: false
        )

        XCTAssertTrue(supportedVideo.isSupportedOnInstalledDevice)
        XCTAssertFalse(unsupportedVideo.isSupportedOnInstalledDevice)
        XCTAssertTrue(supportedAudio.isSupportedOnInstalledDevice)
        XCTAssertFalse(unsupportedAudio.isSupportedOnInstalledDevice)
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
        XCTAssertGreaterThan(report.commandPlanReadyOutputSelectionCount, 0)
        XCTAssertGreaterThan(report.plannedOutputSelectionCount, 0)
        XCTAssertEqual(report.unsupportedOutputSelectionCount, 0)

        let currentBuildItem = report.items.first {
            $0.videoCodec == .hevc && $0.container == .mp4
        }
        let movBuildItem = report.items.first {
            $0.videoCodec == .hevc && $0.container == .mov
        }
        let commandPlanItem = report.items.first {
            $0.videoCodec == .h264 && $0.container == .mp4
        }
        let plannedItem = report.items.first {
            $0.videoCodec == .proResRaw && $0.container == .mkv
        }

        XCTAssertEqual(currentBuildItem?.state, .implemented)
        XCTAssertNil(currentBuildItem?.note)
        XCTAssertEqual(movBuildItem?.state, .implemented)
        XCTAssertNil(movBuildItem?.note)
        XCTAssertEqual(commandPlanItem?.state, .commandPlanReady)
        XCTAssertTrue(commandPlanItem?.note?.contains("software command plan") == true)
        XCTAssertEqual(plannedItem?.state, .planned)
        XCTAssertTrue(plannedItem?.note?.contains("universal codec update") == true)
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
        XCTAssertEqual(report.implementedOutputSelectionCount, 2)
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
            $0.audioCodec == .opus && $0.container == .mkv
        }
        let plannedItem = report.items.first {
            $0.audioCodec == .xheAAC && $0.container == .mp4
        }

        XCTAssertEqual(currentBuildItem?.state, .implemented)
        XCTAssertNil(currentBuildItem?.note)
        XCTAssertEqual(movBuildItem?.state, .implemented)
        XCTAssertNil(movBuildItem?.note)
        XCTAssertEqual(commandPlanItem?.state, .commandPlanReady)
        XCTAssertTrue(commandPlanItem?.note?.contains("software command plan") == true)
        XCTAssertEqual(plannedItem?.state, .planned)
        XCTAssertTrue(plannedItem?.note?.contains("universal codec update") == true)
    }

    func testLaunchSupportCatalogMatchesCurrentLaunchContract() {
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputVideoCodecs,
            [
                TaptionLaunchInputVideoSupportItem(codec: .av1, availability: .availableNow),
                TaptionLaunchInputVideoSupportItem(codec: .vp9, availability: .availableNow),
                TaptionLaunchInputVideoSupportItem(codec: .vp8, availability: .availableNow),
                TaptionLaunchInputVideoSupportItem(codec: .mpeg2, availability: .availableNow),
                TaptionLaunchInputVideoSupportItem(codec: .mpeg4Visual, availability: .availableNow),
                TaptionLaunchInputVideoSupportItem(codec: .h264, availability: .availableOnSupportedHardware),
                TaptionLaunchInputVideoSupportItem(codec: .hevc, availability: .availableOnSupportedHardware),
                TaptionLaunchInputVideoSupportItem(codec: .proRes, availability: .availableOnSupportedHardware)
            ]
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputVideoSummary,
            "AV1, VP9, VP8, MPEG-2, MPEG-4 Visual, H.264 / AVC, H.265 / HEVC, Apple ProRes"
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputContainers,
            [.mp4, .mov, .m4v, .avi, .webm, .mxf, .mpegProgramStream]
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputContainerSummary,
            "MP4, MOV, QT, M4V, AVI, DIVX, WEBM, MXF, MPG, MPEG, MPE, VOB, MOD, DAT"
        )
        XCTAssertTrue(
            TaptionLaunchSupportCatalog.supportedInputVideoNote.contains("H.264 / AVC")
        )
        XCTAssertTrue(
            TaptionLaunchSupportCatalog.supportedInputVideoNote.contains("H.265 / HEVC")
        )
        XCTAssertTrue(
            TaptionLaunchSupportCatalog.supportedInputVideoNote.contains("Apple ProRes")
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.supportedInputContainerNote,
            "The current launch build imports Apple-readable containers plus selected software-inspected inputs such as WebM, AVI, MXF, and MPEG program streams."
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .mp4, videoCodec: .av1),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input container and codec."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .avi, videoCodec: .mpeg4Visual),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input container and codec."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .mp4, videoCodec: .vp9),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input container and codec."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .webm, videoCodec: .vp8),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input container and codec."
            )
        )
        XCTAssertEqual(
            TaptionLaunchSupportCatalog.diagnoseInput(container: .mpegProgramStream, videoCodec: .mpeg2),
            TaptionLaunchInputSupportDiagnosis(
                state: .supported,
                title: "Input Supported",
                detail: "The current launch build can inspect this input container and codec."
            )
        )
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
            .commandPlanReady
        )
        XCTAssertEqual(
            TaptionCodecOutputCatalog.routeImplementationState(
                sourceCodec: .av1,
                outputCodec: .h264,
                container: .mp4
            ),
            .commandPlanReady
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
        let temporaryURL = URL(fileURLWithPath: "/tmp/output.avi")
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .h264,
            container: .avi,
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
        XCTAssertEqual(plan.codecRoute, TaptionCodecRoute(sourceCodec: .av1, outputCodec: .h264))
        XCTAssertEqual(plan.codecExecutionKind, .planned)
        XCTAssertEqual(plan.finalOutputURL?.path, "/tmp/input_taption.avi")
        XCTAssertEqual(plan.encoderSelection.requestedMode, .automatic)
        XCTAssertEqual(plan.videoCommandPlan?.routeSummary, "AV1 to H.264 / AVC")
        XCTAssertTrue(plan.videoCommandPlan?.arguments.contains("libx264") == true)
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
            videoCodec: .av1,
            audioCodec: .flac,
            container: .mkv
        )

        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/vp9-opus.webm"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/vp9-opus_taption.mkv"),
            outputPolicy: outputPolicy
        )

        XCTAssertEqual(plan.outputPolicy.audioCodec, .flac)
        XCTAssertEqual(plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac))
        XCTAssertEqual(plan.audioPlan?.options.outputCodec, .flac)
        XCTAssertEqual(plan.audioPlan?.options.outputContainer, .mkv)
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
        XCTAssertEqual(audioPlan?.readiness.readiness, .commandPlanOnly)
        XCTAssertFalse(audioPlan?.isRunnableInCurrentBuild ?? true)
        XCTAssertEqual(audioPlan?.options.sampleRate, 48_000)
        XCTAssertEqual(audioPlan?.options.channelCount, 6)
        XCTAssertEqual(audioPlan?.options.targetBitrate, 512_000)
        XCTAssertTrue(audioPlan?.commandPlan?.arguments.contains("aac") == true)
        XCTAssertTrue(audioPlan?.commandPlan?.arguments.contains("48000") == true)
        XCTAssertTrue(audioPlan?.commandPlan?.arguments.contains("6") == true)
        XCTAssertTrue(audioPlan?.commandPlan?.arguments.contains("512000") == true)
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
        XCTAssertEqual(plan.codecExecutionKind, .planned)
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

        XCTAssertTrue(message.contains("H.265 / MP4 or MOV output"))
        XCTAssertTrue(message.contains("AV1, VP9, VP8, MPEG-2, and MPEG-4 Visual with software fallback"))
        XCTAssertTrue(message.contains("H.264, H.265, or ProRes"))
        XCTAssertTrue(message.contains("H.264 / AVC"))
        XCTAssertTrue(message.contains("universal codec roadmap"))
        XCTAssertTrue(message.contains("not executable on the selected device/output path yet"))
    }

    func testLocalRealVP8WebMSampleCanPrepareHEVCJob() async throws {
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

    func testVorbisToAACOnMP4UsesBundledSoftwareDecodeAndIsRunnableNow() {
        let selection = TaptionAudioCodecRoutePlanner.selectRoute(
            sourceCodec: .vorbis,
            outputCodec: .aac,
            outputContainer: .mp4
        )
        let readiness = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .vorbis, outputCodec: .aac),
            outputContainer: .mp4
        )
        let preferredDescriptor = TaptionAudioCodecDescriptorRegistry(
            outputContainer: .mp4
        ).preferredDescriptor(
            for: TaptionAudioCodecRoute(sourceCodec: .vorbis, outputCodec: .aac)
        )

        XCTAssertEqual(selection.support, .softwareTranscode)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .appleAVAssetExport)
        XCTAssertEqual(readiness.readiness, .softwareBackendExecutable)
        XCTAssertTrue(readiness.isRunnableInCurrentBuild)
        XCTAssertFalse(readiness.hasCommandPlan)
        XCTAssertEqual(readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertEqual(preferredDescriptor?.backend, .softwareVLCDecoder)
    }

    func testLocalRealVP8WebMSampleCanEncodeHEVCWithAACAudio() async throws {
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
                    outputContainer: .mkv
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
            outputContainer: .mkv
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

    func testLoadedVideoPathInfoSummarizesCurrentPlannedAndBlockedRoutes() {
        let implemented = LoadedVideoPathInfo.make(
            sourceCodec: .av1,
            routeSelection: selectRoute(
                sourceCodec: .av1,
                outputCodec: .hevc,
                profile: .softwareOnly
            ),
            outputSelection: TaptionOutputSelection(videoCodec: .hevc, container: .mp4)
        )
        let planned = LoadedVideoPathInfo.make(
            sourceCodec: .h264,
            routeSelection: selectRoute(
                sourceCodec: .h264,
                outputCodec: .av1,
                profile: .h264HEVCHardware
            ),
            outputSelection: TaptionOutputSelection(videoCodec: .av1, container: .mkv)
        )
        let blocked = LoadedVideoPathInfo.make(
            sourceCodec: .h264,
            routeSelection: selectRoute(
                sourceCodec: .h264,
                outputCodec: .proResRaw,
                profile: .h264HEVCHardware
            ),
            outputSelection: TaptionOutputSelection(videoCodec: .proResRaw, container: .mkv)
        )

        XCTAssertEqual(implemented.title, "Path SW")
        XCTAssertEqual(implemented.outputSummary, "H.265 + AAC / MP4")
        XCTAssertTrue(implemented.isRouteEncodable, "\(implemented)")
        XCTAssertTrue(implemented.detail.contains("software fallback"), implemented.detail)

        XCTAssertEqual(planned.title, "Path SW Plan Ready")
        XCTAssertEqual(planned.outputSummary, "AV1 + AAC / MKV")
        XCTAssertFalse(planned.isRouteEncodable)
        XCTAssertTrue(planned.detail.contains("FFmpeg-family backend command can be planned"))
        XCTAssertTrue(planned.detail.contains("AV1 / MKV output has a software command plan"))

        XCTAssertEqual(blocked.title, "Path SW Blocked")
        XCTAssertEqual(blocked.outputSummary, "Apple ProRes RAW + AAC / MKV")
        XCTAssertFalse(blocked.isRouteEncodable)
        XCTAssertTrue(blocked.detail.contains("Apple ProRes RAW has no selected software video encoder"))
    }

    func testLoadedVideoPathInfoExplainsProResRawSampleGate() {
        let planned = LoadedVideoPathInfo.make(
            sourceCodec: .proResRaw,
            routeSelection: selectRoute(
                sourceCodec: .proResRaw,
                outputCodec: .hevc,
                profile: appleProfile("apple_a19pro_av1_decode_prores_raw")
            ),
            outputSelection: TaptionOutputSelection(videoCodec: .hevc, container: .mp4)
        )

        XCTAssertEqual(planned.title, "Path Planned")
        XCTAssertEqual(planned.outputSummary, "H.265 + AAC / MP4")
        XCTAssertFalse(planned.isRouteEncodable)
        XCTAssertTrue(planned.detail.contains("ProRes RAW to H.265 needs real-world sample proof"))
        XCTAssertTrue(planned.detail.contains("runtime verification"))
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
            XCTAssertEqual(info.outputSummary, "H.265 + AAC / MP4", sourceCodec.rawValue)
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
            inputSupportDetail: "The current launch build can inspect this input container and codec.",
            isInputSupportedNow: true,
            codecPathTitle: "Path SW Plan Ready",
            codecPathDetail: "Command plan only.",
            outputSummary: "AV1 / MKV",
            outputName: "sample_taption.mkv",
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
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
            route: TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac),
            options: .preservingSource(outputCodec: .flac, outputContainer: .mkv)
        )

        XCTAssertEqual(request.options.outputCodec, .flac)
        XCTAssertEqual(request.options.outputContainer, .mkv)
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
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
            route: route,
            options: .preservingSource(outputCodec: .flac, outputContainer: .mkv)
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
            outputURL: URL(fileURLWithPath: "/tmp/output.mkv"),
            route: route,
            options: .preservingSource(outputCodec: .flac, outputContainer: .mkv)
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
        let outputURL = temporaryTestURL(fileName: "opus-to-flac.mkv")
        try? FileManager.default.removeItem(at: outputURL)
        let route = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let request = TaptionAudioCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.webm"),
            outputURL: outputURL,
            route: route,
            options: .preservingSource(outputCodec: .flac, outputContainer: .mkv)
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
        XCTAssertEqual(output.outputContainer, .mkv)
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testUniversalAudioCommandPlanBuildsTranscodeAndCopyRoutes() throws {
        let opusToFLAC = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let opusPlan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(
            request: TaptionAudioCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/opus.webm"),
                outputURL: URL(fileURLWithPath: "/tmp/flac.mkv"),
                route: opusToFLAC,
                options: .preservingSource(outputCodec: .flac, outputContainer: .mkv)
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
        XCTAssertTrue(opusPlan.arguments.contains("/tmp/flac.mkv"))

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

    func testVideoExecutionReadinessReportSeparatesCurrentBuildCommandPlansAndEncoderGaps() {
        let report = TaptionVideoCodecExecutionReadinessReporter.makeReport(outputContainer: .mkv)
        let expectedRouteCount = TaptionCodecRegistry.universalSourceCodecs.count
            * TaptionCodecRegistry.universalOutputCodecs.count

        XCTAssertEqual(report.routeCount, expectedRouteCount)
        XCTAssertTrue(report.allRoutesHaveExecutionPath)
        XCTAssertFalse(report.allRoutesRunnableInCurrentBuild)
        XCTAssertEqual(report.runnableInCurrentBuildRouteCount, TaptionCodecRegistry.softwareImplementedRoutes.count)
        XCTAssertEqual(report.implementedRouteCount, TaptionCodecRegistry.softwareImplementedRoutes.count)
        XCTAssertGreaterThan(report.commandPlanOnlyRouteCount, 0)
        XCTAssertGreaterThan(report.blockedMissingSoftwareEncoderRouteCount, 0)
        XCTAssertEqual(
            Set(report.blockedOutputCodecs),
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs)
        )

        let implementedItem = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc),
            outputContainer: .mkv
        )
        XCTAssertEqual(implementedItem.readiness, .implementedInCurrentBuild)
        XCTAssertTrue(implementedItem.isRunnableInCurrentBuild)
        XCTAssertTrue(implementedItem.hasCommandPlan)

        let commandOnlyItem = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1),
            outputContainer: .mkv
        )
        XCTAssertEqual(commandOnlyItem.readiness, .commandPlanOnly)
        XCTAssertFalse(commandOnlyItem.isRunnableInCurrentBuild)
        XCTAssertTrue(commandOnlyItem.hasCommandPlan)
        XCTAssertEqual(commandOnlyItem.commandBackend, .ffmpegFamily)

        let blockedItem = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .proResRaw),
            outputContainer: .mkv
        )
        XCTAssertEqual(blockedItem.readiness, .blockedMissingSoftwareEncoder)
        XCTAssertFalse(blockedItem.isRunnableInCurrentBuild)
        XCTAssertFalse(blockedItem.hasCommandPlan)
        XCTAssertTrue(blockedItem.blockingReason?.contains("Apple ProRes RAW") == true)
    }

    func testVideoExecutionReadinessReportPromotesCommandPlansWhenBroadBackendShips() {
        let item = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1),
            outputContainer: .mkv,
            broadSoftwareBackendExecutable: true
        )
        let report = TaptionVideoCodecExecutionReadinessReporter.makeReport(
            outputContainer: .mkv,
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
            Set(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs)
        )
    }

    func testAudioExecutionReadinessReportSeparatesCurrentBuildCommandPlansAndEncoderGaps() {
        let report = TaptionAudioCodecExecutionReadinessReporter.makeReport(outputContainer: .mkv)
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
            outputContainer: .mkv
        )
        XCTAssertEqual(copyItem.readiness, .copyInCurrentBuild)
        XCTAssertTrue(copyItem.isRunnableInCurrentBuild)
        XCTAssertTrue(copyItem.hasCommandPlan)

        let nativeItem = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .pcm),
            outputContainer: .mkv
        )
        XCTAssertEqual(nativeItem.readiness, .nativeTranscodeInCurrentBuild)
        XCTAssertTrue(nativeItem.isRunnableInCurrentBuild)
        XCTAssertFalse(nativeItem.hasCommandPlan)

        let commandOnlyItem = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac),
            outputContainer: .mkv
        )
        XCTAssertEqual(commandOnlyItem.readiness, .commandPlanOnly)
        XCTAssertFalse(commandOnlyItem.isRunnableInCurrentBuild)
        XCTAssertTrue(commandOnlyItem.hasCommandPlan)
        XCTAssertEqual(commandOnlyItem.commandBackend, .ffmpegFamily)

        let blockedItem = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .aac, outputCodec: .xheAAC),
            outputContainer: .mkv
        )
        XCTAssertEqual(blockedItem.readiness, .blockedMissingSoftwareEncoder)
        XCTAssertFalse(blockedItem.isRunnableInCurrentBuild)
        XCTAssertFalse(blockedItem.hasCommandPlan)
        XCTAssertTrue(blockedItem.blockingReason?.contains("xHE-AAC") == true)
    }

    func testAudioExecutionReadinessReportPromotesCommandPlansWhenBroadBackendShips() {
        let item = TaptionAudioCodecExecutionReadinessReporter.item(
            for: TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac),
            outputContainer: .mkv,
            broadSoftwareBackendExecutable: true
        )
        let report = TaptionAudioCodecExecutionReadinessReporter.makeReport(
            outputContainer: .mkv,
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
                    outputURL: URL(fileURLWithPath: "/tmp/audio-\(outputCodec.rawValue).mkv"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, outputContainer: .mkv)
                )

                let plan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: request)

                XCTAssertEqual(plan.backend, .ffmpegFamily, route.displayName)
                XCTAssertEqual(plan.routeSummary, route.displayName, route.displayName)
                XCTAssertTrue(plan.arguments.contains("-c:a"), route.displayName)
                XCTAssertEqual(
                    plan.arguments.last,
                    "/tmp/audio-\(outputCodec.rawValue).mkv",
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
                    outputURL: URL(fileURLWithPath: "/tmp/audio-\(outputCodec.rawValue).mkv"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, outputContainer: .mkv)
                )

                if sourceCodec == outputCodec {
                    let plan = try? SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: request)
                    XCTAssertNotNil(plan, route.displayName)
                    XCTAssertTrue(plan?.arguments.contains("copy") == true, route.displayName)
                    continue
                }

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
        XCTAssertEqual(selection.decodeBackend, .ffmpegFamily)
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

        XCTAssertTrue(reconciliation.isKnownModel)
        XCTAssertTrue(reconciliation.isConsistentWithStaticMatrix)
        XCTAssertEqual(reconciliation.matchedMarketingName, "iPhone 15 Pro")
        XCTAssertEqual(reconciliation.matchedProfileID, "apple_a17pro_av1_decode")
        XCTAssertEqual(Set(reconciliation.expectedHardwareDecodeCodecs), expectedDecode)
        XCTAssertEqual(Set(reconciliation.expectedHardwareEncodeCodecs), expectedEncode)
        XCTAssertTrue(reconciliation.missingExpectedDecodeCodecs.isEmpty)
        XCTAssertTrue(reconciliation.unexpectedDecodeCodecs.isEmpty)
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
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"routeSimulationSummary\"") == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"staticMatrixReconciliation\"") == true)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("\"universalCodecCompletionAudit\"") == true)
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
        XCTAssertEqual(loadedSnapshots.first?.universalCodecCompletionAudit?.contractName, "All-to-All Universal Codec Mesh")
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
        XCTAssertTrue(report.commandUnsupportedVideoOutputCodecs.contains(.proResRaw))
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

        XCTAssertFalse(bundledCandidateReport.isReadyForReleaseNotices)
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

    func testOpenSourceNoticeLicenseTextResourcesAreBundledAndReadable() {
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
        let commandPlan = try makeH264ToAV1CommandPlan()
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
        let outputURL = temporaryTestURL(fileName: "universal-command-output.mkv")
        try? FileManager.default.removeItem(at: outputURL)
        let commandPlan = try makeH264ToAV1CommandPlan(outputURL: outputURL)
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
        XCTAssertEqual(result.stdoutTail, "encoded H.264 / AVC to AV1")
        XCTAssertEqual(result.stderrTail, "frame=42")
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testEncoderServiceRunsPreparedSoftwareCommandPlanWhenBroadBackendIsReady() async throws {
        let outputURL = temporaryTestURL(fileName: "h264-to-av1.mkv")
        try? FileManager.default.removeItem(at: outputURL)
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: makeAsset(sourceCodec: .h264),
            sourceURL: URL(fileURLWithPath: "/tmp/h264-source.mp4"),
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .av1, container: .mkv),
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let executor = SW_FFmpegCommandExecutor(
            readinessReport: readyBroadSoftwareBackendReport(),
            runner: FakeFFmpegCommandRunner { commandPlan in
                XCTAssertEqual(commandPlan, plan.videoCommandPlan)
                try FileManager.default.createDirectory(
                    at: commandPlan.outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("encoded through app encoder service".utf8).write(to: commandPlan.outputURL)
                return SW_FFmpegCommandRunResult(exitCode: 0, stderr: "frame=12")
            }
        )
        let service = AVFoundationHEVCEncoderService(softwareExecutor: executor)
        var progressStages: [TaptionEncodingStage] = []

        let result = try await service.encode(plan: plan) { progress in
            progressStages.append(progress.stage)
        }

        XCTAssertEqual(plan.codecRoute, TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1))
        XCTAssertEqual(plan.codecExecutionKind, .planned)
        XCTAssertNotNil(plan.videoCommandPlan)
        XCTAssertEqual(result.temporaryOutputURL, outputURL)
        XCTAssertEqual(result.finalOutputURL?.lastPathComponent, "h264-source_taption.mkv")
        XCTAssertEqual(result.usedBackend, .ffmpegFamily)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testEncoderServiceKeepsPreparedNoAudioSoftwareCommandPlan() async throws {
        let outputURL = temporaryTestURL(fileName: "silent-h264-to-av1.mkv")
        try? FileManager.default.removeItem(at: outputURL)
        let silentAsset = TaptionVideoAsset(
            displayName: "silent-h264.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .h264,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: []
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: silentAsset,
            sourceURL: URL(fileURLWithPath: "/tmp/silent-h264-source.mp4"),
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .av1, container: .mkv),
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
        )
        let executor = SW_FFmpegCommandExecutor(
            readinessReport: readyBroadSoftwareBackendReport(),
            runner: FakeFFmpegCommandRunner { commandPlan in
                XCTAssertEqual(commandPlan, plan.videoCommandPlan)
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
        let service = AVFoundationHEVCEncoderService(softwareExecutor: executor)

        let result = try await service.encode(plan: plan, progress: { _ in })

        XCTAssertNil(plan.audioPlan)
        XCTAssertEqual(result.temporaryOutputURL, outputURL)
        XCTAssertEqual(result.usedBackend, .ffmpegFamily)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testEncoderServicePrefersDirectSoftwareAlgorithmOverPreparedCommandPlan() async throws {
        let route = TaptionCodecRoute(sourceCodec: .vp9, outputCodec: .hevc)
        let sourceURL = URL(fileURLWithPath: "/tmp/direct-software-source.webm")
        let outputURL = temporaryTestURL(fileName: "direct-software-vp9-to-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)

        let directDescriptor = TaptionCodecAlgorithmDescriptor(
            route: route,
            mode: .software,
            backend: .softwareVLCDecoder,
            displayName: "direct vp9->hevc"
        )
        let registry = TaptionCodecTranscodingRegistry(
            algorithms: [
                TaptionCodecTranscodingAlgorithmEntry(
                    descriptor: directDescriptor,
                    transcode: { request, progress in
                        progress(TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0))
                        progress(TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.5))
                        try FileManager.default.createDirectory(
                            at: request.outputURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try Data("direct software output".utf8).write(to: request.outputURL)
                        progress(TaptionEncodingProgress(stage: .completed, fractionCompleted: 1))
                        return TaptionCodecTranscodeOutput(
                            outputURL: request.outputURL,
                            route: request.route,
                            usedMode: .software,
                            usedBackend: .softwareVLCDecoder,
                            outputVideoCodec: .hevc,
                            outputAudioTrackCount: 0
                        )
                    }
                )
            ]
        )
        let commandPlan = SW_FFmpegCommandPlan(
            sourceURL: sourceURL,
            outputURL: outputURL,
            routeSummary: route.displayName,
            arguments: ["-i", sourceURL.path, outputURL.path]
        )
        let plan = TaptionEncodingPlan(
            input: TaptionEncodingInput(kind: .singleAsset),
            outputPolicy: TaptionVideoOutputPolicy(
                videoCodec: .hevc,
                audioCodec: .aac,
                container: .mp4
            ),
            codecRoute: route,
            codecExecutionKind: .software,
            videoCommandPlan: commandPlan,
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none),
            encoderSelection: TaptionEncoderSelection(
                requestedMode: .software,
                backend: .customSoftware,
                reason: "Direct software transcoder is available."
            ),
            sourceURL: sourceURL,
            temporaryOutputURL: outputURL
        )
        let executor = SW_FFmpegCommandExecutor(
            readinessReport: readyBroadSoftwareBackendReport(),
            runner: FakeFFmpegCommandRunner { _ in
                XCTFail("Prepared FFmpeg command plan should not run when a direct software algorithm exists.")
                return SW_FFmpegCommandRunResult(exitCode: 0)
            }
        )
        let service = AVFoundationHEVCEncoderService(
            registry: registry,
            softwareExecutor: executor
        )
        var progressStages: [TaptionEncodingStage] = []

        let result = try await service.encode(plan: plan) { progress in
            progressStages.append(progress.stage)
        }

        XCTAssertEqual(result.temporaryOutputURL, outputURL)
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testFFmpegCommandExecutorSurfacesRunnerFailureWithStderrTail() async throws {
        let commandPlan = try makeH264ToAV1CommandPlan()
        let executor = SW_FFmpegCommandExecutor(
            readinessReport: readyBroadSoftwareBackendReport(),
            runner: FakeFFmpegCommandRunner { _ in
                SW_FFmpegCommandRunResult(
                    exitCode: 64,
                    stderr: "unsupported encoder settings"
                )
            }
        )

        do {
            _ = try await executor.execute(commandPlan, progress: { _ in })
            XCTFail("Runner failure should surface as a command failure.")
        } catch let error as SW_FFmpegCommandExecutionError {
            XCTAssertEqual(
                error,
                .commandFailed(exitCode: 64, stderrTail: "unsupported encoder settings")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSoftwareBackendRegistryCoversLegacyAndModernContainers() {
        let backend = SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate

        XCTAssertTrue(backend.canReadContainer(.mp4))
        XCTAssertTrue(backend.canReadContainer(.mov))
        XCTAssertTrue(backend.canReadContainer(.avi))
        XCTAssertTrue(backend.canReadContainer(.lrf))
        XCTAssertTrue(backend.canReadContainer(.webm))
        XCTAssertTrue(backend.canWriteContainer(.mp4))
        XCTAssertTrue(backend.canWriteContainer(.mov))
        XCTAssertTrue(backend.canWriteContainer(.avi))
        XCTAssertTrue(backend.canWriteContainer(.webm))
    }

    @MainActor
    func testPendingSaveConflictPromptsBeforeOverwritingExistingOutput() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = directoryURL.appendingPathComponent("clip_taption.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)
        try Data("existing output".utf8).write(to: finalURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )
        try await store.savePendingState(state)
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForSaveConflictPrompt(in: viewModel)

        XCTAssertEqual(viewModel.saveConflictPrompt?.existingURL, finalURL)
        XCTAssertEqual(viewModel.saveConflictPrompt?.suggestedURL.lastPathComponent, "clip_taption 2.mp4")
        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "existing output")
        XCTAssertEqual(try String(contentsOf: temporaryURL, encoding: .utf8), "new output")

        let states = try await store.loadPendingStates()
        XCTAssertEqual(states.map(\.id), [state.id])
        XCTAssertEqual(states.first?.requiresRewardedAd, false)
    }

    @MainActor
    func testResolutionAvailabilityUsesSourceOrientation() {
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: FakePendingSaveStore())
        )
        let portraitAsset = makeAsset(
            sourceCodec: .h264,
            displaySize: TaptionPixelSize(width: 1080, height: 1920)
        )

        XCTAssertTrue(viewModel.resolutionPresetIsAvailable(TaptionOutputResolutionPreset.fullHD, for: portraitAsset))
        XCTAssertTrue(viewModel.resolutionPresetIsAvailable(TaptionOutputResolutionPreset.hd720, for: portraitAsset))
        XCTAssertFalse(viewModel.resolutionPresetIsAvailable(TaptionOutputResolutionPreset.qhd1440, for: portraitAsset))
    }

    @MainActor
    func testRecoverFolderAccessStillSavesAfterPromptWasDismissed() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = directoryURL.appendingPathComponent("clip_taption.mp4")
        let pickedFileURL = directoryURL.appendingPathComponent("picked.mp4")
        try Data("new output".utf8).write(to: temporaryURL)
        try Data("picked".utf8).write(to: pickedFileURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )
        try await store.savePendingState(state)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        XCTAssertNil(viewModel.folderAccessPrompt)

        viewModel.recoverFolderAccessForPendingSave(url: pickedFileURL)
        try await waitForCompletedSave(in: viewModel)

        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "new output")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        let states = try await store.loadPendingStates()
        XCTAssertTrue(states.isEmpty)
    }

    @MainActor
    func testPendingSaveRestoreShowsEncodedOutputSizeInSizeTile() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let temporaryContents = Data("new output".utf8)
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = directoryURL.appendingPathComponent("clip_taption.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try temporaryContents.write(to: temporaryURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )
        try await store.savePendingState(state)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()

        let expectedSize = ByteCountFormatter.string(
            fromByteCount: Int64(temporaryContents.count),
            countStyle: .file
        )
        XCTAssertEqual(viewModel.outputSizeDisplayText, expectedSize)
        XCTAssertEqual(viewModel.outputSizeSecondaryText, "Encoded")
        XCTAssertEqual(viewModel.outputSizeStatusMessage, "Encoded output: \(expectedSize).")
    }

    @MainActor
    func testAutoSizeShowsEstimatedOutputInMainTileAndPopoverValue() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: sourceURL)
        let asset = makeAsset(sourceCodec: .av1, fileSize: 400_000_000)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: asset)
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertEqual(viewModel.outputSizeDisplayText, "Auto")
        XCTAssertEqual(viewModel.outputSizeSecondaryText, "400 MB")
        XCTAssertEqual(viewModel.selectedOutputTargetSizeText, "400 MB")
        XCTAssertNil(viewModel.outputSizeStatusMessage)
        XCTAssertEqual(viewModel.outputTargetSizeRangeMB.lowerBound, 100)
        XCTAssertEqual(viewModel.outputTargetSizeRangeMB.upperBound, 400)
    }

    @MainActor
    func testManualSizeUsesChosenValueAndClampsToAutoMaximum() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: sourceURL)
        let asset = makeAsset(sourceCodec: .av1, fileSize: 400_000_000)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: asset)
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        viewModel.selectOutputSize(.manual)
        XCTAssertEqual(viewModel.outputSizeDisplayText, "400 MB")
        XCTAssertNil(viewModel.outputSizeSecondaryText)

        viewModel.updateOutputTargetSizeMB(250)
        XCTAssertEqual(viewModel.outputSizeDisplayText, "250 MB")
        XCTAssertEqual(viewModel.selectedOutputTargetSizeText, "250 MB")
        XCTAssertNil(viewModel.outputSizeSecondaryText)

        viewModel.updateOutputTargetSizeMB(450)
        XCTAssertEqual(viewModel.outputSizeDisplayText, "400 MB")
        XCTAssertEqual(viewModel.selectedOutputTargetSizeText, "400 MB")
        XCTAssertEqual(viewModel.selectedOutputTargetSizeValueMB, 400)
    }

    @MainActor
    func testRestoredPendingSaveDoesNotAutoPromptForFolderAccess() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = directoryURL.appendingPathComponent("clip_taption.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )
        try await store.savePendingState(state)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()

        XCTAssertNil(viewModel.folderAccessPrompt)
        XCTAssertNil(viewModel.pendingSaveExportPrompt)
        XCTAssertNotNil(viewModel.pendingSaveRecoveryJob)
    }

    @MainActor
    func testPermissionDeniedPendingSaveRequestsExportPrompt() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            chmod(directoryURL.path, 0o755)
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let readOnlyDirectoryURL = directoryURL.appendingPathComponent("ReadOnly", isDirectory: true)
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = readOnlyDirectoryURL.appendingPathComponent("clip_taption.mp4")
        try FileManager.default.createDirectory(at: readOnlyDirectoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)
        chmod(readOnlyDirectoryURL.path, 0o555)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )
        try await store.savePendingState(state)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForCondition(timeout: 2) {
            viewModel.pendingSaveExportPrompt != nil
        }

        XCTAssertNil(viewModel.folderAccessPrompt)
        XCTAssertEqual(viewModel.pendingSaveExportPrompt?.job.id, state.id)
        XCTAssertEqual(
            viewModel.pendingSaveExportPrompt?.exportPresentationURL.lastPathComponent,
            finalURL.lastPathComponent
        )
        XCTAssertNotEqual(
            viewModel.pendingSaveExportPrompt?.exportPresentationURL.lastPathComponent,
            temporaryURL.lastPathComponent
        )
    }

    @MainActor
    func testPermissionDeniedPendingSaveExportCompletesAfterPromptDismissalRace() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            chmod(directoryURL.path, 0o755)
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let readOnlyDirectoryURL = directoryURL.appendingPathComponent("ReadOnly", isDirectory: true)
        let exportDirectoryURL = directoryURL.appendingPathComponent("Recovered", isDirectory: true)
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = readOnlyDirectoryURL.appendingPathComponent("clip_taption.mp4")
        let exportURL = exportDirectoryURL.appendingPathComponent("clip_taption.mp4")
        try FileManager.default.createDirectory(at: readOnlyDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportDirectoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)
        chmod(readOnlyDirectoryURL.path, 0o555)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )
        try await store.savePendingState(state)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForPendingSaveExportPrompt(in: viewModel)

        let prompt = try XCTUnwrap(viewModel.pendingSaveExportPrompt)
        try FileManager.default.copyItem(at: prompt.exportPresentationURL, to: exportURL)

        viewModel.dismissPendingSaveExportPrompt()
        viewModel.completePendingSaveExport(prompt: prompt, destinationURL: exportURL)
        try await waitForCompletedSave(in: viewModel)

        XCTAssertNil(viewModel.pendingSaveExportPrompt)
        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(
            viewModel.state.detail,
            expectedCompletedSaveDetail(
                url: exportURL,
                fileByteCount: Data("new output".utf8).count
            )
        )
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Save Complete")
        XCTAssertNil(viewModel.fileCardSnapshots.first?.detailText)
        XCTAssertEqual(try String(contentsOf: exportURL, encoding: .utf8), "new output")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        let states = try await store.loadPendingStates()
        XCTAssertTrue(states.isEmpty)
    }

    @MainActor
    func testPermissionDeniedPendingSaveExportCancelKeepsPendingState() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            chmod(directoryURL.path, 0o755)
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let readOnlyDirectoryURL = directoryURL.appendingPathComponent("ReadOnly", isDirectory: true)
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = readOnlyDirectoryURL.appendingPathComponent("clip_taption.mp4")
        try FileManager.default.createDirectory(at: readOnlyDirectoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)
        chmod(readOnlyDirectoryURL.path, 0o555)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )
        try await store.savePendingState(state)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForPendingSaveExportPrompt(in: viewModel)

        viewModel.dismissPendingSaveExportPrompt()

        XCTAssertNil(viewModel.pendingSaveExportPrompt)
        XCTAssertEqual(viewModel.pendingSaveRecoveryJob?.id, state.id)
        XCTAssertEqual(viewModel.state.title, "Pending save")
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryURL.path))
        let states = try await store.loadPendingStates()
        XCTAssertEqual(states.map(\.id), [state.id])
    }

    @MainActor
    func testExportRecoveryKeepsSaveCompleteVisibleWhileAnotherPendingSaveRemainsQueued() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            chmod(directoryURL.path, 0o755)
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let readOnlyDirectoryURL = directoryURL.appendingPathComponent("ReadOnly", isDirectory: true)
        let recoveredDirectoryURL = directoryURL.appendingPathComponent("Recovered", isDirectory: true)
        let firstTemporaryURL = directoryURL.appendingPathComponent("first-encoded.mp4")
        let firstFinalURL = readOnlyDirectoryURL.appendingPathComponent("first_taption.mp4")
        let recoveredFirstURL = recoveredDirectoryURL.appendingPathComponent("first_taption.mp4")
        let secondTemporaryURL = directoryURL.appendingPathComponent("second-encoded.mp4")
        let secondFinalURL = directoryURL.appendingPathComponent("second_taption.mp4")
        try FileManager.default.createDirectory(at: readOnlyDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recoveredDirectoryURL, withIntermediateDirectories: true)
        try Data("first output".utf8).write(to: firstTemporaryURL)
        try Data("second output".utf8).write(to: secondTemporaryURL)
        chmod(readOnlyDirectoryURL.path, 0o555)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let firstState = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: firstTemporaryURL,
            finalOutputURL: firstFinalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let secondState = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: secondTemporaryURL,
            finalOutputURL: secondFinalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        try await store.savePendingState(firstState)
        try await store.savePendingState(secondState)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForPendingSaveExportPrompt(in: viewModel)

        let prompt = try XCTUnwrap(viewModel.pendingSaveExportPrompt)
        try FileManager.default.copyItem(at: prompt.exportPresentationURL, to: recoveredFirstURL)

        viewModel.completePendingSaveExport(prompt: prompt, destinationURL: recoveredFirstURL)
        try await waitForCondition(timeout: 2) {
            if case .completed = viewModel.state {
                return viewModel.state.detail == self.expectedCompletedSaveDetail(
                    url: recoveredFirstURL,
                    fileByteCount: Data("first output".utf8).count
                )
                    && viewModel.showsSaveAction
                    && viewModel.saveActionTitle == "Save Next"
            }
            return false
        }

        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Save Complete")
        XCTAssertNil(viewModel.fileCardSnapshots.first?.detailText)
        XCTAssertEqual(try String(contentsOf: recoveredFirstURL, encoding: .utf8), "first output")

        viewModel.saveCurrentPendingOutput()
        try await waitForCondition(timeout: 2) {
            if case .completed = viewModel.state {
                return viewModel.state.detail == self.expectedCompletedSaveDetail(
                    url: secondFinalURL,
                    fileByteCount: Data("second output".utf8).count
                )
                    && !viewModel.showsSaveAction
            }
            return false
        }

        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(try String(contentsOf: secondFinalURL, encoding: .utf8), "second output")
        let states = try await store.loadPendingStates()
        XCTAssertTrue(states.isEmpty)
    }

    @MainActor
    func testPendingSaveOverwriteChoiceReplacesExistingOutputWithoutAnotherAd() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = directoryURL.appendingPathComponent("clip_taption.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)
        try Data("existing output".utf8).write(to: finalURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )
        try await store.savePendingState(state)
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForSaveConflictPrompt(in: viewModel)
        viewModel.overwriteExistingPendingSave()
        try await waitForCompletedSave(in: viewModel)

        XCTAssertNil(viewModel.saveConflictPrompt)
        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "new output")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        let expectedSize = ByteCountFormatter.string(
            fromByteCount: Int64(Data("new output".utf8).count),
            countStyle: .file
        )
        XCTAssertEqual(viewModel.outputSizeDisplayText, expectedSize)
        XCTAssertEqual(viewModel.outputSizeSecondaryText, "Encoded")
        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(
            viewModel.state.detail,
            expectedCompletedSaveDetail(
                url: finalURL,
                fileByteCount: Data("new output".utf8).count
            )
        )
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Save Complete")
        XCTAssertNil(viewModel.fileCardSnapshots.first?.detailText)
        let states = try await store.loadPendingStates()
        XCTAssertTrue(states.isEmpty)
    }

    @MainActor
    func testPendingSaveSaveAsChoicePromptsForFileNameAndWritesCustomFile() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = directoryURL.appendingPathComponent("clip_taption.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)
        try Data("existing output".utf8).write(to: finalURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )
        try await store.savePendingState(state)
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForSaveConflictPrompt(in: viewModel)
        viewModel.savePendingOutputAsNewFile()
        let renamePrompt = try XCTUnwrap(viewModel.pendingSaveRenamePrompt)
        XCTAssertEqual(renamePrompt.suggestedFileName, "clip_taption 2.mp4")
        let customURL = directoryURL.appendingPathComponent("clip_taption_custom.mp4")
        viewModel.confirmPendingSaveAsNewFile(named: "clip_taption_custom")
        try await waitForCompletedSave(in: viewModel)

        XCTAssertNil(viewModel.saveConflictPrompt)
        XCTAssertNil(viewModel.pendingSaveRenamePrompt)
        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "existing output")
        XCTAssertEqual(try String(contentsOf: customURL, encoding: .utf8), "new output")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(
            viewModel.state.detail,
            expectedCompletedSaveDetail(
                url: customURL,
                fileByteCount: Data("new output".utf8).count
            )
        )
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Save Complete")
        XCTAssertNil(viewModel.fileCardSnapshots.first?.detailText)
        let states = try await store.loadPendingStates()
        XCTAssertTrue(states.isEmpty)
    }

    @MainActor
    func testCompletedSaveStaysVisibleWhileAnotherPendingSaveRemainsQueued() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let firstTemporaryURL = directoryURL.appendingPathComponent("first-encoded.mp4")
        let firstFinalURL = directoryURL.appendingPathComponent("first_taption.mp4")
        let secondTemporaryURL = directoryURL.appendingPathComponent("second-encoded.mp4")
        let secondFinalURL = directoryURL.appendingPathComponent("second_taption.mp4")
        try Data("first output".utf8).write(to: firstTemporaryURL)
        try Data("second output".utf8).write(to: secondTemporaryURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let firstState = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: firstTemporaryURL,
            finalOutputURL: firstFinalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let secondState = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: secondTemporaryURL,
            finalOutputURL: secondFinalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        try await store.savePendingState(firstState)
        try await store.savePendingState(secondState)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForCondition(timeout: 2) {
            if case .completed = viewModel.state {
                return viewModel.state.detail == self.expectedCompletedSaveDetail(
                    url: firstFinalURL,
                    fileByteCount: Data("first output".utf8).count
                )
                    && viewModel.showsSaveAction
                    && viewModel.saveActionTitle == "Save Next"
            }
            return false
        }

        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Save Complete")
        XCTAssertNil(viewModel.fileCardSnapshots.first?.detailText)
        XCTAssertNil(viewModel.pendingSaveRecoveryJob)
        XCTAssertEqual(try String(contentsOf: firstFinalURL, encoding: .utf8), "first output")

        viewModel.saveCurrentPendingOutput()
        try await waitForCondition(timeout: 2) {
            if case .completed = viewModel.state {
                return viewModel.state.detail == self.expectedCompletedSaveDetail(
                    url: secondFinalURL,
                    fileByteCount: Data("second output".utf8).count
                )
                    && !viewModel.showsSaveAction
            }
            return false
        }

        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(try String(contentsOf: secondFinalURL, encoding: .utf8), "second output")
        let states = try await store.loadPendingStates()
        XCTAssertTrue(states.isEmpty)
    }

    func testSaveFailurePresenterRecognizesCocoaFileExistsAsConflict() {
        let underlying = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(POSIXErrorCode.EEXIST.rawValue),
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. File exists"]
        )
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileWriteFileExists.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "encoded.mp4 couldn’t be copied because an item with the same name already exists.",
                NSUnderlyingErrorKey: underlying
            ]
        )

        XCTAssertTrue(TaptionFinalSaveConflictError.isDestinationAlreadyExistsError(error))

        let presentation = TaptionSaveFailurePresenter.presentation(
            for: error,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false
        )

        XCTAssertEqual(presentation.cause, "A file already exists at the save destination.")
        XCTAssertTrue(presentation.action.contains("Choose Overwrite"))
        XCTAssertTrue(presentation.action.contains("Retry will save without another ad"))
    }

    @MainActor
    func testStorageBlockedShowsLowSpaceWarningInSizeTile() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: sourceURL)

        let requiredBytes = Int64(800 * 1024 * 1024)
        let availableBytes = Int64(200 * 1024 * 1024)
        let storageChecker = FixedStorageChecker(
            requirement: TaptionStorageRequirement(
                estimatedOutputBytes: 400 * 1024 * 1024,
                requiredWorkingBytes: requiredBytes,
                availableBytes: availableBytes
            )
        )
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                storageChecker: storageChecker
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForStorageBlockedState(in: viewModel)

        let requiredText = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
        let availableText = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
        XCTAssertEqual(viewModel.outputSizeDisplayText, "Auto")
        XCTAssertEqual(viewModel.outputSizeSecondaryText, "Low Space")
        XCTAssertTrue(viewModel.outputSizeShowsWarning)
        XCTAssertEqual(
            viewModel.outputSizeStatusMessage,
            "Low space. Need \(requiredText) free. Available \(availableText)."
        )
    }

    func testTaptionSavePolicyDefaultsToNoRewardedSaveGate() {
        XCTAssertEqual(TaptionSavePolicy().saveGate, .none)
    }

    func testStarWalletBadgeTextUsesFixedWidthFormatting() {
        XCTAssertEqual(makeStarWalletSnapshot(balance: 0).badgeText, "000")
        XCTAssertEqual(makeStarWalletSnapshot(balance: 7).badgeText, "007")
        XCTAssertEqual(makeStarWalletSnapshot(balance: 123).badgeText, "123")
        XCTAssertEqual(makeStarWalletSnapshot(balance: 1_200).badgeText, "999+")
    }

    func testStarWalletStoreRoundTripsEncryptedSnapshot() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let secureStore = TestStarWalletSecureStore()
        let walletFileURL = directoryURL.appendingPathComponent("stars.enc")
        let quarantineURL = directoryURL.appendingPathComponent("quarantine", isDirectory: true)
        let store = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )

        _ = try await store.earnStar(source: "rewarded_ad")
        let expectedSnapshot = try await store.recordPurchase(
            StarPurchaseProduct(
                productID: "stars.10",
                starCount: 10,
                displayName: "10 Stars"
            )
        )

        let reloadedStore = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )
        let reloadedSnapshot = await reloadedStore.currentSnapshot()

        XCTAssertEqual(reloadedSnapshot.balance, expectedSnapshot.balance)
        XCTAssertEqual(reloadedSnapshot.sequence, expectedSnapshot.sequence)
        XCTAssertEqual(reloadedSnapshot.totalEarned, expectedSnapshot.totalEarned)
        XCTAssertEqual(reloadedSnapshot.totalSpent, expectedSnapshot.totalSpent)
        XCTAssertEqual(reloadedSnapshot.totalPurchased, expectedSnapshot.totalPurchased)
        XCTAssertEqual(reloadedSnapshot.events.map(\.kind), expectedSnapshot.events.map(\.kind))
        XCTAssertEqual(reloadedSnapshot.events.map(\.note), expectedSnapshot.events.map(\.note))
        XCTAssertEqual(reloadedSnapshot.totalPurchased, 10)
        XCTAssertFalse(try Data(contentsOf: walletFileURL).isEmpty)
    }

    func testStarWalletStoreResetsWhenCiphertextIsTampered() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let secureStore = TestStarWalletSecureStore()
        let walletFileURL = directoryURL.appendingPathComponent("stars.enc")
        let quarantineURL = directoryURL.appendingPathComponent("quarantine", isDirectory: true)
        let store = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )

        _ = try await store.earnStar(source: "rewarded_ad")

        var ciphertext = try Data(contentsOf: walletFileURL)
        XCTAssertFalse(ciphertext.isEmpty)
        ciphertext[0] ^= 0xFF
        try ciphertext.write(to: walletFileURL, options: [.atomic])

        let reloadedStore = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )
        let snapshot = await reloadedStore.currentSnapshot()

        XCTAssertEqual(snapshot, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: walletFileURL.path))
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: quarantineURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(quarantinedFiles.count, 1)
    }

    func testStarWalletStoreRejectsRollbackPayload() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let secureStore = TestStarWalletSecureStore()
        let walletFileURL = directoryURL.appendingPathComponent("stars.enc")
        let quarantineURL = directoryURL.appendingPathComponent("quarantine", isDirectory: true)
        let store = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )

        _ = try await store.earnStar(source: "first_reward")
        let rollbackCiphertext = try Data(contentsOf: walletFileURL)
        _ = try await store.earnStar(source: "second_reward")

        try rollbackCiphertext.write(to: walletFileURL, options: [.atomic])

        let reloadedStore = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )
        let snapshot = await reloadedStore.currentSnapshot()

        XCTAssertEqual(snapshot, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: walletFileURL.path))
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: quarantineURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(quarantinedFiles.count, 1)
    }

    func testDefaultStarEarningServiceCreditsOneStarOnlyWhenRewardIsEarned() async throws {
        let walletStore = FakeStarWalletStore()
        let rewardedAdProvider = RecordingRewardedAdProvider(showResult: .earnedReward)
        let service = DefaultStarEarningService(
            walletStore: walletStore,
            rewardedAdProvider: rewardedAdProvider
        )

        let result = try await service.watchAdAndEarnStar()
        let showCallCount = await rewardedAdProvider.recordedShowCallCount()

        XCTAssertEqual(result.adResult, .earnedReward)
        XCTAssertEqual(result.snapshot.balance, 1)
        XCTAssertEqual(result.snapshot.totalEarned, 1)
        XCTAssertEqual(showCallCount, 1)
    }

    func testDefaultStarEarningServiceLeavesBalanceUnchangedWithoutReward() async throws {
        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 2))
        let rewardedAdProvider = RecordingRewardedAdProvider(showResult: .closedWithoutReward)
        let service = DefaultStarEarningService(
            walletStore: walletStore,
            rewardedAdProvider: rewardedAdProvider
        )

        let result = try await service.watchAdAndEarnStar()
        let showCallCount = await rewardedAdProvider.recordedShowCallCount()

        XCTAssertEqual(result.adResult, .closedWithoutReward)
        XCTAssertEqual(result.snapshot.balance, 2)
        XCTAssertEqual(result.snapshot.totalEarned, 2)
        XCTAssertEqual(showCallCount, 1)
    }

    @MainActor
    func testWatchAdForStarReloadsRewardedAdAfterEachEarnedReward() async throws {
        let rewardedAdProvider = CyclingRewardedAdProvider(
            states: [.ready, .loading, .ready, .loading, .ready]
        )
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                rewardedAdProvider: rewardedAdProvider
            )
        )

        await viewModel.refreshStarsIfNeeded()

        XCTAssertTrue(viewModel.canWatchAdForStar)

        viewModel.watchAdForStar()
        try await waitForCondition(timeout: 2) {
            viewModel.starWalletSnapshot.balance == 1
                && viewModel.canWatchAdForStar
                && viewModel.rewardedAdState == .ready
        }

        viewModel.watchAdForStar()
        try await waitForCondition(timeout: 2) {
            viewModel.starWalletSnapshot.balance == 2
                && viewModel.canWatchAdForStar
                && viewModel.rewardedAdState == .ready
        }

        let showCallCount = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(showCallCount, 2)
    }

    @MainActor
    func testWatchAdButtonRemainsEnabledWhileRewardedAdKeepsLoading() async throws {
        let rewardedAdProvider = CyclingRewardedAdProvider(
            states: [.loading, .loading, .ready]
        )
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                rewardedAdProvider: rewardedAdProvider
            )
        )

        await viewModel.refreshStarsIfNeeded()

        XCTAssertEqual(viewModel.rewardedAdState, .loading)
        XCTAssertTrue(viewModel.canWatchAdForStar)
        XCTAssertEqual(viewModel.watchAdButtonTitle, "Ad Loading")

        viewModel.watchAdForStar()
        try await waitForCondition(timeout: 2) {
            viewModel.rewardedAdState == .ready && viewModel.canWatchAdForStar
        }

        let showCallCount = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(showCallCount, 0)
    }

    @MainActor
    func testStartPreparedEncodingWithoutStarsEncodesBeforeRewardedSaveAd() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: sourceURL)

        let rewardedAdProvider = RecordingRewardedAdProvider(showResult: .earnedReward)
        let sessionEndAdProvider = RecordingSessionEndAdProvider()
        let walletStore = FakeStarWalletStore()
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                rewardedAdProvider: rewardedAdProvider,
                sessionEndAdProvider: sessionEndAdProvider,
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertTrue(viewModel.canStartEncodingNow)
        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 0)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Ready")

        viewModel.startPreparedEncoding()
        try await waitForCondition(timeout: 2) {
            viewModel.state.pendingSaveJob?.state.requiresRewardedAd == true
                && viewModel.canWatchAdForStar
        }

        XCTAssertEqual(viewModel.state.title, "Ready to save")
        XCTAssertEqual(viewModel.watchAdButtonTitle, "Watch Ad to Save")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("source_taption.mp4").path
        ))
        let showCallCountBeforeSaveAd = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(showCallCountBeforeSaveAd, 0)

        viewModel.watchAdForStar()
        try await waitForCompletedSave(in: viewModel)
        let showCallCount = await rewardedAdProvider.recordedShowCallCount()
        let sessionReasons = await sessionEndAdProvider.recordedReasons()

        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 0)
        XCTAssertEqual(showCallCount, 1)
        XCTAssertTrue(sessionReasons.isEmpty)
        XCTAssertEqual(viewModel.state.title, "Save Complete")
    }

    @MainActor
    func testStartPreparedEncodingWithStarConsumesOneAndSavesWithoutRewardedAd() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: sourceURL)

        let rewardedAdProvider = RecordingRewardedAdProvider(showResult: .earnedReward)
        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                rewardedAdProvider: rewardedAdProvider,
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()
        try await waitForCompletedSave(in: viewModel)

        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 0)
        let showCallCount = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(showCallCount, 0)
        XCTAssertEqual(viewModel.state.title, "Save Complete")
    }

    @MainActor
    func testEncodingFailureRefundsConsumedStar() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: sourceURL)

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: FailingEncoderService(),
                starWalletStore: walletStore
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()

        try await waitForCondition(timeout: 2) {
            if case .failed = viewModel.state {
                return viewModel.starWalletSnapshot.balance == 1
            }
            return false
        }

        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 1)
        XCTAssertEqual(viewModel.state.title, "Encoding failed")
    }

    @MainActor
    func testCancelledEncodingDoesNotRefundConsumedStar() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: sourceURL)

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: CancellableEncoderService(),
                starWalletStore: walletStore
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()
        try await waitForCondition(timeout: 2) {
            viewModel.state.canCancel
        }

        viewModel.cancel()
        try await waitForCondition(timeout: 2) {
            if case .cancelled = viewModel.state {
                return true
            }
            return false
        }

        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 0)
    }

    @MainActor
    func testFolderBatchEncodesNextItemThenWaitsForRewardedSaveAdWhenBalanceRunsOut() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = [
            directoryURL.appendingPathComponent("a.mp4"),
            directoryURL.appendingPathComponent("b.mp4"),
            directoryURL.appendingPathComponent("c.mp4")
        ]
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 2))
        let rewardedAdProvider = RecordingRewardedAdProvider(showResult: .earnedReward)
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                rewardedAdProvider: rewardedAdProvider,
                starWalletStore: walletStore
            )
        )

        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()

        try await waitForCondition(timeout: 3) {
            viewModel.state.pendingSaveJob?.sourceName == "c.mp4"
                && viewModel.state.pendingSaveJob?.state.requiresRewardedAd == true
                && viewModel.fileCardSnapshots.last?.statusText == "Watch Ad to Save"
                && viewModel.starWalletSnapshot.balance == 0
        }

        let statuses = Dictionary(uniqueKeysWithValues: viewModel.fileCardSnapshots.map {
            ($0.id, $0.statusText)
        })
        XCTAssertEqual(statuses[fileURLs[0].absoluteString], "Save Complete")
        XCTAssertEqual(statuses[fileURLs[1].absoluteString], "Save Complete")
        XCTAssertEqual(statuses[fileURLs[2].absoluteString], "Watch Ad to Save")
        let showCallCountBeforeSaveAd = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(showCallCountBeforeSaveAd, 0)

        viewModel.watchAdForStar()
        try await waitForCompletedSave(in: viewModel)

        XCTAssertEqual(viewModel.state.title, "Save Complete")
        let showCallCountAfterSaveAd = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(showCallCountAfterSaveAd, 1)
    }

    private struct FakeFFmpegCommandRunner: SW_FFmpegCommandRunning {
        var runBlock: @Sendable (SW_FFmpegCommandPlan) async throws -> SW_FFmpegCommandRunResult

        func run(commandPlan: SW_FFmpegCommandPlan) async throws -> SW_FFmpegCommandRunResult {
            try await runBlock(commandPlan)
        }
    }

    private final class TestStarWalletSecureStore: @unchecked Sendable, StarWalletSecureStoring {
        private var encryptionKeyData = Data((0..<32).map(UInt8.init))
        private var integrityMetadata: StarWalletIntegrityMetadata?

        func loadOrCreateEncryptionKeyData() throws -> Data {
            encryptionKeyData
        }

        func loadIntegrityMetadata() throws -> StarWalletIntegrityMetadata? {
            integrityMetadata
        }

        func saveIntegrityMetadata(_ metadata: StarWalletIntegrityMetadata) throws {
            integrityMetadata = metadata
        }

        func clearIntegrityMetadata() throws {
            integrityMetadata = nil
        }
    }

    private actor RecordingRewardedAdProvider: RewardedAdProviding {
        private let currentStateValue: AdLoadState
        private let showResultValue: RewardedAdShowResult
        private var showCallCount = 0

        init(
            currentState: AdLoadState = .ready,
            showResult: RewardedAdShowResult = .earnedReward
        ) {
            self.currentStateValue = currentState
            self.showResultValue = showResult
        }

        func currentRewardedState() async -> AdLoadState {
            currentStateValue
        }

        func showRewardedAd() async -> RewardedAdShowResult {
            showCallCount += 1
            return showResultValue
        }

        func recordedShowCallCount() -> Int {
            showCallCount
        }
    }

    private actor CyclingRewardedAdProvider: RewardedAdProviding {
        private var states: [AdLoadState]
        private var showCallCount = 0

        init(states: [AdLoadState]) {
            self.states = states
        }

        func currentRewardedState() async -> AdLoadState {
            nextState()
        }

        func preloadRewardedAd() async -> AdLoadState {
            nextState()
        }

        func showRewardedAd() async -> RewardedAdShowResult {
            showCallCount += 1
            return .earnedReward
        }

        func recordedShowCallCount() -> Int {
            showCallCount
        }

        private func nextState() -> AdLoadState {
            guard !states.isEmpty else {
                return .ready
            }
            return states.removeFirst()
        }
    }

    private actor RecordingSessionEndAdProvider: SessionEndAdProviding {
        private var reasons: [SessionEndAdReason] = []
        private var preloadCount = 0

        func preloadSessionEndAd() async {
            preloadCount += 1
        }

        func showSessionEndAd(reason: SessionEndAdReason) async {
            reasons.append(reason)
        }

        func recordedReasons() -> [SessionEndAdReason] {
            reasons
        }

        func recordedPreloadCount() -> Int {
            preloadCount
        }
    }

    private struct ImmediateEncoderService: EncoderServicing {
        var outputData: Data

        func encode(
            plan: TaptionEncodingPlan,
            progress: @escaping (TaptionEncodingProgress) -> Void
        ) async throws -> TaptionEncodingResult {
            guard let temporaryOutputURL = plan.temporaryOutputURL else {
                throw TaptionVideoCoreError.missingTemporaryOutputURL
            }

            progress(TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0))
            progress(TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.5, elapsedTime: 0.1))
            try FileManager.default.createDirectory(
                at: temporaryOutputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try outputData.write(to: temporaryOutputURL)
            progress(TaptionEncodingProgress(stage: .waitingForSaveGate, fractionCompleted: 1, elapsedTime: 0.2))

            return TaptionEncodingResult(
                planID: plan.id,
                temporaryOutputURL: temporaryOutputURL,
                finalOutputURL: plan.finalOutputURL,
                usedBackend: .customSoftware,
                usedMode: .software
            )
        }

        func cancelEncoding(planID: UUID) async {}
    }

    private struct FailingEncoderService: EncoderServicing {
        func encode(
            plan: TaptionEncodingPlan,
            progress: @escaping (TaptionEncodingProgress) -> Void
        ) async throws -> TaptionEncodingResult {
            progress(TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0))
            throw TaptionVideoCoreError.exportFailed("Synthetic encoding failure.")
        }

        func cancelEncoding(planID: UUID) async {}
    }

    private struct CancellableEncoderService: EncoderServicing {
        func encode(
            plan: TaptionEncodingPlan,
            progress: @escaping (TaptionEncodingProgress) -> Void
        ) async throws -> TaptionEncodingResult {
            progress(TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.1))
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        func cancelEncoding(planID: UUID) async {}
    }

    private struct FixedStorageChecker: StorageChecking {
        var requirement: TaptionStorageRequirement

        func storageRequirement(for plan: TaptionEncodingPlan) async throws -> TaptionStorageRequirement {
            requirement
        }
    }

    private struct StubMediaInspector: MediaInspecting {
        var asset: TaptionVideoAsset

        func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
            var inspectedAsset = asset
            inspectedAsset.displayName = url.lastPathComponent
            inspectedAsset.location = TaptionVideoAssetLocation(kind: .file, url: url)
            return inspectedAsset
        }
    }

    private func readyBroadSoftwareBackendReport() -> TaptionSoftwareCodecBackendReadinessReport {
        SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(
            isBundledInCurrentBuild: true,
            satisfiedGates: Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
        )
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TaptionEncoderTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeStarWalletSnapshot(
        balance: Int,
        totalEarned: Int? = nil,
        totalSpent: Int = 0,
        totalPurchased: Int = 0,
        sequence: Int64 = 0
    ) -> StarWalletSnapshot {
        StarWalletSnapshot(
            balance: balance,
            totalEarned: totalEarned ?? balance,
            totalSpent: totalSpent,
            totalPurchased: totalPurchased,
            sequence: sequence,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            events: []
        )
    }

    private func expectedCompletedSaveDetail(
        url: URL,
        fileByteCount: Int,
        duration: String = "Unknown"
    ) -> String {
        let format = url.pathExtension.isEmpty ? "Unknown" : url.pathExtension.uppercased()
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(fileByteCount),
            countStyle: .file
        )
        return [
            "File: \(url.lastPathComponent)",
            "Format: \(format)",
            "Size: \(size)",
            "Time: \(duration)",
            "Path: \(url.path)"
        ].joined(separator: "\n")
    }

    private func makeHomeViewModelTestEnvironment(
        pendingSaveStore: PendingSaveStoring,
        mediaInspector: MediaInspecting = FakeMediaInspector(),
        encoderService: EncoderServicing = FakeEncoderService(),
        storageChecker: StorageChecking = FakeStorageChecker(),
        rewardedAdProvider: RewardedAdProviding = FakeRewardedAdProvider(),
        sessionEndAdProvider: SessionEndAdProviding = FakeSessionEndAdProvider(),
        starWalletStore: StarWalletManaging = FakeStarWalletStore()
    ) -> AppEnvironment {
        let configuration = AppConfiguration()
        let starEarningService = DefaultStarEarningService(
            walletStore: starWalletStore,
            rewardedAdProvider: rewardedAdProvider
        )
        return AppEnvironment(
            configuration: configuration,
            featureFlags: .phase0,
            mediaInspector: mediaInspector,
            encoderService: encoderService,
            storageChecker: storageChecker,
            sourceOpener: FakeSourceOpener(),
            outputResolver: DefaultOutputResolver(
                namingPolicy: TaptionOutputNamingPolicy(suffix: configuration.outputSuffix)
            ),
            pendingSaveStore: pendingSaveStore,
            adGate: FakeAdGate(),
            bannerAdProvider: FakeBannerAdProvider(),
            rewardedAdProvider: rewardedAdProvider,
            starWalletStore: starWalletStore,
            starEarningService: starEarningService,
            starPurchaseProvider: FakeStarPurchaseProvider(
                products: configuration.starPurchaseProducts
            ),
            sessionEndAdProvider: sessionEndAdProvider,
            backgroundCoordinator: FakeBackgroundEncodingCoordinator(),
            projectDocumentStore: FakeProjectFileStore()
        )
    }

    @MainActor
    private func waitForSaveConflictPrompt(
        in viewModel: HomeViewModel,
        timeout: TimeInterval = 2
    ) async throws {
        try await waitForCondition(timeout: timeout) {
            viewModel.saveConflictPrompt != nil
        }
    }

    @MainActor
    private func waitForPendingSaveExportPrompt(
        in viewModel: HomeViewModel,
        timeout: TimeInterval = 2
    ) async throws {
        try await waitForCondition(timeout: timeout) {
            viewModel.pendingSaveExportPrompt != nil
        }
    }

    @MainActor
    private func waitForCompletedSave(
        in viewModel: HomeViewModel,
        timeout: TimeInterval = 2
    ) async throws {
        try await waitForCondition(timeout: timeout) {
            if case .completed = viewModel.state {
                return true
            }
            return false
        }
    }

    @MainActor
    private func waitForStorageBlockedState(
        in viewModel: HomeViewModel,
        timeout: TimeInterval = 2
    ) async throws {
        try await waitForCondition(timeout: timeout) {
            if case .storageBlocked = viewModel.state {
                return true
            }
            return false
        }
    }

    @MainActor
    private func waitForReadyToStartState(
        in viewModel: HomeViewModel,
        timeout: TimeInterval = 2
    ) async throws {
        try await waitForCondition(timeout: timeout) {
            if case .readyToStart = viewModel.state {
                return true
            }
            return false
        }
    }

    @MainActor
    private func waitForCondition(
        timeout: TimeInterval,
        _ condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition())
    }

    private func makeH264ToAV1CommandPlan(
        outputURL: URL = URL(fileURLWithPath: "/tmp/output.mkv")
    ) throws -> SW_FFmpegCommandPlan {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)
        return try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
                outputURL: outputURL,
                route: route,
                options: .preservingSource(outputCodec: .av1, container: .mkv)
            )
        )
    }

    private func temporaryTestURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    }

    private func selectAV1ToHEVC(
        profile: TaptionCodecHardwareSupportProfile
    ) -> TaptionCodecRouteSelection {
        selectRoute(
            sourceCodec: .av1,
            outputCodec: .hevc,
            profile: profile
        )
    }

    private func selectRoute(
        sourceCodec: TaptionVideoCodec,
        outputCodec: TaptionVideoCodec,
        profile: TaptionCodecHardwareSupportProfile
    ) -> TaptionCodecRouteSelection {
        TaptionCodecRoutePlanner.selectRoute(
            for: makeAsset(sourceCodec: sourceCodec),
            outputCodec: outputCodec,
            requestedMode: .automatic,
            hardwareSupport: profile
        )
    }

    private func makeAsset(
        sourceCodec: TaptionVideoCodec,
        displaySize: TaptionPixelSize = TaptionPixelSize(width: 1920, height: 1080),
        fileSize: Int64 = 1_000_000
    ) -> TaptionVideoAsset {
        TaptionVideoAsset(
            displayName: "\(sourceCodec.rawValue).mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: sourceCodec,
                naturalSize: displaySize,
                displaySize: displaySize,
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: [
                TaptionAudioTrackInfo(
                    codec: .aac,
                    channelCount: 2,
                    sampleRate: 48_000
                )
            ],
            fingerprint: TaptionMediaFingerprint(fileSize: fileSize)
        )
    }

    private func makeAudioDescription(
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

    private func syntheticDeviceCodecReport(
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

    private func appleProfile(_ id: String) -> TaptionCodecHardwareSupportProfile {
        guard let profile = HW_AppleDeviceCodecProfiles.profile(id: id) else {
            XCTFail("Missing Apple device codec profile: \(id)")
            return .softwareOnly
        }
        return profile.hardwareSupportProfile
    }

    private func appleModelProfile(_ identifier: String) -> TaptionCodecHardwareSupportProfile {
        guard let profile = HW_AppleDeviceCodecModelMatrix.hardwareSupportProfile(identifier: identifier) else {
            XCTFail("Missing Apple device model codec profile: \(identifier)")
            return .softwareOnly
        }
        return profile
    }

    private func containerSort(
        _ lhs: TaptionVideoContainer,
        _ rhs: TaptionVideoContainer
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
