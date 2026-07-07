@preconcurrency import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation

#if canImport(TaptionFFmpegDecodeBridge)
import TaptionFFmpegDecodeBridge
#endif

struct SW_FFmpegCommandRunResult: Codable, Equatable {
    var exitCode: Int32
    var stdout: String
    var stderr: String

    init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

struct SW_FFmpegCommandExecutionResult: Codable, Equatable {
    var commandPlan: SW_FFmpegCommandPlan
    var exitCode: Int32
    var outputURL: URL
    var didCreateOutput: Bool
    var stdoutTail: String
    var stderrTail: String
}

enum SW_FFmpegCommandExecutionError: LocalizedError, Equatable {
    case backendNotExecutable(openGates: [TaptionSoftwareCodecBackendReadinessGate])
    case runnerUnavailable
    case commandFailed(exitCode: Int32, stderrTail: String)
    case outputFileMissing(URL)

    var errorDescription: String? {
        switch self {
        case .backendNotExecutable(let openGates):
            let gateList = openGates.map(\.displayName).joined(separator: ", ")
            return "FFmpeg-family backend is not executable in this build. Open gates: \(gateList)."
        case .runnerUnavailable:
            return "FFmpeg-family command runner is not installed in this build."
        case .commandFailed(let exitCode, let stderrTail):
            return "FFmpeg-family command failed with exit code \(exitCode). \(stderrTail)"
        case .outputFileMissing(let url):
            return "FFmpeg-family command completed but did not create output at \(url.path)."
        }
    }
}

protocol SW_FFmpegCommandRunning: Sendable {
    func run(commandPlan: SW_FFmpegCommandPlan) async throws -> SW_FFmpegCommandRunResult
}

struct SW_FFmpegCommandExecutor {
    var readinessReport: TaptionSoftwareCodecBackendReadinessReport
    var runner: (any SW_FFmpegCommandRunning)?
    var fileManager: FileManager
    var validateOutputFileExists: Bool

    init(
        readinessReport: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(),
        runner: (any SW_FFmpegCommandRunning)? = nil,
        fileManager: FileManager = .default,
        validateOutputFileExists: Bool = true
    ) {
        self.readinessReport = readinessReport
        self.runner = runner
        self.fileManager = fileManager
        self.validateOutputFileExists = validateOutputFileExists
    }

    func execute(
        _ commandPlan: SW_FFmpegCommandPlan,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> SW_FFmpegCommandExecutionResult {
        guard readinessReport.isExecutableInCurrentBuild else {
            throw SW_FFmpegCommandExecutionError.backendNotExecutable(
                openGates: readinessReport.openGates
            )
        }
        guard let runner else {
            throw SW_FFmpegCommandExecutionError.runnerUnavailable
        }

        progress(TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0))
        progress(TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.01))

        let runResult = try await runner.run(commandPlan: commandPlan)
        let stdoutTail = Self.tail(runResult.stdout)
        let stderrTail = Self.tail(runResult.stderr)

        guard runResult.exitCode == 0 else {
            throw SW_FFmpegCommandExecutionError.commandFailed(
                exitCode: runResult.exitCode,
                stderrTail: stderrTail
            )
        }

        let outputExists = fileManager.fileExists(atPath: commandPlan.outputURL.path)
        guard outputExists || !validateOutputFileExists else {
            throw SW_FFmpegCommandExecutionError.outputFileMissing(commandPlan.outputURL)
        }

        progress(TaptionEncodingProgress(stage: .completed, fractionCompleted: 1))

        return SW_FFmpegCommandExecutionResult(
            commandPlan: commandPlan,
            exitCode: runResult.exitCode,
            outputURL: commandPlan.outputURL,
            didCreateOutput: outputExists,
            stdoutTail: stdoutTail,
            stderrTail: stderrTail
        )
    }

