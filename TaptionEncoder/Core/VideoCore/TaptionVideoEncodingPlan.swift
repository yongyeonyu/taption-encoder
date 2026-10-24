import Foundation

enum TaptionEncodingInputKind: String, Codable, Equatable {
    case singleAsset
    case timelineProject
}

enum TaptionSaveDestinationKind: String, Codable, Equatable {
    case sourceFolder
    case photosLibrary
    case temporaryOnly
}

enum TaptionSaveGate: String, Codable, Equatable {
    case none
    case rewardedAdBeforeFinalSave
}

enum TaptionEncodingStage: String, Codable, Equatable {
    case queued
    case inspecting
    case preparing
    case encoding
    case waitingForSaveGate
    case saving
    case completed
    case cancelled
    case failed
}

enum TaptionEncodingOptimizationProfile: String, Codable, Equatable, CaseIterable {
    case batterySaver
    case balanced
    case performance

    var menuTitle: String {
        switch self {
        case .batterySaver:
            return "Battery Saver"
        case .balanced:
            return "Balanced"
        case .performance:
            return "Max Performance"
        }
    }

    var detailText: String {
        switch self {
        case .batterySaver:
            return "Caps automatic source output at 1080p and 30 fps, lowers bitrate, and samples device usage less often."
        case .balanced:
            return "Preserves source resolution, frame rate, and the normal automatic bitrate target."
        case .performance:
            return "Prioritizes the fastest path, raises the automatic bitrate budget, overlaps decode and encode work, and samples usage more often."
        }
    }

    var sliderValue: Double {
        switch self {
        case .batterySaver:
            return 0
        case .balanced:
            return 1
        case .performance:
            return 2
        }
    }

    var bitrateMultiplier: Double {
        switch self {
        case .batterySaver:
            return 0.70
        case .balanced:
            return 1.0
        case .performance:
            return 1.35
        }
    }

    var maximumAutomaticResolution: TaptionPixelSize? {
        switch self {
        case .batterySaver:
            return TaptionPixelSize(width: 1920, height: 1080)
        case .balanced, .performance:
            return nil
        }
    }

    var maximumFrameRate: TaptionRationalFrameRate? {
        switch self {
        case .batterySaver:
            return TaptionRationalFrameRate(numerator: 30)
        case .balanced, .performance:
            return nil
        }
    }

    var resourceSampleIntervalNanoseconds: UInt64 {
        switch self {
        case .batterySaver:
            return 2_000_000_000
        case .balanced:
            return 1_000_000_000
        case .performance:
            return 500_000_000
        }
    }

    var softwareDecodePollingIntervalNanoseconds: UInt64 {
        switch self {
        case .batterySaver:
            return 50_000_000
        case .balanced:
            return 25_000_000
        case .performance:
            return 10_000_000
        }
    }

    var softwareFramePipelineDepth: Int {
        switch self {
        case .batterySaver:
            return 1
        case .balanced:
            return 3
        case .performance:
            return 6
        }
    }

    var softwareAudioPipelineDepth: Int {
        switch self {
        case .batterySaver, .balanced:
            return 8
        case .performance:
            return 12
        }
    }

    var softwareVideoOnlyDecoderPlaybackRate: Float {
        switch self {
        case .batterySaver:
            return 1
        case .balanced:
            return 2
        case .performance:
            return 4
        }
    }

    var writerBackpressureSleepMicroseconds: UInt32 {
        switch self {
        case .batterySaver:
            return 2_000
        case .balanced:
            return 1_000
        case .performance:
            return 250
        }
    }

    static func fromSliderValue(_ value: Double) -> TaptionEncodingOptimizationProfile {
        switch Int(value.rounded()) {
        case ...0:
            return .batterySaver
        case 1:
            return .balanced
        default:
            return .performance
        }
    }

    static func fromDebugString(_ value: String) -> TaptionEncodingOptimizationProfile? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch normalized {
        case "battery", "batterysaver", "savebattery", "lowpower":
            return .batterySaver
        case "balanced", "balance", "default":
            return .balanced
        case "performance", "maxperformance", "maximumperformance", "max", "fast", "fastest":
            return .performance
        default:
            return nil
        }
    }
}

/// How a picture that does not have the output frame's shape is placed in that frame.
///
/// A standard preset (1080p, 720p, 4K ...) is a fixed frame, so a source with a different shape has to be
/// placed in it. Which of the three placements is right is the user's call, not the encoder's guess.
enum TaptionVideoScaleMode: String, Codable, Equatable, CaseIterable {
    /// Whole picture, black bars where the shapes differ (letterbox / pillarbox).
    case fit
    /// Frame filled edge to edge, the overflow is cropped away.
    case fill
    /// Picture stretched to the frame; the shape changes.
    case stretch

    var menuTitle: String {
        switch self {
        case .fit:
            return "Fit"
        case .fill:
            return "Fill"
        case .stretch:
            return "Stretch"
        }
    }

    var detailText: String {
        switch self {
        case .fit:
            return "Keeps the whole picture and adds black bars where the shapes differ."
        case .fill:
            return "Fills the frame and crops the parts that overflow."
        case .stretch:
            return "Stretches the picture to the frame. The shape changes."
        }
    }

    static let `default` = TaptionVideoScaleMode.fit
}

struct TaptionAdvancedOutputOptions: Codable, Equatable {
    var resizeTo: TaptionPixelSize?
    var frameRate: TaptionRationalFrameRate?
    var targetBitrate: Int?
    var color: TaptionColorDescription?
    var rotationDegrees: Int?
    var optimizationProfile: TaptionEncodingOptimizationProfile?
    /// Only meaningful together with `resizeTo`. `nil` behaves like `.fit`.
    var scaleMode: TaptionVideoScaleMode?

