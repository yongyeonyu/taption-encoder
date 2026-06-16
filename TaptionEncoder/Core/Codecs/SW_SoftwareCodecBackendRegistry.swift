import Foundation

struct TaptionSoftwareCodecBackendProfile: Codable, Equatable, Identifiable {
    var id: String { backend.rawValue }
    var backend: TaptionEncodingBackend
    var displayName: String
    var videoDecodeCodecs: Set<TaptionVideoCodec>
    var videoEncodeCodecs: Set<TaptionVideoCodec>
    var audioDecodeCodecs: Set<TaptionAudioCodec>
    var audioEncodeCodecs: Set<TaptionAudioCodec>
    var readableContainers: Set<TaptionVideoContainer>
    var writableContainers: Set<TaptionVideoContainer>
    var requiresLicenseReview: Bool
    var notes: String

    func canDecodeVideo(_ codec: TaptionVideoCodec) -> Bool {
        videoDecodeCodecs.contains(codec)
    }

    func canEncodeVideo(_ codec: TaptionVideoCodec) -> Bool {
        videoEncodeCodecs.contains(codec)
    }

    func canDecodeAudio(_ codec: TaptionAudioCodec) -> Bool {
        audioDecodeCodecs.contains(codec)
    }

    func canEncodeAudio(_ codec: TaptionAudioCodec) -> Bool {
        audioEncodeCodecs.contains(codec)
    }

    func canReadContainer(_ container: TaptionVideoContainer) -> Bool {
        readableContainers.contains(container)
    }

    func canWriteContainer(_ container: TaptionVideoContainer) -> Bool {
        writableContainers.contains(container)
    }
}

enum TaptionSoftwareCodecBackendReadinessGate: String, Codable, CaseIterable, Comparable {
    case licenseReview
    case appStorePolicyReview
    case binarySizeBudget
    case iosPackagingIntegration
    case codecNoticeGeneration
    case fixtureTranscodeRegressionProof
    case audioSignalRegressionProof
    case oldDevicePerformanceProof

    static func < (
        lhs: TaptionSoftwareCodecBackendReadinessGate,
        rhs: TaptionSoftwareCodecBackendReadinessGate
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .licenseReview:
            return "License review"
        case .appStorePolicyReview:
            return "App Store policy review"
        case .binarySizeBudget:
            return "Binary size budget"
        case .iosPackagingIntegration:
            return "iOS packaging"
        case .codecNoticeGeneration:
            return "Open-source notice generation"
        case .fixtureTranscodeRegressionProof:
            return "Fixture transcode proof"
        case .audioSignalRegressionProof:
            return "Audio signal proof"
        case .oldDevicePerformanceProof:
            return "Old-device performance proof"
        }
    }
}

struct TaptionSoftwareCodecBackendReadinessReport: Codable, Equatable {
    var backend: TaptionEncodingBackend
    var displayName: String
    var isBundledInCurrentBuild: Bool
    var isExecutableInCurrentBuild: Bool
    var openGates: [TaptionSoftwareCodecBackendReadinessGate]
    var videoDecodeCodecCount: Int
    var videoEncodeCodecCount: Int
    var audioDecodeCodecCount: Int
    var audioEncodeCodecCount: Int
    var readableContainerCount: Int
    var writableContainerCount: Int
    var plannedVideoRouteCount: Int
    var plannedAudioRouteCount: Int
    var commandPlannableVideoOutputCodecCount: Int
    var commandUnsupportedVideoOutputCodecs: [TaptionVideoCodec]
    var commandPlannableAudioOutputCodecCount: Int
    var commandUnsupportedAudioOutputCodecs: [TaptionAudioCodec]

    var canPromoteToExecutableBackend: Bool {
        isBundledInCurrentBuild && openGates.isEmpty
    }

    var mustRemainPlanningOnly: Bool {
        !canPromoteToExecutableBackend
    }
}

enum TaptionOpenSourceNoticeCategory: String, Codable, CaseIterable, Comparable {
    case shippedComponent
    case localDevelopmentTooling
    case planningOnlyCandidate

    static func < (
        lhs: TaptionOpenSourceNoticeCategory,
        rhs: TaptionOpenSourceNoticeCategory
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .shippedComponent:
            return "Shipped Components"
        case .localDevelopmentTooling:
            return "Local Development Tooling"
        case .planningOnlyCandidate:
            return "Broad Codec Backend Candidate"
        }
    }
}

