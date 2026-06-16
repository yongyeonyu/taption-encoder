import Foundation
import UIKit

protocol BackgroundEncodingCoordinating: TaptionBackgroundEncodingCoordinating {}

final class UIApplicationBackgroundEncodingCoordinator: BackgroundEncodingCoordinating {
    private var activePlanIDs: Set<UUID> = []
    private var backgroundTasks: [UUID: UIBackgroundTaskIdentifier] = [:]
    private let application: UIApplication

    init(application: UIApplication = .shared) {
        self.application = application
    }

    var support: TaptionBackgroundEncodingSupport {
        .availableWhenUserChooses
    }

    func beginBackgroundEncoding(plan: TaptionEncodingPlan) async throws {
        await MainActor.run {
            beginBackgroundEncodingOnMainActor(plan: plan)
        }
    }

    func endBackgroundEncoding(planID: UUID) async {
        await MainActor.run {
            endBackgroundEncodingOnMainActor(planID: planID)
        }
    }

    @MainActor
    private func beginBackgroundEncodingOnMainActor(plan: TaptionEncodingPlan) {
        guard !activePlanIDs.contains(plan.id) else {
            return
        }

        activePlanIDs.insert(plan.id)
        application.isIdleTimerDisabled = true

        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = application.beginBackgroundTask(withName: "Taption Encoding") { [weak self] in
            Task { @MainActor [weak self] in
                self?.expireBackgroundTask(planID: plan.id)
            }
        }

        guard taskID != .invalid else {
            AppLogger.warning(
                "Background task could not be started; idle timer remains disabled while active",
                category: .encoding,
                metadata: ["plan": plan.id.uuidString]
            )
            return
        }

        backgroundTasks[plan.id] = taskID
        AppLogger.info(
            "Background encoding task started",
            category: .encoding,
            metadata: ["plan": plan.id.uuidString]
        )
    }

    @MainActor
    private func endBackgroundEncodingOnMainActor(planID: UUID) {
        activePlanIDs.remove(planID)

        if let taskID = backgroundTasks.removeValue(forKey: planID) {
            application.endBackgroundTask(taskID)
            AppLogger.info(
                "Background encoding task ended",
                category: .encoding,
                metadata: ["plan": planID.uuidString]
            )
        }

        if activePlanIDs.isEmpty {
            application.isIdleTimerDisabled = false
        }
    }

    @MainActor
    private func expireBackgroundTask(planID: UUID) {
        guard let taskID = backgroundTasks.removeValue(forKey: planID) else {
            return
        }

        application.endBackgroundTask(taskID)
        AppLogger.warning(
            "Background encoding time expired",
            category: .encoding,
            metadata: ["plan": planID.uuidString]
        )
    }
}

struct FakeBackgroundEncodingCoordinator: BackgroundEncodingCoordinating {
    var support: TaptionBackgroundEncodingSupport {
        .unavailableKeepAppOpen
    }

    func beginBackgroundEncoding(plan: TaptionEncodingPlan) async throws {}

    func endBackgroundEncoding(planID: UUID) async {}
}
