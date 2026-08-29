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

enum TaptionSoftwareCodecBackendReviewStatus: String, Codable, Equatable {
    case open
    case satisfied
    case blocked
}

struct TaptionSoftwareCodecBackendReviewFinding: Codable, Equatable, Identifiable {
    var id: String { gate.rawValue }
    var gate: TaptionSoftwareCodecBackendReadinessGate
    var status: TaptionSoftwareCodecBackendReviewStatus
    var summary: String
    var requiredEvidence: [String]
}

struct TaptionSoftwareCodecBackendReviewReport: Codable, Equatable {
    var backend: TaptionEncodingBackend
    var displayName: String
    var statusDate: String
    var reviewedSourceURLs: [String]
    var conclusion: String
    var findings: [TaptionSoftwareCodecBackendReviewFinding]

    var satisfiedGates: [TaptionSoftwareCodecBackendReadinessGate] {
        findings
            .filter { $0.status == .satisfied }
            .map(\.gate)
            .sorted()
    }

    var openGates: [TaptionSoftwareCodecBackendReadinessGate] {
        findings
            .filter { $0.status != .satisfied }
            .map(\.gate)
            .sorted()
    }

    var approvedForExecution: Bool {
        Set(satisfiedGates) == Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
    }
}

enum TaptionFFmpegFamilyBackendCandidateStatus: String, Codable, Equatable {
    case selected
    case rejected
    case deferred
}

struct TaptionFFmpegFamilyBackendCandidateDecision: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var status: TaptionFFmpegFamilyBackendCandidateStatus
    var runnerShape: String
    var rationale: String
    var requiredEvidence: [String]
}

struct TaptionFFmpegFamilyBackendDecisionReport: Codable, Equatable {
    var statusDate: String
    var selectedCandidateID: String
    var selectedOutputPolicy: String
    var sourceURLs: [String]
    var candidates: [TaptionFFmpegFamilyBackendCandidateDecision]
    var proofBoundary: String

    var selectedCandidate: TaptionFFmpegFamilyBackendCandidateDecision? {
        candidates.first { $0.id == selectedCandidateID }
    }
}

