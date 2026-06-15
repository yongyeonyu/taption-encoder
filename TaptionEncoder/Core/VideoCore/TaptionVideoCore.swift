import Foundation

enum TaptionVideoCoreError: Error, Equatable {
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64?)
    case missingTemporaryOutputURL
}

struct TaptionPreparedEncodingJob: Equatable {
    var asset: TaptionVideoAsset
    var plan: TaptionEncodingPlan
    var storageRequirement: TaptionStorageRequirement

    init(
        asset: TaptionVideoAsset,
        plan: TaptionEncodingPlan,
        storageRequirement: TaptionStorageRequirement
    ) {
        self.asset = asset
        self.plan = plan
        self.storageRequirement = storageRequirement
    }
}

struct TaptionVideoCore {
    var services: TaptionVideoCoreServices

    init(services: TaptionVideoCoreServices) {
        self.services = services
    }

    func prepareSingleAssetHEVCJob(
        sourceURL: URL,
        temporaryOutputURL: URL,
        preferredMode: TaptionEncoderMode = .hardware,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy()
    ) async throws -> TaptionPreparedEncodingJob {
        let asset = try await services.inspector.inspectVideo(at: sourceURL)
        let plan = TaptionEncodingPlanner.makeSingleAssetHEVCPlan(
            asset: asset,
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryOutputURL,
            preferredMode: preferredMode,
            savePolicy: savePolicy
        )
        let storageRequirement = try await services.storageChecker.storageRequirement(for: plan)
        guard storageRequirement.hasEnoughSpace else {
            throw TaptionVideoCoreError.insufficientStorage(
                requiredBytes: storageRequirement.requiredWorkingBytes,
                availableBytes: storageRequirement.availableBytes
            )
        }
        return TaptionPreparedEncodingJob(
            asset: asset,
            plan: plan,
            storageRequirement: storageRequirement
        )
    }

    func encodePreparedJob(
        _ job: TaptionPreparedEncodingJob,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionEncodingResult {
        try await services.backgroundCoordinator?.beginBackgroundEncoding(plan: job.plan)

        do {
            var result = try await services.encoder.encode(plan: job.plan, progress: progress)
            if result.pendingSaveState == nil {
                result.pendingSaveState = makePendingSaveStateIfNeeded(
                    plan: job.plan,
                    result: result
                )
            }

            if let pendingSaveState = result.pendingSaveState,
               job.plan.savePolicy.shouldRestorePendingSaveOnLaunch {
                try await services.pendingSaveStore.savePendingState(pendingSaveState)
            }

            await services.backgroundCoordinator?.endBackgroundEncoding(planID: job.plan.id)
            return result
        } catch {
            await services.backgroundCoordinator?.endBackgroundEncoding(planID: job.plan.id)
            throw error
        }
    }

    func cancelEncoding(planID: UUID) async {
        await services.encoder.cancelEncoding(planID: planID)
        await services.backgroundCoordinator?.endBackgroundEncoding(planID: planID)
    }

    func loadRestorablePendingSaves() async throws -> [TaptionPendingSaveState] {
        try await services.pendingSaveStore.loadPendingStates()
    }

    func authorizePendingSave(_ state: TaptionPendingSaveState) async throws -> Bool {
        let isAuthorized = try await services.saveGateAuthorizer.authorizeFinalSave(for: state)
        if isAuthorized {
            try await services.pendingSaveStore.removePendingState(id: state.id)
        }
        return isAuthorized
    }

    private func makePendingSaveStateIfNeeded(
        plan: TaptionEncodingPlan,
        result: TaptionEncodingResult
    ) -> TaptionPendingSaveState? {
        guard plan.savePolicy.saveGate == .rewardedAdBeforeFinalSave else {
            return nil
        }
        return TaptionPendingSaveState(
            planID: plan.id,
            temporaryOutputURL: result.temporaryOutputURL,
            finalOutputURL: plan.finalOutputURL,
            saveDestination: plan.savePolicy.destination,
            requiresRewardedAd: true
        )
    }
}
