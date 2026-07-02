import SwiftUI
import SwiftVLC
import UIKit
import UniformTypeIdentifiers

private enum QueueCardSwipeIntent {
    case none
    case select
    case delete
}

private enum QueueAutoScrollDirection: Equatable {
    case up
    case down
}

private struct QueueAutoScrollRequest: Equatable {
    var targetID: String
    var direction: QueueAutoScrollDirection
}

struct LoadedFilesPanelView: View {
    var files: [EncodingFileCardSnapshot]
    var contentScale: CGFloat
    var panelHeight: CGFloat
    var onSelect: (String) -> Void
    var onPlay: (String) -> Void
    var onToggleSelection: (String) -> Void
    var onDelete: (String) -> Void
    var onMove: (String, String) -> Void
    var onMoveEnded: () -> Void

    @State private var draggedFileID: String?
    @State private var pressedGroupAnchorID: String?
    @State private var hoveredDropTargetID: String?
    @State private var lastAutoScrollAt: Date = .distantPast
    @State private var lastAutoScrollRequest: QueueAutoScrollRequest?

    private var selectedFileCount: Int {
        files.filter(\.isMultiSelected).count
    }

    private var isGroupPressActive: Bool {
        pressedGroupAnchorID != nil && selectedFileCount > 1
    }

