import AVFoundation

enum HW_AV1HEVCCodecAlgorithm: TaptionStaticCodecTranscodingAlgorithm {
    static let descriptor = TaptionCodecAlgorithmDescriptor(
        sourceCodec: .av1,
        outputCodec: .hevc,
        mode: .hardware,
        backend: .appleVideoToolbox,
        displayName: "AV1 to H.265 Hardware"
    )

    typealias Selection = HW_AppleHEVCCodecAlgorithm.Selection

    static func selectedMode(for requestedMode: TaptionEncoderMode) -> Selection {
        HW_AppleHEVCCodecAlgorithm.selectedMode(for: requestedMode)
    }

    static func selectHEVCPreset(for asset: AVAsset) throws -> String {
        try HW_AppleHEVCCodecAlgorithm.selectHEVCPreset(for: asset)
    }

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try await HW_AppleHEVCCodecAlgorithm.transcode(
            request: request,
            progress: progress
        )
    }
}
