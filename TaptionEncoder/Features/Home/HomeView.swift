import Darwin
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum HomeSystemDocumentPickerMode: String {
    case files
    case folder

    var allowedContentTypes: [UTType] {
        switch self {
        case .files:
            return ImportableVideoTypes.all
        case .folder:
            return [.folder]
        }
    }

    var allowsMultipleSelection: Bool {
        switch self {
        case .files:
            return true
        case .folder:
            return false
        }
    }
}

private struct HomeSystemDocumentPickerPresenter: UIViewControllerRepresentable {
    @Binding var mode: HomeSystemDocumentPickerMode?
    var onCompletion: (HomeSystemDocumentPickerMode, Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard let mode else {
            return
        }

        context.coordinator.present(mode: mode, anchoredBy: viewController)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: HomeSystemDocumentPickerPresenter
        var presentedMode: HomeSystemDocumentPickerMode?

        init(parent: HomeSystemDocumentPickerPresenter) {
            self.parent = parent
        }

        func present(mode: HomeSystemDocumentPickerMode, anchoredBy anchor: UIViewController) {
            guard presentedMode != mode else {
                return
            }

            presentedMode = mode
            DispatchQueue.main.async { [weak self, weak anchor] in
                self?.presentPicker(mode: mode, anchoredBy: anchor)
            }
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            complete(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            complete(.success([]))
        }

        private func presentPicker(
            mode: HomeSystemDocumentPickerMode,
            anchoredBy anchor: UIViewController?
        ) {
            guard parent.mode == mode else {
                presentedMode = nil
                return
            }

            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: mode.allowedContentTypes,
                asCopy: false
            )
            picker.allowsMultipleSelection = mode.allowsMultipleSelection
            picker.delegate = self
            if #available(iOS 14.0, *) {
                picker.shouldShowFileExtensions = true
            }

            guard let presenter = Self.topMostPresenter(preferredAnchor: anchor) else {
                AppLogger.warning(
                    "System document picker presenter unavailable",
                    category: .fileImport,
                    metadata: ["mode": mode.rawValue]
                )
                presentedMode = nil
                parent.mode = nil
                return
            }

            presenter.present(picker, animated: true)
        }

        private static func topMostPresenter(preferredAnchor anchor: UIViewController?) -> UIViewController? {
            let anchorRoot = anchor?.view.window?.rootViewController
            let sceneRoot = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }?
                .rootViewController

            guard var presenter = anchorRoot ?? sceneRoot else {
                return nil
            }

            while let presented = presenter.presentedViewController,
                  !presented.isBeingDismissed {
                presenter = presented
            }

