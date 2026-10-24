import AVFoundation
import AudioToolbox
import CoreImage
import CoreMedia
import SwiftUI
import SwiftVLC
import UIKit
import XCTest
@testable import Taption_Encoder

internal final class RecordingSourcePreservingOutputVerifier: SourcePreservingOutputVerifying {
    struct Call: Equatable {
        var planID: UUID
        var outputURL: URL
    }

    private(set) var calls: [Call] = []
    var result: Result<TaptionSourcePreservingOutputVerificationReport, Error>

    init(result: Result<TaptionSourcePreservingOutputVerificationReport, Error> = .success(
        TaptionSourcePreservingOutputVerificationReport(
            failures: [],
            warnings: [],
            metadata: ["sourcePreservingOutput": "test-verified"]
        )
    )) {
        self.result = result
    }

    func verify(
        plan: TaptionEncodingPlan,
        outputURL: URL
    ) async throws -> TaptionSourcePreservingOutputVerificationReport {
        calls.append(Call(planID: plan.id, outputURL: outputURL))
        return try result.get()
    }
}

enum TaptionEncoderTestSuiteFilter {
    static func filtering(
        _ suite: XCTestSuite,
        excluding methodNames: Set<String>
    ) -> XCTestSuite {
        guard !methodNames.isEmpty else {
            return suite
        }

        let filteredSuite = XCTestSuite(name: suite.name)
        for test in suite.tests where !methodNames.contains(where: test.name.contains) {
            filteredSuite.addTest(test)
        }
        return filteredSuite
    }
}

//  The test methods themselves live in the CodecRoutePlannerTests+*.swift
//  files, split out of this file for size only. This part keeps the class
//  declaration, the shared helpers and the defaultTestSuite exclusion lists.
final class CodecRoutePlannerTests: XCTestCase {
    override class var defaultTestSuite: XCTestSuite {
        var excludedMethodNames: Set<String> = []
        let environment = ProcessInfo.processInfo.environment

        if environment["TAPTION_RUN_RETIRED_PROOF_TESTS"] != "1" {
            excludedMethodNames.formUnion(retiredSourceOnlyProofTestNames)
        }
        if environment["TAPTION_RUN_LOCAL_REAL_SAMPLE_TESTS"] != "1" {
            excludedMethodNames.formUnion(localRealSampleProofTestNames)
        }
#if !targetEnvironment(simulator)
        excludedMethodNames.formUnion(hostCheckoutContractTestNames)
#endif

        return TaptionEncoderTestSuiteFilter.filtering(
            super.defaultTestSuite,
            excluding: excludedMethodNames
        )
    }

    internal static let retiredSourceOnlyProofTestNames: Set<String> = [
        "testBundledAMRWBH263SampleEncodesHEVCMOVWithALACAudio",
        "testBundledAMRWBH263SampleEncodesHEVCMOVWithPCMAudio",
        "testBundledAvailableNowSamplesAreReadyOnSoftwareOnlyProfile",
        "testBundledAvailableNowSamplesGenerateQueueThumbnails",
        "testBundledAvailableNowSamplesInspectToExpectedLaunchCodecs",
        "testBundledCodecBenchmarkScriptCoversPlaybackEncodingAndProfiles",
        "testBundledFlashVideoMP3SampleEncodesHEVCMOVWithALACAudio",
        "testBundledFlashVideoMP3SampleEncodesHEVCMOVWithPCMAudio",
        "testBundledH264AC3SampleEncodesHEVCMOVWithALACAudioOnSoftwarePath",
        "testBundledH264AC3SampleEncodesHEVCMOVWithPCMAudioOnSoftwarePath",
        "testBundledH264EAC3SampleEncodesHEVCMOVWithALACAudioOnSoftwarePath",
        "testBundledH264EAC3SampleEncodesHEVCMOVWithPCMAudioOnSoftwarePath",
        "testBundledProResSampleKeepsHardwareGate",
        "testBundledQuickTimeVideoAACSampleEncodesHEVCMOVWithALACAudio",
        "testBundledQuickTimeVideoAACSampleEncodesHEVCMOVWithPCMAudio",
        "testBundledSampleSourceNoticeRejectsGeneratedOnlyFixtures",
        "testBundledSampleThumbnailResourcesCoverSeededVideos",
        "testBundledTestVideosMatchCurrentLaunchVideoSupport",
        "testBundledTheoraOpusSampleEncodesHEVCMOVWithALACAudio",
        "testBundledTheoraOpusSampleEncodesHEVCMOVWithPCMAudio",
        "testBundledTheoraVorbisSampleEncodesHEVCMOVWithALACAudio",
        "testBundledTheoraVorbisSampleEncodesHEVCMOVWithPCMAudio",
        "testExternalPlayerRegistrationVerifierCoversInstalledDocumentOwnership",
        "testExternalVideoPlayerFlowVerifierCoversRealOpenURLPath",
        "testNextIntermediateBundledSamplesEncodeToHEVCMP4",
        "testNextLegacyBundledSamplesEncodeToHEVCMP4",
        "testPictureInPictureProbeVerifierCoversSimulatorAndDeviceLaunches",
        "testPreviewRegressionSamplesProduceVisibleVideoSnapshots",
        "testQueuePreviewVideoViewProducesVideoOutputForFirstBundledSample",
        "testRealDeviceBundledAMRWBH263SampleEncodesHEVCWithAACAudio",
        "testRealDeviceBundledTheoraOpusSampleEncodesHEVCWithAACAudio",
        "testRealVideoAndRoQBundledSamplesEncodeToHEVCMP4",
        "testRepresentativeBundledAvailableNowSamplesEncodeToHEVCMP4",
        "testScreenAndArchiveBundledSamplesEncodeToHEVCMP4"
    ]

