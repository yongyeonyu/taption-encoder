import Foundation

protocol MediaInspecting: TaptionVideoInspecting {}

struct FakeMediaInspector: MediaInspecting {
    func inspectVideo(at url: URL) async throws -> TaptionVideoAsset {
        TaptionVideoAsset(
            displayName: url.lastPathComponent,
            location: TaptionVideoAssetLocation(kind: .file, url: url),
            container: .unknown,
            duration: nil,
            videoTrack: TaptionVideoTrackInfo(
                codec: .av1,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30),
                estimatedBitrate: nil,
                color: TaptionColorDescription(),
                rotationDegrees: 0
            ),
            audioTracks: []
        )
    }
}
