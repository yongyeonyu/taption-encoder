import Foundation

enum SourceOpenRequest: Equatable {
    case files
    case photos
}

struct SourceOpenResult: Equatable {
    var sourceName: String
    var url: URL?

    init(sourceName: String, url: URL? = nil) {
        self.sourceName = sourceName
        self.url = url
    }
}

protocol SourceOpening {
    func open(request: SourceOpenRequest) async throws -> SourceOpenResult
}

struct FakeSourceOpener: SourceOpening {
    func open(request: SourceOpenRequest) async throws -> SourceOpenResult {
        switch request {
        case .files:
            return SourceOpenResult(sourceName: "Files")
        case .photos:
            return SourceOpenResult(sourceName: "Photos")
        }
    }
}

protocol VideoSourceDownloading {
    func ensureLocalVideo(at url: URL) async throws
}

enum VideoSourceDownloadError: LocalizedError {
    case timedOut
    case unavailable(Error)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "The iCloud video has not finished downloading."
        case .unavailable(let error):
            return "The iCloud video could not be downloaded. \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        "Check your connection, open Files, download the video, then try again."
    }
}

struct UbiquitousVideoDownloadState {
    var isUbiquitous: Bool
    var status: URLUbiquitousItemDownloadingStatus?
    var error: Error? = nil

    var hasLocalCopy: Bool {
        status == .downloaded || status == .current
    }
}

struct UbiquitousVideoDownloader: VideoSourceDownloading {
    var readState: (URL) throws -> UbiquitousVideoDownloadState = { url in
        guard FileManager.default.isUbiquitousItem(at: url) else {
            return UbiquitousVideoDownloadState(isUbiquitous: false)
        }
        // URL resource values may be cached; each poll needs the current status.
        var resourceURL = url
        resourceURL.removeAllCachedResourceValues()
        let values = try resourceURL.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemDownloadingErrorKey
        ])
        return UbiquitousVideoDownloadState(
            isUbiquitous: values.isUbiquitousItem == true,
            status: values.ubiquitousItemDownloadingStatus,
            error: values.ubiquitousItemDownloadingError
        )
    }
    var requestDownload: (URL) throws -> Void = {
        try FileManager.default.startDownloadingUbiquitousItem(at: $0)
    }
    var sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var pollInterval: Duration = .milliseconds(250)
    var pollAttempts = 480

    func ensureLocalVideo(at url: URL) async throws {
        try Task.checkCancellation()
        guard url.isFileURL else {
            return
        }

        do {
            let initial = try readState(url)
            guard initial.isUbiquitous, !initial.hasLocalCopy else {
                return
            }
            try Task.checkCancellation()
            AppLogger.info(
                "iCloud video download requested before inspection",
                category: .fileImport,
                metadata: ["name": url.lastPathComponent]
            )
            try requestDownload(url)

            for attempt in 0...max(0, pollAttempts) {
                try Task.checkCancellation()
                let state = try readState(url)
                if state.hasLocalCopy {
                    AppLogger.info(
                        "iCloud video download completed before inspection",
                        category: .fileImport,
                        metadata: ["name": url.lastPathComponent]
                    )
                    return
                }
                if let error = state.error {
                    throw VideoSourceDownloadError.unavailable(error)
                }
                guard attempt < pollAttempts else {
                    throw VideoSourceDownloadError.timedOut
                }
                try await sleep(pollInterval)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VideoSourceDownloadError {
            throw error
        } catch {
            throw VideoSourceDownloadError.unavailable(error)
        }
    }
}
