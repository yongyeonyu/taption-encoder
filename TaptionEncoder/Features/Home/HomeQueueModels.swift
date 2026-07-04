import Foundation

struct BatteryEncodingSettings: Equatable {
    static let minimumLimitPercent = 30
    static let maximumLimitPercent = 100
    static let defaultLimitPercent = 30

    private static let batteryLimitPercentKey = "batteryEncoding.limitPercent"
    private static let powerConnectedOnlyKey = "batteryEncoding.powerConnectedOnly"
    private static let optimizationProfileKey = "batteryEncoding.optimizationProfile"

    var batteryLimitPercent: Int
    var powerConnectedOnly: Bool
    var optimizationProfile: TaptionEncodingOptimizationProfile

    init(
        batteryLimitPercent: Int = Self.defaultLimitPercent,
        powerConnectedOnly: Bool = false,
        optimizationProfile: TaptionEncodingOptimizationProfile = .balanced
    ) {
        self.batteryLimitPercent = Self.clampLimitPercent(batteryLimitPercent)
        self.powerConnectedOnly = powerConnectedOnly
        self.optimizationProfile = optimizationProfile
    }

    static var sliderRange: ClosedRange<Double> {
        Double(minimumLimitPercent)...Double(maximumLimitPercent)
    }

    static func load(defaults: UserDefaults = .standard) -> BatteryEncodingSettings {
        let storedLimit = defaults.object(forKey: batteryLimitPercentKey) == nil
            ? nil
            : defaults.integer(forKey: batteryLimitPercentKey)
        let storedPowerOnly = defaults.object(forKey: powerConnectedOnlyKey) == nil
            ? nil
            : defaults.bool(forKey: powerConnectedOnlyKey)
        let storedOptimizationProfile = defaults.string(forKey: optimizationProfileKey)
            .flatMap(TaptionEncodingOptimizationProfile.init(rawValue:))
        return BatteryEncodingSettings(
            batteryLimitPercent: storedLimit ?? defaultLimitPercent,
            powerConnectedOnly: storedPowerOnly ?? false,
            optimizationProfile: storedOptimizationProfile ?? .balanced
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(batteryLimitPercent, forKey: Self.batteryLimitPercentKey)
        defaults.set(powerConnectedOnly, forKey: Self.powerConnectedOnlyKey)
        defaults.set(optimizationProfile.rawValue, forKey: Self.optimizationProfileKey)
    }

    static func clampLimitPercent(_ value: Int) -> Int {
        min(max(value, minimumLimitPercent), maximumLimitPercent)
    }
}

struct BatteryEncodingPowerSnapshot: Equatable {
    var batteryPercent: Int?
    var isPowerConnected: Bool
    var isPowerStateKnown: Bool
}

enum BatteryEncodingBlockReason: Equatable {
    case batteryLimitReached(batteryPercent: Int, limitPercent: Int)
    case powerDisconnected(isPowerStateKnown: Bool)

    var alertTitle: String {
        "Connect Power"
    }

    var alertMessage: String {
        switch self {
        case .batteryLimitReached(let batteryPercent, let limitPercent):
            return "Battery is at \(batteryPercent)%. Battery Limit is \(limitPercent)%. Connect power before starting encoding."
        case .powerDisconnected(let isPowerStateKnown):
            if isPowerStateKnown {
                return "Power Connected Only is enabled. Connect power before starting encoding."
            }
            return "Power Connected Only is enabled, but power status is unavailable. Connect power before starting encoding."
        }
    }

    var batchStopMessage: String {
        switch self {
        case .batteryLimitReached(let batteryPercent, let limitPercent):
            return "Stopped after the current video. Battery reached \(batteryPercent)%, at or below the \(limitPercent)% Battery Limit. Connect power to continue encoding."
        case .powerDisconnected(let isPowerStateKnown):
            if isPowerStateKnown {
                return "Stopped after the current video. Power was disconnected while Power Connected Only was enabled. Connect power to continue encoding."
            }
            return "Stopped after the current video. Power status became unavailable while Power Connected Only was enabled. Connect power to continue encoding."
        }
    }
}

enum BatteryEncodingGate {
    static func blockReason(
        settings: BatteryEncodingSettings,
        snapshot: BatteryEncodingPowerSnapshot
    ) -> BatteryEncodingBlockReason? {
        if let batteryPercent = snapshot.batteryPercent,
           batteryPercent <= settings.batteryLimitPercent {
            return .batteryLimitReached(
                batteryPercent: batteryPercent,
                limitPercent: settings.batteryLimitPercent
            )
        }

        if settings.powerConnectedOnly,
           !snapshot.isPowerConnected {
            return .powerDisconnected(isPowerStateKnown: snapshot.isPowerStateKnown)
        }

        return nil
    }
}

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
    var isRouteEncodable: Bool
    var isStarLimited: Bool
    var isPreviewable: Bool

    static let queued = BatchItemRuntime(
        asset: nil,
        videoInfo: nil,
        progress: nil,
        statusText: "Queued",
        detailText: nil,
        isActive: false,
        isEnabled: true,
        isRouteEncodable: true,
        isStarLimited: false,
        isPreviewable: false
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
    var stopMessage: String?
    var itemStates: [URL: BatchItemRuntime]
    var selectedURL: URL?
    var multiSelectedURLs: Set<URL>
    var selectedSaveDestination: TaptionSaveDestinationKind?
    var outputFolderURL: URL?

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
        self.multiSelectedURLs = []
        self.selectedSaveDestination = nil
        self.outputFolderURL = nil
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
                thumbnailSourceURL: url,
                videoInfo: item.videoInfo,
                statusText: item.statusText,
                detailText: item.detailText,
                progress: item.progress,
                isActive: item.isActive,
                isSelected: selectedURL == url,
                isMultiSelected: multiSelectedURLs.contains(url),
                isEnabled: item.isEnabled,
                isStarLimited: item.isStarLimited,
                isPreviewable: item.isPreviewable
            )
        }
    }
}
