import SwiftUI
import UIKit

enum HomeMenuSheet: String, Identifiable {
    case help
    case batterySettings
    case privacyAds
    case openSource
    case deviceInfo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .help:
            return "Help"
        case .batterySettings:
            return "Battery Settings"
        case .privacyAds:
            return "Privacy & Ads"
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
        case .batterySettings:
            BatterySettingsSheetContentView()
        case .privacyAds:
            PrivacyAdsSheetContentView()
        case .openSource:
            OpenSourceNoticesSheetContentView()
        case .deviceInfo:
            DeviceInfoSheetContentView()
        }
    }
}

private struct PrivacyAdsSheetContentView: View {
    @State private var consentStatus = "Checking"
    @State private var privacyOptionsStatus = "Checking"
    @State private var actionMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetInfoCard(
                    title: "Ad Privacy",
                    rows: [
                        ("Ads", "Non-personalized"),
                        ("Consent", consentStatus),
                        ("Privacy Options", privacyOptionsStatus)
                    ]
                )

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        presentPrivacyOptions()
                    } label: {
                        Label("Privacy Options", systemImage: "hand.raised")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TaptionTheme.accent)

                    Button {
                        reportAdIssue()
                    } label: {
                        Label("Report Ad Issue", systemImage: "exclamationmark.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(TaptionTheme.accent)

                    if let actionMessage {
                        Text(actionMessage)
                            .font(.caption)
                            .foregroundStyle(TaptionTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
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
            .padding(18)
        }
        .onAppear {
            AdPrivacyActionHandler.refreshConsentStatus()
            refreshStatus()
        }
    }

    private func presentPrivacyOptions() {
        actionMessage = "Opening privacy options..."
        Task { @MainActor in
            let didPresent = await AdPrivacyActionHandler.presentPrivacyOptions()
            refreshStatus()
            actionMessage = didPresent
                ? "Privacy options were opened."
                : "Privacy options are not available for this region or session yet."
        }
    }

    private func reportAdIssue() {
        actionMessage = AdPrivacyActionHandler.openAdReportEmail()
            ? "Opening your mail app for the ad report."
            : "Mail is unavailable. Contact help@taption.com with the ad details."
    }

    private func refreshStatus() {
        consentStatus = AdPrivacyActionHandler.consentStatusText()
        privacyOptionsStatus = AdPrivacyActionHandler.privacyOptionsStatusText()
    }
}

private enum AdPrivacyActionHandler {
    @MainActor
    static func refreshConsentStatus() {
        #if canImport(GoogleMobileAds)
        AdMobConsentManager.shared.refreshConsentStatusIfNeeded()
        #endif
    }

    @MainActor
    static func presentPrivacyOptions() async -> Bool {
        #if canImport(GoogleMobileAds)
        return await AdMobConsentManager.shared.presentPrivacyOptionsIfAvailable()
        #else
        return false
        #endif
    }

    @MainActor
    static func consentStatusText() -> String {
        #if canImport(GoogleMobileAds)
        return AdMobConsentManager.shared.consentStatusText
        #else
        return "Unavailable"
        #endif
    }

    @MainActor
    static func privacyOptionsStatusText() -> String {
        #if canImport(GoogleMobileAds)
        return AdMobConsentManager.shared.privacyOptionsStatusText
        #else
        return "Unavailable"
        #endif
    }

    @MainActor
    static func openAdReportEmail() -> Bool {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "help@taption.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Taption Encoder Ad Report"),
            URLQueryItem(
                name: "body",
                value: [
                    "Describe the inappropriate ad:",
                    "",
                    "Approximate time:",
                    "Advertiser or app name:",
                    "Screenshot attached:"
                ].joined(separator: "\n")
            )
        ]
        guard let url = components.url,
              UIApplication.shared.canOpenURL(url) else {
            return false
        }
        UIApplication.shared.open(url)
        return true
    }
}

private struct HelpSheetContentView: View {
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "00.00.00"
    private let deviceReport = HW_CodecCapabilityProbe.makeReport()

