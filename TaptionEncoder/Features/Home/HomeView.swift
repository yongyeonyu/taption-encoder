import SwiftUI
import PhotosUI

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
                        onSelect: { viewModel.selectFileCard(id: $0) }
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
                contentTypes: [.folder],
                allowsMultipleSelection: false,
                onPick: { urls in
                    AppLogger.info(
                        "Folder picker returned folders",
                        category: .folderImport,
                        metadata: [
                            "count": "\(urls.count)",
                            "names": urls.map(\.lastPathComponent).joined(separator: "|")
                        ]
                    )
                    isFolderImporterPresented = false
                    if let url = urls.first {
                        viewModel.startFolderFlow(url: url)
                    }
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

#Preview {
    HomeView()
}