    var body: some View {
        VStack(spacing: 0) {
            if files.isEmpty {
                emptyState
            } else {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 8 * contentScale) {
                            ForEach(files) { file in
                                QueueFileDropContainer(
                                    targetID: file.id,
                                    draggedFileID: $draggedFileID,
                                    contentScale: contentScale,
                                    onMove: onMove,
                                    onMoveEnded: {
                                        onMoveEnded()
                                        withAnimation(queueSpringAnimation) {
                                            pressedGroupAnchorID = nil
                                        }
                                        hoveredDropTargetID = nil
                                    },
                                    onAutoScroll: { targetID, direction in
                                        autoScrollQueue(
                                            from: targetID,
                                            direction: direction,
                                            proxy: scrollProxy
                                        )
                                    },
                                    onHover: { targetID in
                                        hoveredDropTargetID = targetID
                                    }
                                ) {
                                    EncodingFileCardView(
                                        file: file,
                                        contentScale: contentScale,
                                        selectedGroupCount: selectedFileCount,
                                        isGroupPressAnchor: pressedGroupAnchorID == file.id,
                                        isBundledByGroupPress: isGroupPressActive
                                            && file.isMultiSelected
                                            && pressedGroupAnchorID != file.id,
                                        onSelect: { onSelect(file.id) },
                                        onPlay: { onPlay(file.id) },
                                        onToggleSelection: { onToggleSelection(file.id) },
                                        onDelete: { onDelete(file.id) },
                                        onDragStarted: {
                                            draggedFileID = file.id
                                            if file.isMultiSelected && selectedFileCount > 1 {
                                                withAnimation(queueSpringAnimation) {
                                                    pressedGroupAnchorID = file.id
                                                }
                                            }
                                        },
                                        onGroupPressChanged: { isPressing in
                                            guard file.isMultiSelected && selectedFileCount > 1 else {
                                                return
                                            }
                                            withAnimation(queueSpringAnimation) {
                                                pressedGroupAnchorID = isPressing ? file.id : nil
                                            }
                                        }
                                    )
                                    .id(file.id)
                                    .zIndex(pressedGroupAnchorID == file.id ? 2 : 0)
                                }
                            }
                        }
                        .animation(queueSpringAnimation, value: files.map(\.id))
                        .animation(queueSpringAnimation, value: pressedGroupAnchorID)
                        .padding(8 * contentScale)
                    }
                    .onDrop(
                        of: [UTType.plainText],
                        delegate: QueuePanelDropDelegate(
                            panelHeight: panelHeight,
                            contentScale: contentScale,
                            draggedFileID: $draggedFileID,
                            anchorTargetID: hoveredDropTargetID,
                            onMoveEnded: {
                                onMoveEnded()
                                withAnimation(queueSpringAnimation) {
                                    pressedGroupAnchorID = nil
                                }
                                hoveredDropTargetID = nil
                            },
                            onAutoScroll: { direction in
                                guard let anchorID = hoveredDropTargetID ?? draggedFileID else {
                                    return
                                }
                                autoScrollQueue(
                                    from: anchorID,
                                    direction: direction,
                                    proxy: scrollProxy
                                )
                            }
                        )
                    )
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

    private var queueSpringAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.84)
    }

    private func autoScrollQueue(
        from targetID: String,
        direction: QueueAutoScrollDirection,
        proxy: ScrollViewProxy
    ) {
        guard draggedFileID != nil,
              let targetIndex = files.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        hoveredDropTargetID = targetID

        let destinationIndex: Int
        let anchor: UnitPoint
        switch direction {
        case .up:
            destinationIndex = max(files.startIndex, targetIndex - 1)
            anchor = .top
        case .down:
            destinationIndex = min(files.index(before: files.endIndex), targetIndex + 1)
            anchor = .bottom
        }
        guard destinationIndex != targetIndex else {
            return
        }

        let request = QueueAutoScrollRequest(targetID: targetID, direction: direction)
        let now = Date()
        guard request != lastAutoScrollRequest
            || now.timeIntervalSince(lastAutoScrollAt) >= 0.16 else {
            return
        }

        lastAutoScrollRequest = request
        lastAutoScrollAt = now
        withAnimation(.linear(duration: 0.14)) {
            proxy.scrollTo(files[destinationIndex].id, anchor: anchor)
        }
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
    var selectedGroupCount: Int
    var isGroupPressAnchor: Bool
    var isBundledByGroupPress: Bool
    var onSelect: () -> Void
    var onPlay: () -> Void
    var onToggleSelection: () -> Void
    var onDelete: () -> Void
    var onDragStarted: () -> Void
    var onGroupPressChanged: (Bool) -> Void

    @State private var swipeOffset: CGFloat = 0
    @State private var isSwipeGestureActive = false
    @State private var isCardPressActive = false

    var body: some View {
        ZStack {
            swipeActionBackground
            groupStackLayer
            cardContent
                .offset(x: swipeOffset)
                .scaleEffect(cardScale)
                .opacity(cardOpacity)
            deleteSwipeTrashOverlay
        }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .simultaneousGesture(swipeGesture)
            .onTapGesture {
                guard !isSwipeGestureActive, abs(swipeOffset) < 1 else {
                    return
                }
                onSelect()
            }
            .onLongPressGesture(
                minimumDuration: 0.22,
                maximumDistance: 22,
                pressing: { isPressing in
                    isCardPressActive = isPressing
                    onGroupPressChanged(isPressing)
                },
                perform: {}
            )
            .onDrag {
                onDragStarted()
                return NSItemProvider(object: file.id as NSString)
            } preview: {
                dragPreview
            }
            .animation(queueSpringAnimation, value: swipeOffset)
            .animation(queueSpringAnimation, value: isGroupPressAnchor)
            .animation(queueSpringAnimation, value: isBundledByGroupPress)
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 9 * contentScale) {
            QueueFileThumbnailView(
                sourceURL: file.thumbnailSourceURL,
                canAttemptThumbnail: file.isInteractable,
                playbackGestureEnabled: thumbnailPlaybackEnabled,
                contentScale: contentScale,
                onPlay: onPlay
            )

            VStack(alignment: .leading, spacing: 7 * contentScale) {
                headerRow
                informationSection
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
            if file.isMultiSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13 * contentScale, weight: .bold))
                    .foregroundStyle(TaptionTheme.accent)
            }

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
    private var informationSection: some View {
        if let info = file.videoInfo {
            infoGrid(info)
        } else if file.isSelected, let detailText = file.detailText {
            Text(detailText)
                .font(contentScale < 0.9 ? .caption2 : .caption)
                .foregroundStyle(file.isInteractable ? TaptionTheme.mutedText : TaptionTheme.disabledText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: infoTableHeight, alignment: .center)
        } else {
            Color.clear
                .frame(height: infoTableHeight)
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
        if file.isMultiSelected {
            return TaptionTheme.selectedSurface.opacity(0.95)
        }
        if file.isSelected {
            return TaptionTheme.selectedSurface.opacity(file.isInteractable ? 1 : 0.74)
        }
        return file.isInteractable ? TaptionTheme.elevatedSurface : TaptionTheme.elevatedSurface.opacity(0.55)
    }

    private var cardBorder: Color {
        if file.isMultiSelected {
            return TaptionTheme.accent.opacity(0.82)
        }
        if file.isSelected {
            return TaptionTheme.accent
        }
        return file.isInteractable ? TaptionTheme.border : Color.white.opacity(0.08)
    }

    private var statusColor: Color {
        if file.isStarLimited || file.statusText == "Need Stars" {
            return starLimitedStatusColor
        }
        if !file.isInteractable {
            return TaptionTheme.disabledText
        }
        return file.isSelected || file.isActive ? Color.white.opacity(0.92) : TaptionTheme.mutedText
    }

    private var starLimitedStatusColor: Color {
        Color(red: 0.96, green: 0.18, blue: 0.22)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.15 else {
                    return
                }
                isSwipeGestureActive = true
                swipeOffset = clampedSwipeOffset(horizontal)
            }
            .onEnded { value in
                let horizontal = clampedSwipeOffset(value.translation.width)
                let vertical = value.translation.height
                guard abs(horizontal) > 46,
                      abs(horizontal) > abs(vertical) * 1.35 else {
                    resetSwipeOffset()
                    return
                }

                if horizontal < 0, abs(horizontal) >= actionThreshold {
                    onToggleSelection()
                } else if horizontal >= actionThreshold {
                    onDelete()
                }
                resetSwipeOffset()
            }
    }

    @ViewBuilder
    private var swipeActionBackground: some View {
        let progress = min(1, abs(swipeOffset) / swipeLimit)
        HStack {
            if swipeOffset > 0 {
                Color.clear
            } else if swipeOffset < 0 {
                Spacer(minLength: 0)
                swipeActionLabel(icon: "checkmark.circle.fill", text: "Select", color: TaptionTheme.accent)
            }
        }
        .padding(.horizontal, 14 * contentScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(swipeBackgroundColor.opacity(0.16 + 0.24 * progress))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(progress)
    }

    @ViewBuilder
    private var deleteSwipeTrashOverlay: some View {
        let progress = min(1, max(0, swipeOffset) / swipeLimit)
        if swipeOffset > 0 {
            Image(systemName: "trash.fill")
                .font(.system(size: max(24, 32 * contentScale), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: max(48, 58 * contentScale), height: max(48, 58 * contentScale))
                .background(deleteColor)
                .clipShape(Circle())
                .shadow(color: deleteColor.opacity(0.35), radius: 8, x: 0, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 14 * contentScale)
                .opacity(progress)
                .scaleEffect(0.82 + (0.18 * progress))
                .allowsHitTesting(false)
        }
    }

    private func swipeActionLabel(icon: String, text: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(contentScale < 0.9 ? .caption.weight(.bold) : .subheadline.weight(.bold))
            .foregroundStyle(color)
            .labelStyle(.iconOnly)
            .frame(width: 34 * contentScale, height: 34 * contentScale)
            .background(color.opacity(0.16))
            .clipShape(Circle())
    }

    @ViewBuilder
    private var groupStackLayer: some View {
        if isGroupPressAnchor && selectedGroupCount > 1 {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TaptionTheme.selectedSurface.opacity(0.64))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.accent.opacity(0.34), lineWidth: 1)
                )
                .offset(x: -7 * contentScale, y: -7 * contentScale)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(TaptionTheme.selectedSurface.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(TaptionTheme.accent.opacity(0.22), lineWidth: 1)
                )
                .offset(x: -13 * contentScale, y: -13 * contentScale)
        }
    }

    private var dragPreview: some View {
        ZStack(alignment: .topTrailing) {
            previewCardContent
                .frame(width: 300 * contentScale)
            if file.isMultiSelected && selectedGroupCount > 1 {
                Text("\(selectedGroupCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(TaptionTheme.accent)
                    .clipShape(Capsule())
                    .padding(6)
            }
        }
    }

    private var previewCardContent: some View {
        HStack(alignment: .top, spacing: 9 * contentScale) {
            QueueFileThumbnailView(
                sourceURL: file.thumbnailSourceURL,
                canAttemptThumbnail: file.isInteractable,
                playbackGestureEnabled: false,
                contentScale: contentScale
            )

            VStack(alignment: .leading, spacing: 7 * contentScale) {
                headerRow
                informationSection
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

    private var visualSwipeIntent: QueueCardSwipeIntent {
        if swipeOffset > visualIntentThreshold {
            return .delete
        }
        if swipeOffset < -visualIntentThreshold {
            return .select
        }
        return .none
    }

    private var swipeBackgroundColor: Color {
        visualSwipeIntent == .delete ? deleteColor : TaptionTheme.accent
    }

    private var cardScale: CGFloat {
        if isGroupPressAnchor {
            return 1.025
        }
        return isBundledByGroupPress ? 0.94 : 1
    }

    private var cardOpacity: Double {
        let baseOpacity = file.isInteractable ? 1 : 0.58
        return isBundledByGroupPress ? 0.46 : baseOpacity
    }

    private var thumbnailPlaybackEnabled: Bool {
        !isSwipeGestureActive
            && !isCardPressActive
            && !isBundledByGroupPress
            && abs(swipeOffset) < 1
    }

    private var swipeLimit: CGFloat {
        max(72, 112 * contentScale)
    }

    private var actionThreshold: CGFloat {
        max(58, 72 * contentScale)
    }

    private var visualIntentThreshold: CGFloat {
        max(18, 24 * contentScale)
    }

    private var deleteColor: Color {
        Color(red: 0.96, green: 0.18, blue: 0.22)
    }

    private var queueSpringAnimation: Animation {
        .spring(response: 0.26, dampingFraction: 0.82)
    }

    private func clampedSwipeOffset(_ offset: CGFloat) -> CGFloat {
        min(swipeLimit, max(-swipeLimit, offset))
    }

    private func resetSwipeOffset() {
        withAnimation(queueSpringAnimation) {
            swipeOffset = 0
        }
        isSwipeGestureActive = false
    }

    private func infoGrid(_ info: LoadedVideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 5 * contentScale) {
            HStack(spacing: 8 * contentScale) {
                tableValue(info.duration)
                tableValue(info.frameRate)
                tableValue(info.resolution)
                tableValue(info.fileSize)
            }

            HStack(spacing: 10 * contentScale) {
                tableValue(inputVideoCodecText(info.inputSummary))
                tableValue(info.audio)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: infoTableHeight, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private func tableValue(_ value: String) -> some View {
        Text(value)
            .font(contentScale < 0.9 ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(defaultValueColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inputVideoCodecText(_ inputSummary: String) -> String {
        inputSummary
            .components(separatedBy: " / ")
            .first
            .map { $0.isEmpty ? inputSummary : $0 } ?? inputSummary
    }

    private var infoTableHeight: CGFloat {
        max(44, 50 * contentScale)
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

private struct QueueFileDropContainer<Content: View>: View {
    let targetID: String
    @Binding var draggedFileID: String?
    var contentScale: CGFloat
    var onMove: (String, String) -> Void
    var onMoveEnded: () -> Void
    var onAutoScroll: (String, QueueAutoScrollDirection) -> Void
    var onHover: (String) -> Void

    @State private var targetHeight: CGFloat = 0

    private var content: Content

    init(
        targetID: String,
        draggedFileID: Binding<String?>,
        contentScale: CGFloat,
        onMove: @escaping (String, String) -> Void,
        onMoveEnded: @escaping () -> Void,
        onAutoScroll: @escaping (String, QueueAutoScrollDirection) -> Void,
        onHover: @escaping (String) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.targetID = targetID
        self._draggedFileID = draggedFileID
        self.contentScale = contentScale
        self.onMove = onMove
        self.onMoveEnded = onMoveEnded
        self.onAutoScroll = onAutoScroll
        self.onHover = onHover
        self.content = content()
    }

    var body: some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            targetHeight = geometry.size.height
                        }
                        .onChange(of: geometry.size) { _, newSize in
                            targetHeight = newSize.height
                        }
                }
            )
            .onDrop(
                of: [UTType.plainText],
                delegate: QueueFileDropDelegate(
                    targetID: targetID,
                    targetHeight: targetHeight,
                    contentScale: contentScale,
                    draggedFileID: $draggedFileID,
                    onMove: onMove,
                    onMoveEnded: onMoveEnded,
                    onAutoScroll: onAutoScroll,
                    onHover: onHover
                )
            )
    }
}

private struct QueuePanelDropDelegate: DropDelegate {
    let panelHeight: CGFloat
    let contentScale: CGFloat
    @Binding var draggedFileID: String?
    var anchorTargetID: String?
    var onMoveEnded: () -> Void
    var onAutoScroll: (QueueAutoScrollDirection) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedFileID != nil,
              let direction = autoScrollDirection(for: info.location.y) else {
            return DropProposal(operation: .move)
        }
        onAutoScroll(direction)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            onMoveEnded()
        }
        draggedFileID = nil
        return true
    }

    private func autoScrollDirection(for locationY: CGFloat) -> QueueAutoScrollDirection? {
        let height = max(panelHeight, 160 * contentScale)
        let edgeBand = min(max(36, 58 * contentScale), height * 0.24)
        if locationY <= edgeBand {
            return .up
        }
        if locationY >= height - edgeBand {
            return .down
        }
        return nil
    }
}

private struct QueueFileDropDelegate: DropDelegate {
    let targetID: String
    let targetHeight: CGFloat
    let contentScale: CGFloat
    @Binding var draggedFileID: String?
    var onMove: (String, String) -> Void
    var onMoveEnded: () -> Void
    var onAutoScroll: (String, QueueAutoScrollDirection) -> Void
    var onHover: (String) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedFileID,
              draggedFileID != targetID else {
            return
        }
        onHover(targetID)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            onMove(draggedFileID, targetID)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            onMoveEnded()
        }
        draggedFileID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onHover(targetID)
        if let direction = autoScrollDirection(for: info.location.y) {
            onAutoScroll(targetID, direction)
        }
        return DropProposal(operation: .move)
    }

    private func autoScrollDirection(for locationY: CGFloat) -> QueueAutoScrollDirection? {
        let fallbackHeight = max(92, 112 * contentScale)
        let height = max(targetHeight, fallbackHeight)
        let edgeBand = min(max(24, 34 * contentScale), height * 0.34)

        if locationY <= edgeBand {
            return .up
        }
        if locationY >= height - edgeBand {
            return .down
        }
        return nil
    }
}

struct FolderPreviewBrowserView: View {
    var context: FolderPreviewContext
    var files: [EncodingFileCardSnapshot]
    var onSelect: (String) -> Void
    var onImportAll: () -> Void
    var onClose: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 118, maximum: 168), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(files) { file in
                        FolderPreviewTileView(
                            file: file,
                            onSelect: { onSelect(file.id) }
                        )
                    }
                }
                .padding(12)
            }

            bottomBar
        }
        .background(TaptionTheme.appBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(context.folderName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(context.countText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TaptionTheme.mutedText)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.88))
            .background(Color.white.opacity(0.10))
            .clipShape(Circle())
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(TaptionTheme.surface)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(action: onImportAll) {
                Label("Import All", systemImage: "tray.and.arrow.down.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.black.opacity(0.88))
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .background(TaptionTheme.surface)
    }
}

