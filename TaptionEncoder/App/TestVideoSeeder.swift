import Foundation

struct TaptionTestVideoSeedResult: Equatable {
    let destinationURL: URL
    let removedExistingFolder: Bool
    let copiedFilenames: [String]
}

enum TaptionTestVideoSeeder {
    static let bundledFolderName = "TestVideos"
    static let documentsFolderName = "test video"
    static let sourceNoticeFilename = "SAMPLE_SOURCES.txt"

    static let expectedBundledVideoSampleFilenames = [
        "AV1.mp4",
        "VP9.webm",
        "VP8.webm",
        "MPEG-1.mpg",
        "MPEG-2.mpg",
        "MPEG-4 Visual.mov",
        "H.263.3gp",
        "H.261.h261",
        "Flash Video.flv",
        "Microsoft MPEG-4 V2.avi",
        "Microsoft MPEG-4 V3.wmv",
        "Motion JPEG.avi",
        "JPEG 2000.mov",
        "JPEG-LS.avi",
        "Lossless JPEG.avi",
        "Apple Animation.mov",
        "Cinepak.mov",
        "Sorenson Video.mov",
        "Sorenson Video 3.mov",
        "QuickTime Video.mov",
        "Theora.ogv",
        "RealVideo 1.0.rm",
        "RealVideo.rm",
        "RoQ Video.roq",
        "Windows Media Video.wmv",
        "Microsoft Video 1.avi",
        "ASUS V1.avi",
        "ASUS V2.avi",
        "Flash Screen Video.flv",
        "Flash Screen Video 2.flv",
        "ZMBV.avi",
        "CLJR.avi",
        "Snow.avi",
        "FFV1.avi",
        "HuffYUV.avi",
        "Ut Video.avi",
        "MagicYUV.avi",
        "DVCPro HD.mov",
        "DV.dv",
        "CineForm.avi",
        "DNxHD.mov",
        "PNG Video.avi",
        "R10K.mov",
        "V308.mov",
        "V210.avi",
        "R210.avi",
        "V408.mov",
        "V410.mov",
        "Microsoft RLE.avi",
        "QuickTime Graphics.mov",
        "YUV4.mov",
        "Raw Video.avi",
        "H.264 AVC.mp4",
        "H.265 HEVC.mp4",
        "Apple ProRes.mov"
    ]

    static func seedBundledSamplesIntoDocuments(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        do {
            guard let sourceURL = bundle.url(forResource: bundledFolderName, withExtension: nil) else {
                AppLogger.warning(
                    "Bundled test videos folder was not found",
                    category: .app,
                    metadata: ["folder": bundledFolderName]
                )
                return
            }

            let documentsURL = try documentsDirectoryURL(fileManager: fileManager)
            let result = try seedSamples(
                sourceURL: sourceURL,
                documentsDirectoryURL: documentsURL,
                fileManager: fileManager
            )
            AppLogger.info(
                "Test video samples seeded",
                category: .app,
                metadata: [
                    "destination": result.destinationURL.path,
                    "copied": "\(result.copiedFilenames.count)",
                    "removedExistingFolder": "\(result.removedExistingFolder)"
                ]
            )
        } catch {
            AppLogger.error(
                "Test video sample seeding failed",
                category: .app,
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    @discardableResult
    static func seedSamples(
        sourceURL: URL,
        documentsDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> TaptionTestVideoSeedResult {
        let destinationURL = documentsDirectoryURL.appendingPathComponent(
            documentsFolderName,
            isDirectory: true
        )
        let removedExistingFolder = fileManager.fileExists(atPath: destinationURL.path)
        if removedExistingFolder {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )

        let sourceFiles = try fileManager
            .contentsOfDirectory(
                at: sourceURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var copiedFilenames: [String] = []

        for sourceFileURL in sourceFiles {
            let filename = sourceFileURL.lastPathComponent
            let destinationFileURL = destinationURL.appendingPathComponent(filename, isDirectory: false)
            try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
            copiedFilenames.append(filename)
        }

        return TaptionTestVideoSeedResult(
            destinationURL: destinationURL,
            removedExistingFolder: removedExistingFolder,
            copiedFilenames: copiedFilenames
        )
    }

    private static func documentsDirectoryURL(fileManager: FileManager) throws -> URL {
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return documentsURL
    }
}
