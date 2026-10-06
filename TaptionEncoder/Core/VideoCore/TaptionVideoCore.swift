import Foundation

enum TaptionVideoCoreError: Error, Equatable {
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64?)
    case missingTemporaryOutputURL
    case missingSourceURL
    case noVideoTrack
    case unsupportedSourceCodec(TaptionVideoCodec)
    case compatibleHEVCPresetUnavailable
    case exportFailed(String)
    case finalSaveFailed(String)
}

struct TaptionPreparedEncodingJob: Equatable {
    var asset: TaptionVideoAsset
    var plan: TaptionEncodingPlan
    var routeSelection: TaptionCodecRouteSelection
    var storageRequirement: TaptionStorageRequirement

    init(
        asset: TaptionVideoAsset,
        plan: TaptionEncodingPlan,
        routeSelection: TaptionCodecRouteSelection,
        storageRequirement: TaptionStorageRequirement
    ) {
        self.asset = asset
        self.plan = plan
        self.routeSelection = routeSelection
        self.storageRequirement = storageRequirement
    }
}

enum TaptionBackgroundTaskCompletionPolicy: Equatable {
    case afterEncoding
    case callerManaged
}

struct TaptionVideoCore {
    var services: TaptionVideoCoreServices

    init(services: TaptionVideoCoreServices) {
        self.services = services
    }

    func prepareSingleAssetHEVCJob(
        sourceURL: URL,
        temporaryOutputURL: URL,
        preferredMode: TaptionEncoderMode = .automatic,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy()
    ) async throws -> TaptionPreparedEncodingJob {
        let job = try await prepareSingleAssetJob(
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryOutputURL,
            outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
            preferredMode: preferredMode,
            savePolicy: savePolicy
        )

        guard job.routeSelection.isEncodableNow else {
            throw TaptionVideoCoreError.unsupportedSourceCodec(job.asset.videoTrack?.codec ?? .unknown)
        }
        return job
    }

    func prepareSingleAssetJob(
        sourceURL: URL,
        temporaryOutputURL: URL,
        outputPolicy: TaptionVideoOutputPolicy,
        preferredMode: TaptionEncoderMode = .automatic,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy()
    ) async throws -> TaptionPreparedEncodingJob {
        let asset = try await services.inspector.inspectVideo(at: sourceURL)
        return try await prepareSingleAssetJob(
            asset: asset,
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryOutputURL,
            outputPolicy: outputPolicy,
            preferredMode: preferredMode,
            savePolicy: savePolicy
        )
    }

