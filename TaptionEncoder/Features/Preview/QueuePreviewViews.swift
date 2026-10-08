import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI
import UIKit
#if DEBUG
@_spi(ValidationHarness) import SwiftVLC
#else
import SwiftVLC
#endif

enum QueuePreviewPlaybackMath {
    static let skipIntervalSeconds = 10.0

    static func seconds(from duration: Duration?) -> Double? {
        guard let duration else {
            return nil
        }
        let components = duration.components
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
        let total = seconds + attoseconds
        return total.isFinite ? max(0, total) : nil
    }

    static func formattedTime(_ duration: Duration?) -> String {
        formattedSeconds(seconds(from: duration))
    }

    static func formattedSeconds(_ seconds: Double?) -> String {
        guard let secondsValue = seconds,
              secondsValue.isFinite else {
            return "--:--"
        }
        let wholeSeconds = max(0, Int(secondsValue.rounded()))
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds % 3600) / 60
        let seconds = wholeSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func clampedPosition(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(max(value, 0), 1)
    }

    static func hasUsableTimeline(durationSeconds: Double?) -> Bool {
        guard let durationSeconds,
              durationSeconds.isFinite else {
            return false
        }
        return durationSeconds > 0
    }

    static func displayedSliderPosition(
        playerPosition: Double,
        isScrubbing: Bool,
        scrubberPosition: Double,
        dragSeekPreviewPosition: Double?,
        durationSeconds: Double?
    ) -> Double {
        guard hasUsableTimeline(durationSeconds: durationSeconds) else {
            return 0
        }
        if isScrubbing {
            return clampedPosition(scrubberPosition)
        }
        if let dragSeekPreviewPosition {
            return clampedPosition(dragSeekPreviewPosition)
        }
        return clampedPosition(playerPosition)
    }

    static func horizontalDragPosition(
        startPosition: Double,
        translation: CGFloat,
        containerWidth: CGFloat
    ) -> Double {
        guard containerWidth > 0 else {
            return clampedPosition(startPosition)
        }
        let positionDelta = Double(translation / containerWidth)
        return clampedPosition(startPosition + positionDelta)
    }

    static func verticalAdjustmentDelta(
        translation: CGFloat,
        containerHeight: CGFloat
    ) -> Float {
        guard containerHeight > 0 else {
            return 0
        }
        return Float(-translation / containerHeight)
    }
}

enum QueuePreviewControlsVisibilityPolicy {
    static func shouldHideOnBackgroundTap(
        isLoading: Bool,
        hasPlaybackError: Bool,
        areControlsVisible: Bool,
        isScrubbing: Bool,
        isDragging: Bool
    ) -> Bool {
        !isLoading
            && !hasPlaybackError
            && areControlsVisible
            && !isScrubbing
            && !isDragging
    }
}

private enum QueuePreviewDragMode: Equatable {
    case seek(startPosition: Double)
    case brightness(startValue: CGFloat)
    case volume(startValue: Float)
    case previousItem
    case nextItem
}

private struct QueuePreviewGestureFeedback: Equatable {
    var systemImage: String
    var text: String
}

struct QueueVideoPreviewView: View {
    var preview: QueueVideoPreview
    var adUnitID: String
    var isAddedToList: Bool
    var canAddToList: Bool
    var onAddToList: () -> Void
    var onClose: () -> Void
    var onMinimize: (QueuePreviewPlaybackSnapshot) -> Void
    var onPictureInPictureActiveChanged: (Bool) -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    @ViewBuilder
    var body: some View {
        if preview.usesNativePlayback {
            NativeQueueVideoPreviewView(
                preview: preview, adUnitID: adUnitID,
                isAddedToList: isAddedToList, canAddToList: canAddToList,
                onAddToList: onAddToList,
                onClose: onClose, onMinimize: onMinimize,
                onPictureInPictureActiveChanged: onPictureInPictureActiveChanged,
                onPrevious: onPrevious, onNext: onNext
            )
        } else {
            VLCQueueVideoPreviewView(
                preview: preview, adUnitID: adUnitID,
                isAddedToList: isAddedToList, canAddToList: canAddToList,
                onAddToList: onAddToList,
                onClose: onClose, onMinimize: onMinimize,
                onPictureInPictureActiveChanged: onPictureInPictureActiveChanged,
                onPrevious: onPrevious, onNext: onNext
            )
        }
    }
}

struct QueuePreviewAddListButton: View {
    var isAdded: Bool
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add List", systemImage: isAdded ? "checkmark.square.fill" : "square")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isAdded ? TaptionTheme.accent : .white)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.white.opacity(0.16), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isAdded)
        .opacity(isEnabled || isAdded ? 1 : 0.5)
        .accessibilityIdentifier("preview.queue")
        .accessibilityLabel("Add List")
        .accessibilityValue(isAdded ? "Added" : "Not added")
        .accessibilityHint(isAdded ? "This video is in the conversion list." : "Add this video without leaving playback.")
    }
}