    func execute(
        _ fixtureJob: TaptionCodecFixtureExecutionJob,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> SW_FFmpegCommandExecutionResult {
        let jobExecutor = SW_FFmpegCommandExecutor(
            readinessReport: fixtureJob.backendReadiness,
            runner: runner,
            fileManager: fileManager,
            validateOutputFileExists: validateOutputFileExists
        )
        return try await jobExecutor.execute(
            fixtureJob.commandPlan,
            progress: progress
        )
    }

    private static func tail(_ text: String, maxLength: Int = 4_000) -> String {
        guard text.count > maxLength else {
            return text
        }
        return String(text.suffix(maxLength))
    }
}

enum TaptionCodecFixtureExecutionKind: String, Codable, Equatable {
    case videoToHEVC
    case videoCodecTranscode
    case audioToAAC
    case audioCodecTranscode
}

struct TaptionCodecFixtureExecutionJob: Codable, Equatable, Identifiable {
    var id: String {
        let outputSuffix = outputVideoCodec?.rawValue
            ?? outputAudioCodec?.rawValue
            ?? "unknown"
        return "\(kind.rawValue)-\(fixtureName)-\(outputSuffix)"
    }

    var fixtureName: String
    var kind: TaptionCodecFixtureExecutionKind
    var sourceURL: URL
    var outputURL: URL
    var commandPlan: SW_FFmpegCommandPlan
    var sourceVideoCodec: TaptionVideoCodec?
    var outputVideoCodec: TaptionVideoCodec?
    var sourceAudioCodec: TaptionAudioCodec?
    var outputAudioCodec: TaptionAudioCodec?
    var audioOptions: TaptionAudioCodecTranscodeOptions?
    var sourceHasAudio: Bool
    var requiresAudioSignalVerification: Bool
    var backendReadiness: TaptionSoftwareCodecBackendReadinessReport

    var isExecutableInCurrentBuild: Bool {
        backendReadiness.isExecutableInCurrentBuild
    }

    var openBackendGates: [TaptionSoftwareCodecBackendReadinessGate] {
        backendReadiness.openGates
    }

    var audioTranscodeRequest: TaptionAudioCodecTranscodeRequest? {
        guard let sourceAudioCodec,
              let outputAudioCodec else {
            return nil
        }
        return TaptionAudioCodecTranscodeRequest(
            sourceURL: sourceURL,
            outputURL: outputURL,
            route: TaptionAudioCodecRoute(
                sourceCodec: sourceAudioCodec,
                outputCodec: outputAudioCodec
            ),
            options: audioOptions ?? .preservingSource(
                outputCodec: outputAudioCodec,
                outputContainer: TaptionVideoContainer.inferred(from: outputURL)
            )
        )
    }
}

enum TaptionCodecFixtureExecutionPlanner {
    static func makeVideoHEVCJobs(
        rows: [TaptionVideoFixtureManifestRow],
        fixtureDirectoryURL: URL,
        outputDirectoryURL: URL,
        backendReadiness: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
    ) throws -> [TaptionCodecFixtureExecutionJob] {
        try makeVideoCodecJobs(
            rows: rows,
            fixtureDirectoryURL: fixtureDirectoryURL,
            outputDirectoryURL: outputDirectoryURL,
            outputCodec: .hevc,
            outputContainer: .mp4,
            kind: .videoToHEVC,
            backendReadiness: backendReadiness
        )
    }

    static func makeVideoCodecJobs(
        rows: [TaptionVideoFixtureManifestRow],
        fixtureDirectoryURL: URL,
        outputDirectoryURL: URL,
        outputCodec: TaptionVideoCodec,
        outputContainer: TaptionVideoContainer = .mp4,
        kind: TaptionCodecFixtureExecutionKind = .videoCodecTranscode,
        backendReadiness: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
    ) throws -> [TaptionCodecFixtureExecutionJob] {
        try rows.map { row in
            let sourceURL = fixtureDirectoryURL.appendingPathComponent(row.file)
            let outputURL = outputDirectoryURL
                .appendingPathComponent("\(row.name)_SW_APP_CORE_\(outputCodec.rawValue.uppercased())")
                .appendingPathExtension(outputContainer.defaultFileExtension)
            let asset = makeVideoFixtureAsset(row: row)
            let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
                asset: asset,
                sourceURL: sourceURL,
                temporaryOutputURL: outputURL,
                outputPolicy: TaptionVideoOutputPolicy(videoCodec: outputCodec, container: outputContainer),
                savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
            )
            let commandPlan = try SW_FFmpegCodecCommandPlanner.makeSingleAssetCommandPlan(plan: plan)
            let sourceHasAudio = row.audioCodec != .unknown

            return TaptionCodecFixtureExecutionJob(
                fixtureName: row.name,
                kind: kind,
                sourceURL: sourceURL,
                outputURL: outputURL,
                commandPlan: commandPlan,
                sourceVideoCodec: row.videoCodec,
                outputVideoCodec: outputCodec,
                sourceAudioCodec: sourceHasAudio ? row.audioCodec : nil,
                outputAudioCodec: sourceHasAudio ? .aac : nil,
                audioOptions: plan.audioPlan?.options,
                sourceHasAudio: sourceHasAudio,
                requiresAudioSignalVerification: sourceHasAudio,
                backendReadiness: backendReadiness
            )
        }
    }

