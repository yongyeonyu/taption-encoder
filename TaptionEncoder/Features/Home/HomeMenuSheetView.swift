import SwiftUI

enum HomeMenuSheet: String, Identifiable {
    case help
    case openSource
    case deviceInfo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .help:
            return "Help"
        case .openSource:
            return "Open Source Notices"
        case .deviceInfo:
            return "Device Info"
        }
    }
}

struct HomeMenuSheetView: View {
    var sheet: HomeMenuSheet
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                TaptionTheme.appBackground
                    .ignoresSafeArea()

                content
            }
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case .help:
            HelpSheetContentView()
        case .openSource:
            OpenSourceNoticesSheetContentView()
        case .deviceInfo:
            DeviceInfoSheetContentView()
        }
    }
}

private struct HelpSheetContentView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetInfoCard(
                    title: "Quick Flow",
                    rows: [
                        ("1", "Pick files, a folder, or a Photos video."),
                        ("2", "Review the detected media information."),
                        ("3", "Start encoding, then watch the save ad when the output is ready.")
                    ]
                )

                SheetInfoCard(
                    title: "Codec Policy",
                    rows: [
                        ("HW", "Hardware is used first when the device supports the route."),
                        ("SW", "Software is used when hardware is unavailable or the input needs fallback."),
                        ("Quality", "Default options preserve source-like resolution, frame rate, audio timing, and visual quality.")
                    ]
                )

                SheetInfoCard(
                    title: "Current Build",
                    rows: [
                        ("MVP", "AV1 to H.265 is the first app route."),
                        ("Next", "Broader input to H.265, then selectable output codecs.")
                    ]
                )
            }
            .padding(18)
        }
    }
}

private struct OpenSourceNoticesSheetContentView: View {
    private let readinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
    private let shippedNotices = TaptionOpenSourceNoticeCatalog.shippedComponents
    private let toolingNotices = TaptionOpenSourceNoticeCatalog.localDevelopmentTooling

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Third-party components used by this app or its local development tooling are listed here. Final release notices must include the exact shipped binary components and license text.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                OpenSourceNoticeSection(
                    title: TaptionOpenSourceNoticeCategory.shippedComponent.displayName,
                    notices: shippedNotices
                )

                OpenSourceNoticeSection(
                    title: TaptionOpenSourceNoticeCategory.localDevelopmentTooling.displayName,
                    notices: toolingNotices
                )

                BroadCodecBackendNoticeCard(
                    report: readinessReport,
                    notice: TaptionOpenSourceNoticeCatalog
                        .planningOnlyCandidates(readinessReport: readinessReport)
                        .first
                )
            }
            .padding(18)
        }
    }
}

private struct OpenSourceNoticeSection: View {
    var title: String
    var notices: [TaptionOpenSourceNoticeEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(notices) { notice in
                OpenSourceNoticeRow(notice: notice)
            }
        }
    }
}

private struct OpenSourceNoticeRow: View {
    var title: String
    var detail: String
    var licenseText: String?

    init(title: String, detail: String, licenseText: String? = nil) {
        self.title = title
        self.detail = detail
        self.licenseText = licenseText
    }

    init(notice: TaptionOpenSourceNoticeEntry) {
        self.title = notice.name
        self.detail = notice.summary
        self.licenseText = TaptionOpenSourceNoticeTextLoader.licenseText(for: notice)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            if let licenseText {
                DisclosureGroup {
                    Text(licenseText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.white.opacity(0.62))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                } label: {
                    Text("License Text")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TaptionTheme.accent)
                }
                .tint(TaptionTheme.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaptionTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TaptionTheme.border, lineWidth: 1)
        )
    }
}

private struct BroadCodecBackendNoticeCard: View {
    var report: TaptionSoftwareCodecBackendReadinessReport
    var notice: TaptionOpenSourceNoticeEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(TaptionOpenSourceNoticeCategory.planningOnlyCandidate.displayName)
                .font(.headline)
                .foregroundStyle(.white)

