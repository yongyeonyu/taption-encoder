import Foundation
import XCTest
@testable import Taption_Encoder

final class RefactoringRegressionTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BOKKI-Refactor-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func state(_ output: URL) -> TaptionPendingSaveState {
        TaptionPendingSaveState(planID: UUID(), temporaryOutputURL: output,
                                saveDestination: .temporaryOnly, requiresRewardedAd: false)
    }

    func testEncoderRejectsSourceAsTemporaryOutputBeforeChangingBytes() async throws {
        let source = try temporaryDirectory().appendingPathComponent("source.mp4")
        let original = Data("original-video-do-not-remove".utf8)
        try original.write(to: source)
        let asset = TaptionVideoAsset(displayName: "source.mp4", location: .init(kind: .file, url: source),
            container: .mp4, duration: 1, videoTrack: .init(codec: .h264,
                naturalSize: .init(width: 64, height: 64), displaySize: .init(width: 64, height: 64)))
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(asset: asset, sourceURL: source,
            temporaryOutputURL: source, outputPolicy: .init(videoCodec: .hevc, container: .mp4),
            savePolicy: .init(destination: .temporaryOnly, saveGate: .none))
        do { _ = try await AVFoundationHEVCEncoderService().encode(plan: plan, progress: { _ in }); XCTFail("Aliased output accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("separate local file")) }
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testOutputSafetyRejectsSymlinkAndHardLinkAliases() throws {
        let root = try temporaryDirectory(), source = root.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: source)
        let symlink = root.appendingPathComponent("symbolic.mp4"), hardlink = root.appendingPathComponent("hard.mp4")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        try FileManager.default.linkItem(at: source, to: hardlink)
        XCTAssertThrowsError(try MediaFileIdentity.validateEncodingOutput(source: source, temporary: symlink))
        XCTAssertThrowsError(try MediaFileIdentity.validateEncodingOutput(source: source, temporary: hardlink))
        XCTAssertNoThrow(try MediaFileIdentity.validateEncodingOutput(source: source, temporary: root.appendingPathComponent("output.mp4")))
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
    }

    func testResetCleanupKeepsNewOutputAndItsManifest() async throws {
        let root = try temporaryDirectory()
        let old = state(root.appendingPathComponent("old.mp4")), new = state(root.appendingPathComponent("new.mp4"))
        try Data("old".utf8).write(to: old.temporaryOutputURL)
        let store = FilePendingSaveStore(fileURL: root.appendingPathComponent("manifest.json"), recoveryDirectoryURL: root)
        try await store.savePendingState(old)
        let captured = [old]
        try Data("new".utf8).write(to: new.temporaryOutputURL)
        try await store.savePendingState(new)
        await PendingSaveCleanup.removeCapturedStates(captured, from: store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.temporaryOutputURL.path))
        XCTAssertEqual(try Data(contentsOf: new.temporaryOutputURL), Data("new".utf8))
        let remaining = try await store.loadPendingStates()
        XCTAssertEqual(remaining.map(\.id), [new.id])
    }

    func testCleanupPreservesVideoWhenManifestRemovalFails() async throws {
        let output = try temporaryDirectory().appendingPathComponent("pending.mp4")
        try Data("preserved".utf8).write(to: output)
        await PendingSaveCleanup.removeCapturedStates([state(output)], from: RejectingPendingSaveStore())
        XCTAssertEqual(try Data(contentsOf: output), Data("preserved".utf8))
    }

    func testPendingRecoveryPreservesManifestOnTransientReadFailure() async throws {
        let root = try temporaryDirectory(), manifest = root.appendingPathComponent("manifest.json")
        let pending = state(root.appendingPathComponent("pending.mp4"))
        let writer = FilePendingSaveStore(fileURL: manifest)
        try await writer.savePendingState(pending)
        let before = try Data(contentsOf: manifest)
        let blocked = FilePendingSaveStore(fileURL: manifest, isRegularFile: { _ in throw CocoaError(.fileReadNoPermission) })
        do { _ = try await blocked.loadPendingStates(); XCTFail("Read failure treated as missing video") } catch {}
        XCTAssertEqual(try Data(contentsOf: manifest), before)
    }

    func testPendingRecoveryRebasesExistingFileAndDropsOnlyMissingEntries() async throws {
        let root = try temporaryDirectory(), output = root.appendingPathComponent("pending.mp4")
        try Data("encoded".utf8).write(to: output)
        let store = FilePendingSaveStore(fileURL: root.appendingPathComponent("manifest.json"), recoveryDirectoryURL: root)
        let recoverable = state(root.appendingPathComponent("obsolete-container/pending.mp4"))
        try await store.savePendingState(recoverable)
        try await store.savePendingState(state(root.appendingPathComponent("missing.mp4")))
        let loaded = try await store.loadPendingStates()
        XCTAssertEqual(loaded.map(\.id), [recoverable.id])
        XCTAssertEqual(loaded.first?.temporaryOutputURL, output)
        let reloaded = try await store.loadPendingStates()
        XCTAssertEqual(reloaded, loaded)
    }

    func testPendingRecoveryDoesNotTreatDirectoryAsVideo() async throws {
        let root = try temporaryDirectory()
        let store = FilePendingSaveStore(fileURL: root.appendingPathComponent("manifest.json"), recoveryDirectoryURL: root)
        try await store.savePendingState(state(root))
        let loaded = try await store.loadPendingStates()
        XCTAssertTrue(loaded.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }

    func testScopeOwnerDeduplicatesAliasesAndBalancesShutdown() {
        let source = URL(fileURLWithPath: "/tmp/folder/video.mp4")
        var starts = 0, stops = 0
        var owner: SecurityScopedAccessStore? = .init(start: { _ in starts += 1; return true }, stop: { _ in stops += 1 })
        XCTAssertTrue(owner!.acquire(source))
        XCTAssertTrue(owner!.acquire(URL(fileURLWithPath: "/tmp/folder/../folder/video.mp4")))
        XCTAssertEqual(starts, 1)
        owner!.releaseAll(); owner!.releaseAll()
        XCTAssertEqual(stops, 1)
        owner!.acquire(source); owner = nil
        XCTAssertEqual(starts, 2); XCTAssertEqual(stops, 2)
    }

    @MainActor
    func testUnavailableAdPollingDoesNotRetainReleasedHomeModel() async throws {
        let service = UnavailableStarEarningService()
        var environment = AppEnvironment.phase0
        environment.starWalletStore = FakeStarWalletStore()
        environment.starEarningService = service
        var model: HomeViewModel? = HomeViewModel(environment: environment)
        await model?.refreshStarsIfNeeded()
        for _ in 0..<50 {
            if await service.numberOfCalls() >= 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let calls = await service.numberOfCalls()
        XCTAssertGreaterThanOrEqual(calls, 2, "Polling must begin before lifetime assertion")
        weak var releasedModel = model
        model = nil
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(releasedModel, "The long-lived ad poll must not retain its model across sleep/await")
    }

    func testFailedScopeIsNeverReleased() {
        var stops = 0
        let owner = SecurityScopedAccessStore(start: { _ in false }, stop: { _ in stops += 1 })
        XCTAssertFalse(owner.acquire(URL(fileURLWithPath: "/tmp/denied")))
        owner.releaseAll()
        XCTAssertEqual(stops, 0)
    }

    func testMetadataCacheEvictsLeastRecentlyUsedAndInvalidatesChanges() {
        let fingerprint = TaptionMediaFingerprint(fileSize: 8)
        func asset(_ number: Int) -> TaptionVideoAsset {
            let url = URL(fileURLWithPath: "/tmp/\(number).mp4")
            return .init(displayName: url.lastPathComponent, location: .init(kind: .file, url: url),
                         container: .mp4, duration: 1, fingerprint: fingerprint)
        }
        let one = asset(1), two = asset(2), three = asset(3)
        var cache = TaptionInspectedMediaCache(capacity: 2)
        let first = one.location.url!, second = two.location.url!, third = three.location.url!
        cache.store(one, for: first); cache.store(two, for: second)
        XCTAssertEqual(cache.asset(for: first, currentFingerprint: fingerprint), one)
        cache.store(three, for: third)
        XCTAssertNil(cache.asset(for: second, currentFingerprint: fingerprint))
        XCTAssertEqual(cache.asset(for: third, currentFingerprint: fingerprint), three)
        XCTAssertNil(cache.asset(for: first, currentFingerprint: .init(fileSize: 9)))
        XCTAssertNil(cache.asset(for: first, currentFingerprint: fingerprint))
    }

    func testBookmarkStoreRenewsStalePrunesInvalidAndDeduplicatesGrants() throws {
        let suite = "BOKKI-Bookmarks-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = URL(fileURLWithPath: "/tmp/videos", isDirectory: true)
        let stale = Data([1]), fresh = Data([2]), invalid = Data([3])
        defaults.set([stale, invalid, stale], forKey: PreviewFolderBookmarkStore.key)
        let store = PreviewFolderBookmarkStore(defaults: defaults, resolve: { data in
            data == invalid ? nil : .init(url: folder, isStale: data == stale)
        }, create: { _ in fresh })
        XCTAssertEqual(store.folders(containing: folder.appendingPathComponent("video.mp4")), [folder])
        XCTAssertEqual(defaults.array(forKey: PreviewFolderBookmarkStore.key) as? [Data], [fresh])
        XCTAssertTrue(store.folders(containing: URL(fileURLWithPath: "/tmp/videos-other/video.mp4")).isEmpty)
        store.remember(folder)
        XCTAssertEqual(defaults.array(forKey: PreviewFolderBookmarkStore.key) as? [Data], [fresh])
    }

    func testStorageBudgetSaturatesAndRejectsNegativeEstimates() {
        XCTAssertEqual(StorageByteBudget.workingBytes(source: .max, output: .max), .max)
        XCTAssertEqual(StorageByteBudget.workingBytes(source: -50, output: -20), 272 * 1024 * 1024)
        XCTAssertEqual(StorageByteBudget.workingBytes(source: 1000 * 1024 * 1024, output: 200 * 1024 * 1024), 1200 * 1024 * 1024)
    }

    func testCapacityProbeUsesExistingOutputVolumeAncestor() throws {
        let root = try temporaryDirectory()
        XCTAssertEqual(FileSystemStorageChecker.existingAncestor(of: root.appendingPathComponent("not-created/yet")), root)
    }

    func testMalformedMediaNumbersDoNotTrapOrCreateInvalidSeek() {
        for seconds in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            XCTAssertEqual(MediaDisplayFormatting.time(seconds), "--:--")
        }
        XCTAssertEqual(MediaDisplayFormatting.time(3661), "1:01:01")
        XCTAssertEqual(MediaDisplayFormatting.time(-5), "00:00")
        XCTAssertEqual(MediaDisplayFormatting.byteCount(-1), "Unknown size")
        XCTAssertEqual(MediaDisplayFormatting.frameRate(.init(numerator: Int.max)), "Unknown fps")
        XCTAssertNil(QueuePreviewPlaybackMath.clampedSeekSeconds(5, duration: .infinity))
        XCTAssertNil(QueuePreviewPlaybackMath.clampedSeekSeconds(.nan, duration: 10))
        XCTAssertEqual(QueuePreviewPlaybackMath.clampedSeekSeconds(80, duration: 30), 30)
        XCTAssertEqual(QueuePreviewPlaybackMath.clampedSeekSeconds(-5, duration: 30), 0)
        XCTAssertEqual(QueuePreviewPlaybackMath.verticalAdjustmentDelta(translation: .nan, containerHeight: 100), 0)
        XCTAssertEqual(QueuePreviewPlaybackMath.verticalAdjustmentDelta(translation: 10000, containerHeight: 100), -1)
        XCTAssertEqual(QueuePreviewPlaybackMath.horizontalDragPosition(startPosition: 0.5, translation: 10, containerWidth: .infinity), 0.5)
    }

    func testDuplicateSelectionBuildsOneQueueEntryWithoutCrashing() {
        let url = URL(fileURLWithPath: "/tmp/folder/video.mp4")
        let alias = URL(fileURLWithPath: "/tmp/folder/../folder/video.mp4")
        let batch = FolderEncodingBatch(folderName: "Selection", sourceKind: .files, fileURLs: [url, alias, url])
        XCTAssertEqual(batch.fileURLs, [url]); XCTAssertEqual(batch.itemStates.count, 1)
        XCTAssertEqual(batch.cardSnapshots().count, 1)
    }
}

private actor RejectingPendingSaveStore: TaptionPendingSavePersisting {
    func savePendingState(_ state: TaptionPendingSaveState) async throws {}
    func loadPendingStates() async throws -> [TaptionPendingSaveState] { [] }
    func removePendingState(id: UUID) async throws { throw CocoaError(.fileWriteNoPermission) }
}

private actor UnavailableStarEarningService: StarEarningServing {
    private var calls = 0
    func currentAdState() async -> AdLoadState { calls += 1; return .unavailable }
    func numberOfCalls() -> Int { calls }
    func watchAdAndEarnStar() async throws -> StarEarningResult { throw CocoaError(.fileReadUnknown) }
}