    static func makeAudioAACJobs(
        rows: [TaptionAudioFixtureGenerationRow],
        fixtureDirectoryURL: URL,
        outputDirectoryURL: URL,
        backendReadiness: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
    ) throws -> [TaptionCodecFixtureExecutionJob] {
        try makeAudioCodecJobs(
            rows: rows,
            fixtureDirectoryURL: fixtureDirectoryURL,
            outputDirectoryURL: outputDirectoryURL,
            outputCodec: .aac,
            outputContainer: .mp4,
            kind: .audioToAAC,
            backendReadiness: backendReadiness
        )
    }

    static func makeAudioCodecJobs(
        rows: [TaptionAudioFixtureGenerationRow],
        fixtureDirectoryURL: URL,
        outputDirectoryURL: URL,
        outputCodec: TaptionAudioCodec,
        outputContainer: TaptionVideoContainer = .mp4,
        kind: TaptionCodecFixtureExecutionKind = .audioCodecTranscode,
        backendReadiness: TaptionSoftwareCodecBackendReadinessReport = SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport()
    ) throws -> [TaptionCodecFixtureExecutionJob] {
        try rows
            .filter { $0.status == .pass }
            .map { row in
                let sourceURL = fixtureDirectoryURL.appendingPathComponent(row.file)
                let outputURL = outputDirectoryURL
                    .appendingPathComponent("\(row.name)_SW_APP_CORE_\(outputCodec.rawValue.uppercased())")
                    .appendingPathExtension(outputContainer.defaultFileExtension)
                let shape = audioFixtureSignalShape(for: row.targetAudioCodec)
                let sourceTrack = TaptionAudioTrackInfo(
                    codec: row.targetAudioCodec,
                    channelCount: shape.channelCount,
                    sampleRate: shape.sampleRate,
                    estimatedBitrate: shape.bitrate
                )
                let route = TaptionAudioCodecRoute(
                    sourceCodec: row.targetAudioCodec,
                    outputCodec: outputCodec
                )
                let plan = TaptionAudioTranscodePlanner.makePlan(
                    sourceTrack: sourceTrack,
                    trackIndex: 0,
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    outputCodec: outputCodec,
                    outputContainer: outputContainer
                )
                let commandPlan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(
                    request: TaptionAudioCodecTranscodeRequest(
                        sourceURL: sourceURL,
                        outputURL: outputURL,
                        route: route,
                        options: plan.options
                    )
                )

                return TaptionCodecFixtureExecutionJob(
                    fixtureName: row.name,
                    kind: kind,
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    commandPlan: commandPlan,
                    sourceVideoCodec: nil,
                    outputVideoCodec: nil,
                    sourceAudioCodec: row.targetAudioCodec,
                    outputAudioCodec: outputCodec,
                    audioOptions: plan.options,
                    sourceHasAudio: true,
                    requiresAudioSignalVerification: true,
                    backendReadiness: backendReadiness
                )
            }
    }

