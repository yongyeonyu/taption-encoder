import Foundation

enum TaptionOutputImplementationState: String, Codable, Equatable {
    case implemented
    case commandPlanReady
    case planned
    case unsupported

    var displayName: String {
        switch self {
        case .implemented:
            return "Available Now"
        case .commandPlanReady:
            return "Command Plan Ready"
        case .planned:
            return "Planned"
        case .unsupported:
            return "Unsupported"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .implemented:
            return "Now"
        case .commandPlanReady:
            return "Plan Ready"
        case .planned:
            return "Planned"
        case .unsupported:
            return "Blocked"
        }
    }
}

struct TaptionOutputReadinessCatalogItem: Codable, Equatable, Identifiable {
    var videoCodec: TaptionVideoCodec
    var container: TaptionVideoContainer
    var state: TaptionOutputImplementationState
    var note: String?

    var id: String {
        "\(videoCodec.rawValue)-\(container.rawValue)"
    }
}

struct TaptionOutputReadinessCatalogReport: Codable, Equatable {
    var videoCodecCount: Int
    var containerCount: Int
    var outputSelectionCount: Int
    var implementedOutputSelectionCount: Int
    var commandPlanReadyOutputSelectionCount: Int
    var plannedOutputSelectionCount: Int
    var unsupportedOutputSelectionCount: Int
    var defaultOutputCodec: TaptionVideoCodec
    var defaultOutputContainer: TaptionVideoContainer
    var defaultOutputState: TaptionOutputImplementationState
    var firstReleaseOutputCodecs: [TaptionVideoCodec]
    var items: [TaptionOutputReadinessCatalogItem]

    var stateCountsAreConsistent: Bool {
        outputSelectionCount == implementedOutputSelectionCount
            + commandPlanReadyOutputSelectionCount
            + plannedOutputSelectionCount
            + unsupportedOutputSelectionCount
    }

    var outputSelectionCoverageIsPassing: Bool {
        outputSelectionCount == videoCodecCount * containerCount
            && stateCountsAreConsistent
            && defaultOutputState == .implemented
            && unsupportedOutputSelectionCount == 0
    }
}

struct TaptionAudioOutputReadinessCatalogItem: Codable, Equatable, Identifiable {
    var audioCodec: TaptionAudioCodec
    var container: TaptionVideoContainer
    var state: TaptionOutputImplementationState
    var note: String?

    var id: String {
        "\(audioCodec.rawValue)-\(container.rawValue)"
    }
}

struct TaptionAudioOutputReadinessCatalogReport: Codable, Equatable {
    var audioCodecCount: Int
    var containerCount: Int
    var outputSelectionCount: Int
    var implementedOutputSelectionCount: Int
    var commandPlanReadyOutputSelectionCount: Int
    var plannedOutputSelectionCount: Int
    var unsupportedOutputSelectionCount: Int
    var defaultOutputCodec: TaptionAudioCodec
    var defaultOutputContainer: TaptionVideoContainer
    var defaultOutputState: TaptionOutputImplementationState
    var items: [TaptionAudioOutputReadinessCatalogItem]

    var stateCountsAreConsistent: Bool {
        outputSelectionCount == implementedOutputSelectionCount
            + commandPlanReadyOutputSelectionCount
            + plannedOutputSelectionCount
            + unsupportedOutputSelectionCount
    }

    var outputSelectionCoverageIsPassing: Bool {
        outputSelectionCount == audioCodecCount * containerCount
            && stateCountsAreConsistent
            && defaultOutputState == .implemented
            && unsupportedOutputSelectionCount == 0
    }
}

enum TaptionLaunchInputSupportAvailability: String, Codable, Equatable {
    case availableNow
    case availableOnSupportedHardware
}

struct TaptionLaunchInputVideoSupportItem: Codable, Equatable {
    var codec: TaptionVideoCodec
    var availability: TaptionLaunchInputSupportAvailability
}

