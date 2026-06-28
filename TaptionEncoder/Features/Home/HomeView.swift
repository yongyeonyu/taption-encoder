import Darwin
import SwiftUI
import SwiftVLC
import PhotosUI
import UIKit

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @State private var isFileImporterPresented = false
    @State private var isFolderImporterPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var activeMenuSheet: HomeMenuSheet?
    @State private var isOutputSizePopoverPresented = false
    @State private var outputSizeDraftMB: Double?

    init(environment: AppEnvironment = .phase0) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(environment: environment))
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = HomeLayoutMetrics(size: geometry.size)
            let reservesFailureLogArea = viewModel.state.reservesFailureLogArea

            ZStack {
                TaptionTheme.appBackground
                    .ignoresSafeArea()

                VStack(spacing: metrics.verticalSpacing) {
                    AdMobBannerSlotView(
                        adUnitID: viewModel.bannerAdUnitID,
                        displayScale: metrics.bannerScale
                    )
                    header(metrics: metrics)

                    SourceActionBar(
                        canSelectSource: viewModel.state.canSelectSource,
                        canReset: viewModel.state.canReset,
                        onFiles: {
                            AppLogger.info("File button tapped", category: .ui)
                            isFileImporterPresented = true
                        },
                        onFolder: {
                            AppLogger.info("Folder button tapped", category: .ui)
                            isFolderImporterPresented = true
                        },
                        onPhotos: {
                            AppLogger.info("Photos button tapped", category: .ui)
                            isPhotosPickerPresented = true
                        },
                        onReset: {
                            AppLogger.info("Reset button tapped", category: .ui)
                            viewModel.reset()
                        },
                        controlHeight: metrics.controlHeight,
                        buttonFont: metrics.buttonFont
                    )

                    outputSelector(metrics: metrics)

                    OutputSummaryView(
                        title: viewModel.selectedOutputDetailTitle,
                        videoCodecText: viewModel.selectedVideoCodecText,
                        audioCodecText: viewModel.selectedAudioCodecText,
                        contentScale: metrics.contentScale
                    )

                    LoadedFilesPanelView(
                        files: viewModel.fileCardSnapshots,
                        contentScale: metrics.contentScale,
                        panelHeight: metrics.filePanelHeight,
                        onSelect: { viewModel.openPreviewForFileCard(id: $0) }
                    )

                    EncodingProgressView(
                        state: viewModel.state,
                        displayDetail: viewModel.progressDetailText,
                        canStartEncoding: viewModel.canStartEncodingNow,
                        startActionTitle: viewModel.startActionTitle,
                        showsSaveAction: viewModel.showsSaveAction,
                        saveActionTitle: viewModel.saveActionTitle,
                        watchAdButtonTitle: viewModel.watchAdButtonTitle,
                        canWatchAd: viewModel.canWatchAdForStar,
                        controlHeight: metrics.controlHeight,
                        contentScale: metrics.contentScale,
                        reservesFailureLogArea: reservesFailureLogArea,
                        onStart: { viewModel.startPreparedEncoding() },
                        onSave: { viewModel.saveCurrentPendingOutput() },
                        onWatchAd: { viewModel.watchAdForStar() },
                        onCancel: { viewModel.cancel() }
                    )

                    if !reservesFailureLogArea {
                        Spacer(minLength: 0)
                    }

                    AdMobBannerSlotView(
                        adUnitID: viewModel.bannerAdUnitID,
                        displayScale: metrics.bannerScale
                    )

                    exitButton(metrics: metrics)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.vertical, metrics.verticalPadding)
                .frame(width: metrics.canvasWidth, height: metrics.canvasHeight, alignment: .top)
                .background(TaptionTheme.appBackground)
                .clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .sheet(isPresented: $isFileImporterPresented) {
            VideoDocumentPicker(
                contentTypes: ImportableVideoTypes.all,
                allowsMultipleSelection: true,
                onPick: { urls in
                    AppLogger.info(
                        "Document picker returned files",
                        category: .fileImport,
                        metadata: [
                            "count": "\(urls.count)",
                            "names": urls.map(\.lastPathComponent).joined(separator: "|")
                        ]
                    )
                    isFileImporterPresented = false
                    viewModel.startFilesFlow(urls: urls)
                },
                onCancel: {
                    AppLogger.info("Document picker cancelled", category: .fileImport)
                    isFileImporterPresented = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isFolderImporterPresented) {
            VideoDocumentPicker(
                contentTypes: [.folder] + ImportableVideoTypes.all,
                allowsMultipleSelection: false,
                onPick: { urls in
                    AppLogger.info(
                        "Folder picker returned items",
                        category: .folderImport,
                        metadata: [
                            "count": "\(urls.count)",
                            "names": urls.map(\.lastPathComponent).joined(separator: "|")
                        ]
                    )
                    isFolderImporterPresented = false
                    viewModel.handleFolderPickerSelection(urls: urls)
                },
                onCancel: {
                    AppLogger.info("Folder picker cancelled", category: .folderImport)
                    isFolderImporterPresented = false
                }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $activeMenuSheet) { sheet in
            HomeMenuSheetView(sheet: sheet)
        }
        .sheet(
            item: Binding(
                get: { viewModel.pendingSaveExportPrompt },
                set: { prompt in
                    if prompt == nil {
                        viewModel.dismissPendingSaveExportPrompt()
                    }
                }
            )
        ) { prompt in
            PendingSaveExportPicker(
                exportPresentationURL: prompt.exportPresentationURL,
                suggestedDirectoryURL: prompt.suggestedDirectoryURL,
                onPick: { urls in
                    AppLogger.info(
                        "Pending save export picker returned selection",
                        category: .saving,
                        metadata: [
                            "count": "\(urls.count)",
                            "names": urls.map(\.lastPathComponent).joined(separator: "|")
                        ]
                    )
                    if let url = urls.first {
                        viewModel.completePendingSaveExport(prompt: prompt, destinationURL: url)
                    } else {
                        viewModel.dismissPendingSaveExportPrompt()
                    }
                },
                onCancel: {
                    AppLogger.info("Pending save export picker cancelled", category: .saving)
                    viewModel.dismissPendingSaveExportPrompt()
                }
            )
            .ignoresSafeArea()
        }
        .sheet(
            item: Binding(
                get: { viewModel.folderAccessPrompt },
                set: { prompt in
                    if prompt == nil {
                        viewModel.dismissFolderAccessRecoveryPrompt()
                    }
                }
            )
        ) { _ in
            VideoDocumentPicker(
                contentTypes: [.folder],
                allowsMultipleSelection: false,
                onPick: { urls in
                    AppLogger.info(
                        "Folder access recovery picker returned folders",
                        category: .saving,
                        metadata: [
                            "count": "\(urls.count)",
                            "names": urls.map(\.lastPathComponent).joined(separator: "|")
                        ]
                    )
                    if let url = urls.first {
                        viewModel.recoverFolderAccessForPendingSave(url: url)
                    } else {
                        viewModel.dismissFolderAccessRecoveryPrompt()
                    }
                },
                onCancel: {
                    AppLogger.info("Folder access recovery picker cancelled", category: .saving)
                    viewModel.dismissFolderAccessRecoveryPrompt()
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(
            item: Binding<QueueVideoPreview?>(
                get: { viewModel.activePreview },
                set: { preview in
                    if preview == nil {
                        viewModel.dismissPreview()
                    }
                }
            )
        ) { preview in
            QueueVideoPreviewView(
                preview: preview,
                onClose: { viewModel.dismissPreview() }
            )
        }
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $selectedPhotoItem,
            matching: .videos,
            preferredItemEncoding: .current
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else {
                return
            }

            Task {
                do {
                    guard let importedVideo = try await newItem.loadTransferable(type: ImportedPhotoVideo.self) else {
                        await MainActor.run {
                            AppLogger.error("Photos picker returned no transferable video", category: .photosImport)
                            viewModel.fail(message: "The selected Photos video could not be imported.")
                        }
                        return
                    }

                    await MainActor.run {
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
                } catch {
                    await MainActor.run {
                        AppLogger.error(
                            "Photos picker import failed",
                            category: .photosImport,
                            metadata: ["error": error.localizedDescription]
                        )
                        viewModel.fail(message: error.localizedDescription)
                        selectedPhotoItem = nil
                    }
                }
            }
        }
        .task {
            await AdMobBootstrapper.refreshOnActive()
            await viewModel.restorePendingSavesIfNeeded()
            await viewModel.refreshStarsIfNeeded()
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
        .padding(.horizontal, 10 * metrics.contentScale)
        .frame(height: 34 * metrics.contentScale)
        .background(TaptionTheme.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TaptionTheme.border, lineWidth: 1)
        )
        .accessibilityLabel("Stars \(viewModel.starBalanceDisplayText)")
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
            .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.80))
            .frame(maxWidth: .infinity)
            .frame(height: metrics.footerExitButtonHeight)
            .background(Color(red: 1.0, green: 0.30, blue: 0.34).opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(red: 1.0, green: 0.30, blue: 0.34).opacity(0.48), lineWidth: 1)
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
                title: "Output",
                value: "\(viewModel.selectedOutput.container.defaultFileExtension.uppercased())",
                systemImage: "shippingbox",
                isEnabled: viewModel.canChangeOutputSelection,
                metrics: metrics
            ) {
                let availableContainers = viewModel.outputContainerOptions.filter { viewModel.outputContainerIsAvailableNow($0) }
                let unavailableContainers = viewModel.outputContainerOptions.filter { !viewModel.outputContainerIsAvailableNow($0) }

                ForEach(availableContainers, id: \.self) { container in
                    Button {
                        viewModel.selectOutputContainer(container)
                    } label: {
                        menuItemLabel(
                            title: viewModel.outputContainerMenuTitle(container),
                            isSelected: container == viewModel.selectedOutput.container,
                            isEnabled: true
                        )
                    }
                }

                if !availableContainers.isEmpty && !unavailableContainers.isEmpty {
                    Divider()
                }

                ForEach(unavailableContainers, id: \.self) { container in
                    Button {
                        viewModel.selectOutputContainer(container)
                    } label: {
                        menuItemLabel(
                            title: viewModel.outputContainerMenuTitle(container),
                            isSelected: container == viewModel.selectedOutput.container,
                            isEnabled: false
                        )
                    }
                    .disabled(true)
                }
            }

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

private enum QueuePreviewDragMode: Equatable {
    case seek(startPosition: Double)
    case brightness(startValue: CGFloat)
    case volume(startValue: Float)
}

private struct QueuePreviewGestureFeedback: Equatable {
    var systemImage: String
    var text: String
}

private struct QueueVideoPreviewView: View {
    var preview: QueueVideoPreview
    var onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player = Player(instance: QueuePreviewPlayerFactory.softwareDecodeInstance)
    @State private var playbackError: String?
    @State private var isLoading = true
    @State private var didRequestShutdown = false
    @State private var areControlsVisible = true
    @State private var isScrubbing = false
    @State private var scrubberPosition = 0.0
    @State private var dragMode: QueuePreviewDragMode?
    @State private var dragSeekPreviewPosition: Double?
    @State private var gestureFeedback: QueuePreviewGestureFeedback?
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var gestureFeedbackTask: Task<Void, Never>?
    @State private var didAttachVideoSurface = false

    var body: some View {
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

                    controlsOverlay
                        .transition(.opacity)
                }

                centerPlayPauseOverlay

                statusOverlay

                if let gestureFeedback {
                    gestureFeedbackOverlay(gestureFeedback)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
        }
        .background(
            Color.black
                .ignoresSafeArea()
        )
        .onAppear {
            AppOrientationController.shared.activatePreviewOrientations()
            showControls(scheduleAutoHide: false)
        }
        .task(id: preview.id) {
            await startPlayback()
        }
        .onChange(of: player.isPlaying) { _, isPlaying in
            if isPlaying {
                scheduleControlsAutoHide()
            } else {
                showControls(scheduleAutoHide: false)
            }
        }
        .onDisappear {
            shutdownPlayer()
        }
    }

    @ViewBuilder
    private func videoSurface(containerSize: CGSize) -> some View {
        let fittedSize = fittedVideoSize(in: containerSize)
        VideoView(player)
            .id(preview.id)
            .frame(width: fittedSize.width, height: fittedSize.height)
            .background(Color.black)
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

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            previewHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Spacer(minLength: 0)

            transportControls
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
    }

    private var previewHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text(preview.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        previewBadge(systemImage: "video", text: preview.codecBadge)
                        previewBadge(systemImage: "point.3.connected.trianglepath.dotted", text: preview.pathBadge)
                        previewBadge(systemImage: "aspectratio", text: preview.videoInfo.resolution)
                    }
                }
            }

            Spacer(minLength: 8)

            Button(action: closePreview) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.white.opacity(0.94))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
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
            Slider(
                value: Binding(
                    get: { displayedSliderPosition },
                    set: { newValue in
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
            .disabled(!player.isSeekable && player.duration == nil)
            .tint(Color.white)

            HStack(spacing: 16) {
                Button(action: skipBackward) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: 44, height: 38)
                }
                .accessibilityLabel("Rewind 10 seconds")

                Button(action: togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: 48, height: 40)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

                Button(action: skipForward) {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: 44, height: 38)
                }
                .accessibilityLabel("Forward 10 seconds")

                Text(displayedCurrentTimeText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))

                Spacer(minLength: 8)

                Text(durationText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.74))
            }
            .foregroundStyle(Color.white)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
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
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(Color.white.opacity(0.86))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.13))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var displayedSliderPosition: Double {
        if isScrubbing {
            return QueuePreviewPlaybackMath.clampedPosition(scrubberPosition)
        }
        if let dragSeekPreviewPosition {
            return QueuePreviewPlaybackMath.clampedPosition(dragSeekPreviewPosition)
        }
        return QueuePreviewPlaybackMath.clampedPosition(player.position)
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

    @MainActor
    private func startPlayback() async {
        playbackError = nil
        isLoading = true
        player.aspectRatio = .default

        do {
            await waitForVideoSurfaceAttachment()
            try Task.checkCancellation()
            let media = try makePreviewMedia()
            try player.play(media)
            if !(await waitForVideoOutput()) {
                AppLogger.warning(
                    "Queue preview started without a video output",
                    category: .ui,
                    metadata: [
                        "name": preview.displayName,
                        "activeVideoOutputs": "\(player.activeVideoOutputs)",
                        "hasVideoOutput": "\(player.hasVideoOutput)"
                    ]
                )
            }
            isLoading = false
            showControls(scheduleAutoHide: true)
        } catch is CancellationError {
            isLoading = false
        } catch {
            playbackError = "Preview failed. SwiftVLC could not decode this file."
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
        dismiss()
    }

    private func togglePlayback() {
        player.togglePlayPause()
        showControls(scheduleAutoHide: player.isPlaybackRequestedActive)
    }

    private func skipBackward() {
        seekBy(seconds: -QueuePreviewPlaybackMath.skipIntervalSeconds)
        showGestureFeedback(systemImage: "gobackward.10", text: "-10s")
    }

    private func skipForward() {
        seekBy(seconds: QueuePreviewPlaybackMath.skipIntervalSeconds)
        showGestureFeedback(systemImage: "goforward.10", text: "+10s")
    }

    private func seekBy(seconds: Double) {
        let offset = Duration.seconds(seconds)
        if (try? player.seek(by: offset, fast: true)) == nil {
            _ = player.jump(by: offset)
        }
        showControls(scheduleAutoHide: true)
    }

    private func finishScrubbing() {
        let target = QueuePreviewPlaybackMath.clampedPosition(scrubberPosition)
        if player.isSeekable, player.duration != nil {
            try? player.seek(to: PlaybackPosition(target))
        } else {
            _ = player.seek(toPosition: PlaybackPosition(target), fast: true)
        }
        isScrubbing = false
        scrubberPosition = target
        showControls(scheduleAutoHide: true)
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
        showControls(scheduleAutoHide: true)
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
            let volume = min(max(startValue + delta, 0), 2)
            try? player.setAudioVolume(Volume(volume))
            showGestureFeedback(
                systemImage: player.isMuted || volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                text: "\(Int((min(volume, 1) * 100).rounded()))%",
                autoDismiss: false
            )
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, containerSize: CGSize) {
        defer {
            dragMode = nil
            dragSeekPreviewPosition = nil
            dismissGestureFeedbackAfterDelay()
            showControls(scheduleAutoHide: true)
        }

        guard case .seek(let startPosition) = dragMode else {
            return
        }

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
    }

    private func resolvedDragMode(
        for value: DragGesture.Value,
        containerSize: CGSize
    ) -> QueuePreviewDragMode? {
        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)

        if horizontalDistance > verticalDistance * 1.2 {
            return .seek(startPosition: player.position)
        }

        if verticalDistance > horizontalDistance * 1.2 {
            if value.startLocation.x < containerSize.width / 2 {
                return .brightness(startValue: UIScreen.main.brightness)
            }
            return .volume(startValue: player.volume)
        }

        return nil
    }

    private func toggleControls() {
        if areControlsVisible {
            controlsHideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.18)) {
                areControlsVisible = false
            }
        } else {
            showControls(scheduleAutoHide: true)
        }
    }

    private func showControls(scheduleAutoHide: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            areControlsVisible = true
        }
        controlsHideTask?.cancel()
        guard scheduleAutoHide,
              player.isPlaybackRequestedActive,
              playbackError == nil,
              !isLoading else {
            return
        }
        scheduleControlsAutoHide()
    }

    private func scheduleControlsAutoHide() {
        controlsHideTask?.cancel()
        guard player.isPlaybackRequestedActive,
              playbackError == nil,
              !isLoading else {
            return
        }
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                areControlsVisible = false
            }
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

    private func makePreviewMedia() throws -> Media {
        let media = try Media(url: preview.sourceURL)
        QueuePreviewPlayerFactory.configureSoftwareDecodeOptions(on: media, sourceURL: preview.sourceURL)
        return media
    }

    @MainActor
    private func waitForVideoSurfaceAttachment() async {
        for _ in 0..<20 {
            if didAttachVideoSurface {
                try? await Task.sleep(nanoseconds: 120_000_000)
                return
            }
            if Task.isCancelled {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        AppLogger.warning(
            "Queue preview playback starting before video surface attachment was observed",
            category: .ui,
            metadata: ["name": preview.displayName]
        )
    }

    @MainActor
    private func waitForVideoOutput() async -> Bool {
        for _ in 0..<30 {
            if player.hasVideoOutput || player.activeVideoOutputs > 0 {
                return true
            }
            if Task.isCancelled {
                return false
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return player.hasVideoOutput || player.activeVideoOutputs > 0
    }

    private func shutdownPlayer() {
        guard !didRequestShutdown else {
            return
        }
        didRequestShutdown = true
        controlsHideTask?.cancel()
        gestureFeedbackTask?.cancel()
        AppOrientationController.shared.restorePortrait()
        Task { @MainActor in
            await player.shutdown()
        }
    }
}

enum QueuePreviewPlayerFactory {
    static let softwareDecodeInstance = makeSoftwareDecodeInstance(applicationName: "Taption Encoder Preview")

    static func configureSoftwareDecodeOptions(on media: Media, sourceURL: URL, allowsAudio: Bool = true) {
        media.addOption(":codec=avcodec")
        media.addOption(":avcodec-hw=none")
        media.addOption(":no-sub-autodetect-file")
        media.addOption(":no-drop-late-frames")
        media.addOption(":no-skip-frames")
        if !allowsAudio {
            media.addOption(":no-audio")
        }
        if sourceURL.pathExtension.lowercased() == "h261" {
            media.addOption(":demux=avformat")
            media.addOption(":avformat-format=h261")
        }
    }

    private static func makeSoftwareDecodeInstance(applicationName: String) -> VLCInstance {
        let arguments = VLCInstance.defaultArguments + [
            "--codec=avcodec",
            "--avcodec-hw=none"
        ]

        do {
            return try VLCInstance(
                arguments: arguments,
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