    private static func makeVideoFixtureAsset(
        row: TaptionVideoFixtureManifestRow
    ) -> TaptionVideoAsset {
        let audioTracks: [TaptionAudioTrackInfo]
        if row.audioCodec == .unknown {
            audioTracks = []
        } else {
            audioTracks = [
                TaptionAudioTrackInfo(
                    codec: row.audioCodec,
                    channelCount: 2,
                    sampleRate: 48_000,
                    estimatedBitrate: 160_000
                )
            ]
        }

        return TaptionVideoAsset(
            displayName: row.file,
            location: TaptionVideoAssetLocation(kind: .file),
            container: row.container,
            duration: 3,
            videoTrack: TaptionVideoTrackInfo(
                codec: row.videoCodec,
                naturalSize: TaptionPixelSize(width: 640, height: 360),
                displaySize: TaptionPixelSize(width: 640, height: 360),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30),
                estimatedBitrate: 2_000_000,
                color: TaptionColorDescription(),
                rotationDegrees: 0
            ),
            audioTracks: audioTracks,
            fingerprint: TaptionMediaFingerprint(fileSize: 1_000_000)
        )
    }

    private static func audioFixtureSignalShape(
        for codec: TaptionAudioCodec
    ) -> (sampleRate: Double, channelCount: Int, bitrate: Int) {
        switch codec {
        case .aLaw, .muLaw, .amr, .ilbc:
            return (8_000, 1, 64_000)
        case .adpcm:
            return (22_050, 1, 96_000)
        default:
            return (48_000, 2, 192_000)
        }
    }
}

enum TaptionVideoCodecExecutionReadiness: String, Codable, Equatable {
    case implementedInCurrentBuild
    case softwareBackendExecutable
    case commandPlanOnly
    case blockedMissingSoftwareEncoder
    case unsupported
}

struct TaptionVideoCodecExecutionReadinessItem: Codable, Equatable, Identifiable {
    var id: String {
        "\(route.sourceCodec.rawValue)-to-\(route.outputCodec.rawValue)-\(outputContainer.rawValue)"
    }

    var route: TaptionCodecRoute
    var outputContainer: TaptionVideoContainer
    var readiness: TaptionVideoCodecExecutionReadiness
    var routeSelection: TaptionCodecRouteSelection
    var decodeBackend: TaptionEncodingBackend?
    var encodeBackend: TaptionEncodingBackend?
    var commandBackend: TaptionEncodingBackend?
    var isRunnableInCurrentBuild: Bool
    var hasCommandPlan: Bool
    var blockingReason: String?
}

struct TaptionVideoCodecExecutionReadinessReport: Codable, Equatable {
    var outputContainer: TaptionVideoContainer
    var routeCount: Int
    var runnableInCurrentBuildRouteCount: Int
    var implementedRouteCount: Int
    var softwareBackendExecutableRouteCount: Int
    var commandPlanOnlyRouteCount: Int
    var blockedMissingSoftwareEncoderRouteCount: Int
    var unsupportedRouteCount: Int
    var commandPlannableOutputCodecs: [TaptionVideoCodec]
    var blockedOutputCodecs: [TaptionVideoCodec]
    var items: [TaptionVideoCodecExecutionReadinessItem]

    var allRoutesHaveExecutionPath: Bool {
        routeCount > 0 && unsupportedRouteCount == 0
    }

    var allRoutesRunnableInCurrentBuild: Bool {
        routeCount > 0 && runnableInCurrentBuildRouteCount == routeCount
    }
}

enum TaptionVideoCodecExecutionReadinessReporter {
    static func makeReport(
        outputContainer: TaptionVideoContainer = .mp4,
        hardwareSupport: TaptionCodecHardwareSupportProfile = .softwareOnly,
        broadSoftwareBackendExecutable: Bool = false
    ) -> TaptionVideoCodecExecutionReadinessReport {
        let items = TaptionCodecRegistry.plannedUniversalRoutes
            .map { route in
                makeItem(
                    route: route,
                    outputContainer: outputContainer,
                    hardwareSupport: hardwareSupport,
                    broadSoftwareBackendExecutable: broadSoftwareBackendExecutable
                )
            }
            .sorted {
                if $0.route.sourceCodec.rawValue == $1.route.sourceCodec.rawValue {
                    return $0.route.outputCodec.rawValue < $1.route.outputCodec.rawValue
                }
                return $0.route.sourceCodec.rawValue < $1.route.sourceCodec.rawValue
            }
        let blockedOutputCodecs = Set(items.compactMap { item in
            item.readiness == .blockedMissingSoftwareEncoder ? item.route.outputCodec : nil
        }).sorted { $0.rawValue < $1.rawValue }

        return TaptionVideoCodecExecutionReadinessReport(
            outputContainer: outputContainer,
            routeCount: items.count,
            runnableInCurrentBuildRouteCount: items.filter(\.isRunnableInCurrentBuild).count,
            implementedRouteCount: items.filter { $0.readiness == .implementedInCurrentBuild }.count,
            softwareBackendExecutableRouteCount: items.filter { $0.readiness == .softwareBackendExecutable }.count,
            commandPlanOnlyRouteCount: items.filter { $0.readiness == .commandPlanOnly }.count,
            blockedMissingSoftwareEncoderRouteCount: items.filter { $0.readiness == .blockedMissingSoftwareEncoder }.count,
            unsupportedRouteCount: items.filter { $0.readiness == .unsupported }.count,
            commandPlannableOutputCodecs: SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs,
            blockedOutputCodecs: blockedOutputCodecs,
            items: items
        )
    }

