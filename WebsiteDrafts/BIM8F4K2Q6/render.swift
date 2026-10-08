import AppKit
import CoreGraphics
import Foundation
import ImageIO

// Rebuild with: swift render.swift
// Editable copy, colors, geometry, and crop are in layout.json.
// Actual release UI is always read from the unmodified SourceAssets PNGs.

let base = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let config = try JSONSerialization.jsonObject(with: Data(contentsOf: base.appendingPathComponent("layout.json"))) as! [String: Any]
let panels = config["panels"] as! [[String: Any]]
let screen = config["screen"] as! [String: Any]
let cropConfig = screen["sourceRect"] as! [String: NSNumber]
let targetConfig = screen["targetRect"] as! [String: NSNumber]
let positions = config["textPositions"] as! [String: Any]
let output = base.appendingPathComponent("Finished")
let editable = base.appendingPathComponent("Editable")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: editable, withIntermediateDirectories: true)

func rectangle(_ d: [String: NSNumber]) -> CGRect {
    CGRect(x: d["x"]!.doubleValue, y: d["y"]!.doubleValue, width: d["width"]!.doubleValue, height: d["height"]!.doubleValue)
}
let sourceRect = rectangle(cropConfig)
let device = rectangle(targetConfig)

func color(_ hex: String) -> NSColor {
    let raw = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((raw >> 16) & 255) / 255, green: CGFloat((raw >> 8) & 255) / 255, blue: CGFloat(raw & 255) / 255, alpha: 1)
}
func fill(_ rect: CGRect, _ shade: NSColor, radius: CGFloat = 0) {
    shade.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
func text(_ string: String, x: CGFloat, y: CGFloat, size: CGFloat, shade: NSColor, bold: Bool = false) {
    let font = NSFont(name: bold ? "HelveticaNeue-Bold" : "HelveticaNeue", size: size)!
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: shade]
    let measured = (string as NSString).size(withAttributes: attributes)
    precondition(x + measured.width <= 1110 || size < 45, "Headline exceeds safe width: \(string)")
    (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
}

func drawPanel(_ panel: [String: Any]) throws {
    let foreground = color(panel["foreground"] as! String)
    let secondary = color(panel["secondary"] as! String)
    let accent = color(panel["accent"] as! String)
    let background = color(panel["background"] as! String)
    fill(CGRect(x: 0, y: 0, width: 1206, height: 2622), background)

    // Quiet geometric backdrop; outside the unchanged app UI.
    color(panel["halo"] as! String).setFill()
    NSBezierPath(ovalIn: CGRect(x: 420, y: 968, width: 1300, height: 1460)).fill()
    color(panel["halo"] as! String).withAlphaComponent(0.48).setFill()
    NSBezierPath(ovalIn: CGRect(x: -620, y: 1840, width: 1260, height: 1220)).fill()

    text("Bokki Encoder", x: 96, y: 95, size: 43, shade: foreground, bold: true)
    fill(CGRect(x: 1012, y: 91, width: 98, height: 67), accent, radius: 33)
    text(String((panel["id"] as! String).prefix(2)), x: 1042, y: 101, size: 31, shade: color("#103E31"), bold: true)
    text(panel["eyebrow"] as! String, x: 96, y: 221, size: 26, shade: secondary, bold: true)
    let headline = panel["headline"] as! [String]
    text(headline[0], x: 89, y: 292, size: 138, shade: foreground, bold: true)
    text(headline[1], x: 89, y: 444, size: 138, shade: panel["id"] as! String == "02-hevc-output" ? accent : foreground, bold: true)
    let caption = panel["caption"] as! [String]
    text(caption[0], x: 96, y: 630, size: 43, shade: secondary)
    text(caption[1], x: 96, y: 688, size: 43, shade: secondary)

    let badges = panel["badges"] as! [String]
    var badgeX: CGFloat = 96
    for badge in badges {
        text(badge, x: badgeX, y: 776, size: 29, shade: foreground, bold: true)
        let width = (badge as NSString).size(withAttributes: [.font: NSFont(name: "HelveticaNeue-Bold", size: 29)!]).width
        badgeX += width + 47
        if badge != badges.last! {
            fill(CGRect(x: badgeX - 27, y: 790, width: 7, height: 7), accent, radius: 3.5)
        }
    }

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.23)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: 15)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    fill(device.insetBy(dx: -12, dy: -12), color("#17251F"), radius: 83)
    NSGraphicsContext.restoreGraphicsState()
    fill(device.insetBy(dx: -5, dy: -5), color("#55635A"), radius: 75)

    let sourceURL = base.appendingPathComponent(panel["source"] as! String)
    let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)!
    let cg = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
    precondition(cg.width == 1242 && cg.height == 2688)
    let actualUICrop = cg.cropping(to: sourceRect)!
    let cropProof = base.appendingPathComponent("Evidence/UI-crop-\(panel["id"] as! String).png")
    let proofDestination = CGImageDestinationCreateWithURL(cropProof as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(proofDestination, actualUICrop, nil)
    precondition(CGImageDestinationFinalize(proofDestination))
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: device, xRadius: 68, yRadius: 68).addClip()
    let imageContext = NSGraphicsContext.current!.cgContext
    imageContext.interpolationQuality = .high
    imageContext.translateBy(x: device.minX, y: device.maxY)
    imageContext.scaleBy(x: 1, y: -1)
    imageContext.draw(actualUICrop, in: CGRect(x: 0, y: 0, width: device.width, height: device.height))
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ panel: [String: Any], width: Int, height: Int, suffix: String) throws {
    // RGB, without alpha; directly writes an opaque App Store-compatible image.
    let rgbSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let cg = CGContext(data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: rgbSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: CGFloat(width) / 1206, y: -CGFloat(height) / 2622)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    try drawPanel(panel)
    NSGraphicsContext.restoreGraphicsState()
    let bitmap = NSBitmapImageRep(cgImage: cg.makeImage()!)
    let name = "BokkiEncoder-\(panel["id"] as! String)-\(suffix)"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
    if suffix == "web" {
        try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])!.write(to: output.appendingPathComponent(name + ".jpg"))
    }
}

