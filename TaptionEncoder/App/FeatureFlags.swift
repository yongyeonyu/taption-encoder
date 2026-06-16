import Foundation

struct FeatureFlags: Equatable {
    var isRealEncodingEnabled: Bool
    var isAdMobEnabled: Bool
    var isPhotosImportEnabled: Bool
    var isBackgroundEncodingEnabled: Bool
    var isProjectEditingEnabled: Bool
    var isMergeEditingEnabled: Bool
    var usesFakeServices: Bool

    init(
        isRealEncodingEnabled: Bool = false,
        isAdMobEnabled: Bool = false,
        isPhotosImportEnabled: Bool = false,
        isBackgroundEncodingEnabled: Bool = false,
        isProjectEditingEnabled: Bool = false,
        isMergeEditingEnabled: Bool = false,
        usesFakeServices: Bool = true
    ) {
        self.isRealEncodingEnabled = isRealEncodingEnabled
        self.isAdMobEnabled = isAdMobEnabled
        self.isPhotosImportEnabled = isPhotosImportEnabled
        self.isBackgroundEncodingEnabled = isBackgroundEncodingEnabled
        self.isProjectEditingEnabled = isProjectEditingEnabled
        self.isMergeEditingEnabled = isMergeEditingEnabled
        self.usesFakeServices = usesFakeServices
    }

    static let phase0 = FeatureFlags(
        isRealEncodingEnabled: true,
        isAdMobEnabled: true,
        usesFakeServices: false
    )
}