    static func item(
        for route: TaptionCodecRoute,
        outputContainer: TaptionVideoContainer = .mp4,
        hardwareSupport: TaptionCodecHardwareSupportProfile = .softwareOnly,
        broadSoftwareBackendExecutable: Bool = false
    ) -> TaptionVideoCodecExecutionReadinessItem {
        makeItem(
            route: route,
            outputContainer: outputContainer,
            hardwareSupport: hardwareSupport,
            broadSoftwareBackendExecutable: broadSoftwareBackendExecutable
        )
    }

    private static func makeItem(
        route: TaptionCodecRoute,
        outputContainer: TaptionVideoContainer,
        hardwareSupport: TaptionCodecHardwareSupportProfile,
        broadSoftwareBackendExecutable: Bool
    ) -> TaptionVideoCodecExecutionReadinessItem {
        let selection = TaptionCodecRoutePlanner.selectRoute(
            for: asset(sourceCodec: route.sourceCodec),
            outputCodec: route.outputCodec,
            requestedMode: .automatic,
            hardwareSupport: hardwareSupport
        )
        let commandBackend: TaptionEncodingBackend? = SW_FFmpegCodecCommandPlanner.videoEncoderName(
            for: route.outputCodec
        ) == nil ? nil : .ffmpegFamily

        guard selection.support != .unsupported else {
            return item(
                route: route,
                outputContainer: outputContainer,
                selection: selection,
                readiness: .unsupported,
                commandBackend: nil,
                isRunnableInCurrentBuild: false,
                hasCommandPlan: false,
                blockingReason: selection.reason
            )
        }

        if selection.support == .implemented && selection.isEncodableNow {
            return item(
                route: route,
                outputContainer: outputContainer,
                selection: selection,
                readiness: .implementedInCurrentBuild,
                commandBackend: commandBackend,
                isRunnableInCurrentBuild: true,
                hasCommandPlan: commandBackend != nil,
                blockingReason: nil
            )
        }

        guard SW_FFmpegCodecCommandPlanner.videoEncoderName(for: route.outputCodec) != nil else {
            return item(
                route: route,
                outputContainer: outputContainer,
                selection: selection,
                readiness: .blockedMissingSoftwareEncoder,
                commandBackend: nil,
                isRunnableInCurrentBuild: false,
                hasCommandPlan: false,
                blockingReason: "\(route.outputCodec.displayName) has no selected software video encoder in the current command plan."
            )
        }

        return item(
            route: route,
            outputContainer: outputContainer,
            selection: selection,
            readiness: broadSoftwareBackendExecutable ? .softwareBackendExecutable : .commandPlanOnly,
            commandBackend: .ffmpegFamily,
            isRunnableInCurrentBuild: broadSoftwareBackendExecutable,
            hasCommandPlan: true,
            blockingReason: broadSoftwareBackendExecutable
                ? nil
                : "The FFmpeg-family backend command can be planned, but the backend is not bundled in this build."
        )
    }

    private static func item(
        route: TaptionCodecRoute,
        outputContainer: TaptionVideoContainer,
        selection: TaptionCodecRouteSelection,
        readiness: TaptionVideoCodecExecutionReadiness,
        commandBackend: TaptionEncodingBackend?,
        isRunnableInCurrentBuild: Bool,
        hasCommandPlan: Bool,
        blockingReason: String?
    ) -> TaptionVideoCodecExecutionReadinessItem {
        TaptionVideoCodecExecutionReadinessItem(
            route: route,
            outputContainer: outputContainer,
            readiness: readiness,
            routeSelection: selection,
            decodeBackend: selection.decodeBackend,
            encodeBackend: selection.encodeBackend,
            commandBackend: commandBackend,
            isRunnableInCurrentBuild: isRunnableInCurrentBuild,
            hasCommandPlan: hasCommandPlan,
            blockingReason: blockingReason
        )
    }