struct TaptionOpenSourceNoticeEntry: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var summary: String
    var category: TaptionOpenSourceNoticeCategory
    var isShippedInCurrentBuild: Bool
    var requiresFinalLicenseText: Bool
    var licenseTextResourcePath: String?
    var relatedBackend: TaptionEncodingBackend?

    var hasFinalLicenseText: Bool {
        !requiresFinalLicenseText || licenseTextResourcePath?.isEmpty == false
    }
}

struct TaptionOpenSourceNoticeReadinessReport: Codable, Equatable {
    var entryCount: Int
    var shippedEntryCount: Int
    var entriesRequiringFinalLicenseTextCount: Int
    var missingFinalLicenseTextEntries: [TaptionOpenSourceNoticeEntry]

    var isReadyForReleaseNotices: Bool {
        missingFinalLicenseTextEntries.isEmpty
    }
}

struct TaptionOpenSourceNoticeBundleResourceReport: Equatable {
    var entriesRequiringFinalLicenseText: [TaptionOpenSourceNoticeEntry]
    var missingResourceEntries: [TaptionOpenSourceNoticeEntry]
    var emptyResourceEntries: [TaptionOpenSourceNoticeEntry]

    var isReadyForBundledResources: Bool {
        missingResourceEntries.isEmpty && emptyResourceEntries.isEmpty
    }
}

enum TaptionOpenSourceNoticeTextLoader {
    static func licenseText(
        for entry: TaptionOpenSourceNoticeEntry,
        bundle: Bundle = .main
    ) -> String? {
        guard let url = licenseTextURL(for: entry, bundle: bundle) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func licenseTextURL(
        for entry: TaptionOpenSourceNoticeEntry,
        bundle: Bundle = .main
    ) -> URL? {
        guard let resourcePath = entry.licenseTextResourcePath else {
            return nil
        }
        return resourceURL(forResourcePath: resourcePath, bundle: bundle)
    }

    static func resourceURL(
        forResourcePath resourcePath: String,
        bundle: Bundle = .main
    ) -> URL? {
        let nsPath = resourcePath as NSString
        let resourceName = (nsPath.deletingPathExtension as NSString).lastPathComponent
        let resourceExtension = nsPath.pathExtension
        let resourceDirectory = nsPath.deletingLastPathComponent
        let subdirectory = resourceDirectory.isEmpty ? nil : resourceDirectory
        return bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension.isEmpty ? nil : resourceExtension,
            subdirectory: subdirectory
        )
    }
}

enum TaptionOpenSourceNoticeCatalog {
    static var shippedComponents: [TaptionOpenSourceNoticeEntry] {
        [
            TaptionOpenSourceNoticeEntry(
                id: "swiftvlc-libvlc",
                name: "SwiftVLC / libVLC",
                summary: "Software AV1 media decoding fallback used by the current app build.",
                category: .shippedComponent,
                isShippedInCurrentBuild: true,
                requiresFinalLicenseText: true,
                licenseTextResourcePath: "OpenSourceNotices/SwiftVLC-libVLC.txt",
                relatedBackend: .softwareAV1Decoder
            ),
            TaptionOpenSourceNoticeEntry(
                id: "google-mobile-ads",
                name: "Google Mobile Ads SDK",
                summary: "Banner, interstitial, app-open, and rewarded ad integration.",
                category: .shippedComponent,
                isShippedInCurrentBuild: true,
                requiresFinalLicenseText: true,
                licenseTextResourcePath: "OpenSourceNotices/GoogleMobileAds.txt",
                relatedBackend: nil
            ),
            TaptionOpenSourceNoticeEntry(
                id: "google-user-messaging-platform",
                name: "Google User Messaging Platform",
                summary: "Consent and privacy messaging support when required.",
                category: .shippedComponent,
                isShippedInCurrentBuild: true,
                requiresFinalLicenseText: true,
                licenseTextResourcePath: "OpenSourceNotices/GoogleUserMessagingPlatform.txt",
                relatedBackend: nil
            )
        ]
    }

    static var localDevelopmentTooling: [TaptionOpenSourceNoticeEntry] {
        [
            TaptionOpenSourceNoticeEntry(
                id: "ffmpeg-local-tooling",
                name: "FFmpeg",
                summary: "Development-only fixture generation and local codec validation scripts. This is not a shipped broad codec backend in the current app build.",
                category: .localDevelopmentTooling,
                isShippedInCurrentBuild: false,
                requiresFinalLicenseText: false,
                licenseTextResourcePath: nil,
                relatedBackend: nil
            )
        ]
    }

