import ActivityKit
import Foundation

@MainActor
protocol EncodingLiveActivityCoordinating {
    var areActivitiesEnabled: Bool { get }
    func start(snapshot: TaptionEncodingActivitySnapshot) async
    func update(snapshot: TaptionEncodingActivitySnapshot) async
    func end(snapshot: TaptionEncodingActivitySnapshot, dismissalDelay: TimeInterval) async
    func cancel() async
}

@MainActor
final class ActivityKitEncodingLiveActivityCoordinator: EncodingLiveActivityCoordinating {
    private var activity: Activity<TaptionEncodingLiveActivityAttributes>?

    nonisolated init() {}

    var areActivitiesEnabled: Bool {
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    func start(snapshot: TaptionEncodingActivitySnapshot) async {
        guard #available(iOS 16.2, *) else {
            return
        }
        guard areActivitiesEnabled else {
            AppLogger.info("Live Activity skipped because activities are disabled", category: .encoding)
            return
        }

        if let activity {
            await update(snapshot: snapshot)
            AppLogger.info(
                "Live Activity reused",
                category: .encoding,
                metadata: ["activity": activity.id, "session": snapshot.sessionID]
            )
            return
        }

        do {
            let content = ActivityContent(
                state: snapshot.contentState,
                staleDate: nil,
                relevanceScore: 1
            )
            activity = try Activity.request(
                attributes: snapshot.activityAttributes,
                content: content,
                pushType: nil
            )
            AppLogger.info(
                "Live Activity started",
                category: .encoding,
                metadata: ["session": snapshot.sessionID]
            )
        } catch {
            AppLogger.warning(
                "Live Activity could not start",
                category: .encoding,
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    func update(snapshot: TaptionEncodingActivitySnapshot) async {
        guard #available(iOS 16.2, *),
              let activity else {
            return
        }
        let content = ActivityContent(
            state: snapshot.contentState,
            staleDate: nil,
            relevanceScore: 1
        )
        await activity.update(content)
    }

    func end(snapshot: TaptionEncodingActivitySnapshot, dismissalDelay: TimeInterval = 12) async {
        guard #available(iOS 16.2, *),
              let activity else {
            self.activity = nil
            return
        }
        let content = ActivityContent(
            state: snapshot.contentState,
            staleDate: nil,
            relevanceScore: 0
        )
        await activity.end(
            content,
            dismissalPolicy: .after(Date().addingTimeInterval(max(dismissalDelay, 0)))
        )
        self.activity = nil
        AppLogger.info(
            "Live Activity ended",
            category: .encoding,
            metadata: ["session": snapshot.sessionID]
        )
    }

    func cancel() async {
        guard #available(iOS 16.2, *),
              let activity else {
            self.activity = nil
            return
        }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
        AppLogger.info("Live Activity cancelled", category: .encoding)
    }
}

struct NoopEncodingLiveActivityCoordinator: EncodingLiveActivityCoordinating {
    nonisolated init() {}

    var areActivitiesEnabled: Bool { false }
    func start(snapshot: TaptionEncodingActivitySnapshot) async {}
    func update(snapshot: TaptionEncodingActivitySnapshot) async {}
    func end(snapshot: TaptionEncodingActivitySnapshot, dismissalDelay: TimeInterval) async {}
    func cancel() async {}
}
