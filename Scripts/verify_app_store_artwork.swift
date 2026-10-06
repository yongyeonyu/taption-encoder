import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Vision

struct Box: Decodable {
    let x: Int; let y: Int; let width: Int; let height: Int
    func contains(_ px: Int, _ py: Int) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }
}
struct Entry: Decodable {
    let locale: String; let group: String; let fileName: String
    let originalPath: String; let updatedPath: String
    let width: Int; let height: Int; let allowedRegions: [Box]
    let homeTitleRemoved: Bool
}
struct Report: Decodable { let taskId: String; let images: [Entry] }
struct Baseline: Decodable {
    struct File: Decodable { let originalPath: String; let sha256: String }
    let files: [File]
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "ArtworkQA", code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]) }
}
func decode(_ path: String) throws -> (CGImage, [UInt8]) {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          CGImageSourceGetStatus(source) == .statusComplete,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw NSError(domain: "ArtworkQA", code: 2) }
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    pixels.withUnsafeMutableBytes { raw in
        let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: image.colorSpace!,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return (image, pixels)
}
func recognize(_ image: CGImage) throws -> [[String: Any]] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US", "ko-KR"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first else { return nil }
        return ["text": text.string, "confidence": text.confidence,
                "box": [observation.boundingBox.minX, observation.boundingBox.minY,
                        observation.boundingBox.width, observation.boundingBox.height]]
    }
}
let root = CommandLine.arguments[1]
let report = try JSONDecoder().decode(Report.self, from: Data(contentsOf:
    URL(fileURLWithPath: root + "/precision-qa.json")))
let baseline = try JSONDecoder().decode(Baseline.self, from: Data(contentsOf:
    URL(fileURLWithPath: root + "/original-file-checksums.json")))
let originalHashes = Dictionary(uniqueKeysWithValues: baseline.files.map { ($0.originalPath, $0.sha256) })
try require(report.taskId == "NAME06Y2K8" && report.images.count == 30, "Wrong inventory")
try require(report.images.filter(\.homeTitleRemoved).count == 26, "Missing clear/dimmed home edits")
var rows: [[String: Any]] = []
for item in report.images {
    let beforeData = try Data(contentsOf: URL(fileURLWithPath: item.originalPath))
    let beforeSHA = SHA256.hash(data: beforeData).map { String(format: "%02x", $0) }.joined()
    try require(beforeSHA == originalHashes[item.originalPath], "Original was changed")
    let afterData = try Data(contentsOf: URL(fileURLWithPath: item.updatedPath))
    try require(afterData.count > 26 && afterData[24] == 8 && afterData[25] == 2, "Not 8-bit RGB PNG")
    let (before, beforePixels) = try decode(item.originalPath)
    let (after, afterPixels) = try decode(item.updatedPath)
    try require(before.width == item.width && after.width == item.width &&
                before.height == item.height && after.height == item.height, "Wrong dimensions")
    var outside = 0
    for y in 0..<item.height { for x in 0..<item.width {
        let i = (y * item.width + x) * 4
        if beforePixels[i] != afterPixels[i] || beforePixels[i + 1] != afterPixels[i + 1] ||
           beforePixels[i + 2] != afterPixels[i + 2] || beforePixels[i + 3] != afterPixels[i + 3] {
            if !item.allowedRegions.contains(where: { $0.contains(x, y) }) { outside += 1 }
        }
    } }
    try require(outside == 0, "Independent non-target pixel comparison failed")
    let brand = item.allowedRegions[0]
    let crop = after.cropping(to: CGRect(x: brand.x, y: brand.y, width: brand.width, height: brand.height))!
    let brandOCR = try recognize(crop)
    let normalized = brandOCR.map { $0["text"] as! String }.joined().uppercased()
        .filter { $0.isLetter || $0.isNumber }
    try require(normalized == "YYYENCODER", "Incorrect wordmark OCR: \(normalized)")
    let allOCR = try recognize(after)
    let residual = allOCR.filter { ($0["text"] as! String).lowercased().contains("taption") }
    try require(residual.isEmpty, "Old name remains in OCR")
    let digest = SHA256.hash(data: afterData).map { String(format: "%02x", $0) }.joined()
    let md5 = Insecure.MD5.hash(data: afterData).map { String(format: "%02x", $0) }.joined()
    rows.append(["locale": item.locale, "group": item.group, "fileName": item.fileName,
        "path": item.updatedPath, "bytes": afterData.count, "width": after.width, "height": after.height,
        "sha256": digest, "md5": md5, "originalSHA256Unchanged": true,
        "outsideAllowedRegionsChangedPixels": outside, "pngRGBNoAlpha": true,
        "homeTitleRemoved": item.homeTitleRemoved, "wordmarkOCR": brandOCR,
        "residualOldNameOCR": residual, "fullOCR": allOCR])
    print("PASS \(item.locale)/\(item.group)/\(item.fileName): YYY Encoder / outside=0 / original SHA unchanged")
    fflush(stdout)
}
let output: [String: Any] = ["taskId": report.taskId, "totalImages": rows.count,
    "homeTitlesRemoved": 26, "independentPixelAndOCRQAPassed": true,
    "verifiedAt": ISO8601DateFormatter().string(from: Date()), "images": rows]
try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: root + "/final-artwork-qa.json"))