enum TaptionFFmpegFamilyBackendDecisionCatalog {
    static var currentVC1Y41PDecision: TaptionFFmpegFamilyBackendDecisionReport {
        TaptionFFmpegFamilyBackendDecisionReport(
            statusDate: "2026-07-11",
            selectedCandidateID: "source-built-lgpl-ffmpeg-decode-bridge",
            selectedOutputPolicy: "Decode VC-1 raw, Y41P, and ProRes RAW fallback with a bundled source-built LGPL FFmpeg-family library bridge, then feed Taption Encoder's existing H.265 / HEVC MP4/MOV writer. Do not add non-H.265 outputs or writable containers beyond MP4/MOV.",
            sourceURLs: [
                "https://www.ffmpeg.org/legal.html",
                "https://www.ffmpeg.org/general.html",
                "https://developer.apple.com/app-store/review/guidelines/",
                "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html",
                "https://github.com/arthenica/ffmpeg-kit",
                "https://github.com/arthenica/ffmpeg-kit/wiki/License"
            ],
            candidates: [
                TaptionFFmpegFamilyBackendCandidateDecision(
                    id: "source-built-lgpl-ffmpeg-decode-bridge",
                    name: "Source-built LGPL FFmpeg-family decode bridge",
                    status: .selected,
                    runnerShape: "Bundle-contained in-process library bridge; no downloaded binary, side-loaded plugin, or external executable.",
                    rationale: "This is the narrowest App Store-safe candidate for VC-1 raw and Y41P because it targets demux/decode only while preserving the existing H.265-only MP4/MOV output writer. The app keeps GPL/nonfree code disabled, records exact source/build notices, and avoids prebuilt binary provenance risk.",
                    requiredEvidence: [
                        "Engineering configure line with GPL and nonfree features disabled is recorded for the vendored bridge; formal legal approval remains separate.",
                        "Exact source archive URL, SHA-256, local bridge source, and bundled notice/source-availability resources are recorded.",
                        "iOS static XCFramework integration proves the bridge can execute in process from the app/test bundle on simulator and a connected iPad.",
                        "Focused app-side VC-1 raw and Y41P sample transcodes to H.265 MP4/MOV have simulator and connected-iPad output verification; Y41P PCM audio preservation to AAC has connected-iPad decoded-signal proof.",
                        "iPhone and older-device thermal, memory, battery, and runtime threshold proof before release promotion."
                    ]
                ),
                TaptionFFmpegFamilyBackendCandidateDecision(
                    id: "prebuilt-or-archived-ffmpegkit",
                    name: "Prebuilt or archived FFmpegKit binary package",
                    status: .rejected,
                    runnerShape: "Prebuilt command-style wrapper package.",
                    rationale: "FFmpegKit is retired with historical binaries/docs, and FFmpegKit package licensing changes to GPL when GPL builds are used. Prebuilt binary provenance and package availability are weaker than a reproducible source-built app-owned bridge.",
                    requiredEvidence: [
                        "Only reconsider if the company selects a maintained source-built successor and reviews its exact source, build flags, notices, and binary provenance.",
                        "Do not consume random community prebuilt binaries for App Store release."
                    ]
                ),
                TaptionFFmpegFamilyBackendCandidateDecision(
                    id: "downloaded-ffmpeg-binary-or-plugin",
                    name: "Downloaded ffmpeg binary or codec plugin",
                    status: .rejected,
                    runnerShape: "Runtime-downloaded executable or codec module.",
                    rationale: "Apple requires apps to be self-contained and not download, install, or execute code that changes app functionality.",
                    requiredEvidence: [
                        "No App Store path. Keep this rejected unless Apple policy or company distribution model changes."
                    ]
                ),
                TaptionFFmpegFamilyBackendCandidateDecision(
                    id: "swiftvlc-current-bundle",
                    name: "Current SwiftVLC/libVLC bundle",
                    status: .deferred,
                    runnerShape: "Existing software VLC decoder path.",
                    rationale: "It remains useful for current executable software routes, but current VC-1 raw and Y41P local sample proof shows no-frame or unsupported behavior. It is not the selected path for promoting these two samples.",
                    requiredEvidence: [
                        "Only reconsider for VC-1 raw/Y41P if a bundled libVLC configuration proves app-side frame decode for both samples."
                    ]
                )
            ],
            proofBoundary: "This decision now has source-built bridge artifacts plus focused iOS simulator and connected-iPad real-decoder execution proof for VC-1 raw and Y41P. Y41P PCM audio preservation to AAC has connected-iPad track and decoded-signal proof, and ProRes RAW fallback has simulator output proof. It is not formal legal approval, not App Review approval, not broad-backend release promotion, not iPhone or older-device threshold proof, not TestFlight proof, and not public-release proof."
        )
    }
}