    init(
        resizeTo: TaptionPixelSize? = nil,
        frameRate: TaptionRationalFrameRate? = nil,
        targetBitrate: Int? = nil,
        color: TaptionColorDescription? = nil,
        rotationDegrees: Int? = nil,
        optimizationProfile: TaptionEncodingOptimizationProfile? = nil,
        scaleMode: TaptionVideoScaleMode? = nil
    ) {
        self.resizeTo = resizeTo
        self.frameRate = frameRate
        self.targetBitrate = targetBitrate
        self.color = color
        self.rotationDegrees = rotationDegrees
        self.optimizationProfile = optimizationProfile
        self.scaleMode = scaleMode
    }

    static let preserveSource = TaptionAdvancedOutputOptions()

    var resolvedScaleMode: TaptionVideoScaleMode {
        scaleMode ?? .default
    }
}

struct TaptionVideoOutputPolicy: Codable, Equatable {
    var videoCodec: TaptionVideoCodec
    var audioCodec: TaptionAudioCodec
    var container: TaptionVideoContainer
    var profile: TaptionHEVCProfile
    var qualityPolicy: TaptionQualityPolicy
    var advancedOptions: TaptionAdvancedOutputOptions

    init(
        videoCodec: TaptionVideoCodec = .hevc,
        audioCodec: TaptionAudioCodec = TaptionAudioCodecRoutePlanner.defaultOutputCodec,
        container: TaptionVideoContainer = .mp4,
        profile: TaptionHEVCProfile = .automatic,
        qualityPolicy: TaptionQualityPolicy = .preserveSourceVisuals,
        advancedOptions: TaptionAdvancedOutputOptions = .preserveSource
    ) {
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.container = container
        self.profile = profile
        self.qualityPolicy = qualityPolicy
        self.advancedOptions = advancedOptions
    }
}

typealias TaptionHEVCOutputPolicy = TaptionVideoOutputPolicy

struct TaptionSourcePreservationRequirements: Codable, Equatable {
    var displaySize: TaptionPixelSize?
    var frameRate: TaptionRationalFrameRate?
    var targetBitrate: Int?
    var color: TaptionColorDescription?
    var rotationDegrees: Int?
    var duration: TimeInterval?
    var expectsAudio: Bool
    var audioSampleRate: Double?
    var audioChannelCount: Int?

    init(
        displaySize: TaptionPixelSize? = nil,
        frameRate: TaptionRationalFrameRate? = nil,
        targetBitrate: Int? = nil,
        color: TaptionColorDescription? = nil,
        rotationDegrees: Int? = nil,
        duration: TimeInterval? = nil,
        expectsAudio: Bool = false,
        audioSampleRate: Double? = nil,
        audioChannelCount: Int? = nil
    ) {
        self.displaySize = displaySize
        self.frameRate = frameRate
        self.targetBitrate = targetBitrate
        self.color = color
        self.rotationDegrees = rotationDegrees
        self.duration = duration
        self.expectsAudio = expectsAudio
        self.audioSampleRate = audioSampleRate
        self.audioChannelCount = audioChannelCount
    }

    init(videoTrack: TaptionVideoTrackInfo) {
        self.init(
            displaySize: videoTrack.displaySize,
            frameRate: videoTrack.nominalFrameRate,
            targetBitrate: videoTrack.estimatedBitrate,
            color: videoTrack.color,
            rotationDegrees: videoTrack.rotationDegrees
        )
    }

    init(asset: TaptionVideoAsset, audioPlan: TaptionAudioTranscodePlan? = nil) {
        self.init(
            displaySize: asset.videoTrack?.displaySize,
            frameRate: asset.videoTrack?.nominalFrameRate,
            targetBitrate: asset.videoTrack?.estimatedBitrate,
            color: asset.videoTrack?.color,
            rotationDegrees: asset.videoTrack?.rotationDegrees,
            duration: asset.duration,
            expectsAudio: !asset.audioTracks.isEmpty,
            audioSampleRate: audioPlan?.options.sampleRate ?? asset.audioTracks.first?.sampleRate,
            audioChannelCount: audioPlan?.options.channelCount ?? asset.audioTracks.first?.channelCount
        )
    }

    func missingFields(in outputPolicy: TaptionVideoOutputPolicy) -> [String] {
        guard outputPolicy.qualityPolicy == .preserveSourceVisuals else {
            return []
        }

        let options = outputPolicy.advancedOptions
        var missing: [String] = []
        if displaySize != nil, options.resizeTo == nil {
            missing.append("resolution")
        }
        if frameRate != nil, options.frameRate == nil {
            missing.append("frame rate")
        }
        if targetBitrate != nil, options.targetBitrate == nil {
            missing.append("bitrate")
        }
        if color != nil, options.color == nil {
            missing.append("color metadata")
        }
        if rotationDegrees != nil, options.rotationDegrees == nil {
            missing.append("orientation")
        }
        return missing
    }
}

struct TaptionSourcePreservingOutputVerificationReport: Equatable {
    var failures: [String]
    var warnings: [String]
    var metadata: [String: String]

    var isPassing: Bool {
        failures.isEmpty
    }
}

enum TaptionSourcePreservingVerificationError: Error, Equatable {
    case failed(String)
}

extension TaptionSourcePreservingVerificationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

