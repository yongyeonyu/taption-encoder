//
//  CodecRoutePlannerTests+FolderAndQueue.swift
//  Tests 11675-13560 of the original CodecRoutePlannerTests.swift, moved here
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
    func testPreviewAudioRoundTripRejectsFirstFullPlayersDelayedShutdown() async throws {
        var deactivations = 0
        let lifetime = QueuePreviewAudioSessionLifetime(activate: {}, deactivate: { deactivations += 1 })
        try await lifetime.activate(id: "same-file.full.1")
        try await lifetime.activate(id: "same-file.mini.1")
        try await lifetime.activate(id: "same-file.full.2")
        lifetime.deactivate(id: "same-file.full.1")
        lifetime.deactivate(id: "same-file.mini.1")
        await lifetime.waitForPendingOperations()
        XCTAssertEqual(deactivations, 0)
        lifetime.deactivate(id: "same-file.full.2")
        await lifetime.waitForPendingOperations()
        XCTAssertEqual(deactivations, 1)
    }

    @MainActor
    func testPreviewAudioLifetimeSkipsSupersededRequests() async throws {
        let gate = PreviewAudioOperationGate()
        var activations = 0
        var deactivations = 0
        let lifetime = QueuePreviewAudioSessionLifetime(
            activate: { activations += 1; if activations == 1 { await gate.wait() } },
            deactivate: { deactivations += 1 }
        )
        let first = Task { try await lifetime.activate(id: "A") }
        try await waitForCondition(timeout: 5) { gate.isWaiting }
        let second = Task { try await lifetime.activate(id: "B") }
        try await waitForCondition(timeout: 5) { lifetime.ownerID == "B" }
        lifetime.deactivate(id: "B")
        let current = Task { try await lifetime.activate(id: "C") }
        try await waitForCondition(timeout: 5) { lifetime.ownerID == "C" }
        gate.release()
        do { try await first.value; XCTFail("Expected first request to be superseded") } catch is CancellationError {}
        do { try await second.value; XCTFail("Expected second request to be superseded") } catch is CancellationError {}
        try await current.value
        XCTAssertEqual(activations, 2)
        XCTAssertEqual(deactivations, 0)
        lifetime.deactivate(id: "C")
        await lifetime.waitForPendingOperations()
        XCTAssertEqual(deactivations, 1)
    }

    func testPreviewAudioUsesOffMainWorkerAndCompatibleOptions() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("TaptionEncoder/Features/Preview/QueuePreviewViews.swift"), encoding: .utf8)
        let worker = try XCTUnwrap(text.range(of: "private enum QueuePreviewAudioSessionWorker"))
        let end = try XCTUnwrap(text.range(of: "enum QueuePreviewDemuxMode"))
        let body = String(text[worker.lowerBound..<end.lowerBound])
        XCTAssertTrue(body.contains("DispatchQueue(label:"))
        XCTAssertTrue(body.contains("try session.setCategory(.playback, mode: .moviePlayback, options: [])"))
        XCTAssertFalse(body.contains(".allowAirPlay"))
        XCTAssertFalse(body.contains(".allowBluetoothA2DP"))
        XCTAssertTrue(body.contains("if #available(iOS 27.0, *)"))
        XCTAssertTrue(body.contains("session.activate(options:"))
        XCTAssertTrue(body.contains("session.deactivate(options:"))
        XCTAssertTrue(body.contains("try session.setActive(true)"))
        XCTAssertTrue(text.contains("@State private var audioSessionInstanceID = UUID()"))
        XCTAssertTrue(text.contains("let sessionID = previewAudioSessionID"))
    }

    @MainActor
    func testCloudSourceReplacementCancelsDownloadAndAllowsRetry() async throws {
        let directory = temporaryDirectoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("cloud.mp4")
        let second = directory.appendingPathComponent("other.mp4")
        try Data("source".utf8).write(to: first)
        try Data("source".utf8).write(to: second)
        let downloader = CancelableSourceDownloader(heldURL: first)
        let inspector = CountingMediaInspector(asset: makeAsset(sourceCodec: .h264))
        let model = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(pendingSaveStore: FakePendingSaveStore(), mediaInspector: inspector),
            sourceDownloader: downloader
        )
        model.openExternalPlayerFile(url: first)
        try await waitForAsyncCondition { await downloader.started }
        XCTAssertEqual(inspector.inspectionCount, 0)
        // Source replacement is intentionally blocked while inspection is busy.
        // Cancel the active download before selecting another file or retrying.
        XCTAssertTrue(model.state.canCancel)
        model.cancel()
        try await waitForCondition(timeout: 10) { model.state == .cancelled }
        try await waitForAsyncCondition { await downloader.wasCancelled }
        model.openExternalPlayerFile(url: second)
        try await waitForReadyToStartState(in: model, timeout: 10)
        try await waitForAsyncCondition { await downloader.wasCancelled }
        XCTAssertEqual(model.activePreview?.sourceURL, second)
        XCTAssertEqual(inspector.inspectionCount, 1)
        model.openExternalPlayerFile(url: first)
        try await waitForReadyToStartState(in: model, timeout: 10)
        XCTAssertEqual(model.activePreview?.sourceURL, first)
        XCTAssertEqual(inspector.inspectionCount, 2)
    }

    @MainActor
    internal final class PreviewAudioOperationGate {
        private var continuation: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { continuation != nil }
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() { continuation?.resume(); continuation = nil }
    }

    internal actor CancelableSourceDownloader: VideoSourceDownloading {
        let heldURL: URL
        var started = false
        var wasCancelled = false
        private var holdsFirstRequest = true
        init(heldURL: URL) { self.heldURL = heldURL }
        func ensureLocalVideo(at url: URL) async throws {
            guard url == heldURL, holdsFirstRequest else { return }
            started = true
            do { try await Task.sleep(for: .seconds(30)) }
            catch {
                wasCancelled = error is CancellationError
                holdsFirstRequest = false
                throw error
            }
        }
    }

    @MainActor
    internal struct StartRaceFixture {
        var directoryURL: URL
        var firstURL: URL
        var secondURL: URL
        var viewModel: HomeViewModel
        var wallet: SuspendedStartStarWalletStore
        var encoder: RecordingStartEncoder
    }

    @MainActor
    internal func makeStartRaceFixture(balance: Int = 3) async throws -> StartRaceFixture {
        let directoryURL = temporaryDirectoryURL()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let firstURL = directoryURL.appendingPathComponent("first.mp4")
        let secondURL = directoryURL.appendingPathComponent("second.mp4")
        try Data("source".utf8).write(to: firstURL)
        try Data("source".utf8).write(to: secondURL)
        let wallet = SuspendedStartStarWalletStore(snapshot: makeStarWalletSnapshot(balance: balance))
        let encoder = RecordingStartEncoder()
        let model = HomeViewModel(environment: makeHomeViewModelTestEnvironment(
            pendingSaveStore: FakePendingSaveStore(),
            mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
            encoderService: encoder, starWalletStore: wallet
        ))
        await model.refreshStarsIfNeeded()
        model.startFilesFlow(url: firstURL)
        try await waitForReadyToStartState(in: model, timeout: 10)
        return StartRaceFixture(directoryURL: directoryURL, firstURL: firstURL, secondURL: secondURL,
                                viewModel: model, wallet: wallet, encoder: encoder)
    }

    @MainActor
    internal func waitForAsyncCondition(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for controlled asynchronous state")
        throw NSError(domain: "CodecRoutePlannerTests.Wait", code: 1)
    }

    internal actor SuspendedStartStarWalletStore: StarWalletManaging {
        let store: FakeStarWalletStore
        var snapshotsHeld = false
        var debitsHeld = false
        var snapshotWaiters: [CheckedContinuation<Void, Never>] = []
        var debitWaiters: [CheckedContinuation<Void, Never>] = []
        var debits = 0
        var refunds = 0
        var wasRefundCancelled = false
        init(snapshot: StarWalletSnapshot) { store = FakeStarWalletStore(snapshot: snapshot) }
        func currentSnapshot() async -> StarWalletSnapshot {
            if snapshotsHeld { await withCheckedContinuation { snapshotWaiters.append($0) } }
            return await store.currentSnapshot()
        }
        func consumeStar(source: String) async throws -> StarWalletSnapshot {
            debits += 1
            let snapshot = try await store.consumeStar(source: source)
            if debitsHeld { await withCheckedContinuation { debitWaiters.append($0) } }
            return snapshot
        }
        func earnStar(source: String) async throws -> StarWalletSnapshot { try await store.earnStar(source: source) }
        func refundStar(source: String) async throws -> StarWalletSnapshot {
            wasRefundCancelled = Task.isCancelled
            let snapshot = try await store.refundStar(source: source)
            refunds += 1
            return snapshot
        }
        func holdSnapshots() { snapshotsHeld = true }
        func holdDebits() { debitsHeld = true }
        func releaseSnapshots() {
            snapshotsHeld = false
            let waiters = snapshotWaiters
            snapshotWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        func releaseOldestDebit() {
            guard !debitWaiters.isEmpty else { return }
            debitWaiters.removeFirst().resume()
        }
        func pendingSnapshotCount() -> Int { snapshotWaiters.count }
        func pendingDebitCount() -> Int { debitWaiters.count }
        func debitCount() -> Int { debits }
        func refundCount() -> Int { refunds }
        func balance() async -> Int { await store.currentSnapshot().balance }
        func refundWasCancelled() -> Bool { wasRefundCancelled }
    }

    internal actor RecordingStartEncoder: EncoderServicing {
        var sources: [URL] = []
        func encode(plan: TaptionEncodingPlan, progress: @escaping (TaptionEncodingProgress) -> Void) async throws -> TaptionEncodingResult {
            guard let sourceURL = plan.sourceURL else { throw TaptionVideoCoreError.missingSourceURL }
            sources.append(sourceURL)
            return try await ImmediateEncoderService(outputData: Data("encoded".utf8)).encode(plan: plan, progress: progress)
        }
        func cancelEncoding(planID: UUID) async {}
        func callCount() -> Int { sources.count }
        func sourceURLs() -> [URL] { sources }
    }

    @MainActor
    internal final class PreviewOutputGate {
        var continuation: CheckedContinuation<Bool, Never>?
        var isWaiting: Bool { continuation != nil }
        func wait() async -> Bool { await withCheckedContinuation { continuation = $0 } }
        func release() { continuation?.resume(returning: false); continuation = nil }
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
        XCTAssertEqual(viewModel.convertActionTitle, "Convert 2 videos · 2 Stars")
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
    func testFolderPickerSelectionSkipsNonVideoFiles() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let sourceURL = directoryURL.appendingPathComponent("picked.mp4")
        let textURL = directoryURL.appendingPathComponent("notes.txt")
        try Data("source".utf8).write(to: sourceURL)
        try Data("notes".utf8).write(to: textURL)

        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )

        viewModel.handleFolderPickerSelection(urls: [textURL, sourceURL])
        try await waitForReadyToStartState(in: viewModel)

        guard case .readyToStart(let review) = viewModel.state else {
            return XCTFail("Expected ready state for supported video")
        }
        XCTAssertEqual(review.source.url, sourceURL)
        XCTAssertEqual(viewModel.fileCardSnapshots.map(\.fileName), ["picked.mp4"])
    }

    @MainActor
    func testFolderPickerSelectionRoutesFolderToFolderFlow() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let folderURL = directoryURL.appendingPathComponent("PickedFolder", isDirectory: true)
        let sourceURL = folderURL.appendingPathComponent("inside.mp4")
        let textURL = folderURL.appendingPathComponent("notes.txt")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: sourceURL)
        try Data("notes".utf8).write(to: textURL)

        let scanResult = try FolderContentsScanner.scan(folderURL: folderURL)
        XCTAssertEqual(scanResult.videoURLs, [sourceURL])
        XCTAssertEqual(scanResult.skippedNonVideoFileCount, 1)

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
    func testFolderBatchSavesDirectlyIntoSelectedOutputFolderWithUniqueNames() async throws {
        let parentURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: parentURL)
        }
        let sourceFolderURL = parentURL.appendingPathComponent("VideoFolder", isDirectory: true)
        let firstURL = sourceFolderURL.appendingPathComponent("a.mp4")
        let secondURL = sourceFolderURL.appendingPathComponent("b.mp4")
        let outputFolderURL = parentURL.appendingPathComponent("ChosenOutput", isDirectory: true)
        let firstOutputURL = outputFolderURL.appendingPathComponent("a_taption.mp4")
        let uniqueFirstOutputURL = outputFolderURL.appendingPathComponent("a_taption (2).mp4")
        let secondOutputURL = outputFolderURL.appendingPathComponent("b_taption.mp4")
        try FileManager.default.createDirectory(at: sourceFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
        try Data("source a".utf8).write(to: firstURL)
        try Data("source b".utf8).write(to: secondURL)
        try Data("existing".utf8).write(to: firstOutputURL)
        let defaultsSuiteName = "FolderOutputSelectionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let walletStore = FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 2))
        let backgroundCoordinator = RecordingBackgroundEncodingCoordinator(
            observedFinalOutputURL: secondOutputURL
        )
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                starWalletStore: walletStore,
                backgroundCoordinator: backgroundCoordinator
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFolderFlow(url: sourceFolderURL)
        viewModel.importFolderPreviewBatch()
        try await waitForReadyToStartState(in: viewModel)
        XCTAssertFalse(viewModel.prepareFolderOutputDirectoryForStart(defaults: defaults))
        XCTAssertTrue(viewModel.selectFolderOutputDirectory(outputFolderURL, defaults: defaults))
        viewModel.startPreparedEncoding()

        try await waitForCondition(timeout: 3) {
            FileManager.default.fileExists(atPath: uniqueFirstOutputURL.path)
                && FileManager.default.fileExists(atPath: secondOutputURL.path)
                && viewModel.state.title == "Save Complete"
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sourceFolderURL.appendingPathComponent("a_taption.mp4").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sourceFolderURL.appendingPathComponent("b_taption.mp4").path
        ))
        XCTAssertEqual(try String(contentsOf: firstOutputURL, encoding: .utf8), "existing")
        XCTAssertEqual(try String(contentsOf: uniqueFirstOutputURL, encoding: .utf8), "encoded")
        XCTAssertEqual(try String(contentsOf: secondOutputURL, encoding: .utf8), "encoded")
        let finalOutputPresenceAtBackgroundEnd = await backgroundCoordinator
            .recordedFinalOutputPresenceAtEnd()
        XCTAssertEqual(finalOutputPresenceAtBackgroundEnd, [false, true])
    }

    @MainActor
    func testFolderOutputBookmarkIsReusedForTheNextFolderBatch() async throws {
        let parentURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: parentURL)
        }
        let firstSourceFolderURL = parentURL.appendingPathComponent("First", isDirectory: true)
        let secondSourceFolderURL = parentURL.appendingPathComponent("Second", isDirectory: true)
        let outputFolderURL = parentURL.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: firstSourceFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSourceFolderURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: firstSourceFolderURL.appendingPathComponent("first.mp4"))
        try Data("source".utf8).write(to: secondSourceFolderURL.appendingPathComponent("second.mp4"))

        let defaultsSuiteName = "FolderOutputBookmarkTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let firstViewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264))
            )
        )
        firstViewModel.startFolderFlow(url: firstSourceFolderURL)
        firstViewModel.importFolderPreviewBatch()
        try await waitForReadyToStartState(in: firstViewModel)
        XCTAssertTrue(firstViewModel.selectFolderOutputDirectory(outputFolderURL, defaults: defaults))

        let secondViewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                mediaInspector: StubMediaInspector(asset: makeAsset(sourceCodec: .h264)),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                starWalletStore: FakeStarWalletStore(snapshot: makeStarWalletSnapshot(balance: 1))
            )
        )
        await secondViewModel.refreshStarsIfNeeded()
        secondViewModel.startFolderFlow(url: secondSourceFolderURL)
        secondViewModel.importFolderPreviewBatch()
        try await waitForReadyToStartState(in: secondViewModel)
        XCTAssertTrue(secondViewModel.prepareFolderOutputDirectoryForStart(defaults: defaults))
        secondViewModel.startPreparedEncoding()
        try await waitForCondition(timeout: 3) {
            FileManager.default.fileExists(
                atPath: outputFolderURL.appendingPathComponent("second_taption.mp4").path
            ) && secondViewModel.state.title == "Save Complete"
        }
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
            $0.folderName == "BOKKI Encoder Files"
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
        XCTAssertEqual(
            viewModel.folderPreviewFileSnapshots.compactMap { snapshot in
                URL(string: snapshot.id)?.resolvingSymlinksInPath().standardizedFileURL.path
            },
            [childVideoURL.resolvingSymlinksInPath().standardizedFileURL.path]
        )
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
        XCTAssertEqual(
            viewModel.folderPreviewFileSnapshots.compactMap { snapshot in
                URL(string: snapshot.id)?.resolvingSymlinksInPath().standardizedFileURL.path
            },
            [keptChildVideoURL.resolvingSymlinksInPath().standardizedFileURL.path]
        )
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

        XCTAssertEqual(viewModel.importBrowserContext?.rootFolderName, "BOKKI Encoder Files")
        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "BOKKI Encoder Files/\(childName)")
        XCTAssertEqual(viewModel.importBrowserContext?.canGoUp, true)
        XCTAssertEqual(viewModel.importBrowserFiles.map(\.fileName), ["child.mp4"])

        viewModel.navigateImportBrowserUp()

        XCTAssertEqual(viewModel.importBrowserContext?.pathText, "BOKKI Encoder Files")
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
        XCTAssertTrue(loadedFilesPanelText.contains("line.3.horizontal"))
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
        XCTAssertTrue(loadedFilesPanelText.contains(".onTapGesture(count: usesListLayout ? 1 : 2)"))
        XCTAssertTrue(loadedFilesPanelText.contains("usesListLayout ? \"Play preview\" : \"Double tap to play preview\""))
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
        XCTAssertTrue(homeLayoutMetricsText.contains("filePanelHeight = max(usesScrollableLayout ? 180 : 80, remainingHeight)"))
        XCTAssertFalse(homeLayoutMetricsText.contains("filePanelHeight = max(remainingHeight, minimumFilePanelHeight)"))
    }

    func testHomeLayoutMetricsShrinksQueuePanelUnderVerticalPressure() {
        let portraitMetrics = HomeLayoutMetrics(size: CGSize(width: 393, height: 852), reservesFailureLogArea: false, userInterfaceIdiom: .phone)
        let compactLandscapeMetrics = HomeLayoutMetrics(size: CGSize(width: 852, height: 393), reservesFailureLogArea: false, userInterfaceIdiom: .phone)

        XCTAssertEqual(compactLandscapeMetrics.canvasHeight, 393, accuracy: 0.1)
        XCTAssertLessThanOrEqual(compactLandscapeMetrics.contentScale, portraitMetrics.contentScale)
        XCTAssertLessThan(compactLandscapeMetrics.filePanelHeight, portraitMetrics.filePanelHeight)
        XCTAssertGreaterThanOrEqual(compactLandscapeMetrics.filePanelHeight, 180)
        XCTAssertTrue(compactLandscapeMetrics.usesScrollableLayout)
        XCTAssertFalse(portraitMetrics.usesScrollableLayout)
    }

    func testHomeLayoutMetricsUsesTwoColumnsOnlyForIPadLandscape() {
        let padLandscape = HomeLayoutMetrics(
            size: CGSize(width: 1194, height: 834),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .pad
        )
        let padPortrait = HomeLayoutMetrics(
            size: CGSize(width: 834, height: 1194),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .pad
        )
        let padLandscapeWithFailureLog = HomeLayoutMetrics(
            size: CGSize(width: 1194, height: 834),
            reservesFailureLogArea: true,
            userInterfaceIdiom: .pad
        )
        let phoneLandscape = HomeLayoutMetrics(
            size: CGSize(width: 852, height: 393),
            reservesFailureLogArea: false,
            userInterfaceIdiom: .phone
        )

        XCTAssertTrue(padLandscape.usesPadLandscapeColumns)
        XCTAssertGreaterThan(padLandscape.columnWidth, 400)
        XCTAssertGreaterThanOrEqual(padLandscape.filePanelHeight, 120)
        XCTAssertEqual(
            padLandscape.filePanelHeight,
            padLandscapeWithFailureLog.filePanelHeight,
            accuracy: 0.1
        )
        XCTAssertFalse(padPortrait.usesPadLandscapeColumns)
        XCTAssertFalse(phoneLandscape.usesPadLandscapeColumns)
    }

}
