import SwiftUI
import SwiftVLC
import UIKit

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
        .disabled(!file.isInteractable)
        .opacity(file.isInteractable ? 1 : 0.58)
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 9 * contentScale) {
            QueueFileThumbnailView(
                sourceURL: file.thumbnailSourceURL,
                canAttemptThumbnail: file.isInteractable,
                contentScale: contentScale
            )

            VStack(alignment: .leading, spacing: 7 * contentScale) {
                headerRow
                selectedDetailSection
                progressSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * contentScale) {
            Text(file.fileName)
                .font(contentScale < 0.9 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(file.isInteractable ? Color.white.opacity(0.92) : TaptionTheme.disabledText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 4)

            Text(file.statusText)
                .font(contentScale < 0.9 ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private var selectedDetailSection: some View {
        if file.isSelected {
            if let info = file.videoInfo {
                infoGrid(info)
            } else if let detailText = file.detailText {
                Text(detailText)
                    .font(contentScale < 0.9 ? .caption2 : .caption)
                    .foregroundStyle(file.isInteractable ? TaptionTheme.mutedText : TaptionTheme.disabledText)
                    .lineLimit(detailLineLimit)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: detailLineLimit == nil)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
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

    private var cardBackground: Color {
        guard file.isInteractable else {
            return TaptionTheme.elevatedSurface.opacity(0.55)
        }
        return file.isSelected ? TaptionTheme.selectedSurface : TaptionTheme.elevatedSurface
    }

    private var cardBorder: Color {
        guard file.isInteractable else {
            return Color.white.opacity(0.08)
        }
        return file.isSelected ? Color.white.opacity(0.35) : TaptionTheme.border
    }

    private var statusColor: Color {
        if !file.isInteractable {
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
        file.isInteractable ? Color.white.opacity(0.88) : TaptionTheme.disabledText
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

private struct QueueFileThumbnailView: View {
    var sourceURL: URL?
    var canAttemptThumbnail: Bool
    var contentScale: CGFloat

    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false
    @State private var didFail = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.34))

            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(max(0.6, contentScale * 0.72))
                    .tint(TaptionTheme.mutedText)
            } else {
                Image(systemName: didFail ? "film" : "photo.on.rectangle.angled")
                    .font(.system(size: 16 * contentScale, weight: .semibold))
                    .foregroundStyle(TaptionTheme.mutedText)
            }
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .task(id: thumbnailTaskID) {
            await loadThumbnail()
        }
        .accessibilityHidden(true)
    }

    private var thumbnailTaskID: String {
        "\(canAttemptThumbnail)-\(sourceURL?.absoluteString ?? "none")"
    }

    private var thumbnailSize: CGSize {
        CGSize(
            width: max(48, 58 * contentScale),
            height: max(34, 42 * contentScale)
        )
    }

    @MainActor
    private func loadThumbnail() async {
        thumbnailImage = nil
        didFail = false

        guard canAttemptThumbnail,
              let sourceURL else {
            isLoading = false
            return
        }

        isLoading = true
        defer {
            isLoading = false
        }

        do {
            thumbnailImage = try await QueueVideoThumbnailRenderer.thumbnailImage(for: sourceURL)
        } catch {
            if !Task.isCancelled {
                didFail = true
                AppLogger.debug(
                    "Queue thumbnail generation failed",
                    category: .ui,
                    metadata: [
                        "name": sourceURL.lastPathComponent,
                        "error": String(describing: error)
                    ]
                )
            }
        }
    }
}

enum QueueVideoThumbnailRenderer {
    static let defaultPixelSize = CGSize(width: 192, height: 108)

    @MainActor
    static func thumbnailImage(
        for sourceURL: URL,
        pixelSize: CGSize = defaultPixelSize,
        timeout: Duration = .seconds(6)
    ) async throws -> UIImage {
        do {
            return try await mediaThumbnailImage(for: sourceURL, pixelSize: pixelSize, timeout: timeout)
        } catch {
            AppLogger.warning(
                "Queue thumbnail media thumbnail failed; using fallback",
                category: .ui,
                metadata: [
                    "name": sourceURL.lastPathComponent,
                    "error": String(describing: error)
                ]
            )
            return fallbackThumbnailImage(for: sourceURL, pixelSize: pixelSize)
        }
    }

    @MainActor
    private static func mediaThumbnailImage(
        for sourceURL: URL,
        pixelSize: CGSize,
        timeout: Duration
    ) async throws -> UIImage {
        let media = try Media(url: sourceURL)
        QueuePreviewPlayerFactory.configureSoftwareDecodeOptions(on: media, sourceURL: sourceURL, allowsAudio: false)

        let data = try await media.thumbnail(
            at: .seconds(0.2),
            width: Int(max(pixelSize.width.rounded(), 1)),
            height: Int(max(pixelSize.height.rounded(), 1)),
            crop: true,
            seekMode: .fast,
            timeout: timeout,
            instance: QueuePreviewPlayerFactory.softwareDecodeInstance
        )
        guard let image = UIImage(data: data) else {
            throw QueueVideoThumbnailRendererError.mediaThumbnailFailed("UIImage decode failed")
        }
        return image
    }

    @MainActor
    private static func fallbackThumbnailImage(for sourceURL: URL, pixelSize: CGSize) -> UIImage {
        let size = CGSize(
            width: max(pixelSize.width.rounded(), 48),
            height: max(pixelSize.height.rounded(), 27)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1).setFill()
            rendererContext.fill(bounds)

            UIColor(red: 0.19, green: 0.23, blue: 0.30, alpha: 1).setFill()
            rendererContext.fill(bounds.insetBy(dx: 1, dy: 1))

            let circleRect = CGRect(
                x: (size.width - 38) / 2,
                y: (size.height - 38) / 2 - 6,
                width: 38,
                height: 38
            )
            UIColor.white.withAlphaComponent(0.18).setFill()
            UIBezierPath(ovalIn: circleRect).fill()

            let playPath = UIBezierPath()
            playPath.move(to: CGPoint(x: circleRect.midX - 5, y: circleRect.midY - 9))
            playPath.addLine(to: CGPoint(x: circleRect.midX - 5, y: circleRect.midY + 9))
            playPath.addLine(to: CGPoint(x: circleRect.midX + 10, y: circleRect.midY))
            playPath.close()
            UIColor.white.withAlphaComponent(0.82).setFill()
            playPath.fill()

            let extensionText = fallbackLabel(for: sourceURL)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.74),
                .paragraphStyle: paragraph
            ]
            let textRect = CGRect(x: 8, y: size.height - 24, width: size.width - 16, height: 16)
            extensionText.draw(with: textRect, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        }
    }

    private static func fallbackLabel(for sourceURL: URL) -> String {
        let ext = sourceURL.pathExtension.uppercased()
        if ext.isEmpty {
            return "VIDEO"
        }
        return String(ext.prefix(8))
    }
}

enum QueueVideoThumbnailRendererError: Error, LocalizedError, Equatable {
    case mediaThumbnailFailed(String)

    var errorDescription: String? {
        switch self {
        case .mediaThumbnailFailed(let error):
            return "media.thumbnail failed: \(error)"
        }
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