struct TaptionVisualQualitySample: Equatable {
    var width: Int
    var height: Int
    var averageRed: Double
    var averageGreen: Double
    var averageBlue: Double
    var averageLuma: Double
    var lumaStandardDeviation: Double
    var nonBlackRatio: Double

    init(
        width: Int,
        height: Int,
        averageRed: Double,
        averageGreen: Double,
        averageBlue: Double,
        averageLuma: Double,
        lumaStandardDeviation: Double,
        nonBlackRatio: Double
    ) {
        self.width = width
        self.height = height
        self.averageRed = averageRed
        self.averageGreen = averageGreen
        self.averageBlue = averageBlue
        self.averageLuma = averageLuma
        self.lumaStandardDeviation = lumaStandardDeviation
        self.nonBlackRatio = nonBlackRatio
    }
}

struct TaptionSourcePreservingVisualQualityReport: Equatable {
    var failures: [String]
    var warnings: [String]
    var metadata: [String: String]

    var isPassing: Bool {
        failures.isEmpty
    }
}

enum TaptionSourcePreservingVisualQualityComparator {
    static func verify(
        sourceSample: TaptionVisualQualitySample?,
        outputSample: TaptionVisualQualitySample
    ) -> TaptionSourcePreservingVisualQualityReport {
        var failures: [String] = []
        var warnings: [String] = []
        var metadata: [String: String] = [
            "visualQuality": "checked",
            "outputVisualSample": sampleString(outputSample)
        ]

        guard outputSample.width > 0,
              outputSample.height > 0,
              outputSample.averageLuma.isFinite,
              outputSample.lumaStandardDeviation.isFinite else {
            return TaptionSourcePreservingVisualQualityReport(
                failures: ["output visual sample was invalid"],
                warnings: warnings,
                metadata: metadata
            )
        }

        guard let sourceSample else {
            warnings.append("Source visual sample was unavailable; output visual decodability was verified only.")
            metadata["sourceVisualSample"] = "unavailable"
            return TaptionSourcePreservingVisualQualityReport(
                failures: failures,
                warnings: warnings,
                metadata: metadata
            )
        }

        metadata["sourceVisualSample"] = sampleString(sourceSample)

        let sourceHasVisibleContrast = sourceSample.lumaStandardDeviation >= 0.035
        let outputIsFlat = outputSample.lumaStandardDeviation < 0.006
        if sourceHasVisibleContrast,
           outputIsFlat {
            failures.append("visual sample lost source contrast and appears flat")
        }

        let sourceHasVisibleBrightness = sourceSample.averageLuma >= 0.06
        let lumaDelta = abs(sourceSample.averageLuma - outputSample.averageLuma)
        metadata["visualLumaDelta"] = String(format: "%.4f", lumaDelta)
        if sourceHasVisibleBrightness,
           lumaDelta > 0.45 {
            failures.append("visual sample brightness changed too much")
        }

        let colorDelta = (
            abs(sourceSample.averageRed - outputSample.averageRed)
                + abs(sourceSample.averageGreen - outputSample.averageGreen)
                + abs(sourceSample.averageBlue - outputSample.averageBlue)
        ) / 3
        metadata["visualColorDelta"] = String(format: "%.4f", colorDelta)
        if sourceHasVisibleBrightness,
           colorDelta > 0.50 {
            failures.append("visual sample color changed too much")
        }

        if sourceSample.nonBlackRatio > 0.20,
           outputSample.nonBlackRatio < 0.02 {
            failures.append("visual sample collapsed to near-black output")
        }

        return TaptionSourcePreservingVisualQualityReport(
            failures: failures,
            warnings: warnings,
            metadata: metadata
        )
    }

    private static func sampleString(_ sample: TaptionVisualQualitySample) -> String {
        [
            "\(sample.width)x\(sample.height)",
            "rgb:\(String(format: "%.3f", sample.averageRed))/\(String(format: "%.3f", sample.averageGreen))/\(String(format: "%.3f", sample.averageBlue))",
            "luma:\(String(format: "%.3f", sample.averageLuma))",
            "sigma:\(String(format: "%.3f", sample.lumaStandardDeviation))",
            "nonBlack:\(String(format: "%.3f", sample.nonBlackRatio))"
        ].joined(separator: ",")
    }
}

enum TaptionSourcePreservingExecutionAudit {
    static func validate(plan: TaptionEncodingPlan) throws {
        guard let requirements = plan.sourcePreservationRequirements else {
            return
        }
        let missingFields = requirements.missingFields(in: plan.outputPolicy)
        guard missingFields.isEmpty else {
            throw TaptionSourcePreservingVerificationError.failed(
                "Source-preserving output plan is incomplete: \(missingFields.joined(separator: ", "))."
            )
        }
    }

    static func logMetadata(for plan: TaptionEncodingPlan) -> [String: String] {
        guard let requirements = plan.sourcePreservationRequirements else {
            return ["sourcePreserving": "not-tracked"]
        }

        let options = plan.outputPolicy.advancedOptions
        var metadata: [String: String] = [
            "sourcePreserving": "tracked",
            "sourcePreservingMissing": requirements.missingFields(in: plan.outputPolicy).joined(separator: "|")
        ]
        if let displaySize = options.resizeTo {
            metadata["preserveResolution"] = "\(displaySize.width)x\(displaySize.height)"
        }
        if let scaleMode = options.scaleMode {
            metadata["scaleMode"] = scaleMode.rawValue
        }
        if let frameRate = options.frameRate {
            metadata["preserveFrameRate"] = "\(frameRate.numerator)/\(frameRate.denominator)"
        }
        if let targetBitrate = options.targetBitrate {
            metadata["preserveBitrate"] = "\(targetBitrate)"
        }
        if let color = options.color {
            metadata["preserveColor"] = "\(color.primaries.rawValue)/\(color.transfer.rawValue)/\(color.matrix.rawValue)/hdr:\(color.isHDR)"
        }
        if let rotationDegrees = options.rotationDegrees {
            metadata["preserveOrientation"] = "\(rotationDegrees)"
        }
        return metadata
    }

