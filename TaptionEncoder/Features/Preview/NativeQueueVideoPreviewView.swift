import AVFoundation
import AVKit
import SwiftUI

// HEVC with Alpha needs Apple's compositor. VLC can report a video output
// without displaying sparse transparent subtitle frames correctly.
struct NativeQueueVideoPreviewView: View {
    var preview: QueueVideoPreview
    var adUnitID: String = ""
    var isMiniPlayer = false
    var onClose: () -> Void
    var onMinimize: (QueuePreviewPlaybackSnapshot) -> Void
    var onPictureInPictureActiveChanged: (Bool) -> Void = { _ in }
    var onPrevious: () -> Void = {}
    var onNext: () -> Void = {}

    @StateObject private var playback = NativeQueuePreviewPlayback()
    @State private var didBeginAdSuppression = false

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
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.16)))
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .top) {
                        videoSurface
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .ignoresSafeArea()
                            .zIndex(0)
                        VStack(spacing: 12) {
                            AdMobBannerSlotView(adUnitID: adUnitID, displayScale: 1)
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preview.displayName)
                                        .font(.headline)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                    Text("\(preview.codecBadge) · \(preview.videoInfo.resolution)")
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if let playlist = preview.playlist {
                                    Button(action: onPrevious) {
                                        Image(systemName: "backward.end.fill")
                                    }
                                    .disabled(!playlist.hasPrevious)
                                    .accessibilityLabel("Previous video")
                                    Button(action: onNext) {
                                        Image(systemName: "forward.end.fill")
                                    }
                                    .disabled(!playlist.hasNext)
                                    .accessibilityLabel("Next video")
                                }
                                headerButtons
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.top, max(proxy.safeAreaInsets.top, 8))
                        .padding(.bottom, 12)
                        .background(LinearGradient(
                            colors: [.black.opacity(0.85), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .zIndex(1)
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
            if !isMiniPlayer {
                AppOrientationController.shared.activatePreviewOrientations()
            }
        }
        .task(id: preview.id) {
            await playback.start(preview: preview, isMiniPlayer: isMiniPlayer)
            #if DEBUG
            await debugHandoffIfRequested()
            #endif
        }
        .onDisappear {
            playback.shutdown()
            onPictureInPictureActiveChanged(false)
            if !isMiniPlayer {
                AppOrientationController.shared.restorePortrait()
            }
            if didBeginAdSuppression {
                didBeginAdSuppression = false
                AdMobBootstrapper.endVideoPlaybackAdSuppression(reason: "nativeQueuePreview")
            }
        }
    }

    private var videoSurface: some View {
        NativeQueuePlayerController(
            playback: playback,
            startsPictureInPictureAutomatically: !isMiniPlayer,
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
    }

    private var headerButtons: some View {
        HStack(spacing: 4) {
            Button { onMinimize(playback.snapshot()) } label: {
                Image(systemName: isMiniPlayer
                      ? "arrow.up.left.and.arrow.down.right"
                      : "arrow.down.right.and.arrow.up.left")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(isMiniPlayer ? "Expand" : "Minimize")
            Button(action: onClose) {
                Image(systemName: "xmark").frame(width: 36, height: 36)
            }
            .accessibilityLabel("Close")
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
        } catch { return }
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
    var onPictureInPictureActiveChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(playback: playback, onPictureInPictureActiveChanged: onPictureInPictureActiveChanged)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = playback.player
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = startsPictureInPictureAutomatically
        controller.delegate = context.coordinator
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
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.readyObservation = nil
        controller.delegate = nil
        controller.player = nil
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var readyObservation: NSKeyValueObservation?
        var onPictureInPictureActiveChanged: (Bool) -> Void
        weak var playback: NativeQueuePreviewPlayback?

        init(playback: NativeQueuePreviewPlayback, onPictureInPictureActiveChanged: @escaping (Bool) -> Void) {
            self.playback = playback
            self.onPictureInPictureActiveChanged = onPictureInPictureActiveChanged
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