enum TaptionSoftwareCodecBackendReviewCatalog {
    static var currentFFmpegFamilyReview: TaptionSoftwareCodecBackendReviewReport {
        let profile = SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate
        return TaptionSoftwareCodecBackendReviewReport(
            backend: profile.backend,
            displayName: profile.displayName,
            statusDate: "2026-07-11",
            reviewedSourceURLs: [
                "https://www.ffmpeg.org/legal.html",
                "https://www.ffmpeg.org/general.html",
                "https://developer.apple.com/app-store/review/guidelines/",
                "https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html",
                "https://github.com/arthenica/ffmpeg-kit",
                "https://github.com/arthenica/ffmpeg-kit/wiki/License",
                "https://www.x265.org/",
                "https://developer.apple.com/documentation/coreaudiotypes/kaudioformatmpegd_usac",
                "https://www2.iis.fraunhofer.de/AAC/xhe-aac.html",
                "https://portal.3gpp.org/desktopmodules/Specifications/SpecificationDetails.aspx?specificationId=1450",
                "https://portal.3gpp.org/desktopmodules/Specifications/SpecificationDetails.aspx?specificationId=1449",
                "https://www.etsi.org/resources/intellectual-property-rights/"
            ],
            conclusion: "Engineering review only: a source-built LGPL FFmpeg-family decode bridge is vendored and proven on simulator plus a connected iPad for focused VC-1 raw/Y41P decode into Taption Encoder's H.265 MP4/MOV writer; ProRes RAW fallback is simulator-proven. Keep broad-backend release promotion planning-only until App Store-policy review, formal license review, release notices, broad fixture proof, audio proof, binary-size approval, and older-device proof close separately.",
            findings: [
                TaptionSoftwareCodecBackendReviewFinding(
                    gate: .licenseReview,
                    status: .open,
                    summary: "FFmpeg can stay on the LGPL path only with a reviewed configuration that avoids GPL and nonfree parts. Current command plans mention GPL-sensitive encoders such as libx265/libx264, so proprietary App Store execution requires either a different encoder path, commercial licenses, or a formal source-release decision.",
                    requiredEvidence: [
                        "Final configure line without --enable-gpl and without --enable-nonfree, or a signed commercial/source-release decision for every GPL-sensitive encoder.",
                        "Exact source archive, local changes diff, third-party library license map, and counsel-approved notice/EULA language.",
                        "HEVC/H.265 patent and distribution review kept separate from FFmpeg's open-source license review."
                    ]
                ),
                TaptionSoftwareCodecBackendReviewFinding(
                    gate: .appStorePolicyReview,
                    status: .open,
                    summary: "Apple review guidelines require the app to stay self-contained and prohibit downloading or executing code that changes app functionality. Broad codec support must ship inside the reviewed bundle and must not fetch an ffmpeg binary, plugin, or codec module later.",
                    requiredEvidence: [
                        "App Review note explaining that codec execution is bundled, offline, user-file-scoped, and does not download executable code.",
                        "No runtime code download, plugin install, side-loaded binary, or remote codec module path.",
                        "Third-party SDK and media-conversion behavior checked against current App Review guidelines before submission."
                    ]
                ),
                TaptionSoftwareCodecBackendReviewFinding(
                    gate: .binarySizeBudget,
                    status: .open,
                    summary: "Broad demux/decode support can materially increase app size. A release build must prove the final framework slice size and App Store package impact before enabling execution.",
                    requiredEvidence: [
                        "Archive/export size report for iPhone and iPad slices.",
                        "Codec-module inclusion list with each disabled component justified.",
                        "Cold launch and import latency comparison against the current build."
                    ]
                ),
                TaptionSoftwareCodecBackendReviewFinding(
                    gate: .iosPackagingIntegration,
                    status: .open,
                    summary: "The current command-plan model is a planning boundary. A focused static XCFramework proves an in-process, bundle-contained VC-1/Y41P decode bridge on simulator and a connected iPad, but broader release packaging still needs sandboxed source-access plus iPhone and older-device proof.",
                    requiredEvidence: [
                        "Signed Xcode framework/package integration with no external executable dependency.",
                        "Sandboxed file-access test for Files, folder, and Photos-derived temporary sources.",
                        "Runtime proof that runner injection executes inside the app bundle on simulator and real devices."
                    ]
                ),
                TaptionSoftwareCodecBackendReviewFinding(
                    gate: .codecNoticeGeneration,
                    status: .open,
                    summary: "If the broad backend ships, Open Source Notices must include final license texts, source availability, exact build configuration, and any EULA reverse-engineering carve-out required by the selected licenses.",
                    requiredEvidence: [
                        "Bundled notice resources for FFmpeg and every enabled external library.",
                        "Public source download URL matching the shipped binaries.",
                        "Release-notice tests proving no bundled backend entry is missing final license text."
                    ]
                ),
                TaptionSoftwareCodecBackendReviewFinding(
                    gate: .fixtureTranscodeRegressionProof,
                    status: .open,
                    summary: "Focused app-side simulator and connected-iPad proof exists for VC-1 raw and Y41P through the vendored decode bridge. The remaining selected video codecs have simulator sample transcode proof, while broad retained-fixture regression evidence remains a separate release gate.",
                    requiredEvidence: [
                        "Focused app-side simulator and connected-iPad proof for VC-1 raw and Y41P to H.265 MP4/MOV.",
                        "Regression pass for the existing bundled fixture matrix.",
                        "Output verification for H.265 video, MP4/MOV container, duration, dimensions, and visual decodability."
                    ]
                ),
                TaptionSoftwareCodecBackendReviewFinding(
                    gate: .audioSignalRegressionProof,
                    status: .open,
                    summary: "Official Fraunhofer xHE-AAC input now has Apple-native AAC output signal proof, and Y41P PCM input has bundled-bridge AAC output signal proof for MP4/MOV. AMR-WB+ remains open: FFmpeg 8.1.1 exposes AMR-WB but no AMR-WB+ decoder, while the 3GPP TS 26.304 reference code only has a host raw encode/decode round-trip proof and cannot be promoted into the app without separate IPR and distribution approval.",
                    requiredEvidence: [
                        "Formal AMR-WB+ patent/IPR, reference-source distribution, EULA, and App Store counsel approval before any reference-code or alternate backend is bundled.",
                        "App-side AMR-WB+ decodable sample execution proof after an approved backend exists; host reference-code raw round-trip proof is not a substitute.",
                        "Keep xHE-AAC native execution, Y41P PCM-to-AAC signal proof, and AMR-WB+ host/backend review as separate evidence surfaces.",
                        "Negative-sample handling with clear English fallback copy."
                    ]
                ),
                TaptionSoftwareCodecBackendReviewFinding(
                    gate: .oldDevicePerformanceProof,
                    status: .open,
                    summary: "Broad software decode can stress thermal, memory, battery, and runtime limits on older devices. Execution promotion requires older-device runtime proof separate from simulator results.",
                    requiredEvidence: [
                        "Real-device runtime sample encoding proof on older supported hardware.",
                        "Thermal, battery, memory, and ETA warning behavior captured during long software routes.",
                        "Battery Saver and Max Performance comparisons kept separate from App Store/TestFlight proof."
                    ]
                )
            ]
        )
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

enum TaptionOpenSourceDistributionMaterialRequirement: String, Codable, Equatable {
    case none
    case lgplStaticLinking
}

struct TaptionOpenSourceNoticeEntry: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var summary: String
    var category: TaptionOpenSourceNoticeCategory
    var isShippedInCurrentBuild: Bool
    var requiresFinalLicenseText: Bool
    var licenseTextResourcePath: String?
    var supplementalLicenseTextResourcePaths: [String] = []
    var distributionMaterialRequirement: TaptionOpenSourceDistributionMaterialRequirement = .none
    var verifiedDistributionMaterialsURL: String? = nil
    var relatedBackend: TaptionEncodingBackend?

    var allLicenseTextResourcePaths: [String] {
        [licenseTextResourcePath].compactMap { $0 } + supplementalLicenseTextResourcePaths
    }

    var hasFinalLicenseText: Bool {
        !requiresFinalLicenseText || !allLicenseTextResourcePaths.isEmpty
    }

    var hasVerifiedDistributionMaterials: Bool {
        guard distributionMaterialRequirement != .none else {
            return true
        }
        return verifiedDistributionMaterialsURL?.isEmpty == false
    }
}

struct TaptionOpenSourceNoticeReadinessReport: Codable, Equatable {
    var entryCount: Int
    var shippedEntryCount: Int
    var entriesRequiringFinalLicenseTextCount: Int
    var missingFinalLicenseTextEntries: [TaptionOpenSourceNoticeEntry]
    var missingDistributionMaterialEntries: [TaptionOpenSourceNoticeEntry]