    static func verifyOutput(
        plan: TaptionEncodingPlan,
        outputAsset: TaptionVideoAsset
    ) throws -> TaptionSourcePreservingOutputVerificationReport {
        guard let requirements = plan.sourcePreservationRequirements else {
            return TaptionSourcePreservingOutputVerificationReport(
                failures: [],
                warnings: ["Source preservation requirements were not tracked for this plan."],
                metadata: ["sourcePreservingOutput": "not-tracked"]
            )
        }

        // The plan asks for a specific output. When the user changed the resolution, the frame rate or the
        // colour, the *plan* is the expected result and the source is only the fallback. Comparing the output
        // against the untouched source made every intentional change look like an encoder failure.
        let options = plan.outputPolicy.advancedOptions
        let expectedSize = options.resizeTo ?? requirements.displaySize
        let expectedFrameRate = options.frameRate ?? requirements.frameRate
        let expectedColor = options.color ?? requirements.color
        let expectedRotation = options.rotationDegrees ?? requirements.rotationDegrees

        var failures: [String] = []
        var warnings: [String] = []
        var metadata: [String: String] = [
            "sourcePreservingOutput": "checked"
        ]

        guard let outputTrack = outputAsset.videoTrack else {
            throw TaptionSourcePreservingVerificationError.failed("Source-preserving output verification failed: missing output video track.")
        }

        if let expectedSize {
            metadata["expectedResolution"] = "\(expectedSize.width)x\(expectedSize.height)"
            metadata["actualResolution"] = "\(outputTrack.displaySize.width)x\(outputTrack.displaySize.height)"
            if !sizesMatch(expectedSize, outputTrack.displaySize) {
                failures.append("resolution expected \(expectedSize.width)x\(expectedSize.height) but got \(outputTrack.displaySize.width)x\(outputTrack.displaySize.height)")
            }
        }

        if let expectedFrameRate {
            metadata["expectedFrameRate"] = frameRateString(expectedFrameRate)
            if let actualFrameRate = outputTrack.nominalFrameRate {
                metadata["actualFrameRate"] = frameRateString(actualFrameRate)
                if !frameRatesMatch(expectedFrameRate, actualFrameRate) {
                    failures.append("frame rate expected \(frameRateString(expectedFrameRate)) but got \(frameRateString(actualFrameRate))")
                }
            } else {
                failures.append("frame rate metadata was missing from the output")
            }
        }

        if let expectedColor {
            metadata["expectedColor"] = colorString(expectedColor)
            metadata["actualColor"] = colorString(outputTrack.color)
            failures += colorFailures(expected: expectedColor, actual: outputTrack.color)
        }

        if let expectedRotation {
            metadata["expectedOrientation"] = "\(expectedRotation)"
            metadata["actualOrientation"] = "\(outputTrack.rotationDegrees)"
            let normalizedOrientationPreserved = expectedRotation != 0
                && expectedSize.map { sizesMatch($0, outputTrack.displaySize) } == true
            if outputTrack.rotationDegrees != expectedRotation,
               !normalizedOrientationPreserved {
                failures.append("orientation expected \(expectedRotation) degrees but got \(outputTrack.rotationDegrees) degrees")
            }
        }

        if let expectedDuration = requirements.duration,
           expectedDuration.isFinite,
           expectedDuration > 0 {
            metadata["expectedDuration"] = String(format: "%.3f", expectedDuration)
            if let actualDuration = outputAsset.duration,
               actualDuration.isFinite,
               actualDuration > 0 {
                metadata["actualDuration"] = String(format: "%.3f", actualDuration)
                if abs(actualDuration - expectedDuration) > durationTolerance(for: expectedDuration) {
                    failures.append("duration expected \(String(format: "%.3f", expectedDuration))s but got \(String(format: "%.3f", actualDuration))s")
                }
            } else {
                failures.append("duration metadata was missing from the output")
            }
        }

        metadata["expectedAudio"] = requirements.expectsAudio ? "yes" : "no"
        metadata["actualAudioTracks"] = "\(outputAsset.audioTracks.count)"
        if requirements.expectsAudio {
            guard let firstAudioTrack = outputAsset.audioTracks.first else {
                failures.append("audio track was missing from the output")
                let report = TaptionSourcePreservingOutputVerificationReport(
                    failures: failures,
                    warnings: warnings,
                    metadata: metadata
                )
                try throwIfNeeded(report)
                return report
            }

            if let expectedSampleRate = requirements.audioSampleRate,
               let actualSampleRate = firstAudioTrack.sampleRate {
                metadata["expectedAudioSampleRate"] = "\(Int(expectedSampleRate.rounded()))"
                metadata["actualAudioSampleRate"] = "\(Int(actualSampleRate.rounded()))"
                if abs(actualSampleRate - expectedSampleRate) > 1 {
                    failures.append("audio sample rate expected \(Int(expectedSampleRate)) Hz but got \(Int(actualSampleRate)) Hz")
                }
            }
            if let expectedChannelCount = requirements.audioChannelCount,
               let actualChannelCount = firstAudioTrack.channelCount {
                metadata["expectedAudioChannels"] = "\(expectedChannelCount)"
                metadata["actualAudioChannels"] = "\(actualChannelCount)"
                if actualChannelCount != expectedChannelCount {
                    failures.append("audio channels expected \(expectedChannelCount) but got \(actualChannelCount)")
                }
            }
        } else if !outputAsset.audioTracks.isEmpty {
            warnings.append("Output contains audio even though the source plan did not expect audio.")
        }

        warnings.append("Visual quality is not bit-for-bit lossless; use fixture or device playback proof for perceptual quality.")

        let report = TaptionSourcePreservingOutputVerificationReport(
            failures: failures,
            warnings: warnings,
            metadata: metadata
        )
        try throwIfNeeded(report)
        return report
    }

