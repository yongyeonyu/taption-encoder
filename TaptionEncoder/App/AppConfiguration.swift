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
                productID: "com.taption.encoder.stars.10",
                starCount: 10,
                displayName: "10 Stars"
            ),
            StarPurchaseProduct(
                productID: "com.taption.encoder.stars.50",
                starCount: 50,
                displayName: "50 Stars"
            ),
            StarPurchaseProduct(
                productID: "com.taption.encoder.stars.100",
                starCount: 100,
                displayName: "100 Stars"
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