            return presenter
        }

        private func complete(_ result: Result<[URL], Error>) {
            guard let mode = presentedMode ?? parent.mode else {
                return
            }
            presentedMode = nil
            parent.mode = nil
            parent.onCompletion(mode, result)
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @State private var activeImportBrowser: HomeImportBrowserMode?
    @State private var didCompleteImportBrowserSelection = false
    @State private var activeSystemDocumentPicker: HomeSystemDocumentPickerMode?
    @State private var isPhotosPickerPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var activeMenuSheet: HomeMenuSheet?
    @State private var isOutputSizePopoverPresented = false
    @State private var outputSizeDraftMB: Double?
    @State private var miniPlayerPreview: QueueVideoPreview?
    @State private var autoStartMiniPlayerPiPPreviewID: String?
    @State private var lastExternalVideoOpenURL: URL?
    @State private var lastExternalVideoOpenDate: Date?
    @State private var isDocumentPickerAdSuppressed = false
    @State private var isPhotosPickerAdSuppressed = false
    #if DEBUG
    @State private var didOpenDebugPreviewFile = false
    @State private var didOpenDebugPreviewSample = false
    @State private var didOpenDebugSampleLibrary = false
    #endif

    init(environment: AppEnvironment = .phase0) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(environment: environment))
    }

    var body: some View {
        GeometryReader { geometry in
            let reservesFailureLogArea = viewModel.state.reservesFailureLogArea
            let metrics = HomeLayoutMetrics(
                size: geometry.size,
                reservesFailureLogArea: reservesFailureLogArea,
                showsNativeAdSlot: viewModel.showsNativeAdSlot
            )
            let isFullScreenVideoPlaybackActive = viewModel.activePreview != nil

            ZStack {
                TaptionTheme.appBackground
                    .ignoresSafeArea()

                homeContent(
                    metrics: metrics,
                    reservesFailureLogArea: reservesFailureLogArea,
                    showsPlaybackActions: !isFullScreenVideoPlaybackActive
                )

                if let preview = miniPlayerPreview {
                    miniPlayerOverlay(
                        preview: preview,
                        containerSize: geometry.size,
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .sheet(
            item: $activeImportBrowser,
            onDismiss: handleImportBrowserDismiss
        ) { mode in
            HomeImportBrowserView(
                mode: mode,
                context: viewModel.importBrowserContext,
                folders: viewModel.importBrowserFolders,
                files: viewModel.importBrowserFiles,
                onOpenFolder: { viewModel.navigateImportBrowserIntoFolder(id: $0) },
                onToggleFile: { viewModel.toggleImportBrowserFileSelection(id: $0) },
                onBack: { viewModel.navigateImportBrowserUp() },
                onImport: { importFromBrowser(mode: mode) },
                onClose: { closeImportBrowser(mode: mode) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            item: Binding(
                get: { viewModel.folderPreviewContext },
                set: { context in
                    if context == nil {
                        viewModel.dismissFolderPreviewBrowser()
                    }
                }
            )
        ) { context in
            FolderPreviewBrowserView(
                context: context,
                files: viewModel.folderPreviewFileSnapshots,
                onSelect: { viewModel.selectFolderPreviewFile(id: $0) },
                onImportAll: { viewModel.importFolderPreviewBatch() },
                onClose: { viewModel.dismissFolderPreviewBrowser() }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeMenuSheet) { sheet in
            HomeMenuSheetView(sheet: sheet)
        }
        .alert(
            item: Binding(
                get: { viewModel.batteryEncodingAlert },
                set: { alert in
                    if alert == nil {
                        viewModel.dismissBatteryEncodingAlert()
                    }
                }
            )
        ) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    viewModel.dismissBatteryEncodingAlert()
                }
            )
        }
        .multiFileEncodingDialog(viewModel: viewModel)
        .multiFileMergeUnavailableAlert(viewModel: viewModel)
        .pendingSaveDestinationDialog(viewModel: viewModel)
        .savedFolderDialog(viewModel: viewModel)
        .fullScreenCover(
            isPresented: Binding<Bool>(
                get: { viewModel.activePreview != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissPreview()
                    }
                }
            )
        ) {
            queueVideoPreviewFullScreenCoverContent
        }
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $selectedPhotoItem,
            matching: .videos,
            preferredItemEncoding: .current
        )
        .background(
            HomeSystemDocumentPickerPresenter(
                mode: $activeSystemDocumentPicker,
                onCompletion: handleSystemDocumentPickerResult
            )
            .frame(width: 0, height: 0)
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            handleSelectedPhotoItemChange(newItem)
        }
        .onChange(of: isPhotosPickerPresented) { _, isPresented in
            if !isPresented {
                endPhotosPickerAdSuppressionIfNeeded()
            }
        }
        .onOpenURL { url in
            handleExternalVideoOpen(url: url, source: "scene")
        }
        .onReceive(NotificationCenter.default.publisher(for: .taptionExternalVideoOpenRequested)) { _ in
            drainPendingExternalVideoOpens(source: "delegate")
        }
        .task {
            drainPendingExternalVideoOpens(source: "pending")
            await AdMobBootstrapper.refreshOnActive()
            await viewModel.restorePendingSavesIfNeeded()
            await viewModel.refreshStarsIfNeeded()
            #if DEBUG
            openDebugPreviewFileIfRequested()
            openDebugPreviewSampleIfRequested()
            openDebugSampleLibraryIfRequested()
            #endif
        }
    }

    @ViewBuilder
    private var queueVideoPreviewFullScreenCoverContent: some View {
        if let preview = viewModel.activePreview {
            QueueVideoPreviewView(
                preview: preview,
                adUnitID: viewModel.bannerAdUnitID,
                onClose: { viewModel.dismissPreview() },
                onMinimize: {
                    miniPlayerPreview = preview
                    autoStartMiniPlayerPiPPreviewID = nil
                    viewModel.dismissPreview()
                },
                onPictureInPictureHome: {
                    miniPlayerPreview = preview
                    autoStartMiniPlayerPiPPreviewID = preview.id
                    viewModel.dismissPreview()
                },
                onPrevious: { viewModel.openPreviousPreview() },
                onNext: { viewModel.openNextPreview() }
            )
        } else {
            Color.black
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func homeContent(
        metrics: HomeLayoutMetrics,
        reservesFailureLogArea: Bool,
        showsPlaybackActions: Bool
    ) -> some View {
        VStack(spacing: metrics.verticalSpacing) {
            AdMobBannerSlotView(
                adUnitID: viewModel.bannerAdUnitID,
                displayScale: metrics.bannerScale
            )
            header(metrics: metrics)
            sourceControls(metrics: metrics)
            outputSelector(metrics: metrics)
            outputSummary(metrics: metrics)
            if viewModel.showsIdleNativeAdSlot {
                nativeAdSlot(metrics: metrics)
            }
            loadedFilesPanel(metrics: metrics)
            encodingControls(
                metrics: metrics,
                reservesFailureLogArea: reservesFailureLogArea,
                showsPlaybackActions: showsPlaybackActions
            )
            if viewModel.showsCompletedNativeAdSlot {
                nativeAdSlot(metrics: metrics)
            }

            if !reservesFailureLogArea {
                Spacer(minLength: 0)
            }

            exitButton(metrics: metrics)

            AdMobBannerSlotView(
                adUnitID: viewModel.bannerAdUnitID,
                displayScale: metrics.bannerScale
            )
            .padding(.top, metrics.footerAdSeparationHeight)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(width: metrics.canvasWidth, height: metrics.canvasHeight, alignment: .top)
        .background(TaptionTheme.appBackground)
        .clipped()
    }

    private func sourceControls(metrics: HomeLayoutMetrics) -> some View {
        SourceActionBar(
            canSelectSource: viewModel.state.canSelectSource,
            canReset: viewModel.state.canReset,
            onFiles: openFilesImportBrowser,
            onFolder: openFolderImportBrowser,
            onPhotos: presentPhotosPicker,
            onReset: resetHome,
            controlHeight: metrics.controlHeight,
            buttonFont: metrics.buttonFont
        )
    }

    private func outputSummary(metrics: HomeLayoutMetrics) -> some View {
        OutputSummaryView(
            videoCodecText: viewModel.selectedVideoCodecText,
            audioCodecText: viewModel.selectedAudioCodecText,
            contentScale: metrics.contentScale
        )
    }

    private func nativeAdSlot(metrics: HomeLayoutMetrics) -> some View {
        AdMobNativeAdSlotView(
            adUnitID: viewModel.nativeAdUnitID,
            displayScale: metrics.contentScale,
            title: viewModel.nativeAdSlotTitle
        )
        .frame(height: metrics.nativeAdSlotHeight)
    }

    private func loadedFilesPanel(metrics: HomeLayoutMetrics) -> some View {
        LoadedFilesPanelView(
            files: viewModel.fileCardSnapshots,
            contentScale: metrics.contentScale,
            panelHeight: metrics.filePanelHeight,
            onSelect: { viewModel.selectFileCard(id: $0) },
            onPlay: { viewModel.openPreviewForFileCard(id: $0) },
            onToggleSelection: { viewModel.toggleQueueFileSelection(id: $0) },
            onDelete: { viewModel.deleteQueueFile(id: $0) },
            onMove: { draggedID, targetID in
                viewModel.moveQueueFiles(draggedID: draggedID, before: targetID)
            },
            onMoveEnded: { viewModel.finishQueueMove() }
        )
    }

    private func encodingControls(
        metrics: HomeLayoutMetrics,
        reservesFailureLogArea: Bool,
        showsPlaybackActions: Bool
    ) -> some View {
        EncodingProgressView(
            state: viewModel.state,
            displayDetail: viewModel.progressDetailText,
            canStartEncoding: viewModel.canStartEncodingNow,
            startActionTitle: viewModel.startActionTitle,
            showsSaveAction: viewModel.showsSaveAction,
            saveActionTitle: viewModel.saveActionTitle,
            showsWorkAction: showsPlaybackActions,
            watchAdButtonTitle: viewModel.watchAdButtonTitle,
            showsWatchAdAction: showsPlaybackActions,
            canWatchAd: viewModel.canWatchAdForStar,
            controlHeight: metrics.controlHeight,
            contentScale: metrics.contentScale,
            reservesFailureLogArea: reservesFailureLogArea,
            onStart: { viewModel.startPreparedEncoding() },
            onSave: { viewModel.saveCurrentPendingOutput() },
            onWatchAd: { viewModel.watchAdForStar() },
            onCancel: { viewModel.cancel() }
        )
    }

    private func drainPendingExternalVideoOpens(source: String) {
        for url in ExternalVideoOpenInbox.drainPendingURLs() {
            handleExternalVideoOpen(url: url, source: source)
        }
    }

    private func handleExternalVideoOpen(url: URL, source: String) {
        let now = Date()
        if lastExternalVideoOpenURL == url,
           let lastExternalVideoOpenDate,
           now.timeIntervalSince(lastExternalVideoOpenDate) < 1 {
            AppLogger.info(
                "Duplicate external video URL ignored",
                category: .fileImport,
                metadata: [
                    "name": url.lastPathComponent,
                    "source": source
                ]
            )
            return
        }

        lastExternalVideoOpenURL = url
        lastExternalVideoOpenDate = now
        AppLogger.info(
            "External video URL opened",
            category: .fileImport,
            metadata: [
                "name": url.lastPathComponent,
                "source": source
            ]
        )
        clearMiniPlayerForNewSource(reason: "externalVideoOpen")
        AdMobBootstrapper.suppressAppOpenAdsForExternalPlayback()
        viewModel.openExternalPlayerFile(url: url)
    }

    private func clearMiniPlayerForNewSource(reason: String) {
        guard let miniPlayerPreview else {
            return
        }
        AppLogger.info(
            "Queue mini player cleared for new source",
            category: .ui,
            metadata: [
                "name": miniPlayerPreview.displayName,
                "reason": reason
            ]
        )
        self.miniPlayerPreview = nil
        autoStartMiniPlayerPiPPreviewID = nil
    }

    private func handleImportBrowserDismiss() {
        if didCompleteImportBrowserSelection {
            didCompleteImportBrowserSelection = false
            return
        }
        viewModel.dismissImportBrowser()
    }

    private func openFilesImportBrowser() {
        AppLogger.info("File button tapped", category: .ui)
        beginDocumentPickerAdSuppressionIfNeeded(reason: "filePicker")
        activeSystemDocumentPicker = .files
    }

    private func openFolderImportBrowser() {
        AppLogger.info("Folder button tapped", category: .ui)
        beginDocumentPickerAdSuppressionIfNeeded(reason: "folderPicker")
        activeSystemDocumentPicker = .folder
    }

    private func presentPhotosPicker() {
        AppLogger.info("Album button tapped", category: .ui)
        beginPhotosPickerAdSuppressionIfNeeded()
        isPhotosPickerPresented = true
    }

    private func watchAdFromStarBadge() {
        AppLogger.info("Star badge tapped", category: .ui)
        viewModel.watchAdForStar()
    }

    private func resetHome() {
        AppLogger.info("Reset button tapped", category: .ui)
        miniPlayerPreview = nil
        autoStartMiniPlayerPiPPreviewID = nil
        viewModel.reset()
    }

    private func handleSystemDocumentPickerResult(
        mode: HomeSystemDocumentPickerMode,
        result: Result<[URL], Error>
    ) {
        endDocumentPickerAdSuppressionIfNeeded(reason: mode.rawValue)
        switch mode {
        case .files:
            handleFilePickerResult(result)
        case .folder:
            handleFolderPickerResult(result)
        }
    }

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let selectedURLs = urls.map(\.standardizedFileURL)
            guard !selectedURLs.isEmpty else {
                return
            }
            AppLogger.info(
                "File picker selection completed",
                category: .fileImport,
                metadata: [
                    "count": "\(selectedURLs.count)",
                    "names": selectedURLs.map(\.lastPathComponent).joined(separator: "|")
                ]
            )
            viewModel.handleFolderPickerSelection(urls: selectedURLs)
        case .failure(let error):
            AppLogger.warning(
                "File picker selection failed",
                category: .fileImport,
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func handleFolderPickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folderURL = urls.first?.standardizedFileURL else {
                return
            }
            AppLogger.info(
                "Folder picker selection completed",
                category: .folderImport,
                metadata: ["name": folderURL.lastPathComponent]
            )
            viewModel.handleFolderPickerSelection(urls: [folderURL])
        case .failure(let error):
            AppLogger.warning(
                "Folder picker selection failed",
                category: .folderImport,
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func handleSelectedPhotoItemChange(_ newItem: PhotosPickerItem?) {
        guard let newItem else {
            return
        }

        Task {
            await importSelectedPhotoItem(newItem)
        }
    }

    private func importSelectedPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let importedVideo = try await item.loadTransferable(type: ImportedPhotoVideo.self) else {
                failPhotosImport(message: "The selected Photos video could not be imported.")
                return
            }

            completePhotosImport(importedVideo)
        } catch {
            failPhotosImport(error: error)
        }
    }

    @MainActor
    private func completePhotosImport(_ importedVideo: ImportedPhotoVideo) {
        endPhotosPickerAdSuppressionIfNeeded()
        AppLogger.info(
            "Photos video imported",
            category: .photosImport,
            metadata: ["name": importedVideo.displayName]
        )
        viewModel.startPhotosFlow(
            url: importedVideo.url,
            displayName: importedVideo.displayName
        )
        selectedPhotoItem = nil
    }

    @MainActor
    private func failPhotosImport(message: String) {
        endPhotosPickerAdSuppressionIfNeeded()
        AppLogger.error(
            "Photos picker import failed",
            category: .photosImport,
            metadata: ["error": message]
        )
        viewModel.fail(message: message)
        selectedPhotoItem = nil
    }

    @MainActor
    private func failPhotosImport(error: Error) {
        endPhotosPickerAdSuppressionIfNeeded()
        AppLogger.error(
            "Photos picker import failed",
            category: .photosImport,
            metadata: ["error": error.localizedDescription]
        )
        viewModel.fail(
            error: error,
            summary: "The selected Photos video could not be imported.",
            recovery: "Choose the video again from Photos, then try importing it one more time."
        )
        selectedPhotoItem = nil
    }

    private func beginDocumentPickerAdSuppressionIfNeeded(reason: String) {
        guard !isDocumentPickerAdSuppressed else {
            return
        }
        isDocumentPickerAdSuppressed = true
        AdMobBootstrapper.beginFullScreenAdSuppression(reason: reason)
    }

    private func endDocumentPickerAdSuppressionIfNeeded(reason: String) {
        guard isDocumentPickerAdSuppressed else {
            return
        }
        isDocumentPickerAdSuppressed = false
        AdMobBootstrapper.endFullScreenAdSuppression(reason: reason)
    }

    private func beginPhotosPickerAdSuppressionIfNeeded() {
        guard !isPhotosPickerAdSuppressed else {
            return
        }
        isPhotosPickerAdSuppressed = true
        AdMobBootstrapper.beginFullScreenAdSuppression(reason: "photosPicker")
    }

    private func endPhotosPickerAdSuppressionIfNeeded() {
        guard isPhotosPickerAdSuppressed else {
            return
        }
        isPhotosPickerAdSuppressed = false
        AdMobBootstrapper.endFullScreenAdSuppression(reason: "photosPicker")
    }

    private func importFromBrowser(mode: HomeImportBrowserMode) {
        AppLogger.info(
            "Import browser import tapped",
            category: .ui,
            metadata: ["mode": mode.rawValue]
        )
        didCompleteImportBrowserSelection = true
        viewModel.importFromImportBrowser()
        activeImportBrowser = nil
    }

    private func closeImportBrowser(mode: HomeImportBrowserMode) {
        AppLogger.info(
            "Import browser closed",
            category: .ui,
            metadata: ["mode": mode.rawValue]
        )
        viewModel.dismissImportBrowser()
        activeImportBrowser = nil
    }

    #if DEBUG
    private func openDebugPreviewFileIfRequested() {
        guard !didOpenDebugPreviewFile,
              let previewFilePath = ProcessInfo.processInfo.environment["TAPTION_PREVIEW_FILE"],
              !previewFilePath.isEmpty else {
            return
        }

        didOpenDebugPreviewFile = true
        let previewURL = URL(fileURLWithPath: previewFilePath)
        AppLogger.info(
            "Debug preview file opened",
            category: .fileImport,
            metadata: ["name": previewURL.lastPathComponent]
        )
        AdMobBootstrapper.suppressAppOpenAdsForExternalPlayback()
        if debugAutoStartEncodingRequested {
            viewModel.openDebugFileAndStartEncoding(url: previewURL)
        } else {
            viewModel.openExternalPlayerFile(url: previewURL)
        }
    }

    private func openDebugPreviewSampleIfRequested() {
        guard !didOpenDebugPreviewSample,
              let sampleName = ProcessInfo.processInfo.environment["TAPTION_PREVIEW_SAMPLE_NAME"],
              !sampleName.isEmpty else {
            return
        }

        didOpenDebugPreviewSample = true
        do {
            let sampleFolderURL = try TaptionTestVideoSeeder.documentsSampleFolderURL()
            let previewURL = sampleFolderURL.appendingPathComponent(sampleName)
            AppLogger.info(
                "Debug preview sample opened",
                category: .fileImport,
                metadata: [
                    "name": previewURL.lastPathComponent,
                    "path": previewURL.path,
                    "probeID": debugProbeID ?? "none"
                ]
            )
            AdMobBootstrapper.suppressAppOpenAdsForExternalPlayback()
            viewModel.openExternalPlayerFile(url: previewURL)
        } catch {
            AppLogger.error(
                "Debug preview sample failed",
                category: .fileImport,
                metadata: [
                    "name": sampleName,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    private func openDebugSampleLibraryIfRequested() {
        guard !didOpenDebugSampleLibrary,
              debugSampleLibraryRequested else {
            return
        }

        didOpenDebugSampleLibrary = true
        AppLogger.info("Debug sample library opened", category: .folderImport)
        viewModel.openSampleLibrary()
    }

    private var debugSampleLibraryRequested: Bool {
        ProcessInfo.processInfo.environment["TAPTION_OPEN_SAMPLE_LIBRARY"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--taption-open-sample-library")
    }

    private var debugAutoStartEncodingRequested: Bool {
        ProcessInfo.processInfo.environment["TAPTION_AUTO_START_ENCODING"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--taption-auto-start-encoding")
    }

    private var debugProbeID: String? {
        ProcessInfo.processInfo.environment["TAPTION_PIP_PROBE_ID"]
    }
    #endif

    private func miniPlayerOverlay(
        preview: QueueVideoPreview,
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        let width = min(containerSize.width - 24, containerSize.width < 500 ? 238 : 300)
        let bottomPadding = max(82, safeAreaInsets.bottom + 82)

        return VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                QueueMiniPlayerView(
                    preview: preview,
                    autoStartPictureInPicture: autoStartMiniPlayerPiPPreviewID == preview.id,
                    onClose: {
                        miniPlayerPreview = nil
                        autoStartMiniPlayerPiPPreviewID = nil
                    },
                    onExpand: {
                        miniPlayerPreview = nil
                        autoStartMiniPlayerPiPPreviewID = nil
                        viewModel.restorePreview(preview)
                    },
                    onAutoPictureInPictureHandled: {
                        if autoStartMiniPlayerPiPPreviewID == preview.id {
                            autoStartMiniPlayerPiPPreviewID = nil
                        }
                    }
                )
                .frame(width: max(210, width))
                .padding(.trailing, max(12, safeAreaInsets.trailing + 12))
                .padding(.bottom, bottomPadding)
            }
        }
    }

    private func header(metrics: HomeLayoutMetrics) -> some View {
        HStack(spacing: 10 * metrics.contentScale) {
            Menu {
                Button {
                    activeMenuSheet = .help
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }

                Button {
                    activeMenuSheet = .batterySettings
                } label: {
                    Label("Battery Settings", systemImage: "battery.100percent")
                }

                Button {
                    activeMenuSheet = .privacyAds
                } label: {
                    Label("Privacy & Ads", systemImage: "hand.raised")
                }

                Button {
                    activeMenuSheet = .openSource
                } label: {
                    Label("Open Source Notices", systemImage: "curlybraces")
                }

                Button {
                    activeMenuSheet = .deviceInfo
                } label: {
                    Label("Device Info", systemImage: "iphone")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: metrics.headerIconSize, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(width: 34 * metrics.contentScale, height: 34 * metrics.contentScale)
                    .background(TaptionTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TaptionTheme.border, lineWidth: 1)
                    )
            }
            .accessibilityLabel("Menu")

            HStack(spacing: 10 * metrics.contentScale) {
                Image(systemName: "film.stack")
                    .font(.system(size: metrics.headerIconSize, weight: .semibold))
                    .foregroundStyle(TaptionTheme.accent)
                    .frame(width: 34 * metrics.contentScale, height: 34 * metrics.contentScale)
                    .background(TaptionTheme.selectedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(viewModel.subtitle)
                    .font(metrics.headerFont.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            starBadge(metrics: metrics)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func starBadge(metrics: HomeLayoutMetrics) -> some View {
        Button {
            watchAdFromStarBadge()
        } label: {
            HStack(spacing: 6 * metrics.contentScale) {
                Image(systemName: "star.fill")
                    .font(.system(size: max(13, metrics.headerIconSize - 3), weight: .semibold))
                    .foregroundStyle(Color.yellow.opacity(0.95))

                Text(viewModel.starBalanceDisplayText)
                    .font((metrics.contentScale < 0.84 ? Font.caption : Font.subheadline).monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10 * metrics.contentScale)
        .frame(height: 34 * metrics.contentScale)
        .background(TaptionTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TaptionTheme.border, lineWidth: 1)
        )
        .accessibilityLabel("Watch Ad for Star. Balance \(viewModel.starBalanceDisplayText)")
    }

    private func exitButton(metrics: HomeLayoutMetrics) -> some View {
        Button {
            AppLogger.info("Exit button tapped", category: .ui)
            EncoderAppExitController.requestExit()
        } label: {
            HStack(spacing: 8 * metrics.contentScale) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15 * metrics.contentScale, weight: .semibold))
                Text("Exit")
                    .font(metrics.buttonFont.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.footerExitButtonHeight)
            .background(Color(red: 0.96, green: 0.18, blue: 0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Exit")
        .accessibilityIdentifier("button.exit")
    }

    private func outputSelector(metrics: HomeLayoutMetrics) -> some View {
        HStack(spacing: 8 * metrics.contentScale) {
            outputMenu(
                title: "Resolution",
                value: viewModel.selectedOutput.resolutionPreset.menuTitle,
                secondaryValue: viewModel.selectedResolutionAspectRatioText,
                systemImage: "rectangle.compress.vertical",
                isEnabled: viewModel.canChangeOutputSelection,
                metrics: metrics
            ) {
                let availableResolutions = viewModel.outputResolutionOptions.filter { viewModel.resolutionPresetIsAvailable($0) }
                let unavailableResolutions = viewModel.outputResolutionOptions.filter { !viewModel.resolutionPresetIsAvailable($0) }

                ForEach(availableResolutions, id: \.self) { preset in
                    Button {
                        viewModel.selectOutputResolution(preset)
                    } label: {
                        menuItemLabel(
                            title: viewModel.outputResolutionMenuTitle(preset),
                            isSelected: preset == viewModel.selectedOutput.resolutionPreset,
                            isEnabled: true
                        )
                    }
                }

                if !availableResolutions.isEmpty && !unavailableResolutions.isEmpty {
                    Divider()
                }

                ForEach(unavailableResolutions, id: \.self) { preset in
                    Button {
                        viewModel.selectOutputResolution(preset)
                    } label: {
                        menuItemLabel(
                            title: viewModel.outputResolutionMenuTitle(preset),
                            isSelected: preset == viewModel.selectedOutput.resolutionPreset,
                            isEnabled: false
                        )
                    }
                    .disabled(true)
                }
            }

            outputSizeControl(metrics: metrics)
        }
        .frame(maxWidth: .infinity)
    }

    private func outputSizeControl(metrics: HomeLayoutMetrics) -> some View {
        let range = viewModel.outputTargetSizeRangeMB
        return Button {
            isOutputSizePopoverPresented = true
        } label: {
            outputControlLabel(
                title: "Size",
                value: viewModel.outputSizeDisplayText,
                secondaryValue: viewModel.outputSizeSecondaryText,
                systemImage: "internaldrive",
                isEnabled: viewModel.canChangeOutputSizeSelection,
                secondaryValueColor: viewModel.outputSizeShowsWarning ? Color.orange.opacity(0.95) : nil,
                trailingStatusSystemImage: viewModel.outputSizeShowsWarning ? "exclamationmark.triangle.fill" : nil,
                trailingStatusColor: viewModel.outputSizeShowsWarning ? Color.orange.opacity(0.95) : nil,
                metrics: metrics
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canChangeOutputSizeSelection)
        .popover(isPresented: $isOutputSizePopoverPresented) {
            VStack(alignment: .leading, spacing: 12 * metrics.contentScale) {
                Text("Size")
                    .font(.headline.weight(.semibold))

                HStack(spacing: 8 * metrics.contentScale) {
                    sizePresetButton(.auto)
                    sizePresetButton(.manual)
                }

                HStack(spacing: 8 * metrics.contentScale) {
                    sizePresetButton(.high)
                    sizePresetButton(.medium)
                    sizePresetButton(.low)
                }

                Text(outputSizeDraftText(fallback: viewModel.selectedOutputTargetSizeText))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))

                if let statusMessage = viewModel.outputSizeStatusMessage {
                    HStack(alignment: .top, spacing: 8 * metrics.contentScale) {
                        Image(systemName: viewModel.outputSizeShowsWarning ? "exclamationmark.triangle.fill" : "externaldrive")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(
                                viewModel.outputSizeShowsWarning
                                    ? Color.orange.opacity(0.95)
                                    : TaptionTheme.mutedText
                            )
                            .frame(width: 14 * metrics.contentScale, alignment: .top)

                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(
                                viewModel.outputSizeShowsWarning
                                    ? Color.orange.opacity(0.95)
                                    : TaptionTheme.mutedText
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Slider(
                    value: Binding(
                        get: { outputSizeDraftMB ?? viewModel.selectedOutputTargetSizeValueMB },
                        set: { newValue in
                            outputSizeDraftMB = min(max(newValue, range.lowerBound), range.upperBound)
                        }
                    ),
                    in: range,
                    step: 1,
                    onEditingChanged: { isEditing in
                        if isEditing {
                            outputSizeDraftMB = outputSizeDraftMB ?? viewModel.selectedOutputTargetSizeValueMB
                        } else {
                            commitOutputSizeDraft(range: range)
                        }
                    }
                )
                .tint(TaptionTheme.accent)

                HStack {
                    Text("\(Int(range.lowerBound.rounded())) MB")
                    Spacer()
                    Text("\(Int(range.upperBound.rounded())) MB")
                }
                .font(.caption2)
                .foregroundStyle(TaptionTheme.mutedText)
            }
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(18)
            .frame(width: 280)
            .background(TaptionTheme.elevatedSurface)
            .presentationCompactAdaptation(.popover)
            .onAppear {
                outputSizeDraftMB = nil
            }
            .onDisappear {
                commitOutputSizeDraft(range: range)
            }
        }
    }

    private func sizePresetButton(_ preset: TaptionOutputSizePreset) -> some View {
        Button {
            outputSizeDraftMB = nil
            viewModel.selectOutputSize(preset)
        } label: {
            Text(preset.menuTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(viewModel.selectedOutput.sizePreset == preset ? Color.black : Color.white.opacity(0.86))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(viewModel.selectedOutput.sizePreset == preset ? Color.white : Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func outputSizeDraftText(fallback: String) -> String {
        guard let outputSizeDraftMB else {
            return fallback
        }
        return "\(Int(outputSizeDraftMB.rounded())) MB"
    }

    private func commitOutputSizeDraft(range: ClosedRange<Double>) {
        guard let outputSizeDraftMB else {
            return
        }
        let clamped = min(max(outputSizeDraftMB, range.lowerBound), range.upperBound)
        self.outputSizeDraftMB = nil
        viewModel.updateOutputTargetSizeMB(clamped)
    }

    private func outputMenu<Content: View>(
        title: String,
        value: String,
        secondaryValue: String? = nil,
        systemImage: String,
        isEnabled: Bool,
        metrics: HomeLayoutMetrics,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            outputControlLabel(
                title: title,
                value: value,
                secondaryValue: secondaryValue,
                systemImage: systemImage,
                isEnabled: isEnabled,
                metrics: metrics
            )
        }
        .disabled(!isEnabled)
    }

    private func outputControlLabel(
        title: String,
        value: String,
        secondaryValue: String?,
        systemImage: String,
        isEnabled: Bool,
        secondaryValueColor: Color? = nil,
        trailingStatusSystemImage: String? = nil,
        trailingStatusColor: Color? = nil,
        metrics: HomeLayoutMetrics
    ) -> some View {
        HStack(spacing: 7 * metrics.contentScale) {
            Image(systemName: systemImage)
                .font(.system(size: 14 * metrics.contentScale, weight: .semibold))
                .frame(width: 18 * metrics.contentScale)

            VStack(alignment: .leading, spacing: 2 * metrics.contentScale) {
                Text(title)
                    .font((metrics.contentScale < 0.9 ? Font.caption2 : Font.caption).weight(.semibold))
                    .foregroundStyle(TaptionTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 4 * metrics.contentScale) {
                    Text(value)
                        .font((metrics.contentScale < 0.9 ? Font.caption : metrics.buttonFont).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    if let trailingStatusSystemImage {
                        Image(systemName: trailingStatusSystemImage)
                            .font(.system(size: 10 * metrics.contentScale, weight: .bold))
                            .foregroundStyle(trailingStatusColor ?? TaptionTheme.mutedText)
                    }

                    if let secondaryValue {
                        Text(secondaryValue)
                            .font(Font.caption2.weight(.semibold))
                            .foregroundStyle(secondaryValueColor ?? TaptionTheme.mutedText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isEnabled ? Color.white.opacity(0.9) : TaptionTheme.disabledText)
        .padding(.horizontal, 10 * metrics.contentScale)
        .frame(maxWidth: .infinity)
        .frame(minHeight: max(metrics.controlHeight, 52 * metrics.contentScale))
        .background(TaptionTheme.elevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isEnabled ? TaptionTheme.border : Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isEnabled ? 1 : 0.48)
    }

    private func menuItemLabel(
        title: String,
        isSelected: Bool,
        isEnabled: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
            }
            Text(title)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isEnabled ? Color.white.opacity(0.92) : TaptionTheme.disabledText)
    }
}

@MainActor
private extension View {
    func multiFileEncodingDialog(viewModel: HomeViewModel) -> some View {
        confirmationDialog(
            viewModel.multiFileEncodingPrompt?.title ?? "Encode Multiple Files",
            isPresented: Binding(
                get: { viewModel.multiFileEncodingPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissMultiFileEncodingPrompt()
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: viewModel.multiFileEncodingPrompt
        ) { prompt in
            Button("Encode Separately") {
                viewModel.chooseSeparateEncodingForMultiFilePrompt(prompt: prompt)
            }
            Button("Merge into One") {
                viewModel.chooseMergeEncodingForMultiFilePrompt(prompt: prompt)
            }
            Button("Cancel", role: .cancel) {
                viewModel.dismissMultiFileEncodingPrompt()
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }

    func multiFileMergeUnavailableAlert(viewModel: HomeViewModel) -> some View {
        alert(
            viewModel.multiFileMergeUnavailableAlert?.title ?? "Merge Unavailable",
            isPresented: Binding(
                get: { viewModel.multiFileMergeUnavailableAlert != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissMultiFileMergeUnavailableAlert()
                    }
                }
            ),
            presenting: viewModel.multiFileMergeUnavailableAlert
        ) { _ in
            Button("OK") {
                viewModel.dismissMultiFileMergeUnavailableAlert()
            }
        } message: { alert in
            Text(alert.message)
        }
    }

    func pendingSaveDestinationDialog(viewModel: HomeViewModel) -> some View {
        confirmationDialog(
            viewModel.pendingSaveDestinationPrompt?.title ?? "Save To",
            isPresented: Binding(
                get: { viewModel.pendingSaveDestinationPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissPendingSaveDestinationPrompt()
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: viewModel.pendingSaveDestinationPrompt
        ) { prompt in
            Button("Album") {
                viewModel.chooseAlbumForPendingSave(prompt: prompt)
            }
            Button("Folder") {
                viewModel.chooseFolderForPendingSave(prompt: prompt)
            }
            Button("Cancel", role: .cancel) {
                viewModel.dismissPendingSaveDestinationPrompt()
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }

    func savedFolderDialog(viewModel: HomeViewModel) -> some View {
        alert(
            viewModel.savedFolderPrompt?.title ?? "Open Saved Folder?",
            isPresented: Binding(
                get: { viewModel.savedFolderPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissSavedFolderPrompt()
                    }
                }
            ),
            presenting: viewModel.savedFolderPrompt
        ) { prompt in
            Button("Open Folder") {
                viewModel.openSavedFolder(prompt: prompt)
            }
            Button("Not Now", role: .cancel) {
                viewModel.dismissSavedFolderPrompt()
            }
        } message: { prompt in
            Text(prompt.message)
        }
    }

}

#Preview {
    HomeView()
}

private enum EncoderAppExitController {
    @MainActor
    static func requestExit() {
        let application = UIApplication.shared
        let foregroundScene = application.connectedScenes.first { scene in
            scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive
        }

        if let sceneSession = foregroundScene?.session {
            application.requestSceneSessionDestruction(sceneSession, options: nil) { _ in
                terminateProcess()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            terminateProcess()
        }
    }

    private static func terminateProcess() {
        Darwin.exit(EXIT_SUCCESS)
    }
}