    private static func throwIfNeeded(_ report: TaptionSourcePreservingOutputVerificationReport) throws {
        guard report.isPassing else {
            throw TaptionSourcePreservingVerificationError.failed(
                "Source-preserving output verification failed: \(report.failures.joined(separator: "; "))."
            )
        }
    }

    private static func sizesMatch(_ expected: TaptionPixelSize, _ actual: TaptionPixelSize) -> Bool {
        abs(expected.width - actual.width) <= 1
            && abs(expected.height - actual.height) <= 1
    }

    private static func frameRatesMatch(
        _ expected: TaptionRationalFrameRate,
        _ actual: TaptionRationalFrameRate
    ) -> Bool {
        let expectedValue = expected.value
        let actualValue = actual.value
        guard expectedValue.isFinite,
              actualValue.isFinite,
              expectedValue > 0,
              actualValue > 0 else {
            return false
        }
        return abs(expectedValue - actualValue) <= max(0.1, expectedValue * 0.0025)
    }

    private static func durationTolerance(for duration: TimeInterval) -> TimeInterval {
        max(0.5, duration * 0.02)
    }

    private static func colorFailures(
        expected: TaptionColorDescription,
        actual: TaptionColorDescription
    ) -> [String] {
        var failures: [String] = []
        if expected.isHDR != actual.isHDR {
            failures.append("HDR/SDR expected \(expected.isHDR ? "HDR" : "SDR") but got \(actual.isHDR ? "HDR" : "SDR")")
        }
        if expected.primaries != .unknown,
           actual.primaries != expected.primaries {
            failures.append("color primaries expected \(expected.primaries.rawValue) but got \(actual.primaries.rawValue)")
        }
        if expected.transfer != .unknown,
           actual.transfer != expected.transfer {
            failures.append("color transfer expected \(expected.transfer.rawValue) but got \(actual.transfer.rawValue)")
        }
        if expected.matrix != .unknown,
           actual.matrix != expected.matrix {
            failures.append("color matrix expected \(expected.matrix.rawValue) but got \(actual.matrix.rawValue)")
        }
        if let expectedBitDepth = expected.bitDepth,
           let actualBitDepth = actual.bitDepth,
           expectedBitDepth != actualBitDepth {
            failures.append("bit depth expected \(expectedBitDepth) but got \(actualBitDepth)")
        }
        return failures
    }

    private static func frameRateString(_ frameRate: TaptionRationalFrameRate) -> String {
        "\(frameRate.numerator)/\(frameRate.denominator)"
    }

    private static func colorString(_ color: TaptionColorDescription) -> String {
        "\(color.primaries.rawValue)/\(color.transfer.rawValue)/\(color.matrix.rawValue)/hdr:\(color.isHDR)"
    }
}

enum TaptionSourcePreservingOutputPolicyResolver {
    static func resolvedPolicy(
        for asset: TaptionVideoAsset,
        requestedPolicy: TaptionVideoOutputPolicy
    ) -> TaptionVideoOutputPolicy {
        guard requestedPolicy.qualityPolicy == .preserveSourceVisuals,
              let videoTrack = asset.videoTrack else {
            return requestedPolicy
        }

        var resolvedPolicy = requestedPolicy
        resolvedPolicy.advancedOptions = resolvedOptions(
            for: videoTrack,
            requestedOptions: requestedPolicy.advancedOptions
        )
        return resolvedPolicy
    }

    static func resolvedOptions(
        for videoTrack: TaptionVideoTrackInfo,
        requestedOptions: TaptionAdvancedOutputOptions
    ) -> TaptionAdvancedOutputOptions {
        TaptionAdvancedOutputOptions(
            resizeTo: requestedOptions.resizeTo ?? videoTrack.displaySize,
            frameRate: requestedOptions.frameRate ?? videoTrack.nominalFrameRate,
            targetBitrate: requestedOptions.targetBitrate ?? videoTrack.estimatedBitrate,
            color: requestedOptions.color ?? videoTrack.color,
            rotationDegrees: requestedOptions.rotationDegrees ?? videoTrack.rotationDegrees,
            optimizationProfile: requestedOptions.optimizationProfile,
            scaleMode: requestedOptions.scaleMode
        )
    }
}

struct TaptionOutputNamingPolicy: Codable, Equatable {
    var suffix: String
    var replacesExistingExtension: Bool

    init(suffix: String = "_taption", replacesExistingExtension: Bool = true) {
        self.suffix = suffix
        self.replacesExistingExtension = replacesExistingExtension
    }

    func outputURL(for sourceURL: URL, container: TaptionVideoContainer) -> URL {
        let directoryURL = sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent + suffix
        return directoryURL
            .appendingPathComponent(baseName)
            .appendingPathExtension(container.defaultFileExtension)
    }
}

