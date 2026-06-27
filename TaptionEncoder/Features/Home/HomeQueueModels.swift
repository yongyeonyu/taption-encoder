import Foundation

struct TaptionInspectedMediaCache {
    private var assetsByURL: [URL: TaptionVideoAsset] = [:]

    mutating func store(_ asset: TaptionVideoAsset, for url: URL) {
        assetsByURL[url] = asset
    }

    func asset(
        for url: URL,
        currentFingerprint: TaptionMediaFingerprint
    ) -> TaptionVideoAsset? {
        guard let asset = assetsByURL[url],
              asset.fingerprint == currentFingerprint else {
            return nil
        }
        return asset
    }

    mutating func removeAll() {
        assetsByURL.removeAll()
    }
}

struct BatchItemRuntime {
    var asset: TaptionVideoAsset?
    var videoInfo: LoadedVideoInfo?
    var progress: EncodingProgressSnapshot?
    var statusText: String
    var detailText: String?
    var isActive: Bool
    var isEnabled: Bool

    static let queued = BatchItemRuntime(
        asset: nil,
        videoInfo: nil,
        progress: nil,
        statusText: "Queued",
        detailText: nil,
        isActive: false,
        isEnabled: true
    )
}

struct FolderEncodingBatch {
    var folderURL: URL?
    var folderName: String
    var sourceKind: HomeSourceKind
    var fileURLs: [URL]
    var currentIndex: Int = 0
    var completedCount: Int = 0
    var failedCount: Int = 0
    var lastFailureMessage: String?
    var itemStates: [URL: BatchItemRuntime]
    var selectedURL: URL?

    init(
        folderURL: URL? = nil,
        folderName: String,
        sourceKind: HomeSourceKind,
        fileURLs: [URL]
    ) {
        self.folderURL = folderURL
        self.folderName = folderName
        self.sourceKind = sourceKind
        self.fileURLs = fileURLs
        self.selectedURL = fileURLs.first
        self.itemStates = Dictionary(
            uniqueKeysWithValues: fileURLs.map { ($0, BatchItemRuntime.queued) }
        )
    }

    var totalCount: Int {
        fileURLs.count
    }

    var currentFileURL: URL? {
        guard fileURLs.indices.contains(currentIndex) else {
            return nil
        }
        return fileURLs[currentIndex]
    }

    var hasRemainingFiles: Bool {
        currentIndex < fileURLs.count
    }

    var hasEncodableFiles: Bool {
        fileURLs.contains { itemStates[$0]?.isEnabled != false }
    }

    var remainingEncodableFileCount: Int {
        remainingEncodableFileCount(startingAt: currentIndex)
    }

    func remainingEncodableFileCount(startingAt index: Int) -> Int {
        let startIndex = min(max(index, 0), fileURLs.count)
        return fileURLs
            .dropFirst(startIndex)
            .filter { itemStates[$0]?.isEnabled != false }
            .count
    }

    func snapshot(currentFileName: String? = nil) -> FolderQueueSnapshot {
        FolderQueueSnapshot(
            folderName: folderName,
            currentIndex: currentIndex,
            totalCount: totalCount,
            completedCount: completedCount,
            failedCount: failedCount,
            currentFileName: currentFileName ?? currentFileURL?.lastPathComponent
        )
    }

    func cardSnapshots() -> [EncodingFileCardSnapshot] {
        fileURLs.map { url in
            let item = itemStates[url] ?? .queued
            return EncodingFileCardSnapshot(
                id: url.absoluteString,
                fileName: url.lastPathComponent,
                sourceKind: sourceKind,
                videoInfo: item.videoInfo,
                statusText: item.statusText,
                detailText: item.detailText,
                progress: item.progress,
                isActive: item.isActive,
                isSelected: selectedURL == url,
                isEnabled: item.isEnabled
            )
        }
    }
}