    internal static let localRealSampleProofTestNames: Set<String> = [
        "testLocalJPEGAndJPEGXLVideosEncodeToHEVCMP4AndMOV",
        "testLocalProResPerformanceSampleMeasuresBalancedAndMaxPerformance",
        "testLocalRealAMRNBH263SampleEncodesHEVCWithAACAudio",
        "testLocalRealAMRWBH263SampleEncodesHEVCWithAACAudio",
        "testLocalRealQuickTimeRPZASampleEncodesWithLegacyFrameHoldDuration",
        "testLocalRealVC1RawSampleUsesBundledFFmpegDecodeBridgeRoute",
        "testLocalRealVC1WrappedPCMSamplePreservesAudioInMP4AndMOV",
        "testLocalRealVP8WebMSampleCanEncodeHEVCWithAACAudio",
        "testLocalRealVP8WebMSampleCanPrepareHEVCJob",
        "testLocalRealXHEAACSampleEncodesHEVCWithNativeAACAudio",
        "testLocalRealY41PSampleUsesBundledFFmpegDecodeBridgeRoute",
        "testLocalRemainingCodecSamplesEncodeToHEVCMP4AndMOV"
    ]

    internal static let hostCheckoutContractTestNames: Set<String> = [
        "testAdMobNativeAndPlacementSurfacesAreWiredWithoutPrivacyMenu",
        "testBatterySettingsSheetContainsEncodingOptimizationSlider",
        "testDebugLiveActivityProbeCanStartForLockScreenVerification",
        "testEncodingLiveActivityLockScreenSmallFamilyUsesCondensedLayout",
        "testEncodingProgressViewDisplaysResourceUsageWidgetDuringEncodingOnly",
        "testExternalVideoOpenSuppressesAppOpenAdsBeforePreviewRouting",
        "testFFmpegBridgeRebuildRecipeKeepsNarrowDecodeAndHEVCOutputPolicy",
        "testFileAndFolderButtonsUseSystemPickersWithFolderSelection",
        "testHelpOpenSourceSectionShowsShippedComponentsWithoutInternalPlanning",
        "testHelpSheetIntegratesVersionDeviceInfoAndOpenSourceNotices",
        "testHomeHeaderDoesNotDisplayAppName",
        "testHomeLayoutMetricsDoesNotReserveMiddleNativeAdSlot",
        "testHomeViewModelStartsAndStopsResourceMonitoringAroundEncoding",
        "testImportableVideoTypesMatchCurrentLaunchInputContainers",
        "testLibVLCComplianceInventoryPinsExactSourceInputsAndBlocksPublicRelease",
        "testOpenSourceNoticesMatchResolvedThirdPartyPackagePins",
        "testOutputSummaryKeepsCodecLabelsSmall",
        "testProtectedAppFlowsSuppressFullScreenAdsUntilTheyClose",
        "testQueueCardGestureControlsAreWiredForSelectionDeleteAndDrag",
        "testQueuePreviewCanMinimizeIntoBannerOnlyFloatingPlayer",
        "testQueuePreviewPlayerUsesPictureInPictureSurfaceAndBannerOnlyAds",
        "testQuickLookThumbnailExtensionCoversDocumentBrowserVideoTypes",
        "testReleaseConfigurationAndDistributionGateKeepBinaryHardening",
        "testStarBadgeRunsRewardedAdFlowWithoutPurchaseSheet",
        "testTaptionThemeUsesBlueGreenSlateAndIcePalette"
    ]
}