struct HomeImportBrowserView: View {
    var mode: HomeImportBrowserMode
    var context: HomeImportBrowserContext?
    var folders: [HomeImportBrowserFolderSnapshot]
    var files: [HomeImportBrowserFileSnapshot]
    var onOpenFolder: (String) -> Void
    var onToggleFile: (String) -> Void
    var onBack: () -> Void
    var onImport: () -> Void
    var onClose: () -> Void

    private let columns = [
        GridItem(.flexible(minimum: 82), spacing: 22, alignment: .top),
        GridItem(.flexible(minimum: 82), spacing: 22, alignment: .top),
        GridItem(.flexible(minimum: 82), spacing: 22, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: 28) {
                    if folders.isEmpty, files.isEmpty, context?.hasLocation == true {
                        HomeImportBrowserEmptyTileView(
                            title: context?.emptyStateTitle ?? "No Items",
                            statusText: context?.emptyStateDetail ?? "Empty"
                        )
                    } else {
                        ForEach(folders) { folder in
                            HomeImportBrowserFolderTileView(
                                folder: folder,
                                onSelect: { onOpenFolder(folder.id) }
                            )
                        }

                        ForEach(files) { file in
                            HomeImportBrowserFileTileView(
                                file: file,
                                isSelectable: mode == .files || mode == .folder,
                                onSelect: { onToggleFile(file.id) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .background(ImportBrowserExplorerStyle.background)

            if context?.hasLocation == true {
                bottomBar
            }
        }
        .background(ImportBrowserExplorerStyle.background.ignoresSafeArea())
        .simultaneousGesture(backSwipeGesture)
    }

    private var header: some View {
        ZStack {
            Text(navigationTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 116)

            HStack(spacing: 8) {
                ImportBrowserBackButton(
                    title: backTitle,
                    isEnabled: context?.canGoUp == true,
                    action: onBack
                )

                Spacer(minLength: 8)

                ImportBrowserToolbarButton(
                    systemImage: "xmark",
                    accessibilityLabel: "Close",
                    action: onClose
                )
            }
        }
        .frame(height: 78)
        .padding(.horizontal, 16)
        .background(ImportBrowserExplorerStyle.navigationBar)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button(action: onImport) {
                Label(mode.importTitle, systemImage: mode == .files ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!canImport)
            .foregroundStyle(canImport ? Color.white : ImportBrowserExplorerStyle.secondaryText)
            .background(canImport ? ImportBrowserExplorerStyle.blueAccent : ImportBrowserExplorerStyle.disabledControl)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
        .background(
            ImportBrowserExplorerStyle.background
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(ImportBrowserExplorerStyle.blueAccent.opacity(0.22))
                        .frame(height: 1)
                }
        )
    }

    private var canImport: Bool {
        guard context?.hasLocation == true else {
            return false
        }
        switch mode {
        case .files, .folder:
            return (context?.selectedFileCount ?? 0) > 0
        }
    }

    private var navigationTitle: String {
        guard context?.hasLocation == true else {
            return mode.title
        }
        return context?.currentFolderName ?? mode.title
    }

    private var backTitle: String {
        guard context?.hasLocation == true else {
            return "Back"
        }

        let parts = (context?.pathText ?? "")
            .split(separator: "/")
            .map(String.init)
        guard parts.count > 1 else {
            return "On My iPhone"
        }
        return parts[parts.count - 2]
    }

    private var backSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard context?.canGoUp == true else {
                    return
                }

                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                if horizontal > 72, horizontal > vertical * 1.45 {
                    onBack()
                }
            }
    }
}

private enum ImportBrowserExplorerStyle {
    static let navigationBar = Color(red: 0.02, green: 0.04, blue: 0.08)
    static let background = Color(red: 0.005, green: 0.01, blue: 0.02)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color(red: 0.52, green: 0.72, blue: 1.0)
    static let blueAccent = Color(red: 0.0, green: 0.48, blue: 1.0)
    static let disabledControl = Color(red: 0.05, green: 0.10, blue: 0.18)
    static let folderFront = Color(red: 0.05, green: 0.34, blue: 0.86)
    static let folderBack = Color(red: 0.02, green: 0.18, blue: 0.46)
    static let selectedRing = Color(red: 0.0, green: 0.64, blue: 1.0)
}

private struct ImportBrowserBackButton: View {
    var title: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 29, weight: .semibold))

