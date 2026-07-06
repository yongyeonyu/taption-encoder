import AVFoundation
import AudioToolbox
import CoreMedia
import SwiftUI
import SwiftVLC
import UIKit
import XCTest
@testable import Taption_Encoder

private final class RecordingSourcePreservingOutputVerifier: SourcePreservingOutputVerifying {
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

final class CodecRoutePlannerTests: XCTestCase {
    func testBackgroundReliabilityPresenterWarnsToKeepAppOpenBeforeContinuedProcessingOS() {
        let message = HomeBackgroundReliabilityPresenter.message(
            currentOSMajorVersion: 25,
            backgroundEncodingMinimumMajorVersion: 26,
            liveActivitiesEnabled: false
        )

        XCTAssertTrue(message.contains("Keep Taption Encoder open"))
        XCTAssertTrue(message.contains("iOS/iPadOS 18-25"))
        XCTAssertTrue(message.contains("pause the job"))
    }

    func testBackgroundReliabilityPresenterUsesLockScreenCopyOnContinuedProcessingOS() {
        let enabledMessage = HomeBackgroundReliabilityPresenter.message(
            currentOSMajorVersion: 26,
            backgroundEncodingMinimumMajorVersion: 26,
            liveActivitiesEnabled: true
        )
        let disabledMessage = HomeBackgroundReliabilityPresenter.message(
            currentOSMajorVersion: 26,
            backgroundEncodingMinimumMajorVersion: 26,
            liveActivitiesEnabled: false
        )

        XCTAssertTrue(enabledMessage.contains("Lock Screen and Dynamic Island"))
        XCTAssertTrue(disabledMessage.contains("Turn on Live Activities"))
    }

    func testHomeErrorPresenterFormatsEnglishRecoveryBeforeDiagnostics() {
        let providerError = NSError(
            domain: "TaptionEncoderTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Provider rejected the source"]
        )

        let error = HomeErrorPresenter.error(
            title: "Import failed",
            summary: "The app could not import the selected video.",
            recovery: "Open the source again from Files or Photos.",
            error: providerError
        )

        XCTAssertEqual(error.title, "Import failed")
        XCTAssertTrue(error.message.hasPrefix("The app could not import the selected video."))
        XCTAssertTrue(error.message.contains("Cause: iOS or the selected provider returned an error."))
        XCTAssertTrue(error.message.contains("Fix: Open the source again from Files or Photos."))
        XCTAssertTrue(error.message.contains("Log:"))
        XCTAssertTrue(error.message.contains("TaptionEncoderTests"))
        XCTAssertNotEqual(error.message, providerError.localizedDescription)
    }

    func testHomeErrorPresenterCardDetailKeepsActionableTextBeforeRawDiagnostic() {
        let routeError = TaptionVideoCoreError.unsupportedSourceCodec(.vp9)

        let detail = HomeErrorPresenter.cardDetail(
            summary: "The app could not prepare this video for encoding.",
            recovery: "Choose another source or output setting, then try again.",
            error: routeError
        )

        XCTAssertTrue(detail.hasPrefix("The app could not prepare this video for encoding."))
        XCTAssertTrue(detail.contains("Choose another source or output setting"))
        XCTAssertTrue(detail.contains("Log:"))
    }

    func testProductionAdMobConfigurationRejectsGoogleDemoAdUnitIDs() {
        let configuration = AdMobRuntimeConfiguration.productionConfiguration(
            appOpenAdUnitID: "ca-app-pub-3940256099942544/5575463023",
            homeBannerAdUnitID: " ca-app-pub-3940256099942544/2934735716 ",
            nativeAdUnitID: "ca-app-pub-3940256099942544/3986624511",
            rewardedSaveAdUnitID: nil,
            sessionEndInterstitialAdUnitID: "ca-app-pub-3940256099942544/4411468910"
        )
        let adUnitIDs = [
            configuration.appOpenAdUnitID,
            configuration.homeBannerAdUnitID,
            configuration.nativeAdUnitID,
            configuration.rewardedSaveAdUnitID,
            configuration.sessionEndInterstitialAdUnitID
        ]

        XCTAssertEqual(configuration.appOpenAdUnitID, "ca-app-pub-9754025737691277/9568683076")
        XCTAssertEqual(configuration.homeBannerAdUnitID, "ca-app-pub-9754025737691277/6794641076")
        XCTAssertEqual(configuration.nativeAdUnitID, "")
        XCTAssertEqual(configuration.rewardedSaveAdUnitID, "ca-app-pub-9754025737691277/2855396062")
        XCTAssertEqual(configuration.sessionEndInterstitialAdUnitID, "ca-app-pub-9754025737691277/6942519738")
        XCTAssertFalse(adUnitIDs.contains { $0.hasPrefix(AdMobRuntimeConfiguration.googleDemoAdUnitPrefix) })
    }

    func testAdPlacementPolicyDecodesRuntimeSwitchesAndFrequencyCaps() throws {
        let json = """
        {
          "disabledPlacements": ["homeBanner", "nativeCompleted"],
          "minimumIntervals": {
            "appOpen": 120,
            "startInterstitial": 600
          }
        }
        """

        let policy = try XCTUnwrap(AdPlacementPolicy.decode(jsonString: json))

        XCTAssertFalse(policy.isEnabled(.homeBanner))
        XCTAssertTrue(policy.isEnabled(.nativeIdle))
        XCTAssertFalse(policy.isEnabled(.nativeCompleted))
        XCTAssertEqual(policy.minimumInterval(for: .appOpen), 120)
        XCTAssertEqual(policy.minimumInterval(for: .startInterstitial), 600)
        XCTAssertEqual(policy.minimumInterval(for: .sessionEndInterstitial), 8 * 60)
    }

    @MainActor
    func testAdPlacementFrequencyLimiterBlocksUntilMinimumIntervalPasses() {
        let limiter = AdPlacementFrequencyLimiter.shared
        let now = Date()
        let policy = AdPlacementPolicy(
            minimumIntervals: [.appOpen: 60]
        )
        limiter.reset()

        XCTAssertTrue(limiter.canPresent(.appOpen, now: now, policy: policy))
        limiter.recordPresentation(.appOpen, now: now)
        XCTAssertFalse(limiter.canPresent(.appOpen, now: now.addingTimeInterval(20), policy: policy))
        XCTAssertTrue(limiter.canPresent(.appOpen, now: now.addingTimeInterval(61), policy: policy))

        limiter.reset()
    }

    func testAdMobPrivacyNativeAndPlacementSurfacesAreWired() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let adProvidersURL = rootURL.appendingPathComponent("TaptionEncoder/Core/Ads/AdProviders.swift")
        let appEnvironmentURL = rootURL.appendingPathComponent("TaptionEncoder/App/AppEnvironment.swift")
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let menuURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeMenuSheetView.swift")
        let adProvidersText = try String(contentsOf: adProvidersURL, encoding: .utf8)
        let appEnvironmentText = try String(contentsOf: appEnvironmentURL, encoding: .utf8)
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
        let menuText = try String(contentsOf: menuURL, encoding: .utf8)

