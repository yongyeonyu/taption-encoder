import Foundation

/// Codec/container metadata can contain NaN, infinity or values outside Int's range.
enum MediaDisplayFormatting {
    static func time(_ seconds: Double?, unknown: String = "--:--") -> String {
        guard let seconds, seconds.isFinite, seconds.rounded() < Double(Int.max / 2) else { return unknown }
        let total = Int(max(0, seconds.rounded()))
        let hours = total / 3600
        let minutes = (total / 60) % 60
        let remainderSeconds = total % 60
        let tail = String(format: "%02d:%02d", minutes, remainderSeconds)
        return hours > 0 ? "\(hours):" + tail : tail
    }

    static func frameRate(_ rate: TaptionRationalFrameRate?) -> String {
        guard let value = rate?.value, value.isFinite, value > 0, value < Double(Int.max / 2) else { return "Unknown fps" }
        if abs(value.rounded() - value) < 0.01 { return "\(Int(value.rounded())) fps" }
        return String(format: "%.2f fps", value)
    }

    static func byteCount(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "Unknown size" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