    var isReadyForReleaseNotices: Bool {
        missingFinalLicenseTextEntries.isEmpty
    }

    var isReadyForPublicDistribution: Bool {
        isReadyForReleaseNotices && missingDistributionMaterialEntries.isEmpty
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
        guard !entry.allLicenseTextResourcePaths.isEmpty else {
            return nil
        }

        var texts: [String] = []
        for resourcePath in entry.allLicenseTextResourcePaths {
            guard let url = resourceURL(forResourcePath: resourcePath, bundle: bundle),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                return nil
            }
            texts.append(text)
        }
        return texts.joined(separator: "\n\n")
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
                id: "swiftvlc",
                name: "SwiftVLC 0.10.1",
                summary: "MIT-licensed Swift wrapper pinned to revision 58d1f3a8fc1366b2ffcd4748203a52d8410b7da2. The separately licensed libVLC engine is disclosed independently.",
                category: .shippedComponent,
                isShippedInCurrentBuild: true,
                requiresFinalLicenseText: true,
                licenseTextResourcePath: "OpenSourceNotices/SwiftVLC-MIT.txt",
                relatedBackend: .softwareVLCDecoder
            ),
            TaptionOpenSourceNoticeEntry(
                id: "libvlc",
                name: "libVLC",
                summary: "Statically linked VideoLAN media engine built from revision c833c4be000b426d73ff4324bec574065f00e3df under LGPL 2.1 or later. Its checksum-verified contrib notices and relinking offer are included.",
                category: .shippedComponent,
                isShippedInCurrentBuild: true,
                requiresFinalLicenseText: true,
                licenseTextResourcePath: "OpenSourceNotices/libVLC-LGPL-Notice.txt",
                supplementalLicenseTextResourcePaths: [
                    "OpenSourceNotices/LGPL-2.1.txt",
                    "OpenSourceNotices/libVLC-Contrib-Licenses.txt"
                ],
                distributionMaterialRequirement: .lgplStaticLinking,
                relatedBackend: .softwareVLCDecoder
            ),
            TaptionOpenSourceNoticeEntry(
                id: "ffmpeg-lgpl-decode-bridge",
                name: "FFmpeg 8.1.1 LGPL Decode Bridge",
                summary: "Statically linked, decode-only FFmpeg 8.1.1 bridge under LGPL 2.1 or later. GPL and nonfree components are disabled; exact enabled components and relinking offer are included.",
                category: .shippedComponent,
                isShippedInCurrentBuild: true,
                requiresFinalLicenseText: true,
                licenseTextResourcePath: "OpenSourceNotices/FFmpeg-LGPL-Decode-Bridge.txt",
                supplementalLicenseTextResourcePaths: ["OpenSourceNotices/LGPL-2.1.txt"],
                distributionMaterialRequirement: .lgplStaticLinking,
                relatedBackend: .ffmpegFamily
            ),
            TaptionOpenSourceNoticeEntry(
                id: "google-mobile-ads",
                name: "Google Mobile Ads Swift Package Wrapper 13.5.0",
                summary: "Apache 2.0 applies to the pinned Swift Package manifest and wrapper. It does not license the separately distributed GoogleMobileAds SDK binary, which is governed by Google's SDK terms.",
                category: .shippedComponent,
                isShippedInCurrentBuild: true,
                requiresFinalLicenseText: true,
                licenseTextResourcePath: "OpenSourceNotices/GoogleMobileAds.txt",
                relatedBackend: nil
            ),
            TaptionOpenSourceNoticeEntry(
                id: "google-user-messaging-platform",
                name: "Google User Messaging Platform Swift Package Wrapper 3.1.0",
                summary: "Apache 2.0 applies to the pinned Swift Package manifest and wrapper. It does not license the separately distributed UserMessagingPlatform SDK binary, which is governed by Google's SDK terms.",
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
            missingFinalLicenseTextEntries: requiringFinalText.filter { !$0.hasFinalLicenseText },
            missingDistributionMaterialEntries: entries.filter { !$0.hasVerifiedDistributionMaterials }
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
                $0.allLicenseTextResourcePaths.contains { resourcePath in
                    TaptionOpenSourceNoticeTextLoader.resourceURL(
                        forResourcePath: resourcePath,
                        bundle: bundle
                    ) == nil
                }
            },
            emptyResourceEntries: requiringFinalText.filter {
                $0.allLicenseTextResourcePaths.contains { resourcePath in
                    guard let url = TaptionOpenSourceNoticeTextLoader.resourceURL(
                        forResourcePath: resourcePath,
                        bundle: bundle
                    ) else {
                        return false
                    }
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                        return true
                    }
                    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            }
        )
    }
}