struct TaptionLaunchOutputSupport: Codable, Equatable {
    var videoCodec: TaptionVideoCodec
    var audioCodec: TaptionAudioCodec
    var container: TaptionVideoContainer
}

enum TaptionLaunchInputSupportState: String, Codable, Equatable {
    case supported
    case plannedCodec
    case unsupportedContainer
    case unsupportedCodec
}

struct TaptionLaunchInputSupportDiagnosis: Codable, Equatable {
    var state: TaptionLaunchInputSupportState
    var title: String
    var detail: String

    var isSupportedNow: Bool {
        state == .supported
    }

    var isPlannedOnly: Bool {
        state == .plannedCodec
    }
}

struct TaptionLaunchInputReadinessReport: Codable, Equatable {
    var executableNowVideoCodecs: [TaptionVideoCodec]
    var hardwareGatedVideoCodecs: [TaptionVideoCodec]
    var plannedVideoCodecs: [TaptionVideoCodec]
    var inputContainers: [TaptionVideoContainer]
    var outputVideoCodec: TaptionVideoCodec
    var outputContainers: [TaptionVideoContainer]

    var executableNowVideoCodecCount: Int {
        executableNowVideoCodecs.count
    }

    var hardwareGatedVideoCodecCount: Int {
        hardwareGatedVideoCodecs.count
    }

    var plannedVideoCodecCount: Int {
        plannedVideoCodecs.count
    }

    var roadmapVideoCodecCount: Int {
        executableNowVideoCodecCount
            + hardwareGatedVideoCodecCount
            + plannedVideoCodecCount
    }
}

enum TaptionLaunchInputRuntimeAvailability: String, Codable, Equatable {
    case nowHardware
    case nowSoftware
    case nowMixed
    case needsHardware
    case planned
    case unsupported

    var displayName: String {
        switch self {
        case .nowHardware:
            return "Now(HW)"
        case .nowSoftware:
            return "Now(SW)"
        case .nowMixed:
            return "Now(HW/SW)"
        case .needsHardware:
            return "Needs HW"
        case .planned:
            return "Planned"
        case .unsupported:
            return "No"
        }
    }

    var isExecutableNow: Bool {
        switch self {
        case .nowHardware, .nowSoftware, .nowMixed:
            return true
        case .needsHardware, .planned, .unsupported:
            return false
        }
    }
}

struct TaptionLaunchInputRuntimeReadinessReport: Codable, Equatable {
    var nowHardwareVideoCodecs: [TaptionVideoCodec]
    var nowSoftwareVideoCodecs: [TaptionVideoCodec]
    var nowMixedVideoCodecs: [TaptionVideoCodec]
    var needsHardwareVideoCodecs: [TaptionVideoCodec]
    var plannedVideoCodecs: [TaptionVideoCodec]
    var unsupportedVideoCodecs: [TaptionVideoCodec]

    var executableNowVideoCodecCount: Int {
        nowHardwareVideoCodecs.count
            + nowSoftwareVideoCodecs.count
            + nowMixedVideoCodecs.count
    }
}

enum TaptionLaunchSupportCatalog {
    static let supportedInputContainers: [TaptionVideoContainer] = [
        .mp4,
        .mov,
        .m4v,
        .mkv,
        .avi,
        .webm,
        .flv,
        .ogg,
        .mpegTransportStream,
        .mxf,
        .mpegProgramStream,
        .lrf,
        .dv,
        .threeGP,
        .threeGPP2,
        .asf,
        .wmv,
        .nut,
        .roq,
        .realMedia,
        .rawElementaryStream
    ]

