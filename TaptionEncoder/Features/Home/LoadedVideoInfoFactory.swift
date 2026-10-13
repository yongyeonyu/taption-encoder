import Foundation

/// Presentation is rebuilt from the current output selection, independent of import/queue state.
enum LoadedVideoInfoFactory {
    static func make(source: HomeSelectedSource, asset: TaptionVideoAsset, outputName: String,
                     selectedOutput: TaptionOutputSelection, routeSelection: TaptionCodecRouteSelection? = nil) -> LoadedVideoInfo {
        let videoTrack = asset.videoTrack
        let audioTrack = asset.audioTracks.first
        let inputSupport = TaptionLaunchSupportCatalog.diagnoseInput(
            container: asset.container,
            videoCodec: videoTrack?.codec ?? .unknown
        )
        let routeSelection = routeSelection ?? TaptionCodecRoutePlanner.selectRoute(
            for: asset,
            outputCodec: selectedOutput.videoCodec,
            requestedMode: .automatic
        )
        let videoPath = LoadedVideoPathInfo.make(
            sourceCodec: videoTrack?.codec ?? .unknown,
            routeSelection: routeSelection,
            outputSelection: selectedOutput
        )
        let audioPath = LoadedAudioPathInfo.make(
            firstAudioTrack: audioTrack,
            trackCount: asset.audioTracks.count,
            outputCodec: selectedOutput.audioCodec,
            outputContainer: selectedOutput.container
        )
        return LoadedVideoInfo(
            fileName: source.displayName,
            inputSummary: "\(videoTrack?.codec.displayName ?? "Unknown") / \(asset.container.defaultFileExtension.uppercased())",
            resolution: videoTrack.map { "\($0.displaySize.width)x\($0.displaySize.height)" } ?? "Unknown",
            frameRate: MediaDisplayFormatting.frameRate(videoTrack?.nominalFrameRate),
            duration: MediaDisplayFormatting.time(asset.duration, unknown: "Unknown"),
            audio: audioTrack.map { ($0.codec == .unknown ? "Unknown audio" : $0.codec.displayName) + (asset.audioTracks.count > 1 ? " +\(asset.audioTracks.count - 1)" : "") } ?? "No audio",
            audioPathTitle: audioPath.title,
            audioPathDetail: audioPath.detail,
            audioOutputSummary: audioPath.outputSummary,
            fileSize: MediaDisplayFormatting.byteCount(asset.fingerprint.fileSize),
            inputSupportTitle: inputSupport.title,
            inputSupportDetail: inputSupport.detail,
            isInputSupportedNow: inputSupport.isSupportedNow,
            codecPathTitle: videoPath.title,
            codecPathDetail: videoPath.detail,
            outputSummary: videoPath.outputSummary,
            outputName: outputName,
            isRouteEncodable: videoPath.isRouteEncodable
        )
    }

}
