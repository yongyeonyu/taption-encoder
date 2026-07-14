import Foundation
import OSLog

enum AppLogCategory: String {
    case app
    case ads
    case encoding
    case fileImport
    case folderImport
    case mediaInspection
    case photosImport
    case saving
    case storage
    case ui
}

enum AppLogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

enum AppLogger {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.taption.encoder"

    private static let queue = DispatchQueue(label: "com.taption.encoder.diagnostics.filelog")
    private static let maxLogFileSizeBytes: UInt64 = 2_000_000

    static var logDirectoryURL: URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("TaptionEncoderLogs", isDirectory: true)
    }

    static var currentLogFileURL: URL {
        logDirectoryURL.appendingPathComponent("taption-encoder.log", isDirectory: false)
    }

    static func configure() {
        info(
            "Logger configured",
            category: .app,
            metadata: [
                "bundle": subsystem,
                "logFile": currentLogFileURL.path,
                "build": buildSummary
            ]
        )
    }

    #if DEBUG
    static func debug(
        _ message: @autoclosure @escaping () -> String,
        category: AppLogCategory,
        metadata: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.debug, message(), category: category, metadata: metadata, source: "\(file):\(line) \(function)")
    }

    static func info(
        _ message: @autoclosure @escaping () -> String,
        category: AppLogCategory,
        metadata: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.info, message(), category: category, metadata: metadata, source: "\(file):\(line) \(function)")
    }

    static func warning(
        _ message: @autoclosure @escaping () -> String,
        category: AppLogCategory,
        metadata: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.warning, message(), category: category, metadata: metadata, source: "\(file):\(line) \(function)")
    }

    static func error(
        _ message: @autoclosure @escaping () -> String,
        category: AppLogCategory,
        metadata: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        log(.error, message(), category: category, metadata: metadata, source: "\(file):\(line) \(function)")
    }
    #else
    static func debug(
        _ message: @autoclosure @escaping () -> String,
        category: AppLogCategory,
        metadata: [String: String] = [:]
    ) {
        log(.debug, message(), category: category, metadata: metadata, source: nil)
    }

    static func info(
        _ message: @autoclosure @escaping () -> String,
        category: AppLogCategory,
        metadata: [String: String] = [:]
    ) {
        log(.info, message(), category: category, metadata: metadata, source: nil)
    }

    static func warning(
        _ message: @autoclosure @escaping () -> String,
        category: AppLogCategory,
        metadata: [String: String] = [:]
    ) {
        log(.warning, message(), category: category, metadata: metadata, source: nil)
    }

    static func error(
        _ message: @autoclosure @escaping () -> String,
        category: AppLogCategory,
        metadata: [String: String] = [:]
    ) {
        log(.error, message(), category: category, metadata: metadata, source: nil)
    }
    #endif

    private static func log(
        _ level: AppLogLevel,
        _ message: String,
        category: AppLogCategory,
        metadata: [String: String],
        source: String?
    ) {
        let formattedLine = formattedLogLine(
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            source: source
        )
        writeToUnifiedLog(formattedLine, level: level, category: category)
        appendToFile(formattedLine)
    }

    private static func writeToUnifiedLog(
        _ line: String,
        level: AppLogLevel,
        category: AppLogCategory
    ) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug:
            logger.debug("\(line, privacy: .public)")
        case .info:
            logger.info("\(line, privacy: .public)")
        case .warning:
            logger.warning("\(line, privacy: .public)")
        case .error:
            logger.error("\(line, privacy: .public)")
        }
    }

    private static func appendToFile(_ line: String) {
        queue.async {
            do {
                let fileManager = FileManager.default
                let directoryURL = logDirectoryURL
                let fileURL = currentLogFileURL
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
                try rotateLogIfNeeded(fileURL: fileURL, fileManager: fileManager)

                if !fileManager.fileExists(atPath: fileURL.path) {
                    fileManager.createFile(atPath: fileURL.path, contents: nil)
                }

                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                if let data = (line + "\n").data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } catch {
                let logger = Logger(subsystem: subsystem, category: AppLogCategory.app.rawValue)
                logger.error("File log write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func rotateLogIfNeeded(fileURL: URL, fileManager: FileManager) throws {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? UInt64,
              fileSize >= maxLogFileSizeBytes else {
            return
        }

        let rotatedURL = logDirectoryURL.appendingPathComponent(
            "taption-encoder.previous.log",
            isDirectory: false
        )
        try? fileManager.removeItem(at: rotatedURL)
        try fileManager.moveItem(at: fileURL, to: rotatedURL)
    }

    private static func formattedLogLine(
        level: AppLogLevel,
        category: AppLogCategory,
        message: String,
        metadata: [String: String],
        source: String?
    ) -> String {
        let timestamp = ISO8601DateFormatter.appLoggerFormatter.string(from: Date())
        let metadataText = metadata.isEmpty
            ? ""
            : " " + metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(sanitize($0.value))" }
                .joined(separator: " ")
        let sourceText = source.map { " source=\($0)" } ?? ""
        return "\(timestamp) [\(level.rawValue)] [\(category.rawValue)] \(sanitize(message))\(metadataText)\(sourceText)"
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private static var buildSummary: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version)(\(build))"
    }
}

final class TaptionEncodingPerformanceTrace: @unchecked Sendable {
    private let name: String
    private let category: AppLogCategory
    private let baseMetadata: [String: String]
    private let lock = NSLock()
    private let startedAt = Date()
    private var lastMarkAt = Date()

    init(
        name: String,
        category: AppLogCategory,
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.category = category
        self.baseMetadata = metadata
        AppLogger.info(
            "Performance trace started",
            category: category,
            metadata: mergedMetadata(
                phase: "start",
                elapsedMilliseconds: "0.0",
                deltaMilliseconds: "0.0",
                extra: metadata
            )
        )
    }

    func mark(_ phase: String, metadata: [String: String] = [:]) {
        let timing = timingSnapshot()
        AppLogger.info(
            "Performance trace mark",
            category: category,
            metadata: mergedMetadata(
                phase: phase,
                elapsedMilliseconds: timing.elapsedMilliseconds,
                deltaMilliseconds: timing.deltaMilliseconds,
                extra: metadata
            )
        )
    }

    func finish(_ phase: String = "finish", metadata: [String: String] = [:]) {
        let timing = timingSnapshot()
        AppLogger.info(
            "Performance trace finished",
            category: category,
            metadata: mergedMetadata(
                phase: phase,
                elapsedMilliseconds: timing.elapsedMilliseconds,
                deltaMilliseconds: timing.deltaMilliseconds,
                extra: metadata
            )
        )
    }

    static func milliseconds(_ interval: TimeInterval) -> String {
        String(format: "%.1f", interval * 1000.0)
    }

    private func timingSnapshot() -> (elapsedMilliseconds: String, deltaMilliseconds: String) {
        lock.lock()
        defer {
            lock.unlock()
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(startedAt)
        let delta = now.timeIntervalSince(lastMarkAt)
        lastMarkAt = now
        return (
            elapsedMilliseconds: Self.milliseconds(elapsed),
            deltaMilliseconds: Self.milliseconds(delta)
        )
    }

    private func mergedMetadata(
        phase: String,
        elapsedMilliseconds: String,
        deltaMilliseconds: String,
        extra: [String: String]
    ) -> [String: String] {
        var metadata = baseMetadata
        metadata["trace"] = name
        metadata["phase"] = phase
        metadata["elapsedMs"] = elapsedMilliseconds
        metadata["deltaMs"] = deltaMilliseconds
        for (key, value) in extra {
            metadata[key] = value
        }
        return metadata
    }
}

private extension ISO8601DateFormatter {
    static let appLoggerFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()
}