    static let supportedInputVideoCodecs: [TaptionLaunchInputVideoSupportItem] = [
        TaptionLaunchInputVideoSupportItem(codec: .av1, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .vp9, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .vp8, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .mpeg1, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .mpeg2, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .mpeg4Visual, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .h263, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .h261, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .flashVideo, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .microsoftMPEG4V2, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .microsoftMPEG4V3, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .motionJPEG, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .jpeg2000, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .jpegLS, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .losslessJPEG, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .animation, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .cinepak, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .sorensonVideo, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .sorensonVideo3, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .quickTimeVideo, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .theora, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .realVideo1, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .realVideo, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .roqVideo, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .wmv, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .microsoftVideo1, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .asusV1, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .asusV2, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .flashScreenVideo, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .flashScreenVideo2, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .zmbv, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .cljr, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .snow, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .ffv1, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .huffYUV, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .utVideo, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .magicYUV, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .dvcPro, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .dvcProHD, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .dv, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .cineForm, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .dnxhd, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .pngVideo, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .r10k, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .v308, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .v210, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .r210, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .v408, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .v410, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .y41p, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .microsoftRLE, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .quickTimeGraphics, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .yuv4, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .rawVideo, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .h264, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .hevc, availability: .availableNow),
        TaptionLaunchInputVideoSupportItem(codec: .proRes, availability: .availableOnSupportedHardware)
    ]

    static let supportedOutput = TaptionLaunchOutputSupport(
        videoCodec: .hevc,
        audioCodec: TaptionAudioCodecRoutePlanner.defaultOutputCodec,
        container: .mp4
    )

    static var executableNowInputVideoCodecs: [TaptionVideoCodec] {
        supportedInputVideoCodecs
            .filter { $0.availability == .availableNow }
            .map(\.codec)
    }

    static var hardwareGatedInputVideoCodecs: [TaptionVideoCodec] {
        supportedInputVideoCodecs
            .filter { $0.availability == .availableOnSupportedHardware }
            .map(\.codec)
    }

    static var plannedInputVideoCodecs: [TaptionVideoCodec] {
        let currentBuildCodecs = Set(supportedInputVideoCodecs.map(\.codec))
        return TaptionCodecRegistry.universalSourceCodecs.filter {
            !currentBuildCodecs.contains($0)
        }
    }

    static var supportedOutputContainers: [TaptionVideoContainer] {
        TaptionCodecOutputCatalog.selectableContainers
    }

    static var supportedInputVideoSummary: String {
        supportedInputVideoCodecs
            .map { $0.codec.displayName }
            .joined(separator: ", ")
    }

    static var supportedInputContainerSummary: String {
        supportedInputContainers
            .flatMap(\.supportedFileExtensions)
            .map { $0.uppercased() }
            .joined(separator: ", ")
    }

    static var supportedOutputContainerSummary: String {
        supportedOutputContainers
            .map { $0.defaultFileExtension.uppercased() }
            .joined(separator: ", ")
    }

    static var supportedInputVideoNote: String {
        let deviceLimited = supportedInputVideoCodecs
            .filter { $0.availability == .availableOnSupportedHardware }
            .map { $0.codec.displayName }

        guard !deviceLimited.isEmpty else {
            return "All listed input codecs are executable in the current launch build."
        }

        return "\(deviceLimited.joined(separator: ", ")) input requires Apple-native hardware routes on the current device."
    }

    static var plannedInputVideoNote: String {
        guard !plannedInputVideoCodecs.isEmpty else {
            return "There are no roadmap-only input codecs outside the current launch build."
        }

        return "\(plannedInputVideoCodecs.count) roadmap input codecs are tracked for future H.265 output, but are not executable in this build."
    }

    static var supportedInputContainerNote: String {
        "The current launch build imports Apple-readable containers plus selected software-inspected inputs such as MKV, WebM, FLV, OGG/OGV, AVI, MXF, MPEG transport and program streams, DJI LRF, NUT, 3GP, 3G2, ASF/WMV, and raw elementary streams."
    }

    static func inputAvailability(for codec: TaptionVideoCodec) -> TaptionLaunchInputSupportAvailability? {
        supportedInputVideoCodecs
            .first { $0.codec == codec }?
            .availability
    }

