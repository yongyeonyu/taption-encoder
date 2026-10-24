import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if DEBUG
@_spi(ValidationHarness) import SwiftVLC
#else
import SwiftVLC
#endif

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
    case close
}

struct QueuePreviewGestureFeedback: Equatable {
    var systemImage: String
    var text: String
}

struct QueuePreviewGestureExcludedFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

struct QueuePreviewGestureExclusionRegion: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: QueuePreviewGestureExcludedFramesKey.self,
                value: [proxy.frame(in: .named("preview.surface"))])
        }
    }
}

struct QueuePreviewSurfaceDragValue {
    var startLocation: CGPoint
    var translation: CGSize
}

// Reject control-bar touches before recognition, while still receiving drags over
// playback buttons and inside the folder browser's scrolling presentation.
struct QueuePreviewSurfacePanGesture: UIGestureRecognizerRepresentable {
    var canStart: (CGPoint) -> Bool
    var onChanged: (QueuePreviewSurfaceDragValue) -> Void
    var onEnded: (QueuePreviewSurfaceDragValue) -> Void
    var onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(converter: converter, canStart: canStart)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.canStart = canStart
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let value = context.coordinator.value()
        switch recognizer.state {
        case .began, .changed: onChanged(value)
        case .ended: onEnded(value)
        case .cancelled, .failed: onCancelled()
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let converter: CoordinateSpaceConverter
        var canStart: (CGPoint) -> Bool

        init(converter: CoordinateSpaceConverter, canStart: @escaping (CGPoint) -> Bool) {
            self.converter = converter
            self.canStart = canStart
        }

        func value() -> QueuePreviewSurfaceDragValue {
            let location = converter.location(in: .named("preview.surface"))
            let delta = converter.translation(in: .named("preview.surface")) ?? .zero
            return QueuePreviewSurfaceDragValue(
                startLocation: CGPoint(x: location.x - delta.x, y: location.y - delta.y),
                translation: CGSize(width: delta.x, height: delta.y))
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            canStart(value().startLocation)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer
        }
    }
}

struct QueuePreviewGestureFeedbackView: View {
    var feedback: QueuePreviewGestureFeedback

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feedback.systemImage)
                .font(.system(size: 20, weight: .semibold))
            Text(feedback.text)
                .font(.headline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.12), lineWidth: 1))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(feedback.text)
        .accessibilityIdentifier("preview.gesture.feedback")
    }
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
    var onAuthorizeFolder: (URL, Int) -> String? = { _, _ in nil }
    var onRestoreFolderNavigation: (Int) -> Bool = { _ in false }
    var onRequestFolderAccess: () -> Bool = { false }

    /// Set once, by whichever engine reports that it cannot present frames. Keeping it optional is
    /// what stops the two engines from handing the same file back and forth: a file gets exactly one
    /// switch, and the second engine's error message is what the user sees.
    @State private var engineOverride: QueuePreviewPlaybackRoute?

    @ViewBuilder
    var body: some View {
        // Keep orientation ownership stable while swiping between VLC and native playback.
        ZStack { playerView }
            .onAppear { AppOrientationController.shared.activatePreviewOrientations() }
            .onDisappear { AppOrientationController.shared.restorePortrait() }
            .onChange(of: preview.id) { _, _ in engineOverride = nil }
            .videoFolderAccessRequest(id: preview.id, directoryURL: preview.folderAccessURL,
                onRequest: onRequestFolderAccess, onConnect: { onAuthorizeFolder($0, 0) })
    }

    private var route: QueuePreviewPlaybackRoute {
        engineOverride ?? QueuePreviewPlaybackRoutePlanner.route(for: preview)
    }

    /// A file gets one engine switch. Asking for the engine that already failed is refused, so the
    /// failure message from that engine stays on screen instead of the view flickering forever.
    private func switchEngine(to requested: QueuePreviewPlaybackRoute) {
        guard engineOverride == nil, requested != route else { return }
        AppLogger.warning(
            "Queue preview switching engines after a failed presentation",
            category: .ui,
            metadata: [
                "name": preview.displayName,
                "codec": preview.codecBadge,
                "from": route == .native ? "native" : "vlc",
                "to": requested == .native ? "native" : "vlc"
            ]
        )
        engineOverride = requested
    }

    @ViewBuilder
    private var playerView: some View {
        switch route {
        case .native:
            NativeQueueVideoPreviewView(
                preview: preview, adUnitID: adUnitID,
                isAddedToList: isAddedToList, canAddToList: canAddToList,
                onAddToList: onAddToList,
                onClose: onClose, onMinimize: onMinimize,
                onPictureInPictureActiveChanged: onPictureInPictureActiveChanged,
                onPrevious: onPrevious, onNext: onNext, onAuthorizeFolder: onAuthorizeFolder,
                onRestoreFolderNavigation: onRestoreFolderNavigation,
                onPlaybackUnavailable: { switchEngine(to: .vlc) }
            )
        case .vlc:
            VLCQueueVideoPreviewView(
                preview: preview, adUnitID: adUnitID,
                isAddedToList: isAddedToList, canAddToList: canAddToList,
                onAddToList: onAddToList,
                onClose: onClose, onMinimize: onMinimize,
                onPictureInPictureActiveChanged: onPictureInPictureActiveChanged,
                onPrevious: onPrevious, onNext: onNext, onAuthorizeFolder: onAuthorizeFolder,
                onRestoreFolderNavigation: onRestoreFolderNavigation,
                onPlaybackUnavailable: { switchEngine(to: .native) }
            )
        }
    }
}