        XCTAssertTrue(adProvidersText.contains("protocol NativeAdProviding"))
        XCTAssertTrue(adProvidersText.contains("struct AdMobNativeAdProvider"))
        XCTAssertTrue(adProvidersText.contains("AdMobNativeAdSlotView"))
        XCTAssertTrue(adProvidersText.contains("AdLoader("))
        XCTAssertTrue(adProvidersText.contains("adTypes: [.native]"))
        XCTAssertTrue(adProvidersText.contains("ConsentForm.presentPrivacyOptionsForm"))
        XCTAssertTrue(adProvidersText.contains("Extras()"))
        XCTAssertTrue(adProvidersText.contains("[\"npa\": \"1\"]"))
        XCTAssertTrue(adProvidersText.contains("TaptionAdPlacementPolicyJSON"))
        XCTAssertTrue(adProvidersText.contains("AdPlacementFrequencyLimiter"))
        XCTAssertTrue(appEnvironmentText.contains("nativeAdProvider: AdMobNativeAdProvider"))
        XCTAssertFalse(homeViewText.contains("AdMobNativeAdSlotView("))
        XCTAssertFalse(homeViewText.contains("showsNativeAdSlot"))
        XCTAssertTrue(homeViewText.contains(".padding(.top, metrics.footerAdSeparationHeight)"))
        XCTAssertTrue(menuText.contains("Privacy & Ads"))
        XCTAssertTrue(menuText.contains("Report Ad Issue"))
        XCTAssertTrue(menuText.contains("help@taption.com"))
    }

    func testEncodingActivitySnapshotFormatsLiveActivityContent() {
        let snapshot = TaptionEncodingActivitySnapshot(
            sessionID: UUID().uuidString,
            statusText: "Encoding",
            sourceName: "Camera Imports",
            mode: .folder,
            currentIndex: 2,
            totalCount: 5,
            fractionCompleted: 0.424,
            elapsedSeconds: 65,
            remainingSeconds: 125,
            codecPathText: "Hardware Decode + Software Encode",
            outputText: "H.265 / HEVC MP4"
        )

        let state = snapshot.contentState

        XCTAssertEqual(state.statusText, "Encoding")
        XCTAssertEqual(state.sourceName, "Camera Imports")
        XCTAssertEqual(state.modeText, "Folder")
        XCTAssertEqual(state.countText, "2 of 5")
        XCTAssertEqual(state.percentText, "42%")
        XCTAssertEqual(state.elapsedText, "01:05")
        XCTAssertEqual(state.remainingText, "02:05")
        XCTAssertEqual(state.codecPathText, "Hardware Decode + Software Encode")
        XCTAssertEqual(state.outputText, "H.265 / HEVC MP4")
    }

    func testEncodingActivitySnapshotClampsInvalidProgressInputs() {
        let snapshot = TaptionEncodingActivitySnapshot(
            sessionID: UUID().uuidString,
            statusText: "Encoding",
            sourceName: "Clip.mov",
            mode: .single,
            currentIndex: 0,
            totalCount: 0,
            fractionCompleted: 1.7,
            elapsedSeconds: -8,
            remainingSeconds: nil,
            codecPathText: "Automatic Codec Path",
            outputText: "H.265 / HEVC MOV"
        )

        let state = snapshot.contentState

        XCTAssertEqual(snapshot.currentIndex, 1)
        XCTAssertEqual(snapshot.totalCount, 1)
        XCTAssertEqual(snapshot.fractionCompleted, 1)
        XCTAssertEqual(snapshot.elapsedSeconds, 0)
        XCTAssertEqual(state.countText, "Single video")
        XCTAssertEqual(state.percentText, "100%")
        XCTAssertEqual(state.elapsedText, "00:00")
        XCTAssertEqual(state.remainingText, "--:--")
    }

    func testEncodingLiveActivityLockScreenMetricsLeaveTopBreathingRoom() {
        let compact = TaptionEncodingLiveActivityLayoutMetrics.lockScreen(isRegularWidth: false)
        let regular = TaptionEncodingLiveActivityLayoutMetrics.lockScreen(isRegularWidth: true)
        let supplementalSmall = TaptionEncodingLiveActivityLayoutMetrics.lockScreen(
            isRegularWidth: false,
            isSupplementalSmallFamily: true
        )

        XCTAssertEqual(compact.horizontalPadding, 16)
        XCTAssertEqual(compact.topPadding, 92)
        XCTAssertEqual(compact.bottomPadding, 14)
        XCTAssertEqual(regular.horizontalPadding, 20)
        XCTAssertEqual(regular.topPadding, 124)
        XCTAssertEqual(regular.bottomPadding, 16)
        XCTAssertEqual(supplementalSmall.topPadding, 72)
        XCTAssertEqual(supplementalSmall.bottomPadding, 12)
        XCTAssertGreaterThan(regular.topPadding, compact.topPadding)
        XCTAssertGreaterThanOrEqual(regular.topPadding - compact.topPadding, 28)
        XCTAssertGreaterThan(compact.topPadding, compact.bottomPadding)
        XCTAssertGreaterThan(supplementalSmall.topPadding, supplementalSmall.bottomPadding)
    }

    func testEncodingLiveActivityDynamicIslandMetricsStayCompact() {
        XCTAssertEqual(TaptionEncodingLiveActivityLayoutMetrics.dynamicIslandExpandedTopPadding, 10)
        XCTAssertEqual(TaptionEncodingLiveActivityLayoutMetrics.dynamicIslandBottomTopPadding, 7)
    }

    func testEncodingLiveActivityLockScreenSmallFamilyUsesCondensedLayout() throws {
        let widgetURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TaptionEncoderLiveActivityExtension/EncodingLiveActivityWidget.swift")
        let widgetSource = try String(contentsOf: widgetURL, encoding: .utf8)
        XCTAssertTrue(widgetSource.contains("activityFamily == .small"))
        XCTAssertTrue(widgetSource.contains("condensedHeader"))
        XCTAssertTrue(widgetSource.contains("condensedDetails"))
        XCTAssertTrue(widgetSource.contains(".supplementalActivityFamilies([.small, .medium])"))
    }

    func testDebugLiveActivityProbeCanStartForLockScreenVerification() throws {
        let appURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TaptionEncoder/TaptionEncoderApp.swift")
        let appSource = try String(contentsOf: appURL, encoding: .utf8)

        XCTAssertTrue(appSource.contains("#if DEBUG"))
        XCTAssertTrue(appSource.contains("TAPTION_DEBUG_LIVE_ACTIVITY"))
        XCTAssertTrue(appSource.contains("--taption-debug-live-activity"))
        XCTAssertTrue(appSource.contains("ActivityKitEncodingLiveActivityCoordinator"))
        XCTAssertTrue(appSource.contains("Debug Live Activity probe requested"))
    }

    func testBatteryEncodingGateBlocksAtOrBelowLimit() {
        let settings = BatteryEncodingSettings(
            batteryLimitPercent: 30,
            powerConnectedOnly: false
        )

        XCTAssertNil(BatteryEncodingGate.blockReason(
            settings: settings,
            snapshot: BatteryEncodingPowerSnapshot(
                batteryPercent: 31,
                isPowerConnected: false,
                isPowerStateKnown: true
            )
        ))

        XCTAssertEqual(BatteryEncodingGate.blockReason(
            settings: settings,
            snapshot: BatteryEncodingPowerSnapshot(
                batteryPercent: 30,
                isPowerConnected: false,
                isPowerStateKnown: true
            )
        ), .batteryLimitReached(batteryPercent: 30, limitPercent: 30))
    }

    func testBatteryEncodingGateBlocksPowerConnectedOnlyWithoutPower() {
        let settings = BatteryEncodingSettings(
            batteryLimitPercent: 30,
            powerConnectedOnly: true
        )

        XCTAssertEqual(BatteryEncodingGate.blockReason(
            settings: settings,
            snapshot: BatteryEncodingPowerSnapshot(
                batteryPercent: 80,
                isPowerConnected: false,
                isPowerStateKnown: true
            )
        ), .powerDisconnected(isPowerStateKnown: true))

        XCTAssertNil(BatteryEncodingGate.blockReason(
            settings: settings,
            snapshot: BatteryEncodingPowerSnapshot(
                batteryPercent: 80,
                isPowerConnected: true,
                isPowerStateKnown: true
            )
        ))
    }

    func testBackgroundEncodingSnapshotClampsProgressFraction() {
        let lowSnapshot = TaptionBackgroundEncodingSnapshot(
            title: "Taption Encoder",
            subtitle: "Queued",
            fractionCompleted: -0.25
        )
        let highSnapshot = TaptionBackgroundEncodingSnapshot(
            title: "Taption Encoder",
            subtitle: "Done",
            fractionCompleted: 2.1
        )

        XCTAssertEqual(lowSnapshot.fractionCompleted, 0)
        XCTAssertEqual(highSnapshot.fractionCompleted, 1)
    }

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

    func testH264ToHEVCUsesSoftwareEncodeOnOldestSupportedIPad() {
        let profile = appleModelProfile("iPad7,11")
        let selection = selectRoute(
            sourceCodec: .h264,
            outputCodec: .hevc,
            profile: profile
        )

        XCTAssertTrue(profile.canHardwareDecode(.h264))
        XCTAssertFalse(profile.canHardwareEncode(.hevc))
        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .mixed)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testHEVCToHEVCUsesSoftwareFallbackOnOldestSupportedIPad() {
        let profile = appleModelProfile("iPad7,11")
        let selection = selectRoute(
            sourceCodec: .hevc,
            outputCodec: .hevc,
            profile: profile
        )

        XCTAssertFalse(profile.canHardwareDecode(.hevc))
        XCTAssertFalse(profile.canHardwareEncode(.hevc))
        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .software)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testHEVCToHEVCStillPrefersHardwareWhenAvailable() {
        let selection = selectRoute(
            sourceCodec: .hevc,
            outputCodec: .hevc,
            profile: .h264HEVCHardware
        )

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

    func testH261ToHEVCUsesSoftwareWhenNoHardwareIsAvailable() {
        let selection = selectRoute(
            sourceCodec: .h261,
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

    func testNextSevenLegacyCodecsToHEVCUseSoftwareWhenNoHardwareIsAvailable() {
        let codecs: [TaptionVideoCodec] = [
            .flashVideo,
            .microsoftMPEG4V2,
            .microsoftMPEG4V3,
            .jpeg2000,
            .jpegLS,
            .losslessJPEG,
            .animation
        ]

        for codec in codecs {
            let selection = selectRoute(
                sourceCodec: codec,
                outputCodec: .hevc,
                profile: .softwareOnly
            )

            XCTAssertEqual(selection.support, .implemented, codec.displayName)
            XCTAssertTrue(selection.isEncodableNow, codec.displayName)
            XCTAssertEqual(selection.executionKind, .software, codec.displayName)
            XCTAssertEqual(selection.selectedMode, .software, codec.displayName)
            XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder, codec.displayName)
            XCTAssertEqual(selection.encodeBackend, .customSoftware, codec.displayName)
        }
    }

    func testNextFiveLegacyCodecsToHEVCUseSoftwareWhenNoHardwareIsAvailable() {
        let codecs: [TaptionVideoCodec] = [
            .cinepak,
            .sorensonVideo,
            .sorensonVideo3,
            .quickTimeVideo,
            .theora
        ]

        for codec in codecs {
            let selection = selectRoute(
                sourceCodec: codec,
                outputCodec: .hevc,
                profile: .softwareOnly
            )

            XCTAssertEqual(selection.support, .implemented, codec.displayName)
            XCTAssertTrue(selection.isEncodableNow, codec.displayName)
            XCTAssertEqual(selection.executionKind, .software, codec.displayName)
            XCTAssertEqual(selection.selectedMode, .software, codec.displayName)
            XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder, codec.displayName)
            XCTAssertEqual(selection.encodeBackend, .customSoftware, codec.displayName)
        }
    }

    func testNextTenPreservationCodecsToHEVCUseSoftwareWhenNoHardwareIsAvailable() {
        let codecs: [TaptionVideoCodec] = [
            .snow,
            .utVideo,
            .magicYUV,
            .pngVideo,
            .r10k,
            .r210,
            .microsoftRLE,
            .quickTimeGraphics,
            .rawVideo
        ]

        for codec in codecs {
            let selection = selectRoute(
                sourceCodec: codec,
                outputCodec: .hevc,
                profile: .softwareOnly
            )

            XCTAssertEqual(selection.support, .implemented, codec.displayName)
            XCTAssertTrue(selection.isEncodableNow, codec.displayName)
            XCTAssertEqual(selection.executionKind, .software, codec.displayName)
            XCTAssertEqual(selection.selectedMode, .software, codec.displayName)
            XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder, codec.displayName)
            XCTAssertEqual(selection.encodeBackend, .customSoftware, codec.displayName)
        }

        let y41pSelection = selectRoute(
            sourceCodec: .y41p,
            outputCodec: .hevc,
            profile: .softwareOnly
        )
        XCTAssertEqual(y41pSelection.support, .planned)
        XCTAssertFalse(y41pSelection.isEncodableNow)
        XCTAssertEqual(y41pSelection.executionKind, .planned)
        XCTAssertEqual(y41pSelection.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(y41pSelection.encodeBackend, .ffmpegFamily)

        let vc1Selection = selectRoute(
            sourceCodec: .vc1,
            outputCodec: .hevc,
            profile: .softwareOnly
        )
        XCTAssertEqual(vc1Selection.support, .planned)
        XCTAssertFalse(vc1Selection.isEncodableNow)
        XCTAssertEqual(vc1Selection.executionKind, .planned)
        XCTAssertEqual(vc1Selection.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(vc1Selection.encodeBackend, .ffmpegFamily)
    }

    func testRealVideoAndRoQCodecsToHEVCReflectCurrentBackendReadiness() {
        let realVideoCodecs: [TaptionVideoCodec] = [
            .realVideo1,
            .realVideo
        ]

        for codec in realVideoCodecs {
            let selection = selectRoute(
                sourceCodec: codec,
                outputCodec: .hevc,
                profile: .softwareOnly
            )

            XCTAssertEqual(selection.support, .implemented, codec.displayName)
            XCTAssertTrue(selection.isEncodableNow, codec.displayName)
            XCTAssertEqual(selection.executionKind, .software, codec.displayName)
            XCTAssertEqual(selection.selectedMode, .software, codec.displayName)
            XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder, codec.displayName)
            XCTAssertEqual(selection.encodeBackend, .customSoftware, codec.displayName)
        }

        let roqSelection = selectRoute(
            sourceCodec: .roqVideo,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(roqSelection.support, .implemented)
        XCTAssertTrue(roqSelection.isEncodableNow)
        XCTAssertEqual(roqSelection.executionKind, .software)
        XCTAssertEqual(roqSelection.selectedMode, .software)
        XCTAssertEqual(roqSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(roqSelection.encodeBackend, .customSoftware)
    }

    func testMotionJPEGToHEVCUsesSoftwareWhenNoHardwareIsAvailable() {
        let selection = selectRoute(
            sourceCodec: .motionJPEG,
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

    func testWMVToHEVCUsesSoftwareWhenNoHardwareIsAvailable() {
        let selection = selectRoute(
            sourceCodec: .wmv,
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
        let jpegToHEVC = selectRoute(
            sourceCodec: .jpeg,
            outputCodec: .hevc,
            profile: .softwareOnly
        )
        let h264ToAV1 = selectRoute(
            sourceCodec: .h264,
            outputCodec: .av1,
            profile: .h264HEVCHardware
        )

        XCTAssertEqual(jpegToHEVC.support, .planned)
        XCTAssertEqual(jpegToHEVC.executionKind, .planned)
        XCTAssertFalse(jpegToHEVC.isEncodableNow)
        XCTAssertEqual(jpegToHEVC.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(jpegToHEVC.encodeBackend, .ffmpegFamily)

        XCTAssertEqual(h264ToAV1.support, .unsupported)
        XCTAssertEqual(h264ToAV1.executionKind, .unsupported)
        XCTAssertFalse(h264ToAV1.isEncodableNow)
    }

    func testInputToHEVCRoutePlanningPrefersHardwareBackendsPerCodecSide() {
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

    func testUniversalSourceCatalogFeedsH265OnlyOutputCatalog() {
        XCTAssertEqual(
            TaptionCodecRegistry.universalOutputCodecs,
            [.hevc],
            "Output codec options are intentionally limited to H.265 for the current product contract."
        )
        XCTAssertNotEqual(
            TaptionCodecRegistry.universalSourceCodecs,
            TaptionCodecRegistry.universalOutputCodecs,
            "Input and output catalogs are intentionally asymmetric while the product outputs H.265 only."
        )
    }

    func testUniversalCodecContractKeepsRepresentativeInputToH265Routes() {
        let examples = Set(TaptionCodecRegistry.universalContractExampleRoutes)

        XCTAssertEqual(TaptionCodecRegistry.universalProductContractName, "All Inputs to H.265 Codec Mesh")
        XCTAssertEqual(
            TaptionCodecRegistry.universalRoutePairCount,
            TaptionCodecRegistry.universalSourceCodecs.count * TaptionCodecRegistry.universalOutputCodecs.count
        )
        XCTAssertEqual(TaptionCodecRegistry.universalRoutePairs.count, TaptionCodecRegistry.universalRoutePairCount)

        let h264ToHEVC = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)
        let av1ToHEVC = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)
        let h264ToAV1 = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .av1)

        XCTAssertTrue(examples.contains(h264ToHEVC))
        XCTAssertTrue(examples.contains(av1ToHEVC))
        XCTAssertTrue(examples.allSatisfy { $0.outputCodec == .hevc })
        XCTAssertTrue(TaptionCodecRegistry.routeIsInUniversalContract(h264ToHEVC))
        XCTAssertTrue(TaptionCodecRegistry.routeIsInUniversalContract(av1ToHEVC))
        XCTAssertFalse(TaptionCodecRegistry.routeIsInUniversalContract(h264ToAV1))
        XCTAssertEqual(TaptionCodecRegistry.support(for: h264ToAV1), .unsupported)
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
        XCTAssertEqual(report.sameCodecVideoRouteCount, 1)
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
        XCTAssertTrue(report.softwareVideoOutputUnsupportedCodecs.isEmpty)
        XCTAssertTrue(report.softwareAudioOutputUnsupportedCodecs.contains(.xheAAC))
        XCTAssertTrue(report.broadSoftwareBackendRequiresLicenseReview)
    }

    func testUniversalCodecCompletionAuditLocksInputToH265Goal() {
        let report = TaptionUniversalCodecCompletionAuditor.makeReport()
        let outputReadinessCatalog = TaptionCodecOutputCatalog.makeReadinessReport()
        let audioOutputReadinessCatalog = TaptionAudioCodecOutputCatalog.makeReadinessReport()
        let h264ToHEVC = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)
        let av1ToHEVC = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)

        XCTAssertEqual(report.contractName, "All Inputs to H.265 Codec Mesh")
        XCTAssertEqual(report.stage, .allToAllPlanningLocked)
        XCTAssertTrue(report.universalPlanningIsLocked)
        XCTAssertFalse(report.universalCommandPlanningIsComplete)
        XCTAssertFalse(report.universalExecutionIsComplete)
        XCTAssertTrue(report.requiredBidirectionalVideoRoutes.contains(h264ToHEVC))
        XCTAssertTrue(report.requiredBidirectionalVideoRoutes.contains(av1ToHEVC))
        XCTAssertTrue(report.requiredBidirectionalVideoRoutes.allSatisfy { $0.outputCodec == .hevc })
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
        XCTAssertEqual(report.videoBlockedMissingSoftwareEncoderRouteCount, 0)
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

    func testUniversalCodecMatrixDoesNotRequireNonH265ReverseOutputs() {
        for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
            let forwardRoute = TaptionCodecRoute(
                sourceCodec: sourceCodec,
                outputCodec: .hevc
            )
            let reverseRoute = TaptionCodecRoute(
                sourceCodec: .hevc,
                outputCodec: sourceCodec
            )

            XCTAssertTrue(
                TaptionCodecRegistry.plannedUniversalRoutes.contains(forwardRoute),
                "Missing forward route \(sourceCodec.rawValue) -> hevc"
            )
            XCTAssertNotEqual(
                TaptionCodecRegistry.support(for: forwardRoute),
                .unsupported,
                "Forward route became unsupported: \(sourceCodec.rawValue) -> hevc"
            )
            if sourceCodec == .hevc {
                XCTAssertTrue(
                    TaptionCodecRegistry.plannedUniversalRoutes.contains(reverseRoute),
                    "HEVC re-encode remains inside the H.265 output contract."
                )
            } else {
                XCTAssertTrue(
                    !TaptionCodecRegistry.plannedUniversalRoutes.contains(reverseRoute),
                    "Non-H.265 reverse output should stay outside the current product contract."
                )
                XCTAssertEqual(
                    TaptionCodecRegistry.support(for: reverseRoute),
                    .unsupported,
                    "Reverse route should be unsupported unless it still outputs H.265."
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
        let h264Modes = Set(h264Descriptors.map(\.mode))
        let hevcRoute = TaptionCodecRoute(sourceCodec: .hevc, outputCodec: .hevc)
        let hevcDescriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: hevcRoute)
        let hevcModes = Set(hevcDescriptors.map(\.mode))
        let alphaRoute = TaptionCodecRoute(sourceCodec: .hevcWithAlpha, outputCodec: .hevc)
        let alphaDescriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: alphaRoute)
        let dolbyRoute = TaptionCodecRoute(sourceCodec: .dolbyVisionHEVC, outputCodec: .hevc)
        let dolbyDescriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: dolbyRoute)
        let mpeg1Route = TaptionCodecRoute(sourceCodec: .mpeg1, outputCodec: .hevc)
        let mpeg1Descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: mpeg1Route)
        let mpeg2Route = TaptionCodecRoute(sourceCodec: .mpeg2, outputCodec: .hevc)
        let mpeg2Descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: mpeg2Route)
        let mpeg4Route = TaptionCodecRoute(sourceCodec: .mpeg4Visual, outputCodec: .hevc)
        let mpeg4Descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: mpeg4Route)
        let h263Route = TaptionCodecRoute(sourceCodec: .h263, outputCodec: .hevc)
        let h263Descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: h263Route)
        let h261Route = TaptionCodecRoute(sourceCodec: .h261, outputCodec: .hevc)
        let h261Descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: h261Route)
        let motionJPEGRoute = TaptionCodecRoute(sourceCodec: .motionJPEG, outputCodec: .hevc)
        let motionJPEGDescriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: motionJPEGRoute)
        let wmvRoute = TaptionCodecRoute(sourceCodec: .wmv, outputCodec: .hevc)
        let wmvDescriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: wmvRoute)

        XCTAssertEqual(descriptors.count, 2)
        XCTAssertTrue(modes.contains(.hardware))
        XCTAssertTrue(modes.contains(.software))
        XCTAssertEqual(h264Descriptors.count, 2)
        XCTAssertTrue(h264Modes.contains(.hardware))
        XCTAssertTrue(h264Modes.contains(.software))
        XCTAssertTrue(h264Descriptors.contains { $0.mode == .hardware && $0.backend == .appleVideoToolbox })
        XCTAssertTrue(h264Descriptors.contains { $0.mode == .software && $0.backend == .softwareVLCDecoder })
        XCTAssertEqual(hevcDescriptors.count, 2)
        XCTAssertTrue(hevcModes.contains(.hardware))
        XCTAssertTrue(hevcModes.contains(.software))
        XCTAssertTrue(hevcDescriptors.contains { $0.mode == .hardware && $0.backend == .appleVideoToolbox })
        XCTAssertTrue(hevcDescriptors.contains { $0.mode == .software && $0.backend == .softwareVLCDecoder })
        XCTAssertEqual(alphaDescriptors.count, 1)
        XCTAssertEqual(alphaDescriptors.first?.mode, .hardware)
        XCTAssertEqual(alphaDescriptors.first?.backend, .appleVideoToolbox)
        XCTAssertEqual(dolbyDescriptors.count, 1)
        XCTAssertEqual(dolbyDescriptors.first?.mode, .hardware)
        XCTAssertEqual(dolbyDescriptors.first?.backend, .appleVideoToolbox)
        XCTAssertEqual(mpeg1Descriptors.count, 1)
        XCTAssertEqual(mpeg1Descriptors.first?.mode, .software)
        XCTAssertEqual(mpeg1Descriptors.first?.backend, .softwareVLCDecoder)
        XCTAssertEqual(mpeg2Descriptors.count, 1)
        XCTAssertEqual(mpeg2Descriptors.first?.mode, .software)
        XCTAssertEqual(mpeg2Descriptors.first?.backend, .softwareVLCDecoder)
        XCTAssertEqual(mpeg4Descriptors.count, 1)
        XCTAssertEqual(mpeg4Descriptors.first?.mode, .software)
        XCTAssertEqual(mpeg4Descriptors.first?.backend, .softwareVLCDecoder)
        XCTAssertEqual(h263Descriptors.count, 1)
        XCTAssertEqual(h263Descriptors.first?.mode, .software)
        XCTAssertEqual(h263Descriptors.first?.backend, .softwareVLCDecoder)
        XCTAssertEqual(h261Descriptors.count, 1)
        XCTAssertEqual(h261Descriptors.first?.mode, .software)
        XCTAssertEqual(h261Descriptors.first?.backend, .softwareVLCDecoder)
        for codec in [TaptionVideoCodec.flashVideo, .microsoftMPEG4V2, .microsoftMPEG4V3, .jpeg2000, .jpegLS, .losslessJPEG, .animation, .cinepak, .sorensonVideo, .sorensonVideo3, .quickTimeVideo, .theora, .roqVideo, .microsoftVideo1, .asusV1, .asusV2, .flashScreenVideo, .flashScreenVideo2, .zmbv, .cljr, .snow, .ffv1, .huffYUV, .utVideo, .magicYUV, .dvcPro, .dvcProHD, .dv, .cineForm, .dnxhd, .pngVideo, .r10k, .v308, .v210, .r210, .v408, .v410, .microsoftRLE, .quickTimeGraphics, .yuv4, .rawVideo] {
            let route = TaptionCodecRoute(sourceCodec: codec, outputCodec: .hevc)
            let codecDescriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: route)
            XCTAssertEqual(codecDescriptors.count, 1, codec.displayName)
            XCTAssertEqual(codecDescriptors.first?.mode, .software, codec.displayName)
            XCTAssertEqual(codecDescriptors.first?.backend, .softwareVLCDecoder, codec.displayName)
        }
        let vc1Route = TaptionCodecRoute(sourceCodec: .vc1, outputCodec: .hevc)
        XCTAssertTrue(TaptionCodecTranscodingRegistry.live.descriptors(for: vc1Route).isEmpty)
        XCTAssertEqual(
            TaptionCodecTranscodingRegistry.live.plannedDescriptors(for: vc1Route).first?.backend,
            .ffmpegFamily
        )
        let y41pRoute = TaptionCodecRoute(sourceCodec: .y41p, outputCodec: .hevc)
        XCTAssertTrue(TaptionCodecTranscodingRegistry.live.descriptors(for: y41pRoute).isEmpty)
        XCTAssertEqual(
            TaptionCodecTranscodingRegistry.live.plannedDescriptors(for: y41pRoute).first?.backend,
            .ffmpegFamily
        )
        XCTAssertEqual(motionJPEGDescriptors.count, 1)
        XCTAssertEqual(motionJPEGDescriptors.first?.mode, .software)
        XCTAssertEqual(motionJPEGDescriptors.first?.backend, .softwareVLCDecoder)
        XCTAssertEqual(wmvDescriptors.count, 1)
        XCTAssertEqual(wmvDescriptors.first?.mode, .software)
        XCTAssertEqual(wmvDescriptors.first?.backend, .softwareVLCDecoder)
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
        let outputURL = temporaryTestURL(fileName: "mixed-first-hevc.mp4")
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
        let plannedRoute = TaptionCodecRoute(sourceCodec: .jpeg, outputCodec: .hevc)

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
        let plannedRoute = TaptionCodecRoute(sourceCodec: .jpeg, outputCodec: .hevc)
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
        let outputURL = temporaryTestURL(fileName: "runtime-registry-jpeg-to-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let plannedRoute = TaptionCodecRoute(sourceCodec: .jpeg, outputCodec: .hevc)
        let registry = TaptionCodecTranscodingRegistry.makeLive(
            softwareExecutor: SW_FFmpegCommandExecutor(
                readinessReport: readyBroadSoftwareBackendReport(),
                runner: FakeFFmpegCommandRunner { commandPlan in
                    XCTAssertEqual(commandPlan.routeSummary, plannedRoute.displayName)
                    XCTAssertTrue(commandPlan.arguments.contains("libx265"))
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
                options: .preservingSource(outputCodec: .hevc, container: .mp4)
            ),
            executionKind: .software
        ) { progress in
            progressStages.append(progress.stage)
        }

        XCTAssertEqual(output.route, plannedRoute)
        XCTAssertEqual(output.outputURL, outputURL)
        XCTAssertEqual(output.usedMode, .software)
        XCTAssertEqual(output.usedBackend, .ffmpegFamily)
        XCTAssertEqual(output.outputVideoCodec, .hevc)
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testUniversalSoftwareAlgorithmReportsBundledBackendMissingUntilImplementationLands() async {
        let route = TaptionCodecRoute(sourceCodec: .jpeg, outputCodec: .hevc)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: route,
            options: .preservingSource(outputCodec: .hevc, container: .mp4)
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
        let route = TaptionCodecRoute(sourceCodec: .jpeg, outputCodec: .hevc)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: route,
            options: .preservingSource(outputCodec: .hevc, container: .mp4)
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
        let outputURL = temporaryTestURL(fileName: "jpeg-to-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let route = TaptionCodecRoute(sourceCodec: .jpeg, outputCodec: .hevc)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            outputURL: outputURL,
            route: route,
            options: .preservingSource(outputCodec: .hevc, container: .mp4)
        )
        let videoExecutor = SW_FFmpegVideoCodecTranscodeExecutor(
            executor: SW_FFmpegCommandExecutor(
                readinessReport: readyBroadSoftwareBackendReport(),
                runner: FakeFFmpegCommandRunner { commandPlan in
                    XCTAssertEqual(commandPlan.routeSummary, route.displayName)
                    XCTAssertTrue(commandPlan.arguments.contains("libx265"))
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
        XCTAssertEqual(output.outputVideoCodec, .hevc)
        XCTAssertEqual(output.outputAudioTrackCount, 1)
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testUniversalVideoCommandPlanBuildsInputToH265Routes() throws {
        let h264ToHEVC = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)
        let av1ToHEVC = TaptionCodecRoute(sourceCodec: .av1, outputCodec: .hevc)
        let h264ToHEVCPlan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/h264.mp4"),
                outputURL: URL(fileURLWithPath: "/tmp/h264-hevc.mp4"),
                route: h264ToHEVC,
                options: .preservingSource(outputCodec: .hevc, container: .mp4)
            )
        )
        let av1ToHEVCPlan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/av1.webm"),
                outputURL: URL(fileURLWithPath: "/tmp/av1-hevc.mov"),
                route: av1ToHEVC,
                options: .preservingSource(outputCodec: .hevc, container: .mov)
            )
        )

        XCTAssertEqual(h264ToHEVCPlan.backend, .ffmpegFamily)
        XCTAssertEqual(h264ToHEVCPlan.routeSummary, h264ToHEVC.displayName)
        XCTAssertTrue(h264ToHEVCPlan.arguments.contains("libx265"))
        XCTAssertTrue(h264ToHEVCPlan.arguments.contains("/tmp/h264-hevc.mp4"))

        XCTAssertEqual(av1ToHEVCPlan.routeSummary, av1ToHEVC.displayName)
        XCTAssertTrue(av1ToHEVCPlan.arguments.contains("libx265"))
        XCTAssertTrue(av1ToHEVCPlan.arguments.contains("+faststart"))
    }

    func testUniversalVideoCommandPlanAppliesAdvancedOutputOptions() throws {
        let route = TaptionCodecRoute(sourceCodec: .vp9, outputCodec: .hevc)
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
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
                outputURL: URL(fileURLWithPath: "/tmp/vp9-hevc.mp4"),
                route: route,
                options: TaptionCodecTranscodeOptions(outputPolicy: outputPolicy)
            )
        )

        XCTAssertTrue(plan.arguments.contains("scale=1280:720"))
        XCTAssertTrue(plan.arguments.contains("30000/1001"))
        XCTAssertTrue(plan.arguments.contains("8000000"))
        XCTAssertTrue(plan.arguments.contains("libx265"))
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
        XCTAssertEqual(SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs, [.hevc])
        XCTAssertTrue(SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs.isEmpty)
    }

    func testUniversalVideoCommandPlannerBuildsEveryPlannableSourceOutputPair() throws {
        for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
            for outputCodec in SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs {
                let route = TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
                let request = TaptionCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/input-\(sourceCodec.rawValue).mkv"),
                    outputURL: URL(fileURLWithPath: "/tmp/output-\(outputCodec.rawValue).mp4"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, container: .mp4)
                )

                let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

                XCTAssertEqual(plan.backend, .ffmpegFamily, route.displayName)
                XCTAssertEqual(plan.routeSummary, route.displayName, route.displayName)
                XCTAssertTrue(plan.arguments.contains("-c:v"), route.displayName)
                XCTAssertEqual(
                    plan.arguments.last,
                    "/tmp/output-\(outputCodec.rawValue).mp4",
                    route.displayName
                )
            }
        }
    }

    func testUniversalVideoCommandPlannerAcceptsEveryReadableInputContainer() throws {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)

        for inputContainer in SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.readableContainers.sorted(by: containerSort) {
            let request = TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.\(inputContainer.defaultFileExtension)"),
                outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
                route: route,
                options: .preservingSource(outputCodec: .hevc, container: .mp4)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(request: request)

            XCTAssertEqual(plan.sourceURL.pathExtension, inputContainer.defaultFileExtension, inputContainer.rawValue)
            XCTAssertEqual(plan.routeSummary, route.displayName, inputContainer.rawValue)
        }
    }

    func testUniversalVideoCommandPlannerAcceptsEveryWritableOutputContainer() throws {
        let route = TaptionCodecRoute(sourceCodec: .vp9, outputCodec: .hevc)

        for outputContainer in SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.writableContainers.sorted(by: containerSort) {
            let request = TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.webm"),
                outputURL: URL(fileURLWithPath: "/tmp/output.\(outputContainer.defaultFileExtension)"),
                route: route,
                options: .preservingSource(outputCodec: .hevc, container: outputContainer)
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
                outputURL: URL(fileURLWithPath: "/tmp/audio-output.mp4"),
                route: route,
                options: .preservingSource(outputCodec: .flac, outputContainer: .mp4)
            )

            let plan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(request: request)

            XCTAssertEqual(plan.sourceURL.pathExtension, inputContainer.defaultFileExtension, inputContainer.rawValue)
            XCTAssertEqual(plan.routeSummary, route.displayName, inputContainer.rawValue)
        }
    }

    func testUniversalCommandPlannerRejectsUnknownInputContainer() {
        let videoRoute = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)
        let videoRequest = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.notmedia"),
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            route: videoRoute,
            options: .preservingSource(outputCodec: .hevc, container: .mp4)
        )
        let audioRoute = TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .flac)
        let audioRequest = TaptionAudioCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/audio.notmedia"),
            outputURL: URL(fileURLWithPath: "/tmp/audio-output.mp4"),
            route: audioRoute,
            options: .preservingSource(outputCodec: .flac, outputContainer: .mp4)
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
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "h261"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m1v"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "m2v"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "vc1"), .rawElementaryStream)
        XCTAssertEqual(TaptionVideoContainer.inferred(fromFileExtension: "notmedia"), .unknown)
    }

    func testUniversalVideoCommandPlannerAcceptsRepresentativeReadableAliases() throws {
        let route = TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc)
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
            ("h261", .rawElementaryStream),
            ("m1v", .rawElementaryStream),
            ("m2v", .rawElementaryStream),
            ("vc1", .rawElementaryStream)
        ]

        for alias in aliases {
            let request = TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.\(alias.fileExtension)"),
                outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
                route: route,
                options: .preservingSource(outputCodec: .hevc, container: .mp4)
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
        let thumbnailProviderURL = rootURL
            .appendingPathComponent("TaptionEncoderThumbnailExtension/ThumbnailProvider.swift")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let declarations = try XCTUnwrap(
            plist["UTExportedTypeDeclarations"] as? [[String: Any]]
        )
        XCTAssertNil(plist["UTImportedTypeDeclarations"])
        let documentTypes = try XCTUnwrap(
            plist["CFBundleDocumentTypes"] as? [[String: Any]]
        )
        let legacyDocumentType = try XCTUnwrap(
            documentTypes.first { documentType in
                (documentType["LSItemContentTypes"] as? [String])?.contains("com.taption.legacy-video") == true
            }
        )
        let standardVideoDocumentType = try XCTUnwrap(
            documentTypes.first { documentType in
                (documentType["LSItemContentTypes"] as? [String])?.contains("public.movie") == true
            }
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
        let documentContentTypes = Set(
            documentTypes.flatMap { documentType -> [String] in
                documentType["LSItemContentTypes"] as? [String] ?? []
            }
        )
        let documentHandlerRanks = Set(
            documentTypes.compactMap { documentType in
                documentType["LSHandlerRank"] as? String
            }
        )
        let documentIconFiles = Set(
            documentTypes.flatMap { documentType -> [String] in
                documentType["CFBundleTypeIconFiles"] as? [String] ?? []
            }
        )
        let exportedIdentifiers = Set(
            declarations.compactMap { declaration in
                declaration["UTTypeIdentifier"] as? String
            }
        )
        let exportedConformance = Set(
            declarations.flatMap { declaration -> [String] in
                declaration["UTTypeConformsTo"] as? [String] ?? []
            }
        )
        let exportedIconFiles = Set(
            declarations.compactMap { declaration in
                declaration["UTTypeIconFile"] as? String
            }
        )
        let systemHandledExtensions: Set<String> = [
            "3g2",
            "3gp",
            "3gpp",
            "3gpp2",
            "m4v",
            "mov",
            "mp4",
            "qt"
        ]
        let legacySystemContentTypes: Set<String> = [
            "public.avi",
            "org.smpte.mxf",
            "public.dv-movie",
            "com.microsoft.advanced-systems-format",
            "com.microsoft.windows-media-wmv",
            "com.real.realmedia",
            "com.real.realmedia-vbr",
            "org.webmproject.webm",
            "com.adobe.flash.video",
            "public.mpeg",
            "public.mpeg-2-video",
            "public.mpeg-2-transport-stream",
            "public.avchd-mpeg-2-transport-stream",
            "org.xiph.ogv",
            "org.xiph.ogg-audio"
        ]
        let externalPlayerExtensions = launchExtensions.subtracting(systemHandledExtensions)
        let standardVideoContentTypes: Set<String> = [
            "public.audiovisual-content",
            "public.movie",
            "public.video",
            "public.mpeg-4",
            "com.apple.m4v-video",
            "com.apple.quicktime-movie",
            "public.3gpp",
            "public.3gpp2"
        ]
        let thumbnailProviderText = try String(contentsOf: thumbnailProviderURL, encoding: .utf8)
        let thumbnailExtensionLiterals = Set(
            thumbnailProviderText
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmedLine.hasPrefix("\"") else {
                        return nil
                    }
                    let valueStart = trimmedLine.index(after: trimmedLine.startIndex)
                    guard let valueEnd = trimmedLine[valueStart...].firstIndex(of: "\"") else {
                        return nil
                    }
                    return String(trimmedLine[valueStart..<valueEnd])
                }
        )
        let thumbnailLegacyExtensions = thumbnailExtensionLiterals.subtracting(systemHandledExtensions)

        XCTAssertTrue(
            plistExtensions.isSuperset(of: externalPlayerExtensions),
            "Missing Info.plist legacy video extensions: \(externalPlayerExtensions.subtracting(plistExtensions).sorted().joined(separator: ", "))"
        )
        XCTAssertEqual(
            plistExtensions,
            externalPlayerExtensions,
            "Info.plist should only claim currently supported Taption Encoder-only video extensions."
        )
        XCTAssertTrue(
            plistExtensions.isDisjoint(with: systemHandledExtensions),
            "Info.plist should not claim default-player video extensions: \(plistExtensions.intersection(systemHandledExtensions).sorted().joined(separator: ", "))"
        )
        XCTAssertEqual(
            thumbnailLegacyExtensions,
            externalPlayerExtensions,
            "Thumbnail extension should only generate legacy posters for currently supported Taption Encoder-only video extensions."
        )
        XCTAssertTrue(
            thumbnailExtensionLiterals.isSuperset(of: systemHandledExtensions),
            "Thumbnail extension should preserve frame thumbnails for system-handled video extensions."
        )
        XCTAssertTrue(documentContentTypes.isSuperset(of: ["com.taption.legacy-video"]))
        XCTAssertTrue(documentContentTypes.isSuperset(of: legacySystemContentTypes))
        XCTAssertTrue(documentContentTypes.isSuperset(of: standardVideoContentTypes))
        XCTAssertEqual(documentHandlerRanks, ["Owner"])
        XCTAssertEqual(legacyDocumentType["LSHandlerRank"] as? String, "Owner")
        XCTAssertEqual(legacyDocumentType["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertTrue(
            Set(legacyDocumentType["LSItemContentTypes"] as? [String] ?? []).isSuperset(of: legacySystemContentTypes),
            "Legacy document type should claim Files-resolved Taption Encoder video UTIs."
        )
        XCTAssertEqual(standardVideoDocumentType["LSHandlerRank"] as? String, "Owner")
        XCTAssertEqual(standardVideoDocumentType["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertEqual(documentIconFiles, ["AppIcon60x60"])
        XCTAssertEqual(exportedIdentifiers, ["com.taption.legacy-video"])
        XCTAssertTrue(exportedConformance.isSuperset(of: ["public.movie", "public.video"]))
        XCTAssertEqual(exportedIconFiles, ["AppIcon60x60"])
        XCTAssertEqual(plist["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
        XCTAssertEqual(plist["UIFileSharingEnabled"] as? Bool, true)
        XCTAssertEqual(plist["UISupportsDocumentBrowser"] as? Bool, true)
        XCTAssertEqual(
            Set(try XCTUnwrap(plist["UIBackgroundModes"] as? [String])),
            ["audio", "processing"]
        )
        XCTAssertTrue(SupportedVideoFileExtensions.contains(".mp4"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("qt"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("M4V"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("avi"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("webm"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("DAT"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains(".m2t"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("MTS"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("trp"))
        XCTAssertTrue(SupportedVideoFileExtensions.contains("dif"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("lrf"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("nut"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("dvr-ms"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("vc1"))
        XCTAssertTrue(ImportableVideoTypes.fileExtensions.contains("h261"))
    }

    func testExternalVideoOpenPolicyHandlesOnlySupportedFileURLs() {
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Movie.MP4")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Legacy.AVI")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Clip.h261")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Camera.M2TS")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/DJI.LRF")))
        XCTAssertTrue(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/Archive.nut")))
        XCTAssertFalse(ExternalVideoOpenPolicy.canHandle(url: URL(fileURLWithPath: "/tmp/notes.txt")))
        XCTAssertFalse(ExternalVideoOpenPolicy.canHandle(url: URL(string: "https://example.com/movie.mp4")!))
    }

    @MainActor
    func testExternalVideoOpenInboxRetainsDelegateURLUntilHomeViewDrains() {
        _ = ExternalVideoOpenInbox.drainPendingURLs()
        let url = URL(fileURLWithPath: "/tmp/Movie.MP4")

        ExternalVideoOpenInbox.enqueue(url, postsNotification: false)

        XCTAssertEqual(ExternalVideoOpenInbox.drainPendingURLs(), [url])
        XCTAssertEqual(ExternalVideoOpenInbox.drainPendingURLs(), [])
    }

    func testQuickLookThumbnailExtensionCoversDocumentBrowserVideoTypes() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appPlistURL = rootURL.appendingPathComponent("TaptionEncoder/Info.plist")
        let extensionPlistURL = rootURL.appendingPathComponent("TaptionEncoderThumbnailExtension/Info.plist")
        let projectURL = rootURL.appendingPathComponent("TaptionEncoder.xcodeproj/project.pbxproj")
        let appPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: try Data(contentsOf: appPlistURL),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let extensionPlist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: try Data(contentsOf: extensionPlistURL),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let documentTypes = try XCTUnwrap(
            appPlist["CFBundleDocumentTypes"] as? [[String: Any]]
        )
        let documentContentTypes = Set(
            documentTypes.flatMap { documentType in
                documentType["LSItemContentTypes"] as? [String] ?? []
            }
        )
        let extensionInfo = try XCTUnwrap(extensionPlist["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        let supportedContentTypes = Set(
            try XCTUnwrap(attributes["QLSupportedContentTypes"] as? [String])
        )
        let appTypeDeclarations = try XCTUnwrap(
            appPlist["UTExportedTypeDeclarations"] as? [[String: Any]]
        )
        let appLegacyDeclaration = try XCTUnwrap(
            appTypeDeclarations.first { declaration in
                declaration["UTTypeIdentifier"] as? String == "com.taption.legacy-video"
            }
        )
        let appLegacyTagSpecification = try XCTUnwrap(
            appLegacyDeclaration["UTTypeTagSpecification"] as? [String: Any]
        )
        let appLegacyFileExtensions = Set(
            try XCTUnwrap(appLegacyTagSpecification["public.filename-extension"] as? [String])
        )
        let extensionImportedDeclarations = try XCTUnwrap(
            extensionPlist["UTImportedTypeDeclarations"] as? [[String: Any]]
        )
        let extensionLegacyDeclaration = try XCTUnwrap(
            extensionImportedDeclarations.first { declaration in
                declaration["UTTypeIdentifier"] as? String == "com.taption.legacy-video"
            }
        )
        let extensionLegacyConformance = Set(
            try XCTUnwrap(extensionLegacyDeclaration["UTTypeConformsTo"] as? [String])
        )
        let extensionLegacyTagSpecification = try XCTUnwrap(
            extensionLegacyDeclaration["UTTypeTagSpecification"] as? [String: Any]
        )
        let extensionLegacyFileExtensions = Set(
            try XCTUnwrap(extensionLegacyTagSpecification["public.filename-extension"] as? [String])
        )
        let projectText = try String(contentsOf: projectURL, encoding: .utf8)
        let filesResolvedContentTypes: Set<String> = [
            "com.apple.m4v-video",
            "public.avi",
            "org.smpte.mxf",
            "public.dv-movie",
            "com.microsoft.advanced-systems-format",
            "com.microsoft.windows-media-wmv",
            "com.real.realmedia",
            "com.real.realmedia-vbr",
            "org.webmproject.webm",
            "com.adobe.flash.video",
            "public.mpeg",
            "public.mpeg-2-video",
            "public.mpeg-2-transport-stream",
            "public.avchd-mpeg-2-transport-stream",
            "org.xiph.ogv",
            "org.xiph.ogg-audio"
        ]

        XCTAssertEqual(
            extensionInfo["NSExtensionPointIdentifier"] as? String,
            "com.apple.quicklook.thumbnail"
        )
        XCTAssertEqual(
            extensionInfo["NSExtensionPrincipalClass"] as? String,
            "$(PRODUCT_MODULE_NAME).ThumbnailProvider"
        )
        XCTAssertEqual(
            supportedContentTypes,
            ["com.taption.legacy-video"],
            "Thumbnail extension must avoid system-supported QL types that App Store Connect rejects."
        )
        XCTAssertTrue(
            supportedContentTypes.isDisjoint(with: documentContentTypes.subtracting(["com.taption.legacy-video"])),
            "Thumbnail extension must not declare system document types: \(supportedContentTypes.intersection(documentContentTypes.subtracting(["com.taption.legacy-video"])).sorted().joined(separator: ", "))"
        )
        XCTAssertTrue(
            supportedContentTypes.isDisjoint(with: filesResolvedContentTypes),
            "Thumbnail extension must not declare system-resolved file UTIs: \(supportedContentTypes.intersection(filesResolvedContentTypes).sorted().joined(separator: ", "))"
        )
        XCTAssertNil(extensionPlist["UTExportedTypeDeclarations"])
        XCTAssertEqual(extensionLegacyFileExtensions, appLegacyFileExtensions)
        XCTAssertTrue(extensionLegacyFileExtensions.contains("h261"))
        XCTAssertTrue(extensionLegacyConformance.isSuperset(of: ["public.movie", "public.video"]))
        XCTAssertTrue(projectText.contains("SampleThumbnailCatalog.swift in Sources"))
        XCTAssertTrue(projectText.contains("SampleThumbnails in Resources"))
        let extensionResourcesBlock = try XCTUnwrap(
            projectObjectBlock(
                id: "B10000000000000000000600",
                label: "Resources",
                in: projectText
            )
        )
        let testResourcesBlock = try XCTUnwrap(
            projectObjectBlock(
                id: "8A2B3C4D5E6F701000000600",
                label: "Resources",
                in: projectText
            )
        )
        XCTAssertTrue(
            extensionResourcesBlock.contains("B10000000000000000000004 /* SampleThumbnails in Resources */"),
            "Thumbnail extension target must embed SampleThumbnails for Files thumbnails."
        )
        XCTAssertFalse(
            testResourcesBlock.contains("SampleThumbnails in Resources"),
            "SampleThumbnails should not be routed only into the test bundle."
        )
        XCTAssertTrue(projectText.contains("TaptionEncoderThumbnailExtension.appex in Embed Foundation Extensions"))
        XCTAssertTrue(projectText.contains("com.apple.product-type.app-extension"))
        XCTAssertTrue(projectText.contains("PRODUCT_BUNDLE_IDENTIFIER = com.taption.encoder.thumbnail"))
        XCTAssertTrue(projectText.contains("APPLICATION_EXTENSION_API_ONLY = YES"))
    }

    func testBundledTestVideosMatchCurrentLaunchVideoSupport() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let testVideosURL = rootURL.appendingPathComponent("TaptionEncoder/TestVideos", isDirectory: true)
        let filenames = try FileManager.default
            .contentsOfDirectory(atPath: testVideosURL.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()
        let videoFilenames = filenames.filter { $0 != TaptionTestVideoSeeder.sourceNoticeFilename }

        XCTAssertEqual(Set(videoFilenames), Set(TaptionTestVideoSeeder.expectedBundledVideoSampleFilenames))
        XCTAssertEqual(
            videoFilenames.count,
            bundledAvailableNowSampleCodecExpectations().count
                + bundledPlannedSampleCodecExpectations().count
                + TaptionLaunchSupportCatalog.hardwareGatedInputVideoCodecs.count
        )
        XCTAssertTrue(filenames.contains(TaptionTestVideoSeeder.sourceNoticeFilename))
        XCTAssertFalse(videoFilenames.contains { $0.hasPrefix("available-now_") })
        XCTAssertFalse(videoFilenames.contains { $0.hasPrefix("supported-hardware_") })
        XCTAssertFalse(videoFilenames.contains { $0.contains("_") })
        XCTAssertFalse(videoFilenames.contains("Y41P.avi"))
    }

    func testBundledSampleSourceNoticeRejectsGeneratedOnlyFixtures() throws {
        let sourceNoticeURL = bundledTestVideosURL().appendingPathComponent(TaptionTestVideoSeeder.sourceNoticeFilename)
        let sourceNotice = try String(contentsOf: sourceNoticeURL, encoding: .utf8)

        XCTAssertFalse(sourceNotice.contains("Generated codec-conformance fixture"))
        XCTAssertFalse(sourceNotice.contains("Generated with FFmpeg"))
        XCTAssertFalse(sourceNotice.contains("mpeg_demuxer_crash.mpg"))
        XCTAssertFalse(sourceNotice.contains("real/VC-RV10/thankyou.rm"))
        XCTAssertFalse(sourceNotice.contains("real/VC-RV20/Dolby7.5fps1.rm"))
        XCTAssertFalse(sourceNotice.contains("snow-chroma-bug.avi"))
        XCTAssertFalse(sourceNotice.contains("audible tone track when"))
        XCTAssertFalse(sourceNotice.contains("Derived from Chromium bear.mp4"))
        XCTAssertTrue(sourceNotice.contains("Official Blender Open Movie downloads"))
        XCTAssertTrue(sourceNotice.contains("BigBuckBunny_320x180.mp4"))
        XCTAssertTrue(sourceNotice.contains("sintel_trailer-480p.mp4"))
        XCTAssertTrue(sourceNotice.contains("original"))
        XCTAssertTrue(sourceNotice.contains("source audio"))
        XCTAssertFalse(sourceNotice.contains("Y41P.avi"))
    }

    func testBundledSampleThumbnailResourcesCoverSeededVideos() throws {
        let testVideosURL = bundledTestVideosURL()
        let thumbnailsURL = testVideosURL
            .deletingLastPathComponent()
            .appendingPathComponent(SampleThumbnailCatalog.resourceSubdirectory, isDirectory: true)
        let videoFilenames = try FileManager.default
            .contentsOfDirectory(atPath: testVideosURL.path)
            .filter { !$0.hasPrefix(".") && $0 != TaptionTestVideoSeeder.sourceNoticeFilename }
            .sorted()
        let thumbnailFilenames = try FileManager.default
            .contentsOfDirectory(atPath: thumbnailsURL.path)
            .filter { $0.hasSuffix(".png") }
            .sorted()

        XCTAssertEqual(Set(videoFilenames), SampleThumbnailCatalog.expectedSampleFilenames)
        XCTAssertEqual(thumbnailFilenames.count, videoFilenames.count)

        for filename in videoFilenames {
            let sampleURL = testVideosURL.appendingPathComponent(filename)
            let resourceName = try XCTUnwrap(SampleThumbnailCatalog.resourceName(for: sampleURL), filename)
            let thumbnailURL = thumbnailsURL.appendingPathComponent("\(resourceName).png")
            let data = try Data(contentsOf: thumbnailURL)
            let image = try XCTUnwrap(UIImage(data: data), filename)

            XCTAssertEqual(image.size.width, 320, filename)
            XCTAssertEqual(image.size.height, 180, filename)
            XCTAssertGreaterThan(data.count, 128, filename)
        }

        let visiblePreviewSamples = [
            "H.261.h261",
            "R210.avi",
            "RealVideo 1.0.rm",
            "RealVideo.rm",
            "RoQ Video.roq",
            "Snow.avi"
        ]
        for filename in visiblePreviewSamples {
            let sampleURL = testVideosURL.appendingPathComponent(filename)
            let resourceName = try XCTUnwrap(SampleThumbnailCatalog.resourceName(for: sampleURL), filename)
            let thumbnailURL = thumbnailsURL.appendingPathComponent("\(resourceName).png")
            let metrics = try visiblePixelMetrics(fromPNGData: try Data(contentsOf: thumbnailURL))

            XCTAssertGreaterThan(metrics.nonBlackRatio, 0.2, filename)
            XCTAssertGreaterThan(metrics.standardDeviation, 4, filename)
        }
    }

    func testBundledAvailableNowSamplesInspectToExpectedLaunchCodecs() async throws {
        let testVideosURL = bundledTestVideosURL()
        let expectations = bundledAvailableNowSampleCodecExpectations()

        let sampledCodecs = Set(expectations.map(\.1))
        XCTAssertTrue(Set(TaptionLaunchSupportCatalog.executableNowInputVideoCodecs).isSuperset(of: sampledCodecs))
        XCTAssertFalse(TaptionLaunchSupportCatalog.executableNowInputVideoCodecs.contains(.y41p))
        XCTAssertTrue(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.contains(.vc1))
        XCTAssertTrue(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.contains(.y41p))
        XCTAssertFalse(expectations.contains { $0.0 == "Y41P.avi" })

        for (filename, expectedCodec) in expectations {
            let sampleURL = testVideosURL.appendingPathComponent(filename)
            let asset = try await AVFoundationMediaInspector().inspectVideo(at: sampleURL)

            XCTAssertEqual(
                asset.videoTrack?.codec,
                expectedCodec,
                "\(filename) should inspect as \(expectedCodec.displayName)"
            )
            XCTAssertEqual(
                TaptionLaunchSupportCatalog.inputAvailability(for: expectedCodec),
                .availableNow,
                "\(filename) should remain an available-now launch sample"
            )
        }
    }

    func testBundledAvailableNowSamplesAreReadyOnSoftwareOnlyProfile() async throws {
        let testVideosURL = bundledTestVideosURL()

        for (filename, expectedCodec) in bundledAvailableNowSampleCodecExpectations() {
            let sampleURL = testVideosURL.appendingPathComponent(filename)
            let asset = try await AVFoundationMediaInspector().inspectVideo(at: sampleURL)
            let selection = TaptionCodecRoutePlanner.selectRoute(
                for: asset,
                outputCodec: .hevc,
                requestedMode: .automatic,
                hardwareSupport: .softwareOnly
            )

            XCTAssertEqual(asset.videoTrack?.codec, expectedCodec, filename)
            XCTAssertEqual(selection.route, TaptionCodecRoute(sourceCodec: expectedCodec, outputCodec: .hevc), filename)
            XCTAssertTrue(selection.isEncodableNow, filename)
            XCTAssertEqual(selection.executionKind, .software, filename)
            XCTAssertEqual(selection.displayTitle, "Path SW", filename)
        }
    }

    @MainActor
    func testBundledAvailableNowSamplesGenerateQueueThumbnails() async throws {
        var failures: [String] = []

        for filename in filteredBundledAvailableNowSampleFilenames() {
            let sampleURL = bundledTestVideosURL().appendingPathComponent(filename)
            do {
                let image = try await QueueVideoThumbnailRenderer.thumbnailImage(
                    for: sampleURL,
                    timeout: .seconds(4)
                )
                XCTAssertGreaterThan(image.size.width, 0, filename)
                XCTAssertGreaterThan(image.size.height, 0, filename)
                XCTAssertGreaterThan(image.pngData()?.count ?? 0, 128, filename)
            } catch {
                failures.append("\(filename): \(error)")
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Queue thumbnail generation failed for supported bundled samples:\n\(failures.joined(separator: "\n"))"
        )
    }

    @MainActor
    func testQueuePreviewVideoViewProducesVideoOutputForFirstBundledSample() async throws {
        #if targetEnvironment(simulator)
        let sampleURL = bundledTestVideosURL().appendingPathComponent("ASUS V1.avi")
        let player = QueuePreviewPlayerFactory.makePreviewPlayer()
        let media = try Media(url: sampleURL)
        QueuePreviewPlayerFactory.configureSoftwareDecodeOptions(on: media, sourceURL: sampleURL)

        let hostingController = UIHostingController(
            rootView: PiPVideoView(
                player,
                startsAutomaticallyFromInline: true,
                managesAudioSession: false
            )
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
                .frame(width: 320, height: 240)
                .background(Color.black)
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        addTeardownBlock {
            Task { @MainActor in
                window.isHidden = true
                await player.shutdown()
            }
        }
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 250_000_000)

        try player.play(media)
        try await waitForCondition(timeout: 8) {
            player.hasVideoOutput || player.activeVideoOutputs > 0
        }

        let snapshotURL = temporaryTestURL(fileName: "asus-v1-preview.png")
        defer {
            try? FileManager.default.removeItem(at: snapshotURL)
            window.isHidden = true
        }

        try await waitForPreviewSnapshot(
            player: player,
            snapshotURL: snapshotURL,
            timeout: 5
        )

        await player.shutdown()
        #else
        throw XCTSkip("Preview drawable smoke test is simulator-scoped.")
        #endif
    }

    @MainActor
    func testPreviewRegressionSamplesProduceVisibleVideoSnapshots() async throws {
        #if targetEnvironment(simulator)
        let sampleFilenames = [
            "AV1.mp4",
            "Ut Video.avi",
            "Apple Animation.mov"
        ]

        for filename in sampleFilenames {
            let sampleURL = bundledTestVideosURL().appendingPathComponent(filename)
            let player = QueuePreviewPlayerFactory.makePreviewPlayer()
            let media = try Media(url: sampleURL)
            QueuePreviewPlayerFactory.configureSoftwareDecodeOptions(on: media, sourceURL: sampleURL)

            let hostingController = UIHostingController(
                rootView: PiPVideoView(
                    player,
                    startsAutomaticallyFromInline: true,
                    managesAudioSession: false
                )
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 320, height: 240)
                    .background(Color.black)
            )
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 250_000_000)

            try player.play(media)
            try await waitForCondition(timeout: 8) {
                player.hasVideoOutput || player.activeVideoOutputs > 0
            }

            let snapshotURL = temporaryTestURL(fileName: "\(filename)-preview.png")
            defer {
                try? FileManager.default.removeItem(at: snapshotURL)
                window.isHidden = true
            }

            try await waitForPreviewSnapshot(
                player: player,
                snapshotURL: snapshotURL,
                timeout: 5
            )

            let imageData = try Data(contentsOf: snapshotURL)
            let metrics = try visiblePixelMetrics(fromPNGData: imageData)
            XCTAssertGreaterThan(metrics.nonBlackRatio, 0.02, filename)
            XCTAssertGreaterThan(metrics.standardDeviation, 3.0, filename)

            await player.shutdown()
        }
        #else
        throw XCTSkip("Preview visual regression test is simulator-scoped.")
        #endif
    }

    func testQueuePreviewFactoryKeepsQuickTimeDefaultDemuxAndFallsBackToAVFormat() {
        let movURL = URL(fileURLWithPath: "/tmp/Apple Animation.mov")
        let aviURL = URL(fileURLWithPath: "/tmp/ASUS V1.avi")

        XCTAssertEqual(QueuePreviewPlayerFactory.previewDemuxModes(for: movURL), [.automatic, .avformat])
        XCTAssertFalse(
            QueuePreviewPlayerFactory
                .softwareDecodeOptions(for: movURL, demuxMode: .automatic)
                .contains(":demux=avformat")
        )
        XCTAssertTrue(
            QueuePreviewPlayerFactory
                .softwareDecodeOptions(for: movURL, demuxMode: .avformat)
                .contains(":demux=avformat")
        )

        XCTAssertEqual(QueuePreviewPlayerFactory.previewDemuxModes(for: aviURL), [.avformat, .automatic])
        XCTAssertTrue(
            QueuePreviewPlayerFactory
                .softwareDecodeOptions(for: aviURL, demuxMode: .automatic)
                .contains(":demux=avformat")
        )
    }

    func testBundledProResSampleKeepsHardwareGate() async throws {
        let sampleURL = bundledTestVideosURL().appendingPathComponent("Apple ProRes.mov")
        let asset = try await AVFoundationMediaInspector().inspectVideo(at: sampleURL)
        let hardwareSelection = TaptionCodecRoutePlanner.selectRoute(
            for: asset,
            outputCodec: .hevc,
            requestedMode: .automatic,
            hardwareSupport: .proMediaHardware
        )
        let softwareOnlySelection = TaptionCodecRoutePlanner.selectRoute(
            for: asset,
            outputCodec: .hevc,
            requestedMode: .automatic,
            hardwareSupport: .softwareOnly
        )

        XCTAssertEqual(asset.videoTrack?.codec, .proRes)
        XCTAssertEqual(TaptionLaunchSupportCatalog.inputAvailability(for: .proRes), .availableOnSupportedHardware)
        XCTAssertTrue(hardwareSelection.isEncodableNow)
        XCTAssertEqual(hardwareSelection.executionKind, .hardware)
        XCTAssertFalse(softwareOnlySelection.isEncodableNow)
        XCTAssertEqual(softwareOnlySelection.executionKind, .planned)
        XCTAssertEqual(softwareOnlySelection.support, .planned)
    }

    func testRepresentativeBundledAvailableNowSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "H.261.h261",
            "Theora.ogv",
            "JPEG-LS.avi",
            "QuickTime Video.mov",
            "Flash Video.flv"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    func testRealDeviceBundledTheoraOpusSampleEncodesHEVCWithAACAudio() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Real-device runtime proof requires a physical iPhone or iPad.")
        #endif

        let sampleURL = bundledTestVideosURL().appendingPathComponent("Theora.ogv")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled Theora proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: "real-device-theora-opus-hevc.mp4")
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
        XCTAssertEqual(job.asset.container, .ogg)
        XCTAssertEqual(job.asset.videoTrack?.codec, .theora)
        XCTAssertEqual(sourceAudioCodec, .opus)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .theora, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .aac))
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mp4)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 2)
    }

    func testRealDeviceBundledAMRWBH263SampleEncodesHEVCWithAACAudio() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Real-device runtime proof requires a physical iPhone or iPad.")
        #endif

        let sampleURL = bundledTestVideosURL().appendingPathComponent("AMR-WB H.263.3gp")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled AMR-WB proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: "real-device-amr-wb-h263-hevc.mp4")
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

    func testNextLegacyBundledSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "Microsoft Video 1.avi",
            "ASUS V1.avi",
            "ASUS V2.avi"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    func testScreenAndArchiveBundledSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "Flash Screen Video.flv",
            "Flash Screen Video 2.flv",
            "ZMBV.avi",
            "CLJR.avi",
            "FFV1.avi"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    func testNextIntermediateBundledSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "HuffYUV.avi",
            "DVCPro.mov",
            "DVCPro HD.mov",
            "DV.dv",
            "CineForm.avi",
            "DNxHD.mov",
            "V308.mov",
            "V210.avi",
            "V408.mov",
            "V410.mov",
            "YUV4.mov"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    func testRealVideoAndRoQBundledSamplesEncodeToHEVCMP4() async throws {
        let sampleFilenames = [
            "RealVideo 1.0.rm",
            "RealVideo.rm",
            "RoQ Video.roq"
        ]
        try await assertBundledSamplesEncodeToHEVCMP4(sampleFilenames)
    }

    private func assertBundledSamplesEncodeToHEVCMP4(_ sampleFilenames: [String]) async throws {
        let outputDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: outputDirectoryURL)
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

        let filteredSampleFilenames: [String]
        if let sampleFilter = ProcessInfo.processInfo.environment["TAPTION_SAMPLE_FILTER"],
           sampleFilter.isEmpty == false {
            filteredSampleFilenames = sampleFilenames.filter { $0 == sampleFilter }
            XCTAssertFalse(filteredSampleFilenames.isEmpty, sampleFilter)
        } else {
            filteredSampleFilenames = sampleFilenames
        }
        let expectedDisplaySizes = [
            "H.261.h261": TaptionPixelSize(width: 176, height: 144),
            "Theora.ogv": TaptionPixelSize(width: 320, height: 240),
            "JPEG-LS.avi": TaptionPixelSize(width: 80, height: 80),
            "QuickTime Video.mov": TaptionPixelSize(width: 160, height: 120),
            "Flash Video.flv": TaptionPixelSize(width: 160, height: 120)
        ]

        for filename in filteredSampleFilenames {
            do {
                let sampleURL = bundledTestVideosURL().appendingPathComponent(filename)
                let outputURL = outputDirectoryURL
                    .appendingPathComponent("\(sampleURL.deletingPathExtension().lastPathComponent)-hevc.mp4")

                let job = try await core.prepareSingleAssetHEVCJob(
                    sourceURL: sampleURL,
                    temporaryOutputURL: outputURL,
                    savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
                )
                let result = try await core.encodePreparedJob(job, progress: { _ in })
                let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

                XCTAssertTrue(job.routeSelection.isEncodableNow, filename)
                XCTAssertEqual(result.temporaryOutputURL, outputURL, filename)
                XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), filename)
                XCTAssertEqual(outputAsset.container, .mp4, filename)
                XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc, filename)
                if let expectedDisplaySize = expectedDisplaySizes[filename] {
                    XCTAssertEqual(job.asset.videoTrack?.displaySize, expectedDisplaySize, filename)
                    XCTAssertEqual(outputAsset.videoTrack?.displaySize, expectedDisplaySize, filename)
                }
            } catch {
                XCTFail("\(filename): \(error)")
            }
        }
    }

    func testTestVideoSeederRemovesExistingDocumentsFolderAndCopiesBundledFiles() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("Source", isDirectory: true)
        let documentsURL = rootURL.appendingPathComponent("Documents", isDirectory: true)
        let destinationURL = documentsURL.appendingPathComponent(
            TaptionTestVideoSeeder.documentsFolderName,
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let firstFilename = TaptionTestVideoSeeder.expectedBundledVideoSampleFilenames[0]
        let secondFilename = TaptionTestVideoSeeder.expectedBundledVideoSampleFilenames[1]
        let staleDestinationURL = destinationURL.appendingPathComponent(firstFilename)
        let extraDestinationURL = destinationURL.appendingPathComponent("user-leftover.mov")

        try Data("bundle-first".utf8).write(to: sourceURL.appendingPathComponent(firstFilename))
        try Data("bundle-second".utf8).write(to: sourceURL.appendingPathComponent(secondFilename))
        try Data("stale-existing".utf8).write(to: staleDestinationURL)
        try Data("leftover".utf8).write(to: extraDestinationURL)

        let result = try TaptionTestVideoSeeder.seedSamples(
            sourceURL: sourceURL,
            documentsDirectoryURL: documentsURL,
            fileManager: fileManager
        )

        XCTAssertEqual(result.destinationURL, destinationURL)
        XCTAssertTrue(result.removedExistingFolder)
        XCTAssertEqual(result.copiedFilenames, [firstFilename, secondFilename].sorted())
        XCTAssertEqual(try String(contentsOf: staleDestinationURL), "bundle-first")
        XCTAssertEqual(
            try String(contentsOf: destinationURL.appendingPathComponent(secondFilename)),
            "bundle-second"
        )
        XCTAssertFalse(fileManager.fileExists(atPath: extraDestinationURL.path))
    }

    func testTestVideoSeederCreatesDocumentsFolderWhenMissing() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourceURL = rootURL.appendingPathComponent("Source", isDirectory: true)
        let documentsURL = rootURL.appendingPathComponent("Documents", isDirectory: true)
        let destinationURL = documentsURL.appendingPathComponent(
            TaptionTestVideoSeeder.documentsFolderName,
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        try fileManager.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        let filename = TaptionTestVideoSeeder.expectedBundledVideoSampleFilenames[0]
        let sourceFileURL = sourceURL.appendingPathComponent(filename)
        let destinationFileURL = destinationURL.appendingPathComponent(filename)

        try Data("bundle-current".utf8).write(to: sourceFileURL)

        let result = try TaptionTestVideoSeeder.seedSamples(
            sourceURL: sourceURL,
            documentsDirectoryURL: documentsURL,
            fileManager: fileManager
        )

        XCTAssertEqual(result.destinationURL, destinationURL)
        XCTAssertFalse(result.removedExistingFolder)
        XCTAssertEqual(result.copiedFilenames, [filename])
        XCTAssertEqual(try String(contentsOf: destinationFileURL), "bundle-current")
    }

    func testTestVideoSeederDocumentsSampleFolderURLUsesSharedFolderName() throws {
        let sampleURL = try TaptionTestVideoSeeder.documentsSampleFolderURL()

        XCTAssertEqual(sampleURL.lastPathComponent, TaptionTestVideoSeeder.documentsFolderName)
        XCTAssertTrue(sampleURL.path.contains("/Documents/"))
    }

    func testUniversalVideoCommandPlannerRejectsEveryUnsupportedOutputCodec() {
        for sourceCodec in TaptionCodecRegistry.universalSourceCodecs {
            for outputCodec in SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs {
                let route = TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
                let request = TaptionCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/input-\(sourceCodec.rawValue).mkv"),
                    outputURL: URL(fileURLWithPath: "/tmp/output-\(outputCodec.rawValue).mp4"),
                    route: route,
                    options: .preservingSource(outputCodec: outputCodec, container: .mp4)
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

    func testUniversalVideoCommandPlannerRejectsNonH265OutputRoutes() {
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
                .videoRouteNotPlannable(route)
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

    func testSingleAssetPlanCarriesSourcePreservationRequirementsIntoExecutionAudit() throws {
        let sourceColor = TaptionColorDescription(
            primaries: .bt2020,
            transfer: .pq,
            matrix: .bt2020NonConstantLuminance,
            bitDepth: 10,
            isHDR: true
        )
        let track = TaptionVideoTrackInfo(
            codec: .h264,
            naturalSize: TaptionPixelSize(width: 3840, height: 2160),
            displaySize: TaptionPixelSize(width: 2160, height: 3840),
            nominalFrameRate: TaptionRationalFrameRate(numerator: 60000, denominator: 1001),
            estimatedBitrate: 80_000_000,
            color: sourceColor,
            rotationDegrees: 90
        )
        let asset = TaptionVideoAsset(
            displayName: "portrait-hdr.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            duration: 2,
            videoTrack: track
        )

        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: URL(fileURLWithPath: "/tmp/portrait-hdr.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/portrait-hdr_taption.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )

        XCTAssertEqual(
            plan.sourcePreservationRequirements,
            TaptionSourcePreservationRequirements(asset: asset)
        )
        XCTAssertEqual(plan.outputPolicy.advancedOptions.resizeTo, track.displaySize)
        XCTAssertEqual(plan.outputPolicy.advancedOptions.frameRate, track.nominalFrameRate)
        XCTAssertEqual(plan.outputPolicy.advancedOptions.targetBitrate, track.estimatedBitrate)
        XCTAssertEqual(plan.outputPolicy.advancedOptions.color, sourceColor)
        XCTAssertEqual(plan.outputPolicy.advancedOptions.rotationDegrees, 90)
        XCTAssertNoThrow(try TaptionSourcePreservingExecutionAudit.validate(plan: plan))

        let metadata = TaptionSourcePreservingExecutionAudit.logMetadata(for: plan)
        XCTAssertEqual(metadata["sourcePreserving"], "tracked")
        XCTAssertEqual(metadata["sourcePreservingMissing"], "")
        XCTAssertEqual(metadata["preserveResolution"], "2160x3840")
        XCTAssertEqual(metadata["preserveFrameRate"], "60000/1001")
        XCTAssertEqual(metadata["preserveBitrate"], "80000000")
        XCTAssertEqual(metadata["preserveOrientation"], "90")
        XCTAssertEqual(metadata["preserveColor"], "bt2020/pq/bt2020NonConstantLuminance/hdr:true")
    }

    func testSourcePreservingOutputVerificationAcceptsMatchingOutputMetadata() throws {
        let sourceColor = TaptionColorDescription(
            primaries: .bt709,
            transfer: .bt709,
            matrix: .bt709,
            bitDepth: 8,
            isHDR: false
        )
        let sourceAsset = TaptionVideoAsset(
            displayName: "source.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            duration: 4,
            videoTrack: TaptionVideoTrackInfo(
                codec: .h264,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30000, denominator: 1001),
                estimatedBitrate: 12_000_000,
                color: sourceColor,
                rotationDegrees: 0
            ),
            audioTracks: [
                TaptionAudioTrackInfo(codec: .aac, channelCount: 2, sampleRate: 48_000)
            ]
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: sourceAsset,
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )
        let outputAsset = TaptionVideoAsset(
            displayName: "output.mp4",
            location: TaptionVideoAssetLocation(kind: .temporary),
            container: .mp4,
            duration: 4.03,
            videoTrack: TaptionVideoTrackInfo(
                codec: .hevc,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 2997, denominator: 100),
                color: sourceColor,
                rotationDegrees: 0
            ),
            audioTracks: [
                TaptionAudioTrackInfo(codec: .aac, channelCount: 2, sampleRate: 48_000)
            ]
        )

        let report = try TaptionSourcePreservingExecutionAudit.verifyOutput(
            plan: plan,
            outputAsset: outputAsset
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertEqual(report.metadata["sourcePreservingOutput"], "checked")
        XCTAssertEqual(report.metadata["actualResolution"], "1920x1080")
        XCTAssertEqual(report.metadata["actualAudioTracks"], "1")
    }

    func testSourcePreservingOutputVerificationRejectsMismatchedOutputMetadata() {
        let sourceAsset = TaptionVideoAsset(
            displayName: "source.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            duration: 10,
            videoTrack: TaptionVideoTrackInfo(
                codec: .h264,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30),
                color: TaptionColorDescription(primaries: .bt709, transfer: .bt709, matrix: .bt709),
                rotationDegrees: 0
            ),
            audioTracks: [
                TaptionAudioTrackInfo(codec: .aac, channelCount: 2, sampleRate: 48_000)
            ]
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: sourceAsset,
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
        )
        let outputAsset = TaptionVideoAsset(
            displayName: "output.mp4",
            location: TaptionVideoAssetLocation(kind: .temporary),
            container: .mp4,
            duration: 7,
            videoTrack: TaptionVideoTrackInfo(
                codec: .hevc,
                naturalSize: TaptionPixelSize(width: 1280, height: 720),
                displaySize: TaptionPixelSize(width: 1280, height: 720),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 24),
                color: TaptionColorDescription(primaries: .bt2020, transfer: .bt709, matrix: .bt709),
                rotationDegrees: 0
            ),
            audioTracks: []
        )

        XCTAssertThrowsError(try TaptionSourcePreservingExecutionAudit.verifyOutput(
            plan: plan,
            outputAsset: outputAsset
        )) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains("resolution expected 1920x1080 but got 1280x720"))
            XCTAssertTrue(message.contains("frame rate expected 30/1 but got 24/1"))
            XCTAssertTrue(message.contains("duration expected 10.000s but got 7.000s"))
            XCTAssertTrue(message.contains("audio track was missing"))
        }
    }

    func testSourcePreservingVisualQualityComparatorAcceptsSimilarSamples() {
        let sourceSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.42,
            averageGreen: 0.50,
            averageBlue: 0.44,
            averageLuma: 0.48,
            lumaStandardDeviation: 0.18,
            nonBlackRatio: 0.96
        )
        let outputSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.40,
            averageGreen: 0.49,
            averageBlue: 0.43,
            averageLuma: 0.47,
            lumaStandardDeviation: 0.16,
            nonBlackRatio: 0.95
        )

        let report = TaptionSourcePreservingVisualQualityComparator.verify(
            sourceSample: sourceSample,
            outputSample: outputSample
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertEqual(report.metadata["visualQuality"], "checked")
        XCTAssertNotNil(report.metadata["visualLumaDelta"])
        XCTAssertNotNil(report.metadata["visualColorDelta"])
    }

    func testSourcePreservingVisualQualityComparatorRejectsCollapsedOutput() {
        let sourceSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.62,
            averageGreen: 0.50,
            averageBlue: 0.31,
            averageLuma: 0.52,
            lumaStandardDeviation: 0.22,
            nonBlackRatio: 0.90
        )
        let outputSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.01,
            averageGreen: 0.01,
            averageBlue: 0.01,
            averageLuma: 0.01,
            lumaStandardDeviation: 0.001,
            nonBlackRatio: 0.0
        )

        let report = TaptionSourcePreservingVisualQualityComparator.verify(
            sourceSample: sourceSample,
            outputSample: outputSample
        )

        XCTAssertFalse(report.isPassing)
        XCTAssertTrue(report.failures.contains("visual sample lost source contrast and appears flat"))
        XCTAssertTrue(report.failures.contains("visual sample collapsed to near-black output"))
    }

    func testSourcePreservingVisualQualityComparatorPassesWithoutSourceSampleButWarns() {
        let outputSample = TaptionVisualQualitySample(
            width: 96,
            height: 54,
            averageRed: 0.30,
            averageGreen: 0.35,
            averageBlue: 0.40,
            averageLuma: 0.34,
            lumaStandardDeviation: 0.08,
            nonBlackRatio: 0.80
        )

        let report = TaptionSourcePreservingVisualQualityComparator.verify(
            sourceSample: nil,
            outputSample: outputSample
        )

        XCTAssertTrue(report.isPassing)
        XCTAssertEqual(report.metadata["sourceVisualSample"], "unavailable")
        XCTAssertTrue(report.warnings.contains("Source visual sample was unavailable; output visual decodability was verified only."))
    }

    func testSourcePreservingExecutionAuditRejectsMissingKnownSourceFields() {
        let plan = TaptionEncodingPlan(
            input: TaptionEncodingInput(kind: .singleAsset),
            outputPolicy: TaptionVideoOutputPolicy(
                videoCodec: .hevc,
                container: .mp4,
                qualityPolicy: .preserveSourceVisuals,
                advancedOptions: .preserveSource
            ),
            codecRoute: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc),
            codecExecutionKind: .hardware,
            sourcePreservationRequirements: TaptionSourcePreservationRequirements(
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                frameRate: TaptionRationalFrameRate(numerator: 30),
                targetBitrate: 12_000_000,
                color: TaptionColorDescription(primaries: .bt709, transfer: .bt709, matrix: .bt709),
                rotationDegrees: 0
            ),
            sourceURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/output.mp4")
        )

        XCTAssertThrowsError(try TaptionSourcePreservingExecutionAudit.validate(plan: plan)) { error in
            XCTAssertEqual(
                error as? TaptionSourcePreservingVerificationError,
                .failed("Source-preserving output plan is incomplete: resolution, frame rate, bitrate, color metadata, orientation.")
            )
        }
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
            videoCodec: .hevc,
            container: .mov,
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
        XCTAssertTrue(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .pcm, container: .mov).isImplementedNow)
        XCTAssertTrue(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .alac, container: .mov).isImplementedNow)
        XCTAssertFalse(TaptionOutputSelection(videoCodec: .h264, container: .mp4).isImplementedNow)
        XCTAssertFalse(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .pcm, container: .mp4).isImplementedNow)
        XCTAssertFalse(TaptionOutputSelection(videoCodec: .hevc, audioCodec: .alac, container: .mp4).isImplementedNow)
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

    func testEncodingOptimizationProfileSliderMappingAndSettingsPersistence() {
        XCTAssertEqual(TaptionEncodingOptimizationProfile.fromSliderValue(-1), .batterySaver)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.fromSliderValue(1), .balanced)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.fromSliderValue(2), .performance)
        XCTAssertEqual(TaptionEncodingOptimizationProfile.fromDebugString("max-performance"), .performance)

        let suiteName = "BatteryEncodingSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = BatteryEncodingSettings(
            batteryLimitPercent: 45,
            powerConnectedOnly: true,
            optimizationProfile: .performance
        )
        settings.save(defaults: defaults)

        XCTAssertEqual(BatteryEncodingSettings.load(defaults: defaults), settings)
    }

    func testBatterySaverOutputPolicyCapsAutomaticSourceResolutionFrameRateAndBitrate() {
        let asset = makeAsset(
            sourceCodec: .h264,
            displaySize: TaptionPixelSize(width: 3840, height: 2160),
            frameRate: TaptionRationalFrameRate(numerator: 60)
        )
        let balancedPolicy = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            optimizationProfile: .balanced
        ).outputPolicy(for: asset)
        let batteryPolicy = TaptionOutputSelection(
            videoCodec: .hevc,
            container: .mp4,
            optimizationProfile: .batterySaver
        ).outputPolicy(for: asset)

        XCTAssertNil(balancedPolicy.advancedOptions.resizeTo)
        XCTAssertNil(balancedPolicy.advancedOptions.frameRate)
        XCTAssertEqual(batteryPolicy.advancedOptions.resizeTo, TaptionPixelSize(width: 1920, height: 1080))
        XCTAssertEqual(batteryPolicy.advancedOptions.frameRate, TaptionRationalFrameRate(numerator: 30))
        XCTAssertEqual(batteryPolicy.advancedOptions.optimizationProfile, .batterySaver)
        XCTAssertNotNil(balancedPolicy.advancedOptions.targetBitrate)
        XCTAssertNotNil(batteryPolicy.advancedOptions.targetBitrate)
        XCTAssertLessThan(
            batteryPolicy.advancedOptions.targetBitrate ?? Int.max,
            balancedPolicy.advancedOptions.targetBitrate ?? 0
        )
    }

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
    func testPreviewOrientationControllerAllowsLandscapeOnlyDuringPreview() {
        let controller = AppOrientationController.shared

        controller.restorePortrait(requestGeometryUpdate: false)
        XCTAssertEqual(controller.supportedOrientations, .portrait)

        controller.activatePreviewOrientations(requestGeometryUpdate: false)
        XCTAssertTrue(controller.supportedOrientations.contains(.portrait))
        XCTAssertTrue(controller.supportedOrientations.contains(.landscapeLeft))
        XCTAssertTrue(controller.supportedOrientations.contains(.landscapeRight))

        controller.restorePortrait(requestGeometryUpdate: false)
        XCTAssertEqual(controller.supportedOrientations, .portrait)
    }

    func testQueuePreviewPlaybackMathFormatsAndClampsControls() {
        XCTAssertEqual(QueuePreviewPlaybackMath.formattedSeconds(nil), "--:--")
        XCTAssertEqual(QueuePreviewPlaybackMath.formattedSeconds(65), "01:05")
        XCTAssertEqual(QueuePreviewPlaybackMath.formattedSeconds(3661), "1:01:01")

        XCTAssertEqual(QueuePreviewPlaybackMath.clampedPosition(-0.4), 0)
        XCTAssertEqual(QueuePreviewPlaybackMath.clampedPosition(1.4), 1)
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

    func testQueuePreviewBackgroundTapHidesControlsOnlyDuringPlayback() {
        XCTAssertTrue(
            QueuePreviewControlsVisibilityPolicy.shouldHideOnBackgroundTap(
                isLoading: false,
                hasPlaybackError: false,
                areControlsVisible: true,
                isPlaying: true,
                isScrubbing: false,
                isDragging: false
            )
        )
        XCTAssertFalse(
            QueuePreviewControlsVisibilityPolicy.shouldHideOnBackgroundTap(
                isLoading: false,
                hasPlaybackError: false,
                areControlsVisible: false,
                isPlaying: true,
                isScrubbing: false,
                isDragging: false
            )
        )
        XCTAssertFalse(
            QueuePreviewControlsVisibilityPolicy.shouldHideOnBackgroundTap(
                isLoading: false,
                hasPlaybackError: false,
                areControlsVisible: true,
                isPlaying: false,
                isScrubbing: false,
                isDragging: false
            )
        )
        XCTAssertFalse(
            QueuePreviewControlsVisibilityPolicy.shouldHideOnBackgroundTap(
                isLoading: true,
                hasPlaybackError: false,
                areControlsVisible: true,
                isPlaying: true,
                isScrubbing: false,
                isDragging: false
            )
        )
        XCTAssertFalse(
            QueuePreviewControlsVisibilityPolicy.shouldHideOnBackgroundTap(
                isLoading: false,
                hasPlaybackError: true,
                areControlsVisible: true,
                isPlaying: true,
                isScrubbing: false,
                isDragging: false
            )
        )
        XCTAssertFalse(
            QueuePreviewControlsVisibilityPolicy.shouldHideOnBackgroundTap(
                isLoading: false,
                hasPlaybackError: false,
                areControlsVisible: true,
                isPlaying: true,
                isScrubbing: true,
                isDragging: false
            )
        )
        XCTAssertFalse(
            QueuePreviewControlsVisibilityPolicy.shouldHideOnBackgroundTap(
                isLoading: false,
                hasPlaybackError: false,
                areControlsVisible: true,
                isPlaying: true,
                isScrubbing: false,
                isDragging: true
            )
        )
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
            previewViewText.range(of: "private struct PreviewBadgeFlowLayout")
        )
        let previewText = String(previewViewText[previewStart.lowerBound..<previewEnd.lowerBound])

        XCTAssertTrue(previewText.contains("PiPVideoView("))
        XCTAssertTrue(previewText.contains("controller: $pipController"))
        XCTAssertTrue(previewText.contains("startsAutomaticallyFromInline: true"))
        XCTAssertTrue(previewText.contains("managesAudioSession: false"))
        XCTAssertTrue(previewText.contains("Button(action: togglePictureInPicture)"))
        XCTAssertTrue(previewText.contains("startDebugAutoPictureInPictureIfRequested()"))
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
        XCTAssertTrue(previewViewText.contains("private final class QueuePreviewSystemVolumeController"))
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

        XCTAssertTrue(homeViewText.contains("@State private var miniPlayerPreview: QueueVideoPreview?"))
        XCTAssertTrue(homeViewText.contains("@State private var autoStartMiniPlayerPiPPreviewID: String?"))
        XCTAssertTrue(homeViewText.contains("QueueMiniPlayerView("))
        XCTAssertTrue(homeViewText.contains("onMinimize:"))
        XCTAssertTrue(homeViewText.contains("onPictureInPictureHome:"))
        XCTAssertTrue(previewViewText.contains("minimizePreview()"))
        XCTAssertTrue(previewViewText.contains("Queue preview minimized to floating player"))
        XCTAssertTrue(previewViewText.contains("Queue preview Picture in Picture home requested"))
        XCTAssertTrue(previewViewText.contains("TAPTION_AUTO_MINIMIZE_PREVIEW"))
        XCTAssertTrue(previewViewText.contains("Debug auto mini player requested"))
        XCTAssertTrue(previewViewText.contains("Button(action: onExpand)"))
        XCTAssertTrue(previewViewText.contains("Button(action: togglePictureInPicture)"))
        XCTAssertTrue(previewViewText.contains("Queue mini player PiP requested"))
        XCTAssertTrue(previewViewText.contains("Queue mini player PiP exit requested"))
        XCTAssertTrue(previewViewText.contains("Queue mini player PiP ignored because controller is unavailable"))
        XCTAssertTrue(previewViewText.contains("Queue mini player auto PiP requested"))
        XCTAssertTrue(previewViewText.contains("Queue mini player auto PiP state checked"))
        XCTAssertTrue(homeViewText.contains("autoStartPictureInPicture: autoStartMiniPlayerPiPPreviewID == preview.id"))
        XCTAssertTrue(previewViewText.contains(".onChange(of: preview.id)"))
        XCTAssertTrue(previewViewText.contains("keepControlsVisibleForPreviewSwitch()"))
        XCTAssertFalse(homeViewText.contains(".id(preview.id)"))
        XCTAssertTrue(homeViewText.contains("isPresented: Binding<Bool>"))
        XCTAssertTrue(homeViewText.contains("get: { viewModel.activePreview != nil }"))
        XCTAssertTrue(homeViewText.contains("queueVideoPreviewFullScreenCoverContent"))
        XCTAssertFalse(homeViewText.contains("item: Binding<QueueVideoPreview?>"))
        XCTAssertTrue(homeViewText.contains("viewModel.restorePreview(preview)"))
        XCTAssertTrue(previewViewText.contains("queueMiniPlayer"))
        XCTAssertTrue(homeViewText.contains("let isFullScreenVideoPlaybackActive = viewModel.activePreview != nil"))
        XCTAssertTrue(homeViewText.contains("showsPlaybackActions: !isFullScreenVideoPlaybackActive"))
        XCTAssertTrue(homeViewText.contains("showsWorkAction: showsPlaybackActions"))
        XCTAssertTrue(homeViewText.contains("showsWatchAdAction: showsPlaybackActions"))
        XCTAssertTrue(previewViewText.contains("beginVideoPlaybackAdSuppressionIfNeeded()"))
        XCTAssertTrue(previewViewText.contains("endVideoPlaybackAdSuppressionIfNeeded()"))
        XCTAssertTrue(viewModelText.contains("func restorePreview(_ preview: QueueVideoPreview)"))
        XCTAssertTrue(progressViewText.contains("var showsWorkAction: Bool = true"))
        XCTAssertTrue(progressViewText.contains("var showsWatchAdAction: Bool = true"))
        XCTAssertTrue(progressViewText.contains("showsWorkAction\n            && (resolvedCanStartEncoding"))
        XCTAssertTrue(progressViewText.contains("if showsWatchAdAction {\n                        watchAdButton"))
    }

    func testFileAndFolderButtonsUseSystemPickersWithFolderSelection() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let loadedFilesURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/LoadedFilesPanelView.swift")
        let sourceActionBarURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/SourceActionBar.swift")
        let stateURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeScreenState.swift")
        let projectURL = rootURL.appendingPathComponent("TaptionEncoder.xcodeproj/project.pbxproj")
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
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
        XCTAssertTrue(homeViewText.contains("private enum HomeSystemDocumentPickerMode: String"))
        XCTAssertTrue(homeViewText.contains("case files"))
        XCTAssertTrue(homeViewText.contains("case folder"))
        XCTAssertTrue(homeViewText.contains("import UniformTypeIdentifiers"))
        XCTAssertFalse(homeViewText.contains("@State private var pendingImportPicker"))
        XCTAssertTrue(sourceBarText.contains("onFiles: openFilesImportBrowser"))
        XCTAssertTrue(sourceBarText.contains("onFolder: openFolderImportBrowser"))
        XCTAssertFalse(homeViewText.contains("requestImportBrowserLocationAccess(for:"))
        XCTAssertFalse(homeViewText.contains("requestStartupImportBrowserAccessIfNeeded()"))
        XCTAssertTrue(homeViewText.contains("activeSystemDocumentPicker = .files"))
        XCTAssertTrue(homeViewText.contains("activeSystemDocumentPicker = .folder"))
        XCTAssertFalse(homeViewText.contains(".fileImporter("))
        XCTAssertTrue(homeViewText.contains("HomeSystemDocumentPickerPresenter("))
        XCTAssertTrue(homeViewText.contains("UIDocumentPickerViewController("))
        XCTAssertTrue(homeViewText.contains("forOpeningContentTypes: mode.allowedContentTypes"))
        XCTAssertTrue(homeViewText.contains("return ImportableVideoTypes.all"))
        XCTAssertTrue(homeViewText.contains("return [.folder]"))
        XCTAssertTrue(homeViewText.contains("picker.allowsMultipleSelection = mode.allowsMultipleSelection"))
        XCTAssertTrue(homeViewText.contains("return true"))
        XCTAssertTrue(homeViewText.contains("return false"))
        XCTAssertTrue(homeViewText.contains("UIDocumentPickerDelegate"))
        XCTAssertTrue(homeViewText.contains("documentPicker("))
        XCTAssertTrue(homeViewText.contains("documentPickerWasCancelled"))
        XCTAssertTrue(homeViewText.contains("handleSystemDocumentPickerResult"))
        XCTAssertTrue(homeViewText.contains("handleFilePickerResult"))
        XCTAssertTrue(homeViewText.contains("handleFolderPickerResult"))
        XCTAssertTrue(homeViewText.contains("viewModel.handleFolderPickerSelection(urls: selectedURLs)"))
        XCTAssertTrue(homeViewText.contains("viewModel.handleFolderPickerSelection(urls: [folderURL])"))
        XCTAssertFalse(sourceBarText.contains("onSamples"))
        XCTAssertFalse(sourceBarText.contains("openSampleLibrary()"))
        XCTAssertFalse(sourceBarText.contains("activeSystemDocumentPicker = .files"))
        XCTAssertFalse(sourceBarText.contains("activeSystemDocumentPicker = .folder"))
        XCTAssertFalse(sourceActionBarText.contains("var onSamples"))
        XCTAssertFalse(sourceActionBarText.contains("title: \"Sample\""))
        XCTAssertTrue(sourceActionBarText.contains("title: \"Reset\""))
        let resetButtonStart = try XCTUnwrap(sourceActionBarText.range(of: "title: \"Reset\""))
        let resetButtonText = String(sourceActionBarText[resetButtonStart.lowerBound...])
        XCTAssertTrue(resetButtonText.contains("isProminent: true"))
        XCTAssertTrue(homeViewText.contains("HomeImportBrowserView("))
        XCTAssertFalse(homeViewText.contains("onRequestLocationAccess:"))
        XCTAssertFalse(homeViewText.contains("requestImportBrowserLocationAccess(for:"))
        XCTAssertTrue(homeViewText.contains("handleFolderPickerResult"))
        XCTAssertTrue(homeViewText.contains("handleImportBrowserDismiss"))
        XCTAssertFalse(homeViewText.contains("presentPendingImportPickerIfNeeded"))
        XCTAssertFalse(homeViewText.contains("openImportBrowserLocation"))
        XCTAssertFalse(homeViewText.contains("VideoDocumentPicker("))
        XCTAssertFalse(homeViewText.contains("PendingSaveExportPicker("))
        XCTAssertFalse(homeViewText.contains("recoverFolderAccessForPendingSave(url:"))
        let exitButtonStart = try XCTUnwrap(homeViewText.range(of: "private func exitButton"))
        let exitButtonEnd = try XCTUnwrap(homeViewText[exitButtonStart.lowerBound...].range(of: "\n    private func outputSelector"))
        let exitButtonText = String(homeViewText[exitButtonStart.lowerBound..<exitButtonEnd.lowerBound])
        XCTAssertFalse(exitButtonText.contains(".background(Color(red: 1.0, green: 0.30, blue: 0.34).opacity(0.16))"))
        XCTAssertTrue(exitButtonText.contains(".foregroundStyle(.white)"))
        XCTAssertTrue(exitButtonText.contains(".background(Color(red: 0.96, green: 0.18, blue: 0.22))"))
        let homeContentStart = try XCTUnwrap(homeViewText.range(of: "private func homeContent("))
        let homeContentEnd = try XCTUnwrap(homeViewText[homeContentStart.lowerBound...].range(of: "\n    private func sourceControls"))
        let homeContentText = String(homeViewText[homeContentStart.lowerBound..<homeContentEnd.lowerBound])
        let footerExitRange = try XCTUnwrap(homeContentText.range(of: "exitButton(metrics: metrics)"))
        let footerBannerRange = try XCTUnwrap(
            homeContentText[footerExitRange.upperBound...].range(of: "AdMobBannerSlotView(")
        )
        XCTAssertLessThan(footerExitRange.lowerBound, footerBannerRange.lowerBound)
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
            .av1, .vp9, .vp8, .mpeg1, .mpeg2, .mpeg4Visual, .h263, .h261,
            .flashVideo, .microsoftMPEG4V2, .microsoftMPEG4V3, .motionJPEG,
            .jpeg2000, .jpegLS, .losslessJPEG, .animation, .cinepak,
            .sorensonVideo, .sorensonVideo3, .quickTimeVideo, .theora,
            .realVideo1, .realVideo, .roqVideo, .wmv,
            .microsoftVideo1, .asusV1, .asusV2, .flashScreenVideo,
            .flashScreenVideo2, .zmbv, .cljr, .snow, .ffv1, .huffYUV,
            .utVideo, .magicYUV, .dvcPro, .dvcProHD, .dv, .cineForm, .dnxhd,
            .pngVideo, .r10k, .v308, .v210, .r210, .v408, .v410,
            .microsoftRLE, .quickTimeGraphics, .yuv4, .rawVideo, .h264, .hevc
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
        XCTAssertTrue(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.contains(.y41p))
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
        XCTAssertTrue(
            TaptionLaunchSupportCatalog.plannedInputVideoNote.contains("roadmap input codecs")
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

        for sourceCodec in [TaptionAudioCodec.opus, .amr] {
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

    func testBundledTheoraOpusSampleEncodesHEVCMOVWithPCMAudio() async throws {
        let sampleURL = bundledTestVideosURL().appendingPathComponent("Theora.ogv")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled Theora proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: "theora-opus-hevc-pcm.mov")
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
            audioCodec: .pcm,
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
        XCTAssertEqual(sourceAudioCodec, .opus)
        XCTAssertEqual(job.plan.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(job.plan.outputPolicy.audioCodec, .pcm)
        XCTAssertEqual(job.plan.outputPolicy.container, .mov)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .theora, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .pcm))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertEqual(job.plan.audioPlan?.readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mov)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, .pcm)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 2)
        XCTAssertFalse(outputAsset.audioTracks.isEmpty)
    }

    func testBundledTheoraOpusSampleEncodesHEVCMOVWithALACAudio() async throws {
        let sampleURL = bundledTestVideosURL().appendingPathComponent("Theora.ogv")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            XCTFail("Missing bundled Theora proof sample at \(sampleURL.path)")
            return
        }

        let outputURL = temporaryTestURL(fileName: "theora-opus-hevc-alac.mov")
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
            audioCodec: .alac,
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
        XCTAssertEqual(sourceAudioCodec, .opus)
        XCTAssertEqual(job.plan.outputPolicy.videoCodec, .hevc)
        XCTAssertEqual(job.plan.outputPolicy.audioCodec, .alac)
        XCTAssertEqual(job.plan.outputPolicy.container, .mov)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .theora, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .opus, outputCodec: .alac))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .softwareBackendExecutable)
        XCTAssertEqual(job.plan.audioPlan?.readiness.commandBackend, .softwareVLCDecoder)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .softwareVLCDecoder)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(outputAsset.container, .mov)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, .alac)
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

    private func assertBundledFlashVideoMP3SampleEncodesHEVCMOV(
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

    private func assertBundledAMRWBH263SampleEncodesHEVCMOV(
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

    func testLocalRealVC1RawSampleDocumentsPlannedFFmpegBackendAfterVLCNoFrameBlock() async throws {
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
        XCTAssertEqual(job.routeSelection.support, .planned)
        XCTAssertFalse(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.executionKind, .planned)
        XCTAssertEqual(job.routeSelection.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(job.routeSelection.encodeBackend, .appleVideoToolbox)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path) == false)

        let plannedDescriptor = TaptionCodecTranscodingRegistry.live
            .plannedDescriptors(for: job.routeSelection.route)
            .first
        XCTAssertEqual(plannedDescriptor?.backend, .ffmpegFamily)
        XCTAssertTrue(TaptionCodecTranscodingRegistry.live.descriptors(for: job.routeSelection.route).isEmpty)
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

    func testLocalRealY41PSampleDocumentsPlannedFFmpegBackendAfterVLCUnsupportedBlock() async throws {
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
        XCTAssertEqual(job.routeSelection.support, .planned)
        XCTAssertFalse(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.routeSelection.executionKind, .planned)
        XCTAssertEqual(job.routeSelection.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(job.routeSelection.encodeBackend, .appleVideoToolbox)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path) == false)

        let plannedDescriptor = TaptionCodecTranscodingRegistry.live
            .plannedDescriptors(for: job.routeSelection.route)
            .first
        XCTAssertEqual(plannedDescriptor?.backend, .ffmpegFamily)
        XCTAssertTrue(TaptionCodecTranscodingRegistry.live.descriptors(for: job.routeSelection.route).isEmpty)
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
        try requireLocalRealSampleProofs()

        let samplePath = ProcessInfo.processInfo.environment["TAPTION_XHE_AAC_SAMPLE_PATH"]
            ?? "/Users/u_mo_c/Documents/taption_encoder/Samples/Downloaded/internet_supported_missing_2026-07-06/sample_videos/xhe_aac_hevc_video.mp4"
        let sampleURL = URL(fileURLWithPath: samplePath)
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local xHE-AAC real-sample proof requires \(sampleURL.path).")
        }

        let outputURL = temporaryTestURL(fileName: "xhe-aac-hevc-actual-app-hevc.mp4")
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
        XCTAssertEqual(job.asset.container, .mp4)
        XCTAssertEqual(job.asset.videoTrack?.codec, .hevc)
        XCTAssertEqual(job.asset.audioTracks.first?.codec, .xheAAC)
        XCTAssertEqual(job.asset.audioTracks.first?.sampleRate ?? 0, 48_000, accuracy: 1)
        XCTAssertEqual(job.asset.audioTracks.first?.channelCount, 2)
        XCTAssertEqual(job.routeSelection.route, TaptionCodecRoute(sourceCodec: .hevc, outputCodec: .hevc))
        XCTAssertTrue(job.routeSelection.isEncodableNow)
        XCTAssertEqual(job.plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: .xheAAC, outputCodec: .aac))
        XCTAssertEqual(job.plan.audioPlan?.routeSelection.support, .nativeTranscode)
        XCTAssertEqual(job.plan.audioPlan?.readiness.readiness, .nativeTranscodeInCurrentBuild)
        XCTAssertTrue(job.plan.audioPlan?.isRunnableInCurrentBuild ?? false)
        XCTAssertNil(job.plan.audioPlan?.commandPlan)
        XCTAssertEqual(job.plan.audioPlan?.options.sampleRate, 44_100)
        XCTAssertEqual(job.plan.sourcePreservationRequirements?.audioSampleRate, 44_100)

        let result = try await core.encodePreparedJob(job, progress: { _ in })
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: result.temporaryOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.temporaryOutputURL.path))
        XCTAssertEqual(result.usedBackend, .appleVideoToolbox)
        XCTAssertEqual(result.usedMode, .hardware)
        XCTAssertEqual(outputAsset.container, .mp4)
        XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc)
        XCTAssertEqual(outputAsset.audioTracks.first?.codec, .aac)
        XCTAssertEqual(outputAsset.audioTracks.first?.sampleRate ?? 0, 44_100, accuracy: 1)
        XCTAssertEqual(outputAsset.audioTracks.first?.channelCount, 2)
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
            sourceCodec: .jpeg,
            routeSelection: selectRoute(
                sourceCodec: .jpeg,
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
        XCTAssertEqual(implemented.outputSummary, "H.265 + AAC / MP4")
        XCTAssertTrue(implemented.isRouteEncodable, "\(implemented)")
        XCTAssertTrue(implemented.detail.contains("software fallback"), implemented.detail)

        XCTAssertEqual(planned.title, "Path SW Plan Ready")
        XCTAssertEqual(planned.outputSummary, "H.265 + AAC / MP4")
        XCTAssertFalse(planned.isRouteEncodable)
        XCTAssertTrue(planned.detail.contains("FFmpeg-family backend command can be planned"))

        XCTAssertEqual(unsupported.title, "Path Unsupported")
        XCTAssertEqual(unsupported.outputSummary, "Apple ProRes RAW + AAC / MKV")
        XCTAssertFalse(unsupported.isRouteEncodable)
        XCTAssertTrue(unsupported.detail.contains("Apple ProRes RAW / MKV output is not in the current codec roadmap"))
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

        let commandOnlyItem = TaptionVideoCodecExecutionReadinessReporter.item(
            for: TaptionCodecRoute(sourceCodec: .jpeg, outputCodec: .hevc),
            outputContainer: .mp4
        )
        XCTAssertEqual(commandOnlyItem.readiness, .commandPlanOnly)
        XCTAssertFalse(commandOnlyItem.isRunnableInCurrentBuild)
        XCTAssertTrue(commandOnlyItem.hasCommandPlan)
        XCTAssertEqual(commandOnlyItem.commandBackend, .ffmpegFamily)

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
            for: TaptionCodecRoute(sourceCodec: .jpeg, outputCodec: .hevc),
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
        XCTAssertFalse(decoded.launchInputReadinessCatalog?.executableNowVideoCodecs.contains(.vc1) == true)
        XCTAssertTrue(decoded.launchInputReadinessCatalog?.plannedVideoCodecs.contains(.vc1) == true)
        XCTAssertFalse(decoded.launchInputReadinessCatalog?.executableNowVideoCodecs.contains(.y41p) == true)
        XCTAssertTrue(decoded.launchInputReadinessCatalog?.plannedVideoCodecs.contains(.y41p) == true)
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
        XCTAssertNil(
            SW_SoftwareCodecBackendRegistry.currentExecutableVideoDecodeBackend(for: .vc1)
        )
        XCTAssertEqual(
            SW_SoftwareCodecBackendRegistry.preferredVideoDecodeBackend(for: .y41p),
            .ffmpegFamily
        )
        XCTAssertNil(
            SW_SoftwareCodecBackendRegistry.currentExecutableVideoDecodeBackend(for: .y41p)
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
        XCTAssertEqual(review.statusDate, "2026-07-07")
        XCTAssertFalse(review.approvedForExecution)
        XCTAssertTrue(review.satisfiedGates.isEmpty)
        XCTAssertEqual(
            Set(review.openGates),
            Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
        )
        XCTAssertTrue(review.reviewedSourceURLs.contains("https://www.ffmpeg.org/legal.html"))
        XCTAssertTrue(review.reviewedSourceURLs.contains("https://developer.apple.com/app-store/review/guidelines/"))
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

    func testEncoderServiceRunsPreparedSoftwareCommandPlanWhenBroadBackendIsReady() async throws {
        let outputURL = temporaryTestURL(fileName: "jpeg-to-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: makeAsset(sourceCodec: .jpeg),
            sourceURL: URL(fileURLWithPath: "/tmp/jpeg-source.mp4"),
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
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
        let outputVerifier = RecordingSourcePreservingOutputVerifier()
        let service = AVFoundationHEVCEncoderService(
            softwareExecutor: executor,
            outputVerifier: outputVerifier
        )
        var progressStages: [TaptionEncodingStage] = []

        let result = try await service.encode(plan: plan) { progress in
            progressStages.append(progress.stage)
        }

        XCTAssertEqual(plan.codecRoute, TaptionCodecRoute(sourceCodec: .jpeg, outputCodec: .hevc))
        XCTAssertEqual(plan.codecExecutionKind, .planned)
        XCTAssertNotNil(plan.videoCommandPlan)
        XCTAssertEqual(result.temporaryOutputURL, outputURL)
        XCTAssertEqual(result.finalOutputURL?.lastPathComponent, "jpeg-source_taption.mp4")
        XCTAssertEqual(result.usedBackend, .ffmpegFamily)
        XCTAssertEqual(result.usedMode, .software)
        XCTAssertEqual(progressStages, [.preparing, .encoding, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(outputVerifier.calls, [
            RecordingSourcePreservingOutputVerifier.Call(planID: plan.id, outputURL: outputURL)
        ])

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testEncoderServiceFailsWhenSourcePreservingOutputVerificationFails() async throws {
        let outputURL = temporaryTestURL(fileName: "jpeg-to-hevc-verification-fails.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: makeAsset(sourceCodec: .jpeg),
            sourceURL: URL(fileURLWithPath: "/tmp/jpeg-source.mp4"),
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
            savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
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
        let outputURL = temporaryTestURL(fileName: "silent-jpeg-to-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let silentAsset = TaptionVideoAsset(
            displayName: "silent-jpeg.mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .jpeg,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            ),
            audioTracks: []
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: silentAsset,
            sourceURL: URL(fileURLWithPath: "/tmp/silent-jpeg-source.mp4"),
            temporaryOutputURL: outputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
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
        let service = AVFoundationHEVCEncoderService(
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
        let outputVerifier = RecordingSourcePreservingOutputVerifier()
        let service = AVFoundationHEVCEncoderService(
            registry: registry,
            softwareExecutor: executor,
            outputVerifier: outputVerifier
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
        XCTAssertEqual(outputVerifier.calls, [
            RecordingSourcePreservingOutputVerifier.Call(planID: plan.id, outputURL: outputURL)
        ])

        try? FileManager.default.removeItem(at: outputURL)
    }

    func testFFmpegCommandExecutorSurfacesRunnerFailureWithStderrTail() async throws {
        let commandPlan = try makeH261ToHEVCCommandPlan()
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
        XCTAssertFalse(backend.canWriteContainer(.avi))
        XCTAssertFalse(backend.canWriteContainer(.webm))
    }

    @MainActor
    func testPendingSaveConflictSavesUniqueFileWithoutSystemPicker() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = directoryURL.appendingPathComponent("clip_taption.mp4")
        let uniqueURL = directoryURL.appendingPathComponent("clip_taption 2.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)
        try Data("existing output".utf8).write(to: finalURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            saveDestinationWasChosen: true
        )
        try await store.savePendingState(state)
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForCompletedSave(in: viewModel)

        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "existing output")
        XCTAssertEqual(try String(contentsOf: uniqueURL, encoding: .utf8), "new output")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(
            viewModel.state.detail,
            expectedCompletedSaveDetail(
                url: uniqueURL,
                fileByteCount: Data("new output".utf8).count
            )
        )
        XCTAssertEqual(viewModel.savedFolderPrompt?.title, "Open Saved Folder?")
        XCTAssertEqual(viewModel.savedFolderPrompt?.message, "Open the folder containing clip_taption 2.mp4?")
        XCTAssertEqual(viewModel.savedFolderPrompt?.fileName, uniqueURL.lastPathComponent)
        XCTAssertEqual(viewModel.savedFolderPrompt?.folderURL.standardizedFileURL, directoryURL.standardizedFileURL)

        let states = try await store.loadPendingStates()
        XCTAssertTrue(states.isEmpty)
    }

    @MainActor
    func testPendingSaveRequestsDestinationPromptBeforeFinalSave() async throws {
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
        viewModel.retryPendingSave()
        try await waitForPendingSaveDestinationPrompt(in: viewModel)

        let destinationPrompt = try XCTUnwrap(viewModel.pendingSaveDestinationPrompt)
        XCTAssertEqual(destinationPrompt.job.id, state.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalURL.path))
        XCTAssertEqual(try String(contentsOf: temporaryURL, encoding: .utf8), "new output")

        viewModel.chooseFolderForPendingSave(prompt: destinationPrompt)
        try await waitForCompletedSave(in: viewModel)

        XCTAssertNil(viewModel.pendingSaveDestinationPrompt)
        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "new output")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
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
    func testMissingRestoredFinalOutputRoutesToInternalOutputWithoutSystemPicker() async throws {
        let directoryURL = temporaryDirectoryURL()
        try? FileManager.default.removeItem(at: TaptionEncoderStorageLocations.exportedVideosDirectoryURL)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.removeItem(at: TaptionEncoderStorageLocations.exportedVideosDirectoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let internalURL = TaptionEncoderStorageLocations.exportedVideosDirectoryURL
            .appendingPathComponent("encoded.mp4")
        try Data("new output".utf8).write(to: temporaryURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: nil,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            saveDestinationWasChosen: true
        )
        try await store.savePendingState(state)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForCompletedSave(in: viewModel)

        XCTAssertEqual(try String(contentsOf: internalURL, encoding: .utf8), "new output")
        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(
            viewModel.state.detail,
            expectedCompletedSaveDetail(
                url: internalURL,
                fileByteCount: Data("new output".utf8).count
            )
        )
        XCTAssertEqual(viewModel.savedFolderPrompt?.fileName, internalURL.lastPathComponent)
        XCTAssertEqual(
            viewModel.savedFolderPrompt?.folderURL.standardizedFileURL,
            internalURL.deletingLastPathComponent().standardizedFileURL
        )
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
            requiresRewardedAd: false,
            saveDestinationWasChosen: true
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
        let asset = makeAsset(sourceCodec: .av1, duration: 120, fileSize: 400_000_000)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: asset)
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertEqual(viewModel.outputSizeDisplayText, "Auto")
        XCTAssertEqual(viewModel.outputSizeSecondaryText, "~72 MB")
        XCTAssertEqual(viewModel.selectedOutputTargetSizeText, "72 MB")
        XCTAssertEqual(viewModel.outputSizeStatusMessage, "Estimated output: 72 MB.")
        XCTAssertEqual(viewModel.outputTargetSizeRangeMB.lowerBound, 25)
        XCTAssertEqual(viewModel.outputTargetSizeRangeMB.upperBound, 130)

        viewModel.selectOutputResolution(.hd720)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertEqual(viewModel.outputSizeDisplayText, "Auto")
        XCTAssertEqual(viewModel.outputSizeSecondaryText, "~34 MB")
        XCTAssertEqual(viewModel.selectedOutputTargetSizeText, "34 MB")
    }

    @MainActor
    func testOutputRefreshReusesInspectedMetadataForUnchangedFile() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        let sourceData = Data("source".utf8)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try sourceData.write(to: sourceURL)

        let asset = makeAsset(
            sourceCodec: .av1,
            duration: 120,
            fileSize: Int64(sourceData.count),
            fingerprint: try testMediaFingerprint(for: sourceURL)
        )
        let inspector = CountingMediaInspector(asset: asset)
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: inspector
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)
        guard case .readyToStart(let initialReview) = viewModel.state else {
            return XCTFail("Expected ready state after initial inspection")
        }
        XCTAssertEqual(inspector.inspectionCount, 1)

        viewModel.selectOutputResolution(.hd720)
        try await waitForCondition(timeout: 2) {
            if case .readyToStart(let review) = viewModel.state {
                return review.job.plan.id != initialReview.job.plan.id
                    && viewModel.outputSizeStatusMessage == "Estimated output: 34 MB."
            }
            return false
        }

        XCTAssertEqual(inspector.inspectionCount, 1)
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
        let asset = makeAsset(sourceCodec: .av1, duration: 120, fileSize: 400_000_000)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: asset)
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        viewModel.selectOutputSize(.manual)
        XCTAssertEqual(viewModel.outputSizeDisplayText, "130 MB")
        XCTAssertNil(viewModel.outputSizeSecondaryText)

        viewModel.updateOutputTargetSizeMB(80)
        XCTAssertEqual(viewModel.outputSizeDisplayText, "80 MB")
        XCTAssertEqual(viewModel.selectedOutputTargetSizeText, "80 MB")
        XCTAssertNil(viewModel.outputSizeSecondaryText)

        viewModel.updateOutputTargetSizeMB(450)
        XCTAssertEqual(viewModel.outputSizeDisplayText, "130 MB")
        XCTAssertEqual(viewModel.selectedOutputTargetSizeText, "130 MB")
        XCTAssertEqual(viewModel.selectedOutputTargetSizeValueMB, 130)
    }

    @MainActor
    func testRestoredPendingSaveWaitsForUserActionWithoutSystemPicker() async throws {
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
            requiresRewardedAd: false,
            saveDestinationWasChosen: true
        )
        try await store.savePendingState(state)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()

        XCTAssertEqual(viewModel.state.title, "Pending save")
        XCTAssertNotNil(viewModel.pendingSaveRecoveryJob)
    }

    @MainActor
    func testPermissionDeniedPendingSaveRoutesToInternalOutputWithoutSystemPicker() async throws {
        let directoryURL = temporaryDirectoryURL()
        let readOnlyDirectoryURL = directoryURL.appendingPathComponent("ReadOnly", isDirectory: true)
        try? FileManager.default.removeItem(at: TaptionEncoderStorageLocations.exportedVideosDirectoryURL)
        defer {
            chmod(readOnlyDirectoryURL.path, 0o755)
            chmod(directoryURL.path, 0o755)
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.removeItem(at: TaptionEncoderStorageLocations.exportedVideosDirectoryURL)
        }
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = readOnlyDirectoryURL.appendingPathComponent("clip_taption.mp4")
        let internalURL = TaptionEncoderStorageLocations.exportedVideosDirectoryURL
            .appendingPathComponent("clip_taption.mp4")
        try FileManager.default.createDirectory(at: readOnlyDirectoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)
        chmod(readOnlyDirectoryURL.path, 0o555)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            saveDestinationWasChosen: true
        )
        try await store.savePendingState(state)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForCompletedSave(in: viewModel)

        XCTAssertFalse(FileManager.default.fileExists(atPath: finalURL.path))
        XCTAssertEqual(try String(contentsOf: internalURL, encoding: .utf8), "new output")
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(
            viewModel.state.detail,
            expectedCompletedSaveDetail(
                url: internalURL,
                fileByteCount: Data("new output".utf8).count
            )
        )
        let states = try await store.loadPendingStates()
        XCTAssertTrue(states.isEmpty)
    }

    @MainActor
    func testInternalOutputRecoveryKeepsSaveCompleteVisibleWhileAnotherPendingSaveRemainsQueued() async throws {
        let directoryURL = temporaryDirectoryURL()
        let readOnlyDirectoryURL = directoryURL.appendingPathComponent("ReadOnly", isDirectory: true)
        try? FileManager.default.removeItem(at: TaptionEncoderStorageLocations.exportedVideosDirectoryURL)
        defer {
            chmod(readOnlyDirectoryURL.path, 0o755)
            chmod(directoryURL.path, 0o755)
            try? FileManager.default.removeItem(at: directoryURL)
            try? FileManager.default.removeItem(at: TaptionEncoderStorageLocations.exportedVideosDirectoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let firstTemporaryURL = directoryURL.appendingPathComponent("first-encoded.mp4")
        let firstFinalURL = readOnlyDirectoryURL.appendingPathComponent("first_taption.mp4")
        let recoveredFirstURL = TaptionEncoderStorageLocations.exportedVideosDirectoryURL
            .appendingPathComponent("first_taption.mp4")
        let secondTemporaryURL = directoryURL.appendingPathComponent("second-encoded.mp4")
        let secondFinalURL = directoryURL.appendingPathComponent("second_taption.mp4")
        try FileManager.default.createDirectory(at: readOnlyDirectoryURL, withIntermediateDirectories: true)
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
            createdAt: Date(timeIntervalSince1970: 1),
            saveDestinationWasChosen: true
        )
        let secondState = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: secondTemporaryURL,
            finalOutputURL: secondFinalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            createdAt: Date(timeIntervalSince1970: 2),
            saveDestinationWasChosen: true
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
    func testPendingSaveConflictKeepsExistingOutputAndSavesUniqueWithoutAnotherAd() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = directoryURL.appendingPathComponent("clip_taption.mp4")
        let uniqueURL = directoryURL.appendingPathComponent("clip_taption 2.mp4")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("new output".utf8).write(to: temporaryURL)
        try Data("existing output".utf8).write(to: finalURL)

        let store = FilePendingSaveStore(fileURL: directoryURL.appendingPathComponent("pending.json"))
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            saveDestinationWasChosen: true
        )
        try await store.savePendingState(state)
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: store)
        )

        await viewModel.restorePendingSavesIfNeeded()
        viewModel.retryPendingSave()
        try await waitForCompletedSave(in: viewModel)

        XCTAssertEqual(try String(contentsOf: finalURL, encoding: .utf8), "existing output")
        XCTAssertEqual(try String(contentsOf: uniqueURL, encoding: .utf8), "new output")
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
                url: uniqueURL,
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
            createdAt: Date(timeIntervalSince1970: 1),
            saveDestinationWasChosen: true
        )
        let secondState = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: secondTemporaryURL,
            finalOutputURL: secondFinalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: false,
            createdAt: Date(timeIntervalSince1970: 2),
            saveDestinationWasChosen: true
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
        XCTAssertTrue(presentation.action.contains("Choose where to save"))
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

    func testStarBadgeRunsRewardedAdFlowWithoutPurchaseSheet() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let homeViewModelURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeViewModel.swift")
        let homeStateURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeScreenState.swift")
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
        let viewModelText = try String(contentsOf: homeViewModelURL, encoding: .utf8)
        let stateText = try String(contentsOf: homeStateURL, encoding: .utf8)

        XCTAssertTrue(homeViewText.contains("private func watchAdFromStarBadge()"))
        XCTAssertTrue(homeViewText.contains("viewModel.watchAdForStar()"))
        XCTAssertTrue(homeViewText.contains("accessibilityLabel(\"Watch Ad for Star. Balance \\(viewModel.starBalanceDisplayText)\")"))
        XCTAssertFalse(homeViewText.contains("@State private var isStarPurchaseSheetPresented"))
        XCTAssertFalse(homeViewText.contains("StarPurchaseSheetView("))
        XCTAssertFalse(homeViewText.contains("StarPurchaseProductRow"))
        XCTAssertFalse(homeViewText.contains("Pro Mode"))
        XCTAssertFalse(homeViewText.contains("StoreKit"))
        XCTAssertFalse(homeViewText.contains(".starPurchaseNoticeDialog(viewModel: viewModel)"))
        XCTAssertFalse(viewModelText.contains("@Published private(set) var starPurchaseProducts"))
        XCTAssertFalse(viewModelText.contains("@Published private(set) var starPurchaseNotice"))
        XCTAssertFalse(viewModelText.contains("func refreshStarPurchaseProducts()"))
        XCTAssertFalse(viewModelText.contains("func beginStarPurchase(product:"))
        XCTAssertFalse(viewModelText.contains("recordPurchase(product"))
        XCTAssertFalse(stateText.contains("struct StarPurchaseNotice"))
        XCTAssertFalse(stateText.contains("Pro Mode Purchase Not Available"))
        XCTAssertFalse(stateText.contains("App Store Connect"))
    }

    func testStarWalletStoreGrantsInitialInstallBonusOnce() async throws {
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

        let snapshot = await store.currentSnapshot()

        XCTAssertEqual(snapshot.balance, StarWalletStore.initialInstallBonusStarCount)
        XCTAssertEqual(snapshot.totalEarned, StarWalletStore.initialInstallBonusStarCount)
        XCTAssertEqual(snapshot.totalSpent, 0)
        XCTAssertEqual(snapshot.totalPurchased, 0)
        XCTAssertEqual(snapshot.sequence, 1)
        XCTAssertEqual(snapshot.events.map(\.kind), [.initialInstallBonus])
        XCTAssertEqual(snapshot.events.first?.delta, StarWalletStore.initialInstallBonusStarCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: walletFileURL.path))

        let reloadedStore = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )
        let reloadedSnapshot = await reloadedStore.currentSnapshot()

        XCTAssertEqual(reloadedSnapshot.balance, StarWalletStore.initialInstallBonusStarCount)
        XCTAssertEqual(reloadedSnapshot.sequence, 1)
        XCTAssertEqual(reloadedSnapshot.events.map(\.kind), [.initialInstallBonus])
    }

    func testStarWalletStoreRestoresLastKeychainSnapshotAfterWalletFileRemoval() async throws {
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

        _ = await store.currentSnapshot()
        let expectedSnapshot = try await store.consumeStar(source: "test_encode")
        try FileManager.default.removeItem(at: walletFileURL)

        let reloadedStore = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )
        let reloadedSnapshot = await reloadedStore.currentSnapshot()

        XCTAssertEqual(reloadedSnapshot.balance, expectedSnapshot.balance)
        XCTAssertEqual(reloadedSnapshot.sequence, expectedSnapshot.sequence)
        XCTAssertEqual(reloadedSnapshot.events.map(\.kind), expectedSnapshot.events.map(\.kind))
        XCTAssertTrue(FileManager.default.fileExists(atPath: walletFileURL.path))
    }

    func testStarWalletStoreDoesNotRegrantInitialBonusWithoutRecoverableSnapshot() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let secureStore = TestStarWalletSecureStore()
        try secureStore.saveInitialBonusGranted()
        let walletFileURL = directoryURL.appendingPathComponent("stars.enc")
        let quarantineURL = directoryURL.appendingPathComponent("quarantine", isDirectory: true)
        let store = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )

        let snapshot = await store.currentSnapshot()

        XCTAssertEqual(snapshot, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: walletFileURL.path))
    }

    func testStarWalletStoreMarksExistingWalletAsInitialBonusGranted() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let secureStore = TestStarWalletSecureStore()
        let walletFileURL = directoryURL.appendingPathComponent("stars.enc")
        let quarantineURL = directoryURL.appendingPathComponent("quarantine", isDirectory: true)
        let existingStore = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )
        let existingSnapshot = makeStarWalletSnapshot(balance: 3, sequence: 7)
        try await existingStore.persistForTesting(existingSnapshot)

        let reloadedStore = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )
        let reloadedSnapshot = await reloadedStore.currentSnapshot()

        XCTAssertEqual(reloadedSnapshot.balance, 3)
        XCTAssertEqual(reloadedSnapshot.sequence, 7)
        XCTAssertFalse(reloadedSnapshot.events.contains { $0.kind == .initialInstallBonus })

        try FileManager.default.removeItem(at: walletFileURL)

        let missingWalletStore = StarWalletStore(
            fileURL: walletFileURL,
            quarantineDirectoryURL: quarantineURL,
            secureStore: secureStore
        )
        let missingWalletSnapshot = await missingWalletStore.currentSnapshot()

        XCTAssertEqual(missingWalletSnapshot.balance, 3)
        XCTAssertEqual(missingWalletSnapshot.sequence, 7)
        XCTAssertTrue(FileManager.default.fileExists(atPath: walletFileURL.path))
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
        let expectedSnapshot = try await store.earnStar(source: "rewarded_ad")

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
        XCTAssertEqual(reloadedSnapshot.totalPurchased, 0)
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
    func testPendingSaveRewardedAdUnavailableShowsFindAdAndTapRetriesLoad() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let temporaryURL = directoryURL.appendingPathComponent("encoded.mp4")
        let finalURL = directoryURL.appendingPathComponent("source_taption.mp4")
        try Data("encoded".utf8).write(to: temporaryURL)

        let pendingSaveStore = FakePendingSaveStore()
        let state = TaptionPendingSaveState(
            planID: UUID(),
            temporaryOutputURL: temporaryURL,
            finalOutputURL: finalURL,
            saveDestination: .sourceFolder,
            requiresRewardedAd: true,
            saveDestinationWasChosen: true
        )
        try await pendingSaveStore.savePendingState(state)
        let rewardedAdProvider = RetryingRewardedAdProvider()
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: pendingSaveStore,
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                rewardedAdProvider: rewardedAdProvider
            )
        )

        await viewModel.restorePendingSavesIfNeeded()
        try await waitForCondition(timeout: 2) {
            viewModel.state.pendingSaveJob?.state.requiresRewardedAd == true
                && viewModel.rewardedAdState == .unavailable
                && viewModel.canWatchAdForStar
        }

        XCTAssertEqual(viewModel.watchAdButtonTitle, "Find Ad")

        viewModel.watchAdForStar()
        try await waitForCondition(timeout: 2) {
            viewModel.rewardedAdState == .ready
                && viewModel.watchAdButtonTitle == "Watch Ad to Save"
                && viewModel.canWatchAdForStar
        }

        let retryCallCount = await rewardedAdProvider.recordedRetryCallCount()
        let showCallCount = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(retryCallCount, 1)
        XCTAssertEqual(showCallCount, 0)
    }

    @MainActor
    func testStartPreparedEncodingWithoutStarsDisablesStartAndDoesNotEncode() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: sourceURL)

        let rewardedAdProvider = RecordingRewardedAdProvider(showResult: .earnedReward)
        let walletStore = FakeStarWalletStore()
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

        XCTAssertFalse(viewModel.canStartEncodingNow)
        XCTAssertEqual(viewModel.startActionTitle, "Start (-1 Star)")
        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 0)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Ready")

        viewModel.startPreparedEncoding()

        XCTAssertEqual(viewModel.state.title, "Ready to encode")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("source_taption.mp4").path
        ))
        let showCallCount = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(showCallCount, 0)
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
    func testMultiFileStartPromptsBeforeEncodingAndMergeChoiceShowsUnavailableAlert() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = [
            directoryURL.appendingPathComponent("a.mp4"),
            directoryURL.appendingPathComponent("b.mp4")
        ]
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 2))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        viewModel.startPreparedEncoding()

        let prompt = try XCTUnwrap(viewModel.multiFileEncodingPrompt)
        XCTAssertEqual(prompt.fileCount, 2)
        XCTAssertEqual(prompt.title, "Encode Multiple Files")
        XCTAssertEqual(viewModel.state.title, "Ready to encode")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("a_taption.mp4").path
        ))

        viewModel.chooseMergeEncodingForMultiFilePrompt(prompt: prompt)

        XCTAssertNil(viewModel.multiFileEncodingPrompt)
        XCTAssertEqual(viewModel.multiFileMergeUnavailableAlert?.title, "Merge Unavailable")
        XCTAssertEqual(viewModel.state.title, "Ready to encode")
        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 2)
    }

    @MainActor
    func testMultiFilePromptEncodeSeparatelyContinuesBatchEncoding() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = [
            directoryURL.appendingPathComponent("a.mp4"),
            directoryURL.appendingPathComponent("b.mp4")
        ]
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 2))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()

        let prompt = try XCTUnwrap(viewModel.multiFileEncodingPrompt)
        viewModel.chooseSeparateEncodingForMultiFilePrompt(prompt: prompt)
        try await waitForCompletedSave(in: viewModel, timeout: 3)

        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("a_taption.mp4").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("b_taption.mp4").path
        ))
        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 0)
    }

    @MainActor
    func testBatteryLimitBlocksStartBeforeStarDebit() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: sourceURL)

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
        let batteryMonitor = MutableBatteryPowerMonitor(snapshot: BatteryEncodingPowerSnapshot(
            batteryPercent: 30,
            isPowerConnected: false,
            isPowerStateKnown: true
        ))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                starWalletStore: walletStore
            ),
            batteryPowerMonitor: batteryMonitor,
            batterySettingsProvider: {
                BatteryEncodingSettings(
                    batteryLimitPercent: 30,
                    powerConnectedOnly: false
                )
            }
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()

        try await waitForCondition(timeout: 2) {
            viewModel.batteryEncodingAlert != nil
        }

        XCTAssertEqual(viewModel.batteryEncodingAlert?.title, "Connect Power")
        XCTAssertEqual(viewModel.batteryEncodingAlert?.message, "Battery is at 30%. Battery Limit is 30%. Connect power before starting encoding.")
        XCTAssertEqual(viewModel.state.title, "Ready to encode")
        let blockedStartWalletSnapshot = await walletStore.currentSnapshot()
        XCTAssertEqual(blockedStartWalletSnapshot.balance, 1)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("source_taption.mp4").path
        ))
    }

    @MainActor
    func testPowerConnectedOnlyBlocksStartBeforeEncodingWhenDisconnected() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: sourceURL)

        let batteryMonitor = MutableBatteryPowerMonitor(snapshot: BatteryEncodingPowerSnapshot(
            batteryPercent: 80,
            isPowerConnected: false,
            isPowerStateKnown: true
        ))
        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                starWalletStore: walletStore
            ),
            batteryPowerMonitor: batteryMonitor,
            batterySettingsProvider: {
                BatteryEncodingSettings(
                    batteryLimitPercent: 30,
                    powerConnectedOnly: true
                )
            }
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()

        try await waitForCondition(timeout: 2) {
            viewModel.batteryEncodingAlert != nil
        }

        XCTAssertEqual(viewModel.batteryEncodingAlert?.title, "Connect Power")
        XCTAssertEqual(viewModel.batteryEncodingAlert?.message, "Power Connected Only is enabled. Connect power before starting encoding.")
        XCTAssertEqual(viewModel.state.title, "Ready to encode")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("source_taption.mp4").path
        ))
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

        await viewModel.refreshStarsIfNeeded()
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

        await viewModel.refreshStarsIfNeeded()
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
    func testFolderBatchWithPartialStarBalanceActivatesTopCardsAndEncodesOnlyThose() async throws {
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

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertEqual(viewModel.startActionTitle, "Start (-2 Stars)")
        XCTAssertTrue(viewModel.canStartEncodingNow)
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["a.mp4", "b.mp4", "c.mp4"])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isEnabled), [true, true, false])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isStarLimited), [false, false, true])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.statusText), ["Ready", "Queued", "Need Stars"])

        viewModel.startPreparedEncoding()
        try await chooseFolderForPendingSaveDestination(in: viewModel)
        try await waitForCompletedSave(in: viewModel, timeout: 3)

        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertTrue(viewModel.state.detail.contains("2 of 3 files were saved"))
        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("a_taption.mp4").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("b_taption.mp4").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("c_taption.mp4").path
        ))
        let showCallCount = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(showCallCount, 0)
    }

    @MainActor
    func testFolderBatchWithOneStarActivatesOnlyFirstCardBeforeEncoding() async throws {
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

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
        let rewardedAdProvider = RecordingRewardedAdProvider(showResult: .earnedReward)
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                rewardedAdProvider: rewardedAdProvider,
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertEqual(viewModel.startActionTitle, "Start (-1 Star)")
        XCTAssertTrue(viewModel.canStartEncodingNow)
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isEnabled), [true, false, false])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isStarLimited), [false, true, true])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.statusText), ["Ready", "Need Stars", "Need Stars"])

        viewModel.startPreparedEncoding()
        try await chooseFolderForPendingSaveDestination(in: viewModel)
        try await waitForCompletedSave(in: viewModel, timeout: 3)

        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertTrue(viewModel.state.detail.contains("1 of 3 files were saved"))
        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("a_taption.mp4").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("b_taption.mp4").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("c_taption.mp4").path
        ))
        let showCallCount = await rewardedAdProvider.recordedShowCallCount()
        XCTAssertEqual(showCallCount, 0)
    }

    @MainActor
    func testStarLimitedFolderCardKeepsThumbnailDetailsAndPreviewPlayback() async throws {
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

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        let limitedID = fileURLs[1].absoluteString
        var limitedCard = try XCTUnwrap(viewModel.fileCardSnapshots.first { $0.id == limitedID })
        XCTAssertFalse(limitedCard.isEnabled)
        XCTAssertTrue(limitedCard.isStarLimited)
        XCTAssertTrue(limitedCard.isPreviewable)
        XCTAssertTrue(limitedCard.isInteractable)
        XCTAssertEqual(limitedCard.statusText, "Need Stars")
        XCTAssertEqual(limitedCard.thumbnailSourceURL, fileURLs[1])
        XCTAssertNotNil(limitedCard.videoInfo)

        viewModel.selectFileCard(id: limitedID)
        try await waitForCondition(timeout: 2) {
            viewModel.fileCardSnapshots.first { $0.id == limitedID }?.isSelected == true
        }

        limitedCard = try XCTUnwrap(viewModel.fileCardSnapshots.first { $0.id == limitedID })
        XCTAssertTrue(limitedCard.isSelected)
        XCTAssertNotNil(limitedCard.videoInfo)
        XCTAssertEqual(limitedCard.thumbnailSourceURL, fileURLs[1])

        viewModel.openPreviewForFileCard(id: limitedID)
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == fileURLs[1]
        }

        XCTAssertEqual(viewModel.activePreview?.displayName, "b.mp4")
        XCTAssertEqual(viewModel.activePreview?.playlist?.positionText, "2 / 3")
        XCTAssertEqual(viewModel.activePreview?.playlist?.previousName, "a.mp4")
        XCTAssertEqual(viewModel.activePreview?.playlist?.nextName, "c.mp4")
    }

    @MainActor
    func testStarLimitedFolderCardsRemainEditableForSelectionDeleteAndMove() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = [
            directoryURL.appendingPathComponent("a.mp4"),
            directoryURL.appendingPathComponent("b.mp4"),
            directoryURL.appendingPathComponent("c.mp4"),
            directoryURL.appendingPathComponent("d.mp4")
        ]
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["a.mp4", "b.mp4", "c.mp4", "d.mp4"])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isEnabled), [true, false, false, false])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isStarLimited), [false, true, true, true])

        viewModel.selectFileCard(id: fileURLs[2].absoluteString)
        try await waitForCondition(timeout: 2) {
            viewModel.fileCardSnapshots.first { $0.id == fileURLs[2].absoluteString }?.isSelected == true
        }

        viewModel.toggleQueueFileSelection(id: fileURLs[1].absoluteString)
        viewModel.toggleQueueFileSelection(id: fileURLs[2].absoluteString)
        XCTAssertEqual(
            viewModel.fileCardSnapshots.filter(\.isMultiSelected).map(\.fileName),
            ["b.mp4", "c.mp4"]
        )

        viewModel.moveQueueFiles(
            draggedID: fileURLs[2].absoluteString,
            before: fileURLs[0].absoluteString
        )

        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["b.mp4", "c.mp4", "a.mp4", "d.mp4"])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isEnabled), [true, false, false, false])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isStarLimited), [false, true, true, true])
        XCTAssertEqual(
            viewModel.fileCardSnapshots.filter(\.isMultiSelected).map(\.fileName),
            ["b.mp4", "c.mp4"]
        )

        viewModel.finishQueueMove()
        try await waitForCondition(timeout: 2) {
            viewModel.state.preparedEncodingReview?.source.url == fileURLs[1]
        }

        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["b.mp4", "c.mp4", "a.mp4", "d.mp4"])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isEnabled), [true, false, false, false])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isStarLimited), [false, true, true, true])
        XCTAssertEqual(
            viewModel.fileCardSnapshots.filter(\.isMultiSelected).map(\.fileName),
            ["b.mp4", "c.mp4"]
        )

        viewModel.deleteQueueFile(id: fileURLs[2].absoluteString)

        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["a.mp4", "d.mp4"])
        XCTAssertTrue(viewModel.fileCardSnapshots.allSatisfy { !$0.isMultiSelected })
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isEnabled), [true, false])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isStarLimited), [false, true])
    }

    @MainActor
    func testFolderBatchStarBudgetReappliesAfterQueueMove() async throws {
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
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        viewModel.moveQueueFiles(
            draggedID: fileURLs[2].absoluteString,
            before: fileURLs[0].absoluteString
        )

        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["c.mp4", "a.mp4", "b.mp4"])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isEnabled), [true, true, false])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isStarLimited), [false, false, true])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.statusText), ["Queued", "Ready", "Need Stars"])

        viewModel.finishQueueMove()
        try await waitForCondition(timeout: 2) {
            viewModel.state.preparedEncodingReview?.source.url == fileURLs[2]
        }

        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["c.mp4", "a.mp4", "b.mp4"])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isEnabled), [true, true, false])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.isStarLimited), [false, false, true])
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.statusText), ["Ready", "Queued", "Need Stars"])
        XCTAssertEqual(viewModel.startActionTitle, "Start (-2 Stars)")
        XCTAssertTrue(viewModel.canStartEncodingNow)
    }

    @MainActor
    func testFolderBatchStopsAfterCurrentItemWhenPowerDisconnectsDuringEncoding() async throws {
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

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 3))
        let batteryMonitor = MutableBatteryPowerMonitor(snapshot: BatteryEncodingPowerSnapshot(
            batteryPercent: 80,
            isPowerConnected: true,
            isPowerStateKnown: true
        ))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: PowerDisconnectingEncoderService(
                    outputData: Data("encoded".utf8),
                    batteryMonitor: batteryMonitor
                ),
                starWalletStore: walletStore
            ),
            batteryPowerMonitor: batteryMonitor,
            batterySettingsProvider: {
                BatteryEncodingSettings(
                    batteryLimitPercent: 30,
                    powerConnectedOnly: true
                )
            }
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()
        try await waitForCompletedSave(in: viewModel, timeout: 3)

        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertTrue(viewModel.state.detail.contains("Folder encoding stopped. 1 of 3 files were saved."))
        let stoppedBatchWalletSnapshot = await walletStore.currentSnapshot()
        XCTAssertEqual(stoppedBatchWalletSnapshot.balance, 2)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("a_taption.mp4").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("b_taption.mp4").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("c_taption.mp4").path
        ))

        let statuses = Dictionary(uniqueKeysWithValues: viewModel.fileCardSnapshots.map {
            ($0.id, $0.statusText)
        })
        XCTAssertEqual(statuses[fileURLs[0].absoluteString], "Save Complete")
        XCTAssertEqual(statuses[fileURLs[1].absoluteString], "Stopped")
        XCTAssertEqual(statuses[fileURLs[2].absoluteString], "Stopped")
    }

    @MainActor
    func testFolderBatchStopsAfterCurrentItemWhenBatteryDropsBelowLimitDuringEncoding() async throws {
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

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 3))
        let batteryMonitor = MutableBatteryPowerMonitor(snapshot: BatteryEncodingPowerSnapshot(
            batteryPercent: 31,
            isPowerConnected: false,
            isPowerStateKnown: true
        ))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: BatteryDroppingEncoderService(
                    outputData: Data("encoded".utf8),
                    batteryMonitor: batteryMonitor
                ),
                starWalletStore: walletStore
            ),
            batteryPowerMonitor: batteryMonitor,
            batterySettingsProvider: {
                BatteryEncodingSettings(
                    batteryLimitPercent: 30,
                    powerConnectedOnly: false
                )
            }
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()
        try await waitForCompletedSave(in: viewModel, timeout: 3)

        XCTAssertTrue(viewModel.state.detail.contains("Battery reached 29%, at or below the 30% Battery Limit."))
        let stoppedBatchWalletSnapshot = await walletStore.currentSnapshot()
        XCTAssertEqual(stoppedBatchWalletSnapshot.balance, 2)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("a_taption.mp4").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directoryURL.appendingPathComponent("b_taption.mp4").path
        ))

        let statuses = Dictionary(uniqueKeysWithValues: viewModel.fileCardSnapshots.map {
            ($0.id, $0.statusText)
        })
        XCTAssertEqual(statuses[fileURLs[0].absoluteString], "Save Complete")
        XCTAssertEqual(statuses[fileURLs[1].absoluteString], "Stopped")
        XCTAssertEqual(statuses[fileURLs[2].absoluteString], "Stopped")
    }

    @MainActor
    func testFolderPickerSelectionRoutesVideoFileToFileFlow() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("picked.mp4")
        try Data("source".utf8).write(to: sourceURL)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.handleFolderPickerSelection(urls: [sourceURL])
        try await waitForReadyToStartState(in: viewModel)

        guard case .readyToStart(let review) = viewModel.state else {
            return XCTFail("Expected ready state for file passthrough")
        }
        XCTAssertEqual(review.source.kind, .files)
        XCTAssertEqual(review.source.url, sourceURL)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.fileName, "picked.mp4")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.thumbnailSourceURL, sourceURL)
    }

    @MainActor
    func testFolderPickerSelectionRoutesFolderToFolderFlow() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let folderURL = directoryURL.appendingPathComponent("PickedFolder", isDirectory: true)
        let sourceURL = folderURL.appendingPathComponent("inside.mp4")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: sourceURL)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.handleFolderPickerSelection(urls: [folderURL])
        XCTAssertEqual(viewModel.folderPreviewContext?.folderName, "PickedFolder")
        XCTAssertEqual(viewModel.folderPreviewContext?.fileCount, 1)
        XCTAssertEqual(viewModel.folderPreviewFileSnapshots.first?.id, sourceURL.absoluteString)
        XCTAssertEqual(viewModel.folderPreviewFileSnapshots.first?.sourceKind, .folder)
        XCTAssertEqual(viewModel.folderPreviewFileSnapshots.first?.thumbnailSourceURL, sourceURL)

        viewModel.importFolderPreviewBatch()
        try await waitForReadyToStartState(in: viewModel)
        XCTAssertNil(viewModel.activePreview)

        guard case .readyToStart(let review) = viewModel.state else {
            return XCTFail("Expected ready state for folder selection")
        }
        XCTAssertEqual(review.source.kind, .folder)
        XCTAssertEqual(review.folderQueue?.folderName, "PickedFolder")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.id, sourceURL.absoluteString)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.sourceKind, .folder)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.thumbnailSourceURL, sourceURL)
    }

    @MainActor
    func testFolderBatchFolderDestinationSavesIntoSiblingTaptionFolder() async throws {
        let parentURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: parentURL)
        }
        let sourceFolderURL = parentURL.appendingPathComponent("VideoFolder", isDirectory: true)
        let firstURL = sourceFolderURL.appendingPathComponent("a.mp4")
        let secondURL = sourceFolderURL.appendingPathComponent("b.mp4")
        try FileManager.default.createDirectory(at: sourceFolderURL, withIntermediateDirectories: true)
        try Data("source a".utf8).write(to: firstURL)
        try Data("source b".utf8).write(to: secondURL)

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 2))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFolderFlow(url: sourceFolderURL)
        viewModel.importFolderPreviewBatch()
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()
        try await chooseFolderForPendingSaveDestination(in: viewModel)

        let outputFolderURL = parentURL.appendingPathComponent("VideoFolder_taption", isDirectory: true)
        let firstOutputURL = outputFolderURL.appendingPathComponent("a_taption.mp4")
        let secondOutputURL = outputFolderURL.appendingPathComponent("b_taption.mp4")
        try await waitForCondition(timeout: 3) {
            FileManager.default.fileExists(atPath: firstOutputURL.path)
                && FileManager.default.fileExists(atPath: secondOutputURL.path)
                && viewModel.state.title == "Save Complete"
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sourceFolderURL.appendingPathComponent("a_taption.mp4").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sourceFolderURL.appendingPathComponent("b_taption.mp4").path
        ))
        XCTAssertEqual(try String(contentsOf: firstOutputURL, encoding: .utf8), "encoded")
        XCTAssertEqual(try String(contentsOf: secondOutputURL, encoding: .utf8), "encoded")
    }

    @MainActor
    func testFilePickerSelectionOpensPreviewBrowserBeforeImport() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let firstURL = directoryURL.appendingPathComponent("a.mp4")
        let secondURL = directoryURL.appendingPathComponent("b.mp4")
        try Data("source".utf8).write(to: firstURL)
        try Data("source".utf8).write(to: secondURL)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.openFilesPreviewBrowser(urls: [secondURL, firstURL])

        XCTAssertEqual(viewModel.folderPreviewContext?.folderName, "Selected files")
        XCTAssertEqual(viewModel.folderPreviewContext?.fileCount, 2)
        XCTAssertEqual(viewModel.folderPreviewFileSnapshots.map(\.id), [
            firstURL.absoluteString,
            secondURL.absoluteString
        ])
        XCTAssertEqual(viewModel.folderPreviewFileSnapshots.first?.sourceKind, .files)
        XCTAssertNil(viewModel.activePreview)
        guard case .idle = viewModel.state else {
            return XCTFail("Expected file picker browser to stay idle until preview or import is requested")
        }

        viewModel.selectFolderPreviewFile(id: secondURL.absoluteString)
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == secondURL
        }

        XCTAssertEqual(viewModel.activePreview?.displayName, "b.mp4")
        XCTAssertEqual(
            viewModel.folderPreviewFileSnapshots.first(where: { $0.id == secondURL.absoluteString })?.isSelected,
            true
        )
    }

    @MainActor
    func testImportBrowserOpensInAppLocationsWithoutSystemPicker() async throws {
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.openImportBrowser(mode: .files)

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "On My iPhone")
        XCTAssertEqual(viewModel.importBrowserContext?.hasLocation, false)
        XCTAssertEqual(viewModel.importBrowserContext?.canGoBack, false)
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, false)
        XCTAssertTrue(viewModel.importBrowserFolders.contains {
            $0.folderName == "Taption Encoder Files"
        })
        XCTAssertTrue(viewModel.importBrowserFiles.isEmpty)

        let rootID = try XCTUnwrap(viewModel.importBrowserFolders.first?.id)
        viewModel.navigateImportBrowserIntoFolder(id: rootID)

        XCTAssertEqual(viewModel.importBrowserContext?.hasLocation, true)
        XCTAssertEqual(viewModel.importBrowserContext?.canGoBack, true)
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)

        viewModel.navigateImportBrowserUp()

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "On My iPhone")
        XCTAssertEqual(viewModel.importBrowserContext?.hasLocation, false)
    }

    @MainActor
    func testImportBrowserFileModeNavigatesFoldersAndSelectsFiles() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let rootURL = directoryURL.appendingPathComponent("VideoRoot", isDirectory: true)
        let childURL = rootURL.appendingPathComponent("Child", isDirectory: true)
        let rootVideoURL = rootURL.appendingPathComponent("root.mp4")
        let childVideoURL = childURL.appendingPathComponent("child.mp4")
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        try Data("root".utf8).write(to: rootVideoURL)
        try Data("child".utf8).write(to: childVideoURL)
        try Data("note".utf8).write(to: rootURL.appendingPathComponent("notes.txt"))

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.openImportBrowserRoot(url: rootURL, mode: .files)

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "VideoRoot")
        XCTAssertEqual(viewModel.importBrowserFolders.map(\.folderName), ["Child"])
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.fileName), ["root.mp4"])
        XCTAssertEqual(viewModel.importBrowserContext?.selectedFileCount, 0)

        viewModel.navigateImportBrowserIntoFolder(id: childURL.standardizedFileURL.path)

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "VideoRoot/Child")
        XCTAssertEqual(viewModel.importBrowserContext?.canGoBack, true)
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.fileName), ["child.mp4"])

        viewModel.toggleImportBrowserFileSelection(id: childVideoURL.standardizedFileURL.path)

        XCTAssertEqual(viewModel.importBrowserContext?.selectedFileCount, 1)
        XCTAssertEqual(viewModel.importBrowserFiles.first?.isSelected, true)

        viewModel.navigateImportBrowserUp()

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "VideoRoot")
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)
        XCTAssertEqual(viewModel.importBrowserContext?.selectedFileCount, 1)

        viewModel.navigateImportBrowserBack()

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "VideoRoot/Child")
        XCTAssertEqual(viewModel.importBrowserFiles.first?.isSelected, true)

        viewModel.importFromImportBrowser()

        XCTAssertNil(viewModel.importBrowserContext)
        XCTAssertEqual(viewModel.folderPreviewContext?.folderName, "child.mp4")
        XCTAssertEqual(viewModel.folderPreviewContext?.fileCount, 1)
        XCTAssertEqual(viewModel.folderPreviewFileSnapshots.map(\.id), [childVideoURL.absoluteString])
    }

    @MainActor
    func testImportBrowserFolderModeDefaultsToSelectedFilesAndCanTrimQueue() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let rootURL = directoryURL.appendingPathComponent("VideoRoot", isDirectory: true)
        let childURL = rootURL.appendingPathComponent("Child", isDirectory: true)
        let rootVideoURL = rootURL.appendingPathComponent("root.mp4")
        let childVideoURL = childURL.appendingPathComponent("child.mp4")
        let keptChildVideoURL = childURL.appendingPathComponent("keep.mov")
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        try Data("root".utf8).write(to: rootVideoURL)
        try Data("child".utf8).write(to: childVideoURL)
        try Data("keep".utf8).write(to: keptChildVideoURL)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.openImportBrowserRoot(url: rootURL, mode: .folder)

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "VideoRoot")
        XCTAssertEqual(viewModel.importBrowserFolders.map(\.folderName), ["Child"])
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.fileName), ["root.mp4"])
        XCTAssertEqual(viewModel.importBrowserContext?.selectedFileCount, 1)
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.isSelected), [true])

        viewModel.navigateImportBrowserIntoFolder(id: childURL.standardizedFileURL.path)

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "VideoRoot/Child")
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.fileName), ["child.mp4", "keep.mov"])
        XCTAssertEqual(viewModel.importBrowserContext?.selectedFileCount, 2)
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.isSelected), [true, true])

        viewModel.toggleImportBrowserFileSelection(id: childVideoURL.standardizedFileURL.path)

        XCTAssertEqual(viewModel.importBrowserContext?.selectedFileCount, 1)
        XCTAssertEqual(
            viewModel.importBrowserFiles.first(where: { $0.fileName == "child.mp4" })?.isSelected,
            false
        )
        XCTAssertEqual(
            viewModel.importBrowserFiles.first(where: { $0.fileName == "keep.mov" })?.isSelected,
            true
        )

        viewModel.navigateImportBrowserUp()

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "VideoRoot")
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)
        XCTAssertEqual(viewModel.importBrowserContext?.selectedFileCount, 1)
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.isSelected), [true])

        viewModel.navigateImportBrowserIntoFolder(id: childURL.standardizedFileURL.path)
        viewModel.toggleImportBrowserFileSelection(id: childVideoURL.standardizedFileURL.path)
        viewModel.importFromImportBrowser()

        XCTAssertNil(viewModel.importBrowserContext)
        XCTAssertEqual(viewModel.folderPreviewContext?.folderName, "Child")
        XCTAssertEqual(viewModel.folderPreviewContext?.fileCount, 1)
        XCTAssertEqual(viewModel.folderPreviewFileSnapshots.map(\.id), [keptChildVideoURL.absoluteString])
        XCTAssertEqual(viewModel.folderPreviewFileSnapshots.first?.sourceKind, .folder)
    }

    @MainActor
    func testImportBrowserCanMoveUpFromDocumentsChildToParentAndLocations() async throws {
        let documentsURL = try XCTUnwrap(FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first)
        let childName = "ImportBrowserParentProbe-\(UUID().uuidString)"
        let childURL = documentsURL.appendingPathComponent(childName, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: childURL)
        }
        try FileManager.default.createDirectory(at: childURL, withIntermediateDirectories: true)
        try Data("child".utf8).write(to: childURL.appendingPathComponent("child.mp4"))

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.openImportBrowserRoot(url: childURL, mode: .files)

        XCTAssertEqual(viewModel.importBrowserContext?.rootFolderName, "Taption Encoder Files")
        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "Taption Encoder Files/\(childName)")
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.fileName), ["child.mp4"])

        viewModel.navigateImportBrowserUp()

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "Taption Encoder Files")
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)
        XCTAssertTrue(viewModel.importBrowserFolders.contains { $0.folderName == childName })

        viewModel.navigateImportBrowserUp()

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "On My iPhone")
        XCTAssertEqual(viewModel.importBrowserContext?.hasLocation, false)
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, false)
    }

    @MainActor
    func testImportBrowserCanMoveAboveTaptionFolderWhenParentAccessIsGranted() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let grantedRootURL = directoryURL.appendingPathComponent("OnMyPhoneGrant", isDirectory: true)
        let taptionURL = grantedRootURL.appendingPathComponent("Taption", isDirectory: true)
        let siblingURL = grantedRootURL.appendingPathComponent("OtherVideos", isDirectory: true)
        try FileManager.default.createDirectory(at: taptionURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingURL, withIntermediateDirectories: true)
        try Data("taption".utf8).write(to: taptionURL.appendingPathComponent("taption.mp4"))
        try Data("sibling".utf8).write(to: siblingURL.appendingPathComponent("sibling.mp4"))

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.openImportBrowserRoot(
            url: taptionURL,
            mode: .files,
            authorizedRootURL: grantedRootURL
        )

        XCTAssertEqual(viewModel.importBrowserContext?.rootFolderName, "OnMyPhoneGrant")
        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "OnMyPhoneGrant/Taption")
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.fileName), ["taption.mp4"])
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)

        viewModel.navigateImportBrowserUp()

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "OnMyPhoneGrant")
        XCTAssertEqual(viewModel.importBrowserFolders.map(\.folderName), ["OtherVideos", "Taption"])
        XCTAssertTrue(viewModel.importBrowserFiles.isEmpty)
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)

        viewModel.navigateImportBrowserIntoFolder(id: siblingURL.standardizedFileURL.path)

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "OnMyPhoneGrant/OtherVideos")
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.fileName), ["sibling.mp4"])

        viewModel.navigateImportBrowserUp()
        viewModel.navigateImportBrowserUp()

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "On My iPhone")
        XCTAssertEqual(viewModel.importBrowserContext?.hasLocation, false)
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, false)
    }

    @MainActor
    func testQueueCardTapOpensPreviewForEnabledBatchItem() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = [
            directoryURL.appendingPathComponent("a.mp4"),
            directoryURL.appendingPathComponent("b.mp4")
        ]
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)
        XCTAssertNil(viewModel.activePreview)

        viewModel.openPreviewForFileCard(id: fileURLs[1].absoluteString)
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == fileURLs[1]
        }

        XCTAssertEqual(viewModel.activePreview?.displayName, "b.mp4")
        XCTAssertEqual(viewModel.activePreview?.videoInfo.isRouteEncodable, true)
        XCTAssertEqual(
            viewModel.fileCardSnapshots.first(where: { $0.id == fileURLs[1].absoluteString })?.isSelected,
            true
        )
        XCTAssertEqual(
            viewModel.fileCardSnapshots.first(where: { $0.id == fileURLs[1].absoluteString })?.isPreviewable,
            true
        )
        XCTAssertEqual(
            viewModel.fileCardSnapshots.first(where: { $0.id == fileURLs[1].absoluteString })?.thumbnailSourceURL,
            fileURLs[1]
        )
    }

    @MainActor
    func testQueueCardSelectionShowsDetailsWithoutOpeningPreview() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = [
            directoryURL.appendingPathComponent("a.mp4"),
            directoryURL.appendingPathComponent("b.mp4")
        ]
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.dismissPreview()
        XCTAssertNil(viewModel.activePreview)

        viewModel.selectFileCard(id: fileURLs[1].absoluteString)
        try await waitForCondition(timeout: 2) {
            guard let selectedCard = viewModel.fileCardSnapshots.first(where: { $0.id == fileURLs[1].absoluteString }) else {
                return false
            }
            return selectedCard.isSelected
                && selectedCard.videoInfo != nil
                && selectedCard.detailText?.contains("Ready to encode") == true
        }

        XCTAssertEqual(
            viewModel.fileCardSnapshots.first(where: { $0.id == fileURLs[0].absoluteString })?.isSelected,
            false
        )
        XCTAssertNil(viewModel.activePreview)
        XCTAssertEqual(
            viewModel.fileCardSnapshots.first(where: { $0.id == fileURLs[1].absoluteString })?.isPreviewable,
            true
        )
    }

    @MainActor
    func testQueueSwipeSelectionAndDeleteSelectedItems() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = ["a.mp4", "b.mp4", "c.mp4", "d.mp4"].map {
            directoryURL.appendingPathComponent($0)
        }
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        viewModel.toggleQueueFileSelection(id: fileURLs[1].absoluteString)
        viewModel.toggleQueueFileSelection(id: fileURLs[2].absoluteString)

        XCTAssertEqual(
            viewModel.fileCardSnapshots.filter(\.isMultiSelected).map(\.fileName),
            ["b.mp4", "c.mp4"]
        )

        viewModel.deleteQueueFile(id: fileURLs[1].absoluteString)

        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["a.mp4", "d.mp4"])
        XCTAssertTrue(viewModel.fileCardSnapshots.allSatisfy { !$0.isMultiSelected })
        XCTAssertNil(viewModel.activePreview)
    }

    @MainActor
    func testQueueCardTapClearsMultiSelectionAndShowsTappedCardDetails() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = ["a.mp4", "b.mp4", "c.mp4"].map {
            directoryURL.appendingPathComponent($0)
        }
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.toggleQueueFileSelection(id: fileURLs[1].absoluteString)
        viewModel.toggleQueueFileSelection(id: fileURLs[2].absoluteString)
        XCTAssertEqual(viewModel.fileCardSnapshots.filter(\.isMultiSelected).count, 2)

        viewModel.selectFileCard(id: fileURLs[2].absoluteString)
        try await waitForCondition(timeout: 2) {
            viewModel.fileCardSnapshots.first(where: { $0.id == fileURLs[2].absoluteString })?.isSelected == true
        }

        XCTAssertTrue(viewModel.fileCardSnapshots.allSatisfy { !$0.isMultiSelected })
        XCTAssertEqual(
            viewModel.fileCardSnapshots.first(where: { $0.id == fileURLs[2].absoluteString })?.videoInfo?.inputSummary,
            "H.264 / AVC / MP4"
        )
    }

    @MainActor
    func testQueueDragHandleMovesSelectedItemsAsGroup() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = ["a.mp4", "b.mp4", "c.mp4", "d.mp4"].map {
            directoryURL.appendingPathComponent($0)
        }
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        viewModel.toggleQueueFileSelection(id: fileURLs[1].absoluteString)
        viewModel.toggleQueueFileSelection(id: fileURLs[2].absoluteString)
        viewModel.moveQueueFiles(
            draggedID: fileURLs[1].absoluteString,
            before: fileURLs[0].absoluteString
        )
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["b.mp4", "c.mp4", "a.mp4", "d.mp4"])

        viewModel.finishQueueMove()
        try await waitForCondition(timeout: 2) {
            viewModel.state.preparedEncodingReview?.source.url == fileURLs[1]
        }

        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["b.mp4", "c.mp4", "a.mp4", "d.mp4"])
        XCTAssertEqual(
            viewModel.fileCardSnapshots.filter(\.isMultiSelected).map(\.fileName),
            ["b.mp4", "c.mp4"]
        )
        XCTAssertNil(viewModel.activePreview)
    }

    @MainActor
    func testQueueDragHandleMovesSelectedItemsDownAsGroup() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURLs = ["a.mp4", "b.mp4", "c.mp4", "d.mp4"].map {
            directoryURL.appendingPathComponent($0)
        }
        for url in fileURLs {
            try Data("source".utf8).write(to: url)
        }

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        viewModel.toggleQueueFileSelection(id: fileURLs[1].absoluteString)
        viewModel.toggleQueueFileSelection(id: fileURLs[2].absoluteString)
        viewModel.moveQueueFiles(
            draggedID: fileURLs[1].absoluteString,
            before: fileURLs[3].absoluteString
        )

        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["a.mp4", "d.mp4", "b.mp4", "c.mp4"])
        XCTAssertEqual(
            viewModel.fileCardSnapshots.filter(\.isMultiSelected).map(\.fileName),
            ["b.mp4", "c.mp4"]
        )
    }

    func testQueueCardGestureControlsAreWiredForSelectionDeleteAndDrag() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let loadedFilesPanelURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/LoadedFilesPanelView.swift")
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let homeViewModelURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeViewModel.swift")
        let homeLayoutMetricsURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeLayoutMetrics.swift")
        let loadedFilesPanelText = try String(contentsOf: loadedFilesPanelURL, encoding: .utf8)
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
        let homeViewModelText = try String(contentsOf: homeViewModelURL, encoding: .utf8)
        let homeLayoutMetricsText = try String(contentsOf: homeLayoutMetricsURL, encoding: .utf8)

        XCTAssertTrue(loadedFilesPanelText.contains("@State private var swipeOffset: CGFloat = 0"))
        XCTAssertTrue(loadedFilesPanelText.contains("@State private var isSwipeGestureActive = false"))
        XCTAssertTrue(loadedFilesPanelText.contains("@State private var isCardPressActive = false"))
        XCTAssertTrue(loadedFilesPanelText.contains("@State private var pressedGroupAnchorID: String?"))
        XCTAssertTrue(loadedFilesPanelText.contains("var onSelect: (String) -> Void"))
        XCTAssertTrue(loadedFilesPanelText.contains("var onSelect: () -> Void"))
        XCTAssertTrue(loadedFilesPanelText.contains("var onPlay: (String) -> Void"))
        XCTAssertTrue(loadedFilesPanelText.contains("var onPlay: () -> Void"))
        XCTAssertFalse(loadedFilesPanelText.contains("Image(systemName: leadingIconName)"))
        XCTAssertFalse(loadedFilesPanelText.contains("line.3.horizontal"))
        XCTAssertFalse(loadedFilesPanelText.contains("private var dragHandle"))
        XCTAssertFalse(loadedFilesPanelText.contains("private var dragHandleIcon"))
        XCTAssertFalse(loadedFilesPanelText.contains("private var leadingIconName"))
        XCTAssertFalse(loadedFilesPanelText.contains("private var leadingIconColor"))
        XCTAssertFalse(loadedFilesPanelText.contains("Move queue item"))
        XCTAssertTrue(loadedFilesPanelText.contains("deleteSwipeTrashOverlay"))
        XCTAssertTrue(loadedFilesPanelText.contains("private var deleteSwipeTrashOverlay: some View"))
        XCTAssertTrue(loadedFilesPanelText.contains("Image(systemName: \"trash.fill\")"))
        XCTAssertTrue(loadedFilesPanelText.contains(".onDrag {"))
        XCTAssertTrue(loadedFilesPanelText.contains("preview: {"))
        XCTAssertTrue(loadedFilesPanelText.contains(".onDrop("))
        XCTAssertTrue(loadedFilesPanelText.contains("QueueFileDropDelegate"))
        XCTAssertTrue(loadedFilesPanelText.contains(".onTapGesture {"))
        XCTAssertTrue(loadedFilesPanelText.contains("guard !isSwipeGestureActive, abs(swipeOffset) < 1 else"))
        XCTAssertTrue(loadedFilesPanelText.contains("onSelect()"))
        XCTAssertTrue(loadedFilesPanelText.contains("DragGesture(minimumDistance: 28"))
        XCTAssertTrue(loadedFilesPanelText.contains(".onChanged { value in"))
        XCTAssertTrue(loadedFilesPanelText.contains(".onEnded { value in"))
        XCTAssertTrue(loadedFilesPanelText.contains("isSwipeGestureActive = true"))
        XCTAssertTrue(loadedFilesPanelText.contains("if horizontal < 0"))
        XCTAssertTrue(loadedFilesPanelText.contains("resetSwipeOffset()"))
        XCTAssertTrue(loadedFilesPanelText.contains("isSwipeGestureActive = false"))
        XCTAssertTrue(loadedFilesPanelText.contains("onToggleSelection()"))
        XCTAssertTrue(loadedFilesPanelText.contains("onDelete()"))
        XCTAssertTrue(loadedFilesPanelText.contains(".onLongPressGesture("))
        XCTAssertTrue(loadedFilesPanelText.contains("isCardPressActive = isPressing"))
        XCTAssertTrue(loadedFilesPanelText.contains("selectedGroupCount"))
        XCTAssertTrue(loadedFilesPanelText.contains("groupStackLayer"))
        XCTAssertTrue(loadedFilesPanelText.contains("withAnimation(.spring(response: 0.28, dampingFraction: 0.84))"))
        XCTAssertTrue(loadedFilesPanelText.contains("infoGrid(info)"))
        XCTAssertTrue(loadedFilesPanelText.contains("tableValue(info.duration)"))
        XCTAssertTrue(loadedFilesPanelText.contains("tableValue(info.frameRate)"))
        XCTAssertTrue(loadedFilesPanelText.contains("tableValue(info.resolution)"))
        XCTAssertTrue(loadedFilesPanelText.contains("tableValue(info.fileSize)"))
        XCTAssertTrue(loadedFilesPanelText.contains("tableValue(inputVideoCodecText(info.inputSummary))"))
        XCTAssertTrue(loadedFilesPanelText.contains("tableValue(info.audio)"))
        XCTAssertFalse(loadedFilesPanelText.contains("codecFlowTable(info)"))
        XCTAssertFalse(loadedFilesPanelText.contains("tableValue(info.outputSummary)"))
        XCTAssertFalse(loadedFilesPanelText.contains("tableValue(info.audioOutputSummary)"))
        XCTAssertFalse(loadedFilesPanelText.contains("Image(systemName: \"arrow.down\")"))
        XCTAssertFalse(loadedFilesPanelText.contains("Text(\"->\")"))
        XCTAssertFalse(loadedFilesPanelText.contains("codecFlowRow(input:"))
        XCTAssertTrue(loadedFilesPanelText.contains("if file.isSelected {\n            return TaptionTheme.accent"))
        XCTAssertFalse(loadedFilesPanelText.contains("Text(\"Codec Info (Video / Audio)\")"))
        XCTAssertFalse(loadedFilesPanelText.contains("infoCell(\"Time\""))
        XCTAssertFalse(loadedFilesPanelText.contains("infoCell(\"FPS\""))
        XCTAssertFalse(loadedFilesPanelText.contains("infoCell(\"Resolution\""))
        XCTAssertFalse(loadedFilesPanelText.contains("infoCell(\"File\""))
        XCTAssertFalse(loadedFilesPanelText.contains("infoCell(\"Video In\""))
        XCTAssertFalse(loadedFilesPanelText.contains("infoCell(\"Video Out\""))
        XCTAssertFalse(loadedFilesPanelText.contains("infoCell(\"Audio In\""))
        XCTAssertFalse(loadedFilesPanelText.contains("infoCell(\"Audio Out\""))
        XCTAssertTrue(loadedFilesPanelText.contains("playBadge"))
        XCTAssertTrue(loadedFilesPanelText.contains("Image(systemName: \"play.fill\")"))
        XCTAssertTrue(loadedFilesPanelText.contains("if canAttemptThumbnail, onPlay != nil"))
        XCTAssertTrue(loadedFilesPanelText.contains("playbackGestureEnabled: thumbnailPlaybackEnabled"))
        XCTAssertTrue(loadedFilesPanelText.contains("playbackGestureEnabled: false"))
        XCTAssertTrue(loadedFilesPanelText.contains("@State private var lastPointerMovementAt = Date.distantPast"))
        XCTAssertTrue(loadedFilesPanelText.contains(".simultaneousGesture(pointerMovementGesture)"))
        XCTAssertTrue(loadedFilesPanelText.contains("guard canStartPlayback, let onPlay else { return }"))
        XCTAssertTrue(loadedFilesPanelText.contains("Date().timeIntervalSince(lastPointerMovementAt) > 0.35"))
        XCTAssertTrue(loadedFilesPanelText.contains("hasMeaningfulPointerMovement(value.translation)"))
        XCTAssertTrue(loadedFilesPanelText.contains("onPlay: onPlay"))
        XCTAssertTrue(loadedFilesPanelText.contains(".onTapGesture(count: 2)"))
        XCTAssertTrue(loadedFilesPanelText.contains(".accessibilityLabel(canAttemptThumbnail && onPlay != nil ? \"Double tap to play preview\" : \"Video thumbnail\")"))
        XCTAssertTrue(loadedFilesPanelText.contains(".accessibilityAction {"))
        XCTAssertTrue(loadedFilesPanelText.contains(".background(TaptionTheme.accent)"))
        XCTAssertFalse(loadedFilesPanelText.contains("Button(action: onPlay)"))
        let cardViewStart = try XCTUnwrap(loadedFilesPanelText.range(of: "private struct EncodingFileCardView: View"))
        let cardContentStart = try XCTUnwrap(loadedFilesPanelText[cardViewStart.lowerBound...].range(of: "private var cardContent: some View"))
        let cardGestureText = String(loadedFilesPanelText[cardViewStart.lowerBound..<cardContentStart.lowerBound])
        XCTAssertTrue(cardGestureText.contains(".onTapGesture"))
        XCTAssertFalse(cardGestureText.contains("onPlay()"))
        let cardContentText = String(loadedFilesPanelText[cardContentStart.lowerBound...])
        XCTAssertFalse(cardContentText.contains("dragHandle"))
        XCTAssertTrue(homeViewText.contains("onSelect: { viewModel.selectFileCard(id: $0) }"))
        XCTAssertTrue(homeViewText.contains("onPlay: { viewModel.openPreviewForFileCard(id: $0) }"))
        XCTAssertTrue(homeViewText.contains("viewModel.toggleQueueFileSelection(id: $0)"))
        XCTAssertTrue(homeViewText.contains("viewModel.deleteQueueFile(id: $0)"))
        XCTAssertTrue(homeViewText.contains("viewModel.moveQueueFiles(draggedID: draggedID, before: targetID)"))
        XCTAssertTrue(homeViewText.contains("viewModel.finishQueueMove()"))
        XCTAssertTrue(homeViewModelText.contains("autoOpenPreviewAfterPrepare: false"))
        XCTAssertTrue(homeViewModelText.contains("autoOpenPreviewAfterPrepare: Bool = false"))
        XCTAssertTrue(homeViewModelText.contains("batch.multiSelectedURLs.removeAll()"))
        XCTAssertTrue(homeViewModelText.contains("standaloneSelectedQueueIDs.removeAll()"))
        XCTAssertTrue(homeViewText.contains("reservesFailureLogArea: reservesFailureLogArea"))
        XCTAssertTrue(homeLayoutMetricsText.contains("init(\n        size: CGSize,\n        reservesFailureLogArea: Bool = false\n    )"))
        XCTAssertTrue(homeLayoutMetricsText.contains("let availableHeight = max(1, size.height)"))
        XCTAssertTrue(homeLayoutMetricsText.contains("let heightScale = min(max(availableHeight / referenceHeight, minimumScale), maximumScale)"))
        XCTAssertFalse(homeLayoutMetricsText.contains("showsNativeAdSlot"))
        XCTAssertTrue(homeLayoutMetricsText.contains("footerAdSeparationHeight = max(8, 12 * contentScale)"))
        XCTAssertTrue(homeLayoutMetricsText.contains("filePanelHeight = max(0, remainingHeight)"))
        XCTAssertFalse(homeLayoutMetricsText.contains("filePanelHeight = max(remainingHeight, minimumFilePanelHeight)"))
    }

    func testHomeLayoutMetricsShrinksQueuePanelUnderVerticalPressure() {
        let portraitMetrics = HomeLayoutMetrics(size: CGSize(width: 393, height: 852))
        let compactLandscapeMetrics = HomeLayoutMetrics(size: CGSize(width: 852, height: 393))

        XCTAssertEqual(compactLandscapeMetrics.canvasHeight, 393, accuracy: 0.1)
        XCTAssertLessThan(compactLandscapeMetrics.contentScale, portraitMetrics.contentScale)
        XCTAssertLessThan(compactLandscapeMetrics.filePanelHeight, portraitMetrics.filePanelHeight)
        XCTAssertLessThanOrEqual(compactLandscapeMetrics.filePanelHeight, 1)
        XCTAssertGreaterThanOrEqual(compactLandscapeMetrics.filePanelHeight, 0)
    }

    func testHomeLayoutMetricsDoesNotReserveMiddleNativeAdSlot() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let homeLayoutMetricsURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeLayoutMetrics.swift")
        let homeViewModelURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeViewModel.swift")
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
        let homeLayoutMetricsText = try String(contentsOf: homeLayoutMetricsURL, encoding: .utf8)
        let homeViewModelText = try String(contentsOf: homeViewModelURL, encoding: .utf8)
        let metrics = HomeLayoutMetrics(size: CGSize(width: 393, height: 852))

        XCTAssertGreaterThan(metrics.footerAdSeparationHeight, 0)
        XCTAssertGreaterThanOrEqual(metrics.filePanelHeight, 0)
        XCTAssertFalse(homeViewText.contains("nativeAdSlot(metrics:"))
        XCTAssertFalse(homeLayoutMetricsText.contains("nativeAdSlotHeight"))
        XCTAssertFalse(homeViewModelText.contains("showsIdleNativeAdSlot"))
        XCTAssertFalse(homeViewModelText.contains("showsCompletedNativeAdSlot"))
    }

    func testBatterySettingsSheetContainsEncodingOptimizationSlider() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuSheetURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeMenuSheetView.swift")
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let menuSheetText = try String(contentsOf: menuSheetURL, encoding: .utf8)
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)

        XCTAssertTrue(menuSheetText.contains("Encoding Optimization"))
        XCTAssertTrue(menuSheetText.contains("TaptionEncodingOptimizationProfile.allCases"))
        XCTAssertTrue(menuSheetText.contains("updateOptimizationProfile"))
        XCTAssertTrue(menuSheetText.contains("settings.optimizationProfile.menuTitle"))
        XCTAssertTrue(homeViewText.contains("onOptimizationProfileChanged: { viewModel.selectEncodingOptimizationProfile($0) }"))
    }

    func testBundledCodecBenchmarkScriptCoversPlaybackEncodingAndProfiles() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scriptURL = rootURL.appendingPathComponent("Scripts/benchmark_bundled_codecs_simulator.sh")
        let homeViewText = try String(
            contentsOf: rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift"),
            encoding: .utf8
        )
        let homeViewModelText = try String(
            contentsOf: rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeViewModel.swift"),
            encoding: .utf8
        )
        let scriptText = try String(contentsOf: scriptURL, encoding: .utf8)

        XCTAssertTrue(scriptText.contains("--mode MODE"))
        XCTAssertTrue(scriptText.contains("TAPTION_AUTO_START_PIP"))
        XCTAssertTrue(scriptText.contains("TAPTION_AUTO_START_ENCODING"))
        XCTAssertTrue(scriptText.contains("TAPTION_CODEC_PROBE_PROFILE"))
        XCTAssertTrue(scriptText.contains("TAPTION_DEBUG_BENCHMARK_ALLOW_FREE_ENCODING"))
        XCTAssertTrue(scriptText.contains("Codec benchmark probe completed"))
        XCTAssertTrue(scriptText.contains("verify_bundled_test_videos.sh"))
        XCTAssertTrue(homeViewText.contains("applyDebugEncodingOptimizationProfileIfRequested()"))
        XCTAssertTrue(homeViewText.contains("debugAutoStartPictureInPictureRequested"))
        XCTAssertTrue(homeViewModelText.contains("openDebugFileAndAutoOpenPreview"))
        XCTAssertTrue(homeViewModelText.contains("Debug benchmark encoding start bypassed Star charge"))
        XCTAssertTrue(homeViewModelText.contains("Codec benchmark probe completed"))
    }

    @MainActor
    func testSingleFileImportQueuesWithoutAutoOpeningPreview() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("single.mp4")
        try Data("source".utf8).write(to: sourceURL)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertNil(viewModel.activePreview)
        XCTAssertEqual(viewModel.fileCardSnapshots.count, 1)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.fileName, "single.mp4")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.sourceKind, .files)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Ready")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.isPreviewable, true)

        viewModel.openPreviewForFileCard(id: "single.mp4")
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == sourceURL
        }
        XCTAssertEqual(viewModel.activePreview?.sourceURL, sourceURL)
        XCTAssertEqual(viewModel.activePreview?.displayName, "single.mp4")
    }

    @MainActor
    func testAlbumImportQueuesWithoutAutoOpeningPreview() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("album.mov")
        try Data("source".utf8).write(to: sourceURL)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.startPhotosFlow(url: sourceURL, displayName: "Album Clip.mov")
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertNil(viewModel.activePreview)
        XCTAssertEqual(viewModel.fileCardSnapshots.count, 1)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.fileName, "Album Clip.mov")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.sourceKind, .photos)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Ready")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.isPreviewable, true)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.thumbnailSourceURL, sourceURL)

        viewModel.openPreviewForFileCard(id: "Album Clip.mov")
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == sourceURL
        }
        XCTAssertEqual(viewModel.activePreview?.displayName, "Album Clip.mov")
    }

    @MainActor
    func testExternalFileOpenQueuesWithoutAutoOpeningPreview() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("external.avi")
        try Data("source".utf8).write(to: sourceURL)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .mpeg4Visual))
            )
        )

        viewModel.openExternalPlayerFile(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertNil(viewModel.activePreview)
        XCTAssertEqual(viewModel.fileCardSnapshots.count, 1)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.fileName, "external.avi")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.sourceKind, .files)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.statusText, "Ready")
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.isPreviewable, true)

        viewModel.openPreviewForFileCard(id: "external.avi")
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == sourceURL
        }
        XCTAssertEqual(viewModel.activePreview?.sourceURL, sourceURL)
        XCTAssertEqual(viewModel.activePreview?.displayName, "external.avi")
    }

    @MainActor
    func testLegacyPreviewCodecCanOpenPreview() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("lossless.avi")
        try Data("source".utf8).write(to: sourceURL)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .losslessJPEG))
            )
        )

        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertNil(viewModel.activePreview)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.isPreviewable, true)

        viewModel.openPreviewForFileCard(id: "lossless.avi")
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == sourceURL
        }
        XCTAssertEqual(viewModel.activePreview?.displayName, "lossless.avi")
    }

    @MainActor
    func testLegacyAndProResPreviewCodecsStayPlayableInQueue() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let previewInputs: [(filename: String, codec: TaptionVideoCodec)] = [
            ("Snow.avi", .snow),
            ("R210.avi", .r210),
            ("R10K.mov", .r10k),
            ("Microsoft RLE.avi", .microsoftRLE),
            ("Lossless JPEG.avi", .losslessJPEG),
            ("Apple ProRes.mov", .proRes)
        ]
        let fileURLs = try previewInputs.map { input in
            let url = directoryURL.appendingPathComponent(input.filename)
            try Data("source".utf8).write(to: url)
            return url
        }
        let assetsByName = Dictionary(
            uniqueKeysWithValues: previewInputs.map { input in
                (input.filename, makeAsset(sourceCodec: input.codec))
            }
        )

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: URLMappedMediaInspector(
                    assetsByLastPathComponent: assetsByName,
                    fallbackAsset: makeAsset(sourceCodec: .h264)
                )
            )
        )

        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)
        try await waitForCondition(timeout: 2) {
            viewModel.fileCardSnapshots.count == previewInputs.count
        }

        for input in previewInputs {
            let snapshot = try XCTUnwrap(
                viewModel.fileCardSnapshots.first { $0.fileName == input.filename }
            )
            XCTAssertTrue(snapshot.isPreviewable, "\(input.filename) should allow queue preview playback.")
            XCTAssertEqual(snapshot.thumbnailSourceURL?.lastPathComponent, input.filename)
        }

        let firstURL = try XCTUnwrap(fileURLs.first)
        viewModel.openPreviewForFileCard(id: firstURL.absoluteString)
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == firstURL
        }
        XCTAssertEqual(viewModel.activePreview?.displayName, firstURL.lastPathComponent)
    }

    @MainActor
    func testQueuePreviewPlaylistNavigationMovesBetweenBatchItems() async throws {
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

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.startFilesFlow(urls: fileURLs)
        try await waitForReadyToStartState(in: viewModel)

        viewModel.openPreviewForFileCard(id: fileURLs[1].absoluteString)
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == fileURLs[1]
        }

        XCTAssertEqual(viewModel.activePreview?.playlist?.positionText, "2 / 3")
        XCTAssertEqual(viewModel.activePreview?.playlist?.previousName, "a.mp4")
        XCTAssertEqual(viewModel.activePreview?.playlist?.nextName, "c.mp4")

        viewModel.openNextPreview()
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == fileURLs[2]
        }
        XCTAssertEqual(viewModel.activePreview?.playlist?.positionText, "3 / 3")
        XCTAssertEqual(viewModel.activePreview?.playlist?.hasNext, false)
        XCTAssertEqual(viewModel.activePreview?.playlist?.previousName, "b.mp4")

        viewModel.openPreviousPreview()
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == fileURLs[1]
        }
        XCTAssertEqual(viewModel.activePreview?.playlist?.positionText, "2 / 3")
    }

    @MainActor
    func testQueuePreviewPlaylistNavigationSkipsUnencodableItems() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let supportedFirstURL = directoryURL.appendingPathComponent("a.mp4")
        let unsupportedURL = directoryURL.appendingPathComponent("b.mp4")
        let supportedNextURL = directoryURL.appendingPathComponent("c.mp4")
        for url in [supportedFirstURL, unsupportedURL, supportedNextURL] {
            try Data("source".utf8).write(to: url)
        }

        let unsupportedAsset = TaptionVideoAsset(
            displayName: "b.mp4",
            location: TaptionVideoAssetLocation(kind: .file, url: unsupportedURL),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .unknown,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080)
            )
        )
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: URLMappedMediaInspector(
                    assetsByLastPathComponent: [
                        supportedFirstURL.lastPathComponent: makeAsset(sourceCodec: .h264),
                        unsupportedURL.lastPathComponent: unsupportedAsset,
                        supportedNextURL.lastPathComponent: makeAsset(sourceCodec: .vp8)
                    ],
                    fallbackAsset: makeAsset(sourceCodec: .h264)
                )
            )
        )

        viewModel.startFolderFlow(url: directoryURL)
        XCTAssertEqual(viewModel.folderPreviewContext?.fileCount, 3)
        viewModel.importFolderPreviewBatch()
        try await waitForReadyToStartState(in: viewModel)
        XCTAssertNil(viewModel.activePreview)

        viewModel.openPreviewForFileCard(id: supportedFirstURL.absoluteString)
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == supportedFirstURL
        }
        XCTAssertEqual(viewModel.activePreview?.playlist?.positionText, "1 / 2")
        XCTAssertEqual(viewModel.activePreview?.playlist?.nextName, "c.mp4")

        viewModel.openNextPreview()
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == supportedNextURL
        }
        XCTAssertEqual(viewModel.activePreview?.playlist?.positionText, "2 / 2")
        XCTAssertEqual(viewModel.activePreview?.playlist?.previousName, "a.mp4")
    }

    @MainActor
    func testQueuePreviewPlaylistNavigationSkipsEnabledNonPreviewableItems() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let supportedFirstURL = directoryURL.appendingPathComponent("a.mp4")
        let nonPreviewableURL = directoryURL.appendingPathComponent("b.mp4")
        let supportedNextURL = directoryURL.appendingPathComponent("c.mp4")
        for url in [supportedFirstURL, nonPreviewableURL, supportedNextURL] {
            try Data("source".utf8).write(to: url)
        }

        let enabledNonPreviewableAsset = TaptionVideoAsset(
            displayName: "b.mp4",
            location: TaptionVideoAssetLocation(kind: .file, url: nonPreviewableURL),
            container: .unknown,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .h264,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080)
            )
        )
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: URLMappedMediaInspector(
                    assetsByLastPathComponent: [
                        supportedFirstURL.lastPathComponent: makeAsset(sourceCodec: .h264),
                        nonPreviewableURL.lastPathComponent: enabledNonPreviewableAsset,
                        supportedNextURL.lastPathComponent: makeAsset(sourceCodec: .vp8)
                    ],
                    fallbackAsset: makeAsset(sourceCodec: .h264)
                )
            )
        )

        viewModel.startFolderFlow(url: directoryURL)
        XCTAssertEqual(viewModel.folderPreviewContext?.fileCount, 3)
        viewModel.importFolderPreviewBatch()
        try await waitForReadyToStartState(in: viewModel)

        let middleSnapshot = viewModel.fileCardSnapshots.first { $0.fileName == nonPreviewableURL.lastPathComponent }
        XCTAssertEqual(middleSnapshot?.isEnabled, true)
        XCTAssertEqual(middleSnapshot?.isPreviewable, false)
        XCTAssertNil(viewModel.activePreview)

        viewModel.openPreviewForFileCard(id: supportedFirstURL.absoluteString)
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == supportedFirstURL
        }
        XCTAssertEqual(viewModel.activePreview?.playlist?.positionText, "1 / 2")
        XCTAssertEqual(viewModel.activePreview?.playlist?.nextName, "c.mp4")

        viewModel.openNextPreview()
        try await waitForCondition(timeout: 2) {
            viewModel.activePreview?.sourceURL == supportedNextURL
        }
        XCTAssertEqual(viewModel.activePreview?.playlist?.positionText, "2 / 2")
        XCTAssertEqual(viewModel.activePreview?.playlist?.previousName, "a.mp4")
    }

    @MainActor
    func testUnsupportedQueueCardTapDoesNotOpenPreview() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let supportedURL = directoryURL.appendingPathComponent("a.mp4")
        let sourceURL = directoryURL.appendingPathComponent("unsupported.mp4")
        try Data("source".utf8).write(to: supportedURL)
        try Data("source".utf8).write(to: sourceURL)

        let unsupportedAsset = TaptionVideoAsset(
            displayName: "unsupported.mp4",
            location: TaptionVideoAssetLocation(kind: .file, url: sourceURL),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .unknown,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080)
            )
        )
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: URLMappedMediaInspector(
                    assetsByLastPathComponent: [
                        supportedURL.lastPathComponent: makeAsset(sourceCodec: .h264),
                        sourceURL.lastPathComponent: unsupportedAsset
                    ],
                    fallbackAsset: makeAsset(sourceCodec: .h264)
                )
            )
        )

        viewModel.startFilesFlow(urls: [supportedURL, sourceURL])
        try await waitForReadyToStartState(in: viewModel)
        XCTAssertNil(viewModel.activePreview)
        viewModel.openPreviewForFileCard(id: sourceURL.absoluteString)

        try await waitForCondition(timeout: 2) {
            viewModel.fileCardSnapshots.first(where: { $0.id == sourceURL.absoluteString })?.isEnabled == false
        }

        XCTAssertNil(viewModel.activePreview)
        XCTAssertEqual(
            viewModel.fileCardSnapshots.first(where: { $0.id == sourceURL.absoluteString })?.isEnabled,
            false
        )
        XCTAssertEqual(
            viewModel.fileCardSnapshots.first(where: { $0.id == sourceURL.absoluteString })?.isPreviewable,
            false
        )
        XCTAssertEqual(
            viewModel.fileCardSnapshots.first(where: { $0.id == sourceURL.absoluteString })?.thumbnailSourceURL,
            sourceURL
        )
    }

    @MainActor
    func testPreviewClosesOnResetSourceChangeAndEncodingStart() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let firstURL = directoryURL.appendingPathComponent("first.mp4")
        let secondURL = directoryURL.appendingPathComponent("second.mp4")
        try Data("source".utf8).write(to: firstURL)
        try Data("source".utf8).write(to: secondURL)

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                starWalletStore: walletStore
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(url: firstURL)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.openPreviewForFileCard(id: firstURL.lastPathComponent)
        XCTAssertEqual(viewModel.activePreview?.sourceURL, firstURL)

        viewModel.startFilesFlow(url: secondURL)
        XCTAssertNil(viewModel.activePreview)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.openPreviewForFileCard(id: secondURL.lastPathComponent)
        XCTAssertEqual(viewModel.activePreview?.sourceURL, secondURL)

        viewModel.startPreparedEncoding()
        XCTAssertNil(viewModel.activePreview)
        try await waitForCondition(timeout: 2) {
            if viewModel.state.pendingSaveJob != nil {
                return true
            }
            if case .completed = viewModel.state {
                return true
            }
            return false
        }

        viewModel.reset()
        XCTAssertNil(viewModel.activePreview)
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
        private var lastWalletSnapshot: StarWalletSnapshot?
        private var initialBonusGranted = false

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

        func loadLastWalletSnapshot() throws -> StarWalletSnapshot? {
            lastWalletSnapshot
        }

        func saveLastWalletSnapshot(_ snapshot: StarWalletSnapshot) throws {
            lastWalletSnapshot = snapshot
        }

        func loadInitialBonusGranted() throws -> Bool {
            initialBonusGranted
        }

        func saveInitialBonusGranted() throws {
            initialBonusGranted = true
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

    private actor RetryingRewardedAdProvider: RewardedAdProviding {
        private var currentState: AdLoadState
        private var retryCallCount = 0
        private var showCallCount = 0

        init(initialState: AdLoadState = .unavailable) {
            self.currentState = initialState
        }

        func currentRewardedState() async -> AdLoadState {
            currentState
        }

        func preloadRewardedAd() async -> AdLoadState {
            currentState
        }

        func retryRewardedAdNow() async -> AdLoadState {
            retryCallCount += 1
            currentState = .ready
            return currentState
        }

        func showRewardedAd() async -> RewardedAdShowResult {
            showCallCount += 1
            return currentState == .ready ? .earnedReward : .unavailable
        }

        func recordedRetryCallCount() -> Int {
            retryCallCount
        }

        func recordedShowCallCount() -> Int {
            showCallCount
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

    private final class MutableBatteryPowerMonitor: BatteryPowerMonitoring {
        var snapshot: BatteryEncodingPowerSnapshot

        init(snapshot: BatteryEncodingPowerSnapshot) {
            self.snapshot = snapshot
        }

        var currentSnapshot: BatteryEncodingPowerSnapshot {
            snapshot
        }
    }

    private struct PowerDisconnectingEncoderService: EncoderServicing {
        var outputData: Data
        var batteryMonitor: MutableBatteryPowerMonitor

        func encode(
            plan: TaptionEncodingPlan,
            progress: @escaping (TaptionEncodingProgress) -> Void
        ) async throws -> TaptionEncodingResult {
            guard let temporaryOutputURL = plan.temporaryOutputURL else {
                throw TaptionVideoCoreError.missingTemporaryOutputURL
            }

            progress(TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0))
            await MainActor.run {
                batteryMonitor.snapshot = BatteryEncodingPowerSnapshot(
                    batteryPercent: 80,
                    isPowerConnected: false,
                    isPowerStateKnown: true
                )
            }
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

    private struct BatteryDroppingEncoderService: EncoderServicing {
        var outputData: Data
        var batteryMonitor: MutableBatteryPowerMonitor

        func encode(
            plan: TaptionEncodingPlan,
            progress: @escaping (TaptionEncodingProgress) -> Void
        ) async throws -> TaptionEncodingResult {
            guard let temporaryOutputURL = plan.temporaryOutputURL else {
                throw TaptionVideoCoreError.missingTemporaryOutputURL
            }

            progress(TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0))
            await MainActor.run {
                batteryMonitor.snapshot = BatteryEncodingPowerSnapshot(
                    batteryPercent: 29,
                    isPowerConnected: false,
                    isPowerStateKnown: true
                )
            }
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

    private struct URLMappedMediaInspector: MediaInspecting {
        var assetsByLastPathComponent: [String: TaptionVideoAsset]
        var fallbackAsset: TaptionVideoAsset

        func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
            var inspectedAsset = assetsByLastPathComponent[url.lastPathComponent] ?? fallbackAsset
            inspectedAsset.displayName = url.lastPathComponent
            inspectedAsset.location = TaptionVideoAssetLocation(kind: .file, url: url)
            return inspectedAsset
        }
    }

    private final class CountingMediaInspector: MediaInspecting {
        private let queue = DispatchQueue(label: "com.taption.encoder.tests.counting-media-inspector")
        private let asset: TaptionVideoAsset
        private var inspectionCountStorage = 0

        init(asset: TaptionVideoAsset) {
            self.asset = asset
        }

        var inspectionCount: Int {
            queue.sync { inspectionCountStorage }
        }

        func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
            queue.sync {
                inspectionCountStorage += 1
            }

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

    private func testMediaFingerprint(for url: URL) throws -> TaptionMediaFingerprint {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ])
        return TaptionMediaFingerprint(
            fileSize: values.fileSize.map(Int64.init),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate
        )
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
        fileByteCount: Int
    ) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: Int64(fileByteCount),
            countStyle: .file
        )
        return [
            "File: \(url.lastPathComponent)",
            "Size: \(size)"
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
            nativeAdProvider: FakeNativeAdProvider(),
            rewardedAdProvider: rewardedAdProvider,
            starWalletStore: starWalletStore,
            starEarningService: starEarningService,
            sessionEndAdProvider: sessionEndAdProvider,
            backgroundCoordinator: FakeBackgroundEncodingCoordinator(),
            projectDocumentStore: FakeProjectFileStore()
        )
    }

    func testEncodingResourceMonitorMathCalculatesPerCoreCPUUsage() {
        let previous = [
            EncodingCPUCoreTicks(user: 10, system: 20, idle: 70, nice: 0),
            EncodingCPUCoreTicks(user: 5, system: 5, idle: 90, nice: 0)
        ]
        let current = [
            EncodingCPUCoreTicks(user: 40, system: 30, idle: 130, nice: 0),
            EncodingCPUCoreTicks(user: 5, system: 15, idle: 180, nice: 0)
        ]

        let usages = EncodingResourceMonitorMath.cpuUsages(
            previous: previous,
            current: current
        )

        XCTAssertEqual(usages.count, 2)
        XCTAssertEqual(usages[0].index, 0)
        XCTAssertEqual(usages[0].percent, 40, accuracy: 0.01)
        XCTAssertEqual(usages[1].index, 1)
        XCTAssertEqual(usages[1].percent, 10, accuracy: 0.01)
    }

    func testEncodingResourceUsageSnapshotFormatsMemory() {
        let snapshot = EncodingResourceUsageSnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            cpuCores: [
                EncodingCPUCoreUsage(index: 0, percent: 12.4),
                EncodingCPUCoreUsage(index: 1, percent: 88.8)
            ],
            appMemoryBytes: 512 * 1_024 * 1_024,
            totalPhysicalMemoryBytes: 4 * 1_024 * 1_024 * 1_024
        )

        XCTAssertEqual(snapshot.cpuCores[0].percentText, "12%")
        XCTAssertEqual(snapshot.cpuCores[1].percentText, "89%")
        XCTAssertEqual(snapshot.memoryPercentText, "13%")
        XCTAssertTrue(snapshot.memoryUsageText.contains("512"))
    }

    func testEncodingRuntimeWarningEvaluatorCombinesThermalBatteryMemoryAndRuntimeWarnings() {
        let snapshot = EncodingResourceUsageSnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            cpuCores: [],
            appMemoryBytes: 920 * 1_024 * 1_024,
            totalPhysicalMemoryBytes: 1_024 * 1_024 * 1_024,
            thermalState: .serious
        )

        let warnings = EncodingRuntimeWarningEvaluator.warnings(
            resourceUsage: snapshot,
            powerSnapshot: EncodingRuntimePowerSnapshot(
                batteryPercent: 34,
                isPowerConnected: false,
                isPowerStateKnown: true
            ),
            batteryLimitPercent: 30,
            estimatedRemainingTime: 40 * 60,
            optimizationProfile: .performance
        )
        let kinds = warnings.map(\.kind)

        XCTAssertTrue(kinds.contains(.thermal))
        XCTAssertTrue(kinds.contains(.memory))
        XCTAssertTrue(kinds.contains(.battery))
        XCTAssertTrue(kinds.contains(.runtime))
        XCTAssertTrue(warnings.contains { $0.title == "Device Getting Hot" })
        XCTAssertTrue(warnings.contains { $0.title == "App Memory High" })
        XCTAssertTrue(warnings.contains { $0.title == "Battery Near Limit" })
        XCTAssertTrue(warnings.contains { $0.title == "Long Runtime Estimate" })
    }

    func testEncodingRuntimeWarningEvaluatorTreatsCriticalThermalAndMemoryAsCritical() {
        let snapshot = EncodingResourceUsageSnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            cpuCores: [],
            appMemoryBytes: 950 * 1_024 * 1_024,
            totalPhysicalMemoryBytes: 1_024 * 1_024 * 1_024,
            thermalState: .critical
        )

        let warnings = EncodingRuntimeWarningEvaluator.warnings(resourceUsage: snapshot)

        XCTAssertTrue(warnings.contains {
            $0.kind == .thermal && $0.severity == .critical
        })
        XCTAssertTrue(warnings.contains {
            $0.kind == .memory && $0.severity == .critical
        })
    }

    func testEncodingRuntimeWarningEvaluatorSkipsBatteryWarningWhenPowerStateIsUnknown() {
        let snapshot = EncodingResourceUsageSnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            cpuCores: [],
            appMemoryBytes: nil,
            totalPhysicalMemoryBytes: 1_024 * 1_024 * 1_024
        )

        let warnings = EncodingRuntimeWarningEvaluator.warnings(
            resourceUsage: snapshot,
            powerSnapshot: EncodingRuntimePowerSnapshot(
                batteryPercent: 12,
                isPowerConnected: false,
                isPowerStateKnown: false
            ),
            batteryLimitPercent: 30,
            estimatedRemainingTime: 40 * 60
        )

        XCTAssertFalse(warnings.contains { $0.kind == .battery })
    }

    func testEncodingProgressViewDisplaysResourceUsageWidgetDuringEncodingOnly() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let progressViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Encoding/EncodingProgressView.swift")
        let source = try String(contentsOf: progressViewURL, encoding: .utf8)

        XCTAssertTrue(source.contains("EncodingResourceUsageWidget"))
        XCTAssertTrue(source.contains("state.progress?.resourceUsage"))
        XCTAssertTrue(source.contains("state.canCancel"))
        XCTAssertTrue(source.contains("Device CPU"))
        XCTAssertTrue(source.contains("App Memory"))
        XCTAssertTrue(source.contains("Runtime Warnings"))
        XCTAssertTrue(source.contains("resourceUsage.runtimeWarnings"))
    }

    func testHomeViewModelStartsAndStopsResourceMonitoringAroundEncoding() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewModelURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeViewModel.swift")
        let source = try String(contentsOf: viewModelURL, encoding: .utf8)

        XCTAssertTrue(source.contains("private func startResourceMonitoring(sampleIntervalNanoseconds: UInt64)"))
        XCTAssertTrue(source.contains("optimizationProfile.resourceSampleIntervalNanoseconds"))
        XCTAssertTrue(source.contains("Task(priority: taskPriority(for: optimizationProfile))"))
        XCTAssertTrue(source.contains("private func stopResourceMonitoring()"))
        XCTAssertTrue(source.contains("latestResourceUsage"))
        XCTAssertTrue(source.contains("resourceUsage: latestResourceUsage"))
        XCTAssertTrue(source.contains("runtimeWarningResourceUsage"))
        XCTAssertTrue(source.contains("EncodingRuntimeWarningEvaluator.warnings"))
        XCTAssertTrue(source.contains("stopResourceMonitoring()"))
    }

    func testAppEnvironmentInjectsEncodingResourceMonitor() {
        XCTAssertTrue(AppEnvironment.phase0.resourceMonitor is SystemEncodingResourceMonitor)
    }

    @MainActor
    func testEncodingProgressCoalescerEmitsFirstStageThresholdAndFinalProgress() {
        var coalescer = EncodingProgressCoalescer(
            minimumFractionDelta: 0.01,
            minimumTimeInterval: 0.5
        )

        XCTAssertTrue(coalescer.shouldEmit(
            TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0),
            now: 0
        ))
        XCTAssertFalse(coalescer.shouldEmit(
            TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0.005),
            now: 0.1
        ))
        XCTAssertTrue(coalescer.shouldEmit(
            TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.005),
            now: 0.2
        ))
        XCTAssertFalse(coalescer.shouldEmit(
            TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.012),
            now: 0.3
        ))
        XCTAssertTrue(coalescer.shouldEmit(
            TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.016),
            now: 0.4
        ))
        XCTAssertTrue(coalescer.shouldEmit(
            TaptionEncodingProgress(stage: .waitingForSaveGate, fractionCompleted: 1),
            now: 0.45
        ))
    }

    func testEncodingProgressCoalescerEmitsTimedProgressWhenFractionDeltaIsSmall() {
        var coalescer = EncodingProgressCoalescer(
            minimumFractionDelta: 0.10,
            minimumTimeInterval: 0.5
        )

        XCTAssertTrue(coalescer.shouldEmit(
            TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.10),
            now: 1.0
        ))
        XCTAssertFalse(coalescer.shouldEmit(
            TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.12),
            now: 1.2
        ))
        XCTAssertTrue(coalescer.shouldEmit(
            TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.13),
            now: 1.6
        ))
    }

    func testEncodingProgressEmitterTracksObservedAndEmittedCounts() {
        var received: [TaptionEncodingProgress] = []
        let emitter = EncodingProgressEmitter(
            coalescer: EncodingProgressCoalescer(
                minimumFractionDelta: 0.10,
                minimumTimeInterval: 100
            )
        ) { progress in
            received.append(progress)
        }

        emitter.submit(TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.10))
        emitter.submit(TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.12))
        emitter.submit(TaptionEncodingProgress(stage: .waitingForSaveGate, fractionCompleted: 1))

        XCTAssertEqual(received.map(\.stage), [.encoding, .waitingForSaveGate])
        XCTAssertEqual(emitter.stats, EncodingProgressEmitterStats(observedCount: 3, emittedCount: 2))
    }

    func testInspectedMediaCacheReusesOnlyMatchingFingerprints() {
        let url = URL(fileURLWithPath: "/tmp/source.mp4")
        let originalFingerprint = TaptionMediaFingerprint(
            fileSize: 1_024,
            creationDate: Date(timeIntervalSince1970: 1),
            modificationDate: Date(timeIntervalSince1970: 2)
        )
        let changedFingerprint = TaptionMediaFingerprint(
            fileSize: 2_048,
            creationDate: Date(timeIntervalSince1970: 1),
            modificationDate: Date(timeIntervalSince1970: 3)
        )
        let asset = TaptionVideoAsset(
            displayName: "source.mp4",
            location: TaptionVideoAssetLocation(kind: .file, url: url),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .h264,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080)
            ),
            fingerprint: originalFingerprint
        )
        var cache = TaptionInspectedMediaCache()

        cache.store(asset, for: url)

        XCTAssertEqual(cache.asset(for: url, currentFingerprint: originalFingerprint), asset)
        XCTAssertNil(cache.asset(for: url, currentFingerprint: changedFingerprint))
    }

    @MainActor
    private func waitForPendingSaveDestinationPrompt(
        in viewModel: HomeViewModel,
        timeout: TimeInterval = 2
    ) async throws {
        try await waitForCondition(timeout: timeout) {
            if let prompt = viewModel.multiFileEncodingPrompt {
                viewModel.chooseSeparateEncodingForMultiFilePrompt(prompt: prompt)
            }
            return viewModel.pendingSaveDestinationPrompt != nil
        }
    }

    @MainActor
    private func chooseFolderForPendingSaveDestination(
        in viewModel: HomeViewModel,
        timeout: TimeInterval = 2
    ) async throws {
        try await waitForPendingSaveDestinationPrompt(in: viewModel, timeout: timeout)
        let prompt = try XCTUnwrap(viewModel.pendingSaveDestinationPrompt)
        viewModel.chooseFolderForPendingSave(prompt: prompt)
    }

    @MainActor
    private func waitForCompletedSave(
        in viewModel: HomeViewModel,
        timeout: TimeInterval = 2
    ) async throws {
        try await waitForCondition(timeout: timeout) {
            if let prompt = viewModel.multiFileEncodingPrompt {
                viewModel.chooseSeparateEncodingForMultiFilePrompt(prompt: prompt)
            }
            if let prompt = viewModel.pendingSaveDestinationPrompt {
                viewModel.chooseFolderForPendingSave(prompt: prompt)
            }
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

    private func makeH261ToHEVCCommandPlan(
        outputURL: URL = URL(fileURLWithPath: "/tmp/output.mp4")
    ) throws -> SW_FFmpegCommandPlan {
        let route = TaptionCodecRoute(sourceCodec: .h261, outputCodec: .hevc)
        return try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: URL(fileURLWithPath: "/tmp/input.avi"),
                outputURL: outputURL,
                route: route,
                options: .preservingSource(outputCodec: .hevc, container: .mp4)
            )
        )
    }

    private func temporaryTestURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    }

    private func bundledTestVideosURL() -> URL {
        let sourceTreeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TaptionEncoder/TestVideos", isDirectory: true)
        #if targetEnvironment(simulator)
        if FileManager.default.fileExists(atPath: sourceTreeURL.path) {
            return sourceTreeURL
        }
        #endif

        if let appBundleURL = Bundle.main.url(forResource: "TestVideos", withExtension: nil) {
            return appBundleURL
        }

        if let appResourceURL = Bundle.main.resourceURL {
            let fallbackURL = appResourceURL.appendingPathComponent("TestVideos", isDirectory: true)
            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                return fallbackURL
            }
        }

        let testBundle = Bundle(for: CodecRoutePlannerTests.self)
        if let bundledURL = testBundle.url(forResource: "TestVideos", withExtension: nil) {
            return bundledURL
        }

        if let resourceURL = testBundle.resourceURL {
            let fallbackURL = resourceURL.appendingPathComponent("TestVideos", isDirectory: true)
            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                return fallbackURL
            }
        }

        return sourceTreeURL
    }

    private func projectObjectBlock(id: String, label: String, in projectText: String) -> String? {
        let needle = "\t\t\(id) /* \(label) */ = {"
        guard let start = projectText.range(of: needle),
              let end = projectText[start.upperBound...].range(of: "\n\t\t};") else {
            return nil
        }
        return String(projectText[start.lowerBound..<end.upperBound])
    }

    private func filteredBundledAvailableNowSampleFilenames() -> [String] {
        let filenames = bundledAvailableNowSampleCodecExpectations().map(\.0)
        guard let sampleFilter = ProcessInfo.processInfo.environment["TAPTION_SAMPLE_FILTER"],
              sampleFilter.isEmpty == false else {
            return filenames
        }
        let filteredFilenames = filenames.filter { $0 == sampleFilter }
        XCTAssertFalse(filteredFilenames.isEmpty, sampleFilter)
        return filteredFilenames
    }

    private func visiblePixelMetrics(fromPNGData data: Data) throws -> (nonBlackRatio: Double, standardDeviation: Double) {
        guard let image = UIImage(data: data)?.cgImage else {
            throw NSError(
                domain: "TaptionEncoderTests",
                code: -1202,
                userInfo: [NSLocalizedDescriptionKey: "Snapshot image data could not be decoded."]
            )
        }

        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(
                domain: "TaptionEncoderTests",
                code: -1203,
                userInfo: [NSLocalizedDescriptionKey: "Snapshot pixel buffer could not be created."]
            )
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var channelCount = 0
        var nonBlackCount = 0
        var sum = 0.0
        var squaredSum = 0.0

        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            for channelOffset in 0..<3 {
                let value = Double(pixels[offset + channelOffset])
                if value > 8 {
                    nonBlackCount += 1
                }
                sum += value
                squaredSum += value * value
                channelCount += 1
            }
        }

        let mean = sum / Double(channelCount)
        let variance = max(0, squaredSum / Double(channelCount) - mean * mean)
        return (
            nonBlackRatio: Double(nonBlackCount) / Double(channelCount),
            standardDeviation: sqrt(variance)
        )
    }

    @MainActor
    private func waitForPreviewSnapshot(
        player: Player,
        snapshotURL: URL,
        timeout: TimeInterval
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        while Date() < deadline {
            try? FileManager.default.removeItem(at: snapshotURL)
            do {
                try player.takeSnapshot(to: snapshotURL.path, width: 160, height: 0)
                let data = try Data(contentsOf: snapshotURL)
                if data.count > 128,
                   let image = UIImage(data: data),
                   image.size.width > 0,
                   image.size.height > 0 {
                    return
                }
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        throw NSError(
            domain: "TaptionEncoderTests",
            code: -1201,
            userInfo: [
                NSLocalizedDescriptionKey: "Preview snapshot was not produced before timeout. Last error: \(String(describing: lastError))"
            ]
        )
    }

    private func bundledAvailableNowSampleCodecExpectations() -> [(String, TaptionVideoCodec)] {
        [
            ("AV1.mp4", .av1),
            ("VP9.webm", .vp9),
            ("VP8.webm", .vp8),
            ("MPEG-1.mpg", .mpeg1),
            ("MPEG-2.mpg", .mpeg2),
            ("MPEG-4 Visual.mov", .mpeg4Visual),
            ("H.263.3gp", .h263),
            ("AMR-WB H.263.3gp", .h263),
            ("H.261.h261", .h261),
            ("Flash Video.flv", .flashVideo),
            ("Microsoft MPEG-4 V2.avi", .microsoftMPEG4V2),
            ("Microsoft MPEG-4 V3.wmv", .microsoftMPEG4V3),
            ("Motion JPEG.avi", .motionJPEG),
            ("JPEG 2000.mov", .jpeg2000),
            ("JPEG-LS.avi", .jpegLS),
            ("Lossless JPEG.avi", .losslessJPEG),
            ("Apple Animation.mov", .animation),
            ("Cinepak.mov", .cinepak),
            ("Sorenson Video.mov", .sorensonVideo),
            ("Sorenson Video 3.mov", .sorensonVideo3),
            ("QuickTime Video.mov", .quickTimeVideo),
            ("Theora.ogv", .theora),
            ("RealVideo 1.0.rm", .realVideo1),
            ("RealVideo.rm", .realVideo),
            ("RoQ Video.roq", .roqVideo),
            ("Windows Media Video.wmv", .wmv),
            ("Microsoft Video 1.avi", .microsoftVideo1),
            ("ASUS V1.avi", .asusV1),
            ("ASUS V2.avi", .asusV2),
            ("Flash Screen Video.flv", .flashScreenVideo),
            ("Flash Screen Video 2.flv", .flashScreenVideo2),
            ("ZMBV.avi", .zmbv),
            ("CLJR.avi", .cljr),
            ("Snow.avi", .snow),
            ("FFV1.avi", .ffv1),
            ("HuffYUV.avi", .huffYUV),
            ("Ut Video.avi", .utVideo),
            ("MagicYUV.avi", .magicYUV),
            ("DVCPro.mov", .dvcPro),
            ("DVCPro HD.mov", .dvcProHD),
            ("DV.dv", .dv),
            ("CineForm.avi", .cineForm),
            ("DNxHD.mov", .dnxhd),
            ("PNG Video.avi", .pngVideo),
            ("R10K.mov", .r10k),
            ("V308.mov", .v308),
            ("V210.avi", .v210),
            ("R210.avi", .r210),
            ("V408.mov", .v408),
            ("V410.mov", .v410),
            ("Microsoft RLE.avi", .microsoftRLE),
            ("QuickTime Graphics.mov", .quickTimeGraphics),
            ("YUV4.mov", .yuv4),
            ("Raw Video.avi", .rawVideo),
            ("H.264 AVC.mp4", .h264),
            ("H.265 HEVC.mp4", .hevc)
        ]
    }

    private func bundledPlannedSampleCodecExpectations() -> [(String, TaptionVideoCodec)] {
        []
    }

    private func requireLocalRealSampleProofs() throws {
        let flagURL = URL(fileURLWithPath: "/tmp/taption_run_local_real_sample_tests")
        guard ProcessInfo.processInfo.environment["TAPTION_RUN_LOCAL_REAL_SAMPLE_TESTS"] == "1"
            || FileManager.default.fileExists(atPath: flagURL.path) else {
            throw XCTSkip("Local downloaded real-sample proofs are opt-in. Set TAPTION_RUN_LOCAL_REAL_SAMPLE_TESTS=1 or create \(flagURL.path) to run them.")
        }
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
        frameRate: TaptionRationalFrameRate = TaptionRationalFrameRate(numerator: 30),
        videoBitrate: Int? = nil,
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
                estimatedBitrate: videoBitrate
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