    private var videoCodecEntries: [HelpCodecEntry] {
        let entries = TaptionCodecRegistry.universalSourceCodecs.map { codec in
            HelpCodecEntry(
                name: codec.displayName,
                state: videoEntryState(for: codec)
            )
        }
        return sort(entries: entries)
    }

    private var audioCodecEntries: [HelpCodecEntry] {
        let entries = TaptionAudioCodecRoutePlanner.universalAudioCodecs.map { codec in
            let isAvailableNow = TaptionAudioCodecRoutePlanner
                .selectRoute(
                    sourceCodec: codec,
                    outputCodec: .aac,
                    outputContainer: .mp4
                )
                .isSupportedNow
            return HelpCodecEntry(
                name: codec.displayName,
                state: isAvailableNow ? .now : .planned
            )
        }
        return sort(entries: entries)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetInfoCard(
                    title: "Version",
                    rows: [
                        ("App", appVersion)
                    ]
                )

                SheetInfoCard(
                    title: "Containers",
                    rows: [
                        ("Input", TaptionLaunchSupportCatalog.supportedInputContainerSummary),
                        ("Output", TaptionLaunchSupportCatalog.supportedOutputContainerSummary)
                    ]
                )

                HelpLegendCard()

                HelpCodecSectionCard(
                    title: "Video Codecs",
                    entries: videoCodecEntries
                )

                HelpCodecSectionCard(
                    title: "Audio Codecs",
                    entries: audioCodecEntries
                )
            }
            .padding(18)
        }
    }

    private func sort(entries: [HelpCodecEntry]) -> [HelpCodecEntry] {
        entries.sorted { lhs, rhs in
            if lhs.state.priority != rhs.state.priority {
                return lhs.state.priority < rhs.state.priority
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func videoEntryState(for codec: TaptionVideoCodec) -> HelpCodecEntryState {
        switch deviceReport.runtimeAvailability(for: codec) {
        case .nowHardware:
            return .nowHardware
        case .nowSoftware:
            return .nowSoftware
        case .nowMixed:
            return .nowMixed
        case .needsHardware:
            return .needsHardware
        case .planned:
            return .planned
        case .unsupported:
            return .unsupported
        }
    }
}

private struct BatterySettingsSheetContentView: View {
    @State private var settings = BatteryEncodingSettings.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Battery Limit")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Spacer()

                        Text("\(settings.batteryLimitPercent)%")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(TaptionTheme.accent)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(settings.batteryLimitPercent) },
                            set: { updateBatteryLimit(Int($0.rounded())) }
                        ),
                        in: BatteryEncodingSettings.sliderRange,
                        step: 1
                    )
                    .tint(TaptionTheme.accent)

                    HStack {
                        Text("\(BatteryEncodingSettings.minimumLimitPercent)%")
                        Spacer()
                        Text("\(BatteryEncodingSettings.maximumLimitPercent)%")
                    }
                    .font(.caption)
                    .foregroundStyle(TaptionTheme.mutedText)

                    Text("Encoding cannot start at or below the selected battery level.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TaptionTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.border, lineWidth: 1)
                )

                Toggle(isOn: Binding(
                    get: { settings.powerConnectedOnly },
                    set: { updatePowerConnectedOnly($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Power Connected Only")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Encoding can start only while the device is connected to power.")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(TaptionTheme.accent)
                .padding(14)
                .background(TaptionTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.border, lineWidth: 1)
                )
            }
            .padding(18)
        }
    }

    private func updateBatteryLimit(_ limit: Int) {
        settings.batteryLimitPercent = BatteryEncodingSettings.clampLimitPercent(limit)
        settings.save()
    }

    private func updatePowerConnectedOnly(_ isEnabled: Bool) {
        settings.powerConnectedOnly = isEnabled
        settings.save()
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetInfoCard(
                    title: "Device",
                    rows: [
                        ("Model", report.modelDisplayName),
                        ("OS", "\(report.systemName) \(report.systemVersion)"),
                        ("Probe", "\(report.probeResolution.width)x\(report.probeResolution.height)"),
                        ("Checked", generatedAtText)
                    ]
                )

                SheetInfoCard(
                    title: "Input Scope",
                    rows: [
                        ("Now(HW)", "\(runtimeReadiness.nowHardwareVideoCodecs.count) video codecs"),
                        ("Now(SW)", "\(runtimeReadiness.nowSoftwareVideoCodecs.count) video codecs"),
                        ("Now(HW/SW)", "\(runtimeReadiness.nowMixedVideoCodecs.count) video codecs"),
                        ("Needs HW", "\(runtimeReadiness.needsHardwareVideoCodecs.count) hardware-gated codecs"),
                        ("Plan", "\(TaptionLaunchSupportCatalog.plannedInputVideoCodecs.count) roadmap codecs"),
                        ("Out", "H.265 / \(TaptionLaunchSupportCatalog.supportedOutputContainerSummary)")
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
                    Text("Video Codec Paths")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("Now(HW), Now(SW), mixed, hardware-gated, and roadmap-only input states are evaluated for this installed device.")
                        .font(.caption)
                        .foregroundStyle(TaptionTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)

                    if allVideoCapabilities.isEmpty {
                        Text("No video codec probe results are available.")
                            .font(.caption)
                            .foregroundStyle(TaptionTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(allVideoCapabilities) { capability in
                            DeviceVideoCodecCapabilityRow(
                                capability: capability,
                                runtimeAvailability: report.runtimeAvailability(for: capability.videoCodec),
                                routeSelection: report.routeSelection(for: capability.videoCodec)
                            )
                        }
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
                    Text("Audio Codec Paths")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("App and Device badges are evaluated separately for this installed device.")
                        .font(.caption)
                        .foregroundStyle(TaptionTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)

                    if allAudioCapabilities.isEmpty {
                        Text("No audio codec probe results are available.")
                            .font(.caption)
                            .foregroundStyle(TaptionTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(allAudioCapabilities) { capability in
                            DeviceAudioCodecCapabilityRow(capability: capability)
                        }
                    }
                }
                .padding(14)
                .background(TaptionTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.border, lineWidth: 1)
                )

                Text("This screen is focused on the installed device only. Planned input rows are roadmap entries and should not be treated as runnable in this build.")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    private var allVideoCapabilities: [TaptionCodecHardwareCapability] {
        report.videoCapabilities.sorted { lhs, rhs in
            let lhsPriority = videoSortPriority(lhs)
            let rhsPriority = videoSortPriority(rhs)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if lhs.isSupportedOnInstalledDevice != rhs.isSupportedOnInstalledDevice {
                return lhs.isSupportedOnInstalledDevice
                    && !rhs.isSupportedOnInstalledDevice
            }
            return lhs.videoCodec.displayName < rhs.videoCodec.displayName
        }
    }

    private var runtimeReadiness: TaptionLaunchInputRuntimeReadinessReport {
        report.runtimeInputReadinessReport
    }

    private func videoSortPriority(_ capability: TaptionCodecHardwareCapability) -> Int {
        switch report.runtimeAvailability(for: capability.videoCodec) {
        case .nowHardware:
            return 0
        case .nowMixed:
            return 1
        case .nowSoftware:
            return 2
        case .needsHardware:
            return 3
        case .planned:
            return 4
        case .unsupported:
            return 5
        }
    }

    private var allAudioCapabilities: [TaptionAudioCodecHardwareCapability] {
        report.audioCapabilities.sorted { lhs, rhs in
            if lhs.isInputSupportedByCurrentBuild != rhs.isInputSupportedByCurrentBuild {
                return lhs.isInputSupportedByCurrentBuild
                    && !rhs.isInputSupportedByCurrentBuild
            }
            if lhs.isSupportedOnInstalledDevice != rhs.isSupportedOnInstalledDevice {
                return lhs.isSupportedOnInstalledDevice
                    && !rhs.isSupportedOnInstalledDevice
            }
            return lhs.audioCodec.displayName < rhs.audioCodec.displayName
        }
    }

    private var generatedAtText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: report.generatedAt)
    }

    private func saveDeviceReport() {
        do {
            let freshReport = HW_CodecCapabilityProbe.makeReport()
            let snapshot = HW_DeviceCodecReportStore.makeSnapshot(
                report: freshReport,
                routeSimulationSummary: HW_CodecRouteSimulator.summary(),
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
                text: HomeErrorPresenter.cardDetail(
                    summary: "The device report could not be saved.",
                    recovery: "Try saving the report again from Device Info.",
                    error: error
                ),
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
    var runtimeAvailability: TaptionLaunchInputRuntimeAvailability
    var routeSelection: TaptionCodecRouteSelection

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(capability.videoCodec.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    CodecSupportPill(
                        label: "App",
                        text: appSupportText,
                        isActive: runtimeAvailability.isExecutableNow
                    )
                    CodecSupportPill(
                        label: "Device",
                        text: deviceSupportText,
                        isActive: capability.isSupportedOnInstalledDevice
                    )
                }

                Text(preferredPathSummary)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            CapabilityBadge(label: "Decode", value: capability.hardwareDecodeSupported, trueText: "HW", falseText: "SW")
            CapabilityBadge(label: "Encode", value: capability.hardwareEncodeSupported, trueText: "HW", falseText: "SW")
        }
        .padding(10)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var preferredPathSummary: String {
        switch runtimeAvailability {
        case .nowHardware:
            return "Current app input: \(routeSelection.displayTitle). Hardware path to H.265 output."
        case .nowSoftware:
            return "Current app input: \(routeSelection.displayTitle). Software path to H.265 output."
        case .nowMixed:
            return "Current app input: \(routeSelection.displayTitle). Mixed HW/SW path to H.265 output."
        case .needsHardware:
            return "Current app input: Needs Apple-native hardware for H.265 output on this device."
        case .planned:
            return "Roadmap input: H.265 output planned, not executable in this build."
        case .unsupported:
            break
        }

        switch (capability.hardwareDecodeSupported, capability.hardwareEncodeSupported) {
        case (.some(true), .some(true)):
            return "Device path: HW decode + HW encode"
        case (.some(true), .some(false)):
            return "Device path: HW decode + SW encode"
        case (.some(false), .some(true)):
            return "Device path: SW decode + HW encode"
        case (.some(false), .some(false)):
            return "Device path: SW only"
        case (.some(true), .none):
            return "Device path: HW decode. Encode probe unavailable"
        case (.none, .some(true)):
            return "Device path: HW encode. Decode probe unavailable"
        default:
            return capability.coreMediaCodecType == nil
                ? "Device path: Software catalog only"
                : "Device path: Probe unavailable"
        }
    }

    private var appSupportText: String {
        runtimeAvailability.displayName
    }

    private var deviceSupportText: String {
        capability.isSupportedOnInstalledDevice ? "HW" : "No HW"
    }

    private var rowBackground: Color {
        runtimeAvailability.isExecutableNow || capability.shouldHighlightInDeviceInfo
            ? Color.white.opacity(0.045)
            : Color.white.opacity(0.025)
    }

    private var titleColor: Color {
        runtimeAvailability.isExecutableNow || capability.shouldHighlightInDeviceInfo
            ? .white
            : Color.white.opacity(0.42)
    }

    private var detailColor: Color {
        runtimeAvailability.isExecutableNow || capability.shouldHighlightInDeviceInfo
            ? Color.white.opacity(0.52)
            : Color.white.opacity(0.32)
    }
}

private struct DeviceAudioCodecCapabilityRow: View {
    var capability: TaptionAudioCodecHardwareCapability

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(capability.audioCodec.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    CodecSupportPill(
                        label: "App",
                        text: capability.isInputSupportedByCurrentBuild ? "Now" : "No",
                        isActive: capability.isInputSupportedByCurrentBuild
                    )
                    CodecSupportPill(
                        label: "Device",
                        text: capability.isSupportedOnInstalledDevice ? "Native" : "No Native",
                        isActive: capability.isSupportedOnInstalledDevice
                    )
                }

                Text(preferredPathSummary)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
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
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var preferredPathSummary: String {
        if capability.isInputSupportedByCurrentBuild {
            return "Current app input: Supported now"
        }

        if capability.mp4CopySupported || capability.movCopySupported {
            return "Device path: Copy \(copyTargets)"
        }
        if capability.nativeDecodeSupported && capability.nativeEncodeSupported {
            return "Device path: Native decode + Native encode"
        }
        if capability.nativeDecodeSupported {
            return "Device path: Native decode + SW encode"
        }
        if capability.nativeEncodeSupported {
            return "Device path: SW decode + Native encode"
        }
        return "Device path: SW only"
    }

    private var copyTargets: String {
        var containers: [String] = []
        if capability.mp4CopySupported {
            containers.append("MP4")
        }
        if capability.movCopySupported {
            containers.append("MOV")
        }
        return containers.joined(separator: ", ")
    }

    private var rowBackground: Color {
        capability.shouldHighlightInDeviceInfo ? Color.white.opacity(0.045) : Color.white.opacity(0.025)
    }

    private var titleColor: Color {
        capability.shouldHighlightInDeviceInfo ? .white : Color.white.opacity(0.42)
    }

    private var detailColor: Color {
        capability.shouldHighlightInDeviceInfo ? Color.white.opacity(0.52) : Color.white.opacity(0.32)
    }
}

private struct CodecSupportPill: View {
    var label: String
    var text: String
    var isActive: Bool

    var body: some View {
        Text("\(label) \(text)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(isActive ? TaptionTheme.accent : Color.white.opacity(0.46))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isActive ? TaptionTheme.accent.opacity(0.13) : Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

private enum HelpCodecEntryState {
    case nowHardware
    case nowSoftware
    case nowMixed
    case now
    case needsHardware
    case planned
    case unsupported

    var label: String {
        switch self {
        case .nowHardware:
            return "HW"
        case .nowSoftware:
            return "SW"
        case .nowMixed:
            return "HW/SW"
        case .now:
            return "Now"
        case .needsHardware:
            return "Needs HW"
        case .planned:
            return "Planned"
        case .unsupported:
            return "No"
        }
    }

    var priority: Int {
        switch self {
        case .nowHardware:
            return 0
        case .nowMixed:
            return 1
        case .nowSoftware:
            return 2
        case .now:
            return 3
        case .needsHardware:
            return 4
        case .planned:
            return 5
        case .unsupported:
            return 6
        }
    }

    var titleOpacity: Double {
        switch self {
        case .nowHardware, .nowSoftware, .nowMixed, .now:
            return 0.92
        case .needsHardware:
            return 0.78
        case .planned:
            return 0.46
        case .unsupported:
            return 0.32
        }
    }

    var labelOpacity: Double {
        switch self {
        case .nowHardware, .nowSoftware, .nowMixed, .now:
            return 0.58
        case .needsHardware:
            return 0.50
        case .planned:
            return 0.34
        case .unsupported:
            return 0.28
        }
    }
}

private struct HelpCodecEntry: Identifiable {
    let id = UUID()
    var name: String
    var state: HelpCodecEntryState
}

private struct HelpLegendCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Video rows use this installed device: HW is native hardware, SW is software fallback, and Needs HW waits for Apple-native hardware.")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
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

private struct HelpCodecSectionCard: View {
    var title: String
    var entries: [HelpCodecEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            ForEach(entries) { entry in
                HStack(spacing: 10) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(entry.state.titleOpacity))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(entry.state.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(entry.state.labelOpacity))
                }
                .padding(.vertical, 2)
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
