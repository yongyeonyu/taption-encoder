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

// Opt-in switches for the proof suites that need material a checkout does not have.
//
// `xcodebuild test` does not reliably forward the shell environment to the test
// host, so an environment variable alone is not something a script can turn on.
// A flag file is, which is why the local real-sample proofs already accept one.
// Both switches now work the same way: env var first, flag file second.
enum TaptionOptInProofs {
    static let retiredProofsFlagPath = "/tmp/taption_run_retired_proof_tests"
    static let localRealSamplesFlagPath = "/tmp/taption_run_local_real_sample_tests"

    static func isEnabled(
        environmentVariable: String,
        flagPath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if environment[environmentVariable] == "1" {
            return true
        }
        return FileManager.default.fileExists(atPath: flagPath)
    }
}

//  The test methods themselves live in the CodecRoutePlannerTests+*.swift
//  files, split out of this file for size only. This part keeps the class
//  declaration, the shared helpers and the defaultTestSuite exclusion lists.
final class CodecRoutePlannerTests: XCTestCase {
    override class var defaultTestSuite: XCTestSuite {
        var excludedMethodNames: Set<String> = []
        let environment = ProcessInfo.processInfo.environment

        if !TaptionOptInProofs.isEnabled(
            environmentVariable: "TAPTION_RUN_RETIRED_PROOF_TESTS",
            flagPath: TaptionOptInProofs.retiredProofsFlagPath,
            environment: environment
        ) {
            excludedMethodNames.formUnion(retiredSourceOnlyProofTestNames)
        }
        if !TaptionOptInProofs.isEnabled(
            environmentVariable: "TAPTION_RUN_LOCAL_REAL_SAMPLE_TESTS",
            flagPath: TaptionOptInProofs.localRealSamplesFlagPath,
            environment: environment
        ) {
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

/// Renders the surfaces a colour change actually reaches, at iPhone 11 size (414 × 896 pt).
///
/// Why it exists: the Duo render above covers `HomeView` only, so the file rows, folder tiles and
/// the import browser had no visual evidence for a design-token change. This hosts the real views
/// with fixtures — no device capture, no ad, no folder-access sheet — and writes PNGs into the app
/// container, which `devicectl device copy from` can pull off a phone.
///
/// Marker-gated like the Duo render, so ordinary runs and CI skip it. On a simulator create
/// `/tmp/taption-render-phone`; on a device copy a file to `tmp/taption-render-phone` inside the
/// app data container, because `/tmp` there is the sandbox's own tmp.
@MainActor
final class PhoneUIRenderTests: XCTestCase {
    /// iPhone 11: 414 × 896 pt. Rendered at 3× so text stays legible when inspected.
    private let points = CGSize(width: 414, height: 896)

    func testRenderPhoneSurfacesWhenRequested() throws {
        // On a device the app's tmp is `<container>/tmp`, and a literal `/tmp` is not redirected
        // there — so the marker has to be looked up through NSTemporaryDirectory() as well.
        // On a simulator both resolve to paths the host can see.
        let sandboxTmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let markerCandidates = [
            sandboxTmp.appendingPathComponent("taption-render-phone"),
            URL(fileURLWithPath: "/tmp/taption-render-phone"),
        ]
        guard markerCandidates.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Create taption-render-phone in tmp to render the phone surfaces.")
        }

        let output = sandboxTmp.appendingPathComponent("taption-phone-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        try render(
            named: "home",
            view: AnyView(HomeView().background(TaptionTheme.appBackground)),
            into: output
        )
        try render(
            named: "queue",
            view: AnyView(
                LoadedFilesPanelView(
                    files: Self.queueFixtures,
                    contentScale: 1,
                    panelHeight: 86 * CGFloat(Self.queueFixtures.count),
                    onSelect: { _ in },
                    onPlay: { _ in },
                    onToggleSelection: { _ in },
                    onDelete: { _ in },
                    onMove: { _, _ in },
                    onMoveEnded: {}
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(TaptionTheme.appBackground)
            ),
            into: output
        )
    }

    private func render(named name: String, view: AnyView, into output: URL) throws {
        let frame = CGRect(origin: .zero, size: points)
        let window = UIWindow(frame: frame)
        let host = UIHostingController(rootView: view)
        host.view.frame = frame
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        // SwiftUI lays out on the next run-loop turn; the panel settles after that.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        // A first launch raises the folder-access alert in its own window, which would composite
        // into the render as a stray overlay.
        for _ in 0..<3 where host.presentedViewController != nil {
            host.dismiss(animated: false)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
        window.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: points, format: format)
        let image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }

        let data = try XCTUnwrap(image.pngData(), "PNG encoding failed for \(name)")
        try data.write(to: output.appendingPathComponent("phone-\(name).png"))
    }

    /// One row per state the panel draws: active and selected, idle, star-limited, disabled.
    private static var queueFixtures: [EncodingFileCardSnapshot] {
        [
            EncodingFileCardSnapshot(
                id: "active",
                fileName: "beach-4k.mp4",
                sourceKind: .files,
                videoInfo: nil,
                statusText: "Ready",
                detailText: "3840×2160 · 60 fps · 12.4 s",
                progress: nil,
                isActive: true,
                isSelected: true,
                isEnabled: true,
                isPreviewable: true
            ),
            EncodingFileCardSnapshot(
                id: "idle",
                fileName: "interview-hevc.mov",
                sourceKind: .photos,
                videoInfo: nil,
                statusText: "Ready",
                detailText: nil,
                progress: nil,
                isActive: false,
                isSelected: false,
                isEnabled: true,
                isPreviewable: true
            ),
            EncodingFileCardSnapshot(
                id: "limited",
                fileName: "timelapse.mov",
                sourceKind: .folder,
                videoInfo: nil,
                statusText: "Star limited",
                detailText: nil,
                progress: nil,
                isActive: false,
                isSelected: false,
                isEnabled: false,
                isStarLimited: true,
                isPreviewable: true
            ),
        ]
    }
}