                Text(title)
                    .font(.title3.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            .frame(width: 112, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? ImportBrowserExplorerStyle.secondaryText : Color.white.opacity(0.32))
        .accessibilityLabel("Back")
    }
}

private struct ImportBrowserToolbarButton: View {
    var systemImage: String
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 23, weight: .bold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundStyle(ImportBrowserExplorerStyle.secondaryText)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ImportBrowserFolderArtwork: View {
    var systemBadge: String?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let bodyHeight = height * 0.64
            let tabWidth = width * 0.46
            let tabHeight = height * 0.18

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: max(width * 0.055, 6), style: .continuous)
                    .fill(ImportBrowserExplorerStyle.folderFront)
                    .frame(width: width * 0.92, height: bodyHeight)
                    .offset(y: -height * 0.02)

                HStack {
                    RoundedRectangle(cornerRadius: max(width * 0.035, 4), style: .continuous)
                        .fill(ImportBrowserExplorerStyle.folderBack)
                        .frame(width: tabWidth, height: tabHeight)
                    Spacer(minLength: 0)
                }
                .frame(width: width * 0.82)
                .offset(y: -bodyHeight + tabHeight * 0.58)

                if let systemBadge {
                    Image(systemName: systemBadge)
                        .font(.system(size: max(width * 0.18, 18), weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)
                        .offset(y: -height * 0.22)
                }
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(1.18, contentMode: .fit)
    }
}

