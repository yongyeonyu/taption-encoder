@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

enum HW_AppleHEVCCodecAlgorithm {
    struct Selection {
        var mode: TaptionEncoderMode
        var backend: TaptionEncodingBackend
    }

    static var nativeSourceCodecs: [TaptionVideoCodec] {
        TaptionCodecRegistry.appleNativeHEVCHardwareSourceCodecs
    }

    static var nativeDescriptors: [TaptionCodecAlgorithmDescriptor] {
        TaptionCodecRegistry.appleNativeHEVCHardwareAlgorithmDescriptors
    }

    static func selectedMode(for requestedMode: TaptionEncoderMode) -> Selection {
        if hasHardwareHEVCEncoder {
            return Selection(mode: .hardware, backend: .appleVideoToolbox)
        }

        switch requestedMode {
        case .automatic, .hardware, .software:
            return Selection(mode: .software, backend: .appleAVAssetExport)
        }
    }

    static var hasHardwareHEVCEncoder: Bool {
        var encoderList: CFArray?
        guard VTCopyVideoEncoderList(nil, &encoderList) == noErr,
              let encoders = encoderList as? [[CFString: Any]] else {
            return false
        }

        return encoders.contains { encoder in
            guard let codecNumber = encoder[kVTVideoEncoderList_CodecType] as? NSNumber,
                  UInt32(truncating: codecNumber) == kCMVideoCodecType_HEVC else {
                return false
            }
            return (encoder[kVTVideoEncoderList_IsHardwareAccelerated] as? Bool) == true
        }
    }

    static func selectHEVCPreset(for asset: AVAsset) throws -> String {
        let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let candidates = [
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPresetHEVC3840x2160,
            AVAssetExportPresetHEVC1920x1080
        ]

        guard let preset = candidates.first(where: { compatiblePresets.contains($0) }) else {
            throw TaptionVideoCoreError.compatibleHEVCPresetUnavailable
        }
        return preset
    }

    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        try validate(request: request)
        let startedAt = Date()
        let trace = TaptionEncodingPerformanceTrace(
            name: "hw_hevc_transcode",
            category: .encoding,
            metadata: [
                "source": request.sourceURL.lastPathComponent,
                "route": request.route.displayName,
                "output": request.outputURL.lastPathComponent
            ]
        )
        let progressEmitter = EncodingProgressEmitter(progress: progress)
        do {
            let asset = AVURLAsset(url: request.sourceURL)
            let presetName = try selectHEVCPreset(for: asset)
            trace.mark("preset_selected", metadata: ["preset": presetName])

            progressEmitter.submit(TaptionEncodingProgress(
                stage: .preparing,
                fractionCompleted: 0,
                elapsedTime: 0,
                estimatedRemainingTime: nil
            ), force: true)

            guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
                throw TaptionVideoCoreError.compatibleHEVCPresetUnavailable
            }

            let outputFileType = avFileType(
                for: request.options.outputPolicy.container,
                supportedFileTypes: exportSession.supportedFileTypes
            )
            exportSession.outputURL = request.outputURL
            exportSession.outputFileType = outputFileType
            exportSession.shouldOptimizeForNetworkUse = true
            exportSession.videoComposition = try await videoCompositionIfNeeded(
                for: asset,
                targetSize: request.options.outputPolicy.advancedOptions.resizeTo
            )
            trace.mark(
                "export_session_configured",
                metadata: ["fileType": outputFileType.rawValue]
            )