struct TaptionSavePolicy: Codable, Equatable {
    var destination: TaptionSaveDestinationKind
    var saveGate: TaptionSaveGate
    var namingPolicy: TaptionOutputNamingPolicy
    var shouldRestorePendingSaveOnLaunch: Bool

    init(
        destination: TaptionSaveDestinationKind = .sourceFolder,
        saveGate: TaptionSaveGate = .none,
        namingPolicy: TaptionOutputNamingPolicy = TaptionOutputNamingPolicy(),
        shouldRestorePendingSaveOnLaunch: Bool = true
    ) {
        self.destination = destination
        self.saveGate = saveGate
        self.namingPolicy = namingPolicy
        self.shouldRestorePendingSaveOnLaunch = shouldRestorePendingSaveOnLaunch
    }
}

struct TaptionEncoderSelection: Codable, Equatable {
    var requestedMode: TaptionEncoderMode
    var backend: TaptionEncodingBackend?
    var reason: String

    init(
        requestedMode: TaptionEncoderMode = .automatic,
        backend: TaptionEncodingBackend? = nil,
        reason: String = "The app chooses hardware first and falls back automatically."
    ) {
        self.requestedMode = requestedMode
        self.backend = backend
        self.reason = reason
    }
}

struct TaptionEncodingInput: Codable, Equatable {
    var kind: TaptionEncodingInputKind
    var assetID: UUID?
    var projectID: UUID?

    init(kind: TaptionEncodingInputKind, assetID: UUID? = nil, projectID: UUID? = nil) {
        self.kind = kind
        self.assetID = assetID
        self.projectID = projectID
    }
}

struct TaptionEncodingPlan: Identifiable, Codable, Equatable {
    var id: UUID
    var input: TaptionEncodingInput
    var outputPolicy: TaptionVideoOutputPolicy
    var codecRoute: TaptionCodecRoute?
    var codecExecutionKind: TaptionCodecRouteExecutionKind?
    var videoCommandPlan: SW_FFmpegCommandPlan?
    var audioPlan: TaptionAudioTranscodePlan?
    var sourcePreservationRequirements: TaptionSourcePreservationRequirements?
    var savePolicy: TaptionSavePolicy
    var encoderSelection: TaptionEncoderSelection
    var estimatedOutputBytes: Int64?
    var sourceURL: URL?
    var temporaryOutputURL: URL?
    var finalOutputURL: URL?

    init(
        id: UUID = UUID(),
        input: TaptionEncodingInput,
        outputPolicy: TaptionVideoOutputPolicy = TaptionVideoOutputPolicy(),
        codecRoute: TaptionCodecRoute? = nil,
        codecExecutionKind: TaptionCodecRouteExecutionKind? = nil,
        videoCommandPlan: SW_FFmpegCommandPlan? = nil,
        audioPlan: TaptionAudioTranscodePlan? = nil,
        sourcePreservationRequirements: TaptionSourcePreservationRequirements? = nil,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy(),
        encoderSelection: TaptionEncoderSelection = TaptionEncoderSelection(),
        estimatedOutputBytes: Int64? = nil,
        sourceURL: URL? = nil,
        temporaryOutputURL: URL? = nil,
        finalOutputURL: URL? = nil
    ) {
        self.id = id
        self.input = input
        self.outputPolicy = outputPolicy
        self.codecRoute = codecRoute
        self.codecExecutionKind = codecExecutionKind
        self.videoCommandPlan = videoCommandPlan
        self.audioPlan = audioPlan
        self.sourcePreservationRequirements = sourcePreservationRequirements
        self.savePolicy = savePolicy
        self.encoderSelection = encoderSelection
        self.estimatedOutputBytes = estimatedOutputBytes
        self.sourceURL = sourceURL
        self.temporaryOutputURL = temporaryOutputURL
        self.finalOutputURL = finalOutputURL
    }
}

struct TaptionPendingSaveState: Identifiable, Codable, Equatable {
    var id: UUID
    var planID: UUID
    var temporaryOutputURL: URL
    var finalOutputURL: URL?
    var saveDestination: TaptionSaveDestinationKind
    var requiresRewardedAd: Bool
    var createdAt: Date
    var accessBookmarkData: Data?
    var rewardedAdCompletedAt: Date?
    var saveDestinationWasChosen: Bool?

    init(
        id: UUID = UUID(),
        planID: UUID,
        temporaryOutputURL: URL,
        finalOutputURL: URL? = nil,
        saveDestination: TaptionSaveDestinationKind,
        requiresRewardedAd: Bool,
        createdAt: Date = Date(),
        accessBookmarkData: Data? = nil,
        rewardedAdCompletedAt: Date? = nil,
        saveDestinationWasChosen: Bool? = nil
    ) {
        self.id = id
        self.planID = planID
        self.temporaryOutputURL = temporaryOutputURL
        self.finalOutputURL = finalOutputURL
        self.saveDestination = saveDestination
        self.requiresRewardedAd = requiresRewardedAd
        self.createdAt = createdAt
        self.accessBookmarkData = accessBookmarkData
        self.rewardedAdCompletedAt = rewardedAdCompletedAt
        self.saveDestinationWasChosen = saveDestinationWasChosen
    }
}

struct TaptionEncodingProgress: Codable, Equatable {
    var stage: TaptionEncodingStage
    var fractionCompleted: Double
    var elapsedTime: TimeInterval
    var estimatedRemainingTime: TimeInterval?
    var currentFrame: Int64?
    var totalFrames: Int64?

