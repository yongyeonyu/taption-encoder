import Foundation
import UIKit

enum SampleThumbnailCatalog {
    private struct Entry {
        let bytes: Int
        let resourceName: String
    }

    static let resourceSubdirectory = "SampleThumbnails"

    private static let entries: [String: Entry] = [
        "ASUS V1.avi": Entry(bytes: 305498, resourceName: "sample-thumbnail-asus_v1_avi"),
        "ASUS V2.avi": Entry(bytes: 167114, resourceName: "sample-thumbnail-asus_v2_avi"),
        "AV1.mp4": Entry(bytes: 64444, resourceName: "sample-thumbnail-av1_mp4"),
        "AMR-WB H.263.3gp": Entry(bytes: 258024, resourceName: "sample-thumbnail-amr_wb_h_263_3gp"),
        "Apple Animation.mov": Entry(bytes: 377122, resourceName: "sample-thumbnail-apple_animation_mov"),
        "Apple ProRes.mov": Entry(bytes: 41288, resourceName: "sample-thumbnail-apple_prores_mov"),
        "CLJR.avi": Entry(bytes: 996046, resourceName: "sample-thumbnail-cljr_avi"),
        "CineForm.avi": Entry(bytes: 204496, resourceName: "sample-thumbnail-cineform_avi"),
        "Cinepak.mov": Entry(bytes: 138880, resourceName: "sample-thumbnail-cinepak_mov"),
        "DNxHD.mov": Entry(bytes: 227790, resourceName: "sample-thumbnail-dnxhd_mov"),
        "DVCPro.mov": Entry(bytes: 6961725, resourceName: "sample-thumbnail-dvcpro_mov"),
        "DV.dv": Entry(bytes: 18000000, resourceName: "sample-thumbnail-dv_dv"),
        "DVCPro HD.mov": Entry(bytes: 7223581, resourceName: "sample-thumbnail-dvcpro_hd_mov"),
        "FFV1.avi": Entry(bytes: 202986, resourceName: "sample-thumbnail-ffv1_avi"),
        "Flash Screen Video 2.flv": Entry(bytes: 180359, resourceName: "sample-thumbnail-flash_screen_video_2_flv"),
        "Flash Screen Video.flv": Entry(bytes: 133523, resourceName: "sample-thumbnail-flash_screen_video_flv"),
        "Flash Video.flv": Entry(bytes: 48591, resourceName: "sample-thumbnail-flash_video_flv"),
        "H.261.h261": Entry(bytes: 99234, resourceName: "sample-thumbnail-h_261_h261"),
        "H.263.3gp": Entry(bytes: 44696, resourceName: "sample-thumbnail-h_263_3gp"),
        "H.264 AVC.mp4": Entry(bytes: 106091, resourceName: "sample-thumbnail-h_264_avc_mp4"),
        "H.265 HEVC.mp4": Entry(bytes: 58183, resourceName: "sample-thumbnail-h_265_hevc_mp4"),
        "HuffYUV.avi": Entry(bytes: 177770, resourceName: "sample-thumbnail-huffyuv_avi"),
        "JPEG 2000.mov": Entry(bytes: 158388, resourceName: "sample-thumbnail-jpeg_2000_mov"),
        "JPEG-LS.avi": Entry(bytes: 99796, resourceName: "sample-thumbnail-jpeg_ls_avi"),
        "Lossless JPEG.avi": Entry(bytes: 296958, resourceName: "sample-thumbnail-lossless_jpeg_avi"),
        "MPEG-1.mpg": Entry(bytes: 436224, resourceName: "sample-thumbnail-mpeg_1_mpg"),
        "MPEG-2.mpg": Entry(bytes: 104448, resourceName: "sample-thumbnail-mpeg_2_mpg"),
        "MPEG-4 Visual.mov": Entry(bytes: 43719, resourceName: "sample-thumbnail-mpeg_4_visual_mov"),
        "MagicYUV.avi": Entry(bytes: 218268, resourceName: "sample-thumbnail-magicyuv_avi"),
        "Microsoft MPEG-4 V2.avi": Entry(bytes: 159504, resourceName: "sample-thumbnail-microsoft_mpeg_4_v2_avi"),
        "Microsoft MPEG-4 V3.wmv": Entry(bytes: 49185, resourceName: "sample-thumbnail-microsoft_mpeg_4_v3_wmv"),
        "Microsoft RLE.avi": Entry(bytes: 52806, resourceName: "sample-thumbnail-microsoft_rle_avi"),
        "Microsoft Video 1.avi": Entry(bytes: 119770, resourceName: "sample-thumbnail-microsoft_video_1_avi"),
        "Motion JPEG.avi": Entry(bytes: 67760, resourceName: "sample-thumbnail-motion_jpeg_avi"),
        "PNG Video.avi": Entry(bytes: 324004, resourceName: "sample-thumbnail-png_video_avi"),
        "QuickTime Graphics.mov": Entry(bytes: 375564, resourceName: "sample-thumbnail-quicktime_graphics_mov"),
        "QuickTime Video.mov": Entry(bytes: 107816, resourceName: "sample-thumbnail-quicktime_video_mov"),
        "R10K.mov": Entry(bytes: 93635, resourceName: "sample-thumbnail-r10k_mov"),
        "R210.avi": Entry(bytes: 145276, resourceName: "sample-thumbnail-r210_avi"),
        "Raw Video.avi": Entry(bytes: 80764, resourceName: "sample-thumbnail-raw_video_avi"),
        "RealVideo 1.0.rm": Entry(bytes: 171868, resourceName: "sample-thumbnail-realvideo_1_0_rm"),
        "RealVideo.rm": Entry(bytes: 270815, resourceName: "sample-thumbnail-realvideo_rm"),
        "RoQ Video.roq": Entry(bytes: 528214, resourceName: "sample-thumbnail-roq_video_roq"),
        "Snow.avi": Entry(bytes: 153678, resourceName: "sample-thumbnail-snow_avi"),
        "Sorenson Video 3.mov": Entry(bytes: 346711, resourceName: "sample-thumbnail-sorenson_video_3_mov"),
        "Sorenson Video.mov": Entry(bytes: 71280, resourceName: "sample-thumbnail-sorenson_video_mov"),
        "Theora.ogv": Entry(bytes: 399262, resourceName: "sample-thumbnail-theora_ogv"),
        "Ut Video.avi": Entry(bytes: 215276, resourceName: "sample-thumbnail-ut_video_avi"),
        "V210.avi": Entry(bytes: 366940, resourceName: "sample-thumbnail-v210_avi"),
        "V308.mov": Entry(bytes: 382934, resourceName: "sample-thumbnail-v308_mov"),
        "V408.mov": Entry(bytes: 502934, resourceName: "sample-thumbnail-v408_mov"),
        "V410.mov": Entry(bytes: 502934, resourceName: "sample-thumbnail-v410_mov"),
        "VP8.webm": Entry(bytes: 189300, resourceName: "sample-thumbnail-vp8_webm"),
        "VP9.webm": Entry(bytes: 97601, resourceName: "sample-thumbnail-vp9_webm"),
        "Windows Media Video.wmv": Entry(bytes: 29609, resourceName: "sample-thumbnail-windows_media_video_wmv"),
        "YUV4.mov": Entry(bytes: 202876, resourceName: "sample-thumbnail-yuv4_mov"),
        "ZMBV.avi": Entry(bytes: 64858, resourceName: "sample-thumbnail-zmbv_avi")
    ]