    static func planningOnlyCandidates(
        readinessReport: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
    ) -> [TaptionOpenSourceNoticeEntry] {
        [
            TaptionOpenSourceNoticeEntry(
                id: "ffmpeg-family-broad-codec-backend",
                name: readinessReport.displayName,
                summary: "Not bundled in the current app build. It remains planning-only until licensing, App Store policy, binary size, iOS packaging, notices, fixture proof, audio proof, and old-device performance gates are closed.",
                category: .planningOnlyCandidate,
                isShippedInCurrentBuild: readinessReport.isBundledInCurrentBuild,
                requiresFinalLicenseText: readinessReport.isBundledInCurrentBuild,
                licenseTextResourcePath: nil,
                relatedBackend: readinessReport.backend
            )
        ]
    }

    static func allEntries(
        readinessReport: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
    ) -> [TaptionOpenSourceNoticeEntry] {
        shippedComponents
            + localDevelopmentTooling
            + planningOnlyCandidates(readinessReport: readinessReport)
    }

    static func readinessReport(
        readinessReport: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
    ) -> TaptionOpenSourceNoticeReadinessReport {
        let entries = allEntries(readinessReport: readinessReport)
        let requiringFinalText = entries.filter(\.requiresFinalLicenseText)
        return TaptionOpenSourceNoticeReadinessReport(
            entryCount: entries.count,
            shippedEntryCount: entries.filter(\.isShippedInCurrentBuild).count,
            entriesRequiringFinalLicenseTextCount: requiringFinalText.count,
            missingFinalLicenseTextEntries: requiringFinalText.filter { !$0.hasFinalLicenseText }
        )
    }