enum SW_SoftwareCodecBackendRegistry {
    static let vlcSoftwareDecoder = TaptionSoftwareCodecBackendProfile(
        backend: .softwareVLCDecoder,
        displayName: "SwiftVLC Video Software Decoder",
        videoDecodeCodecs: [.av1, .h264, .hevc, .dolbyVisionHEVC, .vp9, .vp8, .mpeg1, .mpeg2, .mpeg4Visual, .h263, .h261, .flashVideo, .microsoftMPEG4V2, .microsoftMPEG4V3, .motionJPEG, .jpeg2000, .jpegLS, .losslessJPEG, .animation, .cinepak, .sorensonVideo, .sorensonVideo3, .quickTimeVideo, .theora, .realVideo1, .realVideo, .roqVideo, .wmv, .microsoftVideo1, .asusV1, .asusV2, .flashScreenVideo, .flashScreenVideo2, .zmbv, .cljr, .snow, .ffv1, .huffYUV, .utVideo, .magicYUV, .dvcPro, .dvcProHD, .dv, .cineForm, .dnxhd, .pngVideo, .r10k, .v308, .v210, .r210, .v408, .v410, .microsoftRLE, .quickTimeGraphics, .yuv4, .rawVideo, .proRes],
        videoEncodeCodecs: [],
        audioDecodeCodecs: [],
        audioEncodeCodecs: [],
        readableContainers: [.mp4, .mov, .m4v, .mkv, .webm, .avi, .flv, .ogg, .mpegTransportStream, .mpegProgramStream, .lrf, .mxf, .dv, .threeGP, .threeGPP2, .asf, .wmv, .nut, .roq, .realMedia, .rawElementaryStream],
        writableContainers: [],
        requiresLicenseReview: true,
        notes: "Current app fallback for AV1, H.264, H.265, VP9, VP8, MPEG-1, MPEG-2, MPEG-4 Visual, H.263, H.261, Flash Video, Microsoft MPEG-4 V2/V3, Motion JPEG, JPEG 2000, JPEG-LS, Lossless JPEG, Apple Animation, Cinepak, Sorenson Video, Sorenson Video 3, QuickTime Video, Theora, RealVideo 1.0, RealVideo, RoQ Video, Windows Media Video, Microsoft Video 1, ASUS V1/V2, FlashSV/FlashSV2, ZMBV, CLJR, Snow, FFV1, HuffYUV, Ut Video, MagicYUV, DVCPro, DVCPro HD, DV, CineForm, DNxHD, PNG Video, R10K, V308, V210, R210, V408, V410, Microsoft RLE, QuickTime Graphics, YUV4, Raw Video, and Apple ProRes decode. Output encoding is handled by the route-specific software-to-H.265 algorithms."
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
        notes: "Candidate backend for broad input to H.265 MP4/MOV conversion. Actual bundled implementation still needs App Store, license, binary-size, and performance review."
    )

