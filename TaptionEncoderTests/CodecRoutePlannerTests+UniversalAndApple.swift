//
//  CodecRoutePlannerTests+UniversalAndApple.swift
//  Tests 157-2092 of the original CodecRoutePlannerTests.swift, moved here
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
    func testAppConfigurationUsesBokkiEncoderWithoutChangingStorageOrOutputPolicy() {
        let configuration = AppConfiguration()

        XCTAssertEqual(configuration.appName, "BOKKI Encoder")
        XCTAssertEqual(configuration.bundleIdentifier, "com.taption.encoder")
        XCTAssertEqual(configuration.outputSuffix, "_taption")
        XCTAssertEqual(configuration.defaultOutputContainer, .mp4)
        XCTAssertEqual(configuration.defaultOutputCodec, .hevc)
        XCTAssertEqual(
            TaptionEncoderStorageLocations.exportedVideosDirectoryURL.lastPathComponent,
            "Taption Encoder Outputs"
        )
    }

    func testHomeHeaderDoesNotDisplayAppName() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let viewText = try String(contentsOf: viewURL, encoding: .utf8)
        let headerStart = try XCTUnwrap(viewText.range(of: "private func header(metrics: HomeLayoutMetrics)"))
        let headerEnd = try XCTUnwrap(viewText.range(
            of: "private func starBadge(metrics: HomeLayoutMetrics)",
            range: headerStart.upperBound..<viewText.endIndex
        ))
        let headerText = String(viewText[headerStart.lowerBound..<headerEnd.lowerBound])

        XCTAssertFalse(headerText.contains("viewModel.subtitle"))
        XCTAssertFalse(headerText.contains("viewModel.appName"))
        XCTAssertFalse(headerText.contains("Taption Encoder"))
        XCTAssertFalse(headerText.contains("BOKKI Encoder"))
        XCTAssertTrue(headerText.contains("line.3.horizontal"))
        XCTAssertTrue(headerText.contains("film.stack"))
        XCTAssertTrue(headerText.contains("starBadge(metrics: metrics)"))
    }

    func testBackgroundReliabilityPresenterWarnsToKeepAppOpenBeforeContinuedProcessingOS() {
        let message = HomeBackgroundReliabilityPresenter.message(
            currentOSMajorVersion: 25,
            backgroundEncodingMinimumMajorVersion: 26,
            liveActivitiesEnabled: false
        )

        XCTAssertTrue(message.contains("Keep BOKKI Encoder open"))
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

    func testAdMobNativeAndPlacementSurfacesAreWiredWithoutPrivacyMenu() throws {
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
        XCTAssertFalse(homeViewText.contains("Privacy & Ads"))
        XCTAssertFalse(menuText.contains("Privacy & Ads"))
        XCTAssertFalse(menuText.contains("case privacyAds"))
        XCTAssertFalse(menuText.contains("PrivacyAdsSheetContentView"))
        XCTAssertFalse(menuText.contains("AdPrivacyActionHandler"))
    }

    /// Rules 3 and 4 of the design system: a view names a role, never a raw colour. The cheapest way
    /// to keep that true is to fail when a palette entry or a hex literal leaks out of the design
    /// system file, because a grep is easy to forget and a failing test is not.
    func testDesignSystemPaletteIsNotReferencedOutsideItsFile() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appURL = rootURL.appendingPathComponent("TaptionEncoder", isDirectory: true)
        let designSystemURL = rootURL
            .appendingPathComponent("TaptionEncoder/Shared/DesignSystem/TaptionDesignSystem.swift")
            .standardizedFileURL

        guard let enumerator = FileManager.default.enumerator(
            at: appURL,
            includingPropertiesForKeys: nil
        ) else {
            return XCTFail("could not enumerate \(appURL.path)")
        }
        var sources: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            sources.append(url)
        }
        // A sweep that finds nothing would pass silently and guard nothing.
        XCTAssertGreaterThan(sources.count, 50, "the sweep found \(sources.count) sources; the path is wrong")

        var offenders: [String] = []
        for source in sources where source.standardizedFileURL != designSystemURL {
            let text = try String(contentsOf: source, encoding: .utf8)
            let relative = source.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            for token in ["TaptionColor.", "Color(taptionHex:"] where text.contains(token) {
                offenders.append("\(relative) references \(token)")
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "views must name a role, not a raw colour:\n" + offenders.joined(separator: "\n")
        )
    }

    func testTaptionThemeUsesBlueGreenSlateAndIcePalette() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // The palette moved out of ProgressCard.swift into the design system; this test guards the
        // values, not the file they used to live in.
        let themeText = try String(
            contentsOf: rootURL.appendingPathComponent(
                "TaptionEncoder/Shared/DesignSystem/TaptionDesignSystem.swift"),
            encoding: .utf8
        )
        let cardText = try String(
            contentsOf: rootURL.appendingPathComponent("TaptionEncoder/Shared/UI/ProgressCard.swift"),
            encoding: .utf8
        )
        let primaryButtonText = try String(
            contentsOf: rootURL.appendingPathComponent("TaptionEncoder/Shared/UI/PrimaryActionButton.swift"),
            encoding: .utf8
        )
        let homeText = try String(
            contentsOf: rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift"),
            encoding: .utf8
        )
        let loadedFilesText = try String(
            contentsOf: rootURL.appendingPathComponent("TaptionEncoder/Features/Home/LoadedFilesPanelView.swift"),
            encoding: .utf8
        )
        let outputSummaryText = try String(
            contentsOf: rootURL.appendingPathComponent("TaptionEncoder/Features/Encoding/OutputSummaryView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(themeText.contains("0x0F191E"))
        XCTAssertTrue(themeText.contains("0x182931"))
        XCTAssertTrue(themeText.contains("0x1D333D"))
        XCTAssertTrue(themeText.contains("0x203E48"))
        XCTAssertTrue(themeText.contains("0x6DD0E5"))
        XCTAssertTrue(themeText.contains("0xEBA58B"))
        XCTAssertTrue(themeText.contains("0x91CBB6"))
        XCTAssertTrue(themeText.contains("0xE5C184"))
        // The card must take its radius from the token, not a literal 8.
        XCTAssertTrue(cardText.contains("TaptionRadius.card"))
        XCTAssertFalse(cardText.contains("cornerRadius: 8"))
        XCTAssertTrue(primaryButtonText.contains("TaptionTheme.accentButtonText"))
        XCTAssertTrue(homeText.contains(".foregroundStyle(TaptionTheme.reward)"))
        XCTAssertTrue(homeText.contains(".background(TaptionTheme.coral)"))
        XCTAssertTrue(loadedFilesText.contains("static let blueAccent = TaptionTheme.accent"))
        XCTAssertTrue(outputSummaryText.contains(".foregroundStyle(TaptionTheme.success)"))
    }

    /// §3.4 F1 of the design-system document: the measured 3.70:1 step has to exist as a role,
    /// and it has to be used where the border already carries interactivity. An enabled control's
    /// edge is its only boundary, so a 1.51:1 hairline leaves a low-vision user without one.
    func testFocusBorderIsTheAccessibleEdgeForInteractiveControls() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let themeText = try String(
            contentsOf: rootURL.appendingPathComponent(
                "TaptionEncoder/Shared/DesignSystem/TaptionDesignSystem.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(themeText.contains("0x628391"), "the measured focus step must be in the palette")
        XCTAssertTrue(themeText.contains("static let focusBorder"))

        // Every file that draws an edge on a tappable thing. `ProgressCard` is absent on purpose:
        // it is the decorative container, and `border` stays decorative.
        let interactiveEdgeSources = [
            "TaptionEncoder/Shared/UI/PrimaryActionButton.swift",
            "TaptionEncoder/Features/Home/HomeView.swift",
            "TaptionEncoder/Features/Home/LoadedFilesPanelView.swift",
            "TaptionEncoder/Features/Encoding/EncodingProgressView.swift",
        ]
        for relative in interactiveEdgeSources {
            let text = try String(contentsOf: rootURL.appendingPathComponent(relative), encoding: .utf8)
            XCTAssertTrue(
                text.contains("TaptionTheme.focusBorder"),
                "\(relative) draws an interactive edge but names the decorative border role"
            )
        }
    }

    /// §3.4 F3: enabled labels used ad-hoc `Color.white.opacity(0.86…0.96)` instead of
    /// `primaryText`, which does not follow a palette change and does not participate in
    /// Increase Contrast. The sites are migrated; this keeps a new one from creeping back in.
    ///
    /// Excluded on purpose: opacities below 0.86 (secondary labels, hairline strokes) and
    /// `AdProviders`' white placeholder card, which is a surface rather than text.
    func testNearWhiteLabelsUseTheTextToken() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migratedSources = [
            "TaptionEncoder/Features/Preview/QueuePreviewViews.swift",
            "TaptionEncoder/Features/Home/HomeView.swift",
            "TaptionEncoder/Features/Home/LoadedFilesPanelView.swift",
            "TaptionEncoder/Features/Encoding/EncodingProgressView.swift",
        ]
        let pattern = try NSRegularExpression(
            pattern: "Color\\.white\\.opacity\\(0\\.(8[6-9]|9[0-6])\\)"
        )

        var offenders: [String] = []
        for relative in migratedSources {
            let text = try String(contentsOf: rootURL.appendingPathComponent(relative), encoding: .utf8)
            let matches = pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if matches > 0 {
                offenders.append("\(relative): \(matches) near-white label(s) bypass the palette")
            }
        }
        XCTAssertTrue(offenders.isEmpty, offenders.joined(separator: "\n"))
    }

    func testHelpSheetIntegratesVersionDeviceInfoAndOpenSourceNotices() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeMenuSheetView.swift")
        let homeURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let menuText = try String(contentsOf: menuURL, encoding: .utf8)
        let homeText = try String(contentsOf: homeURL, encoding: .utf8)
        let helpStart = try XCTUnwrap(menuText.range(of: "private struct HelpSheetContentView"))
        let batteryStart = try XCTUnwrap(
            menuText.range(
                of: "private struct BatterySettingsSheetContentView",
                range: helpStart.upperBound..<menuText.endIndex
            )
        )
        let helpText = String(menuText[helpStart.lowerBound..<batteryStart.lowerBound])

        XCTAssertTrue(helpText.contains("CFBundleShortVersionString"))
        XCTAssertTrue(helpText.contains("CFBundleVersion"))
        XCTAssertTrue(helpText.contains("title: \"Version\""))
        XCTAssertTrue(helpText.contains("DeviceInfoContentView()"))
        XCTAssertTrue(helpText.contains("OpenSourceNoticesContentView()"))
        XCTAssertTrue(menuText.contains("TaptionOpenSourceNoticeCatalog.shippedComponents"))
        XCTAssertTrue(menuText.contains("Required notice text is unavailable in this build."))
        XCTAssertFalse(menuText.contains("case openSource"))
        XCTAssertFalse(menuText.contains("case deviceInfo"))
        XCTAssertFalse(homeText.contains("activeMenuSheet = .openSource"))
        XCTAssertFalse(homeText.contains("activeMenuSheet = .deviceInfo"))
        XCTAssertFalse(homeText.contains("Label(\"Open Source Notices\""))
        XCTAssertFalse(homeText.contains("Label(\"Device Info\""))
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
        XCTAssertEqual(y41pSelection.support, .implemented)
        XCTAssertTrue(y41pSelection.isEncodableNow)
        XCTAssertEqual(y41pSelection.executionKind, .software)
        XCTAssertEqual(y41pSelection.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(y41pSelection.encodeBackend, .customSoftware)

        let vc1Selection = selectRoute(
            sourceCodec: .vc1,
            outputCodec: .hevc,
            profile: .softwareOnly
        )
        XCTAssertEqual(vc1Selection.support, .implemented)
        XCTAssertTrue(vc1Selection.isEncodableNow)
        XCTAssertEqual(vc1Selection.executionKind, .software)
        XCTAssertEqual(vc1Selection.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(vc1Selection.encodeBackend, .customSoftware)
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

    func testDolbyVisionHEVCToHEVCUsesAppleNativeFallbackWithoutHardwarePath() {
        let selection = selectRoute(
            sourceCodec: .dolbyVisionHEVC,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .software)
        XCTAssertEqual(selection.decodeBackend, .softwareVLCDecoder)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testHEVCWithAlphaToHEVCUsesAppleNativeFallbackWithoutHardwarePath() {
        let selection = selectRoute(
            sourceCodec: .hevcWithAlpha,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .software)
        XCTAssertEqual(selection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testProResRawToHEVCUsesAppleNativeDecodeWhenHardwareProfileSupportsIt() {
        let selection = selectRoute(
            sourceCodec: .proResRaw,
            outputCodec: .hevc,
            profile: appleProfile("apple_a19pro_av1_decode_prores_raw")
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .mixed)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(selection.encodeBackend, .appleVideoToolbox)
    }

    func testProResRawToHEVCUsesAppleNativeSoftwareDecodeWithoutHardwareProfile() {
        let selection = selectRoute(
            sourceCodec: .proResRaw,
            outputCodec: .hevc,
            profile: .softwareOnly
        )

        XCTAssertEqual(selection.support, .implemented)
        XCTAssertTrue(selection.isEncodableNow)
        XCTAssertEqual(selection.executionKind, .software)
        XCTAssertEqual(selection.selectedMode, .software)
        XCTAssertEqual(selection.decodeBackend, .appleAVAssetExport)
        XCTAssertEqual(selection.encodeBackend, .customSoftware)
    }

    func testJPEGAndJPEGXLToHEVCUseAppleNativeSoftwareDecode() {
        for sourceCodec in [TaptionVideoCodec.jpeg, .jpegXL] {
            let selection = selectRoute(
                sourceCodec: sourceCodec,
                outputCodec: .hevc,
                profile: .softwareOnly
            )

            XCTAssertEqual(selection.support, .implemented, sourceCodec.rawValue)
            XCTAssertTrue(selection.isEncodableNow, sourceCodec.rawValue)
            XCTAssertEqual(selection.executionKind, .software, sourceCodec.rawValue)
            XCTAssertEqual(selection.selectedMode, .software, sourceCodec.rawValue)
            XCTAssertEqual(selection.decodeBackend, .appleAVAssetExport, sourceCodec.rawValue)
            XCTAssertEqual(selection.encodeBackend, .customSoftware, sourceCodec.rawValue)
        }
    }

    func testLocalJPEGAndJPEGXLVideosEncodeToHEVCMP4AndMOV() async throws {
        try requireLocalRealSampleProofs()
        guard #available(iOS 18.0, *) else {
            throw XCTSkip("JPEG XL video requires iOS 18 or later.")
        }

        var phase = "setup"
        do {
        let sourceCases = [
            (TaptionVideoCodec.jpeg, ProcessInfo.processInfo.environment["TAPTION_JPEG_SAMPLE_PATH"], "JPEG"),
            (TaptionVideoCodec.jpegXL, ProcessInfo.processInfo.environment["TAPTION_JPEG_XL_SAMPLE_PATH"], "JPEG XL")
        ].compactMap { sourceCodec, samplePath, displayName in
            samplePath.map { (sourceCodec, $0, displayName) }
        }
        guard !sourceCases.isEmpty else {
            throw XCTSkip("Local JPEG proof requires TAPTION_JPEG_SAMPLE_PATH and/or TAPTION_JPEG_XL_SAMPLE_PATH.")
        }
        let inspector = AVFoundationMediaInspector()
        let service = AVFoundationHEVCEncoderService(
            outputVerifier: DisabledSourcePreservingOutputVerifier()
        )

        for (sourceCodec, samplePath, displayName) in sourceCases {
            guard FileManager.default.fileExists(atPath: samplePath) else {
                throw XCTSkip("Local \(displayName) proof requires its TAPTION_*_SAMPLE_PATH environment variable.")
            }
            let sourceURL = URL(fileURLWithPath: samplePath)

            phase = "inspect \(sourceCodec.rawValue) source"
            let sourceAsset = try await inspector.inspectVideo(at: sourceURL)
            XCTAssertEqual(sourceAsset.container, .mov, sourceCodec.rawValue)
            XCTAssertEqual(sourceAsset.videoTrack?.codec, sourceCodec, sourceCodec.rawValue)
            XCTAssertTrue(sourceAsset.audioTracks.isEmpty, sourceCodec.rawValue)

            for outputContainer in [TaptionVideoContainer.mp4, .mov] {
                let outputURL = temporaryTestURL(
                    fileName: "\(sourceCodec.rawValue)-to-hevc.\(outputContainer.defaultFileExtension)"
                )
                try? FileManager.default.removeItem(at: outputURL)
                defer { try? FileManager.default.removeItem(at: outputURL) }

                let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
                    asset: sourceAsset,
                    sourceURL: sourceURL,
                    temporaryOutputURL: outputURL,
                    outputPolicy: TaptionVideoOutputPolicy(
                        videoCodec: .hevc,
                        audioCodec: .aac,
                        container: outputContainer
                    ),
                    savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
                )
                XCTAssertTrue(
                    [.mixed, .software].contains(plan.codecExecutionKind),
                    sourceCodec.rawValue
                )
                XCTAssertNil(plan.audioPlan, sourceCodec.rawValue)

                let result: TaptionEncodingResult
                do {
                    phase = "encode \(sourceCodec.rawValue) to \(outputContainer.rawValue)"
                    result = try await service.encode(plan: plan, progress: { _ in })
                } catch {
                    throw NSError(
                        domain: "TaptionEncoderTests.GeneratedCodecSample.Encode",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                    )
                }
                XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path), sourceCodec.rawValue)
                let outputAsset: TaptionVideoAsset
                do {
                    phase = "inspect \(sourceCodec.rawValue) \(outputContainer.rawValue) output"
                    outputAsset = try await inspector.inspectVideo(at: result.temporaryOutputURL)
                } catch {
                    throw NSError(
                        domain: "TaptionEncoderTests.GeneratedCodecSample.Inspect",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                    )
                }

                XCTAssertEqual(result.usedBackend, .appleAVAssetExport, sourceCodec.rawValue)
                XCTAssertEqual(result.usedMode, .software, sourceCodec.rawValue)
                XCTAssertEqual(outputAsset.container, outputContainer, sourceCodec.rawValue)
                XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc, sourceCodec.rawValue)
                XCTAssertTrue(outputAsset.audioTracks.isEmpty, sourceCodec.rawValue)
                XCTAssertGreaterThan(
                    (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
                    0,
                    sourceCodec.rawValue
                )
            }
        }
        } catch {
            let nsError = error as NSError
            XCTFail(
                "Generated codec proof failed during \(phase): [\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)"
            )
        }
    }

    func testLocalRemainingCodecSamplesEncodeToHEVCMP4AndMOV() async throws {
        try requireLocalRealSampleProofs()

        struct SampleCase {
            var codec: TaptionVideoCodec
            var environmentKey: String
            var expectedBackends: [TaptionEncodingBackend]
        }
        let configuredCases = [
            SampleCase(codec: .hevcWithAlpha, environmentKey: "TAPTION_HEVC_ALPHA_SAMPLE_PATH", expectedBackends: [.appleAVAssetExport]),
            SampleCase(codec: .dolbyVisionHEVC, environmentKey: "TAPTION_DOLBY_VISION_SAMPLE_PATH", expectedBackends: [.softwareVLCDecoder]),
            SampleCase(codec: .proResRaw, environmentKey: "TAPTION_PRORES_RAW_SAMPLE_PATH", expectedBackends: [.appleAVAssetExport, .ffmpegFamily]),
            SampleCase(codec: .sorensonVideo3, environmentKey: "TAPTION_SVQ3_SAMPLE_PATH", expectedBackends: [.softwareVLCDecoder]),
            SampleCase(codec: .theora, environmentKey: "TAPTION_THEORA_SAMPLE_PATH", expectedBackends: [.softwareVLCDecoder]),
            SampleCase(codec: .dvcPro, environmentKey: "TAPTION_DVCPRO_SAMPLE_PATH", expectedBackends: [.softwareVLCDecoder]),
            SampleCase(codec: .dvcProHD, environmentKey: "TAPTION_DVCPROHD_SAMPLE_PATH", expectedBackends: [.softwareVLCDecoder])
        ].compactMap { sampleCase -> (SampleCase, URL)? in
            guard let path = ProcessInfo.processInfo.environment[sampleCase.environmentKey] else {
                return nil
            }
            return (sampleCase, URL(fileURLWithPath: path))
        }
        guard !configuredCases.isEmpty else {
            throw XCTSkip("Remaining-codec proof requires at least one TAPTION_*_SAMPLE_PATH environment variable.")
        }

        let inspector = AVFoundationMediaInspector()
        let service = AVFoundationHEVCEncoderService(
            outputVerifier: DisabledSourcePreservingOutputVerifier()
        )
        for (sampleCase, sourceURL) in configuredCases {
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                XCTFail("Missing \(sampleCase.environmentKey): \(sourceURL.path)")
                continue
            }
            let sourceAsset = try await inspector.inspectVideo(at: sourceURL)
            XCTAssertEqual(sourceAsset.videoTrack?.codec, sampleCase.codec, sourceURL.lastPathComponent)

            for outputContainer in [TaptionVideoContainer.mp4, .mov] {
                let outputURL = temporaryTestURL(
                    fileName: "\(sampleCase.codec.rawValue)-remaining-proof.\(outputContainer.defaultFileExtension)"
                )
                let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
                    asset: sourceAsset,
                    sourceURL: sourceURL,
                    temporaryOutputURL: outputURL,
                    outputPolicy: TaptionVideoOutputPolicy(
                        videoCodec: .hevc,
                        audioCodec: .aac,
                        container: outputContainer
                    ),
                    savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
                )
                XCTAssertEqual(plan.codecRoute?.sourceCodec, sampleCase.codec, sourceURL.lastPathComponent)
                XCTAssertNotEqual(plan.codecExecutionKind, .planned, sourceURL.lastPathComponent)
                XCTAssertNotEqual(plan.codecExecutionKind, .unsupported, sourceURL.lastPathComponent)

                let result: TaptionEncodingResult
                do {
                    result = try await service.encode(plan: plan, progress: { _ in })
                } catch {
                    throw NSError(
                        domain: "TaptionEncoderTests.RemainingCodecSample.Encode",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "\(sourceURL.lastPathComponent) to \(outputContainer.rawValue): \(error.localizedDescription)"
                        ]
                    )
                }
                let outputAsset: TaptionVideoAsset
                do {
                    outputAsset = try await inspector.inspectVideo(at: result.temporaryOutputURL)
                } catch {
                    throw NSError(
                        domain: "TaptionEncoderTests.RemainingCodecSample.Inspect",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "\(sourceURL.lastPathComponent) \(outputContainer.rawValue) output: \(error.localizedDescription)"
                        ]
                    )
                }

                XCTAssertTrue(
                    sampleCase.expectedBackends.contains(result.usedBackend),
                    "\(sourceURL.lastPathComponent): \(result.usedBackend.rawValue)"
                )
                XCTAssertEqual(outputAsset.container, outputContainer, sourceURL.lastPathComponent)
                XCTAssertEqual(outputAsset.videoTrack?.codec, .hevc, sourceURL.lastPathComponent)
                XCTAssertGreaterThan(
                    (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
                    0,
                    sourceURL.lastPathComponent
                )
            }
        }
    }

    func testUniversalBridgeRoutesAreEncodableAndUnsupportedOutputsStayBlocked() {
        let vc1ToHEVC = selectRoute(
            sourceCodec: .vc1,
            outputCodec: .hevc,
            profile: .softwareOnly
        )
        let h264ToAV1 = selectRoute(
            sourceCodec: .h264,
            outputCodec: .av1,
            profile: .h264HEVCHardware
        )

        XCTAssertEqual(vc1ToHEVC.support, .implemented)
        XCTAssertEqual(vc1ToHEVC.executionKind, .software)
        XCTAssertTrue(vc1ToHEVC.isEncodableNow)
        XCTAssertEqual(vc1ToHEVC.decodeBackend, .ffmpegFamily)
        XCTAssertEqual(vc1ToHEVC.encodeBackend, .customSoftware)

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
        XCTAssertEqual(alphaDescriptors.count, 2)
        XCTAssertTrue(alphaDescriptors.contains { $0.mode == .hardware && $0.backend == .appleVideoToolbox })
        XCTAssertTrue(alphaDescriptors.contains { $0.mode == .software && $0.backend == .appleAVAssetExport })
        XCTAssertEqual(dolbyDescriptors.count, 2)
        XCTAssertTrue(dolbyDescriptors.contains { $0.mode == .hardware && $0.backend == .appleVideoToolbox })
        XCTAssertTrue(dolbyDescriptors.contains { $0.mode == .software && $0.backend == .softwareVLCDecoder })
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
        XCTAssertEqual(TaptionCodecTranscodingRegistry.live.descriptors(for: vc1Route).first?.backend, .ffmpegFamily)
        XCTAssertTrue(TaptionCodecTranscodingRegistry.live.plannedDescriptors(for: vc1Route).isEmpty)
        let y41pRoute = TaptionCodecRoute(sourceCodec: .y41p, outputCodec: .hevc)
        XCTAssertEqual(TaptionCodecTranscodingRegistry.live.descriptors(for: y41pRoute).first?.backend, .ffmpegFamily)
        XCTAssertTrue(TaptionCodecTranscodingRegistry.live.plannedDescriptors(for: y41pRoute).isEmpty)
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

    func testLiveRegistryExposesBundledBridgeRoutesAsExecutableAlgorithms() {
        for sourceCodec in TaptionCodecRegistry.bundledFFmpegDecodeBridgeSourceCodecs {
            let route = TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: .hevc)
            let descriptors = TaptionCodecTranscodingRegistry.live.descriptors(for: route)

            XCTAssertTrue(
                descriptors.contains { $0.mode == .software && $0.backend == .ffmpegFamily },
                sourceCodec.rawValue
            )
            XCTAssertTrue(TaptionCodecTranscodingRegistry.live.plannedDescriptors(for: route).isEmpty)
        }
    }

    func testConfiguredLiveRegistryDoesNotDuplicateBundledBridgeRoutes() {
        let route = TaptionCodecRoute(sourceCodec: .vc1, outputCodec: .hevc)
        let registry = TaptionCodecTranscodingRegistry.makeLive(
            softwareExecutor: SW_FFmpegCommandExecutor(
                readinessReport: readyBroadSoftwareBackendReport(),
                runner: FakeFFmpegCommandRunner { _ in SW_FFmpegCommandRunResult(exitCode: 0) },
                validateOutputFileExists: false
            )
        )

        XCTAssertEqual(registry.descriptors(for: route).filter { $0.mode == .software }.count, 1)
        XCTAssertTrue(registry.plannedDescriptors(for: route).isEmpty)
    }

    func testUniversalSoftwareAlgorithmHasNoPendingVideoRoutes() {
        XCTAssertTrue(SW_UniversalCodecTranscodeAlgorithm.plannedDescriptors.isEmpty)
    }

    func testFFmpegVideoCodecTranscodeExecutorBlocksUntilReadinessGatesClose() async throws {
        let route = TaptionCodecRoute(sourceCodec: .vc1, outputCodec: .hevc)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.vc1"),
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
        let outputURL = temporaryTestURL(fileName: "vc1-to-hevc.mp4")
        try? FileManager.default.removeItem(at: outputURL)
        let route = TaptionCodecRoute(sourceCodec: .vc1, outputCodec: .hevc)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/input.vc1"),
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

        XCTAssertTrue(plan.arguments.contains("scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:-1:-1:color=black,setsar=1"))
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

}