extension View {
    func videoFolderAccessRequest(id: String?, directoryURL: URL?, isInitialRequest: Bool = false,
                                  onRequest: @escaping () -> Bool, onConnect: @escaping (URL) -> String?) -> some View {
        modifier(VideoFolderAccessRequestModifier(requestID: id, directoryURL: directoryURL,
            isInitialRequest: isInitialRequest, onRequest: onRequest, onConnect: onConnect))
    }
}

private struct VideoFolderAccessRequestModifier: ViewModifier {
    var requestID: String?
    var directoryURL: URL?
    var isInitialRequest: Bool
    var onRequest: () -> Bool
    var onConnect: (URL) -> String?
    @State private var prompt: Prompt?
    @State private var showsPicker = false

    private enum Prompt {
        case request
        case failure(String)
    }

    private var title: String {
        if case .failure = prompt { return "Folder access" }
        return isInitialRequest ? "Allow folder access" : "Connect this folder?"
    }

    func body(content: Content) -> some View {
        content
            .task(id: requestID) {
                showsPicker = false
                prompt = requestID != nil && onRequest() ? .request : nil
            }
            .alert(title, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                   presenting: prompt) { value in
                switch value {
                case .request:
                    Button("Connect folder") { showsPicker = true }
                    Button("Not now", role: .cancel) {}
                case .failure:
                    Button("OK", role: .cancel) {}
                }
            } message: { value in
                switch value {
                case .request:
                    Text("Tap Browse at the bottom to choose On My iPhone, iCloud Drive, or another location. Open a parent folder containing your videos, then tap Open at the top right to allow access to that folder and all its subfolders. BOKKI remembers your permission. Add other locations in Menu → Folder Access.")
                case .failure(let message): Text(message)
                }
            }
            .sheet(isPresented: $showsPicker) {
                QueuePreviewFolderAccessPresenter(directoryURL: directoryURL, isPresented: $showsPicker) { url in
                    if let url, let error = onConnect(url) { prompt = .failure(error) }
                }
            }
    }
}

