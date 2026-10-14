import Foundation
import Photos

struct PhotoLibraryVideo: Identifiable, Equatable, Sendable {
    let id: String
    let fileName: String
    let duration: TimeInterval
}

struct PhotoLibrarySelection: Sendable {
    let albumName: String
    let videos: [PhotoLibraryVideo]
    let selectedID: String
}

protocol PhotoVideoLoading {
    func loadVideo(_ video: PhotoLibraryVideo, to destination: URL) async throws
}

enum PhotoLibraryVideoError: LocalizedError {
    case unavailable, changed
    var errorDescription: String? {
        switch self {
        case .unavailable: return "This video is no longer available in Photos. Open Album and choose another video."
        case .changed: return "This video changed in Photos. Open Album again to refresh it."
        }
    }
}

enum PhotoLibraryVideoResource {
    static func currentResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        return resources.first { $0.type == .fullSizeVideo } ?? resources.first { $0.type == .video }
    }
}

/// Copies only videos that are opened, preserving the current full-size resource.
/// Duplicate requests share a writer, so rapid swipes cannot race on one file.
actor PhotoKitVideoLoader: PhotoVideoLoading {
    private var requests: [URL: (id: UUID, task: Task<Void, Error>)] = [:]

    func loadVideo(_ video: PhotoLibraryVideo, to destination: URL) async throws {
        try Task.checkCancellation()
        let request: (id: UUID, task: Task<Void, Error>)
        if let pending = requests[destination] { request = pending }
        else {
            if FileManager.default.isReadableFile(atPath: destination.path) { return }
            request = (UUID(), Task { try await Self.export(video, to: destination) })
            requests[destination] = request
            Task { [weak self] in
                _ = await request.task.result
                await self?.finishRequest(destination, id: request.id)
            }
        }
        try await PhotoVideoLoadWaiter.wait(for: request.task)
        try Task.checkCancellation()
    }

    private func finishRequest(_ url: URL, id: UUID) {
        if requests[url]?.id == id { requests[url] = nil }
    }

    private static func export(_ video: PhotoLibraryVideo, to destination: URL) async throws {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [video.id], options: nil).firstObject,
              let resource = PhotoLibraryVideoResource.currentResource(for: asset) else { throw PhotoLibraryVideoError.unavailable }
        guard resource.originalFilename == video.fileName else { throw PhotoLibraryVideoError.changed }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

/// Cancelling a view's wait does not cancel a shared resource writer or resurrect the view.
final class PhotoVideoLoadWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?
    private var continuation: CheckedContinuation<Void, Error>?

    static func wait(for task: Task<Void, Error>) async throws {
        let waiter = PhotoVideoLoadWaiter()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiter.install(continuation)
                Task { waiter.finish(await task.result) }
            }
        } onCancel: { waiter.finish(.failure(CancellationError())) }
    }
    private func install(_ value: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let result { lock.unlock(); value.resume(with: result) }
        else { continuation = value; lock.unlock() }
    }
    private func finish(_ value: Result<Void, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let pending = continuation; continuation = nil
        lock.unlock()
        pending?.resume(with: value)
    }
}
