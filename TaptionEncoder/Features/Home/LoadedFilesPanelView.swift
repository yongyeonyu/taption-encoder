import SwiftUI

struct LoadedFilesPanelView: View {
    var files: [EncodingFileCardSnapshot]
    var contentScale: CGFloat
    var panelHeight: CGFloat
    var onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if files.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8 * contentScale) {
                        ForEach(files) { file in
                            EncodingFileCardView(
                                file: file,
                                contentScale: contentScale,
                                onSelect: { onSelect(file.id) }
                            )
                        }
                    }
                    .padding(8 * contentScale)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .background(TaptionTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TaptionTheme.strongBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 8 * contentScale) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 24 * contentScale, weight: .semibold))
                .foregroundStyle(TaptionTheme.mutedText)
            Text("Imported files appear here and are analyzed automatically.")
                .font(contentScale < 0.9 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(TaptionTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12 * contentScale)
    }
}

private struct EncodingFileCardView: View {
    var file: EncodingFileCardSnapshot
    var contentScale: CGFloat
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            cardContent
        }
        .buttonStyle(.plain)
        .disabled(!file.isEnabled)
        .opacity(file.isEnabled ? 1 : 0.58)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 7 * contentScale) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * contentScale) {
                Image(systemName: file.isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 15 * contentScale, weight: .semibold))
                    .foregroundStyle(file.isEnabled && file.isSelected ? Color.white.opacity(0.92) : TaptionTheme.disabledText)
                    .frame(width: 20 * contentScale)

                Text(file.fileName)
                    .font(contentScale < 0.9 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(file.isEnabled ? Color.white.opacity(0.92) : TaptionTheme.disabledText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 4)

                Text(file.statusText)
                    .font(contentScale < 0.9 ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            if file.isSelected {
                if let info = file.videoInfo {
                    infoGrid(info)
                } else if let detailText = file.detailText {
                    Text(detailText)
                        .font(contentScale < 0.9 ? .caption2 : .caption)
                        .foregroundStyle(file.isEnabled ? TaptionTheme.mutedText : TaptionTheme.disabledText)
                        .lineLimit(detailLineLimit)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: detailLineLimit == nil)
                        .textSelection(.enabled)
                }
            }

            if let progress = file.progress {
                VStack(alignment: .leading, spacing: 4 * contentScale) {
                    HStack(spacing: 8 * contentScale) {
                        Text(progress.stageTitle)
                        Spacer(minLength: 4)
                        Text(progress.percentText)
                    }
                    .font((contentScale < 0.9 ? Font.caption2 : Font.caption).monospacedDigit())
                    .foregroundStyle(TaptionTheme.mutedText)

                    ProgressView(value: progress.fractionCompleted)
                        .progressViewStyle(.linear)
                        .tint(TaptionTheme.accent)

                    HStack(spacing: 10 * contentScale) {
                        Label(formatTime(progress.elapsedTime), systemImage: "timer")
                        Label(formatRemainingTime(progress.estimatedRemainingTime), systemImage: "hourglass")
                    }
                    .font((contentScale < 0.9 ? Font.caption2 : Font.caption).monospacedDigit())
                    .foregroundStyle(TaptionTheme.mutedText)
                }
            }
        }
        .padding(9 * contentScale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var cardBackground: Color {
        guard file.isEnabled else {
            return TaptionTheme.elevatedSurface.opacity(0.55)
        }
        return file.isSelected ? TaptionTheme.selectedSurface : TaptionTheme.elevatedSurface
    }

    private var cardBorder: Color {
        guard file.isEnabled else {
            return Color.white.opacity(0.08)
        }
        return file.isSelected ? Color.white.opacity(0.35) : TaptionTheme.border
    }

    private var statusColor: Color {
        if !file.isEnabled {
            return TaptionTheme.disabledText
        }
        return file.isSelected || file.isActive ? Color.white.opacity(0.92) : TaptionTheme.mutedText
    }

    private var detailLineLimit: Int? {
        switch file.statusText {
        case "Failed", "Unreadable", "Not supported yet":
            return nil
        default:
            return 2
        }
    }

    private func infoGrid(_ info: LoadedVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 4 * contentScale) {
            Text("Codec Info (Video / Audio)")
                .font(contentScale < 0.9 ? .caption.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(TaptionTheme.mutedText)

            HStack(spacing: 8 * contentScale) {
                infoCell("Time", info.duration)
                infoCell("Resolution", info.resolution)
            }
            HStack(spacing: 8 * contentScale) {
                infoCell("FPS", info.frameRate)
                infoCell("File", info.fileSize)
            }


            Divider()
                .overlay(TaptionTheme.border)



            HStack(spacing: 8 * contentScale) {
                infoCell("Video In", info.inputSummary)
                infoCell("Video Out", info.outputSummary)
            }
            HStack(spacing: 8 * contentScale) {
                infoCell("Audio In", info.audio)
                infoCell("Audio Out", info.audioOutputSummary)
            }
        }
    }

    private func infoCell(_ title: String, _ value: String, valueColor: Color? = nil) -> some View {
        HStack(spacing: 4 * contentScale) {
            Text(title)
                .font(contentScale < 0.9 ? .caption2.weight(.semibold) : .caption2.weight(.semibold))
                .foregroundStyle(TaptionTheme.mutedText)
            Text(value)
                .font(contentScale < 0.9 ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(valueColor ?? defaultValueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var defaultValueColor: Color {
        file.isEnabled ? Color.white.opacity(0.88) : TaptionTheme.disabledText
    }

    private func supportValueColor(isSupported: Bool) -> Color {
        guard file.isEnabled else {
            return TaptionTheme.disabledText
        }
        return isSupported ? Color.white.opacity(0.92) : TaptionTheme.disabledText
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        let minutes = wholeSeconds / 60
        let seconds = wholeSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func formatRemainingTime(_ seconds: TimeInterval?) -> String {
        guard let seconds else {
            return "--:--"
        }
        return formatTime(seconds)
    }
}

private struct FolderQueueSummaryView: View {
    var snapshot: FolderQueueSnapshot
    var contentScale: CGFloat

    var body: some View {
        HStack(spacing: 8 * contentScale) {
            Label(snapshot.statusText, systemImage: "folder.badge.gearshape")
                .font(contentScale < 0.9 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            if let fileName = snapshot.currentFileName {
                Text(fileName)
                    .font(contentScale < 0.9 ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8 * contentScale)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct VideoInfoSummaryView: View {
    var info: LoadedVideoInfo
    var contentScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * contentScale) {
            Label(info.fileName, systemImage: "doc.richtext")
                .font(contentScale < 0.9 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(spacing: 8) {
                infoPill(title: "Input", value: info.inputSummary)
                infoPill(title: "Size", value: info.resolution)
            }

            HStack(spacing: 8) {
                infoPill(title: "FPS", value: info.frameRate)
                infoPill(title: "Time", value: info.duration)
            }

            HStack(spacing: 8) {
                infoPill(title: "Audio", value: info.audio)
                infoPill(title: "File", value: info.fileSize)
            }

            HStack(spacing: 8) {
                infoPill(title: "Video", value: info.codecPathBadge)
                infoPill(title: "Audio", value: info.audioPathBadge)
            }

            HStack(spacing: 8) {
                infoPill(title: "Out", value: info.outputSummary)
                infoPill(title: "Audio Out", value: info.audioOutputSummary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10 * contentScale)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func infoPill(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(contentScale < 0.9 ? .caption2.weight(.semibold) : .caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(contentScale < 0.9 ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
