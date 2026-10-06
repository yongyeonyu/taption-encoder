import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Deterministic, non-bundled artwork maintenance. Original PNGs are read-only.
struct Region: Codable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var right: Int { x + width }
    var bottom: Int { y + height }
    func padded(_ amount: Int) -> Region {
        Region(x: x - amount, y: y - amount,
               width: width + amount * 2, height: height + amount * 2)
    }
    func contains(_ px: Int, _ py: Int) -> Bool {
        px >= x && px < right && py >= y && py < bottom
    }
}
struct Match: Decodable { let kind: String; let x: Int; let y: Int; let width: Int; let height: Int
    var region: Region { Region(x: x, y: y, width: width, height: height) }
}
struct Artwork: Decodable {
    let locale: String; let group: String; let fileName: String
    let originalPath: String; let updatedPath: String
    let width: Int; let height: Int; let matches: [Match]
}
struct Inventory: Decodable { let taskId: String; let count: Int; let images: [Artwork] }
struct PixelCanvas {
    let width: Int
    let height: Int
    let colorSpace: CGColorSpace
    var bytes: [UInt8]
    init(image: CGImage) throws {
        width = image.width; height = image.height
        colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let w = width, h = height, space = colorSpace
        bytes = Array(repeating: 0, count: w * h * 4)
        try bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw failure("Cannot decode image") }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard stride(from: 3, to: bytes.count, by: 4).allSatisfy({ bytes[$0] == 255 })
        else { throw failure("Original image is not opaque") }
    }
    init(path: String) throws {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw failure("Cannot open PNG: \(path)") }
        try self.init(image: image)
    }
    func pixel(_ x: Int, _ y: Int) -> [UInt8] {
        Array(bytes[((y * width + x) * 4)..<((y * width + x) * 4 + 4)])
    }
    mutating func setPixel(_ x: Int, _ y: Int, _ color: [UInt8]) {
        let start = (y * width + x) * 4
        for c in 0..<4 { bytes[start + c] = color[c] }
    }
    func check(_ region: Region) throws {
        guard region.x >= 0 && region.y >= 0 && region.right <= width && region.bottom <= height
        else { throw failure("Out-of-bounds region \(region)") }
    }
    mutating func fill(_ region: Region, _ color: [UInt8]) throws {
        try check(region)
        for y in region.y..<region.bottom { for x in region.x..<region.right { setPixel(x, y, color) } }
    }
    func image() throws -> CGImage {
        // RGBX avoids an alpha channel in the delivered App Store PNG.
        let data = Data(bytes) as CFData
        guard let provider = CGDataProvider(data: data),
              let result = CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw failure("Cannot construct image") }
        return result
    }
    mutating func draw(line: CTLine, x: CGFloat, baselineFromTop: CGFloat, clip: Region) throws {
        let w = width, h = height, space = colorSpace
        try bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw failure("Cannot draw text") }
            context.clip(to: CGRect(x: clip.x, y: h - clip.bottom, width: clip.width, height: clip.height))
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: x, y: CGFloat(h) - baselineFromTop)
            context.setShouldAntialias(true)
            CTLineDraw(line, context)
        }
    }
    func save(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw failure("Cannot create PNG") }
        CGImageDestinationAddImage(dest, try image(), nil)
        guard CGImageDestinationFinalize(dest) else { throw failure("Cannot finalize PNG") }
    }
}
func failure(_ message: String) -> NSError { NSError(domain: "PreciseArtwork", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
func textLine(_ text: String, size: CGFloat, color: CGColor) -> CTLine {
    let font = NSFont.systemFont(ofSize: size, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font.fontName as CFString, size, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
    ]
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
}
func restoreMarketingBackground(original: PixelCanvas, edited: inout PixelCanvas, region: Region) throws {
    try original.check(region.padded(1))
    // The wordmark lies on an unobstructed, smoothly varying background.
    for y in region.y..<region.bottom {
        let left = original.pixel(region.x - 1, y), right = original.pixel(region.right, y)
        guard zip(left.prefix(3), right.prefix(3)).allSatisfy({ abs(Int($0) - Int($1)) <= 8 })
        else { throw failure("Wordmark background is not smooth") }
        for x in region.x..<region.right {
            let t = Double(x - region.x + 1) / Double(region.width + 1)
            let color = (0..<3).map { UInt8((Double(left[$0]) * (1 - t) + Double(right[$0]) * t).rounded()) } + [255]
            edited.setPixel(x, y, color)
        }
    }
}
func homeRemovalRegions(reference original: PixelCanvas, title: Region) throws -> [Region] {
    let middleY = title.y + title.height / 2
    let background = original.pixel(title.right + 20, middleY)
    // Locate the original icon, then the unchanged Menu/star controls by their
    // mid-row outlines. No recreation of control pixels is involved.
    var iconRight = title.x - 8
    while iconRight > 0 && original.pixel(iconRight, middleY) == background { iconRight -= 1 }
    var iconLeft = iconRight
    while iconLeft > 0 && original.pixel(iconLeft - 1, middleY) != background { iconLeft -= 1 }
    let iconMiddleX = (iconLeft + iconRight) / 2
    var iconTop = middleY, iconBottom = middleY
    while iconTop > 0 && original.pixel(iconMiddleX, iconTop - 1) != background { iconTop -= 1 }
    while iconBottom < original.height - 1 && original.pixel(iconMiddleX, iconBottom + 1) != background { iconBottom += 1 }
    let icon = Region(x: iconLeft, y: iconTop, width: iconRight - iconLeft + 1, height: iconBottom - iconTop + 1).padded(2)
    guard (40...120).contains(icon.width) && abs(icon.height - icon.width) <= 6
    else { throw failure("Unexpected home icon geometry: \(icon)") }
    var menuRight = iconLeft - 10
    while menuRight > 0 && original.pixel(menuRight, middleY) == background { menuRight -= 1 }
    var starLeft = title.right + 10
    while starLeft < original.width - 1 && original.pixel(starLeft, middleY) == background { starLeft += 1 }
    guard menuRight < iconLeft - 10 && starLeft > title.right + 10 else { throw failure("Cannot locate controls") }
    let center = Double(menuRight + 1 + starLeft) / 2
    let moved = Region(x: Int((center - Double(icon.width) / 2).rounded()), y: icon.y,
                       width: icon.width, height: icon.height)
    let removedTitle = title.padded(4)
    try original.check(icon); try original.check(moved); try original.check(removedTitle)
    return [removedTitle, icon, moved]
}
func restoreHeaderBackground(original: PixelCanvas, edited: inout PixelCanvas, region: Region) throws {
    try original.check(region.padded(1))
    // Sheet dimming can quantize a subtle vertical background gradient. Keep
    // each row's actual background instead of extending one sampled color.
    for y in region.y..<region.bottom {
        let left = original.pixel(region.x - 1, y), right = original.pixel(region.right, y)
        guard zip(left.prefix(3), right.prefix(3)).allSatisfy({ abs(Int($0) - Int($1)) <= 3 })
        else { throw failure("Header edit crosses non-background content") }
        for x in region.x..<region.right {
            let t = Double(x - region.x + 1) / Double(region.width + 1)
            let color = (0..<3).map { UInt8((Double(left[$0]) * (1 - t) + Double(right[$0]) * t).rounded()) } + [255]
            edited.setPixel(x, y, color)
        }
    }
}
func removeHomeTitle(original: PixelCanvas, edited: inout PixelCanvas, title: Region,
                     geometryReference: PixelCanvas? = nil) throws -> [Region] {
    let regions = try homeRemovalRegions(reference: geometryReference ?? original, title: title)
    let removedTitle = regions[0], icon = regions[1], moved = regions[2]
    try restoreHeaderBackground(original: original, edited: &edited, region: removedTitle)
    try restoreHeaderBackground(original: original, edited: &edited, region: icon)
    for dy in 0..<icon.height { for dx in 0..<icon.width {
        edited.setPixel(moved.x + dx, moved.y + dy, original.pixel(icon.x + dx, icon.y + dy))
    } }
    for dy in 0..<icon.height { for dx in 0..<icon.width {
        guard edited.pixel(moved.x + dx, moved.y + dy) == original.pixel(icon.x + dx, icon.y + dy)
        else { throw failure("Icon copy mismatch") }
    } }
    return regions
}
func makePreview(_ images: [Artwork], locale: String, root: String) throws {
    let width = 3000, height = 2750
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: space,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw failure("Cannot create preview") }
    ctx.setFillColor(CGColor(red: 0.065, green: 0.075, blue: 0.11, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let groups = ["iphone", "ipad-portrait", "ipad-landscape"]
    let tops = [20, 1350, 2210], imageHeights = [1240, 780, 420]
    for (row, group) in groups.enumerated() {
        let items = images.filter { $0.locale == locale && $0.group == group }.sorted { $0.fileName < $1.fileName }
        guard items.count == 5 else { throw failure("Unexpected preview count") }
        for (column, item) in items.enumerated() {
            let image = try PixelCanvas(path: item.updatedPath).image()
            let scale = min(560 / CGFloat(image.width), CGFloat(imageHeights[row]) / CGFloat(image.height))
            let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
            let x = CGFloat(column * 600) + (600 - w) / 2
            let y = CGFloat(height - tops[row] - 45) - h
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: x, y: y, width: w, height: h))
            let label = textLine("\(locale) · \(group) · \(column + 1)", size: 23,
                                 color: CGColor(gray: 0.94, alpha: 1))
            ctx.textPosition = CGPoint(x: column * 600 + 25, y: height - tops[row] - 28)
            CTLineDraw(label, ctx)
        }
    }
    guard let image = ctx.makeImage() else { throw failure("Cannot finalize preview") }
    try PixelCanvas(image: image).save(root + "/PREVIEW-" + locale + ".png")
}

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
guard !root.isEmpty else { throw failure("Usage: precise_app_store_branding.swift ARTWORK_ROOT") }
let inventory = try JSONDecoder().decode(Inventory.self,
    from: Data(contentsOf: URL(fileURLWithPath: root + "/original-ocr.json")))
guard inventory.taskId == "NAME06Y2K8", inventory.count == 30, inventory.images.count == 30
else { throw failure("Unexpected artwork inventory") }
var reports: [[String: Any]] = []
for item in inventory.images {
    let original = try PixelCanvas(path: item.originalPath)
    guard original.width == item.width && original.height == item.height else { throw failure("Dimension mismatch") }
    var edited = original
    guard let oldBrand = item.matches.first(where: { $0.kind == "marketing" })
    else { throw failure("Marketing brand not found") }
    var brand = oldBrand.region
    // One OCR result joined the adjacent app icon into the word Taption.
    if brand.x < 140 { brand = Region(x: 149, y: 81, width: 263, height: 34) }
    let marketing = brand.padded(6)
    try restoreMarketingBackground(original: original, edited: &edited, region: marketing)
    var colors: [[UInt8]: Int] = [:]
    for y in brand.y..<brand.bottom { for x in brand.x..<brand.right {
        let color = original.pixel(x, y)
        if color.prefix(3).allSatisfy({ $0 > 180 }) { colors[color, default: 0] += 1 }
    } }
    guard let foreground = colors.max(by: { $0.value < $1.value })?.key,
          let color = CGColor(colorSpace: original.colorSpace, components: foreground.map { CGFloat($0) / 255 })
    else { throw failure("Cannot match brand foreground") }
    let sampleLine = textLine("Taption Encoder", size: 40, color: color)
    let sampleBounds = CTLineGetBoundsWithOptions(sampleLine, .useGlyphPathBounds)
    let size = 40 * CGFloat(brand.width) / sampleBounds.width
    let oldLine = textLine("Taption Encoder", size: size, color: color)
    let oldBounds = CTLineGetBoundsWithOptions(oldLine, .useGlyphPathBounds)
    let replacement = textLine("YYY Encoder", size: size, color: color)
    let replacementBounds = CTLineGetBoundsWithOptions(replacement, .useGlyphPathBounds)
    try edited.draw(line: replacement, x: CGFloat(brand.x) - replacementBounds.minX,
        baselineFromTop: CGFloat(brand.bottom) + oldBounds.minY, clip: marketing)
    var allowed = [marketing]
    var homeRegion = item.matches.first(where: { $0.kind == "home" })?.region
    var homeGeometryReference: PixelCanvas?
    // The iPad sheet presentations dim, but do not occlude, the home header.
    // OCR skips this low-contrast title. Use the verified geometry of the
    // same device group's clear home header and sample each image's own dimmed
    // background/icon pixels rather than importing undimmed pixels.
    if homeRegion == nil && item.group.hasPrefix("ipad-") {
        guard item.fileName.hasPrefix("02-") || item.fileName.hasPrefix("05-"),
              let reference = inventory.images.first(where: {
                  $0.locale == item.locale && $0.group == item.group && $0.fileName.hasPrefix("01-")
              }),
              let home = reference.matches.first(where: { $0.kind == "home" })
        else { throw failure("Cannot verify dimmed iPad home geometry") }
        homeRegion = home.region
        homeGeometryReference = try PixelCanvas(path: reference.originalPath)
    }
    if let home = homeRegion {
        allowed += try removeHomeTitle(original: original, edited: &edited, title: home,
                                      geometryReference: homeGeometryReference)
    }
    var changed = 0, outside = 0
    for y in 0..<original.height { for x in 0..<original.width {
        let offset = (y * original.width + x) * 4
        if (0..<4).contains(where: { original.bytes[offset + $0] != edited.bytes[offset + $0] }) {
            changed += 1
            if !allowed.contains(where: { $0.contains(x, y) }) { outside += 1 }
        }
    } }
    guard changed > 0 && outside == 0 else { throw failure("Non-target pixels changed") }
    try edited.save(item.updatedPath)
    let roundtrip = try PixelCanvas(path: item.updatedPath)
    guard roundtrip.width == item.width && roundtrip.height == item.height && roundtrip.bytes == edited.bytes
    else { throw failure("PNG lossless roundtrip failed") }
    let headerImage = try edited.image().cropping(to: CGRect(x: marketing.x, y: marketing.y,
        width: marketing.width, height: marketing.height))!
    try PixelCanvas(image: headerImage).save(root + "/qa-headers/\(item.locale)-\(item.group)-\(item.fileName)")
    let encoded = try JSONEncoder().encode(allowed)
    reports.append(["locale": item.locale, "group": item.group, "fileName": item.fileName,
        "originalPath": item.originalPath, "updatedPath": item.updatedPath,
        "width": item.width, "height": item.height, "changedPixels": changed,
        "outsideAllowedRegionsChangedPixels": outside, "losslessRoundtrip": true,
        "homeTitleRemoved": homeRegion != nil,
        "matchedFontSize": Double(size), "replacementText": "YYY Encoder",
        "allowedRegions": try JSONSerialization.jsonObject(with: encoded)])
    print("PASS \(item.locale)/\(item.group)/\(item.fileName): changed=\(changed), outside=\(outside)")
}
for locale in ["ko", "en-US"] { try makePreview(inventory.images, locale: locale, root: root) }
let report: [String: Any] = ["taskId": inventory.taskId, "totalImages": reports.count,
    "method": "CoreGraphics/CoreText deterministic region edits, owner-authorized",
    "originalsUnmodified": true, "allOutsideTargetPixelsUnchanged": true, "images": reports]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: root + "/precision-qa.json"))
print("Completed 30 PNGs and two localized preview contact sheets.")
