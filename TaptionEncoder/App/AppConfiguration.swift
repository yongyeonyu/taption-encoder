import Foundation

struct AppConfiguration: Equatable {
    let appName: String
    let bundleIdentifier: String
    let minimumOSDescription: String
    let outputSuffix: String
    let defaultOutputContainer: TaptionVideoContainer
    let defaultOutputCodec: TaptionVideoCodec
    let defaultEncoderMode: TaptionEncoderMode
    let backgroundEncodingMinimumMajorVersion: Int

    init(
        appName: String = "Taption Encoder",
        bundleIdentifier: String = "com.taption.encoder",
        minimumOSDescription: String = "iOS/iPadOS 15.0",
        outputSuffix: String = "_taption",
        defaultOutputContainer: TaptionVideoContainer = .mp4,
        defaultOutputCodec: TaptionVideoCodec = .hevc,
        defaultEncoderMode: TaptionEncoderMode = .automatic,
        backgroundEncodingMinimumMajorVersion: Int = 26
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.minimumOSDescription = minimumOSDescription
        self.outputSuffix = outputSuffix
        self.defaultOutputContainer = defaultOutputContainer
        self.defaultOutputCodec = defaultOutputCodec
        self.defaultEncoderMode = defaultEncoderMode
        self.backgroundEncodingMinimumMajorVersion = backgroundEncodingMinimumMajorVersion
    }
}