            OpenSourceNoticeRow(
                title: notice?.name ?? report.displayName,
                detail: notice?.summary ?? "Not bundled in the current app build."
            )

            Text("Open gates: \(openGateSummary)")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var openGateSummary: String {
        guard !report.openGates.isEmpty else {
            return "None"
        }
        return report.openGates
            .map(\.displayName)
            .joined(separator: ", ")
    }
}

private struct DeviceInfoSheetContentView: View {
    @State private var report = HW_CodecCapabilityProbe.makeReport()
    @State private var reportSaveMessage: ReportSaveMessage?
    private let routeSimulationSummary = HW_CodecRouteSimulator.summary()
    private let codecCompletionAudit = TaptionUniversalCodecCompletionAuditor.makeReport()
    private let outputReadinessCatalog = TaptionCodecOutputCatalog.makeReadinessReport()
    private let audioOutputReadinessCatalog = TaptionAudioCodecOutputCatalog.makeReadinessReport()
    private let modelCoverageReport = HW_AppleDeviceCodecModelMatrix.coverageReport()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetInfoCard(
                    title: "Device",
                    rows: [
                        ("Model", report.modelIdentifier),
                        ("Static Match", staticModelSummary),
                        ("Matrix", reportReconciliationSummary),
                        ("OS", "\(report.systemName) \(report.systemVersion)"),
                        ("Probe", "\(report.probeResolution.width)x\(report.probeResolution.height)")
                    ]
                )

                SheetInfoCard(
                    title: "Apple Device Route Simulation",
                    rows: [
                        ("Profiles", "\(routeSimulationSummary.profileCount) family and model profiles"),
                        ("Routes", "\(routeSimulationSummary.routeCountPerProfile) routes per profile"),
                        ("Rows", "\(routeSimulationSummary.rowCount) simulated route decisions"),
                        ("AV1", routeSimulationSummary.av1ToHEVCPathSummary),
                        ("Priority", routeSimulationSummary.isPassing ? "HW-first route priority passed." : "Review HW route priority warnings.")
                    ]
                )

                SheetInfoCard(
                    title: "Static Apple Model Matrix",
                    rows: [
                        ("Scope", modelCoverageReport.scope),
                        ("Models", "\(modelCoverageReport.modelCount) total · \(modelCoverageReport.iPhoneModelCount) iPhone · \(modelCoverageReport.iPadModelCount) iPad"),
                        ("AV1 Decode", "\(modelCoverageReport.av1HardwareDecodeModelCount) models"),
                        ("HEVC Encode", "\(modelCoverageReport.hevcHardwareEncodeModelCount) models"),
                        ("ProRes Encode", "\(modelCoverageReport.proResHardwareEncodeModelCount) models"),
                        ("Status", modelCoverageReport.isPassing ? "No duplicate or missing profile rows." : "Review matrix coverage warnings.")
                    ]
                )

                SheetInfoCard(
                    title: "Universal Codec Mesh Readiness",
                    rows: [
                        ("Contract", codecCompletionAudit.contractName),
                        ("Stage", codecCompletionAuditStageSummary),
                        ("Required", codecCompletionAudit.missingRequiredBidirectionalVideoRoutes.isEmpty ? "H.264 to AV1, AV1 to H.264, and same-codec re-encode routes are planned." : "Review required bidirectional route gaps."),
                        ("Video", "\(codecCompletionAudit.videoCurrentBuildRunnableRouteCount) runnable · \(codecCompletionAudit.videoCommandPlanOnlyRouteCount) command-plan · \(codecCompletionAudit.videoBlockedMissingSoftwareEncoderRouteCount) blocked · \(codecCompletionAudit.videoPendingRuntimeRouteCount) pending runtime"),
                        ("Audio", "\(codecCompletionAudit.audioCurrentBuildRunnableRouteCount) runnable · \(codecCompletionAudit.audioCommandPlanOnlyRouteCount) command-plan · \(codecCompletionAudit.audioBlockedMissingSoftwareEncoderRouteCount) blocked · \(codecCompletionAudit.audioPendingRuntimeRouteCount) pending runtime"),
                        ("Selectors", codecCompletionAudit.outputSelectionCoverageIsPassing ? "Video and audio output selectors cover the universal route catalogs." : "Review output selector coverage gaps."),
                        ("Backend", "\(codecCompletionAudit.broadSoftwareBackendDisplayName) has \(codecCompletionAudit.broadSoftwareBackendOpenGateCount) open readiness gates.")
                    ]
                )