    private static func asset(sourceCodec: TaptionVideoCodec) -> TaptionVideoAsset {
        TaptionVideoAsset(
            displayName: "\(sourceCodec.rawValue).mp4",
            location: TaptionVideoAssetLocation(kind: .file),
            container: .mp4,
            duration: 1,
            videoTrack: TaptionVideoTrackInfo(
                codec: sourceCodec,
                naturalSize: TaptionPixelSize(width: 1920, height: 1080),
                displaySize: TaptionPixelSize(width: 1920, height: 1080),
                nominalFrameRate: TaptionRationalFrameRate(numerator: 30)
            )
        )
    }
}

#if canImport(TaptionFFmpegDecodeBridge)
enum SW_FFmpegDecodeBridgeRunnerError: LocalizedError, Equatable {
    case unsupportedOutput(URL)
    case probeFailed(status: Int32, message: String)
    case invalidProbeSize(width: Int32, height: Int32)
    case writerStartFailed(String)
    case decodeFailed(status: Int32, message: String)
    case writerFinishFailed(String)
    case outputMissing(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedOutput(let url):
            return "FFmpeg decode bridge output must be MP4 or MOV: \(url.lastPathComponent)."
        case .probeFailed(let status, let message):
            return "FFmpeg decode bridge probe failed with status \(status). \(message)"
        case .invalidProbeSize(let width, let height):
            return "FFmpeg decode bridge reported an invalid video size: \(width)x\(height)."
        case .writerStartFailed(let message):
            return "FFmpeg decode bridge HEVC writer failed to start. \(message)"
        case .decodeFailed(let status, let message):
            return "FFmpeg decode bridge failed with status \(status). \(message)"
        case .writerFinishFailed(let message):
            return "FFmpeg decode bridge HEVC writer failed to finish. \(message)"
        case .outputMissing(let url):
            return "FFmpeg decode bridge completed but did not create output at \(url.path)."
        }
    }
}

struct SW_FFmpegDecodeBridgeRunReport: Codable, Equatable {
    var frameCount: Int
    var width: Int
    var height: Int
    var averageFrameRate: Double
    var codecName: String
    var pixelFormatName: String
    var outputURL: URL
}

private final class SW_FFmpegDecodeBridgeAssetWriterBox: @unchecked Sendable {
    private let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) {
        self.writer = writer
    }

    func finish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if self.writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: SW_FFmpegDecodeBridgeRunnerError.writerFinishFailed(
                            self.writer.error?.localizedDescription
                            ?? "Writer ended with status \(self.writer.status.rawValue)."
                        )
                    )
                }
            }
        }
    }
}

struct SW_FFmpegDecodeBridgeCommandRunner: SW_FFmpegCommandRunning {
    var maximumFrameCount: Int32
    var targetBitrate: Int?

    init(
        maximumFrameCount: Int32 = 0,
        targetBitrate: Int? = nil
    ) {
        self.maximumFrameCount = maximumFrameCount
        self.targetBitrate = targetBitrate
    }

    func run(commandPlan: SW_FFmpegCommandPlan) async throws -> SW_FFmpegCommandRunResult {
        let report = try await SW_FFmpegDecodeBridgeHEVCTranscoder.transcode(
            commandPlan: commandPlan,
            maximumFrameCount: maximumFrameCount,
            targetBitrate: targetBitrate
        )
        return SW_FFmpegCommandRunResult(
            exitCode: 0,
            stdout: [
                "backend=TaptionFFmpegDecodeBridge",
                "frames=\(report.frameCount)",
                "size=\(report.width)x\(report.height)",
                "fps=\(String(format: "%.3f", report.averageFrameRate))",
                "codec=\(report.codecName)",
                "pixelFormat=\(report.pixelFormatName)",
                "output=\(report.outputURL.lastPathComponent)"
            ].joined(separator: "\n")
        )
    }
}