func xml(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;")
}
func writeSVG(_ panel: [String: Any]) throws {
    let fg = panel["foreground"] as! String
    let secondary = panel["secondary"] as! String
    let accent = panel["accent"] as! String
    let halo = panel["halo"] as! String
    let scale = device.width / sourceRect.width
    let imageX = device.minX - sourceRect.minX * scale
    let imageY = device.minY - sourceRect.minY * scale
    let data = try Data(contentsOf: base.appendingPathComponent(panel["source"] as! String)).base64EncodedString()
    var svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1206" height="2622" viewBox="0 0 1206 2622">
    <title>Bokki Encoder — \(xml((panel["headline"] as! [String]).joined(separator: " ")))</title>
    <desc>Marketing composition using unchanged public release 1.1.9 app imagery. Typography and device framing are editable.</desc>
    <defs><clipPath id="canvas"><rect width="1206" height="2622"/></clipPath><clipPath id="actual-ui"><rect x="205" y="852" width="796" height="1725.875" rx="68"/></clipPath><filter id="shadow" x="-20%" y="-10%" width="140%" height="130%"><feDropShadow dx="0" dy="15" stdDeviation="15" flood-opacity="0.23"/></filter></defs>
    <g clip-path="url(#canvas)">
    <rect width="1206" height="2622" fill="\(panel["background"] as! String)"/>
    <ellipse cx="1070" cy="1698" rx="650" ry="730" fill="\(halo)"/>
    <ellipse cx="10" cy="2450" rx="630" ry="610" fill="\(halo)" opacity="0.48"/>
    <g font-family="Helvetica Neue, Arial, sans-serif">
    <text x="96" y="137" font-size="43" font-weight="700" fill="\(fg)">Bokki Encoder</text>
    <rect x="1012" y="91" width="98" height="67" rx="33" fill="\(accent)"/>
    <text x="1042" y="132" font-size="31" font-weight="700" fill="#103E31">\(String((panel["id"] as! String).prefix(2)))</text>
    <text x="96" y="247" font-size="26" font-weight="700" fill="\(secondary)">\(xml(panel["eyebrow"] as! String))</text>
    """
    let headlines = panel["headline"] as! [String]
    for i in 0..<2 {
        let shade = i == 1 && panel["id"] as! String == "02-hevc-output" ? accent : fg
        svg += "<text x=\"89\" y=\"\(427 + i * 152)\" font-size=\"138\" font-weight=\"700\" fill=\"\(shade)\">\(xml(headlines[i]))</text>\n"
    }
    let captions = panel["caption"] as! [String]
    for i in 0..<2 {
        svg += "<text x=\"96\" y=\"\(672 + i * 58)\" font-size=\"43\" fill=\"\(secondary)\">\(xml(captions[i]))</text>\n"
    }
    var badgeX: CGFloat = 96
    let badges = panel["badges"] as! [String]
    for badge in badges {
        svg += "<text x=\"\(badgeX)\" y=\"804\" font-size=\"29\" font-weight=\"700\" fill=\"\(fg)\">\(xml(badge))</text>\n"
        badgeX += (badge as NSString).size(withAttributes: [.font: NSFont(name: "HelveticaNeue-Bold", size: 29)!]).width + 47
        if badge != badges.last! { svg += "<circle cx=\"\(badgeX - 23.5)\" cy=\"793.5\" r=\"3.5\" fill=\"\(accent)\"/>\n" }
    }
    svg += """
    </g><rect x="193" y="840" width="820" height="1749.875" rx="83" fill="#17251F" filter="url(#shadow)"/>
    <rect x="200" y="847" width="806" height="1735.875" rx="75" fill="#55635A"/>
    <g clip-path="url(#actual-ui)"><image x="\(imageX)" y="\(imageY)" width="\(1242 * scale)" height="\(2688 * scale)" href="data:image/png;base64,\(data)"/></g>
    </g></svg>
    """
    try svg.write(to: editable.appendingPathComponent("BokkiEncoder-\(panel["id"] as! String).svg"), atomically: true, encoding: .utf8)
}

for panel in panels {
    try render(panel, width: 1206, height: 2622, suffix: "1206x2622")
    try render(panel, width: 603, height: 1311, suffix: "web")
    try writeSVG(panel)
    print("Rendered \(panel["id"] as! String): 1206x2622 RGB PNG, 603x1311 web PNG/JPEG, editable SVG.")
}