                SheetInfoCard(
                    title: "Output Selector Readiness",
                    rows: [
                        ("Catalog", "\(outputReadinessCatalog.videoCodecCount) codecs · \(outputReadinessCatalog.containerCount) containers"),
                        ("Selections", "\(outputReadinessCatalog.outputSelectionCount) output codec/container pairs"),
                        ("Now", "\(outputReadinessCatalog.implementedOutputSelectionCount) executable in this build"),
                        ("Plan Ready", "\(outputReadinessCatalog.commandPlanReadyOutputSelectionCount) command-plan ready"),
                        ("Planned", "\(outputReadinessCatalog.plannedOutputSelectionCount) waiting for codec/backend decisions"),
                        ("Blocked", "\(outputReadinessCatalog.unsupportedOutputSelectionCount) unsupported selections"),
                        ("Default", "\(outputReadinessCatalog.defaultOutputCodec.shortDisplayName) / \(outputReadinessCatalog.defaultOutputContainer.defaultFileExtension.uppercased()) is \(outputReadinessCatalog.defaultOutputState.shortDisplayName)")
                    ]
                )

                SheetInfoCard(
                    title: "Audio Output Readiness",
                    rows: [
                        ("Catalog", "\(audioOutputReadinessCatalog.audioCodecCount) codecs · \(audioOutputReadinessCatalog.containerCount) containers"),
                        ("Selections", "\(audioOutputReadinessCatalog.outputSelectionCount) audio codec/container pairs"),
                        ("Now", "\(audioOutputReadinessCatalog.implementedOutputSelectionCount) executable in this build"),
                        ("Plan Ready", "\(audioOutputReadinessCatalog.commandPlanReadyOutputSelectionCount) command-plan ready"),
                        ("Planned", "\(audioOutputReadinessCatalog.plannedOutputSelectionCount) waiting for codec/backend decisions"),
                        ("Blocked", "\(audioOutputReadinessCatalog.unsupportedOutputSelectionCount) unsupported selections"),
                        ("Default", "\(audioOutputReadinessCatalog.defaultOutputCodec.displayName) / \(audioOutputReadinessCatalog.defaultOutputContainer.defaultFileExtension.uppercased()) is \(audioOutputReadinessCatalog.defaultOutputState.shortDisplayName)")
                    ]
                )

