import SwiftUI

struct EncodingProgressView: View {
    var state: HomeScreenState
    var displayDetail: String? = nil
    var canStartEncoding: Bool? = nil
    var startActionTitle: String = "Start"
    var showsSaveAction: Bool = false
    var saveActionTitle: String = "Save"
    var showsWorkAction: Bool = true
    var watchAdButtonTitle: String = "Watch Ad (+1 Star)"
    var showsWatchAdAction: Bool = true
    var canWatchAd: Bool = false
    var controlHeight: CGFloat = 44
    var contentScale: CGFloat = 1
    var reservesFailureLogArea: Bool = false
    var onStart: () -> Void
    var onSave: () -> Void
    var onWatchAd: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * contentScale) {
            if showsStatusDetails {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title)
                            .font(contentScale < 0.9 ? .subheadline.weight(.semibold) : .headline)
                            .foregroundStyle(TaptionTheme.primaryText)
                            .lineLimit(1)
                        detailMessage
                    }
                    Spacer(minLength: 0)
                }
            }

            if let resourceUsage = state.progress?.resourceUsage,
                   state.canCancel {
                    EncodingResourceUsageWidget(
                        resourceUsage: resourceUsage,
                        contentScale: contentScale
                    )
            }

            VStack(spacing: 8 * contentScale) {
                    if showsPrimaryAction {
                        actionButton
                    }
                    if showsWatchAdAction {
                        watchAdButton
                    }
            }
        }
        .frame(maxHeight: usesExpandedFailureLog ? .infinity : nil, alignment: .top)
        .layoutPriority(usesExpandedFailureLog ? 1 : 0)
    }

    private var showsStatusDetails: Bool {
        switch state {
        case .idle, .readyToStart: return false
        default: return true
        }
    }

    @ViewBuilder
    private var detailMessage: some View {
        if isFailedState {
            ScrollView(.vertical, showsIndicators: true) {
                Text(state.detail)
                    .font(contentScale < 0.9 ? .caption2 : .caption)
                    .foregroundStyle(TaptionTheme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: usesExpandedFailureLog ? .infinity : max(70, 96 * contentScale), alignment: .top)
            .padding(8)
            .background(TaptionTheme.elevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TaptionTheme.border, lineWidth: 1)
            )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if isCompletedState {
            Text(resolvedDetailText)
                .font(contentScale < 0.9 ? .caption2 : .caption)
                .foregroundStyle(TaptionTheme.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } else {
            Text(resolvedDetailText)
                .font(contentScale < 0.9 ? .caption : .subheadline)
                .foregroundStyle(TaptionTheme.mutedText)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
    }

    private var resolvedDetailText: String {
        displayDetail ?? state.detail
    }

    private var usesExpandedFailureLog: Bool {
        isFailedState && reservesFailureLogArea
    }

    private var isFailedState: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    private var isCompletedState: Bool {
        if case .completed = state {
            return true
        }
        return false
    }

    private var resolvedCanStartEncoding: Bool {
        canStartEncoding ?? state.canStartEncoding
    }

    private var showsPrimaryAction: Bool {
        showsWorkAction
            && (!state.isBusy
            || showsSaveAction
            || state.preparedEncodingReview != nil
            || state.canCancel)
    }

    @ViewBuilder
    private var actionButton: some View {
        if resolvedCanStartEncoding {
            Button {
                onStart()
            } label: {
                Label(startActionTitle, systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(TaptionTheme.accentButtonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(50, controlHeight))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .buttonStyle(.plain)
            .background(TaptionTheme.accent)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TaptionTheme.accent.opacity(0.65), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if showsSaveAction {
            Button {
                onSave()
            } label: {
                Label(saveActionTitle, systemImage: "square.and.arrow.down")
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(TaptionTheme.accentButtonText)
                    .frame(maxWidth: .infinity)
                    .frame(height: controlHeight)
            }
            .buttonStyle(.plain)
            .background(TaptionTheme.accent)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TaptionTheme.accent.opacity(0.65), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if !state.isBusy {
            Button {} label: {
                Label(startActionTitle, systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(TaptionTheme.disabledText)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(50, controlHeight))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .buttonStyle(.plain)
            .background(TaptionTheme.accent.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(true)
            .opacity(0.8)
        } else {
            Button {
                onCancel()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(state.canCancel ? TaptionTheme.accent : TaptionTheme.disabledText)
                    .frame(maxWidth: .infinity)
                    .frame(height: controlHeight)
            }
            .buttonStyle(.plain)
            .background(TaptionTheme.elevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(state.canCancel ? TaptionTheme.border : Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(!state.canCancel)
            .opacity(state.canCancel ? 1 : 0.48)
        }
    }

    private var watchAdButton: some View {
        Button {
            onWatchAd()
        } label: {
            Label(watchAdButtonTitle, systemImage: "star.fill")
                .font(contentScale < 0.9 ? .caption.weight(.semibold) : .body.weight(.semibold))
                .foregroundStyle(canWatchAd ? TaptionTheme.accentButtonText : TaptionTheme.disabledText)
                .frame(maxWidth: .infinity)
                .frame(height: controlHeight)
        }
        .buttonStyle(.plain)
        .background(canWatchAd ? TaptionTheme.accent : TaptionTheme.elevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(canWatchAd ? TaptionTheme.accent.opacity(0.65) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .disabled(!canWatchAd)
        .opacity(canWatchAd ? 1 : 0.58)
    }
}

private struct EncodingResourceUsageWidget: View {
    var resourceUsage: EncodingResourceUsageSnapshot
    var contentScale: CGFloat

    private var coreColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: 8 * contentScale),
            GridItem(.flexible(minimum: 0), spacing: 8 * contentScale)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * contentScale) {
            HStack(spacing: 8 * contentScale) {
                Label("Device CPU", systemImage: "cpu")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Label(resourceUsage.memoryPercentText, systemImage: "memorychip")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TaptionTheme.accent)
                    .lineLimit(1)
            }

            if resourceUsage.cpuCores.isEmpty {
                Text("CPU unavailable")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TaptionTheme.mutedText)
            } else {
                LazyVGrid(columns: coreColumns, alignment: .leading, spacing: 6 * contentScale) {
                    ForEach(resourceUsage.cpuCores) { core in
                        EncodingCoreUsageRow(core: core, contentScale: contentScale)
                    }
                }
            }

            HStack(spacing: 6 * contentScale) {
                Text("App Memory")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(TaptionTheme.mutedText)
                Spacer(minLength: 6)
                Text(resourceUsage.memoryUsageText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            if !resourceUsage.runtimeWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 6 * contentScale) {
                    Text("Runtime Warnings")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TaptionTheme.mutedText)
                    ForEach(resourceUsage.runtimeWarnings) { warning in
                        HStack(alignment: .top, spacing: 6 * contentScale) {
                            Image(systemName: iconName(for: warning))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(color(for: warning.severity))
                                .frame(width: max(14, 16 * contentScale), alignment: .center)
                            VStack(alignment: .leading, spacing: 2 * contentScale) {
                                Text(warning.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.86))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                Text(warning.message)
                                    .font(.caption2)
                                    .foregroundStyle(TaptionTheme.mutedText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 2 * contentScale)
            }
        }
        .padding(.horizontal, 10 * contentScale)
        .padding(.vertical, 8 * contentScale)
        .background(TaptionTheme.elevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TaptionTheme.accent.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func iconName(for warning: EncodingRuntimeWarning) -> String {
        switch warning.kind {
        case .thermal:
            return "thermometer.medium"
        case .memory:
            return "memorychip"
        case .battery:
            return "battery.25percent"
        case .runtime:
            return "hourglass"
        }
    }

    private func color(for severity: EncodingRuntimeWarningSeverity) -> Color {
        switch severity {
        case .notice:
            return TaptionTheme.accent
        case .warning:
            return TaptionTheme.coral
        case .critical:
            return TaptionTheme.coral
        }
    }
}

private struct EncodingCoreUsageRow: View {
    var core: EncodingCPUCoreUsage
    var contentScale: CGFloat

    var body: some View {
        HStack(spacing: 5 * contentScale) {
            Text("C\(core.index + 1)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TaptionTheme.mutedText)
                .frame(width: max(20, 22 * contentScale), alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(TaptionTheme.accent)
                        .frame(width: max(3, proxy.size.width * core.fraction))
                }
            }
            .frame(height: 5)

            Text(core.percentText)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.78))
                .frame(width: max(32, 34 * contentScale), alignment: .trailing)
        }
        .frame(minHeight: 14 * contentScale)
    }
}
