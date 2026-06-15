@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

protocol EncoderServicing: TaptionVideoEncoding {}

struct FakeEncoderService: EncoderServicing {
    func encode(
        plan: TaptionEncodingPlan,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionEncodingResult {
        let totalSteps = 24
        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))

        for step in 1...totalSteps {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 120_000_000)

            let fraction = Double(step) / Double(totalSteps)
            let elapsed = Double(step) * 0.12
            let remaining = max(0, Double(totalSteps - step) * 0.12)
            progress(TaptionEncodingProgress(
                stage: step == totalSteps ? .waitingForSaveGate : .encoding,
                fractionCompleted: fraction,
                elapsedTime: elapsed,
                estimatedRemainingTime: remaining,
                currentFrame: Int64(step * 30),
                totalFrames: Int64(totalSteps * 30)
            ))
        }

        guard let temporaryOutputURL = plan.temporaryOutputURL else {
            throw TaptionVideoCoreError.missingTemporaryOutputURL
        }

        return TaptionEncodingResult(
            planID: plan.id,
            temporaryOutputURL: temporaryOutputURL,
            finalOutputURL: nil,
            usedBackend: plan.encoderSelection.backend ?? .simulatedHardware,
            usedMode: plan.encoderSelection.requestedMode
        )
    }

    func cancelEncoding(planID: UUID) async {}
}

final class AVFoundationHEVCEncoderService: EncoderServicing {
    private let lock = NSLock()
    private var activeExports: [UUID: AVAssetExportSession] = [:]

    func encode(
        plan: TaptionEncodingPlan,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionEncodingResult {
        guard let sourceURL = plan.sourceURL else {
            throw TaptionVideoCoreError.missingSourceURL
        }
        guard let temporaryOutputURL = plan.temporaryOutputURL else {
            throw TaptionVideoCoreError.missingTemporaryOutputURL
        }

        try FileManager.default.createDirectory(
            at: temporaryOutputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: temporaryOutputURL)

        let asset = AVURLAsset(url: sourceURL)
        let presetName = try selectHEVCPreset(for: asset)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw TaptionVideoCoreError.compatibleHEVCPresetUnavailable
        }

        let outputFileType = exportSession.supportedFileTypes.contains(.mp4)
            ? AVFileType.mp4
            : (exportSession.supportedFileTypes.first ?? .mov)
        exportSession.outputURL = temporaryOutputURL
        exportSession.outputFileType = outputFileType
        exportSession.shouldOptimizeForNetworkUse = true

        let exportSessionBox = ExportSessionBox(exportSession)
        let selectedMode = HEVCEncoderCapability.selectedMode(for: plan.encoderSelection.requestedMode)
        setActiveExport(exportSession, for: plan.id)
        let startedAt = Date()

        progress(TaptionEncodingProgress(
            stage: .preparing,
            fractionCompleted: 0,
            elapsedTime: 0,
            estimatedRemainingTime: nil
        ))

        let progressTask = Task { [exportSessionBox] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                let rawProgress = Double(exportSessionBox.progress)
                let fraction = min(max(rawProgress, 0.01), 0.99)
                let elapsed = Date().timeIntervalSince(startedAt)
                let remaining = fraction > 0.02
                    ? max(0, elapsed * (1 - fraction) / fraction)
                    : nil
                progress(TaptionEncodingProgress(
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

        do {
            try await export(exportSessionBox)
            progressTask.cancel()
            removeActiveExport(for: plan.id)

            guard FileManager.default.fileExists(atPath: temporaryOutputURL.path) else {
                throw TaptionVideoCoreError.exportFailed("The H.265 output file was not created.")
            }

            progress(TaptionEncodingProgress(
                stage: .waitingForSaveGate,
                fractionCompleted: 1,
                elapsedTime: Date().timeIntervalSince(startedAt),
                estimatedRemainingTime: 0
            ))

            return TaptionEncodingResult(
                planID: plan.id,
                temporaryOutputURL: temporaryOutputURL,
                finalOutputURL: plan.finalOutputURL,
                usedBackend: selectedMode.backend,
                usedMode: selectedMode.mode
            )
        } catch is CancellationError {
            progressTask.cancel()
            removeActiveExport(for: plan.id)
            try? FileManager.default.removeItem(at: temporaryOutputURL)
            throw CancellationError()
        } catch {
            progressTask.cancel()
            removeActiveExport(for: plan.id)
            try? FileManager.default.removeItem(at: temporaryOutputURL)
            throw TaptionVideoCoreError.exportFailed(error.localizedDescription)
        }
    }

    func cancelEncoding(planID: UUID) async {
        let exportSession = activeExport(for: planID)
        exportSession?.cancelExport()
        removeActiveExport(for: planID)
    }

    private func selectHEVCPreset(for asset: AVAsset) throws -> String {
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

    private func export(_ exportSessionBox: ExportSessionBox) async throws {
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

    private func setActiveExport(_ exportSession: AVAssetExportSession, for planID: UUID) {
        lock.lock()
        activeExports[planID] = exportSession
        lock.unlock()
    }

    private func activeExport(for planID: UUID) -> AVAssetExportSession? {
        lock.lock()
        let exportSession = activeExports[planID]
        lock.unlock()
        return exportSession
    }

    private func removeActiveExport(for planID: UUID) {
        lock.lock()
        activeExports.removeValue(forKey: planID)
        lock.unlock()
    }
}

private final class ExportSessionBox: @unchecked Sendable {
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

    func exportAsynchronously(completionHandler handler: @escaping @Sendable () -> Void) {
        session.exportAsynchronously(completionHandler: handler)
    }

    func cancelExport() {
        session.cancelExport()
    }
}

private enum HEVCEncoderCapability {
    struct Selection {
        var mode: TaptionEncoderMode
        var backend: TaptionEncodingBackend
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

    private static var hasHardwareHEVCEncoder: Bool {
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
}
