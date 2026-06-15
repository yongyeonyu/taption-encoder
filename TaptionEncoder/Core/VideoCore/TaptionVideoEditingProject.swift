import Foundation

enum TaptionProjectDocumentKind: String, Codable, Equatable {
    case fcpxml
    case fcpxmld
}

struct TaptionFCPXMLPolicy: Codable, Equatable {
    var documentKind: TaptionProjectDocumentKind
    var dtdVersion: String?
    var resolvesLatestStableDTDAtWriteTime: Bool
    var canBundleManagedMedia: Bool

    init(
        documentKind: TaptionProjectDocumentKind = .fcpxml,
        dtdVersion: String? = nil,
        resolvesLatestStableDTDAtWriteTime: Bool = true,
        canBundleManagedMedia: Bool = false
    ) {
        self.documentKind = documentKind
        self.dtdVersion = dtdVersion
        self.resolvesLatestStableDTDAtWriteTime = resolvesLatestStableDTDAtWriteTime
        self.canBundleManagedMedia = canBundleManagedMedia
    }
}

struct TaptionTimeRange: Codable, Equatable {
    var start: TimeInterval
    var duration: TimeInterval

    init(start: TimeInterval, duration: TimeInterval) {
        self.start = max(0, start)
        self.duration = max(0, duration)
    }

    var end: TimeInterval {
        start + duration
    }
}

struct TaptionCanvasPlacement: Codable, Equatable {
    var normalizedCenterX: Double
    var normalizedCenterY: Double
    var scale: Double
    var rotationDegrees: Double

    init(
        normalizedCenterX: Double = 0.5,
        normalizedCenterY: Double = 0.5,
        scale: Double = 1,
        rotationDegrees: Double = 0
    ) {
        self.normalizedCenterX = normalizedCenterX
        self.normalizedCenterY = normalizedCenterY
        self.scale = scale
        self.rotationDegrees = rotationDegrees
    }
}

enum TaptionVideoEditOperation: String, Codable, Equatable, CaseIterable {
    case trim
    case cut
    case split
    case shorten
    case reorder
    case canvasPosition
}

struct TaptionVideoSlice: Identifiable, Codable, Equatable {
    var id: UUID
    var sourceRange: TaptionTimeRange
    var timelineStart: TimeInterval
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        sourceRange: TaptionTimeRange,
        timelineStart: TimeInterval,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.sourceRange = sourceRange
        self.timelineStart = max(0, timelineStart)
        self.isEnabled = isEnabled
    }

    var timelineRange: TaptionTimeRange {
        TaptionTimeRange(start: timelineStart, duration: sourceRange.duration)
    }
}

struct TaptionTouchWidgetAnchor: Codable, Equatable {
    var segmentID: UUID
    var normalizedX: Double
    var normalizedY: Double
    var role: String

    init(
        segmentID: UUID,
        normalizedX: Double,
        normalizedY: Double,
        role: String
    ) {
        self.segmentID = segmentID
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.role = role
    }
}

struct TaptionVideoSegment: Identifiable, Codable, Equatable {
    var id: UUID
    var assetID: UUID
    var displayName: String
    var slices: [TaptionVideoSlice]
    var placement: TaptionCanvasPlacement
    var editOperations: [TaptionVideoEditOperation]

    init(
        id: UUID = UUID(),
        assetID: UUID,
        displayName: String,
        slices: [TaptionVideoSlice],
        placement: TaptionCanvasPlacement = TaptionCanvasPlacement(),
        editOperations: [TaptionVideoEditOperation] = []
    ) {
        self.id = id
        self.assetID = assetID
        self.displayName = displayName
        self.slices = slices
        self.placement = placement
        self.editOperations = editOperations
    }

    var duration: TimeInterval {
        slices
            .filter(\.isEnabled)
            .map { $0.sourceRange.duration }
            .reduce(0, +)
    }
}

enum TaptionMergeNormalizationDecision: String, Codable, Equatable, CaseIterable {
    case appSuggestedNearestValue
    case userSelectedExplicitValue
    case keepSourceWhenCompatible
}

struct TaptionMergeNormalizationPlan: Codable, Equatable {
    var targetSize: TaptionPixelSize?
    var frameRate: TaptionRationalFrameRate?
    var color: TaptionColorDescription?
    var audioSampleRate: Double?
    var decision: TaptionMergeNormalizationDecision

    init(
        targetSize: TaptionPixelSize? = nil,
        frameRate: TaptionRationalFrameRate? = nil,
        color: TaptionColorDescription? = nil,
        audioSampleRate: Double? = nil,
        decision: TaptionMergeNormalizationDecision = .appSuggestedNearestValue
    ) {
        self.targetSize = targetSize
        self.frameRate = frameRate
        self.color = color
        self.audioSampleRate = audioSampleRate
        self.decision = decision
    }
}

struct TaptionVideoTimeline: Codable, Equatable {
    var canvasSize: TaptionPixelSize?
    var segments: [TaptionVideoSegment]
    var touchWidgetAnchors: [TaptionTouchWidgetAnchor]
    var normalizationPlan: TaptionMergeNormalizationPlan

    init(
        canvasSize: TaptionPixelSize? = nil,
        segments: [TaptionVideoSegment] = [],
        touchWidgetAnchors: [TaptionTouchWidgetAnchor] = [],
        normalizationPlan: TaptionMergeNormalizationPlan = TaptionMergeNormalizationPlan()
    ) {
        self.canvasSize = canvasSize
        self.segments = segments
        self.touchWidgetAnchors = touchWidgetAnchors
        self.normalizationPlan = normalizationPlan
    }

    var duration: TimeInterval {
        segments
            .flatMap(\.slices)
            .filter(\.isEnabled)
            .map(\.timelineRange.end)
            .max() ?? 0
    }
}

struct TaptionVideoProject: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var fcpxmlPolicy: TaptionFCPXMLPolicy
    var assets: [TaptionVideoAsset]
    var timeline: TaptionVideoTimeline

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        fcpxmlPolicy: TaptionFCPXMLPolicy = TaptionFCPXMLPolicy(),
        assets: [TaptionVideoAsset] = [],
        timeline: TaptionVideoTimeline = TaptionVideoTimeline()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fcpxmlPolicy = fcpxmlPolicy
        self.assets = assets
        self.timeline = timeline
    }
}