    init(
        stage: TaptionEncodingStage,
        fractionCompleted: Double,
        elapsedTime: TimeInterval = 0,
        estimatedRemainingTime: TimeInterval? = nil,
        currentFrame: Int64? = nil,
        totalFrames: Int64? = nil
    ) {
        self.stage = stage
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.elapsedTime = max(0, elapsedTime)
        self.estimatedRemainingTime = estimatedRemainingTime
        self.currentFrame = currentFrame
        self.totalFrames = totalFrames
    }
}

struct EncodingProgressCoalescer {
    var minimumFractionDelta: Double
    var minimumTimeInterval: TimeInterval

    private(set) var lastEmittedProgress: TaptionEncodingProgress?
    private var lastEmissionUptime: TimeInterval?

    init(
        minimumFractionDelta: Double = 0.01,
        minimumTimeInterval: TimeInterval = 0.5
    ) {
        self.minimumFractionDelta = max(minimumFractionDelta, 0)
        self.minimumTimeInterval = max(minimumTimeInterval, 0)
    }

    mutating func shouldEmit(
        _ progress: TaptionEncodingProgress,
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        let shouldRecord = shouldRecord(progress, now: now)
        if shouldRecord {
            lastEmittedProgress = progress
            lastEmissionUptime = now
        }
        return shouldRecord
    }

    private func shouldRecord(
        _ progress: TaptionEncodingProgress,
        now: TimeInterval
    ) -> Bool {
        guard let lastEmittedProgress else {
            return true
        }
        if progress.stage != lastEmittedProgress.stage {
            return true
        }
        if progress.fractionCompleted >= 1,
           lastEmittedProgress.fractionCompleted < 1 {
            return true
        }
        if progress.fractionCompleted - lastEmittedProgress.fractionCompleted >= minimumFractionDelta {
            return true
        }
        guard let lastEmissionUptime else {
            return true
        }
        return now - lastEmissionUptime >= minimumTimeInterval
            && progress.fractionCompleted > lastEmittedProgress.fractionCompleted
    }
}

struct EncodingProgressEmitterStats: Equatable {
    var observedCount: Int
    var emittedCount: Int
}

final class EncodingProgressEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private var coalescer: EncodingProgressCoalescer
    private let progress: (TaptionEncodingProgress) -> Void
    private var observedCount = 0
    private var emittedCount = 0

    init(
        coalescer: EncodingProgressCoalescer = EncodingProgressCoalescer(),
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) {
        self.coalescer = coalescer
        self.progress = progress
    }

    func submit(_ snapshot: TaptionEncodingProgress, force: Bool = false) {
        var shouldEmit = force
        lock.lock()
        observedCount += 1
        if !shouldEmit {
            shouldEmit = coalescer.shouldEmit(snapshot)
        } else {
            _ = coalescer.shouldEmit(snapshot)
        }
        if shouldEmit {
            emittedCount += 1
        }
        lock.unlock()

        guard shouldEmit else {
            return
        }
        progress(snapshot)
    }

    var stats: EncodingProgressEmitterStats {
        lock.lock()
        defer { lock.unlock() }
        return EncodingProgressEmitterStats(
            observedCount: observedCount,
            emittedCount: emittedCount
        )
    }
}

struct TaptionStorageRequirement: Codable, Equatable {
    var estimatedOutputBytes: Int64
    var requiredWorkingBytes: Int64
    var availableBytes: Int64?

    init(
        estimatedOutputBytes: Int64,
        requiredWorkingBytes: Int64,
        availableBytes: Int64? = nil
    ) {
        self.estimatedOutputBytes = estimatedOutputBytes
        self.requiredWorkingBytes = requiredWorkingBytes
        self.availableBytes = availableBytes
    }

    var hasEnoughSpace: Bool {
        guard let availableBytes else {
            return true
        }
        return availableBytes >= requiredWorkingBytes
    }
}

struct TaptionEncodingResult: Codable, Equatable {
    var planID: UUID
    var temporaryOutputURL: URL
    var finalOutputURL: URL?
    var usedBackend: TaptionEncodingBackend
    var usedMode: TaptionEncoderMode
    var pendingSaveState: TaptionPendingSaveState?
    /// True when the compressed samples were copied instead of re-encoded, so the picture is bit-identical.
    var usedLosslessCopy: Bool?

    init(
        planID: UUID,
        temporaryOutputURL: URL,
        finalOutputURL: URL? = nil,
        usedBackend: TaptionEncodingBackend,
        usedMode: TaptionEncoderMode,
        pendingSaveState: TaptionPendingSaveState? = nil,
        usedLosslessCopy: Bool? = nil
    ) {
        self.planID = planID
        self.temporaryOutputURL = temporaryOutputURL
        self.finalOutputURL = finalOutputURL
        self.usedBackend = usedBackend
        self.usedMode = usedMode
        self.pendingSaveState = pendingSaveState
        self.usedLosslessCopy = usedLosslessCopy
    }
}

enum TaptionEncodingPlanner {
    static func makeSingleAssetHEVCPlan(
        asset: TaptionVideoAsset,
        sourceURL: URL,
        temporaryOutputURL: URL,
        preferredMode: TaptionEncoderMode = .automatic,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy()
    ) -> TaptionEncodingPlan {
        let outputPolicy = TaptionVideoOutputPolicy(
            videoCodec: .hevc,
            container: .mp4,
            profile: .automatic,
            qualityPolicy: .preserveSourceVisuals,
            advancedOptions: .preserveSource
        )
        return makeSingleAssetPlan(
            asset: asset,
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryOutputURL,
            outputPolicy: outputPolicy,
            preferredMode: preferredMode,
            savePolicy: savePolicy
        )
    }

