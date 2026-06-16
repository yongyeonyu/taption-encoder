import SwiftUI
import PhotosUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @State private var isFileImporterPresented = false
    @State private var isFolderImporterPresented = false
    @State private var isPhotosPickerPresented = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var activeMenuSheet: HomeMenuSheet?

    init(environment: AppEnvironment = .phase0) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(environment: environment))
    }

    var body: some View {
        GeometryReader { geometry in
            let metrics = HomeLayoutMetrics(size: geometry.size)

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
                        statusText: viewModel.selectedOutputDetailStatusText,
                        outputSummary: viewModel.selectedOutputDetailSummary,
                        detailText: viewModel.selectedOutputDetailText,
                        routeBadges: viewModel.selectedOutputRouteBadges,
                        contentScale: metrics.contentScale
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detected Files")
                            .font(metrics.contentScale < 0.9 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text("Imported files are inspected automatically and show their video and audio route results here.")
                            .font(metrics.contentScale < 0.9 ? .caption2 : .caption)
                            .foregroundStyle(TaptionTheme.mutedText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    LoadedFilesPanelView(
                        files: viewModel.fileCardSnapshots,
                        contentScale: metrics.contentScale,
                        panelHeight: metrics.filePanelHeight,
                        onSelect: { viewModel.selectFileCard(id: $0) }
                    )

                    if let pendingJob = viewModel.pendingSaveRecoveryJob {
                        PendingSaveRecoveryView(
                            job: pendingJob,
                            onRetry: { viewModel.retryPendingSave() },
                            onReset: { viewModel.reset() }
                        )
                    }

                    EncodingProgressView(
                        state: viewModel.state,
                        controlHeight: metrics.controlHeight,
                        contentScale: metrics.contentScale,
                        onStart: { viewModel.startPreparedEncoding() },
                        onSave: { viewModel.saveCurrentPendingOutput() },
                        onCancel: { viewModel.cancel() }
                    )

                    Spacer(minLength: 0)

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
        .sheet(item: $activeMenuSheet) { sheet in
            HomeMenuSheetView(sheet: sheet)
        }
        .confirmationDialog(
            "File already exists",
            isPresented: Binding(
                get: { viewModel.saveConflictPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissSaveConflictPrompt()
                    }
                }
            ),
            presenting: viewModel.saveConflictPrompt
        ) { _ in
            Button("Overwrite", role: .destructive) {
                viewModel.overwriteExistingPendingSave()
            }
            Button("Save As") {
                viewModel.savePendingOutputAsNewFile()
            }
            Button("Cancel", role: .cancel) {
                viewModel.dismissSaveConflictPrompt()
            }
        } message: { prompt in
            Text(prompt.message)
        }
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                AppLogger.info(
                    "Folder picker returned folders",
                    category: .folderImport,
                    metadata: [
                        "count": "\(urls.count)",
                        "names": urls.map(\.lastPathComponent).joined(separator: "|")
                    ]
                )
                if let url = urls.first {
                    viewModel.startFolderFlow(url: url)
                }
            case .failure(let error):
                AppLogger.error(
                    "Folder picker failed",
                    category: .folderImport,
                    metadata: ["error": error.localizedDescription]
                )
                viewModel.fail(message: error.localizedDescription)
            }
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
            await viewModel.restorePendingSavesIfNeeded()
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

            Color.clear
                .frame(width: 34 * metrics.contentScale, height: 34 * metrics.contentScale)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func outputSelector(metrics: HomeLayoutMetrics) -> some View {
        HStack(spacing: 8 * metrics.contentScale) {
            outputMenu(
                title: "Output\nFormat",
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
                title: "Reso\nlution",
                value: viewModel.selectedOutput.resolutionPreset.menuTitle,
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
        return VStack(alignment: .leading, spacing: 6 * metrics.contentScale) {
            HStack(spacing: 7 * metrics.contentScale) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 14 * metrics.contentScale, weight: .semibold))
                Text("Size\n(MB)")
                    .font((metrics.contentScale < 0.9 ? Font.caption : metrics.buttonFont).weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Button {
                    viewModel.selectOutputSize(.auto)
                } label: {
                    Text("Auto")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(viewModel.selectedOutput.sizePreset == .auto ? Color.black : Color.white.opacity(0.82))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(viewModel.selectedOutput.sizePreset == .auto ? Color.white : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canChangeOutputSelection)
            }

            Text(viewModel.selectedOutputTargetSizeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TaptionTheme.mutedText)

            Slider(
                value: Binding(
                    get: { viewModel.selectedOutputTargetSizeValueMB },
                    set: { newValue in
                        viewModel.updateOutputTargetSizeMB(newValue)
                    }
                ),
                in: range,
                step: 1
            )
            .tint(TaptionTheme.accent)
            .disabled(!viewModel.canChangeOutputSelection)

            HStack {
                Text("\(Int(range.lowerBound.rounded())) MB")
                Spacer()
                Text("\(Int(range.upperBound.rounded())) MB")
            }
            .font(.caption2)
            .foregroundStyle(TaptionTheme.mutedText)
        }
        .foregroundStyle(viewModel.canChangeOutputSelection ? Color.white.opacity(0.9) : TaptionTheme.disabledText)
        .padding(.horizontal, 10 * metrics.contentScale)
        .padding(.vertical, 8 * metrics.contentScale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: max(metrics.controlHeight, 86 * metrics.contentScale))
        .background(TaptionTheme.elevatedSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(viewModel.canChangeOutputSelection ? TaptionTheme.border : Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(viewModel.canChangeOutputSelection ? 1 : 0.48)
    }

    private func outputMenu<Content: View>(
        title: String,
        value: String,
        systemImage: String,
        isEnabled: Bool,
        metrics: HomeLayoutMetrics,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 7 * metrics.contentScale) {
                Image(systemName: systemImage)
                    .font(.system(size: 14 * metrics.contentScale, weight: .semibold))
                Text(title)
                    .font((metrics.contentScale < 0.9 ? Font.caption : metrics.buttonFont).weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Text(value)
                    .font(Font.caption2.weight(.semibold))
                    .foregroundStyle(TaptionTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
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
        .disabled(!isEnabled)
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