            let exportSessionBox = HW_AppleHEVCExportSessionBox(exportSession)
            let progressTask = Task { [exportSessionBox] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    let rawProgress = Double(exportSessionBox.progress)
                    let fraction = min(max(rawProgress, 0.01), 0.99)
                    let elapsed = Date().timeIntervalSince(startedAt)
                    let remaining = fraction > 0.02
                        ? max(0, elapsed * (1 - fraction) / fraction)
                        : nil
                    progressEmitter.submit(TaptionEncodingProgress(
                        stage: .encoding,
                        fractionCompleted: fraction,
                        elapsedTime: elapsed,
                        estimatedRemainingTime: remaining
                    ))

                    if exportSessionBox.status == .completed
                        || exportSessionBox.status == .failed
                        || exportSessionBox.status == .cancelled {
                        return
                    }
                }
            }
            defer {
                progressTask.cancel()
            }
            try await export(exportSessionBox)
            trace.mark("export_completed")

            progressEmitter.submit(TaptionEncodingProgress(
                stage: .waitingForSaveGate,
                fractionCompleted: 1,
                elapsedTime: Date().timeIntervalSince(startedAt),
                estimatedRemainingTime: 0
            ), force: true)
            let progressStats = progressEmitter.stats
            trace.finish(
                "completed",
                metadata: [
                    "progressObserved": "\(progressStats.observedCount)",
                    "progressEmitted": "\(progressStats.emittedCount)"
                ]
            )

            return TaptionCodecTranscodeOutput(
                outputURL: request.outputURL,
                route: request.route,
                usedMode: .hardware,
                usedBackend: .appleVideoToolbox,
                outputVideoCodec: request.options.outputPolicy.videoCodec,
                outputAudioTrackCount: 1
            )
        } catch is CancellationError {
            trace.finish("cancelled")
            throw CancellationError()
        } catch {
            trace.finish("failed", metadata: ["error": error.localizedDescription])
            throw error
        }
    }

    private static func validate(request: TaptionCodecTranscodeRequest) throws {
        guard request.route.outputCodec == .hevc,
              request.options.outputPolicy.videoCodec == .hevc else {
            throw TaptionCodecTranscodingRegistryError.requestRouteMismatch(
                expected: request.route,
                actual: TaptionCodecRoute(
                    sourceCodec: request.route.sourceCodec,
                    outputCodec: request.options.outputPolicy.videoCodec
                )
            )
        }
        guard request.route.sourceCodec == .av1
                || nativeSourceCodecs.contains(request.route.sourceCodec) else {
            throw TaptionCodecTranscodingRegistryError.routeNotImplemented(request.route)
        }
    }

    private static func videoCompositionIfNeeded(
        for asset: AVAsset,
        targetSize: TaptionPixelSize?
    ) async throws -> AVMutableVideoComposition? {
        guard let targetSize,
              targetSize.isValid else {
            return nil
        }

        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            return nil
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let displayedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let displayedSize = CGSize(
            width: abs(displayedRect.width),
            height: abs(displayedRect.height)
        )
        let renderSize = evenSize(CGSize(
            width: CGFloat(targetSize.width),
            height: CGFloat(targetSize.height)
        ))

        guard displayedSize.width > 0,
              displayedSize.height > 0,
              renderSize.width > 0,
              renderSize.height > 0,
              !sizesAreEquivalent(displayedSize, renderSize) else {
            return nil
        }

        let scale = min(
            renderSize.width / displayedSize.width,
            renderSize.height / displayedSize.height
        )
        let scaledSize = CGSize(
            width: displayedSize.width * scale,
            height: displayedSize.height * scale
        )
        let originTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -displayedRect.minX, y: -displayedRect.minY)
        )
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let centeringTransform = CGAffineTransform(
            translationX: (renderSize.width - scaledSize.width) / 2,
            y: (renderSize.height - scaledSize.height) / 2
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(
            originTransform
                .concatenating(scaleTransform)
                .concatenating(centeringTransform),
            at: .zero
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = frameDuration(for: nominalFrameRate)
        composition.instructions = [instruction]
        return composition
    }

    private static func evenSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: CGFloat(evenDimension(size.width)),
            height: CGFloat(evenDimension(size.height))
        )
    }

    private static func evenDimension(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded - 1
    }

    private static func sizesAreEquivalent(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width.rounded() - rhs.width.rounded()) < 1
            && abs(lhs.height.rounded() - rhs.height.rounded()) < 1
    }

    private static func frameDuration(for nominalFrameRate: Float) -> CMTime {
        guard nominalFrameRate.isFinite,
              nominalFrameRate > 0 else {
            return CMTime(value: 1, timescale: 30)
        }
        return CMTime(seconds: 1.0 / Double(nominalFrameRate), preferredTimescale: 600)
    }

    private static func export(_ exportSessionBox: HW_AppleHEVCExportSessionBox) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                exportSessionBox.exportAsynchronously {
                    switch exportSessionBox.status {
                    case .completed:
                        continuation.resume()
                    case .cancelled:
                        continuation.resume(throwing: CancellationError())
                    case .failed:
                        continuation.resume(throwing: exportSessionBox.error ?? TaptionVideoCoreError.exportFailed("H.265 export failed."))
                    default:
                        continuation.resume(throwing: TaptionVideoCoreError.exportFailed("H.265 export ended with status \(exportSessionBox.status.rawValue)."))
                    }
                }
            }
        } onCancel: {
            exportSessionBox.cancelExport()
        }
    }

    private static func avFileType(
        for container: TaptionVideoContainer,
        supportedFileTypes: [AVFileType]
    ) -> AVFileType {
        let preferred: AVFileType
        switch container {
        case .mov:
            preferred = .mov
        case .m4v:
            preferred = .m4v
        default:
            preferred = .mp4
        }
        if supportedFileTypes.contains(preferred) {
            return preferred
        }
        if supportedFileTypes.contains(.mp4) {
            return .mp4
        }
        return supportedFileTypes.first ?? .mov
    }
}

private final class HW_AppleHEVCExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }

    var progress: Float {
        session.progress
    }

    var status: AVAssetExportSession.Status {
        session.status
    }

    var error: Error? {
        session.error
    }

    func exportAsynchronously(completionHandler: @escaping () -> Void) {
        session.exportAsynchronously(completionHandler: completionHandler)
    }

    func cancelExport() {
        session.cancelExport()
    }
}
