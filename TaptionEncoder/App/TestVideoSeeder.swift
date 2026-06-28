import Foundation

struct TaptionTestVideoSeedResult: Equatable {
    let destinationURL: URL
    let migratedFilenames: [String]
    let removedLegacyFilenames: [String]
    let copiedFilenames: [String]
    let skippedFilenames: [String]
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
        "Windows Media Video.wmv",
        "Microsoft Video 1.avi",
        "ASUS V1.avi",
        "ASUS V2.avi",
        "Flash Screen Video.flv",
        "Flash Screen Video 2.flv",
        "ZMBV.avi",
        "CLJR.avi",
        "FFV1.avi",
        "HuffYUV.avi",
        "DVCPro HD.mov",
        "DV.dv",
        "CineForm.avi",
        "DNxHD.mov",
        "V308.mov",
        "V210.avi",
        "V408.mov",
        "V410.mov",
        "YUV4.mov",
        "H.264 AVC.mp4",
        "H.265 HEVC.mp4",
        "Apple ProRes.mov"
    ]

    static let legacyVideoSampleFilenamePairs: [(current: String, legacy: String)] = [
        ("AV1.mp4", "available-now_av1_av01_mp4.mp4"),
        ("VP9.webm", "available-now_vp9_vp09_webm.webm"),
        ("VP8.webm", "available-now_vp8_vp8_webm.webm"),
        ("MPEG-1.mpg", "available-now_mpeg1_mpeg1video_mpg.mpg"),
        ("MPEG-2.mpg", "available-now_mpeg2_mpeg2video_mpg.mpg"),
        ("MPEG-4 Visual.mov", "available-now_mpeg4-visual_mpeg4_avi.avi"),
        ("MPEG-4 Visual.mov", "MPEG-4 Visual.avi"),
        ("H.263.3gp", "available-now_h263_h263_3gp.3gp"),
        ("H.261.h261", "available-now_h261_h261_h261.h261"),
        ("Flash Video.flv", "available-now_flash-video_flv1_flv.flv"),
        ("Microsoft MPEG-4 V2.avi", "available-now_microsoft-mpeg4-v2_msmpeg4v2_avi.avi"),
        ("Microsoft MPEG-4 V3.wmv", "available-now_microsoft-mpeg4-v3_msmpeg4v3_avi.avi"),
        ("Microsoft MPEG-4 V3.wmv", "Microsoft MPEG-4 V3.avi"),
        ("Motion JPEG.avi", "available-now_motion-jpeg_mjpeg_avi.avi"),
        ("JPEG 2000.mov", "available-now_jpeg-2000_jpeg2000_mov.mov"),
        ("JPEG-LS.avi", "available-now_jpeg-ls_jpegls_avi.avi"),
        ("Lossless JPEG.avi", "available-now_lossless-jpeg_ljpeg_avi.avi"),
        ("Apple Animation.mov", "available-now_apple-animation_qtrle_mov.mov"),
        ("Cinepak.mov", "available-now_cinepak_cvid_mov.mov"),
        ("Sorenson Video.mov", "available-now_sorenson-video_svq1_mov.mov"),
        ("Sorenson Video 3.mov", "available-now_sorenson-video-3_svq3_mov.mov"),
        ("QuickTime Video.mov", "available-now_quicktime-video_rpza_mov.mov"),
        ("Theora.ogv", "available-now_theora_theora_ogv.ogv"),
        ("Windows Media Video.wmv", "available-now_wmv_wmv2_wmv.wmv"),
        ("H.264 AVC.mp4", "available-now_h264-avc_avc1_mp4.mp4"),
        ("H.265 HEVC.mp4", "available-now_h265-hevc_hvc1_mp4.mp4"),
        ("Apple ProRes.mov", "supported-hardware_prores_prores_mov.mov"),
        ("FFV1.avi", "FFV1.mkv"),
        ("HuffYUV.avi", "available-now_huffyuv_huffyuv_avi.avi"),
        ("DVCPro HD.mov", "available-now_dvcpro-hd_dvhq_mov.mov"),
        ("DV.dv", "available-now_dv_dvvideo_dv.dv"),
        ("CineForm.avi", "available-now_cineform_cfhd_mov.mov"),
        ("DNxHD.mov", "available-now_dnxhd_dnxhd_mov.mov"),
        ("V308.mov", "available-now_v308_v308_mov.mov"),
        ("V210.avi", "available-now_v210_v210_mov.mov"),
        ("V408.mov", "available-now_v408_v408_mov.mov"),
        ("V410.mov", "available-now_v410_v410_mov.mov"),
        ("YUV4.mov", "available-now_yuv4_yuv4_mov.mov")
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
                    "migrated": "\(result.migratedFilenames.count)",
                    "removedLegacy": "\(result.removedLegacyFilenames.count)",
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
        let legacyMigration = try migrateLegacySampleFilenames(
            in: destinationURL,
            fileManager: fileManager
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
            migratedFilenames: legacyMigration.migratedFilenames,
            removedLegacyFilenames: legacyMigration.removedLegacyFilenames,
            copiedFilenames: copiedFilenames,
            skippedFilenames: skippedFilenames
        )
    }

    private static func migrateLegacySampleFilenames(
        in destinationURL: URL,
        fileManager: FileManager
    ) throws -> (migratedFilenames: [String], removedLegacyFilenames: [String]) {
        var migratedFilenames: [String] = []
        var removedLegacyFilenames: [String] = []

        for pair in legacyVideoSampleFilenamePairs {
            let currentURL = destinationURL.appendingPathComponent(pair.current, isDirectory: false)
            let legacyURL = destinationURL.appendingPathComponent(pair.legacy, isDirectory: false)
            guard fileManager.fileExists(atPath: legacyURL.path) else {
                continue
            }

            if fileManager.fileExists(atPath: currentURL.path) {
                try fileManager.removeItem(at: legacyURL)
                removedLegacyFilenames.append(pair.legacy)
            } else {
                try fileManager.moveItem(at: legacyURL, to: currentURL)
                migratedFilenames.append(pair.current)
            }
        }

        return (migratedFilenames, removedLegacyFilenames)
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
