//
//  CodecRoutePlannerTests+EncodingAndStandard.swift
//  Tests 15464-17387 of the original CodecRoutePlannerTests.swift, moved here
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

    internal struct FakeFFmpegCommandRunner: SW_FFmpegCommandRunning {
        var runBlock: @Sendable (SW_FFmpegCommandPlan) async throws -> SW_FFmpegCommandRunResult

        func run(commandPlan: SW_FFmpegCommandPlan) async throws -> SW_FFmpegCommandRunResult {
            try await runBlock(commandPlan)
        }
    }

    internal final class TestStarWalletSecureStore: @unchecked Sendable, StarWalletSecureStoring {
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

    internal actor RecordingRewardedAdProvider: RewardedAdProviding {
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

    internal actor CyclingRewardedAdProvider: RewardedAdProviding {
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

    internal actor RetryingRewardedAdProvider: RewardedAdProviding {
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

    internal actor RecordingSessionEndAdProvider: SessionEndAdProviding {
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

    internal actor RecordingBackgroundEncodingCoordinator: BackgroundEncodingCoordinating {
        nonisolated var support: TaptionBackgroundEncodingSupport {
            .availableWhenUserChooses
        }

        private let observedFinalOutputURL: URL?
        private var beginPlanIDs: [UUID] = []
        private var endPlanIDs: [UUID] = []
        private var finalOutputPresenceAtEnd: [Bool] = []

        init(observedFinalOutputURL: URL? = nil) {
            self.observedFinalOutputURL = observedFinalOutputURL
        }

        func beginBackgroundEncoding(plan: TaptionEncodingPlan) async throws {
            beginPlanIDs.append(plan.id)
        }

        func updateBackgroundEncoding(
            planID: UUID,
            snapshot: TaptionBackgroundEncodingSnapshot
        ) async {}

        func endBackgroundEncoding(planID: UUID) async {
            endPlanIDs.append(planID)
            if let observedFinalOutputURL {
                finalOutputPresenceAtEnd.append(
                    FileManager.default.fileExists(atPath: observedFinalOutputURL.path)
                )
            }
        }

        func recordedBeginPlanIDs() -> [UUID] {
            beginPlanIDs
        }

        func recordedEndPlanIDs() -> [UUID] {
            endPlanIDs
        }

        func recordedFinalOutputPresenceAtEnd() -> [Bool] {
            finalOutputPresenceAtEnd
        }
    }

    internal struct ImmediateEncoderService: EncoderServicing {
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

    internal final class MutableBatteryPowerMonitor: BatteryPowerMonitoring {
        var snapshot: BatteryEncodingPowerSnapshot

        init(snapshot: BatteryEncodingPowerSnapshot) {
            self.snapshot = snapshot
        }

        var currentSnapshot: BatteryEncodingPowerSnapshot {
            snapshot
        }
    }

    internal struct PowerDisconnectingEncoderService: EncoderServicing {
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

    internal struct BatteryDroppingEncoderService: EncoderServicing {
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

    internal struct FailingEncoderService: EncoderServicing {
        func encode(
            plan: TaptionEncodingPlan,
            progress: @escaping (TaptionEncodingProgress) -> Void
        ) async throws -> TaptionEncodingResult {
            progress(TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0))
            throw TaptionVideoCoreError.exportFailed("Synthetic encoding failure.")
        }

        func cancelEncoding(planID: UUID) async {}
    }

    internal struct CancellableEncoderService: EncoderServicing {
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

    internal struct FixedStorageChecker: StorageChecking {
        var requirement: TaptionStorageRequirement

        func storageRequirement(for plan: TaptionEncodingPlan) async throws -> TaptionStorageRequirement {
            requirement
        }
    }

    internal final class RecordingStorageChecker: StorageChecking {
        private let queue = DispatchQueue(label: "com.taption.encoder.tests.storage-checker")
        private let requirement: TaptionStorageRequirement
        private var count = 0

        init(requirement: TaptionStorageRequirement) { self.requirement = requirement }
        var checkCount: Int { queue.sync { count } }

        func storageRequirement(for plan: TaptionEncodingPlan) async throws -> TaptionStorageRequirement {
            queue.sync { count += 1 }
            return requirement
        }
    }

    internal struct FailingVideoSourceDownloader: VideoSourceDownloading {
        var error: Error
        func ensureLocalVideo(at url: URL) async throws { throw error }
    }

    internal struct StubMediaInspector: MediaInspecting {
        var asset: TaptionVideoAsset

        func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
            var inspectedAsset = asset
            inspectedAsset.displayName = url.lastPathComponent
            inspectedAsset.location = TaptionVideoAssetLocation(kind: .file, url: url)
            return inspectedAsset
        }
    }

    internal struct URLMappedMediaInspector: MediaInspecting {
        var assetsByLastPathComponent: [String: TaptionVideoAsset]
        var fallbackAsset: TaptionVideoAsset

        func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
            var inspectedAsset = assetsByLastPathComponent[url.lastPathComponent] ?? fallbackAsset
            inspectedAsset.displayName = url.lastPathComponent
            inspectedAsset.location = TaptionVideoAssetLocation(kind: .file, url: url)
            return inspectedAsset
        }
    }

    internal final class CountingMediaInspector: MediaInspecting {
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

    internal func readyBroadSoftwareBackendReport() -> TaptionSoftwareCodecBackendReadinessReport {
        SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(
            isBundledInCurrentBuild: true,
            satisfiedGates: Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
        )
    }

    internal func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TaptionEncoderTests-\(UUID().uuidString)", isDirectory: true)
    }

    internal func testMediaFingerprint(for url: URL) throws -> TaptionMediaFingerprint {
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

    internal func makeStarWalletSnapshot(
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

    internal func expectedCompletedSaveDetail(
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

    internal func makeHomeViewModelTestEnvironment(
        pendingSaveStore: PendingSaveStoring,
        mediaInspector: MediaInspecting = FakeMediaInspector(),
        encoderService: EncoderServicing = FakeEncoderService(),
        storageChecker: StorageChecking = FakeStorageChecker(),
        rewardedAdProvider: RewardedAdProviding = FakeRewardedAdProvider(),
        sessionEndAdProvider: SessionEndAdProviding = FakeSessionEndAdProvider(),
        starWalletStore: StarWalletManaging = FakeStarWalletStore(),
        backgroundCoordinator: BackgroundEncodingCoordinating = FakeBackgroundEncodingCoordinator()
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
            backgroundCoordinator: backgroundCoordinator,
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
        // Deliberately stops at the call: this asserts the task is created with the priority derived
        // from the profile, not which expression holds the profile.
        XCTAssertTrue(source.contains("Task(priority: taskPriority(for: "))
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
    internal func waitForPendingSaveDestinationPrompt(
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
    internal func chooseFolderForPendingSaveDestination(
        in viewModel: HomeViewModel,
        timeout: TimeInterval = 2
    ) async throws {
        try await waitForPendingSaveDestinationPrompt(in: viewModel, timeout: timeout)
        let prompt = try XCTUnwrap(viewModel.pendingSaveDestinationPrompt)
        viewModel.chooseFolderForPendingSave(prompt: prompt)
    }

    @MainActor
    internal func waitForCompletedSave(
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
    internal func waitForStorageBlockedState(
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
    internal func waitForReadyToStartState(
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
    internal func waitForCondition(
        timeout: TimeInterval,
        _ condition: @MainActor @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(condition())
    }

    internal func makeH261ToHEVCCommandPlan(
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

    internal func temporaryTestURL(fileName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    }

    /// Resolves a playback fixture: `TAPTION_PLAYBACK_FIXTURE` wins, then `<host home>/Downloads/<fileName>`,
    /// then the app container's Documents folder.
    ///
    /// Playback regressions are reported against real files, so the fixture lives outside the
    /// repository rather than bloating it with a 100 MB asset. `SIMULATOR_HOST_HOME` is the only way
    /// to reach the host home from a simulated app (`NSHomeDirectory()` returns the app container).
    /// A physical device has no host filesystem, so the same file is pushed into Documents first:
    ///
    /// ```
    /// xcrun devicectl device copy to --device <id> --source <file> \
    ///   --destination "Documents/<fileName>" --domain-type appDataContainer \
    ///   --domain-identifier <bundle id>
    /// ```
    internal func playbackFixtureURL(fileName: String) -> URL {
        let candidates: [URL] = [
            ProcessInfo.processInfo.environment["TAPTION_PLAYBACK_FIXTURE"]
                .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
            URL(fileURLWithPath: ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]
                ?? NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Downloads", isDirectory: true)
                .appendingPathComponent(fileName),
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? candidates[0]
    }

    /// Converts a decoded frame to PNG so it can be measured by `visiblePixelMetrics(fromPNGData:)`,
    /// which keeps one definition of "this frame shows something".
    internal func pngData(from pixelBuffer: CVPixelBuffer) throws -> Data {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let cgImage = try XCTUnwrap(context.createCGImage(image, from: image.extent))
        return try XCTUnwrap(UIImage(cgImage: cgImage).pngData())
    }

    internal func assertDecodedAudioSignalPresent(
        at url: URL,
        minimumPeakAmplitude: Int32 = 32
    ) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioTrack = try XCTUnwrap(audioTracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var peakAmplitude: Int32 = 0
        var inspectedSampleCount = 0
        while let sampleBuffer = output.copyNextSampleBuffer(),
              inspectedSampleCount < 44_100 {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }
            var lengthAtOffset = 0
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength,
                dataPointerOut: &dataPointer
            )
            guard status == kCMBlockBufferNoErr, let dataPointer else {
                continue
            }
            let sampleCount = totalLength / MemoryLayout<Int16>.size
            dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { samples in
                for index in 0..<sampleCount {
                    peakAmplitude = max(peakAmplitude, abs(Int32(samples[index])))
                }
            }
            inspectedSampleCount += sampleCount
        }

        XCTAssertGreaterThan(inspectedSampleCount, 0)
        XCTAssertGreaterThan(
            peakAmplitude,
            minimumPeakAmplitude,
            "Encoded audio track contained no measurable signal."
        )
    }

    internal func assertDecodedVideoSignalPresent(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        output.alwaysCopiesSampleData = false
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        let sampleBuffer = try XCTUnwrap(output.copyNextSampleBuffer())
        let pixelBuffer = try XCTUnwrap(CMSampleBufferGetImageBuffer(sampleBuffer))
        XCTAssertEqual(CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let baseAddress = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixelBuffer))
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let sampleStepX = max(width / 64, 1)
        let sampleStepY = max(height / 64, 1)
        var inspectedPixelCount = 0
        var visiblePixelCount = 0

        for y in stride(from: 0, to: height, by: sampleStepY) {
            let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width, by: sampleStepX) {
                let pixel = row.advanced(by: x * 4)
                if max(pixel[0], pixel[1], pixel[2]) > 12 {
                    visiblePixelCount += 1
                }
                inspectedPixelCount += 1
            }
        }

        XCTAssertGreaterThan(inspectedPixelCount, 0)
        XCTAssertGreaterThan(
            Double(visiblePixelCount) / Double(max(inspectedPixelCount, 1)),
            0.01,
            "Encoded video frame contained no measurable image signal."
        )
    }

    internal func bundledTestVideosURL() -> URL {
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

    internal func projectObjectBlock(id: String, label: String, in projectText: String) -> String? {
        let needle = "\t\t\(id) /* \(label) */ = {"
        guard let start = projectText.range(of: needle),
              let end = projectText[start.upperBound...].range(of: "\n\t\t};") else {
            return nil
        }
        return String(projectText[start.lowerBound..<end.upperBound])
    }

    internal func filteredBundledAvailableNowSampleFilenames() -> [String] {
        let filenames = bundledAvailableNowSampleCodecExpectations().map(\.0)
        guard let sampleFilter = ProcessInfo.processInfo.environment["TAPTION_SAMPLE_FILTER"],
              sampleFilter.isEmpty == false else {
            return filenames
        }
        let filteredFilenames = filenames.filter { $0 == sampleFilter }
        XCTAssertFalse(filteredFilenames.isEmpty, sampleFilter)
        return filteredFilenames
    }

    internal func visiblePixelMetrics(fromPNGData data: Data) throws -> (nonBlackRatio: Double, standardDeviation: Double) {
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
    internal func waitForPreviewSnapshot(
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

    internal func bundledAvailableNowSampleCodecExpectations() -> [(String, TaptionVideoCodec)] {
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
            ("Theora Vorbis.ogv", .theora),
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
            ("H.264 AC3.mp4", .h264),
            ("H.264 EAC3.mp4", .h264),
            ("H.265 HEVC.mp4", .hevc)
        ]
    }

    internal func bundledPlannedSampleCodecExpectations() -> [(String, TaptionVideoCodec)] {
        []
    }

    internal func bundledTestFixtureURL(
        resourceName: String,
        extension resourceExtension: String
    ) throws -> URL {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw XCTSkip("Missing bundled test fixture \(resourceName).\(resourceExtension).")
        }
        return url
    }

    internal func requireLocalRealSampleProofs() throws {
        let flagURL = URL(fileURLWithPath: "/tmp/taption_run_local_real_sample_tests")
        guard ProcessInfo.processInfo.environment["TAPTION_RUN_LOCAL_REAL_SAMPLE_TESTS"] == "1"
            || FileManager.default.fileExists(atPath: flagURL.path) else {
            throw XCTSkip("Local downloaded real-sample proofs are opt-in. Set TAPTION_RUN_LOCAL_REAL_SAMPLE_TESTS=1 or create \(flagURL.path) to run them.")
        }
    }

    internal func selectAV1ToHEVC(
        profile: TaptionCodecHardwareSupportProfile
    ) -> TaptionCodecRouteSelection {
        selectRoute(
            sourceCodec: .av1,
            outputCodec: .hevc,
            profile: profile
        )
    }

    internal func selectRoute(
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

    // MARK: - Standard resolution frames and fit / fill / stretch

    func testStandardPresetProducesTheExactStandardFrame() {
        // A 4:3 source used to be fitted inside 1920x1080, which produced 1440x1080 — a size the "1080p"
        // preset never promised.
        let selection = TaptionOutputSelection(resolutionPreset: .fullHD)
        let policy = selection.outputPolicy(
            for: makeAsset(
                sourceCodec: .h264,
                displaySize: TaptionPixelSize(width: 2880, height: 2160)
            )
        )

        XCTAssertEqual(policy.advancedOptions.resizeTo, TaptionPixelSize(width: 1920, height: 1080))
        XCTAssertEqual(policy.advancedOptions.scaleMode, .fit)
    }

    func testStandardPresetTurnsWithAPortraitSource() {
        let selection = TaptionOutputSelection(resolutionPreset: .fullHD)
        let policy = selection.outputPolicy(
            for: makeAsset(
                sourceCodec: .h264,
                displaySize: TaptionPixelSize(width: 1440, height: 1080)
            )
        )

        // Landscape source, landscape frame.
        XCTAssertEqual(policy.advancedOptions.resizeTo, TaptionPixelSize(width: 1920, height: 1080))

        let portraitPolicy = selection.outputPolicy(
            for: makeAsset(
                sourceCodec: .h264,
                displaySize: TaptionPixelSize(width: 1080, height: 1440)
            )
        )
        XCTAssertEqual(portraitPolicy.advancedOptions.resizeTo, TaptionPixelSize(width: 1080, height: 1920))
    }

    func testStandardPresetCanEnlargeASmallerSource() {
        let selection = TaptionOutputSelection(resolutionPreset: .uhd4k)
        let policy = selection.outputPolicy(
            for: makeAsset(
                sourceCodec: .h264,
                displaySize: TaptionPixelSize(width: 640, height: 360)
            )
        )

        XCTAssertEqual(policy.advancedOptions.resizeTo, TaptionPixelSize(width: 3840, height: 2160))
    }

    func testScaleModeIsOnlyCarriedWhenTheFrameShapeDiffers() {
        let squareSource = makeAsset(
            sourceCodec: .h264,
            displaySize: TaptionPixelSize(width: 1080, height: 1080)
        )
        let fillPolicy = TaptionOutputSelection(
            resolutionPreset: .fullHD,
            scaleMode: .fill
        ).outputPolicy(for: squareSource)
        XCTAssertEqual(fillPolicy.advancedOptions.resizeTo, TaptionPixelSize(width: 1920, height: 1080))
        XCTAssertEqual(fillPolicy.advancedOptions.scaleMode, .fill)

        // 16:9 source into a 16:9 frame: nothing to decide.
        let wideSource = makeAsset(
            sourceCodec: .h264,
            displaySize: TaptionPixelSize(width: 3840, height: 2160)
        )
        let widePolicy = TaptionOutputSelection(
            resolutionPreset: .fullHD,
            scaleMode: .fill
        ).outputPolicy(for: wideSource)
        XCTAssertNil(widePolicy.advancedOptions.scaleMode)

        XCTAssertTrue(TaptionOutputResolutionPreset.fullHD.needsScaleModeChoice(for: squareSource.videoTrack?.displaySize))
        XCTAssertFalse(TaptionOutputResolutionPreset.fullHD.needsScaleModeChoice(for: wideSource.videoTrack?.displaySize))
        XCTAssertFalse(TaptionOutputResolutionPreset.source.needsScaleModeChoice(for: squareSource.videoTrack?.displaySize))
    }

    func testOutputVerificationAcceptsAnIntentionalResize() throws {
        // This is the reported failure: changing a non-standard video to a standard frame used to fail the
        // output check because the file was compared against the untouched source.
        let sourceAsset = makeAsset(
            sourceCodec: .h264,
            displaySize: TaptionPixelSize(width: 2880, height: 2160),
            videoBitrate: 20_000_000
        )
        let selection = TaptionOutputSelection(resolutionPreset: .fullHD, scaleMode: .fill)
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: sourceAsset,
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            temporaryOutputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            outputPolicy: selection.outputPolicy(for: sourceAsset)
        )

        let outputAsset = TaptionVideoAsset(
            displayName: "output.mp4",
            location: TaptionVideoAssetLocation(kind: .temporary),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .hevc,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30),
                color: TaptionColorDescription(),
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
        XCTAssertEqual(report.metadata["expectedResolution"], "1920x1080")
        XCTAssertEqual(report.metadata["actualResolution"], "1920x1080")
    }

    func testOutputVerificationStillRejectsAFrameThePlanDidNotAskFor() {
        let sourceAsset = makeAsset(
            sourceCodec: .h264,
            displaySize: TaptionPixelSize(width: 1920, height: 1080)
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
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: .hevc,
                naturalSize: TaptionPixelSize(width: 1280, height: 720),
                displaySize: TaptionPixelSize(width: 1280, height: 720),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30),
                rotationDegrees: 0
            ),
            audioTracks: [
                TaptionAudioTrackInfo(codec: .aac, channelCount: 2, sampleRate: 48_000)
            ]
        )

        XCTAssertThrowsError(
            try TaptionSourcePreservingExecutionAudit.verifyOutput(plan: plan, outputAsset: outputAsset)
        )
    }

    func testFFmpegFilterFollowsTheSelectedScaleMode() throws {
        func filter(_ mode: TaptionVideoScaleMode) throws -> String {
            let plan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
                request: TaptionCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/source.webm"),
                    outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
                    route: TaptionCodecRoute(sourceCodec: .vp9, outputCodec: .hevc),
                    options: TaptionCodecTranscodeOptions(
                        outputPolicy: TaptionVideoOutputPolicy(
                            videoCodec: .hevc,
                            container: .mp4,
                            advancedOptions: TaptionAdvancedOutputOptions(
                                resizeTo: TaptionPixelSize(width: 1920, height: 1080),
                                scaleMode: mode
                            )
                        )
                    )
                )
            )
            let index = try XCTUnwrap(plan.arguments.firstIndex(of: "-vf"))
            return plan.arguments[index + 1]
        }

        XCTAssertEqual(
            try filter(.fit),
            "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:-1:-1:color=black,setsar=1"
        )
        XCTAssertEqual(
            try filter(.fill),
            "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,setsar=1"
        )
        XCTAssertEqual(try filter(.stretch), "scale=1920:1080,setsar=1")
    }

    // MARK: - Explicit-bitrate writer path

    func testSizedWriterEncodeOnlyTakesFramesItCanWriteFaithfully() {
        func accepts(
            sourceCodec: TaptionVideoCodec = .hevc,
            color: TaptionColorDescription = TaptionColorDescription(),
            profile: TaptionHEVCProfile = .automatic,
            container: TaptionVideoContainer = .mp4,
            audioCodec: TaptionAudioCodec = .aac
        ) -> Bool {
            HW_AppleHEVCCodecAlgorithm.requestsSizedWriterEncode(
                TaptionCodecTranscodeRequest(
                    sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
                    outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
                    route: TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: .hevc),
                    options: TaptionCodecTranscodeOptions(
                        outputPolicy: TaptionVideoOutputPolicy(
                            videoCodec: .hevc,
                            audioCodec: audioCodec,
                            container: container,
                            profile: profile,
                            advancedOptions: TaptionAdvancedOutputOptions(color: color)
                        )
                    )
                )
            )
        }

        XCTAssertTrue(accepts())
        // An HDR or 10-bit source is no longer turned away here: `resolvedOptions` copies the source's colour into
        // the request, so this predicate cannot tell "the file is HDR" from "the user asked for HDR". That decision
        // needs the source and the composition, so the writer makes it — see the HDR encode test.
        XCTAssertTrue(accepts(color: TaptionColorDescription(bitDepth: 10)))
        XCTAssertTrue(accepts(color: TaptionColorDescription(bitDepth: 10, isHDR: true)))
        // An explicit Main 10 profile is still a request this writer does not answer.
        XCTAssertFalse(accepts(profile: .main10))
        // The writer produces AAC (copying it through, or decoding the source to PCM and encoding it). An audio
        // codec it cannot produce is still the export session's job.
        XCTAssertFalse(accepts(audioCodec: .opus))
        // Nor can it write a container it does not support.
        XCTAssertFalse(accepts(container: .mkv))
        // AV1 hardware decode runs through this same writer, so the bitrate has to reach it as well.
        XCTAssertTrue(accepts(sourceCodec: .av1))
        // A codec the hardware writer cannot read at all still belongs to the export session.
        XCTAssertFalse(accepts(sourceCodec: .mpeg2))
        // VP9 is in the set for a future hardware route; today `validate` rejects it before this guard is reached.
        XCTAssertTrue(HW_AppleHEVCCodecAlgorithm.explicitBitrateSourceCodecs.contains(.vp9))
    }

    /// The inspector used to report `bitDepth: nil` for every file, which quietly disabled the 10-bit decisions
    /// downstream. This pins the value it now reports, and pins the fallback that covers files where CoreMedia
    /// omits `BitsPerComponent` — the two have to agree.
    func testInspectorReportsTheBitDepthTheFileDeclares() async throws {
        let directory = try makeEvidenceDirectory(named: "bit-depth")
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await writeEvidenceVideo(
            size: CGSize(width: 320, height: 240),
            seconds: 0.6,
            fill: .white,
            to: sourceURL
        )

        func descriptions(at url: URL) async throws -> [CMFormatDescription] {
            let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            return try await track.load(.formatDescriptions)
        }

        // The fixture is H.264, so this also exercises the `avcC` fallback rather than the declared extension.
        let sourceDescriptions = try await descriptions(at: sourceURL)
        let sourceAsset = try await AVFoundationMediaInspector().inspectVideo(at: sourceURL)
        XCTAssertEqual(sourceAsset.videoTrack?.color.bitDepth, 8)
        XCTAssertEqual(
            sourceDescriptions.first.flatMap(TaptionVideoBitDepthProbe.bitDepthFromCodecConfiguration),
            8,
            "The avcC profile byte has to resolve to the same depth as the declared extension."
        )
        XCTAssertFalse(TaptionVideoBitDepthProbe.isHighBitDepth(sourceDescriptions))

        // The sized writer emits HEVC, so the `hvcC` fallback is covered too.
        let outputURL = directory.appendingPathComponent("output.mp4")
        _ = try await HW_AppleHEVCCodecAlgorithm.transcode(
            request: TaptionCodecTranscodeRequest(
                sourceURL: sourceURL,
                outputURL: outputURL,
                route: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc),
                options: TaptionCodecTranscodeOptions(
                    outputPolicy: TaptionVideoOutputPolicy(
                        videoCodec: .hevc,
                        container: .mp4,
                        advancedOptions: TaptionAdvancedOutputOptions(targetBitrate: 1_500_000)
                    ),
                    preserveAudioWhenPossible: false
                )
            ),
            progress: { _ in }
        )
        let outputDescriptions = try await descriptions(at: outputURL)
        let outputAsset = try await AVFoundationMediaInspector().inspectVideo(at: outputURL)
        XCTAssertEqual(outputAsset.videoTrack?.color.bitDepth, 8)
        XCTAssertEqual(
            outputDescriptions.first.flatMap(TaptionVideoBitDepthProbe.bitDepthFromCodecConfiguration),
            8
        )
        XCTAssertFalse(outputAsset.videoTrack?.color.isHDR ?? true)
    }

    /// A source with no audio must still reach the sized writer.
    ///
    /// The plan enum's "no audio" case was called `none`, and `return .none` in a function returning
    /// `SizedWriterAudioPlan?` binds to `Optional.none` — `nil`, meaning "cannot do this, use the export session".
    /// Every silent source therefore lost its bitrate without any error, which is the same defect the sized writer
    /// exists to fix. This runs in the simulator because the bug was in the decision, not in the encoding.
    func testSizedWriterTreatsAMissingAudioTrackAsNoAudioRatherThanGivingUp() async throws {
        let directory = try makeEvidenceDirectory(named: "silent-audio-plan")
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("silent.mp4")
        try await writeEvidenceVideo(
            size: CGSize(width: 320, height: 240),
            seconds: 0.4,
            fill: .white,
            to: sourceURL
        )
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audioTracks.isEmpty)

        func plan(preserveAudio: Bool) async throws -> HW_AppleHEVCCodecAlgorithm.SizedWriterAudioPlan? {
            try await HW_AppleHEVCCodecAlgorithm.sizedWriterAudioPlan(
                for: TaptionCodecTranscodeRequest(
                    sourceURL: sourceURL,
                    outputURL: directory.appendingPathComponent("out.mp4"),
                    route: TaptionCodecRoute(sourceCodec: .h264, outputCodec: .hevc),
                    options: TaptionCodecTranscodeOptions(
                        outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
                        preserveAudioWhenPossible: preserveAudio
                    )
                ),
                asset: asset
            )
        }

        let preserving = try await plan(preserveAudio: true)
        let notPreserving = try await plan(preserveAudio: false)
        // `nil` here would mean the export session takes over and the requested bitrate is discarded.
        XCTAssertNotNil(preserving)
        XCTAssertNotNil(notPreserving)
        guard case .noAudio = try XCTUnwrap(preserving),
              case .noAudio = try XCTUnwrap(notPreserving) else {
            return XCTFail("A silent source has no audio to plan for, in both modes.")
        }
    }

    /// VP9 has no VideoToolbox decoder, so the entry in `explicitBitrateSourceCodecs` cannot be reached: `validate`
    /// refuses the route before the sized writer is ever considered. Recording that here means the entry is either
    /// removed deliberately or starts working deliberately — it cannot rot unnoticed.
    func testVP9NeverReachesTheSizedWriterBecauseTheRouteIsRejected() async throws {
        let route = TaptionCodecRoute(sourceCodec: .vp9, outputCodec: .hevc)
        let request = TaptionCodecTranscodeRequest(
            sourceURL: URL(fileURLWithPath: "/tmp/never-read.webm"),
            outputURL: URL(fileURLWithPath: "/tmp/never-written.mp4"),
            route: route,
            options: TaptionCodecTranscodeOptions(
                outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4)
            )
        )
        // The guard would say yes, which is exactly why the route check has to be the thing that says no.
        XCTAssertTrue(HW_AppleHEVCCodecAlgorithm.requestsSizedWriterEncode(request))

        do {
            _ = try await HW_AppleHEVCCodecAlgorithm.transcode(request: request, progress: { _ in })
            XCTFail("A VP9 route has no hardware decoder, so the encode must not start.")
        } catch let error as TaptionCodecTranscodingRegistryError {
            XCTAssertEqual(error, .routeNotImplemented(route))
        }
    }

    func testSizedWriterEncodeUsesTheBitrateThePlanDerivedFromTheFrame() {
        let source = makeAsset(
            sourceCodec: .h264,
            displaySize: TaptionPixelSize(width: 1920, height: 1080),
            videoBitrate: 8_000_000
        )

        func bitrate(_ preset: TaptionOutputResolutionPreset) -> Int? {
            TaptionOutputSelection(resolutionPreset: preset)
                .outputPolicy(for: source)
                .advancedOptions
                .targetBitrate
        }

        let highDefinition = bitrate(.hd720)
        let fullHighDefinition = bitrate(.fullHD)
        let ultraHighDefinition = bitrate(.uhd4k)

        // The point of the explicit-bitrate path: these numbers have to differ, or the resolution choice would
        // only change the pixel count and the file would still be encoded at the preset's fixed bitrate.
        let hd = highDefinition ?? 0
        let fhd = fullHighDefinition ?? 0
        let uhd = ultraHighDefinition ?? 0
        XCTAssertGreaterThan(fhd, hd)
        XCTAssertGreaterThan(uhd, fhd)
    }

    func testSoftwareFallbackDecodesAtTheSourceShapeSoThePlacementStaysOurs() throws {
        // libvlc decides on its own whether to letterbox or stretch the buffer it is handed, and that choice is not
        // in the API this app links against. Asking for a buffer that already has the source's shape moves the
        // placement decision back to us.
        let asset = makeAsset(
            sourceCodec: .av1,
            displaySize: TaptionPixelSize(width: 2880, height: 2160)
        )

        func configuration(_ mode: TaptionVideoScaleMode) throws -> SW_AV1HEVCTranscodeConfiguration {
            try SW_AV1HEVCTranscodeConfiguration.make(
                asset: asset,
                outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
                options: TaptionCodecTranscodeOptions(
                    outputPolicy: TaptionVideoOutputPolicy(
                        videoCodec: .hevc,
                        container: .mp4,
                        advancedOptions: TaptionAdvancedOutputOptions(
                            resizeTo: TaptionPixelSize(width: 1920, height: 1080),
                            scaleMode: mode
                        )
                    )
                )
            )
        }

        let fit = try configuration(.fit)
        XCTAssertEqual(fit.targetSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(try XCTUnwrap(fit.decodeSize), CGSize(width: 1440, height: 1080))
        XCTAssertTrue(fit.needsFrameComposition)

        // Fill has to cover the frame before it is cropped, so the decode buffer is larger than the frame.
        let fill = try configuration(.fill)
        XCTAssertEqual(try XCTUnwrap(fill.decodeSize), CGSize(width: 1920, height: 1440))

        // Stretch is applied when the picture is placed, so the buffer only has to keep the source's shape.
        let stretch = try configuration(.stretch)
        XCTAssertEqual(try XCTUnwrap(stretch.decodeSize), CGSize(width: 1440, height: 1080))
    }

    func testSoftwareFallbackSkipsCompositionWhenTheShapeAlreadyMatches() throws {
        let asset = makeAsset(
            sourceCodec: .av1,
            displaySize: TaptionPixelSize(width: 3840, height: 2160)
        )

        let configuration = try SW_AV1HEVCTranscodeConfiguration.make(
            asset: asset,
            outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            options: TaptionCodecTranscodeOptions(
                outputPolicy: TaptionVideoOutputPolicy(
                    videoCodec: .hevc,
                    container: .mp4,
                    advancedOptions: TaptionAdvancedOutputOptions(
                        resizeTo: TaptionPixelSize(width: 1920, height: 1080),
                        scaleMode: .fill
                    )
                )
            )
        )

        // 16:9 into 16:9: the decoder output already is the frame, so no per-frame compositing is added.
        XCTAssertNil(configuration.decodeSize)
        XCTAssertFalse(configuration.needsFrameComposition)
    }

}
