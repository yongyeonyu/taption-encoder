import Foundation
import CoreGraphics

enum QueuePreviewSurfaceVerticalAction: Equatable {
    case brightness, volume, close
}

enum QueuePreviewSurfaceGesturePolicy {
    // Lock to the region where the drag began, even if the finger crosses a boundary.
    static func verticalAction(start: CGPoint, translation: CGSize, size: CGSize) -> QueuePreviewSurfaceVerticalAction? {
        guard isInsideSurface(start, size: size),
              translation.width.isFinite, translation.height.isFinite,
              abs(translation.height) >= 18,
              abs(translation.height) > abs(translation.width) * 1.2 else { return nil }
        if start.x < size.width / 3 { return .brightness }
        if start.x > size.width * 2 / 3 { return .volume }
        return .close
    }

    static func shouldClose(translation: CGSize, size: CGSize) -> Bool {
        guard size.width.isFinite, size.width > 0, size.height.isFinite, size.height > 0,
              translation.width.isFinite, translation.height.isFinite else { return false }
        let threshold = max(72, min(size.height * 0.12, 120))
        return translation.height >= threshold && translation.height > abs(translation.width) * 1.2
    }

    static func canStart(start: CGPoint, size: CGSize, excludedFrames: [CGRect]) -> Bool {
        guard isInsideSurface(start, size: size) else { return false }
        // Use the controls' actual bounds so rotation and text size don't change routing.
        return !excludedFrames.contains { $0.contains(start) }
    }

    private static func isInsideSurface(_ start: CGPoint, size: CGSize) -> Bool {
        size.width.isFinite && size.width > 0 && size.height.isFinite && size.height > 0
            && start.x.isFinite && start.y.isFinite
            && start.x >= 0 && start.x <= size.width && start.y >= 0 && start.y <= size.height
    }
}

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