    static func isPlannedInputVideoCodec(_ codec: TaptionVideoCodec) -> Bool {
        plannedInputVideoCodecs.contains(codec)
    }

    static func makeInputReadinessReport() -> TaptionLaunchInputReadinessReport {
        TaptionLaunchInputReadinessReport(
            executableNowVideoCodecs: executableNowInputVideoCodecs,
            hardwareGatedVideoCodecs: hardwareGatedInputVideoCodecs,
            plannedVideoCodecs: plannedInputVideoCodecs,
            inputContainers: supportedInputContainers,
            outputVideoCodec: supportedOutput.videoCodec,
            outputContainers: supportedOutputContainers
        )
    }

    static func runtimeAvailability(
        for codec: TaptionVideoCodec,
        hardwareSupport: TaptionCodecHardwareSupportProfile
    ) -> TaptionLaunchInputRuntimeAvailability {
        guard inputAvailability(for: codec) != nil else {
            return isPlannedInputVideoCodec(codec) ? .planned : .unsupported
        }

        let selection = TaptionCodecRoutePlanner.selectRoute(
            sourceCodec: codec,
            outputCodec: supportedOutput.videoCodec,
            requestedMode: .automatic,
            hardwareSupport: hardwareSupport
        )

        guard selection.isEncodableNow else {
            return selection.support == .unsupported ? .unsupported : .needsHardware
        }

        switch selection.executionKind {
        case .hardware:
            return .nowHardware
        case .software:
            return .nowSoftware
        case .mixed:
            return .nowMixed
        case .planned:
            return .planned
        case .unsupported:
            return .unsupported
        }
    }

    static func makeRuntimeInputReadinessReport(
        hardwareSupport: TaptionCodecHardwareSupportProfile
    ) -> TaptionLaunchInputRuntimeReadinessReport {
        var nowHardwareVideoCodecs: [TaptionVideoCodec] = []
        var nowSoftwareVideoCodecs: [TaptionVideoCodec] = []
        var nowMixedVideoCodecs: [TaptionVideoCodec] = []
        var needsHardwareVideoCodecs: [TaptionVideoCodec] = []
        var plannedVideoCodecs: [TaptionVideoCodec] = []
        var unsupportedVideoCodecs: [TaptionVideoCodec] = []

        for codec in TaptionCodecRegistry.universalSourceCodecs {
            switch runtimeAvailability(for: codec, hardwareSupport: hardwareSupport) {
            case .nowHardware:
                nowHardwareVideoCodecs.append(codec)
            case .nowSoftware:
                nowSoftwareVideoCodecs.append(codec)
            case .nowMixed:
                nowMixedVideoCodecs.append(codec)
            case .needsHardware:
                needsHardwareVideoCodecs.append(codec)
            case .planned:
                plannedVideoCodecs.append(codec)
            case .unsupported:
                unsupportedVideoCodecs.append(codec)
            }
        }

        return TaptionLaunchInputRuntimeReadinessReport(
            nowHardwareVideoCodecs: nowHardwareVideoCodecs,
            nowSoftwareVideoCodecs: nowSoftwareVideoCodecs,
            nowMixedVideoCodecs: nowMixedVideoCodecs,
            needsHardwareVideoCodecs: needsHardwareVideoCodecs,
            plannedVideoCodecs: plannedVideoCodecs,
            unsupportedVideoCodecs: unsupportedVideoCodecs
        )
    }