struct QueuePreviewAddListButton: View {
    var isAdded: Bool
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(isAdded ? "Added" : "Add", systemImage: isAdded ? "checkmark" : "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isAdded ? TaptionTheme.accent : .white)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 11)
                .frame(minHeight: 44)
                .background(.white.opacity(0.14), in: Capsule())
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

enum QueuePreviewBarNavigation: Equatable {
    case previous, next
    case folderAccessRequired

    static func destination(translation: CGSize, playlist: QueueVideoPreviewPlaylist?, isEnabled: Bool, needsFolderAccess: Bool = false) -> Self? {
        guard isEnabled,
              translation.width.isFinite, translation.height.isFinite,
              abs(translation.width) >= 44,
              abs(translation.width) > abs(translation.height) * 1.4 else { return nil }
        if translation.width < 0, playlist?.hasNext == true { return .next }
        if translation.width > 0, playlist?.hasPrevious == true { return .previous }
        if needsFolderAccess { return .folderAccessRequired }
        return nil
    }
}

struct QueuePreviewRoundButton: View {
    var symbol: String
    var label: String
    var identifier: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

struct QueuePreviewActionBar: View {
    var preview: QueueVideoPreview
    var isAdded: Bool
    var canAdd: Bool
    var canNavigate: Bool
    var onAdd: () -> Void
    var onClose: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onAuthorizeFolder: (URL, Int) -> String? = { _, _ in nil }
    var onRestoreFolderNavigation: (Int) -> Bool = { _ in false }

    @State private var showsInformation = false
    @State private var isSharing = false
    @State private var shareError: String?
    @State private var errorTitle = "Unable to share"
    @State private var showsFolderAccess = false
    @State private var connectsFolderAfterInformation = false
    @State private var showsFolderHint = false

    var body: some View {
        HStack(spacing: 7) {
            QueuePreviewRoundButton(symbol: "info", label: "Video information", identifier: "preview.info") {
                showsInformation = true
            }
            QueuePreviewRoundButton(symbol: "square.and.arrow.up", label: "Share video", identifier: "preview.share") {
                isSharing = true
            }
            .background {
                QueuePreviewSharePresenter(sourceURL: preview.sourceURL, isPresented: $isSharing) {
                    errorTitle = "Unable to share"
                    shareError = $0
                }
                .allowsHitTesting(false)
            }
            Text(preview.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityIdentifier("preview.filename")
                .accessibilityValue(preview.playlist?.positionText ?? "1 / 1")
                .accessibilityHint(preview.folderAccessURL == nil
                    ? "Swipe left for the next file or right for the previous file."
                    : "Connect this folder in Video information to browse nearby videos.")
                .accessibilityAdjustableAction { direction in
                    guard canNavigate else { return }
                    switch direction {
                    case .increment: if preview.playlist?.hasNext == true { onNext() }
                    case .decrement: if preview.playlist?.hasPrevious == true { onPrevious() }
                    @unknown default: break
                    }
                }
            QueuePreviewAddListButton(isAdded: isAdded, isEnabled: canAdd, action: onAdd)
            QueuePreviewRoundButton(symbol: "xmark", label: "Close", identifier: "preview.close", action: onClose)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard !showsInformation && !isSharing && !showsFolderAccess else { return }
            let direction = QueuePreviewBarNavigation.destination(translation: value.translation,
                playlist: preview.playlist, isEnabled: canNavigate, needsFolderAccess: preview.folderAccessURL != nil)
            switch direction {
            case .previous: onPrevious()
            case .next: onNext()
            case .folderAccessRequired:
                showsFolderHint = !onRestoreFolderNavigation(value.translation.width < 0 ? 1 : -1)
            case nil: break
            }
        })
        .overlay(alignment: .top) {
            if showsFolderHint {
                Text("Connect the folder in ⓘ to browse its videos.")
                    .font(.caption).foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.85), in: Capsule())
                    .offset(y: -120)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("preview.folder.hint")
            }
        }
        .task(id: showsFolderHint) {
            guard showsFolderHint else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            showsFolderHint = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preview.actions")
        .sheet(isPresented: $showsInformation, onDismiss: {
            if connectsFolderAfterInformation {
                connectsFolderAfterInformation = false
                showsFolderAccess = true
            }
        }) {
            QueuePreviewInformationSheet(preview: preview) {
                connectsFolderAfterInformation = true
                showsInformation = false
            }
        }
        .sheet(isPresented: $showsFolderAccess) {
            QueuePreviewFolderAccessPresenter(directoryURL: preview.folderAccessURL, isPresented: $showsFolderAccess) { url in
                if let url {
                    errorTitle = "Folder access"
                    shareError = onAuthorizeFolder(url, 0)
                }
            }
        }
        .alert(errorTitle, isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: { Text(shareError ?? "") }
        .onChange(of: preview.id) { _, _ in
            showsInformation = false
            isSharing = false
            showsFolderAccess = false
            connectsFolderAfterInformation = false
            showsFolderHint = false
        }
    }
}

struct QueuePreviewInformationSheet: View {
    var preview: QueueVideoPreview
    var onConnectFolder: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if preview.folderAccessURL != nil {
                    Section("Folder navigation") {
                        LabeledContent("Folder", value: preview.folderAccessURL?.lastPathComponent ?? "")
                        Button("Connect folder", action: onConnectFolder)
                            .accessibilityIdentifier("preview.folder.connect")
                Text("Tap Browse at the bottom to switch between On My iPhone, iCloud Drive, and other locations. Open the folder containing this video, then tap Open at the top right. This connects the folder and its subfolders.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("File") {
                    info("Name", preview.displayName)
                    info("Size", preview.videoInfo.fileSize)
                    info("Duration", preview.videoInfo.duration)
                    info("Container", preview.sourceURL.pathExtension.uppercased())
                }
                Section("Video") {
                    info("Format", preview.videoInfo.inputSummary)
                    info("Resolution", preview.videoInfo.resolution)
                    info("Frame rate", preview.videoInfo.frameRate)
                }
                Section("Audio") {
                    info("Format", preview.videoInfo.audio)
                }
                Section("Conversion") {
                    info("Video processing", preview.pathBadge)
                    Text(preview.videoInfo.codecPathDetail).font(.footnote).foregroundStyle(.secondary)
                    info("Audio processing", preview.videoInfo.audioPathBadge)
                    Text(preview.videoInfo.audioPathDetail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            .navigationTitle("Video Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("preview.info.done")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func info(_ name: String, _ value: String) -> some View {
        LabeledContent(name, value: value.isEmpty ? "Not available" : value)
    }
}

struct QueuePreviewCenterControls: View {
    var isPlaying: Bool
    var canSeek: Bool
    var onBackward: () -> Void
    var onToggle: () -> Void
    var onForward: () -> Void

    var body: some View {
        HStack(spacing: 30) {
            skipButton("gobackward.10", label: "Back 10 seconds", identifier: "preview.backward", action: onBackward)
            Button(action: onToggle) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(.black.opacity(0.56), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
            .accessibilityIdentifier("preview.playback")
            skipButton("goforward.10", label: "Forward 10 seconds", identifier: "preview.forward", action: onForward)
        }
    }

    private func skipButton(_ symbol: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.5), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSeek)
        .opacity(canSeek ? 1 : 0.4)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
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
    var onAuthorizeFolder: (URL, Int) -> String? = { _, _ in nil }
    var onRestoreFolderNavigation: (Int) -> Bool = { _ in false }
    /// Called when libVLC opens the file but never presents a frame, so the parent can try the
    /// native engine. The error message is set as well, so a refused switch still explains itself.
    var onPlaybackUnavailable: () -> Void = {}

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
    @State private var gestureExcludedFrames: [CGRect] = []
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
                    .allowsHitTesting(false)

                if let gestureFeedback {
                    QueuePreviewGestureFeedbackView(feedback: gestureFeedback)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                QueuePreviewSystemVolumeBridgeView(controller: systemVolumeController)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .coordinateSpace(name: "preview.surface")
            .onPreferenceChange(QueuePreviewGestureExcludedFramesKey.self) { gestureExcludedFrames = $0 }
            .gesture(surfacePanGesture(containerSize: proxy.size))
        }
        .background(
            Color.black
                .ignoresSafeArea()
        )
        .onAppear {
            beginVideoPlaybackAdSuppressionIfNeeded()
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
            .background(QueuePreviewGestureExclusionRegion())
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
            Spacer(minLength: 0)
            transportControls
                .padding(.horizontal, containerSize.width < 380 ? 10 : 16)
                .padding(.bottom, max(safeAreaInsets.bottom, 12))
        }
    }

    private func previewBannerScale(containerSize: CGSize) -> CGFloat {
        let widthFitScale = max(min((containerSize.width - 24) / 320, 1), 0.72)
        let heightScale = containerSize.width > containerSize.height ? 0.78 : 1
        return min(widthFitScale, heightScale)
    }

    private var centerPlayPauseOverlay: some View {
        Group {
            if areControlsVisible && !isLoading && playbackError == nil {
                QueuePreviewCenterControls(
                    isPlaying: player.isPlaying, canSeek: hasUsableTimeline,
                    onBackward: skipBackward, onToggle: togglePlayback, onForward: skipForward
                )
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
    }

    private var transportControls: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { displayedSliderPosition },
                    set: { newValue in
                        guard hasUsableTimeline else { return }
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
                    } else { finishScrubbing() }
                }
            )
            .disabled(!hasUsableTimeline)
            .tint(.white)
            .accessibilityLabel("Playback position")
            .accessibilityIdentifier("preview.timeline")

            HStack {
                Text(displayedCurrentTimeText)
                Spacer()
                Text(durationText)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("preview.time")
            .padding(.bottom, 8)

            QueuePreviewActionBar(
                preview: preview, isAdded: isAddedToList,
                canAdd: canAddToList && !isLoading, canNavigate: !isLoading,
                onAdd: onAddToList, onClose: closePreview,
                onPrevious: previousItem, onNext: nextItem, onAuthorizeFolder: onAuthorizeFolder,
                onRestoreFolderNavigation: onRestoreFolderNavigation
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 18))
        .background(QueuePreviewGestureExclusionRegion())
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
                onPlaybackUnavailable()
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
            onPlaybackUnavailable()
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
        // The skip buttons promise ten seconds, even when keyframes are far apart.
        if (try? player.seek(by: offset, fast: false)) == nil {
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
            SpatialTapGesture(count: 2, coordinateSpace: .named("preview.surface")),
            SpatialTapGesture(count: 1, coordinateSpace: .named("preview.surface"))
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

    private func surfacePanGesture(containerSize: CGSize) -> QueuePreviewSurfacePanGesture {
        QueuePreviewSurfacePanGesture(
            canStart: { start in
                !isScrubbing && QueuePreviewSurfaceGesturePolicy.canStart(
                    start: start, size: containerSize,
                    excludedFrames: areControlsVisible ? gestureExcludedFrames : []
                )
            },
            onChanged: { value in
                handleDragChanged(value, containerSize: containerSize)
            },
            onEnded: { value in
                guard dragMode != nil else { return }
                handleDragEnded(value, containerSize: containerSize)
            },
            onCancelled: {
                dragMode = nil
                dragSeekPreviewPosition = nil
                dismissGestureFeedbackAfterDelay()
            })
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

    private func handleDragChanged(_ value: QueuePreviewSurfaceDragValue, containerSize: CGSize) {
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
                text: "Brightness \(Int((brightness * 100).rounded()))%",
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
                text: "Volume \(Int((volume * 100).rounded()))%",
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
        case .close:
            if value.translation.height > 0 {
                showGestureFeedback(systemImage: "chevron.down", text:
                    QueuePreviewSurfaceGesturePolicy.shouldClose(translation: value.translation, size: containerSize)
                        ? "Release to close" : "Swipe down to close", autoDismiss: false)
            }
        }
    }

    private func handleDragEnded(_ value: QueuePreviewSurfaceDragValue, containerSize: CGSize) {
        let shouldClose = dragMode == .close && QueuePreviewSurfaceGesturePolicy.shouldClose(
            translation: value.translation, size: containerSize)
        defer {
            dragMode = nil
            dragSeekPreviewPosition = nil
            if !shouldClose {
                dismissGestureFeedbackAfterDelay()
                showControls(scheduleAutoHide: false)
            }
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
        case .close:
            if shouldClose { closePreview() }
        case .brightness, .volume, .none:
            return
        }
    }

    private func resolvedDragMode(
        for value: QueuePreviewSurfaceDragValue,
        containerSize: CGSize
    ) -> QueuePreviewDragMode? {
        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)
        guard max(horizontalDistance, verticalDistance) >= 18 else { return nil }

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

        switch QueuePreviewSurfaceGesturePolicy.verticalAction(
            start: value.startLocation, translation: value.translation, size: containerSize) {
        case .brightness: return .brightness(startValue: UIScreen.main.brightness)
        case .volume: return .volume(startValue: systemVolumeController.volume)
        case .close: return .close
        case nil: return nil
        }
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

    /// One engine switch per file, for the same reason as `QueueVideoPreviewView`: whichever engine
    /// cannot present frames gets replaced once, and the other engine's message is what remains.
    @State private var engineOverride: QueuePreviewPlaybackRoute?

    @ViewBuilder
    var body: some View {
        Group {
            switch engineOverride ?? QueuePreviewPlaybackRoutePlanner.route(for: preview) {
            case .native:
                NativeQueueVideoPreviewView(
                    preview: preview, isMiniPlayer: true,
                    onClose: onClose, onMinimize: onExpand,
                    onPlaybackUnavailable: { switchEngine(to: .vlc) }
                )
            case .vlc:
                VLCQueueMiniPlayerView(
                    preview: preview, onClose: onClose, onExpand: onExpand,
                    onPlaybackUnavailable: { switchEngine(to: .native) }
                )
            }
        }
        .onChange(of: preview.id) { _, _ in engineOverride = nil }
    }

    private func switchEngine(to requested: QueuePreviewPlaybackRoute) {
        guard engineOverride == nil,
              requested != QueuePreviewPlaybackRoutePlanner.route(for: preview) else { return }
        engineOverride = requested
    }
}
private struct VLCQueueMiniPlayerView: View {
    var preview: QueueVideoPreview
    var onClose: () -> Void
    var onExpand: (QueuePreviewPlaybackSnapshot) -> Void
    var onPlaybackUnavailable: () -> Void = {}

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
                onPlaybackUnavailable()
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
            onPlaybackUnavailable()
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

@MainActor
final class QueuePreviewSystemVolumeController: ObservableObject {
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

struct QueuePreviewSystemVolumeBridgeView: UIViewRepresentable {
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

/// Which engine presents the queue preview.
///
/// Two engines, and neither covers everything:
///
/// - `.vlc` — libVLC. Reads every container the encoder reads, which is why it is the default.
///   On iOS it renders through its sample-buffer output, and its VideoToolbox session rejects
///   tracks that carry more than one sample description with differing parameter sets. Dolby
///   Vision profile 8 keeps a second `hvc1` entry for the base layer, so the decoder reports
///   `kVTVideoDecoderBadDataErr`, restarts, and discards every frame. The video output still
///   exists, so `hasVideoOutput` reports `true` while the screen stays black — a track-level
///   probe cannot detect this.
/// - `.native` — `AVPlayerViewController`. Parses those tracks the way Photos and Files do, and
///   presents HDR with the system's own tone mapping.
///
/// So the split follows *what the system understands better*, not preference: HDR, more than
/// eight bits per component, and alpha composition go native; everything else keeps libVLC's far
/// wider container support.
enum QueuePreviewPlaybackRoute: Equatable {
    case native
    case vlc
}

enum QueuePreviewPlaybackRoutePlanner {
    /// Containers `AVFoundation` opens. Outside this set the native engine has nothing to read,
    /// so libVLC stays the only option even for HDR sources.
    static let nativeReadableContainers: Set<TaptionVideoContainer> = [.mp4, .mov, .m4v]

    static func route(
        for track: TaptionVideoTrackInfo?,
        container: TaptionVideoContainer
    ) -> QueuePreviewPlaybackRoute {
        guard let track else { return .vlc }

        // Unchanged behaviour: only Apple's compositor renders HEVC Alpha correctly, and only in
        // QuickTime files.
        if track.codec == .hevcWithAlpha {
            return container == .mov ? .native : .vlc
        }

        guard nativeReadableContainers.contains(container) else { return .vlc }

        if track.codec == .dolbyVisionHEVC {
            return .native
        }

        if track.color.isHDR || (track.color.bitDepth ?? 8) > 8 {
            return .native
        }

        return .vlc
    }

    static func route(for preview: QueueVideoPreview) -> QueuePreviewPlaybackRoute {
        preview.usesNativePlayback ? .native : .vlc
    }
}

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