                Button {
                    saveDeviceReport()
                } label: {
                    Label("Save Device Report", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .background(TaptionTheme.accent)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.accent.opacity(0.65), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if let reportSaveMessage {
                    Text(reportSaveMessage.text)
                        .font(.caption)
                        .foregroundStyle(reportSaveMessage.isError ? Color.red.opacity(0.86) : TaptionTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Video HW Codec Support")
                        .font(.headline)
                        .foregroundStyle(.white)

                    ForEach(report.videoCapabilities) { capability in
                        DeviceVideoCodecCapabilityRow(capability: capability)
                    }
                }
                .padding(14)
                .background(TaptionTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.border, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Audio Native Codec Support")
                        .font(.headline)
                        .foregroundStyle(.white)

                    ForEach(report.audioCapabilities) { capability in
                        DeviceAudioCodecCapabilityRow(capability: capability)
                    }
                }
                .padding(14)
                .background(TaptionTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.border, lineWidth: 1)
                )

                Text("Video hardware support is probed on this device at runtime. Audio support uses Apple-native codec capability catalogs. Encoding still falls back to software if hardware or native support is unavailable, busy, or unsupported for the selected route.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    private var staticModelSummary: String {
        guard let model = HW_AppleDeviceCodecModelMatrix.model(identifier: report.modelIdentifier) else {
            return "Runtime probe only"
        }
        return "\(model.marketingName) · \(model.chipFamily)"
    }

    private var reportReconciliationSummary: String {
        HW_DeviceCodecReportReconciler
            .reconcile(report: report)
            .statusSummary
    }

    private var codecCompletionAuditStageSummary: String {
        switch codecCompletionAudit.stage {
        case .launchRouteOnly:
            return "Launch route only. Universal planning needs review."
        case .allToAllPlanningLocked:
            return "All-to-all planning locked. Runtime execution is still gated."
        case .allToAllCommandPlansReady:
            return "All-to-all command plans ready. Backend execution is still gated."
        case .allToAllExecutable:
            return "All-to-all execution ready."
        }
    }

    private func saveDeviceReport() {
        do {
            let freshReport = HW_CodecCapabilityProbe.makeReport()
            let snapshot = HW_DeviceCodecReportStore.makeSnapshot(
                report: freshReport,
                routeSimulationSummary: routeSimulationSummary,
                createdAt: freshReport.generatedAt
            )
            let fileURL = try HW_DeviceCodecReportStore.save(snapshot: snapshot)
            report = freshReport
            reportSaveMessage = ReportSaveMessage(
                text: "Saved \(fileURL.lastPathComponent)",
                isError: false
            )
            AppLogger.info(
                "Device codec report saved",
                category: .app,
                metadata: [
                    "file": fileURL.lastPathComponent,
                    "model": freshReport.modelIdentifier
                ]
            )
        } catch {
            reportSaveMessage = ReportSaveMessage(
                text: "Save failed: \(error.localizedDescription)",
                isError: true
            )
            AppLogger.error(
                "Device codec report save failed",
                category: .app,
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private struct ReportSaveMessage: Equatable {
        var text: String
        var isError: Bool
    }
}

private struct DeviceVideoCodecCapabilityRow: View {
    var capability: TaptionCodecHardwareCapability

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(capability.videoCodec.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(capability.coreMediaCodecType ?? "Software catalog only")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            CapabilityBadge(label: "Decode", value: capability.hardwareDecodeSupported)
            CapabilityBadge(label: "Encode", value: capability.hardwareEncodeSupported)
        }
        .padding(10)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DeviceAudioCodecCapabilityRow: View {
    var capability: TaptionAudioCodecHardwareCapability

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(capability.audioCodec.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(copySummary)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            CapabilityBadge(
                label: "Decode",
                value: capability.nativeDecodeSupported,
                trueText: "Native",
                falseText: "SW"
            )
            CapabilityBadge(
                label: "Encode",
                value: capability.nativeEncodeSupported,
                trueText: "Native",
                falseText: "SW"
            )
        }
        .padding(10)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var copySummary: String {
        var containers: [String] = []
        if capability.mp4CopySupported {
            containers.append("MP4")
        }
        if capability.movCopySupported {
            containers.append("MOV")
        }
        guard !containers.isEmpty else {
            return "Transcode required for MP4/MOV"
        }
        return "Copy: \(containers.joined(separator: ", "))"
    }
}

private struct CapabilityBadge: View {
    var label: String
    var value: Bool?
    var trueText: String = "HW"
    var falseText: String = "SW"

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.54))

            Text(text)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(minWidth: 54)
    }

    private var text: String {
        switch value {
        case .some(true):
            return trueText
        case .some(false):
            return falseText
        case .none:
            return "N/A"
        }
    }

    private var color: Color {
        switch value {
        case .some(true):
            return TaptionTheme.accent
        case .some(false):
            return Color.white.opacity(0.66)
        case .none:
            return Color.white.opacity(0.42)
        }
    }
}

private struct SheetInfoCard: View {
    var title: String
    var rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(rows, id: \.0) { row in
                HStack(alignment: .top, spacing: 10) {
                    Text(row.0)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TaptionTheme.accent)
                        .frame(width: 52, alignment: .leading)

                    Text(row.1)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TaptionTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TaptionTheme.border, lineWidth: 1)
        )
    }
}
