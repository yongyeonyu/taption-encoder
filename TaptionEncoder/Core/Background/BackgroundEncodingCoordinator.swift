import Foundation
import BackgroundTasks
import UIKit

protocol BackgroundEncodingCoordinating: TaptionBackgroundEncodingCoordinating {}

final class UIApplicationBackgroundEncodingCoordinator: BackgroundEncodingCoordinating {
    private var activePlanIDs: Set<UUID> = []
    private var backgroundTasks: [UUID: UIBackgroundTaskIdentifier] = [:]
    private var continuedTaskIDs: [UUID: String] = [:]
    private var continuedTasks: [UUID: AnyObject] = [:]
    private var registeredContinuedTaskIdentifiers: Set<String> = []
    private let application: UIApplication
    private let continuedTaskIdentifierPrefix = "com.taption.encoder.encoding"

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
        submitContinuedProcessingTaskIfAvailable(plan: plan)
        AppLogger.info(
            "Background encoding task started",
            category: .encoding,
            metadata: ["plan": plan.id.uuidString]
        )
    }

    func updateBackgroundEncoding(planID: UUID, snapshot: TaptionBackgroundEncodingSnapshot) async {
        await MainActor.run {
            updateBackgroundEncodingOnMainActor(planID: planID, snapshot: snapshot)
        }
    }

    @MainActor
    private func updateBackgroundEncodingOnMainActor(
        planID: UUID,
        snapshot: TaptionBackgroundEncodingSnapshot
    ) {
        guard #available(iOS 26.0, *),
              let task = continuedTasks[planID] as? BGContinuedProcessingTask else {
            return
        }

        task.updateTitle(snapshot.title, subtitle: snapshot.subtitle)
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = Int64((snapshot.fractionCompleted * 1000).rounded())
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

        completeContinuedProcessingTask(planID: planID, success: true)
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

    @MainActor
    private func submitContinuedProcessingTaskIfAvailable(plan: TaptionEncodingPlan) {
        guard #available(iOS 26.0, *) else {
            return
        }

        let taskIdentifier = continuedTaskIdentifier(for: plan)
        let registered = registerContinuedProcessingTaskIfNeeded(
            identifier: taskIdentifier,
            planID: plan.id
        )
        guard registered else {
            return
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: taskIdentifier,
            title: "BOKKI Encoder",
            subtitle: plan.sourceURL?.lastPathComponent ?? "Encoding video"
        )
        request.strategy = .queue
        request.requiredResources = []
        do {
            try BGTaskScheduler.shared.submit(request)
            continuedTaskIDs[plan.id] = taskIdentifier
            AppLogger.info(
                "Continued processing task submitted",
                category: .encoding,
                metadata: ["plan": plan.id.uuidString, "identifier": taskIdentifier]
            )
        } catch {
            AppLogger.warning(
                "Continued processing task could not be submitted",
                category: .encoding,
                metadata: ["plan": plan.id.uuidString, "error": error.localizedDescription]
            )
        }
    }

    @available(iOS 26.0, *)
    @MainActor
    private func registerContinuedProcessingTaskIfNeeded(
        identifier: String,
        planID: UUID
    ) -> Bool {
        guard !registeredContinuedTaskIdentifiers.contains(identifier) else {
            return true
        }

        let didRegister = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                self?.handleContinuedProcessingTask(continuedTask, planID: planID)
            }
        }

        if didRegister {
            registeredContinuedTaskIdentifiers.insert(identifier)
        } else {
            AppLogger.warning(
                "Continued processing task registration failed",
                category: .encoding,
                metadata: ["plan": planID.uuidString, "identifier": identifier]
            )
        }
        return didRegister
    }

    @available(iOS 26.0, *)
    @MainActor
    private func handleContinuedProcessingTask(
        _ task: BGContinuedProcessingTask,
        planID: UUID
    ) {
        continuedTasks[planID] = task
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = 0
        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.expireContinuedProcessingTask(planID: planID)
            }
        }
        AppLogger.info(
            "Continued processing task started",
            category: .encoding,
            metadata: ["plan": planID.uuidString]
        )
    }

    @MainActor
    private func expireContinuedProcessingTask(planID: UUID) {
        completeContinuedProcessingTask(planID: planID, success: false)
        AppLogger.warning(
            "Continued processing task expired",
            category: .encoding,
            metadata: ["plan": planID.uuidString]
        )
    }

    @MainActor
    private func completeContinuedProcessingTask(planID: UUID, success: Bool) {
        if #available(iOS 26.0, *),
           let task = continuedTasks.removeValue(forKey: planID) as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = success ? task.progress.totalUnitCount : task.progress.completedUnitCount
            task.setTaskCompleted(success: success)
        }

        if #available(iOS 26.0, *),
           let identifier = continuedTaskIDs.removeValue(forKey: planID) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
    }

    private func continuedTaskIdentifier(for plan: TaptionEncodingPlan) -> String {
        "\(continuedTaskIdentifierPrefix).\(plan.id.uuidString)"
    }
}

struct FakeBackgroundEncodingCoordinator: BackgroundEncodingCoordinating {
    var support: TaptionBackgroundEncodingSupport {
        .unavailableKeepAppOpen
    }

    func beginBackgroundEncoding(plan: TaptionEncodingPlan) async throws {}

    func updateBackgroundEncoding(planID: UUID, snapshot: TaptionBackgroundEncodingSnapshot) async {}

    func endBackgroundEncoding(planID: UUID) async {}
}
