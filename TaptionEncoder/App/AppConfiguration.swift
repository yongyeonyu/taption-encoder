import Foundation

struct AppConfiguration: Equatable {
    static let marketingURL = URL(string: "https://bokkiyaw.com/products/encoder/")!
    static let supportURL = URL(string: "https://bokkiyaw.com/support/encoder/")!
    static let privacyPolicyURL = URL(string: "https://bokkiyaw.com/privacy/encoder/")!
    static let openSourceURL = URL(string: "https://bokkiyaw.com/licenses/")!
    static let supportEmail = "support@bokkiyaw.com"
    static let supportEmailURL = URL(string: "mailto:support@bokkiyaw.com")!

    let appName: String
    let bundleIdentifier: String
    let minimumOSDescription: String
    let outputSuffix: String
    let defaultOutputContainer: TaptionVideoContainer
    let defaultOutputCodec: TaptionVideoCodec
    let backgroundEncodingMinimumMajorVersion: Int

    init(
        appName: String = "BOKKI Encoder",
        bundleIdentifier: String = "com.taption.encoder",
        minimumOSDescription: String = "iOS/iPadOS 18.0",
        outputSuffix: String = "_taption",
        defaultOutputContainer: TaptionVideoContainer = .mp4,
        defaultOutputCodec: TaptionVideoCodec = .hevc,
        backgroundEncodingMinimumMajorVersion: Int = 26
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.minimumOSDescription = minimumOSDescription
        self.outputSuffix = outputSuffix
        self.defaultOutputContainer = defaultOutputContainer
        self.defaultOutputCodec = defaultOutputCodec
        self.backgroundEncodingMinimumMajorVersion = backgroundEncodingMinimumMajorVersion
    }
}
