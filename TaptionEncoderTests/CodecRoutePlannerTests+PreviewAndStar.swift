//
//  CodecRoutePlannerTests+PreviewAndStar.swift
//  Tests 9732-11674 of the original CodecRoutePlannerTests.swift, moved here
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

        // Every standard preset stays selectable: an odd-sized video has to be able to become 1080p or 4K.
        XCTAssertTrue(viewModel.resolutionPresetIsAvailable(TaptionOutputResolutionPreset.fullHD, for: portraitAsset))
        XCTAssertTrue(viewModel.resolutionPresetIsAvailable(TaptionOutputResolutionPreset.hd720, for: portraitAsset))
        XCTAssertTrue(viewModel.resolutionPresetIsAvailable(TaptionOutputResolutionPreset.qhd1440, for: portraitAsset))

        // The orientation still decides whether a preset is the same size, smaller, or an enlargement.
        XCTAssertFalse(viewModel.resolutionPresetUpscales(TaptionOutputResolutionPreset.fullHD, for: portraitAsset))
        XCTAssertFalse(viewModel.resolutionPresetUpscales(TaptionOutputResolutionPreset.hd720, for: portraitAsset))
        XCTAssertTrue(viewModel.resolutionPresetUpscales(TaptionOutputResolutionPreset.qhd1440, for: portraitAsset))
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
        XCTAssertEqual(StarWalletStore.initialInstallBonusStarCount, 3)
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
        XCTAssertEqual(viewModel.convertActionTitle, "Convert 1 video · 1 Star")
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
        let finalOutputURL = directoryURL.appendingPathComponent("source_taption.mp4")
        let backgroundCoordinator = RecordingBackgroundEncodingCoordinator(
            observedFinalOutputURL: finalOutputURL
        )
        let viewModel = HomeViewModel(
            environment: makeHomeViewModelTestEnvironment(
                pendingSaveStore: FakePendingSaveStore(),
                encoderService: ImmediateEncoderService(outputData: Data("encoded".utf8)),
                rewardedAdProvider: rewardedAdProvider,
                starWalletStore: walletStore,
                backgroundCoordinator: backgroundCoordinator
            )
        )

        await viewModel.refreshStarsIfNeeded()
        viewModel.startFilesFlow(url: sourceURL)
        try await waitForReadyToStartState(in: viewModel)
        viewModel.startPreparedEncoding()
        try await waitForCompletedSave(in: viewModel)

        XCTAssertEqual(viewModel.starWalletSnapshot.balance, 0)
        let showCallCount = await rewardedAdProvider.recordedShowCallCount()
        let finalOutputPresenceAtBackgroundEnd = await backgroundCoordinator
            .recordedFinalOutputPresenceAtEnd()
        XCTAssertEqual(showCallCount, 0)
        XCTAssertEqual(viewModel.state.title, "Save Complete")
        XCTAssertEqual(finalOutputPresenceAtBackgroundEnd, [false])
    }

    @MainActor
    func testEncodingStartIsReservedSynchronouslyAndDebitsOnce() async throws {
        for balance in [1, 3] {
            let fixture = try await makeStartRaceFixture(balance: balance)
            defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
            await fixture.wallet.holdSnapshots()
            fixture.viewModel.startPreparedEncoding()
            XCTAssertTrue(fixture.viewModel.isStartingEncoding)
            XCTAssertFalse(fixture.viewModel.canStartEncodingNow)
            fixture.viewModel.startPreparedEncoding()
            try await waitForAsyncCondition { await fixture.wallet.pendingSnapshotCount() == 1 }
            await fixture.wallet.releaseSnapshots()
            try await waitForCompletedSave(in: fixture.viewModel, timeout: 10)
            let calls = await fixture.wallet.debitCount()
            let encoderCalls = await fixture.encoder.callCount()
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(encoderCalls, 1)
            XCTAssertEqual(fixture.viewModel.starWalletSnapshot.balance, balance - 1)
            XCTAssertFalse(fixture.viewModel.isStartingEncoding)
        }
    }

    @MainActor
    func testResetWhileStartSnapshotIsPendingPreventsDebitAndEncoding() async throws {
        let fixture = try await makeStartRaceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        await fixture.wallet.holdSnapshots()
        fixture.viewModel.startPreparedEncoding()
        try await waitForAsyncCondition { await fixture.wallet.pendingSnapshotCount() == 1 }
        fixture.viewModel.reset()
        XCTAssertEqual(fixture.viewModel.state, .idle)
        await fixture.wallet.releaseSnapshots()
        try await Task.sleep(for: .milliseconds(80))
        let calls = await fixture.wallet.debitCount()
        let encoderCalls = await fixture.encoder.callCount()
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(encoderCalls, 0)
        XCTAssertEqual(fixture.viewModel.state, .idle)
        XCTAssertFalse(fixture.viewModel.isStartingEncoding)
    }

    @MainActor
    func testResetAfterDebitCommitRefundsAbandonedStartWithoutEncoding() async throws {
        let fixture = try await makeStartRaceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        await fixture.wallet.holdDebits()
        fixture.viewModel.startPreparedEncoding()
        try await waitForAsyncCondition { await fixture.wallet.pendingDebitCount() == 1 }
        fixture.viewModel.reset()
        await fixture.wallet.releaseOldestDebit()
        try await waitForAsyncCondition { await fixture.wallet.refundCount() == 1 }
        let encoderCalls = await fixture.encoder.callCount()
        let balance = await fixture.wallet.balance()
        let cancelledRefund = await fixture.wallet.refundWasCancelled()
        XCTAssertEqual(encoderCalls, 0)
        XCTAssertEqual(balance, 3)
        XCTAssertFalse(cancelledRefund)
        XCTAssertEqual(fixture.viewModel.state, .idle)
    }

    @MainActor
    func testSourceReplacementDuringDebitDoesNotClearNewerEncodingStart() async throws {
        let fixture = try await makeStartRaceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        await fixture.wallet.holdDebits()
        fixture.viewModel.startPreparedEncoding()
        try await waitForAsyncCondition { await fixture.wallet.pendingDebitCount() == 1 }
        fixture.viewModel.startFilesFlow(url: fixture.secondURL)
        try await waitForReadyToStartState(in: fixture.viewModel, timeout: 10)
        fixture.viewModel.startPreparedEncoding()
        try await waitForAsyncCondition { await fixture.wallet.pendingDebitCount() == 2 }
        await fixture.wallet.releaseOldestDebit()
        try await waitForAsyncCondition { await fixture.wallet.refundCount() == 1 }
        XCTAssertTrue(fixture.viewModel.isStartingEncoding)
        await fixture.wallet.releaseOldestDebit()
        try await waitForCompletedSave(in: fixture.viewModel, timeout: 10)
        let encoderCalls = await fixture.encoder.callCount()
        let sources = await fixture.encoder.sourceURLs()
        let balance = await fixture.wallet.balance()
        XCTAssertEqual(encoderCalls, 1)
        XCTAssertEqual(sources, [fixture.secondURL])
        XCTAssertEqual(balance, 2)
        XCTAssertEqual(fixture.viewModel.starWalletSnapshot.balance, 2)
    }

    @MainActor
    func testExternalPreviewRepeatedStartPreparesAndDebitsOnce() async throws {
        let fixture = try await makeStartRaceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        fixture.viewModel.openExternalPlayerFile(url: fixture.firstURL)
        try await waitForReadyToStartState(in: fixture.viewModel, timeout: 10)
        XCTAssertEqual(fixture.viewModel.state.preparedEncodingReview?.requiresEncodingPreparation, true)
        fixture.viewModel.startPreparedEncoding()
        fixture.viewModel.startPreparedEncoding()
        try await waitForCompletedSave(in: fixture.viewModel, timeout: 10)
        let calls = await fixture.wallet.debitCount()
        let encoderCalls = await fixture.encoder.callCount()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(encoderCalls, 1)
    }

    @MainActor
    func testMiniPlayerClosesForFilesPhotosResetAndEncodingStart() async throws {
        let fixture = try await makeStartRaceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let model = fixture.viewModel
        model.openPreviewForFileCard(id: fixture.firstURL.lastPathComponent)
        model.minimizePreview(try XCTUnwrap(model.activePreview))
        XCTAssertNil(model.activePreview)
        XCTAssertEqual(model.miniPlayerPreview?.sourceURL, fixture.firstURL)
        model.startFilesFlow(url: fixture.secondURL)
        XCTAssertNil(model.miniPlayerPreview)
        try await waitForReadyToStartState(in: model, timeout: 10)
        model.openPreviewForFileCard(id: fixture.secondURL.lastPathComponent)
        model.minimizePreview(try XCTUnwrap(model.activePreview))
        model.startPhotosFlow(url: fixture.firstURL, displayName: "photo.mp4")
        XCTAssertNil(model.miniPlayerPreview)
        try await waitForReadyToStartState(in: model, timeout: 10)
        model.openPreviewForFileCard(id: "photo.mp4")
        model.minimizePreview(try XCTUnwrap(model.activePreview))
        model.reset()
        XCTAssertNil(model.miniPlayerPreview)
        model.startFilesFlow(url: fixture.firstURL)
        try await waitForReadyToStartState(in: model, timeout: 10)
        model.openPreviewForFileCard(id: fixture.firstURL.lastPathComponent)
        model.minimizePreview(try XCTUnwrap(model.activePreview))
        model.startPreparedEncoding()
        XCTAssertNil(model.miniPlayerPreview)
        try await waitForCompletedSave(in: model, timeout: 10)
    }

    @MainActor
    func testOpeningFullPreviewClearsMiniPlaybackSession() async throws {
        let fixture = try await makeStartRaceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        fixture.viewModel.openPreviewForFileCard(id: fixture.firstURL.lastPathComponent)
        let preview = try XCTUnwrap(fixture.viewModel.activePreview)
        fixture.viewModel.minimizePreview(preview)
        fixture.viewModel.restorePreview(preview)
        XCTAssertNil(fixture.viewModel.miniPlayerPreview)
        XCTAssertEqual(fixture.viewModel.activePreview?.id, preview.id)
        fixture.viewModel.dismissPreview()
    }

    @MainActor
    func testPreviewFallbackCancellationNeverPlaysAnotherAttempt() async throws {
        let lifetime = QueuePreviewPlaybackLifetime()
        let operationID = lifetime.begin()
        var playCount = 0
        var resultCount = 0
        let task = Task { @MainActor in
            try await QueuePreviewPlaybackAttempts.run(
                demuxModes: [.automatic, .avformat],
                validate: { try lifetime.check(operationID) },
                stop: {}, play: { _, _ in playCount += 1 },
                waitForOutput: { try await Task.sleep(for: .seconds(10)); return false },
                didFinishAttempt: { _, _, _ in resultCount += 1 }
            )
        }
        try await waitForCondition(timeout: 2) { playCount == 1 }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled fallback must propagate CancellationError")
        } catch is CancellationError {}
        XCTAssertEqual(playCount, 1)
        XCTAssertEqual(resultCount, 0)
    }

    @MainActor
    func testPreviewFallbackGenerationReplacementStopsOldAttempt() async throws {
        let lifetime = QueuePreviewPlaybackLifetime()
        let operationID = lifetime.begin()
        let gate = PreviewOutputGate()
        var playCount = 0
        let task = Task { @MainActor in
            try await QueuePreviewPlaybackAttempts.run(
                demuxModes: [.automatic, .avformat],
                validate: { try lifetime.check(operationID) },
                stop: {}, play: { _, _ in playCount += 1 },
                waitForOutput: { await gate.wait() }, didFinishAttempt: { _, _, _ in }
            )
        }
        try await waitForCondition(timeout: 2) { gate.isWaiting }
        let newOperationID = lifetime.begin()
        gate.release()
        do {
            _ = try await task.value
            XCTFail("Superseded playback must not retry")
        } catch is CancellationError {}
        XCTAssertEqual(playCount, 1)
        XCTAssertTrue(lifetime.isCurrent(newOperationID))
        lifetime.invalidate()
        XCTAssertThrowsError(try lifetime.check(newOperationID))
    }

    @MainActor
    func testPreviewFallbackStillTriesSecondDemuxWhenNotCancelled() async throws {
        let lifetime = QueuePreviewPlaybackLifetime()
        let operationID = lifetime.begin()
        var modes: [QueuePreviewDemuxMode] = []
        let ready = try await QueuePreviewPlaybackAttempts.run(
            demuxModes: [.automatic, .avformat], validate: { try lifetime.check(operationID) },
            stop: {}, play: { _, mode in modes.append(mode) },
            waitForOutput: { modes.count == 2 }, didFinishAttempt: { _, _, _ in }
        )
        XCTAssertTrue(ready)
        XCTAssertEqual(modes, [.automatic, .avformat])
    }

    func testNativePreviewWrappersDoNotConstructVLCPlayers() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("TaptionEncoder/Features/Preview/QueuePreviewViews.swift"), encoding: .utf8)
        for (wrapper, implementation) in [("struct QueueVideoPreviewView: View", "private struct VLCQueueVideoPreviewView: View"),
                                          ("struct QueueMiniPlayerView: View", "private struct VLCQueueMiniPlayerView: View")] {
            let begin = try XCTUnwrap(text.range(of: wrapper))
            let end = try XCTUnwrap(text.range(of: implementation))
            let wrapperText = String(text[begin.lowerBound..<end.lowerBound])
            XCTAssertTrue(wrapperText.contains("NativeQueueVideoPreviewView("))
            XCTAssertFalse(wrapperText.contains("makePreviewPlayer()"))
        }
    }

    @MainActor
    func testPreviewHandoffPreservesPositionAndPauseAcrossRoundTrip() async throws {
        let fixture = try await makeStartRaceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let model = fixture.viewModel
        model.openPreviewForFileCard(id: fixture.firstURL.lastPathComponent)
        let full = try XCTUnwrap(model.activePreview)
        let paused = QueuePreviewPlaybackSnapshot(seconds: 6.25, isPlaying: false)
        model.minimizePreview(full, snapshot: paused)
        let mini = try XCTUnwrap(model.miniPlayerPreview)
        XCTAssertEqual(mini.playbackSnapshot, paused)
        XCTAssertEqual(mini.id, full.id)
        let later = QueuePreviewPlaybackSnapshot(seconds: 9.5, isPlaying: false)
        model.restorePreview(mini, snapshot: later)
        XCTAssertEqual(model.activePreview?.playbackSnapshot, later)
        XCTAssertNil(model.miniPlayerPreview)
        XCTAssertEqual(model.activePreview?.sourceURL, fixture.firstURL)
    }

    @MainActor
    func testPreviewHandoffPreservesPlaybackIntentAcrossRoundTrip() async throws {
        let fixture = try await makeStartRaceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let model = fixture.viewModel
        model.openPreviewForFileCard(id: fixture.firstURL.lastPathComponent)
        let full = try XCTUnwrap(model.activePreview)
        let playing = QueuePreviewPlaybackSnapshot(seconds: 12.1, isPlaying: true)
        model.minimizePreview(full, snapshot: playing)
        let mini = try XCTUnwrap(model.miniPlayerPreview)
        model.restorePreview(mini)
        XCTAssertEqual(model.activePreview?.playbackSnapshot, playing)
    }

    @MainActor
    func testPreviewHandoffRejectsCallbacksFromDismissedOrReplacedPreview() async throws {
        let fixture = try await makeStartRaceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let model = fixture.viewModel
        model.openPreviewForFileCard(id: fixture.firstURL.lastPathComponent)
        let old = try XCTUnwrap(model.activePreview)
        model.minimizePreview(old, snapshot: QueuePreviewPlaybackSnapshot(seconds: 4, isPlaying: false))
        model.startFilesFlow(url: fixture.secondURL)
        try await waitForReadyToStartState(in: model, timeout: 10)
        model.openPreviewForFileCard(id: fixture.secondURL.lastPathComponent)
        let current = try XCTUnwrap(model.activePreview)
        model.restorePreview(old)
        model.minimizePreview(old)
        XCTAssertEqual(model.activePreview?.id, current.id)
        XCTAssertNil(model.activePreview?.playbackSnapshot)
        XCTAssertNil(model.miniPlayerPreview)
        model.dismissPreview()
        model.restorePreview(current)
        XCTAssertNil(model.activePreview)
    }

    func testPreviewSnapshotSanitizesAndClampsTime() {
        for invalid in [-3.0, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(QueuePreviewPlaybackSnapshot(seconds: invalid, isPlaying: false).seconds, 0)
        }
        let snapshot = QueuePreviewPlaybackSnapshot(seconds: 100, isPlaying: true)
        XCTAssertEqual(snapshot.clampedSeconds(durationSeconds: 10), 10)
        XCTAssertEqual(snapshot.clampedSeconds(durationSeconds: nil), 100)
        XCTAssertEqual(snapshot.clampedSeconds(durationSeconds: .nan), 100)
        XCTAssertLessThan(QueuePreviewPlaybackSnapshot(seconds: .greatestFiniteMagnitude, isPlaying: true).seconds,
                          Double(Int64.max) / 1_000)
    }

    @MainActor
    func testPreviewRestorerSeeksBeforeRestoringPause() async throws {
        var events: [String] = []
        try await QueuePreviewPlaybackRestorer.restore(
            snapshot: QueuePreviewPlaybackSnapshot(seconds: 6.25, isPlaying: false), validate: {},
            isSeekable: { true }, durationSeconds: { 20 },
            seek: { events.append("seek:\($0)") }, setPlaying: { events.append("playing:\($0)") }
        )
        XCTAssertEqual(events, ["seek:6.25", "playing:false"])
    }

    @MainActor
    func testPreviewRestorerWaitsForSeekabilityAndRestoresPlay() async throws {
        var polls = 0
        var events: [String] = []
        try await QueuePreviewPlaybackRestorer.restore(
            snapshot: QueuePreviewPlaybackSnapshot(seconds: 100, isPlaying: true), validate: {},
            isSeekable: { polls += 1; return polls >= 3 }, durationSeconds: { 20 },
            seek: { events.append("seek:\($0)") }, setPlaying: { events.append("playing:\($0)") }
        )
        XCTAssertGreaterThanOrEqual(polls, 3)
        XCTAssertEqual(events, ["seek:20.0", "playing:true"])
    }

    @MainActor
    func testPreviewRestorerCancellationDoesNotSeekOrResume() async throws {
        let lifetime = QueuePreviewPlaybackLifetime()
        let id = lifetime.begin()
        var polls = 0
        var changes = 0
        let task = Task { @MainActor in
            try await QueuePreviewPlaybackRestorer.restore(
                snapshot: QueuePreviewPlaybackSnapshot(seconds: 6, isPlaying: true),
                validate: { try lifetime.check(id) }, isSeekable: { polls += 1; return false },
                durationSeconds: { 20 }, seek: { _ in changes += 1 }, setPlaying: { _ in changes += 1 }
            )
        }
        try await waitForCondition(timeout: 5) { polls > 0 }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        XCTAssertEqual(changes, 0)
    }

    @MainActor
    func testPreviewRestorerRejectsSupersededGeneration() async throws {
        let lifetime = QueuePreviewPlaybackLifetime()
        let id = lifetime.begin()
        var polls = 0
        var changes = 0
        let task = Task { @MainActor in
            try await QueuePreviewPlaybackRestorer.restore(
                snapshot: QueuePreviewPlaybackSnapshot(seconds: 6, isPlaying: false),
                validate: { try lifetime.check(id) }, isSeekable: { polls += 1; return false },
                durationSeconds: { 20 }, seek: { _ in changes += 1 }, setPlaying: { _ in changes += 1 }
            )
        }
        try await waitForCondition(timeout: 5) { polls > 0 }
        _ = lifetime.begin()
        do { try await task.value; XCTFail("Expected stale request cancellation") } catch is CancellationError {}
        XCTAssertEqual(changes, 0)
    }

    @MainActor
    func testPreviewRestorerSeekFailureDoesNotResume() async throws {
        var resumed = false
        do {
            try await QueuePreviewPlaybackRestorer.restore(
                snapshot: QueuePreviewPlaybackSnapshot(seconds: 6, isPlaying: true), validate: {},
                isSeekable: { true }, durationSeconds: { 20 },
                seek: { _ in throw NSError(domain: "Test.Seek", code: 71) }, setPlaying: { resumed = $0 }
            )
            XCTFail("Expected seek failure")
        } catch {
            XCTAssertEqual((error as NSError).domain, "Test.Seek")
        }
        XCTAssertFalse(resumed)
    }

    @MainActor
    func testPreviewRestorerAwaitsSeekBeforePause() async throws {
        let gate = PreviewAudioOperationGate()
        var events: [String] = []
        let task = Task { @MainActor in
            try await QueuePreviewPlaybackRestorer.restore(
                snapshot: QueuePreviewPlaybackSnapshot(seconds: 6, isPlaying: false), validate: {},
                isSeekable: { true }, durationSeconds: { 20 },
                seek: { _ in events.append("seekRequested"); await gate.wait(); events.append("seekCompleted") },
                setPlaying: { events.append("playing:\($0)") }
            )
        }
        try await waitForCondition(timeout: 5) { gate.isWaiting }
        XCTAssertEqual(events, ["seekRequested"])
        gate.release()
        try await task.value
        XCTAssertEqual(events, ["seekRequested", "seekCompleted", "playing:false"])
    }

    @MainActor
    func testPreviewRestorerCancellationAfterSeekDoesNotResume() async throws {
        let lifetime = QueuePreviewPlaybackLifetime()
        let id = lifetime.begin()
        var changedPlayback = false
        do {
            try await QueuePreviewPlaybackRestorer.restore(
                snapshot: QueuePreviewPlaybackSnapshot(seconds: 6, isPlaying: true),
                validate: { try lifetime.check(id) }, isSeekable: { true }, durationSeconds: { 20 },
                seek: { _ in lifetime.invalidate() }, setPlaying: { _ in changedPlayback = true }
            )
            XCTFail("Expected cancellation after the old seek finishes")
        } catch is CancellationError {}
        XCTAssertFalse(changedPlayback)
    }

    @MainActor
    func testPreviewSeekCompletionWaitsForNativeClock() async throws {
        var polls = 0
        try await QueuePreviewSeekCompletion.wait(
            targetSeconds: 6,
            reportedSeconds: { polls += 1; return polls < 3 ? nil : 6.05 }, validate: {}
        )
        XCTAssertEqual(polls, 3)
    }

    @MainActor
    func testPreviewSeekCompletionRejectsOldAndUnrelatedTimes() async throws {
        var polls = 0
        try await QueuePreviewSeekCompletion.wait(
            targetSeconds: 6,
            reportedSeconds: {
                polls += 1
                if polls == 1 { return 0.41 }
                if polls == 2 { return 7 }
                return 6.1
            }, validate: {}
        )
        XCTAssertEqual(polls, 3)
    }

    @MainActor
    func testPreviewSeekCompletionAcceptsDelayedNativeClockWithinHalfSecond() async throws {
        var polls = 0
        try await QueuePreviewSeekCompletion.wait(
            targetSeconds: 22.24,
            reportedSeconds: { polls += 1; return polls == 1 ? 0.4 : 22.655 },
            validate: {}
        )
        XCTAssertEqual(polls, 2)
    }

    @MainActor
    func testPreviewSeekCompletionRejectsTimestampPastHalfSecondTolerance() async throws {
        var polls = 0
        try await QueuePreviewSeekCompletion.wait(
            targetSeconds: 6,
            reportedSeconds: { polls += 1; return polls == 1 ? 6.55 : 6.1 },
            validate: {}
        )
        XCTAssertEqual(polls, 2)
    }

    @MainActor
    func testPreviewSeekCompletionTimeoutIsActionable() async throws {
        do {
            try await QueuePreviewSeekCompletion.wait(
                targetSeconds: 6, reportedSeconds: { 0.41 }, validate: {}, maxPolls: 2
            )
            XCTFail("A stale native clock must not count as a completed seek")
        } catch QueuePreviewPlaybackResumeError.seekNotCompleted {
            XCTAssertEqual(QueuePreviewPlaybackResumeError.seekNotCompleted.errorDescription,
                           "Playback position could not be restored. Close and open the video again.")
        }
    }

    @MainActor
    func testPreviewPausedSeekCompletionWaitsForDisplayedFrame() async throws {
        var polls = 0
        try await QueuePreviewSeekCompletion.wait(
            targetSeconds: 6, reportedSeconds: { nil }, validate: {},
            didDisplayFrame: { polls += 1; return polls >= 3 }
        )
        XCTAssertEqual(polls, 3)
    }

    @MainActor
    func testPreviewPausedSeekRetriesMissingOutputWhilePlaying() async throws {
        var events: [String] = []
        try await QueuePreviewSeekCompletion.confirmPausedSeek(
            validate: {},
            waitForOutput: { events.append("pausedSeek"); throw QueuePreviewPlaybackResumeError.seekNotCompleted },
            retryWhilePlaying: { events.append("mutedRetry") }
        )
        XCTAssertEqual(events, ["pausedSeek", "mutedRetry"])
    }

    @MainActor
    func testPreviewPausedSeekCancellationDoesNotRetry() async throws {
        var retried = false
        do {
            try await QueuePreviewSeekCompletion.confirmPausedSeek(
                validate: {}, waitForOutput: { throw CancellationError() },
                retryWhilePlaying: { retried = true }
            )
            XCTFail("Cancelled seek must not resume the player for a retry")
        } catch is CancellationError {}
        XCTAssertFalse(retried)
    }

    @MainActor
    func testPreviewPausedSeekRejectsStaleRetry() async throws {
        let lifetime = QueuePreviewPlaybackLifetime()
        let id = lifetime.begin()
        var retried = false
        do {
            try await QueuePreviewSeekCompletion.confirmPausedSeek(
                validate: { try lifetime.check(id) },
                waitForOutput: { lifetime.invalidate(); throw QueuePreviewPlaybackResumeError.seekNotCompleted },
                retryWhilePlaying: { retried = true }
            )
            XCTFail("An old player must not retry after being dismissed")
        } catch is CancellationError {}
        XCTAssertFalse(retried)
    }

    @MainActor
    func testPreviewSeekCompletionPropagatesCancellation() async throws {
        var polls = 0
        let task = Task { @MainActor in
            try await QueuePreviewSeekCompletion.wait(
                targetSeconds: 6, reportedSeconds: { polls += 1; return nil }, validate: {}
            )
        }
        try await waitForCondition(timeout: 5) { polls > 0 }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancelled seek wait") } catch is CancellationError {}
    }

    @MainActor
    func testPreviewSeekReadinessRequiresPlayingAndNativeTimestamp() async throws {
        var polls = 0
        try await QueuePreviewSeekCompletion.waitUntilReady(
            isPlaying: { polls += 1; return polls > 1 },
            reportedSeconds: { polls < 3 ? 0 : 0.1 }, validate: {}
        )
        XCTAssertEqual(polls, 3)
    }

    @MainActor
    func testPreviewSeekReadinessTimeoutRejectsUnstartedClock() async throws {
        do {
            try await QueuePreviewSeekCompletion.waitUntilReady(
                isPlaying: { true }, reportedSeconds: { 0 }, validate: {}, maxPolls: 2
            )
            XCTFail("Video output readiness must not imply that the input clock is ready")
        } catch QueuePreviewPlaybackResumeError.seekNotCompleted {}
    }

    @MainActor
    func testPreviewSeekReadinessPropagatesCancellation() async throws {
        var polls = 0
        let task = Task { @MainActor in
            try await QueuePreviewSeekCompletion.waitUntilReady(
                isPlaying: { polls += 1; return false }, reportedSeconds: { nil }, validate: {}
            )
        }
        try await waitForCondition(timeout: 5) { polls > 0 }
        task.cancel()
        do { try await task.value; XCTFail("Expected cancelled input readiness wait") } catch is CancellationError {}
    }

    @MainActor
    func testPreviewAudioLifetimeSerializesPendingActivationAndClose() async throws {
        let gate = PreviewAudioOperationGate()
        var events: [String] = []
        let lifetime = QueuePreviewAudioSessionLifetime(
            activate: { events.append("activate"); await gate.wait() },
            deactivate: { events.append("deactivate") }
        )
        let opening = Task { try await lifetime.activate(id: "full") }
        try await waitForCondition(timeout: 5) { gate.isWaiting }
        lifetime.deactivate(id: "full")
        XCTAssertEqual(events, ["activate"])
        gate.release()
        do { try await opening.value; XCTFail("Expected closed session") } catch is CancellationError {}
        await lifetime.waitForPendingOperations()
        XCTAssertEqual(events, ["activate", "deactivate"])
    }

    @MainActor
    func testPreviewAudioLifetimeOldShutdownDoesNotDeactivateNewPreview() async throws {
        var activations = 0
        var deactivations = 0
        let lifetime = QueuePreviewAudioSessionLifetime(
            activate: { activations += 1 }, deactivate: { deactivations += 1 }
        )
        try await lifetime.activate(id: "full")
        try await lifetime.activate(id: "mini")
        lifetime.deactivate(id: "full")
        await lifetime.waitForPendingOperations()
        XCTAssertEqual(activations, 2)
        XCTAssertEqual(deactivations, 0)
        lifetime.deactivate(id: "mini")
        await lifetime.waitForPendingOperations()
        XCTAssertEqual(deactivations, 1)
    }

}