internal actor RecordingPhotoVideoLoader: PhotoVideoLoading {
    internal var loaded: [String] = []
    internal let unavailable: Set<String>
    internal let delayed: Set<String>
    init(unavailable: Set<String> = [], delayed: Set<String> = []) { self.unavailable = unavailable; self.delayed = delayed }
    func loadedIDs() -> [String] { loaded }
    func loadVideo(_ video: PhotoLibraryVideo, to destination: URL) async throws {
        if FileManager.default.fileExists(atPath: destination.path) { return }
        loaded.append(video.id)
        if delayed.contains(video.id) { try await Task.sleep(for: .milliseconds(100)) }
        if unavailable.contains(video.id) { throw PhotoLibraryVideoError.unavailable }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("source".utf8).write(to: destination)
    }
}

/// Renders the home screen at the exact App Store screenshot sizes for iPhone Duo.
///
/// Xcode 27.0 ships no Duo device type, so `simctl io screenshot` cannot produce these images on
/// this machine. This renders the same views at the same point sizes instead, which is the closest
/// honest substitute: the pixels come from the real `HomeView`, not from a mock.
///
/// It stays inert unless a marker file exists, so ordinary runs and CI skip it.
@MainActor
final class DuoAppStoreScreenshotTests: XCTestCase {
    /// Point sizes are the required pixel sizes divided by 3.
    /// Outer 1398 x 2034, inner 2007 x 2853 — both from Apple's screenshot specification table.
    internal let cases: [(name: String, points: CGSize, pixels: CGSize)] = [
        ("outer", CGSize(width: 466, height: 678), CGSize(width: 1398, height: 2034)),
        ("inner", CGSize(width: 669, height: 951), CGSize(width: 2007, height: 2853)),
    ]

    func testRenderDuoScreenshotsWhenRequested() throws {
        let marker = URL(fileURLWithPath: "/tmp/taption-render-duo")
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("Create /tmp/taption-render-duo to render the Duo screenshots.")
        }

        let output = URL(fileURLWithPath: "/tmp/taption-duo-shots")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for item in cases {
            let frame = CGRect(origin: .zero, size: item.points)
            let window = UIWindow(frame: frame)
            let host = UIHostingController(rootView: HomeView())
            host.view.frame = frame
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.layoutIfNeeded()

            // SwiftUI lays out on the next run-loop turn, and the banner/queue settle after that.
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))

            // A first launch raises the folder-access alert, which composites as a stray overlay in
            // an offscreen render (UIKit presents it in its own window). Screenshots must show the
            // screen, not a prompt about a folder that only exists on a real device.
            for _ in 0..<3 where host.presentedViewController != nil {
                host.dismiss(animated: false)
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            }

            window.layoutIfNeeded()

            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: item.points, format: format)
            let image = renderer.image { context in
                window.layer.render(in: context.cgContext)
            }

            let data = try XCTUnwrap(image.pngData(), "PNG encoding failed for \(item.name)")
            XCTAssertEqual(image.size.width * image.scale, item.pixels.width)
            XCTAssertEqual(image.size.height * image.scale, item.pixels.height)

            let file = output.appendingPathComponent("duo-\(item.name)-\(Int(item.pixels.width))x\(Int(item.pixels.height)).png")
            try data.write(to: file)
            print("rendered \(file.path) \(Int(item.pixels.width))x\(Int(item.pixels.height))")
        }
    }
}
