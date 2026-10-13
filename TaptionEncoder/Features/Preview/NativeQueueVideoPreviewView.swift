import AVFoundation
import AVKit
import SwiftUI
import UIKit

// HEVC with Alpha needs Apple's compositor. VLC can report a video output
// without displaying sparse transparent subtitle frames correctly.
struct NativeQueueVideoPreviewView: View {
    var preview: QueueVideoPreview
    var adUnitID: String = ""
    var isMiniPlayer = false
    var isAddedToList = false
    var canAddToList = false
    var onAddToList: () -> Void = {}
    var onClose: () -> Void
    var onMinimize: (QueuePreviewPlaybackSnapshot) -> Void
    var onPictureInPictureActiveChanged: (Bool) -> Void = { _ in }
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}
    var onAuthorizeFolder: (URL, Int) -> String? = { _, _ in nil }

    @StateObject private var playback = NativeQueuePreviewPlayback()
    @State private var didBeginAdSuppression = false
    @State private var areControlsVisible = false
    @State private var isScrubbing = false
    @State private var scrubSeconds = 0.0

    var body: some View {
        Group {
            if isMiniPlayer {
                VStack(spacing: 0) {
                    videoSurface
                        .aspectRatio(preview.aspectRatio ?? 16.0 / 9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .topTrailing) { headerButtons }
                    Text(preview.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(8)
                }
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16)).allowsHitTesting(false))
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .top) {
                        videoSurface
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .ignoresSafeArea()
                            .zIndex(0)
                        if areControlsVisible {
                            VStack {
                                AdMobBannerSlotView(adUnitID: adUnitID, displayScale: 1)
                                    .padding(.top, max(proxy.safeAreaInsets.top, 8))
                                Spacer(minLength: 0)
                            }
                            .zIndex(1)
                            .transition(.opacity)

                            if !playback.isLoading && playback.errorMessage == nil {
                                centerPlaybackControls
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .zIndex(1)
                                    .transition(.opacity)
                            }

                            playbackControls
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .padding(.horizontal, proxy.size.width < 380 ? 10 : 16)
                                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 12))
                                .zIndex(1)
                                .transition(.opacity)
                        }
                    }
                }
                .background(.black)
            }
        }
        .onAppear {
            if !didBeginAdSuppression {
                didBeginAdSuppression = true
                AdMobBootstrapper.beginVideoPlaybackAdSuppression(reason: "nativeQueuePreview")
            }
        }
        .task(id: preview.id) {
            areControlsVisible = false
            isScrubbing = false
            scrubSeconds = 0
            await playback.start(preview: preview, isMiniPlayer: isMiniPlayer)
            #if DEBUG
            await debugHandoffIfRequested()
            #endif
        }
        .onDisappear {
            playback.shutdown()
            onPictureInPictureActiveChanged(false)
            if didBeginAdSuppression {
                didBeginAdSuppression = false
                AdMobBootstrapper.endVideoPlaybackAdSuppression(reason: "nativeQueuePreview")
            }
        }
    }

    private var videoSurface: some View {
        NativeQueuePlayerController(
            playback: playback,
            startsPictureInPictureAutomatically: false,
            showsPlaybackControls: isMiniPlayer,
            onVideoTap: toggleControls,
            onPictureInPictureActiveChanged: onPictureInPictureActiveChanged
        )
        .background(.black)
        .overlay {
            if let error = playback.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.black.opacity(0.7))
            } else if playback.isLoading {
                ProgressView().tint(.white).allowsHitTesting(false)
            }
        }
        .accessibilityAction(named: Text("Show playback controls")) {
            areControlsVisible = true
        }
    }

    private func toggleControls() {
        guard !isMiniPlayer, !isScrubbing else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            if playback.errorMessage != nil {
                areControlsVisible = true
            } else {
                areControlsVisible.toggle()
            }
        }
    }

    private var centerPlaybackControls: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let duration = playbackDuration
            QueuePreviewCenterControls(
                isPlaying: playback.player.rate > 0,
                canSeek: duration > 0,
                onBackward: { seek(to: playback.player.currentTime().seconds - 10, duration: duration) },
                onToggle: {
                    if playback.player.rate > 0 { playback.player.pause() } else { playback.player.play() }
                },
                onForward: { seek(to: playback.player.currentTime().seconds + 10, duration: duration) }
            )
        }
    }

    private var playbackDuration: Double {
        let raw = playback.player.currentItem?.duration.seconds ?? 0
        return raw.isFinite ? max(raw, 0) : 0
    }

    private var playbackControls: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let duration = playbackDuration
            let rawSeconds = playback.player.currentTime().seconds
            let seconds = rawSeconds.isFinite ? min(max(rawSeconds, 0), duration) : 0
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { isScrubbing ? scrubSeconds : seconds },
                    set: {
                        scrubSeconds = $0
                        isScrubbing = true
                    }
                ), in: 0...max(duration, 1), onEditingChanged: { editing in
                    if editing {
                        if !isScrubbing { scrubSeconds = seconds }
                        isScrubbing = true
                    } else {
                        seek(to: scrubSeconds, duration: duration)
                        isScrubbing = false
                    }
                })
                .disabled(duration <= 0 || playback.isLoading)
                .accessibilityLabel("Playback position")
                .accessibilityIdentifier("preview.timeline")
                HStack {
                    Text(QueuePreviewPlaybackMath.formattedSeconds(isScrubbing ? scrubSeconds : seconds))
                    Spacer()
                    Text(QueuePreviewPlaybackMath.formattedSeconds(duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("preview.time")
                .padding(.bottom, 8)

                QueuePreviewActionBar(
                    preview: preview, isAdded: isAddedToList,
                    canAdd: canAddToList && !playback.isLoading, canNavigate: !playback.isLoading,
                    onAdd: onAddToList, onClose: onClose,
                    onPrevious: onPrevious, onNext: onNext, onAuthorizeFolder: onAuthorizeFolder
                )
            }
            .tint(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func seek(to seconds: Double, duration: Double) {
        guard let seconds = QueuePreviewPlaybackMath.clampedSeekSeconds(seconds, duration: duration) else { return }
        playback.player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                             toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private var headerButtons: some View {
        HStack(spacing: 4) {
            if isMiniPlayer {
                Button { onMinimize(playback.snapshot()) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Expand")
                .accessibilityIdentifier("preview.mini.expand")
            }
            Button(action: onClose) {
                Image(systemName: "xmark").frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier(isMiniPlayer ? "preview.mini.close" : "preview.close")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.black.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(isMiniPlayer ? 6 : 0)
    }

    #if DEBUG
    @MainActor
    private func debugHandoffIfRequested() async {
        let environment = ProcessInfo.processInfo.environment
        let shouldMinimize = !isMiniPlayer && preview.playbackSnapshot == nil
            && environment["TAPTION_AUTO_MINIMIZE_PREVIEW"] == "1"
        let shouldExpand = isMiniPlayer && QueuePreviewDebugHandoff.automaticallyRestoresFullPreview
        guard shouldMinimize || shouldExpand else { return }
        do {
            for _ in 0..<500 {
                try Task.checkCancellation()
                if !playback.isLoading { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard !playback.isLoading, playback.errorMessage == nil else { return }
            if shouldMinimize, let requested = QueuePreviewDebugHandoff.requestedSnapshot {
                guard await playback.prepareDebugHandoff(requested) else { return }
            }
            try await Task.sleep(for: .milliseconds(400))
            try Task.checkCancellation()
            onMinimize(playback.snapshot())
        } catch {}
    }
    #endif
}

@MainActor
private final class NativeQueuePreviewPlayback: ObservableObject {
    let player = AVPlayer()
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    private var itemObservation: NSKeyValueObservation?
    private var sessionID: String?
    private var displayName = ""
    private var requestedSnapshot: QueuePreviewPlaybackSnapshot?
    private var restorationTask: Task<Void, Never>?
    private var didRequestRestoration = false
    private var didRestoreSnapshot = false
    private var hasReadyVideoFrame = false

    func start(preview: QueueVideoPreview, isMiniPlayer: Bool) async {
        shutdown()
        isLoading = true
        errorMessage = nil
        displayName = preview.displayName
        requestedSnapshot = preview.playbackSnapshot
        didRequestRestoration = false
        didRestoreSnapshot = preview.playbackSnapshot == nil
        hasReadyVideoFrame = false
        let sessionID = "\(preview.id).native\(isMiniPlayer ? ".mini" : "").\(UUID().uuidString)"
        self.sessionID = sessionID
        do {
            try await QueuePreviewAudioSessionController.activateForPreview(id: sessionID)
            try Task.checkCancellation()
            guard self.sessionID == sessionID else { return }
        } catch is CancellationError {
            if self.sessionID == sessionID { shutdown() }
            return
        } catch {
            guard self.sessionID == sessionID else { return }
            shutdown()
            isLoading = false
            errorMessage = "Audio playback could not start. Close the preview and try again."
            AppLogger.error("Native preview audio activation failed", category: .ui,
                            metadata: ["error": error.localizedDescription])
            return
        }
        player.isMuted = false
        player.volume = 1
        let item = AVPlayerItem(url: preview.sourceURL)
        player.replaceCurrentItem(with: item)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                if item.status == .failed {
                    self.isLoading = false
                    self.errorMessage = "Preview unavailable. Check that the video opens in Files, then try again."
                    AppLogger.error("Native queue preview failed", category: .ui, metadata: [
                        "name": self.displayName,
                        "error": item.error?.localizedDescription ?? "Unknown playback error"
                    ])
                } else if item.status == .readyToPlay,
                          let snapshot = self.requestedSnapshot, !self.didRequestRestoration {
                    self.didRequestRestoration = true
                    self.restorationTask = Task { @MainActor [weak self] in
                        await self?.restore(snapshot, item: item, sessionID: sessionID, isMiniPlayer: isMiniPlayer)
                    }
                }
            }
        }
        if requestedSnapshot == nil { player.play() }
        AppLogger.info("Native queue preview playback started", category: .ui, metadata: [
            "name": displayName, "codec": preview.codecBadge
        ])
    }

    func videoBecameReady() {
        hasReadyVideoFrame = true
        guard didRestoreSnapshot else { return }
        guard sessionID != nil, isLoading else { return }
        isLoading = false
        AppLogger.info("Native queue preview first video frame ready", category: .ui, metadata: [
            "name": displayName
        ])
        #if DEBUG
        if let rawSeconds = ProcessInfo.processInfo.environment["TAPTION_PREVIEW_SEEK_SECONDS"],
           let seconds = Double(rawSeconds), seconds.isFinite, seconds >= 0 {
            player.pause()
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                AppLogger.info("Native queue preview debug seek completed", category: .ui, metadata: [
                    "seconds": rawSeconds, "finished": "\(finished)"
                ])
            }
        }
        #endif
    }

    func snapshot() -> QueuePreviewPlaybackSnapshot {
        if isLoading {
            return requestedSnapshot ?? QueuePreviewPlaybackSnapshot(seconds: 0, isPlaying: true)
        }
        return QueuePreviewPlaybackSnapshot(
            seconds: player.currentTime().seconds,
            isPlaying: player.timeControlStatus != .paused
        )
    }

    #if DEBUG
    func prepareDebugHandoff(_ snapshot: QueuePreviewPlaybackSnapshot) async -> Bool {
        guard let sessionID, let item = player.currentItem else { return false }
        player.pause()
        let finished = await withCheckedContinuation { continuation in
            player.seek(to: CMTime(seconds: snapshot.clampedSeconds(durationSeconds: item.duration.seconds), preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { continuation.resume(returning: $0) }
        }
        guard finished, self.sessionID == sessionID, player.currentItem === item, !Task.isCancelled else { return false }
        if snapshot.isPlaying { player.play() } else { player.pause() }
        return true
    }
    #endif

    private func restore(
        _ snapshot: QueuePreviewPlaybackSnapshot,
        item: AVPlayerItem,
        sessionID: String,
        isMiniPlayer: Bool
    ) async {
        guard self.sessionID == sessionID, player.currentItem === item, !Task.isCancelled else { return }
        let seconds = snapshot.clampedSeconds(durationSeconds: item.duration.seconds)
        let finished = await withCheckedContinuation { continuation in
            player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { continuation.resume(returning: $0) }
        }
        guard self.sessionID == sessionID, player.currentItem === item, !Task.isCancelled else { return }
        guard finished else {
            isLoading = false
            errorMessage = "Playback position could not be restored. Close and open the video again."
            return
        }
        didRestoreSnapshot = true
        if snapshot.isPlaying { player.play() } else { player.pause() }
        AppLogger.info("Native queue preview playback state restored", category: .ui, metadata: [
            "seconds": "\(player.currentTime().seconds)", "playing": "\(player.timeControlStatus != .paused)",
            "mode": isMiniPlayer ? "mini" : "full"
        ])
        if hasReadyVideoFrame { videoBecameReady() }
    }

    func shutdown() {
        restorationTask?.cancel()
        restorationTask = nil
        itemObservation = nil
        player.currentItem?.cancelPendingSeeks()
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let sessionID {
            QueuePreviewAudioSessionController.deactivateAfterPreview(id: sessionID)
            self.sessionID = nil
        }
    }
}

private struct NativeQueuePlayerController: UIViewControllerRepresentable {
    var playback: NativeQueuePreviewPlayback
    var startsPictureInPictureAutomatically: Bool
    var showsPlaybackControls: Bool
    var onVideoTap: () -> Void
    var onPictureInPictureActiveChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(playback: playback, showsPlaybackControls: showsPlaybackControls, onVideoTap: onVideoTap,
                    onPictureInPictureActiveChanged: onPictureInPictureActiveChanged)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = playback.player
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        controller.showsPlaybackControls = showsPlaybackControls
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = startsPictureInPictureAutomatically
        controller.delegate = context.coordinator
        let videoTap = UITapGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.didTapVideo(_:)))
        videoTap.cancelsTouchesInView = false
        videoTap.delegate = context.coordinator
        controller.view.addGestureRecognizer(videoTap)
        context.coordinator.readyObservation = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) {
            [weak playback] controller, _ in
            guard controller.isReadyForDisplay else { return }
            Task { @MainActor [weak playback, weak controller] in
                playback?.videoBecameReady()
                #if DEBUG
                if let controller {
                    AppLogger.info("Native queue preview display geometry", category: .ui, metadata: [
                        "bounds": String(describing: controller.view.bounds),
                        "videoBounds": String(describing: controller.videoBounds),
                        "rate": String(describing: controller.player?.rate)
                    ])
                }
                #endif
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.onPictureInPictureActiveChanged = onPictureInPictureActiveChanged
        context.coordinator.onVideoTap = onVideoTap
        context.coordinator.showsPlaybackControls = showsPlaybackControls
        controller.showsPlaybackControls = showsPlaybackControls
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.readyObservation = nil
        controller.delegate = nil
        controller.player = nil
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate, UIGestureRecognizerDelegate {
        var readyObservation: NSKeyValueObservation?
        var onVideoTap: () -> Void
        var showsPlaybackControls: Bool
        var onPictureInPictureActiveChanged: (Bool) -> Void
        weak var playback: NativeQueuePreviewPlayback?

        init(playback: NativeQueuePreviewPlayback, showsPlaybackControls: Bool, onVideoTap: @escaping () -> Void,
             onPictureInPictureActiveChanged: @escaping (Bool) -> Void) {
            self.playback = playback
            self.onVideoTap = onVideoTap
            self.showsPlaybackControls = showsPlaybackControls
            self.onPictureInPictureActiveChanged = onPictureInPictureActiveChanged
        }

        @objc func didTapVideo(_ recognizer: UITapGestureRecognizer) {
            if recognizer.state == .ended { onVideoTap() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard showsPlaybackControls else { return true }
            // Transport buttons and the scrubber keep their own gestures.
            var view = touch.view
            while let candidate = view {
                if candidate === gestureRecognizer.view { break }
                if candidate is UIControl || candidate.accessibilityTraits.contains(.adjustable) {
                    return false
                }
                view = candidate.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        nonisolated func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            Task { @MainActor [weak self] in
                self?.onPictureInPictureActiveChanged(true)
                AppLogger.info("Native queue preview PiP started", category: .ui)
            }
        }

        nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            Task { @MainActor [weak self] in
                self?.onPictureInPictureActiveChanged(false)
                AppLogger.info("Native queue preview PiP stopped", category: .ui)
            }
        }

        nonisolated func playerViewController(
            _ playerViewController: AVPlayerViewController,
            failedToStartPictureInPictureWithError error: Error
        ) {
            Task { @MainActor [weak self] in
                self?.onPictureInPictureActiveChanged(false)
                AppLogger.warning("Native queue preview PiP failed", category: .ui, metadata: [
                    "error": error.localizedDescription
                ])
            }
        }

        nonisolated func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            Task { @MainActor [weak self] in
                self?.onPictureInPictureActiveChanged(false)
                completionHandler(self != nil)
            }
        }
    }
}