private enum SW_FFmpegDecodeBridgeHEVCTranscoder {
    static func transcode(
        commandPlan: SW_FFmpegCommandPlan,
        maximumFrameCount: Int32,
        targetBitrate: Int?
    ) async throws -> SW_FFmpegDecodeBridgeRunReport {
        guard [.mp4, .mov].contains(TaptionVideoContainer.inferred(from: commandPlan.outputURL)) else {
            throw SW_FFmpegDecodeBridgeRunnerError.unsupportedOutput(commandPlan.outputURL)
        }

        let probe = try probe(sourceURL: commandPlan.sourceURL)
        guard probe.width > 0,
              probe.height > 0 else {
            throw SW_FFmpegDecodeBridgeRunnerError.invalidProbeSize(
                width: probe.width,
                height: probe.height
            )
        }

        try FileManager.default.createDirectory(
            at: commandPlan.outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: commandPlan.outputURL)

        let targetSize = CGSize(width: Int(probe.width), height: Int(probe.height))
        let frameRate = normalizedFrameRate(probe.averageFrameRate)
        let frameDuration = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
        let writer = try AVAssetWriter(
            outputURL: commandPlan.outputURL,
            fileType: avFileType(for: commandPlan.outputURL)
        )
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: writerVideoOutputSettings(
                targetSize: targetSize,
                targetBitrate: targetBitrate,
                frameRate: frameRate
            )
        )
        videoInput.expectsMediaDataInRealTime = false
        videoInput.performsMultiPassEncodingIfSupported = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes(size: targetSize)
        )
        guard writer.canAdd(videoInput) else {
            throw SW_FFmpegDecodeBridgeRunnerError.writerStartFailed("The HEVC video input could not be added.")
        }
        writer.add(videoInput)
        guard writer.startWriting() else {
            throw SW_FFmpegDecodeBridgeRunnerError.writerStartFailed(
                writer.error?.localizedDescription ?? "Unknown AVAssetWriter start failure."
            )
        }
        writer.startSession(atSourceTime: .zero)

        let context = SW_AV1FrameWriterContext(
            writer: writer,
            videoInput: videoInput,
            adaptor: adaptor,
            targetSize: targetSize,
            frameDuration: frameDuration,
            expectedFrameCount: max(Int(maximumFrameCount), 1),
            limitsToExpectedFrameCount: maximumFrameCount > 0,
            allowsLegacyFrameHoldToPreserveDuration: false,
            progressHandler: { _ in }
        )
        guard context.prepareDecodePoolFormat() != nil else {
            throw SW_FFmpegDecodeBridgeRunnerError.writerStartFailed("The decode pixel buffer pool could not be created.")
        }
        defer {
            context.requestCancellation()
            context.clearDecodePool()
        }

        let decodeResult = try decode(
            sourceURL: commandPlan.sourceURL,
            maximumFrameCount: maximumFrameCount,
            context: context
        )

        try context.finishVideoInput()
        try await finishWriter(writer)
        guard FileManager.default.fileExists(atPath: commandPlan.outputURL.path) else {
            throw SW_FFmpegDecodeBridgeRunnerError.outputMissing(commandPlan.outputURL)
        }

        return SW_FFmpegDecodeBridgeRunReport(
            frameCount: max(Int(decodeResult.frameCount), context.currentFrameCount),
            width: Int(decodeResult.width),
            height: Int(decodeResult.height),
            averageFrameRate: normalizedFrameRate(decodeResult.averageFrameRate),
            codecName: stringFromCStringBuffer(decodeResult.codecName),
            pixelFormatName: stringFromCStringBuffer(decodeResult.pixelFormatName),
            outputURL: commandPlan.outputURL
        )
    }

    private static func probe(sourceURL: URL) throws -> TaptionFFmpegDecodeBridgeProbeResult {
        var result = TaptionFFmpegDecodeBridgeProbeResult()
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let status = sourceURL.path.withCString { sourcePath in
            taption_ffmpeg_decode_bridge_probe_video(
                sourcePath,
                &result,
                &errorBuffer,
                Int32(errorBuffer.count)
            )
        }
        guard status == 0 else {
            throw SW_FFmpegDecodeBridgeRunnerError.probeFailed(
                status: status,
                message: String(cString: errorBuffer)
            )
        }
        return result
    }

    private static func decode(
        sourceURL: URL,
        maximumFrameCount: Int32,
        context: SW_AV1FrameWriterContext
    ) throws -> TaptionFFmpegDecodeBridgeProbeResult {
        var result = TaptionFFmpegDecodeBridgeProbeResult()
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let status = sourceURL.path.withCString { sourcePath in
            taption_ffmpeg_decode_bridge_decode_video_to_bgra(
                sourcePath,
                maximumFrameCount,
                ffmpegDecodeBridgeFrameCallback,
                Unmanaged.passUnretained(context).toOpaque(),
                &result,
                &errorBuffer,
                Int32(errorBuffer.count)
            )
        }
        guard status == 0 else {
            throw SW_FFmpegDecodeBridgeRunnerError.decodeFailed(
                status: status,
                message: String(cString: errorBuffer)
            )
        }
        return result
    }

    private static func writerVideoOutputSettings(
        targetSize: CGSize,
        targetBitrate: Int?,
        frameRate: Double
    ) -> [String: Any] {
        let width = max(2, Int(targetSize.width.rounded()))
        let height = max(2, Int(targetSize.height.rounded()))
        let estimatedBitrate = targetBitrate ?? max(
            700_000,
            min(10_000_000, Int(Double(width * height) * max(frameRate, 1) * 0.25))
        )
        return [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: estimatedBitrate,
                AVVideoExpectedSourceFrameRateKey: Int(max(frameRate.rounded(), 1)),
                AVVideoAllowFrameReorderingKey: false
            ]
        ]
    }

    private static func pixelBufferAttributes(size: CGSize) -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: max(2, Int(size.width.rounded())),
            kCVPixelBufferHeightKey as String: max(2, Int(size.height.rounded())),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
    }

    private static func avFileType(for outputURL: URL) -> AVFileType {
        outputURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
    }

    private static func normalizedFrameRate(_ rawValue: Double) -> Double {
        guard rawValue.isFinite,
              rawValue >= 1,
              rawValue <= 240 else {
            return 30
        }
        return rawValue
    }

    private static func stringFromCStringBuffer<T>(_ buffer: T) -> String {
        var mutableBuffer = buffer
        let capacity = MemoryLayout<T>.size / MemoryLayout<CChar>.size
        return withUnsafePointer(to: &mutableBuffer) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { cStringPointer in
                String(cString: cStringPointer)
            }
        }
    }

    private static func finishWriter(_ writer: AVAssetWriter) async throws {
        try await SW_FFmpegDecodeBridgeAssetWriterBox(writer).finish()
    }
}

