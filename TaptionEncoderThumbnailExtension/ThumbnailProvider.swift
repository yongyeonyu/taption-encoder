import AVFoundation
import QuickLookThumbnailing
import UIKit

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let sourceURL = request.fileURL
        guard TaptionThumbnailSupport.isSupportedVideo(sourceURL) else {
            handler(nil, TaptionThumbnailError.unsupportedType(sourceURL))
            return
        }

        let targetSize = TaptionThumbnailSupport.targetSize(for: request)
        let targetScale = max(request.scale, 1)

        if let sampleImage = SampleThumbnailCatalog.image(
            for: sourceURL,
            size: targetSize,
            scale: targetScale
        ) {
            handler(TaptionThumbnailSupport.reply(for: sampleImage, sourceURL: sourceURL, size: targetSize), nil)
            return
        }

        if TaptionThumbnailSupport.canRenderFrameWithAVFoundation(sourceURL) {
            TaptionThumbnailSupport.avFoundationImage(
                for: sourceURL,
                size: targetSize,
                scale: targetScale
            ) { image in
                handler(
                    TaptionThumbnailSupport.reply(
                        for: image ?? TaptionThumbnailSupport.supportedVideoImage(
                            for: sourceURL,
                            size: targetSize,
                            scale: targetScale
                        ),
                        sourceURL: sourceURL,
                        size: targetSize
                    ),
                    nil
                )
            }
            return
        }

        let image = TaptionThumbnailSupport.supportedVideoImage(
            for: sourceURL,
            size: targetSize,
            scale: targetScale
        )
        handler(TaptionThumbnailSupport.reply(for: image, sourceURL: sourceURL, size: targetSize), nil)
    }
}

private enum TaptionThumbnailSupport {
    private static let standardVideoExtensions: Set<String> = [
        "3g2",
        "3gp",
        "3gpp",
        "3gpp2",
        "m4v",
        "mov",
        "mp4",
        "qt"
    ]

    private static let legacyVideoExtensions: Set<String> = [
        "264",
        "265",
        "asf",
        "av1",
        "avi",
        "dat",
        "dif",
        "divx",
        "dv",
        "dvr-ms",
        "f4v",
        "flv",
        "h261",
        "h263",
        "h264",
        "h265",
        "hevc",
        "ivf",
        "m1v",
        "m2v",
        "mkv",
        "mod",
        "mpe",
        "mpeg",
        "mpg",
        "mxf",
        "obu",
        "ogg",
        "ogm",
        "ogv",
        "rm",
        "rmvb",
        "roq",
        "vc1",
        "vob",
        "webm",
        "wmv",
        "y4m"
    ]

    private static let avFoundationFrameExtensions = standardVideoExtensions

    static func isSupportedVideo(_ url: URL) -> Bool {
        supportedExtensions.contains(normalizedExtension(for: url))
    }

    static func targetSize(for request: QLFileThumbnailRequest) -> CGSize {
        CGSize(
            width: max(request.maximumSize.width, request.minimumSize.width, 96),
            height: max(request.maximumSize.height, request.minimumSize.height, 96)
        )
    }

    static func canRenderFrameWithAVFoundation(_ url: URL) -> Bool {
        avFoundationFrameExtensions.contains(normalizedExtension(for: url))
    }

    static func avFoundationImage(
        for url: URL,
        size: CGSize,
        scale: CGFloat,
        completion: @escaping (UIImage?) -> Void
    ) {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.apertureMode = .encodedPixels
        generator.maximumSize = CGSize(width: size.width * scale, height: size.height * scale)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.8, preferredTimescale: 600)

