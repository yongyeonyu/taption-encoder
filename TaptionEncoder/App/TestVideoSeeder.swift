import Foundation

struct TaptionTestVideoSeedResult: Equatable {
    let destinationURL: URL
    let copiedFilenames: [String]
    let skippedFilenames: [String]
}

enum TaptionTestVideoSeeder {
    static let bundledFolderName = "TestVideos"
    static let documentsFolderName = "test video"
    static let sourceNoticeFilename = "SAMPLE_SOURCES.txt"

    static let expectedBundledVideoSampleFilenames = [
        "available-now_av1_av01_mp4.mp4",
        "available-now_vp9_vp09_webm.webm",
        "available-now_vp8_vp8_webm.webm",
        "available-now_mpeg1_mpeg1video_mpg.mpg",
        "available-now_mpeg2_mpeg2video_mpg.mpg",
        "available-now_mpeg4-visual_mpeg4_avi.avi",
        "available-now_h263_h263_3gp.3gp",
        "available-now_h261_h261_h261.h261",
        "available-now_flash-video_flv1_flv.flv",
        "available-now_microsoft-mpeg4-v2_msmpeg4v2_avi.avi",
        "available-now_microsoft-mpeg4-v3_msmpeg4v3_avi.avi",
        "available-now_motion-jpeg_mjpeg_avi.avi",
        "available-now_jpeg-2000_jpeg2000_mov.mov",
        "available-now_jpeg-ls_jpegls_avi.avi",
        "available-now_lossless-jpeg_ljpeg_avi.avi",
        "available-now_apple-animation_qtrle_mov.mov",
        "available-now_cinepak_cvid_mov.mov",
        "available-now_sorenson-video_svq1_mov.mov",
        "available-now_sorenson-video-3_svq3_mov.mov",
        "available-now_quicktime-video_rpza_mov.mov",
        "available-now_theora_theora_ogv.ogv",
        "available-now_wmv_wmv2_wmv.wmv",
        "available-now_h264-avc_avc1_mp4.mp4",
        "available-now_h265-hevc_hvc1_mp4.mp4",
        "supported-hardware_prores_prores_mov.mov"
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
                    "skipped": "\(result.skippedFilenames.count)"
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
        var skippedFilenames: [String] = []

        for sourceFileURL in sourceFiles {
            let filename = sourceFileURL.lastPathComponent
            let destinationFileURL = destinationURL.appendingPathComponent(filename, isDirectory: false)
            if fileManager.fileExists(atPath: destinationFileURL.path) {
                skippedFilenames.append(filename)
                continue
            }

            try fileManager.copyItem(at: sourceFileURL, to: destinationFileURL)
            copiedFilenames.append(filename)
        }

        return TaptionTestVideoSeedResult(
            destinationURL: destinationURL,
            copiedFilenames: copiedFilenames,
            skippedFilenames: skippedFilenames
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