struct QueuePreviewFileNavigation: View {
    var playlist: QueueVideoPreviewPlaylist?
    var isEnabled: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        if let playlist {
            HStack(spacing: 12) {
                Button(action: onPrevious) {
                    Label("Previous", systemImage: "backward.end.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!isEnabled || !playlist.hasPrevious)
                .accessibilityLabel("Previous file")
                .accessibilityIdentifier("preview.previous")
                .accessibilityHint(playlist.previousName ?? "First video")

                Text(playlist.positionText)
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("preview.position")

                Button(action: onNext) {
                    Label("Next", systemImage: "forward.end.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!isEnabled || !playlist.hasNext)
                .accessibilityLabel("Next file")
                .accessibilityIdentifier("preview.next")
                .accessibilityHint(playlist.nextName ?? "Last video")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }
}

private struct VLCQueueVideoPreviewView: View {
    var preview: QueueVideoPreview
    var adUnitID: String
    var isAddedToList: Bool
    var canAddToList: Bool
    var onAddToList: () -> Void
    var onClose: () -> Void
    var onMinimize: (QueuePreviewPlaybackSnapshot) -> Void
    var onPictureInPictureActiveChanged: (Bool) -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void

    @State private var player = QueuePreviewPlayerFactory.makePreviewPlayer()
    @State private var playbackLifetime = QueuePreviewPlaybackLifetime()
    @State private var audioSessionInstanceID = UUID()
    @State private var playbackError: String?
    @State private var isLoading = true
    @State private var didRequestShutdown = false
    @State private var areControlsVisible = false
    @State private var isScrubbing = false
    @State private var scrubberPosition = 0.0
    @State private var dragMode: QueuePreviewDragMode?
    @State private var dragSeekPreviewPosition: Double?
    @State private var gestureFeedback: QueuePreviewGestureFeedback?
    @State private var gestureFeedbackTask: Task<Void, Never>?
    @State private var didAttachVideoSurface = false
    @State private var pipController: PiPController?
    @State private var didBeginVideoPlaybackAdSuppression = false
    @StateObject private var systemVolumeController = QueuePreviewSystemVolumeController()
    #if DEBUG
    @State private var didAttemptDebugAutoPiP = false
    @State private var didAttemptDebugAutoMiniPlayer = false
    #endif

    var body: some View {
        vlcPreviewBody
    }

    private var vlcPreviewBody: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                videoSurface(containerSize: proxy.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                videoGestureLayer(containerSize: proxy.size)

                if areControlsVisible {
                    controlsBackdrop
                        .transition(.opacity)

                    previewTopBanner(
                        containerSize: proxy.size,
                        safeAreaInsets: proxy.safeAreaInsets
                    )

                    controlsOverlay(
                        containerSize: proxy.size,
                        safeAreaInsets: proxy.safeAreaInsets
                    )
                        .transition(.opacity)
                }

                centerPlayPauseOverlay

                statusOverlay

                if let gestureFeedback {
                    gestureFeedbackOverlay(gestureFeedback)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                QueuePreviewSystemVolumeBridgeView(controller: systemVolumeController)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(
            Color.black
                .ignoresSafeArea()
        )
        .onAppear {
            beginVideoPlaybackAdSuppressionIfNeeded()
            AppOrientationController.shared.activatePreviewOrientations()
        }
        .task(id: preview.id) {
            await startPlayback()
        }
        .onChange(of: preview.id) { _, _ in
            resetControlsForPreviewSwitch()
        }
        .onChange(of: playbackError) { _, error in
            if error != nil {
                showControls(scheduleAutoHide: false)
            }
        }
        .onChange(of: pipController?.isActive) { _, isActive in
            handlePictureInPictureActiveChange(isActive == true)
        }
        .onDisappear {
            onPictureInPictureActiveChanged(false)
            shutdownPlayer()
        }
    }

    @ViewBuilder
    private func videoSurface(containerSize: CGSize) -> some View {
        let fittedSize = fittedVideoSize(in: containerSize)
        PiPVideoView(
            player,
            controller: $pipController,
            startsAutomaticallyFromInline: false,
            managesAudioSession: false
        )
        .frame(
            width: min(max(fittedSize.width, 0), containerSize.width),
            height: min(max(fittedSize.height, 0), containerSize.height)
        )
        .background(Color.black)
        .clipped()
        .onAppear {
            didAttachVideoSurface = true
            AppLogger.info(
                "Queue preview video surface appeared",
                category: .ui,
                metadata: ["name": preview.displayName]
            )
        }
        .onDisappear {
            didAttachVideoSurface = false
        }
    }

    private func videoGestureLayer(containerSize: CGSize) -> some View {
        Color.clear
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(tapGesture(containerSize: containerSize))
            .simultaneousGesture(dragGesture(containerSize: containerSize))
    }

    private var controlsBackdrop: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.62),
                Color.black.opacity(0.08),
                Color.black.opacity(0.68)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func previewTopBanner(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        VStack(spacing: 0) {
            AdMobBannerSlotView(
                adUnitID: adUnitID,
                displayScale: previewBannerScale(containerSize: containerSize)
            )
            .padding(.top, max(safeAreaInsets.top, 8))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.82),
                        Color.black.opacity(0.58),
                        Color.black.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }

    private func controlsOverlay(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        VStack(spacing: 0) {
            previewHeader
                .padding(.horizontal, containerSize.width < 380 ? 12 : 16)
                .padding(.top, previewHeaderTopPadding(containerSize: containerSize, safeAreaInsets: safeAreaInsets))

            Spacer(minLength: 0)

            transportControls
                .padding(.horizontal, containerSize.width < 380 ? 10 : 16)
                .padding(.bottom, 18)
        }
    }

    private func previewBannerScale(containerSize: CGSize) -> CGFloat {
        let widthFitScale = max(min((containerSize.width - 24) / 320, 1), 0.72)
        let heightScale = containerSize.width > containerSize.height ? 0.78 : 1
        return min(widthFitScale, heightScale)
    }

    private func previewHeaderTopPadding(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> CGFloat {
        max(safeAreaInsets.top, 8)
            + (50 * previewBannerScale(containerSize: containerSize))
            + 24
    }

    private var previewHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(preview.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.middle)

                PreviewBadgeFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                    previewBadge(systemImage: "video", text: preview.codecBadge)
                    previewBadge(systemImage: "point.3.connected.trianglepath.dotted", text: preview.pathBadge)
                    previewBadge(systemImage: "aspectratio", text: preview.videoInfo.resolution)
                    previewBadge(systemImage: "speaker.wave.2", text: preview.videoInfo.audio)
                    previewBadge(systemImage: "externaldrive", text: preview.videoInfo.fileSize)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("File size: \(preview.videoInfo.fileSize)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                QueuePreviewAddListButton(
                    isAdded: isAddedToList,
                    isEnabled: canAddToList && !isLoading,
                    action: onAddToList
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 4)

            Button(action: closePreview) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white.opacity(0.94))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("preview.close")
        }
    }

    private var centerPlayPauseOverlay: some View {
        Group {
            if areControlsVisible && !isLoading && playbackError == nil {
                Button(action: togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 76, height: 76)
                        .background(Color.black.opacity(0.54))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
    }

    private var transportControls: some View {
        VStack(spacing: 9) {
            QueuePreviewFileNavigation(
                playlist: preview.playlist, isEnabled: !isLoading,
                onPrevious: previousItem, onNext: nextItem
            )

            Slider(
                value: Binding(
                    get: { displayedSliderPosition },
                    set: { newValue in
                        guard hasUsableTimeline else {
                            return
                        }
                        isScrubbing = true
                        scrubberPosition = QueuePreviewPlaybackMath.clampedPosition(newValue)
                        showControls(scheduleAutoHide: false)
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                        scrubberPosition = displayedSliderPosition
                        showControls(scheduleAutoHide: false)
                    } else {
                        finishScrubbing()
                    }
                }
            )
            .disabled(!hasUsableTimeline)
            .tint(Color.white)

            HStack(spacing: 6) {
                Button(action: skipBackward) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 34, height: 36)
                }
                .accessibilityLabel("Rewind 10 seconds")



                Button(action: togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 38, height: 38)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")



                Button(action: skipForward) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 34, height: 36)
                }
                .accessibilityLabel("Forward 10 seconds")

                Text("\(displayedCurrentTimeText) / \(durationText)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .allowsTightening(true)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(1)
            }
            .foregroundStyle(Color.white)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isLoading || playbackError != nil {
            VStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.white)
                    Text("Loading preview")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                }

                if let playbackError {
                    Text(playbackError)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.66))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.bottom, 18)
        }
    }

    private func gestureFeedbackOverlay(_ feedback: QueuePreviewGestureFeedback) -> some View {
        HStack(spacing: 10) {
            Image(systemName: feedback.systemImage)
                .font(.system(size: 20, weight: .semibold))
            Text(feedback.text)
                .font(.headline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.66))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func previewBadge(systemImage: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)
                .layoutPriority(1)
        }
        .lineLimit(1)
        .foregroundStyle(Color.white.opacity(0.86))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var displayedSliderPosition: Double {
        QueuePreviewPlaybackMath.displayedSliderPosition(
            playerPosition: player.position,
            isScrubbing: isScrubbing,
            scrubberPosition: scrubberPosition,
            dragSeekPreviewPosition: dragSeekPreviewPosition,
            durationSeconds: durationSeconds
        )
    }

    private var displayedCurrentTimeText: String {
        if let durationSeconds,
           isScrubbing || dragSeekPreviewPosition != nil {
            return QueuePreviewPlaybackMath.formattedSeconds(durationSeconds * displayedSliderPosition)
        }
        return QueuePreviewPlaybackMath.formattedTime(player.currentTime)
    }

    private var durationText: String {
        QueuePreviewPlaybackMath.formattedTime(player.duration)
    }

    private var durationSeconds: Double? {
        QueuePreviewPlaybackMath.seconds(from: player.duration)
    }

    private var hasUsableTimeline: Bool {
        QueuePreviewPlaybackMath.hasUsableTimeline(durationSeconds: durationSeconds)
    }

    private var isPictureInPictureActive: Bool {
        pipController?.isActive == true
    }

    private var canTogglePictureInPicture: Bool {
        guard let pipController else {
            return false
        }
        return pipController.isPossible || pipController.isActive
    }

    @MainActor
    private func startPlayback() async {
        let operationID = playbackLifetime.begin()
        didRequestShutdown = false
        playbackError = nil
        isLoading = true
        withTransaction(Transaction(animation: nil)) {
            areControlsVisible = false
        }
        player.aspectRatio = .default
        configurePlayerAudioForPreview()

        do {
            try await QueuePreviewAudioSessionController.activateForPreview(id: previewAudioSessionID)
            try playbackLifetime.check(operationID)
            if preview.playbackSnapshot != nil { player.isMuted = true }
            player.stop()
            try await Task.sleep(nanoseconds: 120_000_000)
            try await waitForVideoSurfaceAttachment(operationID: operationID)
            try playbackLifetime.check(operationID)
            let didProduceVideoOutput = try await playPreviewWithFallbacks(operationID: operationID)
            try playbackLifetime.check(operationID)
            if !didProduceVideoOutput {
                player.stop()
                playbackError = "Preview video output is unavailable on this device."
                AppLogger.warning(
                    "Queue preview failed to produce a video output",
                    category: .ui,
                    metadata: [
                        "name": preview.displayName,
                        "codec": preview.codecBadge,
                        "container": preview.sourceURL.pathExtension.lowercased(),
                        "activeVideoOutputs": "\(player.activeVideoOutputs)",
                        "hasVideoOutput": "\(player.hasVideoOutput)"
                    ]
                )
                isLoading = false
                showControls(scheduleAutoHide: false)
                return
            }
            try await restorePlaybackSnapshot(operationID: operationID)
            isLoading = false
            #if DEBUG
            try await startDebugAutoPictureInPictureIfRequested(operationID: operationID)
            try await minimizeDebugPreviewIfRequested(operationID: operationID)
            #endif
        } catch is CancellationError {
            guard playbackLifetime.isCurrent(operationID) else { return }
            isLoading = false
        } catch {
            guard playbackLifetime.isCurrent(operationID), !Task.isCancelled else { return }
            player.stop()
            playbackError = (error as? QueuePreviewPlaybackResumeError)?.errorDescription
                ?? "Preview failed. SwiftVLC could not decode this file."
            isLoading = false
            AppLogger.error(
                "Queue preview playback failed",
                category: .ui,
                metadata: [
                    "name": preview.displayName,
                    "error": String(describing: error)
                ]
            )
        }
    }

    private func closePreview() {
        AppLogger.info(
            "Queue preview close tapped",
            category: .ui,
            metadata: ["name": preview.displayName]
        )
        shutdownPlayer()
        onClose()
    }

    private func minimizePreview() {
        AppLogger.info(
            "Queue preview minimized to floating player",
            category: .ui,
            metadata: ["name": preview.displayName]
        )
        onMinimize(playbackSnapshot())
    }

    private func playbackSnapshot() -> QueuePreviewPlaybackSnapshot {
        if isLoading || playbackError != nil, let snapshot = preview.playbackSnapshot { return snapshot }
        return QueuePreviewPlaybackSnapshot(
            seconds: QueuePreviewPlaybackMath.seconds(from: player.currentTime) ?? 0,
            isPlaying: player.isPlaying
        )
    }

    private func restorePlaybackSnapshot(operationID: UUID) async throws {
        guard let snapshot = preview.playbackSnapshot else { return }
        try await QueuePreviewPlaybackRestorer.restore(
            snapshot: snapshot,
            validate: { try playbackLifetime.check(operationID) },
            isSeekable: { player.isSeekable },
            durationSeconds: { QueuePreviewPlaybackMath.seconds(from: player.duration) },
            seek: { try await QueuePreviewVLCSeek.seek(player, to: $0, pauseBeforeSeeking: !snapshot.isPlaying,
                                                      validate: { try playbackLifetime.check(operationID) }) },
            setPlaying: { if $0 { player.resume() } else { player.pause() } }
        )
        try playbackLifetime.check(operationID)
        player.isMuted = false
        AppLogger.info("Queue preview playback state restored", category: .ui, metadata: [
            "seconds": "\(QueuePreviewPlaybackMath.seconds(from: player.currentTime) ?? 0)",
            "requestedSeconds": "\(snapshot.seconds)", "playing": "\(player.isPlaying)", "mode": "full"
        ])
    }

    private func beginVideoPlaybackAdSuppressionIfNeeded() {
        guard !didBeginVideoPlaybackAdSuppression else {
            return
        }
        didBeginVideoPlaybackAdSuppression = true
        AdMobBootstrapper.beginVideoPlaybackAdSuppression(reason: "queuePreview")
    }

    private func endVideoPlaybackAdSuppressionIfNeeded() {
        guard didBeginVideoPlaybackAdSuppression else {
            return
        }
        didBeginVideoPlaybackAdSuppression = false
        AdMobBootstrapper.endVideoPlaybackAdSuppression(reason: "queuePreview")
    }

    private func togglePlayback() {
        player.togglePlayPause()
        showControls(scheduleAutoHide: false)
    }

    private func togglePictureInPicture() {
        guard let pipController else {
            showGestureFeedback(systemImage: "pip", text: "PiP unavailable")
            showControls(scheduleAutoHide: false)
            return
        }

        if pipController.isActive {
            pipController.stop()
            showGestureFeedback(systemImage: "pip.exit", text: "Inline")
            showControls(scheduleAutoHide: false)
            return
        }

        guard pipController.isPossible else {
            showGestureFeedback(systemImage: "pip", text: "PiP unavailable")
            showControls(scheduleAutoHide: false)
            return
        }

        pipController.start()
        AppLogger.info(
            "Queue preview Picture in Picture requested on current player",
            category: .ui,
            metadata: [
                "name": preview.displayName,
                "possible": "\(pipController.isPossible)",
                "active": "\(pipController.isActive)"
            ]
        )
        showGestureFeedback(systemImage: "pip.enter", text: "Picture in Picture")
        showControls(scheduleAutoHide: false)
    }

    private func handlePictureInPictureActiveChange(_ isActive: Bool) {
        AppLogger.info(
            "Queue preview Picture in Picture active state changed",
            category: .ui,
            metadata: [
                "name": preview.displayName,
                "active": "\(isActive)"
            ]
        )
        if isActive {
            AppOrientationController.shared.restorePortrait()
        } else if !didRequestShutdown {
            AppOrientationController.shared.activatePreviewOrientations()
        }
        onPictureInPictureActiveChanged(isActive)
    }

    #if DEBUG
    @MainActor
    private func startDebugAutoPictureInPictureIfRequested(operationID: UUID) async throws {
        guard !didAttemptDebugAutoPiP,
              debugAutoStartPictureInPictureRequested else {
            return
        }
        didAttemptDebugAutoPiP = true

        for _ in 0..<30 {
            try playbackLifetime.check(operationID)
            if pipController?.isPossible == true {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        guard let pipController else {
            AppLogger.warning(
                "Debug auto PiP skipped because controller is unavailable",
                category: .ui,
                metadata: ["name": preview.displayName]
            )
            return
        }

        AppLogger.info(
            "Debug auto PiP requested",
            category: .ui,
            metadata: debugPictureInPictureMetadata(for: pipController)
        )

        guard pipController.isPossible else {
            return
        }

        try playbackLifetime.check(operationID)
        pipController.start()
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 250_000_000)
            try playbackLifetime.check(operationID)
            if pipController.isActive {
                break
            }
        }
        AppLogger.info(
            "Debug auto PiP state checked",
            category: .ui,
            metadata: debugPictureInPictureMetadata(for: pipController)
        )
    }

    private func debugPictureInPictureMetadata(for pipController: PiPController) -> [String: String] {
        var metadata: [String: String] = [
            "name": preview.displayName,
            "possible": "\(pipController.isPossible)",
            "active": "\(pipController.isActive)",
            "simulator": Self.isSimulatorRuntime ? "true" : "false",
            "probeID": debugProbeID ?? "none"
        ]
        if let probe = pipController.nativeValidationProbe {
            metadata["hasAVController"] = "\(probe.hasAVController)"
            metadata["windowController"] = probe.windowControllerClassName ?? "none"
        }
        return metadata
    }

    private static var isSimulatorRuntime: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var debugAutoStartPictureInPictureRequested: Bool {
        ProcessInfo.processInfo.environment["TAPTION_AUTO_START_PIP"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--taption-auto-start-pip")
    }

    private var debugProbeID: String? {
        ProcessInfo.processInfo.environment["TAPTION_PIP_PROBE_ID"]
    }

    @MainActor
    private func minimizeDebugPreviewIfRequested(operationID: UUID) async throws {
        guard !didAttemptDebugAutoMiniPlayer,
              debugAutoMiniPlayerRequested, preview.playbackSnapshot == nil else {
            return
        }
        didAttemptDebugAutoMiniPlayer = true
        try await Task.sleep(nanoseconds: 300_000_000)
        try playbackLifetime.check(operationID)
        if let snapshot = QueuePreviewDebugHandoff.requestedSnapshot {
            try await QueuePreviewPlaybackRestorer.restore(
                snapshot: snapshot, validate: { try playbackLifetime.check(operationID) },
                isSeekable: { player.isSeekable },
                durationSeconds: { QueuePreviewPlaybackMath.seconds(from: player.duration) },
                seek: { try await QueuePreviewVLCSeek.seek(player, to: $0, pauseBeforeSeeking: !snapshot.isPlaying,
                                                          validate: { try playbackLifetime.check(operationID) }) },
                setPlaying: { if $0 { player.resume() } else { player.pause() } }
            )
            try await Task.sleep(for: .milliseconds(400))
            try playbackLifetime.check(operationID)
        }
        AppLogger.info(
            "Debug auto mini player requested",
            category: .ui,
            metadata: ["name": preview.displayName]
        )
        minimizePreview()
    }

    private var debugAutoMiniPlayerRequested: Bool {
        ProcessInfo.processInfo.environment["TAPTION_AUTO_MINIMIZE_PREVIEW"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--taption-auto-minimize-preview")
    }
    #endif

    private func skipBackward() {
        seekBy(seconds: -QueuePreviewPlaybackMath.skipIntervalSeconds)
        showGestureFeedback(systemImage: "gobackward.10", text: "-10s")
    }

    private func skipForward() {
        seekBy(seconds: QueuePreviewPlaybackMath.skipIntervalSeconds)
        showGestureFeedback(systemImage: "goforward.10", text: "+10s")
    }

    private func previousItem() {
        guard preview.playlist?.hasPrevious == true else {
            return
        }
        resetControlsForPreviewSwitch()
        onPrevious()
    }

    private func nextItem() {
        guard preview.playlist?.hasNext == true else {
            return
        }
        resetControlsForPreviewSwitch()
        onNext()
    }

    private func seekBy(seconds: Double) {
        guard hasUsableTimeline else {
            showControls(scheduleAutoHide: false)
            return
        }
        let offset = Duration.seconds(seconds)
        if (try? player.seek(by: offset, fast: true)) == nil {
            _ = player.jump(by: offset)
        }
        showControls(scheduleAutoHide: false)
    }

    private func finishScrubbing() {
        guard hasUsableTimeline else {
            isScrubbing = false
            scrubberPosition = 0
            showControls(scheduleAutoHide: false)
            return
        }

        let target = QueuePreviewPlaybackMath.clampedPosition(scrubberPosition)
        if player.isSeekable, player.duration != nil {
            try? player.seek(to: PlaybackPosition(target))
        } else {
            _ = player.seek(toPosition: PlaybackPosition(target), fast: true)
        }
        isScrubbing = false
        scrubberPosition = target
        showControls(scheduleAutoHide: false)
    }

    private func tapGesture(containerSize: CGSize) -> some Gesture {
        ExclusiveGesture(
            SpatialTapGesture(count: 2, coordinateSpace: .local),
            SpatialTapGesture(count: 1, coordinateSpace: .local)
        )
        .onEnded { value in
            switch value {
            case .first(let tap):
                handleDoubleTap(at: tap.location, containerSize: containerSize)
            case .second:
                toggleControls()
            }
        }
    }

    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                handleDragChanged(value, containerSize: containerSize)
            }
            .onEnded { value in
                handleDragEnded(value, containerSize: containerSize)
            }
    }

    private func handleDoubleTap(at location: CGPoint, containerSize: CGSize) {
        guard containerSize.width > 0 else {
            return
        }
        showControls(scheduleAutoHide: false)
        if location.x < containerSize.width / 2 {
            skipBackward()
        } else {
            skipForward()
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value, containerSize: CGSize) {
        if dragMode == nil {
            dragMode = resolvedDragMode(for: value, containerSize: containerSize)
        }

        guard let dragMode else {
            return
        }

        switch dragMode {
        case .seek(let startPosition):
            let targetPosition = QueuePreviewPlaybackMath.horizontalDragPosition(
                startPosition: startPosition,
                translation: value.translation.width,
                containerWidth: containerSize.width
            )
            dragSeekPreviewPosition = targetPosition
            let feedbackText: String
            if let durationSeconds {
                feedbackText = QueuePreviewPlaybackMath.formattedSeconds(durationSeconds * targetPosition)
            } else {
                feedbackText = "\(Int((targetPosition * 100).rounded()))%"
            }
            showGestureFeedback(systemImage: "arrow.left.and.right", text: feedbackText, autoDismiss: false)
        case .brightness(let startValue):
            let delta = CGFloat(QueuePreviewPlaybackMath.verticalAdjustmentDelta(
                translation: value.translation.height,
                containerHeight: containerSize.height
            ))
            let brightness = min(max(startValue + delta, 0), 1)
            UIScreen.main.brightness = brightness
            showGestureFeedback(
                systemImage: "sun.max.fill",
                text: "\(Int((brightness * 100).rounded()))%",
                autoDismiss: false
            )
        case .volume(let startValue):
            let delta = QueuePreviewPlaybackMath.verticalAdjustmentDelta(
                translation: value.translation.height,
                containerHeight: containerSize.height
            )
            let volume = QueuePreviewSystemVolumeController.clampedVolume(startValue + delta)
            setPreviewOutputVolume(volume)
            showGestureFeedback(
                systemImage: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                text: "\(Int((volume * 100).rounded()))%",
                autoDismiss: false
            )
        case .previousItem:
            showGestureFeedback(
                systemImage: "backward.end.fill",
                text: preview.playlist?.previousName ?? "Previous",
                autoDismiss: false
            )
        case .nextItem:
            showGestureFeedback(
                systemImage: "forward.end.fill",
                text: preview.playlist?.nextName ?? "Next",
                autoDismiss: false
            )
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, containerSize: CGSize) {
        defer {
            dragMode = nil
            dragSeekPreviewPosition = nil
            dismissGestureFeedbackAfterDelay()
            showControls(scheduleAutoHide: false)
        }

        switch dragMode {
        case .seek(let startPosition):
            let targetPosition = QueuePreviewPlaybackMath.horizontalDragPosition(
                startPosition: startPosition,
                translation: value.translation.width,
                containerWidth: containerSize.width
            )
            if player.isSeekable, player.duration != nil {
                try? player.seek(to: PlaybackPosition(targetPosition))
            } else {
                _ = player.seek(toPosition: PlaybackPosition(targetPosition), fast: true)
            }
        case .previousItem:
            previousItem()
        case .nextItem:
            nextItem()
        case .brightness, .volume, .none:
            return
        }
    }

    private func resolvedDragMode(
        for value: DragGesture.Value,
        containerSize: CGSize
    ) -> QueuePreviewDragMode? {
        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)

        if horizontalDistance > verticalDistance * 1.2 {
            let edgeWidth = min(max(containerSize.width * 0.18, 56), 96)
            if value.startLocation.x < edgeWidth,
               value.translation.width > 0,
               preview.playlist?.hasPrevious == true {
                return .previousItem
            }
            if value.startLocation.x > containerSize.width - edgeWidth,
               value.translation.width < 0,
               preview.playlist?.hasNext == true {
                return .nextItem
            }
            guard hasUsableTimeline else {
                return nil
            }
            return .seek(startPosition: player.position)
        }

        if verticalDistance > horizontalDistance * 1.2 {
            if value.startLocation.x < containerSize.width / 2 {
                return .brightness(startValue: UIScreen.main.brightness)
            }
            return .volume(startValue: systemVolumeController.volume)
        }

        return nil
    }

    private func setPreviewOutputVolume(_ volume: Float) {
        player.isMuted = false
        try? player.setAudioVolume(.unity)
        systemVolumeController.setVolume(volume)
    }

    private func toggleControls() {
        guard !isLoading, playbackError == nil else {
            showControls(scheduleAutoHide: false)
            return
        }

        if QueuePreviewControlsVisibilityPolicy.shouldHideOnBackgroundTap(
            isLoading: isLoading,
            hasPlaybackError: playbackError != nil,
            areControlsVisible: areControlsVisible,
            isScrubbing: isScrubbing,
            isDragging: dragMode != nil
        ) {
            hideControls()
        } else {
            showControls(scheduleAutoHide: false)
        }
    }

    private func showControls(scheduleAutoHide _: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            areControlsVisible = true
        }
    }

    private func hideControls() {
        guard !isScrubbing, dragMode == nil else {
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            areControlsVisible = false
        }
    }

    private func resetControlsForPreviewSwitch() {
        isScrubbing = false
        dragMode = nil
        dragSeekPreviewPosition = nil
        gestureFeedback = nil
        gestureFeedbackTask?.cancel()
        gestureFeedbackTask = nil
        withTransaction(Transaction(animation: nil)) {
            areControlsVisible = false
        }
    }

    private func showGestureFeedback(
        systemImage: String,
        text: String,
        autoDismiss: Bool = true
    ) {
        withAnimation(.easeInOut(duration: 0.12)) {
            gestureFeedback = QueuePreviewGestureFeedback(systemImage: systemImage, text: text)
        }
        gestureFeedbackTask?.cancel()
        if autoDismiss {
            dismissGestureFeedbackAfterDelay()
        }
    }

    private func dismissGestureFeedbackAfterDelay() {
        gestureFeedbackTask?.cancel()
        gestureFeedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                gestureFeedback = nil
            }
        }
    }

    private func fittedVideoSize(in containerSize: CGSize) -> CGSize {
        guard containerSize.width > 0,
              containerSize.height > 0,
              let aspectRatio = preview.aspectRatio,
              aspectRatio > 0 else {
            return containerSize
        }

        let containerAspectRatio = containerSize.width / containerSize.height
        if containerAspectRatio > CGFloat(aspectRatio) {
            let height = containerSize.height
            return CGSize(width: height * CGFloat(aspectRatio), height: height)
        }

        let width = containerSize.width
        return CGSize(width: width, height: width / CGFloat(aspectRatio))
    }

    private func playPreviewWithFallbacks(operationID: UUID) async throws -> Bool {
        let demuxModes = QueuePreviewPlayerFactory.previewDemuxModes(for: preview.sourceURL)
        return try await QueuePreviewPlaybackAttempts.run(
            demuxModes: demuxModes,
            validate: { try playbackLifetime.check(operationID) },
            stop: { player.stop() },
            play: { index, demuxMode in
                let media = try makePreviewMedia(demuxMode: demuxMode)
                AppLogger.info(
                    "Queue preview playback attempt started",
                    category: .ui,
                    metadata: [
                        "name": preview.displayName,
                        "attempt": "\(index + 1)",
                        "demux": demuxMode.logValue,
                    ]
                )
                try player.play(media)
            },
            waitForOutput: { try await waitForVideoOutput(operationID: operationID) },
            didFinishAttempt: { index, demuxMode, ready in
                if ready {
                    AppLogger.info(
                        "Queue preview video output ready",
                        category: .ui,
                        metadata: [
                            "name": preview.displayName,
                            "attempt": "\(index + 1)",
                            "demux": demuxMode.logValue,
                            "activeVideoOutputs": "\(player.activeVideoOutputs)",
                            "hasVideoOutput": "\(player.hasVideoOutput)",
                        ]
                    )
                } else {
                    AppLogger.warning(
                        "Queue preview playback attempt had no video output",
                        category: .ui,
                        metadata: [
                            "name": preview.displayName,
                            "attempt": "\(index + 1)",
                            "demux": demuxMode.logValue,
                            "activeVideoOutputs": "\(player.activeVideoOutputs)",
                            "hasVideoOutput": "\(player.hasVideoOutput)",
                        ]
                    )
                }
            }
        )
    }

    private func makePreviewMedia(demuxMode: QueuePreviewDemuxMode) throws -> Media {
        let media = try Media(url: preview.sourceURL)
        let options = QueuePreviewPlayerFactory.configureSoftwareDecodeOptions(
            on: media,
            sourceURL: preview.sourceURL,
            demuxMode: demuxMode
        )
        AppLogger.info(
            "Queue preview media configured",
            category: .ui,
            metadata: [
                "name": preview.displayName,
                "demux": demuxMode.logValue,
                "options": options.joined(separator: "|")
            ]
        )
        return media
    }

    private func configurePlayerAudioForPreview() {
        player.role = .video
        player.isMuted = false
        do {
            try player.setAudioVolume(.unity)
        } catch {
            AppLogger.warning(
                "Queue preview player volume setup failed",
                category: .ui,
                metadata: [
                    "name": preview.displayName,
                    "error": String(describing: error)
                ]
            )
        }

        AppLogger.info(
            "Queue preview player audio configured",
            category: .ui,
            metadata: [
                "name": preview.displayName,
                "muted": "\(player.isMuted)",
                "volume": String(format: "%.2f", player.volume),
                "role": "\(player.role)"
            ]
        )
    }

    @MainActor
    private func waitForVideoSurfaceAttachment(operationID: UUID) async throws {
        for _ in 0..<20 {
            try playbackLifetime.check(operationID)
            if didAttachVideoSurface {
                try await Task.sleep(nanoseconds: 120_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        AppLogger.warning(
            "Queue preview playback starting before video surface attachment was observed",
            category: .ui,
            metadata: ["name": preview.displayName]
        )
    }

    @MainActor
    private func waitForVideoOutput(operationID: UUID) async throws -> Bool {
        for _ in 0..<80 {
            try playbackLifetime.check(operationID)
            if player.hasVideoOutput || player.activeVideoOutputs > 0 {
                return true
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try playbackLifetime.check(operationID)
        return player.hasVideoOutput || player.activeVideoOutputs > 0
    }

    private func shutdownPlayer() {
        guard !didRequestShutdown else {
            return
        }
        didRequestShutdown = true
        playbackLifetime.invalidate()
        gestureFeedbackTask?.cancel()
        AppOrientationController.shared.restorePortrait()
        pipController?.stop()
        endVideoPlaybackAdSuppressionIfNeeded()
        let sessionID = previewAudioSessionID
        Task { @MainActor in
            await player.shutdown()
            QueuePreviewAudioSessionController.deactivateAfterPreview(id: sessionID)
        }
    }

    private var previewAudioSessionID: String {
        "\(preview.id).vlc.\(audioSessionInstanceID.uuidString)"
    }
}

struct QueueMiniPlayerView: View {
    var preview: QueueVideoPreview
    var onClose: () -> Void
    var onExpand: (QueuePreviewPlaybackSnapshot) -> Void

    @ViewBuilder
    var body: some View {
        if preview.usesNativePlayback {
            NativeQueueVideoPreviewView(
                preview: preview, isMiniPlayer: true,
                onClose: onClose, onMinimize: onExpand
            )
        } else {
            VLCQueueMiniPlayerView(preview: preview, onClose: onClose, onExpand: onExpand)
        }
    }
}

private struct VLCQueueMiniPlayerView: View {
    var preview: QueueVideoPreview
    var onClose: () -> Void
    var onExpand: (QueuePreviewPlaybackSnapshot) -> Void

    @State private var player = QueuePreviewPlayerFactory.makePreviewPlayer()
    @State private var playbackLifetime = QueuePreviewPlaybackLifetime()
    @State private var audioSessionInstanceID = UUID()
    @State private var pipController: PiPController?
    @State private var isLoading = true
    @State private var playbackError: String?
    @State private var didAttachVideoSurface = false
    @State private var didBeginVideoPlaybackAdSuppression = false
    @State private var didRequestShutdown = false

    var body: some View {
        vlcMiniPlayerBody
    }

    private var vlcMiniPlayerBody: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PiPVideoView(
                    player,
                    controller: $pipController,
                    startsAutomaticallyFromInline: false,
                    managesAudioSession: false
                )
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .allowsHitTesting(false)
                .onAppear {
                    didAttachVideoSurface = true
                    AppLogger.info(
                        "Queue mini player video surface appeared",
                        category: .ui,
                        metadata: ["name": preview.displayName]
                    )
                }
                .onDisappear {
                    didAttachVideoSurface = false
                }

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.18))
                }

                if let playbackError {
                    Text(playbackError)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.62))
                }

                HStack(spacing: 4) {
                    Button(action: togglePictureInPicture) {
                        Image(systemName: isPictureInPictureActive ? "pip.exit" : "pip.enter")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(!canTogglePictureInPicture)
                    .opacity(canTogglePictureInPicture ? 1 : 0.38)
                    .accessibilityLabel(isPictureInPictureActive ? "Exit Picture in Picture" : "Picture in Picture")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .background(Color.black.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(6)
            }

            HStack(spacing: 4) {
                Button(action: togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(QueuePreviewPlaybackMath.formattedTime(player.currentTime))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.66))
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                // Keep navigation outside the UIKit video surface so taps
                // cannot be intercepted by the video/PiP presentation layer.
                Button(action: expandPreview) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Expand")
                .accessibilityIdentifier("preview.mini.expand")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("preview.mini.close")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.94))
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.42), radius: 16, x: 0, y: 8)
        .onAppear {
            beginVideoPlaybackAdSuppressionIfNeeded()
        }
        .task(id: preview.id) {
            await startMiniPlayback()
        }
        .onDisappear {
            shutdownMiniPlayer()
        }
    }

    private var miniSessionID: String {
        "\(preview.id).mini.\(audioSessionInstanceID.uuidString)"
    }

    @MainActor
    private func startMiniPlayback() async {
        let operationID = playbackLifetime.begin()
        didRequestShutdown = false
        playbackError = nil
        isLoading = true
        player.aspectRatio = .default

        do {
            try await QueuePreviewAudioSessionController.activateForPreview(id: miniSessionID)
            try playbackLifetime.check(operationID)
            configurePlayerAudioForMiniPlayback()
            if preview.playbackSnapshot != nil { player.isMuted = true }
            player.stop()
            try await Task.sleep(nanoseconds: 120_000_000)
            try await waitForVideoSurfaceAttachment(operationID: operationID)
            try playbackLifetime.check(operationID)
            let didProduceVideoOutput = try await playMiniPreviewWithFallbacks(operationID: operationID)
            try playbackLifetime.check(operationID)
            if !didProduceVideoOutput {
                player.stop()
                playbackError = "Preview unavailable"
                AppLogger.warning(
                    "Queue mini player failed to produce a video output",
                    category: .ui,
                    metadata: [
                        "name": preview.displayName,
                        "codec": preview.codecBadge,
                        "container": preview.sourceURL.pathExtension.lowercased(),
                        "activeVideoOutputs": "\(player.activeVideoOutputs)",
                        "hasVideoOutput": "\(player.hasVideoOutput)"
                    ]
                )
                isLoading = false
                return
            }
            try await restoreMiniPlaybackSnapshot(operationID: operationID)
            isLoading = false
            #if DEBUG
            if QueuePreviewDebugHandoff.automaticallyRestoresFullPreview {
                try await Task.sleep(for: .milliseconds(400))
                try playbackLifetime.check(operationID)
                expandPreview()
            }
            #endif
        } catch is CancellationError {
            guard playbackLifetime.isCurrent(operationID) else { return }
            isLoading = false
        } catch {
            guard playbackLifetime.isCurrent(operationID), !Task.isCancelled else { return }
            player.stop()
            playbackError = (error as? QueuePreviewPlaybackResumeError)?.errorDescription ?? "Preview unavailable"
            isLoading = false
            AppLogger.error(
                "Queue mini player playback failed",
                category: .ui,
                metadata: [
                    "name": preview.displayName,
                    "error": String(describing: error)
                ]
            )
        }
    }

    private func togglePlayback() {
        player.togglePlayPause()
    }

    private func expandPreview() {
        let snapshot: QueuePreviewPlaybackSnapshot
        if isLoading || playbackError != nil, let requested = preview.playbackSnapshot {
            snapshot = requested
        } else {
            snapshot = QueuePreviewPlaybackSnapshot(
                seconds: QueuePreviewPlaybackMath.seconds(from: player.currentTime) ?? 0,
                isPlaying: player.isPlaying
            )
        }
        onExpand(snapshot)
    }

    private func restoreMiniPlaybackSnapshot(operationID: UUID) async throws {
        guard let snapshot = preview.playbackSnapshot else { return }
        try await QueuePreviewPlaybackRestorer.restore(
            snapshot: snapshot,
            validate: { try playbackLifetime.check(operationID) },
            isSeekable: { player.isSeekable },
            durationSeconds: { QueuePreviewPlaybackMath.seconds(from: player.duration) },
            seek: { try await QueuePreviewVLCSeek.seek(player, to: $0, pauseBeforeSeeking: !snapshot.isPlaying,
                                                      validate: { try playbackLifetime.check(operationID) }) },
            setPlaying: { if $0 { player.resume() } else { player.pause() } }
        )
        try playbackLifetime.check(operationID)
        player.isMuted = false
        AppLogger.info("Queue preview playback state restored", category: .ui, metadata: [
            "seconds": "\(QueuePreviewPlaybackMath.seconds(from: player.currentTime) ?? 0)",
            "requestedSeconds": "\(snapshot.seconds)", "playing": "\(player.isPlaying)", "mode": "mini"
        ])
    }

    private var isPictureInPictureActive: Bool {
        pipController?.isActive == true
    }

    private var canTogglePictureInPicture: Bool {
        guard let pipController else {
            return false
        }
        return pipController.isPossible || pipController.isActive
    }

    private func togglePictureInPicture() {
        guard let pipController, canTogglePictureInPicture else {
            AppLogger.info(
                "Queue mini player PiP ignored because controller is unavailable",
                category: .ui,
                metadata: ["name": preview.displayName]
            )
            return
        }

        let wasActive = pipController.isActive
        pipController.toggle()
        AppLogger.info(
            wasActive ? "Queue mini player PiP exit requested" : "Queue mini player PiP requested",
            category: .ui,
            metadata: [
                "name": preview.displayName,
                "possible": "\(pipController.isPossible)",
                "active": "\(pipController.isActive)"
            ]
        )
    }

    private func beginVideoPlaybackAdSuppressionIfNeeded() {
        guard !didBeginVideoPlaybackAdSuppression else {
            return
        }
        didBeginVideoPlaybackAdSuppression = true
        AdMobBootstrapper.beginVideoPlaybackAdSuppression(reason: "queueMiniPlayer")
    }

    private func endVideoPlaybackAdSuppressionIfNeeded() {
        guard didBeginVideoPlaybackAdSuppression else {
            return
        }
        didBeginVideoPlaybackAdSuppression = false
        AdMobBootstrapper.endVideoPlaybackAdSuppression(reason: "queueMiniPlayer")
    }

    private func playMiniPreviewWithFallbacks(operationID: UUID) async throws -> Bool {
        let demuxModes = QueuePreviewPlayerFactory.previewDemuxModes(for: preview.sourceURL)
        return try await QueuePreviewPlaybackAttempts.run(
            demuxModes: demuxModes,
            validate: { try playbackLifetime.check(operationID) },
            stop: { player.stop() },
            play: { index, demuxMode in
                let media = try makeMiniPreviewMedia(demuxMode: demuxMode)
                try player.play(media)
                AppLogger.info(
                    "Queue mini player playback attempt started",
                    category: .ui,
                    metadata: [
                        "name": preview.displayName,
                        "attempt": "\(index + 1)",
                        "demux": demuxMode.logValue,
                    ]
                )
            },
            waitForOutput: { try await waitForVideoOutput(operationID: operationID) },
            didFinishAttempt: { index, demuxMode, ready in
                if ready {
                    AppLogger.info(
                        "Queue mini player video output ready",
                        category: .ui,
                        metadata: [
                            "name": preview.displayName,
                            "attempt": "\(index + 1)",
                            "demux": demuxMode.logValue,
                            "activeVideoOutputs": "\(player.activeVideoOutputs)",
                            "hasVideoOutput": "\(player.hasVideoOutput)",
                        ]
                    )
                }
            }
        )
    }

    private func makeMiniPreviewMedia(demuxMode: QueuePreviewDemuxMode) throws -> Media {
        let media = try Media(url: preview.sourceURL)
        let options = QueuePreviewPlayerFactory.configureSoftwareDecodeOptions(
            on: media,
            sourceURL: preview.sourceURL,
            demuxMode: demuxMode
        )
        AppLogger.info(
            "Queue mini player media configured",
            category: .ui,
            metadata: [
                "name": preview.displayName,
                "demux": demuxMode.logValue,
                "options": options.joined(separator: "|")
            ]
        )
        return media
    }

    private func configurePlayerAudioForMiniPlayback() {
        player.role = .video
        player.isMuted = false
        do {
            try player.setAudioVolume(.unity)
        } catch {
            AppLogger.warning(
                "Queue mini player volume setup failed",
                category: .ui,
                metadata: [
                    "name": preview.displayName,
                    "error": String(describing: error)
                ]
            )
        }
    }

    @MainActor
    private func waitForVideoSurfaceAttachment(operationID: UUID) async throws {
        for _ in 0..<20 {
            try playbackLifetime.check(operationID)
            if didAttachVideoSurface {
                try await Task.sleep(nanoseconds: 120_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    private func waitForVideoOutput(operationID: UUID) async throws -> Bool {
        for _ in 0..<80 {
            try playbackLifetime.check(operationID)
            if player.hasVideoOutput || player.activeVideoOutputs > 0 {
                return true
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try playbackLifetime.check(operationID)
        return player.hasVideoOutput || player.activeVideoOutputs > 0
    }

    private func shutdownMiniPlayer() {
        guard !didRequestShutdown else {
            return
        }
        didRequestShutdown = true
        playbackLifetime.invalidate()
        pipController?.stop()
        endVideoPlaybackAdSuppressionIfNeeded()
        let sessionID = miniSessionID
        Task { @MainActor in
            await player.shutdown()
            QueuePreviewAudioSessionController.deactivateAfterPreview(id: sessionID)
        }
    }
}

private struct PreviewBadgeFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let rows = rows(for: subviews, maxWidth: maxWidth)
        let width = rows.reduce(CGFloat.zero) { max($0, $1.size.width) }
        let height = rows.reduce(CGFloat.zero) { $0 + $1.size.height }
            + CGFloat(max(0, rows.count - 1)) * verticalSpacing

        return CGSize(
            width: maxWidth.isFinite ? min(width, maxWidth) : width,
            height: height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX

            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(
                        width: min(item.size.width, bounds.width),
                        height: item.size.height
                    )
                )
                x += item.size.width + horizontalSpacing
            }

            y += row.size.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [PreviewBadgeRow] {
        guard !subviews.isEmpty else {
            return []
        }

        let effectiveMaxWidth = maxWidth.isFinite && maxWidth > 0
            ? maxWidth
            : .greatestFiniteMagnitude
        var rows: [PreviewBadgeRow] = []
        var currentItems: [PreviewBadgeItem] = []
        var currentSize = CGSize.zero

        for index in subviews.indices {
            let itemSize = size(for: subviews[index], maxWidth: effectiveMaxWidth)
            let item = PreviewBadgeItem(index: index, size: itemSize)
            let nextWidth = currentItems.isEmpty
                ? itemSize.width
                : currentSize.width + horizontalSpacing + itemSize.width

            if !currentItems.isEmpty && nextWidth > effectiveMaxWidth {
                rows.append(PreviewBadgeRow(items: currentItems, size: currentSize))
                currentItems = [item]
                currentSize = itemSize
            } else {
                currentItems.append(item)
                currentSize.width = nextWidth
                currentSize.height = max(currentSize.height, itemSize.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(PreviewBadgeRow(items: currentItems, size: currentSize))
        }

        return rows
    }

    private func size(for subview: Subviews.Element, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, ideal.width > maxWidth else {
            return ideal
        }

        let constrained = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        return CGSize(
            width: min(constrained.width, maxWidth),
            height: constrained.height
        )
    }

    private struct PreviewBadgeRow {
        var items: [PreviewBadgeItem]
        var size: CGSize
    }

    private struct PreviewBadgeItem {
        var index: Int
        var size: CGSize
    }
}

@MainActor
private final class QueuePreviewSystemVolumeController: ObservableObject {
    @Published private(set) var volume: Float

    private let audioSession: AVAudioSession
    private weak var volumeSlider: UISlider?
    private var outputVolumeObservation: NSKeyValueObservation?

    init(audioSession: AVAudioSession = .sharedInstance()) {
        self.audioSession = audioSession
        volume = audioSession.outputVolume
        outputVolumeObservation = audioSession.observe(\.outputVolume, options: [.initial, .new]) { [weak self] session, change in
            let nextVolume = change.newValue ?? session.outputVolume
            Task { @MainActor [weak self] in
                self?.volume = Self.clampedVolume(nextVolume)
            }
        }
    }

    static func clampedVolume(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    func attach(volumeView: MPVolumeView) {
        volumeView.showsVolumeSlider = true
        if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
            volumeSlider = slider
            slider.setValue(volume, animated: false)
            slider.sendActions(for: .valueChanged)
            return
        }

        Task { @MainActor [weak self, weak volumeView] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let volumeView else {
                return
            }
            self?.attach(volumeView: volumeView)
        }
    }

    func setVolume(_ value: Float) {
        let nextVolume = Self.clampedVolume(value)
        volume = nextVolume
        guard let volumeSlider else {
            return
        }
        volumeSlider.setValue(nextVolume, animated: false)
        volumeSlider.sendActions(for: .valueChanged)
        volumeSlider.sendActions(for: .touchUpInside)
    }
}

private struct QueuePreviewSystemVolumeBridgeView: UIViewRepresentable {
    @ObservedObject var controller: QueuePreviewSystemVolumeController

    func makeUIView(context _: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: .zero)
        controller.attach(volumeView: volumeView)
        return volumeView
    }

    func updateUIView(_ volumeView: MPVolumeView, context _: Context) {
        controller.attach(volumeView: volumeView)
    }
}

@MainActor
enum QueuePreviewAudioSessionController {
    private static let lifetime = QueuePreviewAudioSessionLifetime(
        activate: { await QueuePreviewAudioSessionWorker.activate() },
        deactivate: { await QueuePreviewAudioSessionWorker.deactivate() }
    )

    static func activateForPreview(id: String) async throws {
        try await lifetime.activate(id: id)
    }

    static func deactivateAfterPreview(id: String) {
        lifetime.deactivate(id: id)
    }
}

// Session requests are serialized across full/mini and native/VLC transitions.
// An old player's delayed shutdown must not deactivate a newer player's audio.
@MainActor
final class QueuePreviewAudioSessionLifetime {
    private(set) var ownerID: String?
    private var requestID = UUID()
    private var lastOperation: Task<Void, Never>?
    private let activateBody: @MainActor () async -> Void
    private let deactivateBody: @MainActor () async -> Void

    init(activate: @escaping @MainActor () async -> Void, deactivate: @escaping @MainActor () async -> Void) {
        activateBody = activate
        deactivateBody = deactivate
    }

    func activate(id: String) async throws {
        try Task.checkCancellation()
        let request = UUID()
        requestID = request
        ownerID = id
        let previous = lastOperation
        let operation = Task { @MainActor in
            await previous?.value
            guard self.requestID == request, self.ownerID == id else { return }
            await self.activateBody()
        }
        lastOperation = operation
        await operation.value
        try Task.checkCancellation()
        guard requestID == request, ownerID == id else { throw CancellationError() }
    }

    func deactivate(id: String) {
        guard ownerID == id else { return }
        ownerID = nil
        let request = UUID()
        requestID = request
        let previous = lastOperation
        lastOperation = Task { @MainActor in
            await previous?.value
            guard self.requestID == request, self.ownerID == nil else { return }
            await self.deactivateBody()
        }
    }

    func waitForPendingOperations() async { await lastOperation?.value }
}

private enum QueuePreviewAudioSessionWorker {
    private static let queue = DispatchQueue(label: "com.taption.encoder.preview-audio", qos: .userInitiated)

    static func activate() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                do {
                    // Output-only playback already supports AirPlay and Bluetooth A2DP.
                    // allowAirPlay is only valid with playAndRecord (SDK category contract).
                    try session.setCategory(.playback, mode: .moviePlayback, options: [])
                    if #available(iOS 27.0, *) {
                        session.activate(options: []) { activated, error in
                            logActivation(session, activated: activated, error: error, api: "asynchronous")
                            continuation.resume()
                        }
                    } else {
                        try session.setActive(true)
                        logActivation(session, activated: true, error: nil, api: "background")
                        continuation.resume()
                    }
                } catch {
                    logActivation(session, activated: false, error: error, api: "configuration")
                    continuation.resume()
                }
            }
        }
    }

    static func deactivate() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                if #available(iOS 27.0, *) {
                    session.deactivate(options: .notifyOthersOnDeactivation) { deactivated, error in
                        logDeactivation(deactivated: deactivated, error: error)
                        continuation.resume()
                    }
                } else {
                    do {
                        try session.setActive(false, options: .notifyOthersOnDeactivation)
                        logDeactivation(deactivated: true, error: nil)
                    } catch {
                        logDeactivation(deactivated: false, error: error)
                    }
                    continuation.resume()
                }
            }
        }
    }

    private static func logActivation(_ session: AVAudioSession, activated: Bool, error: Error?, api: String) {
        if !activated || error != nil {
            AppLogger.error("Queue preview audio session activation failed", category: .ui, metadata: [
                "error": error?.localizedDescription ?? "Session did not activate", "api": api
            ])
            return
        }
        AppLogger.info("Queue preview audio session activated", category: .ui, metadata: [
            "category": session.category.rawValue, "mode": session.mode.rawValue,
            "outputVolume": String(format: "%.2f", session.outputVolume),
            "api": api, "fallback": "false"
        ])
    }

    private static func logDeactivation(deactivated: Bool, error: Error?) {
        if !deactivated || error != nil {
            AppLogger.warning("Queue preview audio session deactivation failed", category: .ui, metadata: [
                "error": error?.localizedDescription ?? "Session did not deactivate"
            ])
        } else {
            AppLogger.info("Queue preview audio session deactivated", category: .ui)
        }
    }
}