private nonisolated func ffmpegDecodeBridgeFrameWriterContext(
    from opaque: UnsafeMutableRawPointer?
) -> SW_AV1FrameWriterContext? {
    guard let opaque else { return nil }
    return Unmanaged<SW_AV1FrameWriterContext>.fromOpaque(opaque).takeUnretainedValue()
}

private nonisolated func ffmpegDecodeBridgeFrameCallback(
    _ frame: UnsafePointer<TaptionFFmpegDecodeBridgeFrame>?,
    _ opaque: UnsafeMutableRawPointer?
) -> Int32 {
    guard let frame,
          let context = ffmpegDecodeBridgeFrameWriterContext(from: opaque),
          let pixelBuffer = context.makeDecodePixelBuffer(),
          frame.pointee.width > 0,
          frame.pointee.height > 0,
          frame.pointee.bytesPerRow > 0,
          let sourceBaseAddress = frame.pointee.bgraBytes else {
        return -1
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }
    guard let destinationBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        return -2
    }

    let width = Int(frame.pointee.width)
    let height = min(Int(frame.pointee.height), CVPixelBufferGetHeight(pixelBuffer))
    let sourceBytesPerRow = Int(frame.pointee.bytesPerRow)
    let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let bytesPerRowToCopy = min(width * 4, sourceBytesPerRow, destinationBytesPerRow)

    for row in 0..<height {
        let sourceRow = sourceBaseAddress.advanced(by: row * sourceBytesPerRow)
        let destinationRow = destinationBaseAddress.advanced(by: row * destinationBytesPerRow)
        memcpy(destinationRow, sourceRow, bytesPerRowToCopy)
    }

    context.appendDecodedPixelBuffer(pixelBuffer)
    return 0
}
#endif