        let requestedTime = NSValue(time: CMTime(seconds: 0.2, preferredTimescale: 600))
        generator.generateCGImagesAsynchronously(forTimes: [requestedTime]) { _, cgImage, _, result, _ in
            guard result == .succeeded,
                  let cgImage else {
                completion(nil)
                return
            }
            completion(renderFrameImage(cgImage, size: size, scale: scale))
        }
    }

    static func reply(for image: UIImage, sourceURL: URL, size: CGSize) -> QLThumbnailReply {
        let reply = QLThumbnailReply(contextSize: size) {
            image.draw(in: CGRect(origin: .zero, size: size))
            return true
        }

        if #available(iOS 15.0, *) {
            reply.extensionBadge = badgeText(for: sourceURL)
        }

        return reply
    }

    static func supportedVideoImage(for url: URL, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1).setFill()
            context.fill(rect)

            let inset = max(min(size.width, size.height) * 0.08, 6)
            let posterRect = rect.insetBy(dx: inset, dy: inset)
            let posterPath = UIBezierPath(roundedRect: posterRect, cornerRadius: max(inset * 0.52, 6))
            UIColor(red: 0.12, green: 0.17, blue: 0.24, alpha: 1).setFill()
            posterPath.fill()

            UIColor.white.withAlphaComponent(0.12).setStroke()
            posterPath.lineWidth = max(size.width * 0.01, 1)
            posterPath.stroke()

            drawFilmTicks(in: posterRect, tickWidth: max(size.width * 0.045, 4))
            drawPlayGlyph(in: posterRect)
            drawCodecLabel(badgeText(for: url), in: posterRect)
        }
    }

    static func badgeText(for url: URL) -> String {
        let normalizedExtension = normalizedExtension(for: url)
        switch normalizedExtension {
        case "264", "h264":
            return "H.264"
        case "265", "h265", "hevc":
            return "HEVC"
        case "ivf", "obu", "av1":
            return "AV1"
        case "m1v":
            return "M1V"
        case "m2v":
            return "M2V"
        case "3gp", "3gpp":
            return "3GP"
        case "3g2", "3gpp2":
            return "3G2"
        case "dvr-ms":
            return "DVR"
        default:
            let fallback = normalizedExtension.uppercased()
            return fallback.isEmpty ? "VIDEO" : String(fallback.prefix(6))
        }
    }

    private static var supportedExtensions: Set<String> {
        standardVideoExtensions.union(legacyVideoExtensions)
    }

    private static func normalizedExtension(for url: URL) -> String {
        url.pathExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    }

    private static func renderFrameImage(_ cgImage: CGImage, size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.black.setFill()
            context.fill(rect)

            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            let drawRect = aspectFillRect(imageSize: imageSize, in: rect)
            UIImage(cgImage: cgImage).draw(in: drawRect)
        }
    }

    private static func aspectFillRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return bounds
        }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: bounds.midX - width / 2,
            y: bounds.midY - height / 2,
            width: width,
            height: height
        )
    }

    private static func drawFilmTicks(in rect: CGRect, tickWidth: CGFloat) {
        UIColor.black.withAlphaComponent(0.24).setFill()
        let tickCount = 4
        let tickHeight = rect.height / CGFloat(tickCount * 2 + 1)

        for index in 0..<tickCount {
            let y = rect.minY + tickHeight * CGFloat(index * 2 + 1)
            UIBezierPath(
                roundedRect: CGRect(x: rect.minX + tickWidth * 0.45, y: y, width: tickWidth, height: tickHeight),
                cornerRadius: tickWidth * 0.2
            ).fill()
            UIBezierPath(
                roundedRect: CGRect(x: rect.maxX - tickWidth * 1.45, y: y, width: tickWidth, height: tickHeight),
                cornerRadius: tickWidth * 0.2
            ).fill()
        }
    }

    private static func drawPlayGlyph(in rect: CGRect) {
        let diameter = min(rect.width, rect.height) * 0.36
        let circleRect = CGRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2 - rect.height * 0.06,
            width: diameter,
            height: diameter
        )

        UIColor.white.withAlphaComponent(0.18).setFill()
        UIBezierPath(ovalIn: circleRect).fill()

        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: circleRect.midX - diameter * 0.11, y: circleRect.midY - diameter * 0.2))
        triangle.addLine(to: CGPoint(x: circleRect.midX - diameter * 0.11, y: circleRect.midY + diameter * 0.2))
        triangle.addLine(to: CGPoint(x: circleRect.midX + diameter * 0.22, y: circleRect.midY))
        triangle.close()
        UIColor.white.withAlphaComponent(0.88).setFill()
        triangle.fill()
    }

    private static func drawCodecLabel(_ label: String, in rect: CGRect) {
        let fontSize = max(min(rect.height * 0.14, rect.width * 0.14), 10)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: UIColor.white.withAlphaComponent(0.88),
            .paragraphStyle: paragraph
        ]

        let textHeight = fontSize * 1.35
        let textRect = CGRect(
            x: rect.minX + rect.width * 0.16,
            y: rect.maxY - textHeight - rect.height * 0.12,
            width: rect.width * 0.68,
            height: textHeight
        )
        label.draw(with: textRect, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
    }
}

private enum TaptionThumbnailError {
    static func unsupportedType(_ url: URL) -> NSError {
        NSError(
            domain: "com.taption.encoder.thumbnail",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Unsupported thumbnail type: \(url.lastPathComponent)"
            ]
        )
    }
}