    static func diagnoseInput(
        container: TaptionVideoContainer,
        videoCodec: TaptionVideoCodec
    ) -> TaptionLaunchInputSupportDiagnosis {
        guard supportedInputContainers.contains(container) else {
            return TaptionLaunchInputSupportDiagnosis(
                state: .unsupportedContainer,
                title: "Input Container Unsupported",
                detail: "\(container.defaultFileExtension.uppercased()) input is not supported in the current launch build."
            )
        }

        guard let availability = inputAvailability(for: videoCodec) else {
            if isPlannedInputVideoCodec(videoCodec) {
                return TaptionLaunchInputSupportDiagnosis(
                    state: .plannedCodec,
                    title: "Input Planned",
                    detail: "\(videoCodec.displayName) input is in the H.265 roadmap, but is not executable in this build."
                )
            }

            return TaptionLaunchInputSupportDiagnosis(
                state: .unsupportedCodec,
                title: "Input Codec Unsupported",
                detail: "\(videoCodec.displayName) input is not supported in the current launch build."
            )
        }

        let detail: String
        switch availability {
        case .availableNow:
            detail = "The current launch build can inspect this input and encode it to H.265 MP4 or MOV."
        case .availableOnSupportedHardware:
            detail = "\(videoCodec.displayName) input can encode to H.265 only on devices with the required Apple-native hardware path."
        }

        return TaptionLaunchInputSupportDiagnosis(
            state: .supported,
            title: "Input Supported",
            detail: detail
        )
    }
}

enum TaptionCodecOutputCatalog {
    static var selectableVideoCodecs: [TaptionVideoCodec] {
        TaptionCodecRegistry.universalOutputCodecs
    }

    static var selectableContainers: [TaptionVideoContainer] {
        [.mp4, .mov]
    }

    static func implementationState(
        videoCodec: TaptionVideoCodec,
        container: TaptionVideoContainer
    ) -> TaptionOutputImplementationState {
        guard selectableVideoCodecs.contains(videoCodec),
              selectableContainers.contains(container) else {
            return .unsupported
        }

        return .implemented
    }

    static func makeReadinessReport() -> TaptionOutputReadinessCatalogReport {
        let items = selectableVideoCodecs.flatMap { videoCodec in
            selectableContainers.map { container in
                let state = implementationState(
                    videoCodec: videoCodec,
                    container: container
                )
                return TaptionOutputReadinessCatalogItem(
                    videoCodec: videoCodec,
                    container: container,
                    state: state,
                    note: implementationNote(
                        videoCodec: videoCodec,
                        container: container
                    )
                )
            }
        }

        return TaptionOutputReadinessCatalogReport(
            videoCodecCount: selectableVideoCodecs.count,
            containerCount: selectableContainers.count,
            outputSelectionCount: items.count,
            implementedOutputSelectionCount: items.filter { $0.state == .implemented }.count,
            commandPlanReadyOutputSelectionCount: items.filter { $0.state == .commandPlanReady }.count,
            plannedOutputSelectionCount: items.filter { $0.state == .planned }.count,
            unsupportedOutputSelectionCount: items.filter { $0.state == .unsupported }.count,
            defaultOutputCodec: .hevc,
            defaultOutputContainer: .mp4,
            defaultOutputState: implementationState(videoCodec: .hevc, container: .mp4),
            firstReleaseOutputCodecs: TaptionCodecRegistry.firstReleaseOutputCodecs,
            items: items
        )
    }

    static func routeImplementationState(
        sourceCodec: TaptionVideoCodec,
        outputCodec: TaptionVideoCodec,
        container: TaptionVideoContainer
    ) -> TaptionOutputImplementationState {
        let outputState = implementationState(
            videoCodec: outputCodec,
            container: container
        )
        guard outputState != .unsupported else {
            return .unsupported
        }

        let route = TaptionCodecRoute(
            sourceCodec: sourceCodec,
            outputCodec: outputCodec
        )
        switch TaptionCodecRegistry.support(for: route) {
        case .implemented:
            return outputState
        case .planned:
            if outputState == .implemented {
                return commandPlanState(
                    videoCodec: outputCodec,
                    container: container
                )
            }
            return outputState
        case .unsupported:
            return .unsupported
        }
    }