private struct HomeImportBrowserEmptyTileView: View {
    var title: String
    var statusText: String

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ImportBrowserExplorerStyle.disabledControl)

                Image(systemName: "tray")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(ImportBrowserExplorerStyle.secondaryText)
            }
            .frame(height: 82)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ImportBrowserExplorerStyle.blueAccent.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(ImportBrowserExplorerStyle.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .multilineTextAlignment(.center)
                .frame(height: 40, alignment: .top)

            Text(statusText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(ImportBrowserExplorerStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeImportBrowserFolderTileView: View {
    var folder: HomeImportBrowserFolderSnapshot
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .center, spacing: 10) {
                ImportBrowserFolderArtwork(systemBadge: nil)
                    .frame(height: 82)

                Text(folder.folderName)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(ImportBrowserExplorerStyle.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .multilineTextAlignment(.center)
                    .frame(height: 40, alignment: .top)

                Text(folder.detailText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ImportBrowserExplorerStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct HomeImportBrowserFileTileView: View {
    var file: HomeImportBrowserFileSnapshot
    var isSelectable: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .center, spacing: 10) {
                FolderPreviewThumbnailView(
                    sourceURL: file.thumbnailSourceURL,
                    canAttemptThumbnail: true
                )
                .frame(height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if file.isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white, ImportBrowserExplorerStyle.selectedRing)
                            .padding(6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(file.isSelected ? ImportBrowserExplorerStyle.selectedRing : ImportBrowserExplorerStyle.blueAccent.opacity(0.18), lineWidth: file.isSelected ? 2 : 1)
                )

                Text(file.fileName)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(isSelectable ? ImportBrowserExplorerStyle.primaryText : ImportBrowserExplorerStyle.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .multilineTextAlignment(.center)
                    .frame(height: 40, alignment: .top)

                Text(file.detailText)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ImportBrowserExplorerStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
    }
}

private struct FolderPreviewTileView: View {
    var file: EncodingFileCardSnapshot
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                FolderPreviewThumbnailView(
                    sourceURL: file.thumbnailSourceURL,
                    canAttemptThumbnail: file.isInteractable
                )
                .overlay(alignment: .topTrailing) {
                    if file.isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(Color.white, TaptionTheme.accent)
                            .padding(6)
                    }
                }

                Text(file.fileName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .frame(height: 32, alignment: .topLeading)

                Text(file.statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(file.isInteractable ? TaptionTheme.mutedText : TaptionTheme.disabledText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(file.isSelected ? TaptionTheme.selectedSurface : TaptionTheme.elevatedSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(file.isSelected ? Color.white.opacity(0.36) : TaptionTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FolderPreviewThumbnailView: View {
    var sourceURL: URL?
    var canAttemptThumbnail: Bool

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(TaptionTheme.mutedText)
            } else {
                Image(systemName: didFail ? "film" : "photo.on.rectangle.angled")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TaptionTheme.mutedText)
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
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
            thumbnailImage = try await QueueVideoThumbnailRenderer.thumbnailImage(
                for: sourceURL,
                pixelSize: CGSize(width: 320, height: 180)
            )
        } catch {
            if !Task.isCancelled {
                didFail = true
                AppLogger.debug(
                    "Folder preview thumbnail generation failed",
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

private struct QueueFileThumbnailView: View {
    var sourceURL: URL?
    var canAttemptThumbnail: Bool
    var playbackGestureEnabled: Bool = true
    var contentScale: CGFloat
    var onPlay: (() -> Void)? = nil

    @State private var thumbnailImage: UIImage?
    @State private var isLoading = false
    @State private var didFail = false
    @State private var lastPointerMovementAt = Date.distantPast

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.34))
                .accessibilityHidden(true)

            if let thumbnailImage {
                Image(uiImage: thumbnailImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                    .clipped()
                    .accessibilityHidden(true)
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(max(0.6, contentScale * 0.72))
                    .tint(TaptionTheme.mutedText)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: didFail ? "film" : "photo.on.rectangle.angled")
                    .font(.system(size: 16 * contentScale, weight: .semibold))
                    .foregroundStyle(TaptionTheme.mutedText)
                    .accessibilityHidden(true)
            }

            if canAttemptThumbnail, onPlay != nil {
                playBadge
                    .padding(3 * contentScale)
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
        .simultaneousGesture(pointerMovementGesture)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onTapGesture(count: 2) {
            guard canStartPlayback, let onPlay else { return }
            onPlay()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(canAttemptThumbnail && onPlay != nil ? "Double tap to play preview" : "Video thumbnail")
        .accessibilityAddTraits(canAttemptThumbnail && onPlay != nil ? .isButton : [])
        .accessibilityAction {
            guard canStartPlayback, let onPlay else { return }
            onPlay()
        }
    }

    private var pointerMovementGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .local)
            .onChanged { value in
                guard hasMeaningfulPointerMovement(value.translation) else {
                    return
                }
                lastPointerMovementAt = Date()
            }
            .onEnded { value in
                guard hasMeaningfulPointerMovement(value.translation) else {
                    return
                }
                lastPointerMovementAt = Date()
            }
    }

    private var canStartPlayback: Bool {
        canAttemptThumbnail
            && playbackGestureEnabled
            && onPlay != nil
            && Date().timeIntervalSince(lastPointerMovementAt) > 0.35
    }

    private func hasMeaningfulPointerMovement(_ translation: CGSize) -> Bool {
        abs(translation.width) > 4 || abs(translation.height) > 4
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: max(7, 8 * contentScale), weight: .bold))
            .foregroundStyle(.white)
            .frame(width: max(15, 17 * contentScale), height: max(15, 17 * contentScale))
            .background(TaptionTheme.accent)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
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
        if let sampleThumbnail = SampleThumbnailCatalog.image(for: sourceURL) {
            return sampleThumbnail
        }

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
            instance: QueuePreviewPlayerFactory.thumbnailDecodeInstance
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
