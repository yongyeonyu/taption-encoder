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
                        onCancel: { viewModel.cancel() }
                    )

                    if viewModel.state.completedTemporaryOutput != nil {
                        Button {
                            AppLogger.info("Watch Ad & Save button tapped", category: .ui)
                            viewModel.saveCompletedTemporaryOutput()
                        } label: {
                            Label("Watch Ad & Save", systemImage: "play.rectangle")
                                .font(metrics.buttonFont)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: metrics.controlHeight)
                        }
                        .buttonStyle(.plain)
                        .background(TaptionTheme.accent)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(TaptionTheme.accent.opacity(0.65), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

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
                title: "Output",
                value: "\(viewModel.selectedOutput.videoCodec.shortDisplayName) - \(viewModel.selectedOutputStatusText)",
                systemImage: "arrow.triangle.2.circlepath",
                isEnabled: viewModel.canChangeOutputSelection,
                metrics: metrics
            ) {
                ForEach(viewModel.outputCodecOptions, id: \.self) { codec in
                    Button {
                        viewModel.selectOutputCodec(codec)
                    } label: {
                        if codec == viewModel.selectedOutput.videoCodec {
                            Label(viewModel.outputCodecMenuTitle(codec), systemImage: "checkmark")
                        } else {
                            Text(viewModel.outputCodecMenuTitle(codec))
                        }
                    }
                }
            }

            outputMenu(
                title: "Container",
                value: "\(viewModel.selectedOutput.container.defaultFileExtension.uppercased()) - \(viewModel.selectedOutputStatusText)",
                systemImage: "shippingbox",
                isEnabled: viewModel.canChangeOutputSelection,
                metrics: metrics
            ) {
                ForEach(viewModel.outputContainerOptions, id: \.self) { container in
                    Button {
                        viewModel.selectOutputContainer(container)
                    } label: {
                        let label = viewModel.outputContainerMenuTitle(container)
                        if container == viewModel.selectedOutput.container {
                            Label(label, systemImage: "checkmark")
                        } else {
                            Text(label)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
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
                    .font(metrics.buttonFont.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 4)
                Text(value)
                    .font((metrics.contentScale < 0.9 ? Font.caption2 : Font.caption).weight(.semibold))
                    .foregroundStyle(TaptionTheme.mutedText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(isEnabled ? Color.white.opacity(0.9) : TaptionTheme.disabledText)
            .padding(.horizontal, 10 * metrics.contentScale)
            .frame(maxWidth: .infinity)
            .frame(height: metrics.controlHeight)
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
}

#Preview {
    HomeView()
}
