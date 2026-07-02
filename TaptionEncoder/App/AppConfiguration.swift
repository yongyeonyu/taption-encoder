import Foundation

struct AppConfiguration: Equatable {
    let appName: String
    let bundleIdentifier: String
    let minimumOSDescription: String
    let outputSuffix: String
    let defaultOutputContainer: TaptionVideoContainer
    let defaultOutputCodec: TaptionVideoCodec
    let backgroundEncodingMinimumMajorVersion: Int
    let starPurchaseProducts: [StarPurchaseProduct]

    init(
        appName: String = "Taption Encoder",
        bundleIdentifier: String = "com.taption.encoder",
        minimumOSDescription: String = "iOS/iPadOS 18.0",
        outputSuffix: String = "_taption",
        defaultOutputContainer: TaptionVideoContainer = .mp4,
        defaultOutputCodec: TaptionVideoCodec = .hevc,
        backgroundEncodingMinimumMajorVersion: Int = 26,
        starPurchaseProducts: [StarPurchaseProduct] = [
            StarPurchaseProduct(
                productID: "com.taption.encoder.pro_mode",
                starCount: 0,
                displayName: "Pro Mode",
                displayPrice: "$1",
                displaySubtitle: "Remove ads and unlock unlimited Stars.",
                benefitLines: [
                    "Unlimited encoding starts without Star balance limits.",
                    "No rewarded ads before saves.",
                    "One-time non-consumable purchase that can be restored."
                ],
                grantsUnlimitedStars: true,
                removesAds: true
            )
        ]
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.minimumOSDescription = minimumOSDescription
        self.outputSuffix = outputSuffix
        self.defaultOutputContainer = defaultOutputContainer
        self.defaultOutputCodec = defaultOutputCodec
        self.backgroundEncodingMinimumMajorVersion = backgroundEncodingMinimumMajorVersion
        self.starPurchaseProducts = starPurchaseProducts
    }
}
