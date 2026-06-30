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
        ProgressCard {
            VStack(alignment: .leading, spacing: 10 * contentScale) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.title)
                            .font(contentScale < 0.9 ? .subheadline.weight(.semibold) : .headline)
                            .foregroundStyle(Color.white.opacity(0.92))
                            .lineLimit(1)
                        detailMessage
                    }
                    Spacer(minLength: 0)
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
        }
        .frame(maxHeight: usesExpandedFailureLog ? .infinity : nil, alignment: .top)
        .layoutPriority(usesExpandedFailureLog ? 1 : 0)
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
            && (resolvedCanStartEncoding
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
                Label(startActionTitle, systemImage: "play.fill")
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: controlHeight)
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
                    .foregroundStyle(.white)
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
        } else if state.preparedEncodingReview != nil {
            Button {} label: {
                Label(startActionTitle, systemImage: "play.fill")
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(TaptionTheme.disabledText)
                    .frame(maxWidth: .infinity)
                    .frame(height: controlHeight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .buttonStyle(.plain)
            .background(TaptionTheme.elevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(true)
            .opacity(0.48)
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
                .foregroundStyle(canWatchAd ? .white : TaptionTheme.disabledText)
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
