import SwiftUI

struct EncodingProgressView: View {
    var state: HomeScreenState
    var controlHeight: CGFloat = 44
    var contentScale: CGFloat = 1
    var onStart: () -> Void
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

                actionButton
            }
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
            .frame(maxHeight: max(70, 96 * contentScale))
            .padding(8)
            .background(TaptionTheme.elevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TaptionTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Text(state.detail)
                .font(contentScale < 0.9 ? .caption : .subheadline)
                .foregroundStyle(TaptionTheme.mutedText)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
    }

    private var isFailedState: Bool {
        if case .failed = state {
            return true
        }
        return false
    }

    @ViewBuilder
    private var actionButton: some View {
        if state.canStartEncoding {
            Button {
                onStart()
            } label: {
                Label("Start", systemImage: "play.fill")
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
                Label("Start", systemImage: "play.fill")
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(TaptionTheme.disabledText)
                    .frame(maxWidth: .infinity)
                    .frame(height: controlHeight)
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

}
