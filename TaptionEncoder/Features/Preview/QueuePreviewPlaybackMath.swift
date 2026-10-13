import Foundation
import CoreGraphics

enum QueuePreviewPlaybackMath {
    static let skipIntervalSeconds = 10.0

    static func seconds(from duration: Duration?) -> Double? {
        guard let duration else {
            return nil
        }
        let components = duration.components
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        let total = seconds + attoseconds
        return total.isFinite ? max(0, total) : nil
    }

    static func formattedTime(_ duration: Duration?) -> String {
        formattedSeconds(seconds(from: duration))
    }

    static func formattedSeconds(_ seconds: Double?) -> String {
        MediaDisplayFormatting.time(seconds)
    }

    static func clampedSeekSeconds(_ seconds: Double, duration: Double) -> Double? {
        guard seconds.isFinite, duration.isFinite, duration > 0 else { return nil }
        return min(max(seconds, 0), min(duration, Double(Int64.max / 2) / 600))
    }

    static func clampedPosition(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    static func hasUsableTimeline(durationSeconds: Double?) -> Bool {
        guard let durationSeconds,
              durationSeconds.isFinite else {
            return false
        }
        return durationSeconds > 0
    }

    static func displayedSliderPosition(
        playerPosition: Double,
        isScrubbing: Bool,
        scrubberPosition: Double,
        dragSeekPreviewPosition: Double?,
        durationSeconds: Double?
    ) -> Double {
        guard hasUsableTimeline(durationSeconds: durationSeconds) else {
            return 0
        }
        if isScrubbing {
            return clampedPosition(scrubberPosition)
        }
        if let dragSeekPreviewPosition {
            return clampedPosition(dragSeekPreviewPosition)
        }
        return clampedPosition(playerPosition)
    }

    static func horizontalDragPosition(
        startPosition: Double,
        translation: CGFloat,
        containerWidth: CGFloat
    ) -> Double {
        guard containerWidth.isFinite, containerWidth > 0, translation.isFinite else {
            return clampedPosition(startPosition)
        }
        let positionDelta = Double(translation / containerWidth)
        return clampedPosition(startPosition + positionDelta)
    }

    static func verticalAdjustmentDelta(
        translation: CGFloat,
        containerHeight: CGFloat
    ) -> Float {
        guard containerHeight.isFinite, containerHeight > 0, translation.isFinite else {
            return 0
        }
        return Float(min(max(-translation / containerHeight, -1), 1))
    }
}

