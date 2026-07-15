import Foundation
import UniformTypeIdentifiers

struct FolderContentsScanResult {
    let videoURLs: [URL]
    let folderURLs: [URL]
    let skippedNonVideoFileCount: Int
}

enum FolderContentsScanner {
    static func scan(folderURL: URL) throws -> FolderContentsScanResult {
        var coordinatedResult: Result<FolderContentsScanResult, Error>?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)

        coordinator.coordinate(
            readingItemAt: folderURL,
            options: [.withoutChanges],
            error: &coordinationError
        ) { coordinatedURL in
            coordinatedResult = Result {
                try scanCoordinatedFolder(at: coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let coordinatedResult else {
            throw CocoaError(.fileReadUnknown)
        }
        return try coordinatedResult.get()
    }

    private static func scanCoordinatedFolder(at folderURL: URL) throws -> FolderContentsScanResult {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey
        ]
        let contents = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var videoURLs: [URL] = []
        var folderURLs: [URL] = []
        var skippedNonVideoFileCount = 0

        for url in contents {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isHidden != true else {
                continue
            }
            if values.isDirectory == true, values.isPackage != true {
                folderURLs.append(url)
            } else if values.isRegularFile == true {
                if SupportedVideoFileExtensions.contains(url.pathExtension) {
                    videoURLs.append(url)
                } else {
                    skippedNonVideoFileCount += 1
                }
            }
        }

        let filenameAscending: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        return FolderContentsScanResult(
            videoURLs: videoURLs.sorted(by: filenameAscending),
            folderURLs: folderURLs.sorted(by: filenameAscending),
            skippedNonVideoFileCount: skippedNonVideoFileCount
        )
    }
}

enum SupportedVideoFileExtensions {
    static let fileExtensions: [String] = Array(
        Set(
            TaptionLaunchSupportCatalog.supportedInputContainers
                .flatMap(\.supportedFileExtensions)
        )
    ).sorted()

    static let fileExtensionSet = Set(fileExtensions)

    static func contains(_ fileExtension: String) -> Bool {
        let normalizedExtension = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return fileExtensionSet.contains(normalizedExtension)
    }
}

enum ExternalVideoOpenPolicy {
    static func canHandle(url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }
        return SupportedVideoFileExtensions.contains(url.pathExtension)
    }
}

enum ImportableVideoTypes {
    static let fileExtensions = SupportedVideoFileExtensions.fileExtensions

    static let all: [UTType] = {
        var types: [UTType] = [
            .mpeg4Movie,
            .quickTimeMovie
        ]

        for pathExtension in fileExtensions {
            if let type = UTType(filenameExtension: pathExtension),
               !types.contains(type) {
                types.append(type)
            }
        }

        return types
    }()
}