enum QueuePreviewDemuxMode: Equatable {
    case automatic
    case avformat

    var logValue: String {
        switch self {
        case .automatic:
            return "automatic"
        case .avformat:
            return "avformat"
        }
    }
}

@MainActor
final class QueuePreviewPlaybackLifetime {
    private var operationID: UUID?

    func begin() -> UUID {
        let id = UUID()
        operationID = id
        return id
    }

    func isCurrent(_ id: UUID) -> Bool { operationID == id }
    func invalidate() { operationID = nil }

    func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard isCurrent(id) else { throw CancellationError() }
    }
}

@MainActor
enum QueuePreviewPlaybackAttempts {
    static func run(
        demuxModes: [QueuePreviewDemuxMode],
        validate: () throws -> Void,
        stop: () -> Void,
        play: (Int, QueuePreviewDemuxMode) throws -> Void,
        waitForOutput: () async throws -> Bool,
        didFinishAttempt: (Int, QueuePreviewDemuxMode, Bool) -> Void
    ) async throws -> Bool {
        for (index, mode) in demuxModes.enumerated() {
            try validate()
            stop()
            try await Task.sleep(nanoseconds: index == 0 ? 80_000_000 : 180_000_000)
            try validate()
            try play(index, mode)
            let ready = try await waitForOutput()
            try validate()
            didFinishAttempt(index, mode, ready)
            if ready { return true }
        }
        return false
    }
}

