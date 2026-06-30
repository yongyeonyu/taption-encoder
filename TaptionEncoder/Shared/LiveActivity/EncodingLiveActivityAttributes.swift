import ActivityKit
import Foundation

struct TaptionEncodingLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var statusText: String
        var sourceName: String
        var modeText: String
        var currentIndex: Int
        var totalCount: Int
        var fractionCompleted: Double
        var percentText: String
        var elapsedText: String
        var remainingText: String
        var codecPathText: String
        var outputText: String

        var countText: String {
            guard totalCount > 1 else {
                return "Single video"
            }
            return "\(currentIndex) of \(totalCount)"
        }
    }

    var sessionID: String
    var title: String
}

enum TaptionEncodingActivityMode: String, Codable, Hashable {
    case single
    case folder

    var displayText: String {
        switch self {
        case .single:
            return "Single"
        case .folder:
            return "Folder"
        }
    }
}

struct TaptionEncodingActivitySnapshot: Codable, Hashable {
    var sessionID: String
    var title: String
    var statusText: String
    var sourceName: String
    var mode: TaptionEncodingActivityMode
    var currentIndex: Int
    var totalCount: Int
    var fractionCompleted: Double
    var elapsedSeconds: TimeInterval
    var remainingSeconds: TimeInterval?
    var codecPathText: String
    var outputText: String

    init(
        sessionID: String,
        title: String = "Taption Encoder",
        statusText: String,
        sourceName: String,
        mode: TaptionEncodingActivityMode,
        currentIndex: Int = 1,
        totalCount: Int = 1,
        fractionCompleted: Double,
        elapsedSeconds: TimeInterval,
        remainingSeconds: TimeInterval?,
        codecPathText: String,
        outputText: String
    ) {
        self.sessionID = sessionID
        self.title = title
        self.statusText = statusText
        self.sourceName = sourceName
        self.mode = mode
        self.currentIndex = max(currentIndex, 1)
        self.totalCount = max(totalCount, 1)
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.elapsedSeconds = max(elapsedSeconds, 0)
        self.remainingSeconds = remainingSeconds
        self.codecPathText = codecPathText
        self.outputText = outputText
    }

    var activityAttributes: TaptionEncodingLiveActivityAttributes {
        TaptionEncodingLiveActivityAttributes(
            sessionID: sessionID,
            title: title
        )
    }

    var contentState: TaptionEncodingLiveActivityAttributes.ContentState {
        TaptionEncodingLiveActivityAttributes.ContentState(
            statusText: statusText,
            sourceName: sourceName,
            modeText: mode.displayText,
            currentIndex: currentIndex,
            totalCount: totalCount,
            fractionCompleted: fractionCompleted,
            percentText: "\(Int((fractionCompleted * 100).rounded()))%",
            elapsedText: Self.timeText(elapsedSeconds),
            remainingText: Self.remainingTimeText(remainingSeconds),
            codecPathText: codecPathText,
            outputText: outputText
        )
    }

    static func timeText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds / 60) % 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func remainingTimeText(_ seconds: TimeInterval?) -> String {
        guard let seconds else {
            return "--:--"
        }
        return timeText(seconds)
    }
}

struct TaptionEncodingLiveActivityLayoutMetrics: Hashable {
    var horizontalPadding: Double
    var topPadding: Double
    var bottomPadding: Double
    var verticalSpacing: Double

    static let dynamicIslandExpandedTopPadding = 10.0
    static let dynamicIslandBottomTopPadding = 7.0

    static func lockScreen(
        isRegularWidth: Bool,
        isSupplementalSmallFamily: Bool = false
    ) -> TaptionEncodingLiveActivityLayoutMetrics {
        if isSupplementalSmallFamily {
            return TaptionEncodingLiveActivityLayoutMetrics(
                horizontalPadding: 12,
                topPadding: 46,
                bottomPadding: 10,
                verticalSpacing: 4
            )
        }

        return TaptionEncodingLiveActivityLayoutMetrics(
            horizontalPadding: isRegularWidth ? 20 : 16,
            topPadding: isRegularWidth ? 78 : 64,
            bottomPadding: isRegularWidth ? 14 : 12,
            verticalSpacing: isRegularWidth ? 6 : 5
        )
    }
}
