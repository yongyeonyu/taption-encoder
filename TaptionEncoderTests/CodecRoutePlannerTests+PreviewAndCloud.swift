//
//  CodecRoutePlannerTests+PreviewAndCloud.swift
//  Tests 13561-15463 of the original CodecRoutePlannerTests.swift, moved here
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
    /// An unfolded foldable iPhone still reports `.phone`. It has to get the iPad layout anyway, so
    /// the layout is chosen from the short side rather than from the idiom — and every existing
    /// phone, landscape included, has to stay on the phone layout.
    func testUnfoldedFoldableGetsTheWideLayoutWhilePhonesDoNot() {
        // iPad mini's short side is 744 pt; an unfolded foldable lands in the same range.
        let unfolded = HomeLayoutMetrics(
            size: CGSize(width: 744, height: 1133),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )
        let unfoldedLandscape = HomeLayoutMetrics(
            size: CGSize(width: 1133, height: 744),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )
        let phonePortrait = HomeLayoutMetrics(
            size: CGSize(width: 393, height: 852),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )
        let phoneLandscape = HomeLayoutMetrics(
            size: CGSize(width: 852, height: 393),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )
        let padPortrait = HomeLayoutMetrics(
            size: CGSize(width: 834, height: 1194),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .pad
        )

        // Unfolded: wide padding, wide canvas, no compact scrolling, and columns only when landscape.
        XCTAssertTrue(unfolded.usesWideLayout)
        XCTAssertTrue(unfoldedLandscape.usesWideLayout)
        XCTAssertTrue(padPortrait.usesWideLayout)
        XCTAssertFalse(phonePortrait.usesWideLayout)
        XCTAssertFalse(phoneLandscape.usesWideLayout)
        XCTAssertGreaterThanOrEqual(unfolded.horizontalPadding, 28, "Wide layouts keep the 28 pt floor.")
        XCTAssertGreaterThan(unfolded.horizontalPadding, phonePortrait.horizontalPadding)
        XCTAssertFalse(unfolded.usesPadLandscapeColumns)
        XCTAssertTrue(unfoldedLandscape.usesPadLandscapeColumns)
        XCTAssertFalse(unfolded.usesScrollableLayout)
        XCTAssertGreaterThan(unfolded.canvasWidth, phonePortrait.canvasWidth)
        XCTAssertLessThanOrEqual(
            unfolded.canvasWidth, padPortrait.canvasWidth,
            "The unfolded canvas never exceeds the iPad portrait canvas.")

        // Phones are untouched, including the compact landscape that must keep scrolling.
        XCTAssertFalse(phonePortrait.usesPadLandscapeColumns)
        XCTAssertFalse(phoneLandscape.usesPadLandscapeColumns)
        XCTAssertTrue(phoneLandscape.usesScrollableLayout)
        XCTAssertLessThan(phonePortrait.horizontalPadding, unfolded.horizontalPadding)

        // The threshold sits in the gap between the two Duo poses: the folded outer display stays
        // compact, the unfolded inner display goes wide. 466 and 626 are the measured short sides.
        XCTAssertFalse(
            HomeLayoutMetrics.usesWideLayout(
                size: CGSize(width: 466, height: 678), userInterfaceIdiom: .phone),
            "The folded Duo (466 pt) keeps the phone layout.")
        XCTAssertTrue(
            HomeLayoutMetrics.usesWideLayout(
                size: CGSize(width: 626, height: 890), userInterfaceIdiom: .phone),
            "The unfolded Duo (626 pt) gets the iPad layout.")
        XCTAssertLessThan(440, HomeLayoutMetrics.wideLayoutMinimumShortSide)
        XCTAssertGreaterThanOrEqual(626, HomeLayoutMetrics.wideLayoutMinimumShortSide)
    }

    /// The folded Duo is a phone that is wider and shorter than any iPhone. It must scale down to
    /// fit rather than switch layout classes or start scrolling.
    func testFoldedDuoScalesDownWithoutSwitchingLayout() {
        let outer = HomeLayoutMetrics(
            size: CGSize(width: 466, height: 678),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )
        let phone = HomeLayoutMetrics(
            size: CGSize(width: 393, height: 852),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )

        XCTAssertFalse(outer.usesWideLayout, "The outer display is a phone screen, not an iPad one.")
        XCTAssertFalse(outer.usesPadLandscapeColumns)
        XCTAssertFalse(
            outer.usesScrollableLayout,
            "678 pt of height is short but not scroll-short; scrolling would hide the output picker.")
        XCTAssertLessThan(outer.contentScale, phone.contentScale, "Shorter height means smaller type.")
        XCTAssertGreaterThanOrEqual(outer.contentScale, 0.72, "Scaling has a floor, so text stays legible.")
        XCTAssertLessThanOrEqual(
            outer.canvasWidth, 430,
            "The outer display keeps the phone content column instead of stretching to 466.")
        XCTAssertGreaterThan(outer.filePanelHeight, 0, "The file panel must keep positive height.")
    }

    /// Unfolding must not merely widen the phone layout — it has to become the iPad arrangement.
    func testUnfoldedDuoTakesTheIPadArrangement() {
        let inner = HomeLayoutMetrics(
            size: CGSize(width: 626, height: 890),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )
        let phone = HomeLayoutMetrics(
            size: CGSize(width: 393, height: 852),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )

        XCTAssertTrue(inner.usesWideLayout)
        XCTAssertFalse(inner.usesPadLandscapeColumns, "Portrait, so one column.")
        XCTAssertGreaterThanOrEqual(inner.horizontalPadding, 28)
        XCTAssertGreaterThan(inner.horizontalPadding, phone.horizontalPadding)
        XCTAssertGreaterThan(inner.canvasWidth, phone.canvasWidth)
        XCTAssertLessThanOrEqual(inner.canvasWidth, 626, "The canvas never exceeds the panel width.")
        XCTAssertGreaterThan(inner.filePanelHeight, 0)

        // Rotating the unfolded panel keeps it wide and switches to the two-column iPad landscape.
        let innerLandscape = HomeLayoutMetrics(
            size: CGSize(width: 890, height: 626),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )
        XCTAssertTrue(innerLandscape.usesWideLayout)
        XCTAssertTrue(innerLandscape.usesPadLandscapeColumns)
        XCTAssertGreaterThan(innerLandscape.columnWidth, 0)
    }

    /// Rotation follows the layout class, not the idiom: if a screen is arranged like an iPad it
    /// should also be able to turn like one, and a folded phone must stay portrait.
    @MainActor
    func testUnfoldedFoldableRotatesLikeIPadWhileFoldedPhonesStayPortrait() {
        let unfolded = AppOrientationController.homeOrientations(
            for: .phone,
            size: CGSize(width: 744, height: 1133)
        )
        XCTAssertTrue(unfolded.contains(.portrait))
        XCTAssertTrue(unfolded.contains(.landscapeLeft))
        XCTAssertTrue(unfolded.contains(.landscapeRight))

        // Landscape geometry has to reach the same answer, otherwise the policy would flip-flop.
        let unfoldedLandscape = AppOrientationController.homeOrientations(
            for: .phone,
            size: CGSize(width: 1133, height: 744)
        )
        XCTAssertEqual(unfoldedLandscape, unfolded)

        XCTAssertEqual(
            AppOrientationController.homeOrientations(
                for: .phone,
                size: CGSize(width: 393, height: 852)
            ),
            .portrait
        )
        XCTAssertEqual(
            AppOrientationController.homeOrientations(
                for: .phone,
                size: CGSize(width: 852, height: 393)
            ),
            .portrait
        )

        // The folded Duo is wide but short — still a phone, so still portrait-only.
        XCTAssertEqual(
            AppOrientationController.homeOrientations(
                for: .phone,
                size: CGSize(width: 466, height: 678)
            ),
            .portrait
        )
        // Unfolded to 626 pt, the same device must rotate like an iPad.
        XCTAssertEqual(
            AppOrientationController.homeOrientations(
                for: .phone,
                size: CGSize(width: 626, height: 890)
            ),
            unfolded
        )

        // Omitting the size keeps the old idiom-only behaviour, which the preview flow relies on.
        XCTAssertEqual(AppOrientationController.homeOrientations(for: .phone), .portrait)
        XCTAssertEqual(
            AppOrientationController.homeOrientations(for: .pad, size: CGSize(width: 834, height: 1194)),
            AppOrientationController.homeOrientations(for: .pad)
        )
    }

    func testIPadLandscapeKeepsQueueInLeftColumnAndOutputActionsInRightColumn() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let homeViewURL = rootURL.appendingPathComponent("TaptionEncoder/Features/Home/HomeView.swift")
        let homeViewText = try String(contentsOf: homeViewURL, encoding: .utf8)
        let landscapeStart = try XCTUnwrap(homeViewText.range(of: "private func padLandscapeHomeContent("))
        let landscapeEnd = try XCTUnwrap(homeViewText[landscapeStart.upperBound...].range(of: "\n    private func topBanner"))
        let landscapeText = String(homeViewText[landscapeStart.lowerBound..<landscapeEnd.lowerBound])
        let encodingRange = try XCTUnwrap(landscapeText.range(of: "encodingControls("))
        let loadedRange = try XCTUnwrap(landscapeText.range(of: "loadedFilesPanel(metrics: metrics)"))
        let outputRange = try XCTUnwrap(landscapeText.range(of: "outputDisclosure(metrics: metrics)"))
        XCTAssertLessThan(loadedRange.lowerBound, outputRange.lowerBound)
        XCTAssertLessThan(outputRange.lowerBound, encodingRange.lowerBound)
        XCTAssertFalse(landscapeText.contains("exitButton(metrics: metrics)"))
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
    internal func makePreviewQueueBrowserFixture(
        codec: TaptionVideoCodec = .h264,
        availableBytes: Int64 = 1_000_000,
        previewFolderDefaults: UserDefaults? = nil,
        photoVideoLoader: any PhotoVideoLoading = PhotoKitVideoLoader()
    ) async throws -> (directory: URL, urls: [URL], model: HomeViewModel,
                       inspector: CountingMediaInspector, wallet: FakeStarWalletStore,
                       encoder: RecordingStartEncoder) {
        let directory = temporaryDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suffix = codec == .hevcWithAlpha ? "mov" : "mp4"
        let urls = ["a", "b", "c"].map { directory.appendingPathComponent("\($0).\(suffix)") }
        for url in urls { try Data("source".utf8).write(to: url) }
        var asset = makeAsset(sourceCodec: codec)
        if codec == .hevcWithAlpha { asset.container = .mov }
        let inspector = CountingMediaInspector(asset: asset)
        let wallet = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 3))
        let encoder = RecordingStartEncoder()
        let model = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(), mediaInspector: inspector,
            encoderService: encoder,
            storageChecker: RecordingStorageChecker(requirement: TaptionStorageRequirement(
                estimatedOutputBytes: 1_000, requiredWorkingBytes: 1_024, availableBytes: availableBytes
            )),
            starWalletStore: wallet
        ), previewFolderDefaults: previewFolderDefaults ?? UserDefaults(suiteName: "PreviewFolderTests-\(UUID().uuidString)")!, photoVideoLoader: photoVideoLoader)
        await model.refreshStarsIfNeeded()
        return (directory, urls, model, inspector, wallet, encoder)
    }

    @MainActor
    func testPreviewListAddKeepsSelectedFilePlayingUntilClose() async throws {
        let fixture = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.openFilesPreviewBrowser(urls: fixture.urls)
        model.selectFolderPreviewFile(id: fixture.urls[1].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[1] }
        let preview = try XCTUnwrap(model.activePreview)
        let inspections = fixture.inspector.inspectionCount
        XCTAssertFalse(model.isPreviewAddedToList(preview))
        XCTAssertTrue(model.canAddPreviewToList(preview))
        XCTAssertTrue(model.addPreviewToList(preview))
        XCTAssertTrue(model.isPreviewAddedToList(preview))
        XCTAssertFalse(model.canAddPreviewToList(preview))
        XCTAssertFalse(model.addPreviewToList(preview))
        XCTAssertEqual(model.activePreview, preview)
        XCTAssertNil(model.miniPlayerPreview)
        XCTAssertNotNil(model.folderPreviewContext)
        XCTAssertEqual(model.folderPreviewFileSnapshots.count, 3)
        XCTAssertNil(model.state.preparedEncodingReview)
        XCTAssertEqual(fixture.inspector.inspectionCount, inspections)
        model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: model, timeout: 10)
        XCTAssertNil(model.activePreview)
        XCTAssertNil(model.folderPreviewContext)
        XCTAssertEqual(model.fileCardSnapshots.map(\.id), [fixture.urls[1].absoluteString])
        XCTAssertEqual(model.fileCardSnapshots.first?.sourceKind, .files)
        XCTAssertEqual(model.fileCardSnapshots.first?.videoInfo?.fileSize, preview.videoInfo.fileSize)
        XCTAssertEqual(model.state.preparedEncodingReview?.source.url, fixture.urls[1])
        let wallet = await fixture.wallet.currentSnapshot()
        let encodeCalls = await fixture.encoder.callCount()
        XCTAssertEqual(wallet.balance, 3)
        XCTAssertEqual(encodeCalls, 0)
        model.openPreviewForFileCard(id: fixture.urls[1].absoluteString)
        XCTAssertTrue(model.isPreviewAddedToList(try XCTUnwrap(model.activePreview)))
        XCTAssertFalse(model.addPreviewToList(try XCTUnwrap(model.activePreview)))
        XCTAssertEqual(model.fileCardSnapshots.count, 1)
        model.closePreviewFromPlayer()
    }

    @MainActor
    func testPreviewListNativeFolderVideoKeepsPlayerAndGeometryUntilClose() async throws {
        let fixture = try await makePreviewQueueBrowserFixture(codec: .hevcWithAlpha)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.startFolderFlow(url: fixture.directory)
        model.selectFolderPreviewFile(id: fixture.urls[2].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[2] }
        let preview = try XCTUnwrap(model.activePreview)
        XCTAssertTrue(preview.usesNativePlayback)
        XCTAssertTrue(model.addPreviewToList(preview))
        XCTAssertEqual(model.activePreview, preview)
        XCTAssertTrue(model.isPreviewAddedToList(preview))
        XCTAssertNil(model.miniPlayerPreview)
        model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: model, timeout: 10)
        XCTAssertNil(model.folderPreviewContext)
        XCTAssertEqual(model.fileCardSnapshots.map(\.id), [fixture.urls[2].absoluteString])
        XCTAssertEqual(model.fileCardSnapshots.first?.sourceKind, .folder)
        model.openPreviewForFileCard(id: fixture.urls[2].absoluteString)
        XCTAssertEqual(model.activePreview?.usesNativePlayback, true)
        XCTAssertEqual(model.activePreview?.displaySize, preview.displaySize)
        XCTAssertTrue(model.isPreviewAddedToList(try XCTUnwrap(model.activePreview)))
        let wallet = await fixture.wallet.currentSnapshot()
        let encodeCalls = await fixture.encoder.callCount()
        XCTAssertEqual(wallet.balance, 3)
        XCTAssertEqual(encodeCalls, 0)
        model.closePreviewFromPlayer()
    }

    @MainActor
    func testPreviewListExistingBatchIsCheckedAndCannotDuplicateOrExit() async throws {
        let fixture = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.startFilesFlow(urls: fixture.urls)
        try await waitForReadyToStartState(in: model, timeout: 10)
        model.toggleQueueFileSelection(id: fixture.urls[0].absoluteString)
        model.openPreviewForFileCard(id: fixture.urls[2].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[2] }
        let cards = model.fileCardSnapshots
        let planID = model.state.preparedEncodingReview?.job.plan.id
        let preview = try XCTUnwrap(model.activePreview)
        XCTAssertTrue(model.isPreviewAddedToList(preview))
        XCTAssertFalse(model.canAddPreviewToList(preview))
        XCTAssertFalse(model.addPreviewToList(preview))
        XCTAssertEqual(model.activePreview, preview)
        XCTAssertNil(model.miniPlayerPreview)
        XCTAssertEqual(model.fileCardSnapshots, cards)
        XCTAssertEqual(model.state.preparedEncodingReview?.job.plan.id, planID)
        let wallet = await fixture.wallet.currentSnapshot()
        XCTAssertEqual(wallet.balance, 3)
        model.closePreviewFromPlayer()
        XCTAssertNil(model.activePreview)
        XCTAssertEqual(model.fileCardSnapshots, cards)
    }

    @MainActor
    func testConnectedFilePickerAutoLinksFolderAndQueuesOnlyChosenVideo() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        f.model.openConnectedFilesFolder(f.directory)
        XCTAssertEqual(f.model.folderPreviewContext?.selectsSingleFile, true)
        f.model.selectFolderPreviewFile(id: f.urls[1].absoluteString)
        try await waitForCondition(timeout: 10) { f.model.activePreview?.sourceURL == f.urls[1] }
        let preview = try XCTUnwrap(f.model.activePreview)
        XCTAssertNil(preview.folderAccessURL)
        XCTAssertEqual(preview.playlist?.totalCount, 3)
        XCTAssertEqual(preview.playlist?.currentIndex, 1)
        XCTAssertEqual(f.model.fileCardSnapshots.map(\.fileName), ["b.mp4"])
        f.model.openNextPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[2] }
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
    }

    @MainActor
    func testFilePickerHandoffKeepsSnapshotWhenProviderFolderRescanFails() async throws {
        for codec: TaptionVideoCodec in [.h264, .hevcWithAlpha] {
            let f = try await makePreviewQueueBrowserFixture(codec: codec)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
                try? FileManager.default.removeItem(at: f.directory)
            }
            f.model.openConnectedFilesFolder(f.directory)
            XCTAssertEqual(f.model.folderPreviewFileSnapshots.count, 3)
            // The list was available when picked, but a subsequent provider scan fails.
            try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: f.directory.path)
            f.model.selectFolderPreviewFile(id: f.urls[1].absoluteString)
            try await waitForCondition(timeout: 10) { f.model.activePreview?.sourceURL == f.urls[1] }
            XCTAssertEqual(f.model.activePreview?.playlist?.positionText, "2 / 3")
            XCTAssertNil(f.model.activePreview?.folderAccessURL)
            XCTAssertEqual(f.model.activePreview?.usesNativePlayback, codec == .hevcWithAlpha)
            f.model.openNextPreview()
            try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[2] }
            XCTAssertEqual(f.model.activePreview?.playlist?.positionText, "3 / 3")
            f.model.openPreviousPreview()
            try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[1] }
            XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
            f.model.closePreviewFromPlayer()
        }
    }

    @MainActor
    func testMissingVideoFolderPermissionRequestsOncePerLaunchUntilConnected() async throws {
        let suite = "InitialFolderRequest-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "preview.folderAccessRequestShown") // Legacy decline must not suppress future launches.
        let f = try await makePreviewQueueBrowserFixture(previewFolderDefaults: defaults)
        defer { f.model.reset(); try? FileManager.default.removeItem(at: f.directory) }
        XCTAssertTrue(f.model.consumeInitialVideoFolderAccessRequest())
        XCTAssertFalse(f.model.consumeInitialVideoFolderAccessRequest())
        XCTAssertTrue(f.model.fileCardSnapshots.isEmpty)
        XCTAssertNil(f.model.activePreview)
        let replacement = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(), mediaInspector: f.inspector
        ), previewFolderDefaults: defaults)
        defer { replacement.reset() }
        XCTAssertTrue(replacement.consumeInitialVideoFolderAccessRequest(), "Missing permission must be requested on the next launch")
        XCTAssertFalse(replacement.consumeInitialVideoFolderAccessRequest())
        XCTAssertNil(replacement.connectVideoFolder(f.directory))
        let connected = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(), mediaInspector: f.inspector
        ), previewFolderDefaults: defaults)
        defer { connected.reset() }
        XCTAssertFalse(connected.consumeInitialVideoFolderAccessRequest(), "A remembered grant skips the startup request")
    }

    @MainActor
    func testParentFolderGrantReopensDifferentChildFoldersWithoutRequests() async throws {
        let suite = "ParentFolderGrant-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let f = try await makePreviewQueueBrowserFixture(previewFolderDefaults: defaults)
        defer { f.model.reset(); try? FileManager.default.removeItem(at: f.directory) }
        var selections: [URL] = []
        for name in ["TripA", "TripB"] {
            let child = f.directory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
            for source in f.urls { try FileManager.default.copyItem(at: source, to: child.appendingPathComponent(source.lastPathComponent)) }
            selections.append(child.appendingPathComponent(f.urls[1].lastPathComponent))
        }
        XCTAssertNil(f.model.connectVideoFolder(f.directory))
        XCTAssertTrue(f.model.fileCardSnapshots.isEmpty, "Granting access does not import or queue videos")
        XCTAssertFalse(f.model.consumeInitialVideoFolderAccessRequest())
        let replacement = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(), mediaInspector: f.inspector
        ), previewFolderDefaults: defaults)
        defer { replacement.reset() }
        XCTAssertFalse(replacement.consumeInitialVideoFolderAccessRequest())
        let bookmarks = PreviewFolderBookmarkStore(defaults: defaults)
        for selected in selections {
            XCTAssertEqual(bookmarks.folders(containing: selected).count, 1)
            replacement.openExternalPlayerFile(url: selected)
            try await waitForCondition(timeout: 10) { replacement.activePreview?.sourceURL == selected }
            XCTAssertEqual(replacement.activePreview?.playlist?.positionText, "2 / 3")
            XCTAssertNil(replacement.activePreview?.folderAccessURL)
            XCTAssertFalse(replacement.consumePreviewFolderAccessRequest(for: selected.absoluteString))
            replacement.openNextPreview()
            try await waitForCondition(timeout: 5) { replacement.activePreview?.playlist?.positionText == "3 / 3" }
            replacement.closePreviewFromPlayer()
        }
        XCTAssertTrue(bookmarks.folders(containing: f.directory.appendingPathExtension("outside").appendingPathComponent("a.mp4")).isEmpty,
                      "A saved parent never grants unrelated locations")
    }

    @MainActor
    func testMultipleParentFolderGrantsRestoreNavigationAcrossModelReplacement() async throws {
        let suite = "MultipleFolderGrants-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let f = try await makePreviewQueueBrowserFixture(previewFolderDefaults: defaults)
        defer { f.model.reset(); try? FileManager.default.removeItem(at: f.directory) }
        var parents: [URL] = []
        var selections: [URL] = []
        for name in ["Library A", "Library B"] {
            let parent = f.directory.appendingPathComponent(name, isDirectory: true)
            let child = parent.appendingPathComponent("Trip", isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            for source in f.urls {
                try FileManager.default.copyItem(at: source, to: child.appendingPathComponent(source.lastPathComponent))
            }
            parents.append(parent)
            selections.append(child.appendingPathComponent(f.urls[1].lastPathComponent))
        }
        XCTAssertNil(f.model.connectVideoFolder(parents[0]))
        XCTAssertNil(f.model.connectVideoFolders([parents[1], parents[0], parents[1]]))
        XCTAssertEqual(Set(f.model.connectedVideoFolders.map(MediaFileIdentity.canonicalURL)), Set(parents.map(MediaFileIdentity.canonicalURL)))
        XCTAssertTrue(f.model.fileCardSnapshots.isEmpty)
        XCTAssertNil(f.model.activePreview)
        let wallet = await f.wallet.currentSnapshot()
        let encodeCalls = await f.encoder.callCount()
        XCTAssertEqual(wallet.balance, 3)
        XCTAssertEqual(encodeCalls, 0)

        let replacement = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(), mediaInspector: f.inspector
        ), previewFolderDefaults: defaults)
        defer { replacement.reset() }
        XCTAssertEqual(replacement.connectedVideoFolders.count, 2)
        XCTAssertFalse(replacement.consumeInitialVideoFolderAccessRequest())
        let bookmarks = PreviewFolderBookmarkStore(defaults: defaults)
        XCTAssertTrue(bookmarks.folders(containing: f.urls[0]).isEmpty, "Separate parent grants never imply device-wide access")
        for selected in selections {
            replacement.openExternalPlayerFile(url: selected)
            try await waitForCondition(timeout: 10) { replacement.activePreview?.sourceURL == selected }
            XCTAssertNil(replacement.activePreview?.folderAccessURL)
            XCTAssertEqual(replacement.activePreview?.playlist?.positionText, "2 / 3")
            replacement.openNextPreview()
            try await waitForCondition(timeout: 5) { replacement.activePreview?.playlist?.positionText == "3 / 3" }
            replacement.openPreviousPreview()
            try await waitForCondition(timeout: 5) { replacement.activePreview?.sourceURL == selected }
            replacement.closePreviewFromPlayer()
        }
    }

    @MainActor
    func testMultipleFolderConnectionFailureAndCancellationPreserveExistingGrants() async throws {
        let suite = "MultipleFolderValidation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let f = try await makePreviewQueueBrowserFixture(previewFolderDefaults: defaults)
        defer { f.model.reset(); try? FileManager.default.removeItem(at: f.directory) }
        let existing = f.directory.appendingPathComponent("Existing", isDirectory: true)
        let valid = f.directory.appendingPathComponent("New", isDirectory: true)
        for folder in [existing, valid] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        XCTAssertNil(f.model.connectVideoFolder(existing))
        let saved = try XCTUnwrap(defaults.array(forKey: PreviewFolderBookmarkStore.key) as? [Data])
        XCTAssertNil(f.model.connectVideoFolders([]), "Cancelling creates no permission")
        XCTAssertNotNil(f.model.connectVideoFolders([valid, f.urls[0]]))
        XCTAssertNotNil(f.model.connectVideoFolders([valid, f.directory.appendingPathComponent("Missing")]))
        XCTAssertNotNil(f.model.connectVideoFolders([valid, try XCTUnwrap(URL(string: "https://example.com/videos"))]))
        XCTAssertEqual(defaults.array(forKey: PreviewFolderBookmarkStore.key) as? [Data], saved)
        XCTAssertEqual(f.model.connectedVideoFolders.map(MediaFileIdentity.canonicalURL), [MediaFileIdentity.canonicalURL(existing)])
        XCTAssertTrue(f.model.fileCardSnapshots.isEmpty)
        XCTAssertNil(f.model.activePreview)
    }

    @MainActor
    func testFolderBookmarkBatchCreationFailureDoesNotPartiallyPersist() throws {
        let suite = "FolderBookmarkBatchFailure-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = ["Existing", "New", "Fail"].map { root.appendingPathComponent($0, isDirectory: true) }
        for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        var store = PreviewFolderBookmarkStore(defaults: defaults)
        XCTAssertTrue(store.remember(folders[0]))
        let saved = try XCTUnwrap(defaults.array(forKey: PreviewFolderBookmarkStore.key) as? [Data])
        store.create = { folder in folder.lastPathComponent == "Fail" ? nil : try? folder.bookmarkData(options: []) }
        XCTAssertFalse(store.remember(Array(folders.dropFirst())))
        XCTAssertEqual(defaults.array(forKey: PreviewFolderBookmarkStore.key) as? [Data], saved)
    }

    @MainActor
    func testFolderBookmarkBatchRetainsEverySelectedAndPreviouslySavedFolder() throws {
        let suite = "FolderBookmarkBatchCapacity-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = (0..<24).map { root.appendingPathComponent("Library \($0)", isDirectory: true) }
        for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false) }
        let store = PreviewFolderBookmarkStore(defaults: defaults)
        XCTAssertTrue(store.remember(folders[0]))
        XCTAssertTrue(store.remember(Array(folders.dropFirst()) + [folders[1], folders[2]]))
        let restored = PreviewFolderBookmarkStore(defaults: defaults).authorizedFolders()
        XCTAssertEqual(restored.count, folders.count, "Adding folders must never silently discard earlier permissions")
        XCTAssertEqual(Set(restored.map(MediaFileIdentity.canonicalURL)), Set(folders.map(MediaFileIdentity.canonicalURL)))
    }

    @MainActor
    func testInitialFolderConnectionRejectsUnreadableAndNonDirectorySources() async throws {
        let suite = "InvalidInitialFolder-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let f = try await makePreviewQueueBrowserFixture(previewFolderDefaults: defaults)
        defer {
            f.model.reset()
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
            try? FileManager.default.removeItem(at: f.directory)
        }
        XCTAssertNotNil(f.model.connectVideoFolder(f.urls[0]))
        XCTAssertNotNil(f.model.connectVideoFolder(try XCTUnwrap(URL(string: "https://example.com/videos"))))
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: f.directory.path)
        XCTAssertNotNil(f.model.connectVideoFolder(f.directory))
        XCTAssertNil(defaults.array(forKey: PreviewFolderBookmarkStore.key))
        XCTAssertTrue(f.model.fileCardSnapshots.isEmpty)
        XCTAssertNil(f.model.activePreview)
        XCTAssertTrue(f.model.consumeInitialVideoFolderAccessRequest())
    }

    @MainActor
    func testMissingFolderAccessRequestsOncePerSourceAndKeepsPlayback() async throws {
        for codec: TaptionVideoCodec in [.h264, .hevcWithAlpha] {
            let f = try await makePreviewQueueBrowserFixture(codec: codec)
            defer {
                f.model.reset()
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
                try? FileManager.default.removeItem(at: f.directory)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: f.directory.path)
            f.model.openExternalPlayerFile(url: f.urls[1])
            try await waitForReadyToStartState(in: f.model, timeout: 10)
            let original = try XCTUnwrap(f.model.activePreview)
            XCTAssertNotNil(original.folderAccessURL)
            XCTAssertFalse(f.model.consumePreviewFolderAccessRequest(for: "stale-preview"))
            XCTAssertTrue(f.model.consumePreviewFolderAccessRequest(for: original.id))
            XCTAssertFalse(f.model.consumePreviewFolderAccessRequest(for: original.id))
            XCTAssertEqual(f.model.activePreview, original)
            f.model.closePreviewFromPlayer()
            XCTAssertFalse(f.model.consumePreviewFolderAccessRequest(for: original.id))
            f.model.openPreviewForFileCard(id: original.id)
            XCTAssertEqual(f.model.activePreview?.sourceURL, original.sourceURL)
            XCTAssertFalse(f.model.consumePreviewFolderAccessRequest(for: original.id), "Reopening the same source does not nag after declining")
            f.model.openExternalPlayerFile(url: f.urls[0])
            try await waitForCondition(timeout: 10) { f.model.activePreview?.sourceURL == f.urls[0] }
            XCTAssertTrue(f.model.consumePreviewFolderAccessRequest(for: f.urls[0].absoluteString), "A new external source can request access")
            let wallet = await f.wallet.currentSnapshot()
            let encodeCalls = await f.encoder.callCount()
            XCTAssertEqual(wallet.balance, 3)
            XCTAssertEqual(encodeCalls, 0)
            f.model.reset()
            XCTAssertFalse(f.model.consumeInitialVideoFolderAccessRequest(), "An external-video request also satisfies the first-launch invitation")
        }
    }

    @MainActor
    func testReadableFolderDoesNotRequestAccessForExternalFile() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer { f.model.reset(); try? FileManager.default.removeItem(at: f.directory) }
        f.model.openExternalPlayerFile(url: f.urls[1])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        let preview = try XCTUnwrap(f.model.activePreview)
        XCTAssertEqual(preview.playlist?.positionText, "2 / 3")
        XCTAssertFalse(f.model.consumePreviewFolderAccessRequest(for: preview.id))
    }

    @MainActor
    func testSwipeRestoresTransientlyUnavailableFolderAndNavigatesImmediately() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
            try? FileManager.default.removeItem(at: f.directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: f.directory.path)
        f.model.openExternalPlayerFile(url: f.urls[1])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        XCTAssertNotNil(f.model.activePreview?.folderAccessURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
        XCTAssertTrue(f.model.restoreSingleFilePreviewNavigation(offset: 1))
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[2] }
        XCTAssertNil(f.model.activePreview?.folderAccessURL)
        XCTAssertEqual(f.model.activePreview?.playlist?.positionText, "3 / 3")
        f.model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[1] }
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
        let wallet = await f.wallet.currentSnapshot()
        let encodeCalls = await f.encoder.callCount()
        XCTAssertEqual(wallet.balance, 3)
        XCTAssertEqual(encodeCalls, 0)
        f.model.closePreviewFromPlayer()
    }

    @MainActor
    func testSwipeCannotInventFolderPermissionOrReplaceCurrentPlayback() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
            try? FileManager.default.removeItem(at: f.directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: f.directory.path)
        f.model.openExternalPlayerFile(url: f.urls[1])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        let original = try XCTUnwrap(f.model.activePreview)
        XCTAssertFalse(f.model.restoreSingleFilePreviewNavigation(offset: 0))
        XCTAssertFalse(f.model.restoreSingleFilePreviewNavigation(offset: 1))
        XCTAssertFalse(f.model.restoreSingleFilePreviewNavigation(offset: -1))
        XCTAssertEqual(f.model.activePreview, original)
        XCTAssertNil(f.model.folderPreviewContext)
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
        f.model.closePreviewFromPlayer()
    }

    @MainActor
    func testConnectedFolderSurvivesOneAddedVideoAndQueueReopen() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        f.model.startFolderFlow(url: f.directory)
        f.model.selectFolderPreviewFile(id: f.urls[1].absoluteString)
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[1] }
        XCTAssertTrue(f.model.addPreviewToList(try XCTUnwrap(f.model.activePreview)))
        f.model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
        f.model.openPreviewForFileCard(id: f.urls[1].absoluteString)
        XCTAssertEqual(f.model.activePreview?.playlist?.totalCount, 3)
        XCTAssertNil(f.model.activePreview?.folderAccessURL)
        f.model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[0] }
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
    }

    @MainActor
    func testAlbumAutoLinksExactOrderedListAndLoadsNeighboursOnlyWhenPlayed() async throws {
        let loader = RecordingPhotoVideoLoader()
        let f = try await makePreviewQueueBrowserFixture(photoVideoLoader: loader)
        let videos = ["a", "b", "c"].map { PhotoLibraryVideo(id: $0, fileName: "\($0).mp4", duration: 10) }
        defer { f.model.reset(); try? FileManager.default.removeItem(at: f.directory) }
        f.model.startPhotoLibraryFlow(.init(albumName: "Trip", videos: videos, selectedID: "b"))
        try await waitForCondition(timeout: 10) { f.model.activePreview?.displayName == "b.mp4" }
        XCTAssertFalse(f.model.consumePreviewFolderAccessRequest(for: try XCTUnwrap(f.model.activePreview).id))
        var calls = await loader.loadedIDs()
        XCTAssertEqual(calls, ["b"])
        XCTAssertEqual(f.model.activePreview?.playlist?.currentIndex, 1)
        XCTAssertEqual(f.model.activePreview?.playlist?.totalCount, 3)
        XCTAssertNil(f.model.activePreview?.folderAccessURL)
        XCTAssertEqual(f.model.fileCardSnapshots.map(\.fileName), ["b.mp4"])
        XCTAssertEqual(f.model.fileCardSnapshots.first?.sourceKind, .photos)
        f.model.openNextPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.displayName == "c.mp4" }
        XCTAssertEqual(f.model.activePreview?.playlist?.currentIndex, 2)
        f.model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.displayName == "b.mp4" }
        calls = await loader.loadedIDs()
        XCTAssertEqual(calls, ["b", "c"])
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
        let wallet = await f.wallet.currentSnapshot(); XCTAssertEqual(wallet.balance, 3)
        let encodes = await f.encoder.callCount(); XCTAssertEqual(encodes, 0)
    }

    @MainActor
    func testAlbumAddedSubsetKeepsFullPlaylistAfterQueueReopen() async throws {
        let loader = RecordingPhotoVideoLoader()
        let f = try await makePreviewQueueBrowserFixture(photoVideoLoader: loader)
        let videos = ["a", "b", "c"].map { PhotoLibraryVideo(id: $0, fileName: "\($0).mp4", duration: 10) }
        defer { f.model.reset(); try? FileManager.default.removeItem(at: f.directory) }
        f.model.startPhotoLibraryFlow(.init(albumName: "Trip", videos: videos, selectedID: "b"))
        try await waitForCondition(timeout: 10) { f.model.activePreview?.displayName == "b.mp4" }
        f.model.openNextPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.displayName == "c.mp4" }
        XCTAssertTrue(f.model.addPreviewToList(try XCTUnwrap(f.model.activePreview)))
        f.model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        XCTAssertEqual(f.model.fileCardSnapshots.map(\.fileName), ["b.mp4", "c.mp4"])
        XCTAssertTrue(f.model.fileCardSnapshots.allSatisfy { $0.sourceKind == .photos })
        let first = try XCTUnwrap(f.model.fileCardSnapshots.first)
        f.model.openPreviewForFileCard(id: first.id)
        XCTAssertEqual(f.model.activePreview?.displayName, "b.mp4")
        XCTAssertEqual(f.model.activePreview?.playlist?.totalCount, 3)
        f.model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.displayName == "a.mp4" }
        XCTAssertFalse(f.model.isPreviewAddedToList(try XCTUnwrap(f.model.activePreview)))
        XCTAssertNil(f.model.activePreview?.folderAccessURL)
    }

    @MainActor
    func testAlbumNavigationUsesSelectionOrderAndSkipsUnavailableVideo() async throws {
        let loader = RecordingPhotoVideoLoader(unavailable: ["missing"])
        let f = try await makePreviewQueueBrowserFixture(photoVideoLoader: loader)
        defer { f.model.reset(); try? FileManager.default.removeItem(at: f.directory) }
        let videos = ["z", "missing", "a"].map { PhotoLibraryVideo(id: $0, fileName: "\($0).mp4", duration: 10) }
        f.model.startPhotoLibraryFlow(.init(albumName: "Custom", videos: videos, selectedID: "z"))
        try await waitForCondition(timeout: 10) { f.model.activePreview?.displayName == "z.mp4" }
        f.model.openNextPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.displayName == "a.mp4" }
        XCTAssertEqual(f.model.activePreview?.playlist?.totalCount, 2)
        XCTAssertEqual(f.model.activePreview?.playlist?.currentIndex, 1)
        f.model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.displayName == "z.mp4" }
        XCTAssertEqual(f.model.fileCardSnapshots.map(\.fileName), ["z.mp4"])
    }

    @MainActor
    func testAlbumFallbackClearsUnrelatedFileFolderAccessAndNeighbours() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        f.model.openExternalPlayerFile(url: f.directory.appendingPathComponent("not-granted/b.mp4"))
        try await waitForCondition(timeout: 10) { f.model.activePreview != nil }
        XCTAssertNotNil(f.model.activePreview?.folderAccessURL)
        f.model.startPhotosFlow(url: f.urls[0], displayName: "Photo.mp4")
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        f.model.openPreviewForFileCard(id: "Photo.mp4")
        XCTAssertNil(f.model.activePreview?.folderAccessURL)
        XCTAssertNil(f.model.activePreview?.playlist)
    }

    @MainActor
    func testAlbumSupersededNeighbourCannotReplaceNewFolderPreview() async throws {
        let loader = RecordingPhotoVideoLoader(delayed: ["slow"])
        let f = try await makePreviewQueueBrowserFixture(photoVideoLoader: loader)
        defer { f.model.reset(); try? FileManager.default.removeItem(at: f.directory) }
        let videos = ["a", "slow"].map { PhotoLibraryVideo(id: $0, fileName: "\($0).mp4", duration: 10) }
        f.model.startPhotoLibraryFlow(.init(albumName: "Old", videos: videos, selectedID: "a"))
        try await waitForCondition(timeout: 10) { f.model.activePreview?.displayName == "a.mp4" }
        f.model.openNextPreview()
        f.model.openConnectedFilesFolder(f.directory)
        f.model.selectFolderPreviewFile(id: f.urls[1].absoluteString)
        try await waitForCondition(timeout: 10) { f.model.activePreview?.sourceURL == f.urls[1] }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(f.model.activePreview?.sourceURL, f.urls[1])
        XCTAssertEqual(f.model.activePreview?.playlist?.totalCount, 3)
        XCTAssertNil(f.model.activePreview?.folderAccessURL)
    }

    func testSharedPhotoLoadWaiterCancelsWithoutWaitingForWriter() async throws {
        let producer = Task<Void, Error> { try await Task.sleep(for: .seconds(30)) }
        defer { producer.cancel() }
        let wait = Task { try await PhotoVideoLoadWaiter.wait(for: producer) }
        try await Task.sleep(for: .milliseconds(20))
        wait.cancel()
        do { try await wait.value; XCTFail("Cancelled photo wait succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(producer.isCancelled, "A shared writer must not be cancelled by one view")
    }

    @MainActor
    func testSingleFilePreviewDiscoversSiblingsWithoutQueueingThem() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        f.model.openExternalPlayerFile(url: f.urls[1])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        let preview = try XCTUnwrap(f.model.activePreview)
        XCTAssertEqual(preview.sourceURL, f.urls[1])
        XCTAssertEqual(preview.playlist?.currentIndex, 1)
        XCTAssertEqual(preview.playlist?.totalCount, 3)
        XCTAssertEqual(preview.playlist?.previousID, f.urls[0].absoluteString)
        XCTAssertEqual(preview.playlist?.nextID, f.urls[2].absoluteString)
        XCTAssertEqual(f.model.fileCardSnapshots.map(\.fileName), ["b.mp4"])
        XCTAssertEqual(f.inspector.inspectionCount, 1, "Siblings are inspected only when played")
        f.model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[0] }
        XCTAssertFalse(try XCTUnwrap(f.model.activePreview?.playlist).hasPrevious)
        f.model.openPreviousPreview()
        XCTAssertEqual(f.model.activePreview?.sourceURL, f.urls[0])
        f.model.openNextPreview()
        XCTAssertEqual(f.model.activePreview?.sourceURL, f.urls[1])
        f.model.openNextPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[2] }
        XCTAssertFalse(try XCTUnwrap(f.model.activePreview?.playlist).hasNext)
        f.model.openNextPreview()
        XCTAssertEqual(f.model.activePreview?.sourceURL, f.urls[2])
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
        let balance = await f.wallet.currentSnapshot()
        XCTAssertEqual(balance.balance, 3)
        let calls = await f.encoder.callCount()
        XCTAssertEqual(calls, 0)
        f.model.closePreviewFromPlayer()
    }

    @MainActor
    func testSingleFileSiblingAddCommitsOnlyAddedFilesAndKeepsFolderNavigation() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        f.model.openExternalPlayerFile(url: f.urls[1])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        f.model.openNextPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[2] }
        let preview = try XCTUnwrap(f.model.activePreview)
        XCTAssertFalse(f.model.isPreviewAddedToList(preview))
        XCTAssertTrue(f.model.addPreviewToList(preview))
        XCTAssertFalse(f.model.addPreviewToList(preview))
        XCTAssertEqual(f.model.activePreview, preview)
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
        f.model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        XCTAssertEqual(f.model.fileCardSnapshots.map(\.id), [f.urls[1].absoluteString, f.urls[2].absoluteString])
        f.model.openPreviewForFileCard(id: f.urls[1].absoluteString)
        XCTAssertEqual(f.model.activePreview?.playlist?.totalCount, 3)
        f.model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[0] }
        XCTAssertFalse(f.model.isPreviewAddedToList(try XCTUnwrap(f.model.activePreview)))
        f.model.closePreviewFromPlayer()
        let balance = await f.wallet.currentSnapshot()
        XCTAssertEqual(balance.balance, 3)
        let calls = await f.encoder.callCount()
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testSingleFileSiblingFastReturnCancelsPendingNavigation() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        f.model.openExternalPlayerFile(url: f.urls[1])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        f.model.openNextPreview()
        f.model.openPreviewForFileCard(id: f.urls[1].absoluteString)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(f.model.activePreview?.sourceURL, f.urls[1])
        f.model.openNextPreview()
        f.model.closePreviewFromPlayer()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(f.model.activePreview)
    }

    @MainActor
    func testSingleFileSiblingQueueEditsDoNotRestoreRemovedItems() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        f.model.openExternalPlayerFile(url: f.urls[1])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        f.model.openNextPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[2] }
        XCTAssertTrue(f.model.addPreviewToList(try XCTUnwrap(f.model.activePreview)))
        f.model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        f.model.moveQueueFiles(draggedID: f.urls[2].absoluteString, before: f.urls[1].absoluteString)
        f.model.finishQueueMove()
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        f.model.openPreviewForFileCard(id: f.urls[2].absoluteString)
        f.model.closePreviewFromPlayer()
        XCTAssertEqual(f.model.fileCardSnapshots.map(\.id), [f.urls[2].absoluteString, f.urls[1].absoluteString])
        f.model.deleteQueueFile(id: f.urls[1].absoluteString)
        f.model.openPreviewForFileCard(id: f.urls[2].absoluteString)
        f.model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[1] }
        XCTAssertFalse(f.model.isPreviewAddedToList(try XCTUnwrap(f.model.activePreview)))
        f.model.closePreviewFromPlayer()
        XCTAssertEqual(f.model.fileCardSnapshots.map(\.id), [f.urls[2].absoluteString])
    }

    @MainActor
    func testSingleFileSiblingNaturalOrderExcludesAudioHiddenFilesAndDirectories() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: f.directory) }
        let names = ["clip10.mp4", "clip2.mp4", "notes.txt", "music.mp3", ".hidden.mp4"]
        for name in names { try Data("source".utf8).write(to: f.directory.appendingPathComponent(name)) }
        try FileManager.default.createDirectory(at: f.directory.appendingPathComponent("folder.mp4"), withIntermediateDirectories: false)
        let selected = f.directory.appendingPathComponent("clip10.mp4")
        f.model.openExternalPlayerFile(url: selected)
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        let playlist = try XCTUnwrap(f.model.activePreview?.playlist)
        XCTAssertEqual(playlist.previousName, "clip2.mp4")
        XCTAssertEqual(playlist.totalCount, 5)
        XCTAssertEqual(f.model.fileCardSnapshots.map(\.fileName), ["clip10.mp4"])
        f.model.closePreviewFromPlayer()
    }

    @MainActor
    func testSingleFileFolderGrantKeepsPlaybackAndRejectsUnrelatedFolder() async throws {
        let f = try await makePreviewQueueBrowserFixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
            try? FileManager.default.removeItem(at: f.directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: f.directory.path)
        f.model.openExternalPlayerFile(url: f.urls[0])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        let original = try XCTUnwrap(f.model.activePreview)
        XCTAssertNotNil(original.folderAccessURL)
        XCTAssertNotNil(f.model.authorizeSingleFilePreviewFolder(f.directory.appendingPathComponent("unrelated"), navigationOffset: 1))
        XCTAssertEqual(f.model.activePreview, original)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
        XCTAssertNil(f.model.authorizeSingleFilePreviewFolder(f.directory, navigationOffset: 1))
        try await waitForCondition(timeout: 5) { f.model.activePreview?.sourceURL == f.urls[1] }
        XCTAssertEqual(f.model.activePreview?.playlist?.totalCount, 3)
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
        f.model.closePreviewFromPlayer()
    }

    @MainActor
    func testConnectedPreviewFolderBookmarkSurvivesSourceAndModelReplacement() async throws {
        let suite = "PreviewFolderReconnect-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let f = try await makePreviewQueueBrowserFixture(previewFolderDefaults: defaults)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
            try? FileManager.default.removeItem(at: f.directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: f.directory.path)
        f.model.openExternalPlayerFile(url: f.urls[0])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        XCTAssertNotNil(f.model.activePreview?.folderAccessURL)
        XCTAssertTrue(f.model.consumePreviewFolderAccessRequest(for: f.urls[0].absoluteString))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
        XCTAssertNil(f.model.authorizeSingleFilePreviewFolder(f.directory, navigationOffset: 0))
        XCTAssertEqual(f.model.activePreview?.sourceURL, f.urls[0], "Connecting a folder keeps the current video")
        XCTAssertNil(f.model.activePreview?.folderAccessURL)
        let bookmarks = try XCTUnwrap(defaults.array(forKey: "preview.authorizedFolderBookmarks") as? [Data])
        XCTAssertEqual(bookmarks.count, 1)
        var stale = false
        let restored = try URL(resolvingBookmarkData: XCTUnwrap(bookmarks.first), options: [.withoutUI], bookmarkDataIsStale: &stale)
        XCTAssertEqual(restored.standardizedFileURL.path, f.directory.standardizedFileURL.path)
        f.model.closePreviewFromPlayer()
        f.model.reset()
        let replacement = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(), mediaInspector: f.inspector
        ), previewFolderDefaults: defaults)
        replacement.openExternalPlayerFile(url: f.urls[2])
        try await waitForReadyToStartState(in: replacement, timeout: 10)
        XCTAssertNil(replacement.activePreview?.folderAccessURL)
        XCTAssertFalse(replacement.consumePreviewFolderAccessRequest(for: f.urls[2].absoluteString))
        XCTAssertEqual(replacement.activePreview?.playlist?.positionText, "3 / 3")
        XCTAssertEqual(replacement.fileCardSnapshots.count, 1)
        replacement.closePreviewFromPlayer()
    }

    @MainActor
    func testInvalidAndUnrelatedFolderBookmarksDoNotGrantPreviewNavigation() async throws {
        let suite = "PreviewFolderInvalid-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let f = try await makePreviewQueueBrowserFixture(previewFolderDefaults: defaults)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.directory.path)
            try? FileManager.default.removeItem(at: f.directory)
        }
        let unrelated = f.directory.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)
        defaults.set([Data([0xff]), try unrelated.bookmarkData(options: [])], forKey: "preview.authorizedFolderBookmarks")
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: f.directory.path)
        f.model.openExternalPlayerFile(url: f.urls[0])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        XCTAssertNotNil(f.model.activePreview?.folderAccessURL)
        XCTAssertNil(f.model.activePreview?.playlist)
        XCTAssertEqual((defaults.array(forKey: "preview.authorizedFolderBookmarks") as? [Data])?.count, 1)
        let original = try XCTUnwrap(f.model.activePreview)
        XCTAssertNotNil(f.model.authorizeSingleFilePreviewFolder(unrelated, navigationOffset: 0))
        XCTAssertEqual(f.model.activePreview, original)
        f.model.closePreviewFromPlayer()
    }

    @MainActor
    func testFolderPickerGrantIsRememberedForLaterSingleFilePreview() async throws {
        let suite = "PreviewFolderSelected-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let f = try await makePreviewQueueBrowserFixture(previewFolderDefaults: defaults)
        defer { try? FileManager.default.removeItem(at: f.directory) }
        f.model.startFolderFlow(url: f.directory)
        XCTAssertEqual(f.model.folderPreviewFileSnapshots.count, 3)
        XCTAssertEqual((defaults.array(forKey: "preview.authorizedFolderBookmarks") as? [Data])?.count, 1)
        f.model.dismissFolderPreviewBrowser()
        f.model.openExternalPlayerFile(url: f.urls[1])
        try await waitForReadyToStartState(in: f.model, timeout: 10)
        XCTAssertEqual(f.model.activePreview?.playlist?.positionText, "2 / 3")
        XCTAssertNil(f.model.activePreview?.folderAccessURL)
        XCTAssertEqual(f.model.fileCardSnapshots.count, 1)
        f.model.closePreviewFromPlayer()
    }

    @MainActor
    func testPreviewListExternalVideoIsCheckedWithoutPreparingOrChargingStars() async throws {
        let fixture = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.openExternalPlayerFile(url: fixture.urls[0])
        try await waitForReadyToStartState(in: model, timeout: 10)
        let review = try XCTUnwrap(model.state.preparedEncodingReview)
        let preview = try XCTUnwrap(model.activePreview)
        XCTAssertTrue(model.isPreviewAddedToList(preview))
        XCTAssertFalse(model.addPreviewToList(preview))
        XCTAssertEqual(model.activePreview, preview)
        XCTAssertEqual(model.fileCardSnapshots.count, 1)
        XCTAssertEqual(model.state.preparedEncodingReview, review)
        XCTAssertEqual(model.state.preparedEncodingReview?.requiresEncodingPreparation, true)
        XCTAssertNil(model.miniPlayerPreview)
        let wallet = await fixture.wallet.currentSnapshot()
        let encodeCalls = await fixture.encoder.callCount()
        XCTAssertEqual(wallet.balance, 3)
        XCTAssertEqual(encodeCalls, 0)
        model.closePreviewFromPlayer()
    }

    @MainActor
    func testPreviewListRejectsDismissedReplacedAndMismatchedCallbacks() async throws {
        let fixture = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.openFilesPreviewBrowser(urls: fixture.urls)
        model.selectFolderPreviewFile(id: fixture.urls[0].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[0] }
        let old = try XCTUnwrap(model.activePreview)
        model.openNextPreview()
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[1] }
        let current = try XCTUnwrap(model.activePreview)
        XCTAssertTrue(model.canAddPreviewToList(current))
        XCTAssertFalse(model.addPreviewToList(old))
        var mismatched = current
        mismatched.sourceURL = fixture.urls[0]
        XCTAssertFalse(model.addPreviewToList(mismatched))
        XCTAssertEqual(model.activePreview, current)
        XCTAssertFalse(model.isPreviewAddedToList(old))
        model.closePreviewFromPlayer()
        XCTAssertFalse(model.addPreviewToList(current))
        XCTAssertFalse(model.isPreviewAddedToList(current))
        model.dismissFolderPreviewBrowser()
    }

    @MainActor
    func testPreviewListUnimplementedOutputRemainsBlockedOnConvert() async throws {
        let fixture = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.selectOutputAudioCodec(.opus)
        model.openFilesPreviewBrowser(urls: fixture.urls)
        model.selectFolderPreviewFile(id: fixture.urls[1].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[1] }
        let preview = try XCTUnwrap(model.activePreview)
        XCTAssertTrue(model.addPreviewToList(preview))
        XCTAssertEqual(model.activePreview, preview)
        model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: model, timeout: 10)
        XCTAssertFalse(model.selectedOutput.isImplementedNow)
        XCTAssertEqual(model.fileCardSnapshots.map(\.id), [fixture.urls[1].absoluteString])
        XCTAssertEqual(model.state.preparedEncodingReview?.requiresEncodingPreparation, true)
        model.startPreparedEncoding()
        try await waitForCondition(timeout: 10) {
            if case .completed = model.state { return true }
            return false
        }
        XCTAssertEqual(model.fileCardSnapshots.first?.statusText, "Blocked")
        let wallet = await fixture.wallet.currentSnapshot()
        let encodeCalls = await fixture.encoder.callCount()
        XCTAssertEqual(wallet.balance, 3)
        XCTAssertEqual(encodeCalls, 0)
    }

    @MainActor
    func testPreviewListDefersStorageBlockUntilConvertWithoutChargingStars() async throws {
        let fixture = try await makePreviewQueueBrowserFixture(availableBytes: 0)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.openFilesPreviewBrowser(urls: fixture.urls)
        model.selectFolderPreviewFile(id: fixture.urls[2].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[2] }
        let preview = try XCTUnwrap(model.activePreview)
        XCTAssertTrue(model.addPreviewToList(preview))
        XCTAssertEqual(model.activePreview, preview)
        XCTAssertNil(model.state.preparedEncodingReview)
        model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: model, timeout: 10)
        XCTAssertEqual(model.state.preparedEncodingReview?.requiresEncodingPreparation, true)
        XCTAssertEqual(model.fileCardSnapshots.map(\.id), [fixture.urls[2].absoluteString])
        model.startPreparedEncoding()
        try await waitForCondition(timeout: 10) {
            if case .completed = model.state { return true }
            return false
        }
        XCTAssertEqual(model.fileCardSnapshots.first?.statusText, "Blocked")
        XCTAssertTrue(model.fileCardSnapshots.first?.detailText?.contains("Low space") == true)
        let wallet = await fixture.wallet.currentSnapshot()
        let encodeCalls = await fixture.encoder.callCount()
        XCTAssertEqual(wallet.balance, 3)
        XCTAssertEqual(encodeCalls, 0)
    }

    @MainActor
    func testPreviewListConvertsOnlyAddedSourceWithOneStar() async throws {
        let fixture = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.openFilesPreviewBrowser(urls: fixture.urls)
        model.selectFolderPreviewFile(id: fixture.urls[1].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[1] }
        XCTAssertTrue(model.addPreviewToList(try XCTUnwrap(model.activePreview)))
        model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: model, timeout: 10)
        model.startPreparedEncoding()
        try await waitForAsyncCondition { await fixture.encoder.callCount() == 1 }
        let sources = await fixture.encoder.sourceURLs()
        let wallet = await fixture.wallet.currentSnapshot()
        XCTAssertEqual(sources, [fixture.urls[1]])
        XCTAssertEqual(wallet.balance, 2)
        XCTAssertNil(model.activePreview)
        XCTAssertNil(model.miniPlayerPreview)
    }

    @MainActor
    func testPreviewListNavigatesUninspectedFilesAndKeepsAddedStateInBothDirections() async throws {
        let fixture = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.openFilesPreviewBrowser(urls: fixture.urls)
        model.selectFolderPreviewFile(id: fixture.urls[1].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[1] }
        let second = try XCTUnwrap(model.activePreview)
        XCTAssertEqual(second.playlist?.positionText, "2 / 3")
        XCTAssertTrue(second.playlist?.hasPrevious == true)
        XCTAssertTrue(second.playlist?.hasNext == true)
        XCTAssertTrue(model.addPreviewToList(second))
        model.openNextPreview()
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[2] }
        let third = try XCTUnwrap(model.activePreview)
        XCTAssertFalse(third.playlist?.hasNext == true)
        XCTAssertFalse(model.isPreviewAddedToList(third))
        XCTAssertTrue(model.addPreviewToList(third))
        model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[1] }
        XCTAssertTrue(model.isPreviewAddedToList(try XCTUnwrap(model.activePreview)))
        XCTAssertFalse(model.addPreviewToList(try XCTUnwrap(model.activePreview)))
        model.openPreviousPreview()
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[0] }
        let first = try XCTUnwrap(model.activePreview)
        XCTAssertFalse(first.playlist?.hasPrevious == true)
        XCTAssertFalse(model.isPreviewAddedToList(first))
        XCTAssertTrue(model.addPreviewToList(first))
        XCTAssertNotNil(model.folderPreviewContext)
        XCTAssertNil(model.state.preparedEncodingReview)
        model.closePreviewFromPlayer()
        try await waitForReadyToStartState(in: model, timeout: 10)
        XCTAssertEqual(model.fileCardSnapshots.map(\.id), [fixture.urls[1], fixture.urls[2], fixture.urls[0]].map(\.absoluteString))
        XCTAssertEqual(model.state.preparedEncodingReview?.source.url, fixture.urls[1])
        XCTAssertNil(model.miniPlayerPreview)
        let wallet = await fixture.wallet.currentSnapshot()
        XCTAssertEqual(wallet.balance, 3)
    }

    @MainActor
    func testPreviewListCloseWithoutAddingReturnsToBrowserAndClearsCancelledMembership() async throws {
        let fixture = try await makePreviewQueueBrowserFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        model.openFilesPreviewBrowser(urls: fixture.urls)
        model.selectFolderPreviewFile(id: fixture.urls[0].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[0] }
        model.closePreviewFromPlayer()
        XCTAssertNil(model.activePreview)
        XCTAssertNotNil(model.folderPreviewContext)
        XCTAssertNil(model.state.preparedEncodingReview)
        model.selectFolderPreviewFile(id: fixture.urls[0].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[0] }
        XCTAssertTrue(model.addPreviewToList(try XCTUnwrap(model.activePreview)))
        model.dismissPreview()
        model.dismissFolderPreviewBrowser()
        model.openFilesPreviewBrowser(urls: fixture.urls)
        model.selectFolderPreviewFile(id: fixture.urls[0].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == fixture.urls[0] }
        XCTAssertFalse(model.isPreviewAddedToList(try XCTUnwrap(model.activePreview)))
        model.closePreviewFromPlayer()
        model.dismissFolderPreviewBrowser()
    }

    @MainActor
    func testPreviewListNavigationSkipsNewlyInspectedUnplayableFile() async throws {
        let directory = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = ["a.mp4", "b.mp4", "c.mp4"].map { directory.appendingPathComponent($0) }
        for url in urls { try Data("source".utf8).write(to: url) }
        let model = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(),
            mediaInspector: URLMappedMediaInspector(assetsByLastPathComponent: [
                "a.mp4": makeAsset(sourceCodec: .h264),
                "b.mp4": makeAsset(sourceCodec: .unknown),
                "c.mp4": makeAsset(sourceCodec: .h264)
            ], fallbackAsset: makeAsset(sourceCodec: .h264))
        ))
        model.openFilesPreviewBrowser(urls: urls)
        model.selectFolderPreviewFile(id: urls[0].absoluteString)
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == urls[0] }
        XCTAssertEqual(model.activePreview?.playlist?.nextID, urls[1].absoluteString)
        model.openNextPreview()
        try await waitForCondition(timeout: 5) { model.activePreview?.sourceURL == urls[2] }
        XCTAssertEqual(model.activePreview?.playlist?.previousID, urls[0].absoluteString)
        XCTAssertEqual(model.activePreview?.playlist?.positionText, "2 / 2")
        model.closePreviewFromPlayer()
        model.dismissFolderPreviewBrowser()
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
        // The first hardware capability probe on a fresh simulator can take several seconds.
        try await waitForReadyToStartState(in: viewModel, timeout: 10)

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
    func testExternalFileOpenAutomaticallyOpensPreview() async throws {
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

        XCTAssertEqual(viewModel.activePreview?.sourceURL, sourceURL)
        XCTAssertEqual(viewModel.state.preparedEncodingReview?.requiresEncodingPreparation, true)
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
    func testExternalPreviewDefersStorageCheckAndDoesNotChargeStarWhenEncodingIsBlocked() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("low-space.mp4")
        try Data("source".utf8).write(to: sourceURL)
        let storageChecker = RecordingStorageChecker(requirement: TaptionStorageRequirement(
            estimatedOutputBytes: 1_000,
            requiredWorkingBytes: 1_024,
            availableBytes: 0
        ))
        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 3))
        let viewModel = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(),
            mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
            storageChecker: storageChecker,
            starWalletStore: walletStore
        ))
        await viewModel.refreshStarsIfNeeded()

        viewModel.openExternalPlayerFile(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)
        XCTAssertEqual(viewModel.activePreview?.sourceURL, sourceURL)
        XCTAssertEqual(storageChecker.checkCount, 0)
        XCTAssertEqual(viewModel.state.preparedEncodingReview?.requiresEncodingPreparation, true)

        viewModel.startPreparedEncoding()
        try await waitForStorageBlockedState(in: viewModel)
        XCTAssertEqual(storageChecker.checkCount, 1)
        let wallet = await walletStore.currentSnapshot()
        XCTAssertEqual(wallet.balance, 3)
    }

    @MainActor
    func testExternalPreviewIsRepreparedBeforeEncodingStarts() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("encode-after-preview.mp4")
        try Data("source".utf8).write(to: sourceURL)
        let storageChecker = RecordingStorageChecker(requirement: TaptionStorageRequirement(
            estimatedOutputBytes: 1_000,
            requiredWorkingBytes: 1_024,
            availableBytes: 1_000_000
        ))
        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 3))
        let viewModel = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(),
            mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
            encoderService: CancellableEncoderService(),
            storageChecker: storageChecker,
            starWalletStore: walletStore
        ))
        await viewModel.refreshStarsIfNeeded()
        viewModel.openExternalPlayerFile(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        viewModel.startPreparedEncoding()
        try await waitForCondition(timeout: 2) {
            if case .encoding = viewModel.state { return true }
            return false
        }
        XCTAssertEqual(storageChecker.checkCount, 1)
        XCTAssertNil(viewModel.activePreview)
        let wallet = await walletStore.currentSnapshot()
        XCTAssertEqual(wallet.balance, 2)
        viewModel.openExternalPlayerFile(url: directoryURL.appendingPathComponent("replacement.mp4"))
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.fileName, sourceURL.lastPathComponent)
        XCTAssertEqual(storageChecker.checkCount, 1)
        viewModel.cancel()
        try await waitForCondition(timeout: 2) { viewModel.state == .cancelled }
    }

    @MainActor
    func testExternalPreviewDoesNotRequireImplementedEncodingOutput() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/playback-only.mp4")
        let storageChecker = RecordingStorageChecker(requirement: TaptionStorageRequirement(
            estimatedOutputBytes: 1_000,
            requiredWorkingBytes: 1_024,
            availableBytes: 0
        ))
        let viewModel = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(),
            mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
            storageChecker: storageChecker
        ))
        viewModel.selectOutputAudioCodec(.opus)
        XCTAssertFalse(viewModel.selectedOutput.isImplementedNow)
        viewModel.openExternalPlayerFile(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertEqual(viewModel.activePreview?.sourceURL, sourceURL)
        XCTAssertEqual(storageChecker.checkCount, 0)
    }

    @MainActor
    func testCloudDownloadFailureIsActionableAndPreventsInspection() async throws {
        let inspector = CountingMediaInspector(asset: makeAsset(sourceCodec: .h264))
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(), mediaInspector: inspector
            ),
            sourceDownloader: FailingVideoSourceDownloader(error: VideoSourceDownloadError.timedOut)
        )
        viewModel.openExternalPlayerFile(url: URL(fileURLWithPath: "/tmp/cloud.mp4"))
        try await waitForCondition(timeout: 2) {
            if case .failed = viewModel.state { return true }
            return false
        }
        guard case .failed(let failure) = viewModel.state else {
            return XCTFail("Expected an iCloud download failure")
        }
        XCTAssertEqual(failure.title, "iCloud download failed")
        XCTAssertTrue(failure.message.contains("open Files, download the video"))
        XCTAssertEqual(inspector.inspectionCount, 0)
        XCTAssertNil(viewModel.activePreview)
    }

    @MainActor
    func testExternalHEVCAlphaSubtitleOpensPreview() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/subtitles.mov")
        var asset = makeAsset(sourceCodec: .hevcWithAlpha,
                              displaySize: TaptionPixelSize(width: 720, height: 720))
        asset.container = .mov
        asset.audioTracks = []
        let storageChecker = RecordingStorageChecker(requirement: TaptionStorageRequirement(
            estimatedOutputBytes: 1_000,
            requiredWorkingBytes: 1_024,
            availableBytes: 0
        ))
        let viewModel = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(),
            mediaInspector: StubMediaInspector(asset: asset),
            storageChecker: storageChecker
        ))
        viewModel.openExternalPlayerFile(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)

        XCTAssertEqual(viewModel.activePreview?.sourceURL, sourceURL)
        XCTAssertEqual(viewModel.activePreview?.videoInfo.audio, "No audio")
        XCTAssertEqual(viewModel.activePreview?.usesNativePlayback, true)
        XCTAssertEqual(viewModel.activePreview?.displaySize, TaptionPixelSize(width: 720, height: 720))
        XCTAssertEqual(storageChecker.checkCount, 0)
    }

    @MainActor
    func testCloudDownloadCancellationDoesNotShowEncodingFailure() async throws {
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: FakePendingSaveStore()),
            sourceDownloader: FailingVideoSourceDownloader(error: CancellationError())
        )
        viewModel.openExternalPlayerFile(url: URL(fileURLWithPath: "/tmp/cloud.mp4"))
        try await waitForCondition(timeout: 2) { viewModel.state == .cancelled }
        XCTAssertNil(viewModel.activePreview)
    }

    func testCloudDownloaderAcceptsCurrentAndDownloadedWithoutRequestingDownload() async throws {
        for status in [URLUbiquitousItemDownloadingStatus.current, .downloaded] {
            var downloadRequests = 0
            let downloader = UbiquitousVideoDownloader(
                readState: { _ in UbiquitousVideoDownloadState(isUbiquitous: true, status: status) },
                requestDownload: { _ in downloadRequests += 1 }
            )
            try await downloader.ensureLocalVideo(at: URL(fileURLWithPath: "/tmp/cloud.mp4"))
            XCTAssertEqual(downloadRequests, 0)
        }
    }

    func testCloudDownloaderAcceptsCurrentAtFinalPoll() async throws {
        var downloadRequests = 0
        var sleeps = 0
        let downloader = UbiquitousVideoDownloader(
            readState: { _ in UbiquitousVideoDownloadState(
                isUbiquitous: true, status: sleeps == 2 ? .current : .notDownloaded
            ) },
            requestDownload: { _ in downloadRequests += 1 },
            sleep: { _ in sleeps += 1 },
            pollAttempts: 2
        )
        try await downloader.ensureLocalVideo(at: URL(fileURLWithPath: "/tmp/cloud.mp4"))
        XCTAssertEqual(downloadRequests, 1)
        XCTAssertEqual(sleeps, 2)
    }

    func testCloudDownloaderReportsTimeout() async throws {
        let downloader = UbiquitousVideoDownloader(
            readState: { _ in UbiquitousVideoDownloadState(isUbiquitous: true, status: .notDownloaded) },
            requestDownload: { _ in }, sleep: { _ in }, pollAttempts: 2
        )
        do {
            try await downloader.ensureLocalVideo(at: URL(fileURLWithPath: "/tmp/cloud.mp4"))
            XCTFail("Expected a download timeout")
        } catch VideoSourceDownloadError.timedOut {
            // The timeout stays distinct from provider and encoding failures.
        }
    }

    func testCloudDownloaderPreservesProviderError() async throws {
        let providerError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let downloader = UbiquitousVideoDownloader(
            readState: { _ in UbiquitousVideoDownloadState(
                isUbiquitous: true, status: .notDownloaded, error: providerError
            ) },
            requestDownload: { _ in }
        )
        do {
            try await downloader.ensureLocalVideo(at: URL(fileURLWithPath: "/tmp/cloud.mp4"))
            XCTFail("Expected a provider error")
        } catch VideoSourceDownloadError.unavailable(let error) {
            XCTAssertEqual((error as NSError).code, NSURLErrorNotConnectedToInternet)
        }
    }

    func testCloudDownloaderPropagatesCancellation() async throws {
        let downloader = UbiquitousVideoDownloader(
            readState: { _ in UbiquitousVideoDownloadState(isUbiquitous: true, status: .notDownloaded) },
            requestDownload: { _ in }, sleep: { _ in throw CancellationError() }
        )
        do {
            try await downloader.ensureLocalVideo(at: URL(fileURLWithPath: "/tmp/cloud.mp4"))
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Cancellation must not become an iCloud or encoding error.
        }
    }

    func testCloudDownloaderSkipsNonUbiquitousAndRemoteURLs() async throws {
        var reads = 0
        var requests = 0
        let downloader = UbiquitousVideoDownloader(
            readState: { _ in
                reads += 1
                return UbiquitousVideoDownloadState(isUbiquitous: false)
            },
            requestDownload: { _ in requests += 1 }
        )
        try await downloader.ensureLocalVideo(at: URL(fileURLWithPath: "/tmp/local.mp4"))
        try await downloader.ensureLocalVideo(at: URL(string: "https://example.com/video.mp4")!)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(requests, 0)
    }

    @MainActor
    func testKnownBlackPreviewCodecStaysEncodableWithoutOpeningPreview() async throws {
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
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.isEnabled, true)
        XCTAssertEqual(viewModel.fileCardSnapshots.first?.isPreviewable, false)

        viewModel.openPreviewForFileCard(id: "lossless.avi")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(viewModel.activePreview)
    }

    @MainActor
    func testKnownBlackPreviewCodecsStayEncodableButNotPreviewableInQueue() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let previewBlockedInputs: [(filename: String, codec: TaptionVideoCodec)] = [
            ("Snow.avi", .snow),
            ("R210.avi", .r210),
            ("R10K.mov", .r10k),
            ("Microsoft RLE.avi", .microsoftRLE),
            ("Lossless JPEG.avi", .losslessJPEG)
        ]
        let fileURLs = try previewBlockedInputs.map { input in
            let url = directoryURL.appendingPathComponent(input.filename)
            try Data("source".utf8).write(to: url)
            return url
        }
        let assetsByName = Dictionary(
            uniqueKeysWithValues: previewBlockedInputs.map { input in
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
            viewModel.fileCardSnapshots.count == previewBlockedInputs.count
        }

        for input in previewBlockedInputs {
            let snapshot = try XCTUnwrap(
                viewModel.fileCardSnapshots.first { $0.fileName == input.filename }
            )
            XCTAssertTrue(snapshot.isEnabled, "\(input.filename) should remain encodable.")
            XCTAssertFalse(snapshot.isPreviewable, "\(input.filename) should not open a black preview.")
            XCTAssertEqual(snapshot.thumbnailSourceURL?.lastPathComponent, input.filename)
        }

        let firstURL = try XCTUnwrap(fileURLs.first)
        viewModel.openPreviewForFileCard(id: firstURL.absoluteString)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(viewModel.activePreview)
    }

    @MainActor
    func testRenderableLegacyAndProResPreviewCodecsStayPlayableInQueue() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let previewInputs: [(filename: String, codec: TaptionVideoCodec)] = [
            ("RoQ Video.roq", .roqVideo),
            ("V210.avi", .v210),
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
        try await waitForReadyToStartState(in: viewModel, timeout: 10)

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

}