enum QueuePreviewPlaybackResumeError: LocalizedError {
    case notSeekable
    case seekNotCompleted

    var errorDescription: String? {
        "Playback position could not be restored. Close and open the video again."
    }
}

@MainActor
enum QueuePreviewSeekCompletion {
    static func confirmPausedSeek(
        validate: () throws -> Void,
        waitForOutput: () async throws -> Void,
        retryWhilePlaying: () async throws -> Void
    ) async throws {
        try validate()
        do {
            try await waitForOutput()
        } catch QueuePreviewPlaybackResumeError.seekNotCompleted {
            try validate()
            try await retryWhilePlaying()
        }
        try validate()
    }

    static func waitUntilReady(
        isPlaying: () -> Bool,
        reportedSeconds: () -> Double?,
        validate: () throws -> Void,
        maxPolls: Int = 100
    ) async throws {
        // A vout and seekable flag can precede a stable input/audio clock.
        // Seeking during that opening window may be accepted but ignored.
        for _ in 0..<maxPolls {
            try validate()
            if isPlaying(), let seconds = reportedSeconds(), seconds.isFinite, seconds > 0 { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try validate()
        throw QueuePreviewPlaybackResumeError.seekNotCompleted
    }

    static func wait(
        targetSeconds: Double,
        reportedSeconds: () -> Double?,
        validate: () throws -> Void,
        didDisplayFrame: () -> Bool = { false },
        maxPolls: Int = 250
    ) async throws {
        // SwiftVLC's currentTime is optimistic after seek(). Only a native
        // time/position event can confirm that the asynchronous seek landed.
        var closestNativeSeconds: Double?
        for _ in 0..<maxPolls {
            try validate()
            if let seconds = reportedSeconds(), seconds.isFinite {
                if closestNativeSeconds.map({ abs(seconds - targetSeconds) < abs($0 - targetSeconds) }) ?? true {
                    closestNativeSeconds = seconds
                }
                // Native time events can arrive about 400 ms after a playing
                // seek. Confirm that bounded delay instead of treating it as
                // a failed seek, while rejecting unrelated timeline positions.
                if abs(seconds - targetSeconds) <= 0.5 { return }
            }
            // Paused libVLC seeks do not always emit timeline events.
            // A new displayed video frame is an independent output ack.
            if didDisplayFrame() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try validate()
        AppLogger.warning("Queue preview seek confirmation timed out", category: .ui, metadata: [
            "targetSeconds": String(targetSeconds),
            "closestNativeSeconds": closestNativeSeconds.map(String.init(describing:)) ?? "none"
        ])
        throw QueuePreviewPlaybackResumeError.seekNotCompleted
    }
}

@MainActor
enum QueuePreviewVLCSeek {
    private final class NativeClock { var seconds: Double? }

    static func seek(
        _ player: Player, to seconds: Double, pauseBeforeSeeking: Bool, validate: () throws -> Void
    ) async throws {
        try validate()
        let clock = NativeClock()
        let events = player.events(policy: .newest(8), filter: {
            if case .timeChanged = $0 { return true }
            if case .positionChanged = $0 { return true }
            return false
        })
        let observer = Task { @MainActor in
            for await event in events {
                guard !Task.isCancelled else { return }
                if case .timeChanged(let time) = event {
                    clock.seconds = QueuePreviewPlaybackMath.seconds(from: time)
                } else if case .positionChanged(let position) = event,
                          let duration = QueuePreviewPlaybackMath.seconds(from: player.duration), duration > 0 {
                    // A paused seek may only publish a native position event.
                    clock.seconds = position * duration
                }
            }
        }
        defer { observer.cancel() }
        // Warm the input clock before pausing or seeking. For paused handoffs,
        // seek only after pause is acknowledged to avoid timeline drift.
        player.resume()
        try await QueuePreviewSeekCompletion.waitUntilReady(
            isPlaying: { player.state == .playing }, reportedSeconds: { clock.seconds }, validate: validate
        )
        AppLogger.info("Queue preview seek ready", category: .ui, metadata: [
            "targetSeconds": "\(seconds)", "nativeSeconds": "\(clock.seconds ?? 0)"
        ])
        if pauseBeforeSeeking {
            player.pause()
            try await waitForPause(player, validate: validate)
            try await Task.sleep(for: .milliseconds(50))
            try validate()
        }
        let displayedPictures = pauseBeforeSeeking ? player.statistics?.displayedPictures : nil
        clock.seconds = nil
        try player.seek(to: .seconds(seconds))
        if pauseBeforeSeeking {
            try await QueuePreviewSeekCompletion.confirmPausedSeek(
                validate: validate,
                waitForOutput: {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["TAPTION_FORCE_PAUSED_SEEK_RETRY"] == "1" {
                        throw QueuePreviewPlaybackResumeError.seekNotCompleted
                    }
                    #endif
                    try await QueuePreviewSeekCompletion.wait(
                        targetSeconds: seconds, reportedSeconds: { clock.seconds }, validate: validate,
                        didDisplayFrame: {
                            guard let displayedPictures, let current = player.statistics?.displayedPictures else { return false }
                            return current > displayedPictures
                        }, maxPolls: 25
                    )
                },
                retryWhilePlaying: {
                    AppLogger.info("Queue preview paused seek retried while muted", category: .ui, metadata: [
                        "targetSeconds": "\(seconds)"
                    ])
                    let wasMuted = player.isMuted
                    player.isMuted = true
                    defer {
                        if (try? validate()) != nil { player.isMuted = wasMuted }
                    }
                    clock.seconds = nil
                    player.resume()
                    // Resume is asynchronous too. A seek sent while the input
                    // is still paused can repeat the original ignored seek.
                    try await QueuePreviewSeekCompletion.waitUntilReady(
                        isPlaying: { player.state == .playing }, reportedSeconds: { clock.seconds },
                        validate: validate
                    )
                    clock.seconds = nil
                    try player.seek(to: .seconds(seconds))
                    try await QueuePreviewSeekCompletion.wait(
                        targetSeconds: seconds, reportedSeconds: { clock.seconds }, validate: validate
                    )
                    try validate()
                    player.pause()
                    try await waitForPause(player, validate: validate)
                }
            )
        } else {
            try await QueuePreviewSeekCompletion.wait(
                targetSeconds: seconds, reportedSeconds: { clock.seconds }, validate: validate
            )
        }
        AppLogger.info("Queue preview seek completed", category: .ui, metadata: [
            "targetSeconds": "\(seconds)", "nativeSeconds": clock.seconds.map(String.init(describing:)) ?? "none",
            "paused": "\(pauseBeforeSeeking)",
            "displayedPictures": player.statistics.map { "\($0.displayedPictures)" } ?? "unavailable"
        ])
    }

    private static func waitForPause(_ player: Player, validate: () throws -> Void) async throws {
        for _ in 0..<100 {
            try validate()
            if player.state == .paused { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try validate()
        throw QueuePreviewPlaybackResumeError.seekNotCompleted
    }
}

@MainActor
enum QueuePreviewPlaybackRestorer {
    static func restore(
        snapshot: QueuePreviewPlaybackSnapshot,
        validate: () throws -> Void,
        isSeekable: () -> Bool,
        durationSeconds: () -> Double?,
        seek: (Double) async throws -> Void,
        setPlaying: (Bool) -> Void
    ) async throws {
        try validate()
        if snapshot.seconds > 0 {
            for _ in 0..<100 {
                try validate()
                if isSeekable() { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            try validate()
            guard isSeekable() else { throw QueuePreviewPlaybackResumeError.notSeekable }
            try await seek(snapshot.clampedSeconds(durationSeconds: durationSeconds()))
        }
        try validate()
        setPlaying(snapshot.isPlaying)
    }
}

#if DEBUG
enum QueuePreviewDebugHandoff {
    static var automaticallyRestoresFullPreview: Bool {
        ProcessInfo.processInfo.environment["TAPTION_AUTO_RESTORE_PREVIEW"] == "1"
    }

    static var requestedSnapshot: QueuePreviewPlaybackSnapshot? {
        guard let rawSeconds = ProcessInfo.processInfo.environment["TAPTION_HANDOFF_SEEK_SECONDS"],
              let seconds = Double(rawSeconds), seconds.isFinite, seconds >= 0 else { return nil }
        return QueuePreviewPlaybackSnapshot(
            seconds: seconds,
            isPlaying: ProcessInfo.processInfo.environment["TAPTION_HANDOFF_PAUSED"] != "1"
        )
    }
}
#endif

enum QueuePreviewPlayerFactory {
    static let softwareDecodeInstance = makeSoftwareDecodeInstance(applicationName: "BOKKI Encoder Preview")
    static let thumbnailDecodeInstance = makeSoftwareDecodeInstance(applicationName: "BOKKI Encoder Thumbnail")

    @MainActor
    static func makePreviewPlayer() -> Player {
        Player(
            instance: makeSoftwareDecodeInstance(
                applicationName: "BOKKI Encoder Preview \(UUID().uuidString)"
            )
        )
    }

    @discardableResult
    static func configureSoftwareDecodeOptions(
        on media: Media,
        sourceURL: URL,
        allowsAudio: Bool = true,
        demuxMode: QueuePreviewDemuxMode = .automatic
    ) -> [String] {
        let options = softwareDecodeOptions(
            for: sourceURL,
            allowsAudio: allowsAudio,
            demuxMode: demuxMode
        )
        for option in options {
            media.addOption(option)
        }
        return options
    }

    static func previewDemuxModes(for sourceURL: URL) -> [QueuePreviewDemuxMode] {
        switch sourceURL.pathExtension.lowercased() {
        case "mov", "qt":
            return [.automatic, .avformat]
        case "avi", "divx":
            return [.avformat, .automatic]
        default:
            return [.automatic]
        }
    }

    static func softwareDecodeOptions(
        for sourceURL: URL,
        allowsAudio: Bool = true,
        demuxMode: QueuePreviewDemuxMode = .automatic
    ) -> [String] {
        var options = [
            ":no-sub-autodetect-file",
            ":no-drop-late-frames",
            ":no-skip-frames"
        ]
        if !allowsAudio {
            options.append(":no-audio")
        }
        if shouldUseAVFormatDemux(for: sourceURL, demuxMode: demuxMode) {
            options.append(":demux=avformat")
        }
        if sourceURL.pathExtension.lowercased() == "h261" {
            options.append(":avformat-format=h261")
        }
        if sourceURL.pathExtension.lowercased() == "vc1" {
            options.append(":avformat-format=vc1")
        }
        return options
    }

    private static func shouldUseAVFormatDemux(
        for sourceURL: URL,
        demuxMode: QueuePreviewDemuxMode
    ) -> Bool {
        switch demuxMode {
        case .avformat:
            return true
        case .automatic:
            switch sourceURL.pathExtension.lowercased() {
            case "avi", "divx", "h261", "h263", "m1v", "m2v", "vc1":
                return true
            default:
                return false
            }
        }
    }

    private static func makeSoftwareDecodeInstance(applicationName: String) -> VLCInstance {
        do {
            return try VLCInstance(
                arguments: VLCInstance.defaultArguments,
                applicationName: applicationName,
                httpUserAgent: "TaptionEncoder/1.0"
            )
        } catch {
            AppLogger.warning(
                "Falling back to the shared VLC instance for queue preview",
                category: .ui,
                metadata: ["error": String(describing: error)]
            )
            return .shared
        }
    }
}