    static func makeSingleAssetPlan(
        asset: TaptionVideoAsset,
        sourceURL: URL,
        temporaryOutputURL: URL,
        outputPolicy: TaptionVideoOutputPolicy,
        preferredMode: TaptionEncoderMode = .automatic,
        savePolicy: TaptionSavePolicy = TaptionSavePolicy()
    ) -> TaptionEncodingPlan {
        let resolvedOutputPolicy = TaptionSourcePreservingOutputPolicyResolver.resolvedPolicy(
            for: asset,
            requestedPolicy: outputPolicy
        )
        let finalURL = savePolicy.namingPolicy.outputURL(
            for: sourceURL,
            container: resolvedOutputPolicy.container
        )
        let routeSelection = TaptionCodecRoutePlanner.selectRoute(
            for: asset,
            outputCodec: resolvedOutputPolicy.videoCodec,
            requestedMode: preferredMode
        )
        let audioPlan = TaptionAudioTranscodePlanner.makeFirstTrackPlan(
            asset: asset,
            sourceURL: sourceURL,
            outputURL: temporaryOutputURL,
            outputCodec: resolvedOutputPolicy.audioCodec,
            outputContainer: resolvedOutputPolicy.container
        )
        let videoCommandPlan = makeVideoCommandPlanIfAvailable(
            sourceURL: sourceURL,
            outputURL: temporaryOutputURL,
            routeSelection: routeSelection,
            outputPolicy: resolvedOutputPolicy,
            audioPlan: audioPlan
        )
        let sourcePreservationRequirements = asset.videoTrack == nil
            ? nil
            : TaptionSourcePreservationRequirements(asset: asset, audioPlan: audioPlan)
        return TaptionEncodingPlan(
            input: TaptionEncodingInput(kind: .singleAsset, assetID: asset.id),
            outputPolicy: resolvedOutputPolicy,
            codecRoute: routeSelection.route,
            codecExecutionKind: routeSelection.executionKind,
            videoCommandPlan: videoCommandPlan,
            audioPlan: audioPlan,
            sourcePreservationRequirements: sourcePreservationRequirements,
            savePolicy: savePolicy,
            encoderSelection: routeSelection.encoderSelection,
            estimatedOutputBytes: estimatedOutputBytes(
                asset: asset,
                outputPolicy: resolvedOutputPolicy
            ),
            sourceURL: sourceURL,
            temporaryOutputURL: temporaryOutputURL,
            finalOutputURL: finalURL
        )
    }

    private static func estimatedOutputBytes(
        asset: TaptionVideoAsset,
        outputPolicy: TaptionVideoOutputPolicy
    ) -> Int64? {
        guard let duration = asset.duration,
              duration.isFinite,
              duration > 0 else {
            return asset.fingerprint.fileSize
        }

        let videoBitrate = outputPolicy.advancedOptions.targetBitrate
            ?? asset.videoTrack?.estimatedBitrate
            ?? 4_000_000
        let audioBitrate = estimatedAudioBitrate(for: asset)
        let estimatedBytes = ((Double(videoBitrate + audioBitrate) * duration) / 8.0).rounded()
        guard estimatedBytes.isFinite, estimatedBytes > 0 else {
            return asset.fingerprint.fileSize
        }
        return Int64(max(estimatedBytes, 1_000_000))
    }

    private static func estimatedAudioBitrate(for asset: TaptionVideoAsset) -> Int {
        let measuredBitrate = asset.audioTracks
            .compactMap(\.estimatedBitrate)
            .reduce(0, +)
        if measuredBitrate > 0 {
            return measuredBitrate
        }
        return asset.audioTracks.isEmpty ? 0 : min(max(asset.audioTracks.count * 160_000, 96_000), 512_000)
    }

    private static func makeVideoCommandPlanIfAvailable(
        sourceURL: URL,
        outputURL: URL,
        routeSelection: TaptionCodecRouteSelection,
        outputPolicy: TaptionVideoOutputPolicy,
        audioPlan: TaptionAudioTranscodePlan?
    ) -> SW_FFmpegCommandPlan? {
        let readiness = TaptionVideoCodecExecutionReadinessReporter.item(
            for: routeSelection.route,
            outputContainer: outputPolicy.container
        )
        guard readiness.hasCommandPlan else {
            return nil
        }

        return try? SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: TaptionCodecTranscodeRequest(
                sourceURL: sourceURL,
                outputURL: outputURL,
                route: routeSelection.route,
                options: TaptionCodecTranscodeOptions(
                    outputPolicy: outputPolicy,
                    preserveSourceVisualQuality: true,
                    preserveAudioWhenPossible: audioPlan != nil
                )
            ),
            audioPlan: audioPlan
        )
    }
}

enum TaptionEncoderRecommendation {
    static func recommendedSelection(
        canUseHardwareHEVC: Bool,
        allowsSoftwareFallback: Bool = true
    ) -> TaptionEncoderSelection {
        if canUseHardwareHEVC {
            return TaptionEncoderSelection(
                requestedMode: .automatic,
                backend: .appleVideoToolbox,
                reason: "Hardware encoding will be used automatically when available."
            )
        }

        if allowsSoftwareFallback {
            return TaptionEncoderSelection(
                requestedMode: .automatic,
                backend: .customSoftware,
                reason: "Software fallback will be used automatically when needed."
            )
        }

        return TaptionEncoderSelection(
            requestedMode: .automatic,
            backend: nil,
            reason: "No compatible encoder was selected."
        )
    }
}