    static func bundleResourceReport(
        bundle: Bundle = .main,
        readinessReport: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
    ) -> TaptionOpenSourceNoticeBundleResourceReport {
        let requiringFinalText = allEntries(readinessReport: readinessReport)
            .filter(\.requiresFinalLicenseText)
        return TaptionOpenSourceNoticeBundleResourceReport(
            entriesRequiringFinalLicenseText: requiringFinalText,
            missingResourceEntries: requiringFinalText.filter {
                TaptionOpenSourceNoticeTextLoader.licenseTextURL(for: $0, bundle: bundle) == nil
            },
            emptyResourceEntries: requiringFinalText.filter {
                guard let text = TaptionOpenSourceNoticeTextLoader.licenseText(for: $0, bundle: bundle) else {
                    return false
                }
                return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
    }
}

enum SW_SoftwareCodecBackendRegistry {
    static let av1SoftwareDecoder = TaptionSoftwareCodecBackendProfile(
        backend: .softwareAV1Decoder,
        displayName: "SwiftVLC AV1 Software Decoder",
        videoDecodeCodecs: [.av1],
        videoEncodeCodecs: [],
        audioDecodeCodecs: [],
        audioEncodeCodecs: [],
        readableContainers: [.mp4, .mov, .m4v, .mkv, .webm],
        writableContainers: [],
        requiresLicenseReview: true,
        notes: "Current app fallback for AV1 decode. Output encoding is handled by the route-specific AV1-to-H.265 algorithm."
    )

    static let ffmpegFamilyCandidate = TaptionSoftwareCodecBackendProfile(
        backend: .ffmpegFamily,
        displayName: "FFmpeg-family Broad Codec Backend",
        videoDecodeCodecs: Set(TaptionCodecRegistry.universalSourceCodecs),
        videoEncodeCodecs: Set(TaptionCodecRegistry.universalOutputCodecs),
        audioDecodeCodecs: Set(TaptionAudioCodecRoutePlanner.universalAudioCodecs),
        audioEncodeCodecs: Set(TaptionAudioCodecRoutePlanner.universalAudioCodecs),
        readableContainers: broadReadableContainers,
        writableContainers: broadWritableContainers,
        requiresLicenseReview: true,
        notes: "Candidate backend for universal all-to-all conversion. Actual bundled implementation still needs App Store, license, binary-size, and performance review."
    )

    static let profiles: [TaptionSoftwareCodecBackendProfile] = [
        av1SoftwareDecoder,
        ffmpegFamilyCandidate
    ]

    static var broadReadableContainers: Set<TaptionVideoContainer> {
        Set(TaptionVideoContainer.allCases.filter { $0 != .unknown })
    }

    static var broadWritableContainers: Set<TaptionVideoContainer> {
        [
            .mp4,
            .mov,
            .m4v,
            .mkv,
            .avi,
            .webm,
            .mxf,
            .mpegTransportStream,
            .mpegProgramStream,
            .dv,
            .ogg,
            .flv,
            .threeGP,
            .threeGPP2,
            .asf,
            .wmv,
            .rawElementaryStream
        ]
    }

    static func profile(for backend: TaptionEncodingBackend) -> TaptionSoftwareCodecBackendProfile? {
        profiles.first { $0.backend == backend }
    }

    static func preferredVideoDecodeBackend(for codec: TaptionVideoCodec) -> TaptionEncodingBackend? {
        if av1SoftwareDecoder.canDecodeVideo(codec) {
            return av1SoftwareDecoder.backend
        }
        return profiles.first { $0.canDecodeVideo(codec) }?.backend
    }

    static func preferredVideoEncodeBackend(for codec: TaptionVideoCodec) -> TaptionEncodingBackend? {
        ffmpegFamilyCandidate.canEncodeVideo(codec) ? ffmpegFamilyCandidate.backend : nil
    }

    static func preferredAudioDecodeBackend(for codec: TaptionAudioCodec) -> TaptionEncodingBackend? {
        ffmpegFamilyCandidate.canDecodeAudio(codec) ? ffmpegFamilyCandidate.backend : nil
    }

    static func preferredAudioEncodeBackend(for codec: TaptionAudioCodec) -> TaptionEncodingBackend? {
        ffmpegFamilyCandidate.canEncodeAudio(codec) ? ffmpegFamilyCandidate.backend : nil
    }

    static func canPlanSoftwareVideoRoute(
        _ route: TaptionCodecRoute,
        outputContainer: TaptionVideoContainer
    ) -> Bool {
        preferredVideoDecodeBackend(for: route.sourceCodec) != nil
            && preferredVideoEncodeBackend(for: route.outputCodec) != nil
            && ffmpegFamilyCandidate.canWriteContainer(outputContainer)
    }

    static func canPlanSoftwareAudioRoute(
        _ route: TaptionAudioCodecRoute
    ) -> Bool {
        preferredAudioDecodeBackend(for: route.sourceCodec) != nil
            && preferredAudioEncodeBackend(for: route.outputCodec) != nil
    }

    static func broadBackendReadinessReport(
        isBundledInCurrentBuild: Bool = false,
        satisfiedGates: Set<TaptionSoftwareCodecBackendReadinessGate> = []
    ) -> TaptionSoftwareCodecBackendReadinessReport {
        let profile = ffmpegFamilyCandidate
        let requiredGates = Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
        let openGates = requiredGates
            .subtracting(satisfiedGates)
            .sorted()
        let isExecutable = isBundledInCurrentBuild && openGates.isEmpty

        return TaptionSoftwareCodecBackendReadinessReport(
            backend: profile.backend,
            displayName: profile.displayName,
            isBundledInCurrentBuild: isBundledInCurrentBuild,
            isExecutableInCurrentBuild: isExecutable,
            openGates: openGates,
            videoDecodeCodecCount: profile.videoDecodeCodecs.count,
            videoEncodeCodecCount: profile.videoEncodeCodecs.count,
            audioDecodeCodecCount: profile.audioDecodeCodecs.count,
            audioEncodeCodecCount: profile.audioEncodeCodecs.count,
            readableContainerCount: profile.readableContainers.count,
            writableContainerCount: profile.writableContainers.count,
            plannedVideoRouteCount: TaptionCodecRegistry.plannedUniversalRoutes.count,
            plannedAudioRouteCount: TaptionAudioCodecRoutePlanner.plannedUniversalRoutes.count,
            commandPlannableVideoOutputCodecCount: SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs.count,
            commandUnsupportedVideoOutputCodecs: SW_FFmpegCodecCommandPlanner.commandUnsupportedVideoOutputCodecs,
            commandPlannableAudioOutputCodecCount: SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs.count,
            commandUnsupportedAudioOutputCodecs: SW_FFmpegCodecCommandPlanner.commandUnsupportedAudioOutputCodecs
        )
    }
}