    static func implementationNote(
        videoCodec: TaptionVideoCodec,
        container: TaptionVideoContainer
    ) -> String? {
        switch implementationState(videoCodec: videoCodec, container: container) {
        case .implemented:
            return nil
        case .commandPlanReady:
            return "\(videoCodec.shortDisplayName) / \(container.defaultFileExtension.uppercased()) output has a software command plan and waits for the broad codec backend."
        case .planned:
            return "\(videoCodec.shortDisplayName) / \(container.defaultFileExtension.uppercased()) output is planned for the universal codec update."
        case .unsupported:
            return "\(videoCodec.shortDisplayName) / \(container.defaultFileExtension.uppercased()) output is not in the current codec roadmap."
        }
    }

    private static func commandPlanState(
        videoCodec: TaptionVideoCodec,
        container: TaptionVideoContainer
    ) -> TaptionOutputImplementationState {
        if SW_FFmpegCodecCommandPlanner.videoEncoderName(for: videoCodec) != nil,
           SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.canWriteContainer(container) {
            return .commandPlanReady
        }
        return .planned
    }
}

enum TaptionAudioCodecOutputCatalog {
    static var selectableAudioCodecs: [TaptionAudioCodec] {
        TaptionAudioCodecRoutePlanner.universalAudioCodecs
    }

    static var selectableContainers: [TaptionVideoContainer] {
        TaptionCodecOutputCatalog.selectableContainers
    }

    static func implementationState(
        audioCodec: TaptionAudioCodec,
        container: TaptionVideoContainer
    ) -> TaptionOutputImplementationState {
        guard selectableAudioCodecs.contains(audioCodec),
              selectableContainers.contains(container) else {
            return .unsupported
        }

        if audioCodec == TaptionAudioCodecRoutePlanner.defaultOutputCodec,
           [.mp4, .mov].contains(container) {
            return .implemented
        }

        if SW_FFmpegCodecCommandPlanner.audioEncoderName(for: audioCodec) != nil,
           SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.canWriteContainer(container) {
            return .commandPlanReady
        }

        return .planned
    }

    static func makeReadinessReport() -> TaptionAudioOutputReadinessCatalogReport {
        let items = selectableAudioCodecs.flatMap { audioCodec in
            selectableContainers.map { container in
                let state = implementationState(
                    audioCodec: audioCodec,
                    container: container
                )
                return TaptionAudioOutputReadinessCatalogItem(
                    audioCodec: audioCodec,
                    container: container,
                    state: state,
                    note: implementationNote(
                        audioCodec: audioCodec,
                        container: container
                    )
                )
            }
        }

        return TaptionAudioOutputReadinessCatalogReport(
            audioCodecCount: selectableAudioCodecs.count,
            containerCount: selectableContainers.count,
            outputSelectionCount: items.count,
            implementedOutputSelectionCount: items.filter { $0.state == .implemented }.count,
            commandPlanReadyOutputSelectionCount: items.filter { $0.state == .commandPlanReady }.count,
            plannedOutputSelectionCount: items.filter { $0.state == .planned }.count,
            unsupportedOutputSelectionCount: items.filter { $0.state == .unsupported }.count,
            defaultOutputCodec: TaptionAudioCodecRoutePlanner.defaultOutputCodec,
            defaultOutputContainer: .mp4,
            defaultOutputState: implementationState(
                audioCodec: TaptionAudioCodecRoutePlanner.defaultOutputCodec,
                container: .mp4
            ),
            items: items
        )
    }

    static func implementationNote(
        audioCodec: TaptionAudioCodec,
        container: TaptionVideoContainer
    ) -> String? {
        switch implementationState(audioCodec: audioCodec, container: container) {
        case .implemented:
            return nil
        case .commandPlanReady:
            return "\(audioCodec.displayName) / \(container.defaultFileExtension.uppercased()) audio output has a software command plan and waits for the broad codec backend."
        case .planned:
            return "\(audioCodec.displayName) / \(container.defaultFileExtension.uppercased()) audio output is planned for the universal codec update."
        case .unsupported:
            return "\(audioCodec.displayName) / \(container.defaultFileExtension.uppercased()) audio output is not in the current codec roadmap."
        }
    }
}