    static var expectedSampleFilenames: Set<String> {
        Set(entries.keys)
    }

    static func resourceName(for url: URL) -> String? {
        guard let entry = matchingEntry(for: url) else {
            return nil
        }
        return entry.resourceName
    }

    static func image(for url: URL, in bundle: Bundle = .main) -> UIImage? {
        guard let entry = matchingEntry(for: url),
              let resourceURL = bundle.url(
                  forResource: entry.resourceName,
                  withExtension: "png",
                  subdirectory: resourceSubdirectory
              ) else {
            return nil
        }
        return UIImage(contentsOfFile: resourceURL.path)
    }

    static func image(for url: URL, in bundle: Bundle = .main, size: CGSize, scale: CGFloat) -> UIImage? {
        guard let image = image(for: url, in: bundle) else {
            return nil
        }
        return renderAspectFill(image: image, size: size, scale: scale)
    }

    private static func matchingEntry(for url: URL) -> Entry? {
        guard let entry = entries[url.lastPathComponent],
              fileSize(for: url) == entry.bytes else {
            return nil
        }
        return entry
    }

    private static func fileSize(for url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else {
            return nil
        }
        return values.fileSize
    }

    private static func renderAspectFill(image: UIImage, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(scale, 1)
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.black.setFill()
            context.fill(rect)

            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else {
                return
            }

            let drawScale = max(rect.width / imageSize.width, rect.height / imageSize.height)
            let drawSize = CGSize(width: imageSize.width * drawScale, height: imageSize.height * drawScale)
            let drawRect = CGRect(
                x: rect.midX - drawSize.width / 2,
                y: rect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            image.draw(in: drawRect)
        }
    }
}
