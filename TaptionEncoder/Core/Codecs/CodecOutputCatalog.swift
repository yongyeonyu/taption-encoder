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

enum TaptionCodecOutputCatalog {
    static var selectableVideoCodecs: [TaptionVideoCodec] {
        TaptionCodecRegistry.universalOutputCodecs
    }

    static var selectableContainers: [TaptionVideoContainer] {
        TaptionVideoContainer.allCases.filter { $0 != .unknown }
    }

    static func implementationState(
        videoCodec: TaptionVideoCodec,
        container: TaptionVideoContainer
    ) -> TaptionOutputImplementationState {
        guard selectableVideoCodecs.contains(videoCodec),
              selectableContainers.contains(container) else {
            return .unsupported
        }

        if videoCodec == .hevc && container == .mp4 {
            return .implemented
        }

        if SW_FFmpegCodecCommandPlanner.videoEncoderName(for: videoCodec) != nil,
           SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.canWriteContainer(container) {
            return .commandPlanReady
        }

        return .planned
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