    func prepareSingleAssetJob(
        asset: TaptionVideoAsset,
        sourceURL: URL,
        temporaryOutputURL: URL,
        outputPolicy: TaptionVideoOutputPolicy,
        preferredMode: TaptionEncoderMode = .automatic,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy()
    ) async throws -> TaptionPreparedEncodingJob {
        guard asset.videoTrack != nil else {
            throw TaptionVideoCoreError.noVideoTrack
        }
        let routeSelection = TaptionCodecRoutePlanner.selectRoute(
            for: asset,
            outputCodec: outputPolicy.videoCodec,
            requestedMode: preferredMode
        )
        let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
            asset: asset,
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryOutputURL,
            outputPolicy: outputPolicy,
            preferredMode: preferredMode,
            savePolicy: savePolicy
        )
        let storageRequirement = try await services.storageChecker.storageRequirement(for: plan)
        let audioRunnableInThisBuild = plan.audioPlan?.isRunnableInCurrentBuild ?? true
        let canRunInThisBuild = routeSelection.isEncodableNow
            && outputPolicy.videoCodec == .hevc
            && outputPolicy.audioCodec == TaptionAudioCodecRoutePlanner.defaultOutputCodec
            && [.mp4, .mov].contains(outputPolicy.container)
            && audioRunnableInThisBuild
        guard !canRunInThisBuild || storageRequirement.hasEnoughSpace else {
            throw TaptionVideoCoreError.insufficientStorage(
                requiredBytes: storageRequirement.requiredWorkingBytes,
                availableBytes: storageRequirement.availableBytes
            )
        }
        return TaptionPreparedEncodingJob(
            asset: asset,
            plan: plan,
            routeSelection: routeSelection,
            storageRequirement: storageRequirement
        )
    }

    func encodePreparedJob(
        _ job: TaptionPreparedEncodingJob,
        backgroundTaskCompletionPolicy: TaptionBackgroundTaskCompletionPolicy = .afterEncoding,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionEncodingResult {
        let trace = TaptionEncodingPerformanceTrace(
            name: "core_encode_prepared_job",
            category: .encoding,
            metadata: [
                "plan": job.plan.id.uuidString,
                "route": job.plan.codecRoute?.displayName ?? "unknown",
                "executionKind": job.plan.codecExecutionKind?.rawValue ?? "unknown"
            ]
        )
        var didBeginBackgroundEncoding = false
        do {
            try await services.backgroundCoordinator?.beginBackgroundEncoding(plan: job.plan)
            didBeginBackgroundEncoding = services.backgroundCoordinator != nil
            trace.mark("background_task_ready")

            var result = try await services.encoder.encode(plan: job.plan) { [services] encodingProgress in
                Task {
                    await services.backgroundCoordinator?.updateBackgroundEncoding(
                        planID: job.plan.id,
                        snapshot: TaptionBackgroundEncodingSnapshot(
                            title: "YYY Encoder",
                            subtitle: job.asset.displayName,
                            fractionCompleted: encodingProgress.fractionCompleted
                        )
                    )
                }
                progress(encodingProgress)
            }
            trace.mark(
                "encoder_completed",
                metadata: [
                    "mode": result.usedMode.rawValue,
                    "backend": result.usedBackend.rawValue
                ]
            )
            if result.pendingSaveState == nil {
                result.pendingSaveState = makePendingSaveStateIfNeeded(
                    plan: job.plan,
                    result: result
                )
                trace.mark("pending_save_state_created")
            }

            if let pendingSaveState = result.pendingSaveState,
               job.plan.savePolicy.shouldRestorePendingSaveOnLaunch {
                try await services.pendingSaveStore.savePendingState(pendingSaveState)
                trace.mark(
                    "pending_save_persisted",
                    metadata: ["pendingSave": pendingSaveState.id.uuidString]
                )
            }

            if backgroundTaskCompletionPolicy == .afterEncoding {
                await services.backgroundCoordinator?.endBackgroundEncoding(planID: job.plan.id)
                didBeginBackgroundEncoding = false
            } else {
                trace.mark("background_task_retained_for_caller")
            }
            trace.finish("completed")
            return result
        } catch is CancellationError {
            if didBeginBackgroundEncoding {
                await services.backgroundCoordinator?.endBackgroundEncoding(planID: job.plan.id)
            }
            trace.finish("cancelled")
            throw CancellationError()
        } catch {
            if didBeginBackgroundEncoding {
                await services.backgroundCoordinator?.endBackgroundEncoding(planID: job.plan.id)
            }
            trace.finish("failed", metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    func cancelEncoding(planID: UUID) async {
        await services.encoder.cancelEncoding(planID: planID)
        await services.backgroundCoordinator?.endBackgroundEncoding(planID: planID)
    }

    func completeBackgroundEncoding(planID: UUID) async {
        await services.backgroundCoordinator?.endBackgroundEncoding(planID: planID)
    }

    func loadRestorablePendingSaves() async throws -> [TaptionPendingSaveState] {
        try await services.pendingSaveStore.loadPendingStates()
    }

    func authorizePendingSave(_ state: TaptionPendingSaveState) async throws -> Bool {
        guard state.requiresRewardedAd else {
            return true
        }

        let isAuthorized = try await services.saveGateAuthorizer.authorizeFinalSave(for: state)
        if isAuthorized {
            var authorizedState = state
            authorizedState.requiresRewardedAd = false
            authorizedState.rewardedAdCompletedAt = Date()
            try await services.pendingSaveStore.savePendingState(authorizedState)
        }
        return isAuthorized
    }

    private func makePendingSaveStateIfNeeded(
        plan: TaptionEncodingPlan,
        result: TaptionEncodingResult
    ) -> TaptionPendingSaveState? {
        let requiresRewardedAd = plan.savePolicy.saveGate == .rewardedAdBeforeFinalSave
        return TaptionPendingSaveState(
            planID: plan.id,
            temporaryOutputURL: result.temporaryOutputURL,
            finalOutputURL: plan.finalOutputURL,
            saveDestination: plan.savePolicy.destination,
            requiresRewardedAd: requiresRewardedAd
        )
    }
}

extension TaptionVideoCoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .insufficientStorage(let requiredBytes, let availableBytes):
            let required = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
            let available = availableBytes.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? "unknown"
            return "Not enough storage. Required: \(required). Available: \(available)."
        case .missingTemporaryOutputURL:
            return "The temporary output path was not prepared."
        case .missingSourceURL:
            return "The source file path is missing."
        case .noVideoTrack:
            return "This file does not contain a readable video track."
        case .unsupportedSourceCodec(let codec):
            let executableInputs = TaptionLaunchSupportCatalog.executableNowInputVideoCodecs
                .map(\.displayName)
                .joined(separator: ", ")
            let hardwareGatedInputs = TaptionLaunchSupportCatalog.hardwareGatedInputVideoCodecs
                .map(\.displayName)
            let hardwareClause = hardwareGatedInputs.isEmpty
                ? ""
                : " Hardware-gated inputs: \(hardwareGatedInputs.joined(separator: ", "))."
            return "This build can run H.265 / MP4 or MOV output for \(executableInputs).\(hardwareClause) \(codec.displayName) remains part of the universal codec roadmap, but this route is not executable on the selected device/output path yet."
        case .compatibleHEVCPresetUnavailable:
            return "This device cannot create a compatible H.265 export session for this file."
        case .exportFailed(let message):
            return message
        case .finalSaveFailed(let message):
            return message
        }
    }
}