    static let profiles: [TaptionSoftwareCodecBackendProfile] = [
        vlcSoftwareDecoder,
        ffmpegFamilyCandidate
    ]

    static var broadReadableContainers: Set<TaptionVideoContainer> {
        Set(TaptionVideoContainer.allCases.filter { $0 != .unknown })
    }

    static var broadWritableContainers: Set<TaptionVideoContainer> {
        [
            .mp4,
            .mov
        ]
    }

    static func profile(for backend: TaptionEncodingBackend) -> TaptionSoftwareCodecBackendProfile? {
        profiles.first { $0.backend == backend }
    }

    static func preferredVideoDecodeBackend(for codec: TaptionVideoCodec) -> TaptionEncodingBackend? {
        if vlcSoftwareDecoder.canDecodeVideo(codec) {
            return vlcSoftwareDecoder.backend
        }
        if TaptionCodecRegistry.bundledFFmpegDecodeBridgeSourceCodecs.contains(codec) {
            return .ffmpegFamily
        }
        return profiles.first { $0.canDecodeVideo(codec) }?.backend
    }

    static func currentExecutableVideoDecodeBackend(for codec: TaptionVideoCodec) -> TaptionEncodingBackend? {
        if vlcSoftwareDecoder.canDecodeVideo(codec) {
            return vlcSoftwareDecoder.backend
        }
        if TaptionCodecRegistry.bundledFFmpegDecodeBridgeSourceCodecs.contains(codec) {
            return .ffmpegFamily
        }
        return nil
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
