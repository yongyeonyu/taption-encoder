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

struct SW_FFmpegDecodeBridgeVideoGeometry: Equatable {
    var codedSize: TaptionPixelSize
    var displaySize: TaptionPixelSize

    init(
        codedSize: TaptionPixelSize,
        sampleAspectRatioHorizontalSpacing: Int,
        sampleAspectRatioVerticalSpacing: Int
    ) {
        self.codedSize = codedSize
        guard sampleAspectRatioHorizontalSpacing > 0,
              sampleAspectRatioVerticalSpacing > 0 else {
            displaySize = codedSize
            return
        }

        let displayWidth = Int(
            (Double(codedSize.width) * Double(sampleAspectRatioHorizontalSpacing)
                / Double(sampleAspectRatioVerticalSpacing)).rounded()
        )
        displaySize = TaptionPixelSize(
            width: max(displayWidth, 2),
            height: codedSize.height
        )
    }
}

enum SW_FFmpegDecodeBridgeVideoGeometryProbe {
    static func inspect(sourceURL: URL) -> SW_FFmpegDecodeBridgeVideoGeometry? {
        #if canImport(TaptionFFmpegDecodeBridge)
        var result = TaptionFFmpegDecodeBridgeProbeResult()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = sourceURL.path.withCString { sourcePath in
            taption_ffmpeg_decode_bridge_probe_video(
                sourcePath,
                &result,
                &errorBuffer,
                Int32(errorBuffer.count)
            )
        }
        guard status == 0,
              result.width > 0,
              result.height > 0 else {
            return nil
        }
        return SW_FFmpegDecodeBridgeVideoGeometry(
            codedSize: TaptionPixelSize(
                width: Int(result.width),
                height: Int(result.height)
            ),
            sampleAspectRatioHorizontalSpacing: Int(result.sampleAspectRatioNumerator),
            sampleAspectRatioVerticalSpacing: Int(result.sampleAspectRatioDenominator)
        )
        #else
        return nil
        #endif
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
    var outputPixelFormatName: String
    var outputAudioTrackCount: Int
    var outputURL: URL
}

enum SW_FFmpegDecodeBridgeWriterMetadata {
    static func expectedFrameCount(
        durationSeconds: Double,
        frameRate: Double,
        maximumFrameCount: Int32
    ) -> Int {
        if maximumFrameCount > 0 {
            return Int(maximumFrameCount)
        }
        guard durationSeconds.isFinite,
              durationSeconds > 0,
              frameRate.isFinite,
              frameRate > 0 else {
            return 1
        }
        return max(1, Int((durationSeconds * frameRate).rounded()))
    }

    static func pixelAspectRatio(
        horizontalSpacing: Int,
        verticalSpacing: Int
    ) -> [String: Any]? {
        guard horizontalSpacing > 0,
              verticalSpacing > 0,
              horizontalSpacing != verticalSpacing else {
            return nil
        }
        return [
            AVVideoPixelAspectRatioHorizontalSpacingKey: horizontalSpacing,
            AVVideoPixelAspectRatioVerticalSpacingKey: verticalSpacing
        ]
    }

    static func sessionEndTime(
        videoDurationSeconds: Double,
        audioDurationSeconds: Double?
    ) -> CMTime? {
        let durations = [videoDurationSeconds, audioDurationSeconds]
            .compactMap { duration -> Double? in
                guard let duration,
                      duration.isFinite,
                      duration > 0 else {
                    return nil
                }
                return duration
            }
        guard let durationSeconds = durations.max() else {
            return nil
        }
        return CMTime(seconds: durationSeconds, preferredTimescale: 600)
    }
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
    var preserveAudioWhenPossible: Bool
    var outputAudioCodec: TaptionAudioCodec
    var optimizationProfile: TaptionEncodingOptimizationProfile
    var color: TaptionColorDescription
    /// The frame the output should have. The bridge never runs an FFmpeg filter chain, so the command plan's
    /// `-vf` argument is inert here and the frame has to be described to the writer directly.
    var resizeTo: TaptionPixelSize?
    /// A frame-rate ceiling. Only rates below the source's can be honoured: the bridge decodes the source's
    /// frames and has none to spare for a higher rate.
    var frameRate: TaptionRationalFrameRate?
    var scaleMode: TaptionVideoScaleMode

    init(
        maximumFrameCount: Int32 = 0,
        targetBitrate: Int? = nil,
        preserveAudioWhenPossible: Bool = false,
        outputAudioCodec: TaptionAudioCodec = .aac,
        optimizationProfile: TaptionEncodingOptimizationProfile = .balanced,
        color: TaptionColorDescription = TaptionColorDescription(),
        resizeTo: TaptionPixelSize? = nil,
        frameRate: TaptionRationalFrameRate? = nil,
        scaleMode: TaptionVideoScaleMode = .default
    ) {
        self.maximumFrameCount = maximumFrameCount
        self.targetBitrate = targetBitrate
        self.preserveAudioWhenPossible = preserveAudioWhenPossible
        self.outputAudioCodec = outputAudioCodec
        self.optimizationProfile = optimizationProfile
        self.color = color
        self.resizeTo = resizeTo
        self.frameRate = frameRate
        self.scaleMode = scaleMode
    }

    func run(commandPlan: SW_FFmpegCommandPlan) async throws -> SW_FFmpegCommandRunResult {
        let report = try await SW_FFmpegDecodeBridgeHEVCTranscoder.transcode(
            commandPlan: commandPlan,
            maximumFrameCount: maximumFrameCount,
            targetBitrate: targetBitrate,
            preserveAudioWhenPossible: preserveAudioWhenPossible,
            outputAudioCodec: outputAudioCodec,
            optimizationProfile: optimizationProfile,
            color: color,
            resizeTo: resizeTo,
            frameRate: frameRate,
            scaleMode: scaleMode
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
                "outputPixelFormat=\(report.outputPixelFormatName)",
                "audioTracks=\(report.outputAudioTrackCount)",
                "output=\(report.outputURL.lastPathComponent)"
            ].joined(separator: "\n")
        )
    }
}

enum SW_FFmpegDecodeBridgeFallbackTranscoder {
    static func transcode(
        request: TaptionCodecTranscodeRequest,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionCodecTranscodeOutput {
        let commandPlan = try SW_FFmpegCodecCommandPlanner.makeVideoCommandPlan(
            request: request
        )
        let inspectedAsset = try? await AVFoundationMediaInspector()
            .inspectVideo(at: request.sourceURL)
        let outputColor = request.options.outputPolicy.advancedOptions.color
            ?? inspectedAsset?.videoTrack?.color
            ?? TaptionColorDescription()
        progress(TaptionEncodingProgress(stage: .preparing, fractionCompleted: 0))
        progress(TaptionEncodingProgress(stage: .encoding, fractionCompleted: 0.01))
        let advancedOptions = request.options.outputPolicy.advancedOptions
        let result = try await SW_FFmpegDecodeBridgeCommandRunner(
            targetBitrate: advancedOptions.targetBitrate,
            preserveAudioWhenPossible: request.options.preserveAudioWhenPossible,
            outputAudioCodec: request.options.outputPolicy.audioCodec,
            optimizationProfile: advancedOptions.optimizationProfile
                ?? .balanced,
            color: outputColor,
            resizeTo: advancedOptions.resizeTo,
            frameRate: advancedOptions.frameRate,
            scaleMode: advancedOptions.resolvedScaleMode
        ).run(commandPlan: commandPlan)
        guard result.exitCode == 0 else {
            throw SW_FFmpegCommandExecutionError.commandFailed(
                exitCode: result.exitCode,
                stderrTail: result.stderr
            )
        }
        guard FileManager.default.fileExists(atPath: request.outputURL.path) else {
            throw SW_FFmpegCommandExecutionError.outputFileMissing(request.outputURL)
        }
        let outputAudioTrackCount = await (
            (try? AVURLAsset(url: request.outputURL).loadTracks(withMediaType: .audio))?.count ?? 0
        )
        progress(TaptionEncodingProgress(stage: .waitingForSaveGate, fractionCompleted: 1))
        return TaptionCodecTranscodeOutput(
            outputURL: request.outputURL,
            route: request.route,
            usedMode: .software,
            usedBackend: .ffmpegFamily,
            outputVideoCodec: .hevc,
            outputAudioTrackCount: outputAudioTrackCount
        )
    }
}

private final class SW_FFmpegNV12FrameOutputContext: @unchecked Sendable {
    private let writerContext: SW_AV1FrameWriterContext
    private let targetWidth: Int
    private let targetHeight: Int
    private let stateLock = NSLock()
    private var pixelBufferPool: CVPixelBufferPool?
    private var pendingPixelBuffer: CVPixelBuffer?

    init(writerContext: SW_AV1FrameWriterContext, targetSize: CGSize) {
        self.writerContext = writerContext
        self.targetWidth = max(2, Int(targetSize.width.rounded()))
        self.targetHeight = max(2, Int(targetSize.height.rounded()))
    }

    func prepare() -> Bool {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 6
        ]
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: targetWidth,
            kCVPixelBufferHeightKey as String: targetHeight,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        var pool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        ) == kCVReturnSuccess,
              let pool else {
            return false
        }
        stateLock.lock()
        pixelBufferPool = pool
        stateLock.unlock()
        return true
    }

    func acquire(_ frame: UnsafeMutablePointer<TaptionFFmpegDecodeBridgeWritableNV12Frame>) -> Int32 {
        guard !writerContext.shouldAbort else {
            return -3
        }
        stateLock.lock()
        guard pendingPixelBuffer == nil,
              let pixelBufferPool else {
            stateLock.unlock()
            return -1
        }
        stateLock.unlock()

        var pixelBuffer: CVPixelBuffer?
        guard frame.pointee.width == targetWidth,
              frame.pointee.height == targetHeight,
              CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                pixelBufferPool,
                &pixelBuffer
              ) == kCVReturnSuccess,
              let pixelBuffer,
              CVPixelBufferIsPlanar(pixelBuffer),
              CVPixelBufferGetPlaneCount(pixelBuffer) >= 2 else {
            return -2
        }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
            return -3
        }
        guard let yBytes = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvBytes = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return -4
        }

        frame.pointee.yBytes = yBytes.assumingMemoryBound(to: UInt8.self)
        frame.pointee.uvBytes = uvBytes.assumingMemoryBound(to: UInt8.self)
        frame.pointee.yBytesPerRow = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
        frame.pointee.uvBytesPerRow = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))

        stateLock.lock()
        pendingPixelBuffer = pixelBuffer
        stateLock.unlock()
        return 0
    }

    func commit(_ frame: UnsafeMutablePointer<TaptionFFmpegDecodeBridgeWritableNV12Frame>) -> Int32 {
        stateLock.lock()
        let pixelBuffer = pendingPixelBuffer
        pendingPixelBuffer = nil
        stateLock.unlock()
        guard let pixelBuffer else {
            return -1
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        guard !writerContext.shouldAbort else {
            return -3
        }
        writerContext.appendDecodedPixelBuffer(pixelBuffer)
        return 0
    }

    func cancelPendingFrame() {
        stateLock.lock()
        let pixelBuffer = pendingPixelBuffer
        pendingPixelBuffer = nil
        pixelBufferPool = nil
        stateLock.unlock()
        if let pixelBuffer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
    }
}

private enum SW_FFmpegDecodeBridgeHEVCTranscoder {
    private struct DecodedVideoResult: Sendable {
        var frameCount: Int
        var width: Int
        var height: Int
        var averageFrameRate: Double
        var codecName: String
        var pixelFormatName: String
    }

    private final class ConcurrentMediaDecodeState: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<DecodedVideoResult, Error>?
        private var videoResult: DecodedVideoResult?
        private var firstError: Error?
        private var completedTaskCount = 0
        private var didResume = false

        func attach(_ continuation: CheckedContinuation<DecodedVideoResult, Error>) {
            lock.lock()
            self.continuation = continuation
            let completion = completionIfReadyLocked()
            lock.unlock()
            completion?()
        }

        func completeVideo(_ result: Result<DecodedVideoResult, Error>) {
            switch result {
            case let .success(videoResult):
                complete(videoResult: videoResult, error: nil)
            case let .failure(error):
                complete(videoResult: nil, error: error)
            }
        }

        func completeAudio(_ result: Result<Void, Error>) {
            switch result {
            case .success:
                complete(videoResult: nil, error: nil)
            case let .failure(error):
                complete(videoResult: nil, error: error)
            }
        }

        private func complete(
            videoResult: DecodedVideoResult?,
            error: Error?
        ) {
            lock.lock()
            if let videoResult {
                self.videoResult = videoResult
            }
            if firstError == nil, let error {
                firstError = error
            }
            completedTaskCount += 1
            let completion = completionIfReadyLocked()
            lock.unlock()
            completion?()
        }

        private func completionIfReadyLocked() -> (() -> Void)? {
            guard completedTaskCount == 2,
                  !didResume,
                  let continuation else {
                return nil
            }
            didResume = true
            self.continuation = nil
            let outcome: Result<DecodedVideoResult, Error>
            if let firstError {
                outcome = .failure(firstError)
            } else if let videoResult {
                outcome = .success(videoResult)
            } else {
                outcome = .failure(SW_FFmpegDecodeBridgeRunnerError.decodeFailed(
                    status: -1,
                    message: "Concurrent bundled video decoding returned no result."
                ))
            }
            return { continuation.resume(with: outcome) }
        }
    }

    static func transcode(
        commandPlan: SW_FFmpegCommandPlan,
        maximumFrameCount: Int32,
        targetBitrate: Int?,
        preserveAudioWhenPossible: Bool,
        outputAudioCodec: TaptionAudioCodec,
        optimizationProfile: TaptionEncodingOptimizationProfile,
        color: TaptionColorDescription,
        resizeTo: TaptionPixelSize? = nil,
        frameRate requestedFrameRate: TaptionRationalFrameRate? = nil,
        scaleMode: TaptionVideoScaleMode = .default
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

        // The bridge decodes at the source's own shape and the writer places the picture in the output frame.
        // Sizing the decode buffer to the source is what makes a resolution change possible at all: the decoder
        // can only fill a buffer that matches the picture it produced, so asking it for the target frame would
        // be rejected outright.
        let sourceSize = CGSize(width: Int(probe.width), height: Int(probe.height))
        // An anamorphic source stores its width in the sample aspect ratio, not in its coded pixels, so the
        // placement has to be decided on the shape the picture is shown with.
        let sourceGeometry = SW_FFmpegDecodeBridgeVideoGeometry(
            codedSize: TaptionPixelSize(width: Int(probe.width), height: Int(probe.height)),
            sampleAspectRatioHorizontalSpacing: Int(probe.sampleAspectRatioNumerator),
            sampleAspectRatioVerticalSpacing: Int(probe.sampleAspectRatioDenominator)
        )
        let sourceDisplaySize = CGSize(
            width: sourceGeometry.displaySize.width,
            height: sourceGeometry.displaySize.height
        )
        let resizedSize = resizedTargetSize(
            resizeTo,
            sourceSize: sourceSize,
            sourceDisplaySize: sourceDisplaySize
        )
        let targetSize = resizedSize ?? sourceSize
        let resizesFrame = resizedSize != nil
        let sourceFrameRate = normalizedFrameRate(probe.averageFrameRate)
        let framePlan = outputFramePlan(
            sourceFrameRate: sourceFrameRate,
            requestedFrameRate: requestedFrameRate
        )
        let frameRate = framePlan.frameRate
        let usesDirectNV12 = !resizesFrame
            && Int(targetSize.width).isMultiple(of: 2)
            && Int(targetSize.height).isMultiple(of: 2)
        let frameDuration = CMTime(seconds: 1.0 / frameRate, preferredTimescale: 600)
        let expectedFrameCount = SW_FFmpegDecodeBridgeWriterMetadata.expectedFrameCount(
            durationSeconds: probe.durationSeconds,
            frameRate: frameRate,
            maximumFrameCount: maximumFrameCount
        )
        let limitsToExpectedFrameCount = maximumFrameCount > 0
            || (probe.durationSeconds.isFinite && probe.durationSeconds > 0)
        let writer = try AVAssetWriter(
            outputURL: commandPlan.outputURL,
            fileType: avFileType(for: commandPlan.outputURL)
        )
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: writerVideoOutputSettings(
                targetSize: targetSize,
                targetBitrate: targetBitrate,
                frameRate: frameRate,
                optimizationProfile: optimizationProfile,
                color: color,
                // A resized frame is already the exact output frame, so the source's sample aspect ratio must
                // not stretch it a second time. Only a straight copy keeps the original ratio.
                pixelAspectRatioHorizontalSpacing: resizesFrame ? 1 : Int(probe.sampleAspectRatioNumerator),
                pixelAspectRatioVerticalSpacing: resizesFrame ? 1 : Int(probe.sampleAspectRatioDenominator)
            )
        )
        videoInput.expectsMediaDataInRealTime = false
        videoInput.performsMultiPassEncodingIfSupported = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes(
                size: targetSize,
                pixelFormat: usesDirectNV12
                    ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                    : kCVPixelFormatType_32BGRA
            )
        )
        guard writer.canAdd(videoInput) else {
            throw SW_FFmpegDecodeBridgeRunnerError.writerStartFailed("The HEVC video input could not be added.")
        }
        writer.add(videoInput)
        writer.shouldOptimizeForNetworkUse = false

        let audioProbe = try probeAudioIfPresent(
            sourceURL: commandPlan.sourceURL,
            preserveAudioWhenPossible: preserveAudioWhenPossible
        )
        let audioContext: SW_AV1AudioWriterContext?
        if let audioProbe {
            let audioConfiguration = makeAudioConfiguration(
                probe: audioProbe,
                outputCodec: outputAudioCodec
            )
            let audioInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: audioConfiguration.writerOutputSettings
            )
            audioInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(audioInput) else {
                throw SW_FFmpegDecodeBridgeRunnerError.writerStartFailed("The audio input could not be added.")
            }
            writer.add(audioInput)
            audioContext = try SW_AV1AudioWriterContext(
                audioInput: audioInput,
                configuration: audioConfiguration,
                maximumPendingSampleBufferCount: optimizationProfile.softwareAudioPipelineDepth,
                backpressureSleepMicroseconds: optimizationProfile.writerBackpressureSleepMicroseconds
            )
        } else {
            audioContext = nil
        }

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
            // A resize is placed here rather than by an FFmpeg filter, because this path decodes through the
            // bundled C bridge and never runs the planned command line. Without a resize the decoded frame is
            // already the output frame and there is nothing to place.
            decodeSize: resizesFrame ? sourceSize : nil,
            displaySize: resizesFrame ? sourceDisplaySize : nil,
            scaleMode: scaleMode,
            frameDuration: frameDuration,
            expectedFrameCount: expectedFrameCount,
            limitsToExpectedFrameCount: limitsToExpectedFrameCount,
            allowsLegacyFrameHoldToPreserveDuration: limitsToExpectedFrameCount,
            decimationRatio: framePlan.decimationRatio,
            maximumPendingFrameCount: optimizationProfile.softwareFramePipelineDepth,
            backpressureSleepMicroseconds: optimizationProfile.writerBackpressureSleepMicroseconds,
            progressHandler: { _ in }
        )
        let nv12Context = usesDirectNV12
            ? SW_FFmpegNV12FrameOutputContext(writerContext: context, targetSize: targetSize)
            : nil
        let preparedDecodeOutput = nv12Context?.prepare() ?? (context.prepareDecodePoolFormat() != nil)
        guard preparedDecodeOutput else {
            throw SW_FFmpegDecodeBridgeRunnerError.writerStartFailed("The decode pixel buffer pool could not be created.")
        }
        defer {
            nv12Context?.cancelPendingFrame()
            context.requestCancellation()
            audioContext?.requestCancellation()
            context.clearDecodePool()
        }

        let decodeResult = try await decodeMedia(
            sourceURL: commandPlan.sourceURL,
            maximumFrameCount: maximumFrameCount,
            videoContext: context,
            nv12Context: nv12Context,
            audioContext: audioContext
        )

        try context.finishVideoInput()
        try audioContext?.finishAudioInput()
        if let sessionEndTime = SW_FFmpegDecodeBridgeWriterMetadata.sessionEndTime(
            videoDurationSeconds: probe.durationSeconds,
            audioDurationSeconds: audioProbe?.durationSeconds
        ) {
            writer.endSession(atSourceTime: sessionEndTime)
        }
        try await finishWriter(writer)
        guard FileManager.default.fileExists(atPath: commandPlan.outputURL.path) else {
            throw SW_FFmpegDecodeBridgeRunnerError.outputMissing(commandPlan.outputURL)
        }

        return SW_FFmpegDecodeBridgeRunReport(
            frameCount: max(decodeResult.frameCount, context.currentFrameCount),
            // The written frame, not the decoded one: with a resize the two differ, and this value is what the
            // run log reports as `size=`.
            width: Int(targetSize.width.rounded()),
            height: Int(targetSize.height.rounded()),
            averageFrameRate: normalizedFrameRate(frameRate),
            codecName: decodeResult.codecName,
            pixelFormatName: decodeResult.pixelFormatName,
            outputPixelFormatName: usesDirectNV12 ? "nv12" : "bgra",
            outputAudioTrackCount: audioContext?.didWriteAnySamples == true ? 1 : 0,
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

    private static func decodeMedia(
        sourceURL: URL,
        maximumFrameCount: Int32,
        videoContext: SW_AV1FrameWriterContext,
        nv12Context: SW_FFmpegNV12FrameOutputContext?,
        audioContext: SW_AV1AudioWriterContext?
    ) async throws -> DecodedVideoResult {
        guard let audioContext else {
            return try decode(
                sourceURL: sourceURL,
                maximumFrameCount: maximumFrameCount,
                context: videoContext,
                nv12Context: nv12Context
            )
        }

        let state = ConcurrentMediaDecodeState()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    state.attach(continuation)
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = Result {
                            try decode(
                                sourceURL: sourceURL,
                                maximumFrameCount: maximumFrameCount,
                                context: videoContext,
                                nv12Context: nv12Context
                            )
                        }
                        if case .failure = result {
                            audioContext.requestCancellation()
                        }
                        state.completeVideo(result)
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = Result {
                            try decodeAudio(sourceURL: sourceURL, context: audioContext)
                        }
                        if case .failure = result {
                            videoContext.requestCancellation()
                        }
                        state.completeAudio(result)
                    }
                }
            } onCancel: {
                videoContext.requestCancellation()
                audioContext.requestCancellation()
            }
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    private static func decode(
        sourceURL: URL,
        maximumFrameCount: Int32,
        context: SW_AV1FrameWriterContext,
        nv12Context: SW_FFmpegNV12FrameOutputContext?
    ) throws -> DecodedVideoResult {
        var result = TaptionFFmpegDecodeBridgeProbeResult()
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let status: Int32 = sourceURL.path.withCString { sourcePath in
            if let nv12Context {
                return taption_ffmpeg_decode_bridge_decode_video_to_nv12(
                    sourcePath,
                    maximumFrameCount,
                    ffmpegDecodeBridgeNV12AcquireCallback,
                    ffmpegDecodeBridgeNV12CommitCallback,
                    Unmanaged.passUnretained(nv12Context).toOpaque(),
                    &result,
                    &errorBuffer,
                    Int32(errorBuffer.count)
                )
            }
            return taption_ffmpeg_decode_bridge_decode_video_to_bgra(
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
        return DecodedVideoResult(
            frameCount: Int(result.frameCount),
            width: Int(result.width),
            height: Int(result.height),
            averageFrameRate: result.averageFrameRate,
            codecName: stringFromCStringBuffer(result.codecName),
            pixelFormatName: stringFromCStringBuffer(result.pixelFormatName)
        )
    }

    private static func probeAudioIfPresent(
        sourceURL: URL,
        preserveAudioWhenPossible: Bool
    ) throws -> TaptionFFmpegDecodeBridgeAudioProbeResult? {
        guard preserveAudioWhenPossible else { return nil }

        var result = TaptionFFmpegDecodeBridgeAudioProbeResult()
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let status = sourceURL.path.withCString { sourcePath in
            taption_ffmpeg_decode_bridge_probe_audio_s16(
                sourcePath,
                &result,
                &errorBuffer,
                Int32(errorBuffer.count)
            )
        }
        if status == -11 {
            return nil
        }
        guard status == 0 else {
            throw SW_FFmpegDecodeBridgeRunnerError.probeFailed(
                status: status,
                message: String(cString: errorBuffer)
            )
        }
        guard result.sampleRate > 0, result.channelCount > 0 else {
            throw SW_FFmpegDecodeBridgeRunnerError.writerStartFailed(
                "The audio probe reported an invalid sample rate or channel count."
            )
        }
        return result
    }

    private static func makeAudioConfiguration(
        probe: TaptionFFmpegDecodeBridgeAudioProbeResult,
        outputCodec: TaptionAudioCodec
    ) -> SW_AV1NativeAudioEncodingConfiguration {
        let sampleRate = Double(probe.sampleRate)
        let channelCount = Int(probe.channelCount)
        return SW_AV1NativeAudioEncodingConfiguration(
            sourceTrack: TaptionAudioTrackInfo(
                codec: .pcm,
                channelCount: channelCount,
                sampleRate: sampleRate
            ),
            outputCodec: outputCodec,
            sampleRate: sampleRate,
            channelCount: channelCount,
            targetBitrate: min(max(channelCount * 96_000, 96_000), 512_000)
        )
    }

    private static func decodeAudio(
        sourceURL: URL,
        context: SW_AV1AudioWriterContext
    ) throws {
        var result = TaptionFFmpegDecodeBridgeAudioProbeResult()
        var errorBuffer = [CChar](repeating: 0, count: 2_048)
        let status = sourceURL.path.withCString { sourcePath in
            taption_ffmpeg_decode_bridge_decode_audio_s16(
                sourcePath,
                ffmpegDecodeBridgeAudioFrameCallback,
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
        if let error = context.snapshotError() {
            throw error
        }
    }

    private static func writerVideoOutputSettings(
        targetSize: CGSize,
        targetBitrate: Int?,
        frameRate: Double,
        optimizationProfile: TaptionEncodingOptimizationProfile,
        color: TaptionColorDescription,
        pixelAspectRatioHorizontalSpacing: Int,
        pixelAspectRatioVerticalSpacing: Int
    ) -> [String: Any] {
        let width = max(2, Int(targetSize.width.rounded()))
        let height = max(2, Int(targetSize.height.rounded()))
        let estimatedBitrate = min(
            max(
                targetBitrate ?? Int(Double(width * height) * max(frameRate, 1) * 0.25),
                700_000
            ),
            200_000_000
        )
        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: estimatedBitrate,
            AVVideoExpectedSourceFrameRateKey: Int(max(frameRate.rounded(), 1)),
            AVVideoAllowFrameReorderingKey: false
        ]
        TaptionHEVCWriterPerformanceHints.apply(
            to: &compressionProperties,
            optimizationProfile: optimizationProfile
        )
        var outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        outputSettings[AVVideoCompressionPropertiesKey] = compressionProperties
        if let colorProperties = SW_AV1HEVCWriterColorProperties.make(for: color) {
            outputSettings[AVVideoColorPropertiesKey] = colorProperties
        }
        if let pixelAspectRatio = SW_FFmpegDecodeBridgeWriterMetadata.pixelAspectRatio(
            horizontalSpacing: pixelAspectRatioHorizontalSpacing,
            verticalSpacing: pixelAspectRatioVerticalSpacing
        ) {
            outputSettings[AVVideoPixelAspectRatioKey] = pixelAspectRatio
        }
        return outputSettings
    }

    private static func pixelBufferAttributes(
        size: CGSize,
        pixelFormat: OSType
    ) -> [String: Any] {
        var attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: max(2, Int(size.width.rounded())),
            kCVPixelBufferHeightKey as String: max(2, Int(size.height.rounded())),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        if pixelFormat == kCVPixelFormatType_32BGRA {
            attributes[kCVPixelBufferCGImageCompatibilityKey as String] = true
            attributes[kCVPixelBufferCGBitmapContextCompatibilityKey as String] = true
        }
        return attributes
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

    /// The frame to write, or `nil` when the source's own frame is already what was asked for.
    ///
    /// `nil` keeps the fast direct-NV12 path, which can only be used when the decoded picture and the written
    /// frame are the same size. A real resize therefore always goes through the BGRA path and is placed by
    /// `SW_AV1FrameWriterContext`, exactly as the VLC route does.
    private static func resizedTargetSize(
        _ requested: TaptionPixelSize?,
        sourceSize: CGSize,
        sourceDisplaySize: CGSize
    ) -> CGSize? {
        guard let requested,
              requested.isValid else {
            return nil
        }
        // HEVC codes whole 2×2 blocks and the writer pool cannot allocate an odd frame.
        let width = evenDimension(requested.width)
        let height = evenDimension(requested.height)
        // "Keep the source" reaches here as one of two sizes, because the plan fills its target from whichever
        // size the app measured: the coded frame or the shape the picture is shown with. Matching either one
        // means the frame must not change, so an anamorphic source keeps its width in the sample aspect ratio
        // instead of being written out as square pixels.
        for unchanged in [sourceSize, sourceDisplaySize]
        where width == Int(unchanged.width.rounded()) && height == Int(unchanged.height.rounded()) {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func evenDimension(_ value: Int) -> Int {
        let clamped = max(2, value)
        return clamped.isMultiple(of: 2) ? clamped : clamped - 1
    }

    /// The written frame rate and the fraction of decoded frames to keep to reach it.
    ///
    /// Only a ceiling can be honoured: the bridge has no frame to give when a higher rate is requested, and
    /// padding the tail (the legacy hold path) does not raise a rate either. A request at or above the source's
    /// rate therefore leaves the source rate alone.
    private static func outputFramePlan(
        sourceFrameRate: Double,
        requestedFrameRate: TaptionRationalFrameRate?
    ) -> (frameRate: Double, decimationRatio: Double) {
        guard let requestedFrameRate else {
            return (sourceFrameRate, 1)
        }
        let requested = requestedFrameRate.value
        guard requested.isFinite,
              requested >= 1,
              requested < sourceFrameRate else {
            return (sourceFrameRate, 1)
        }
        return (requested, requested / sourceFrameRate)
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

private nonisolated func ffmpegDecodeBridgeNV12OutputContext(
    from opaque: UnsafeMutableRawPointer?
) -> SW_FFmpegNV12FrameOutputContext? {
    guard let opaque else { return nil }
    return Unmanaged<SW_FFmpegNV12FrameOutputContext>.fromOpaque(opaque).takeUnretainedValue()
}

private nonisolated func ffmpegDecodeBridgeNV12AcquireCallback(
    _ frame: UnsafeMutablePointer<TaptionFFmpegDecodeBridgeWritableNV12Frame>?,
    _ opaque: UnsafeMutableRawPointer?
) -> Int32 {
    guard let frame,
          let context = ffmpegDecodeBridgeNV12OutputContext(from: opaque) else {
        return -1
    }
    return context.acquire(frame)
}

private nonisolated func ffmpegDecodeBridgeNV12CommitCallback(
    _ frame: UnsafeMutablePointer<TaptionFFmpegDecodeBridgeWritableNV12Frame>?,
    _ opaque: UnsafeMutableRawPointer?
) -> Int32 {
    guard let frame,
          let context = ffmpegDecodeBridgeNV12OutputContext(from: opaque) else {
        return -1
    }
    return context.commit(frame)
}

private nonisolated func ffmpegDecodeBridgeFrameCallback(
    _ frame: UnsafePointer<TaptionFFmpegDecodeBridgeFrame>?,
    _ opaque: UnsafeMutableRawPointer?
) -> Int32 {
    guard let frame,
          let context = ffmpegDecodeBridgeFrameWriterContext(from: opaque),
          !context.shouldAbort,
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

    if sourceBytesPerRow == destinationBytesPerRow,
       bytesPerRowToCopy == sourceBytesPerRow,
       height == CVPixelBufferGetHeight(pixelBuffer) {
        memcpy(destinationBaseAddress, sourceBaseAddress, sourceBytesPerRow * height)
    } else {
        for row in 0..<height {
            let sourceRow = sourceBaseAddress.advanced(by: row * sourceBytesPerRow)
            let destinationRow = destinationBaseAddress.advanced(by: row * destinationBytesPerRow)
            memcpy(destinationRow, sourceRow, bytesPerRowToCopy)
        }
    }

    context.appendDecodedPixelBuffer(pixelBuffer)
    return 0
}

private nonisolated func ffmpegDecodeBridgeAudioFrameCallback(
    _ frame: UnsafePointer<TaptionFFmpegDecodeBridgeAudioFrame>?,
    _ opaque: UnsafeMutableRawPointer?
) -> Int32 {
    guard let frame,
          let opaque,
          let samples = frame.pointee.interleavedS16Samples,
          frame.pointee.sampleCount > 0 else {
        return -1
    }
    let context = Unmanaged<SW_AV1AudioWriterContext>.fromOpaque(opaque).takeUnretainedValue()
    guard !context.shouldAbort,
          frame.pointee.sampleRate == context.sampleRate,
          frame.pointee.channelCount == context.channelCount else {
        return -2
    }
    let ptsMicroseconds = Int64(max(frame.pointee.ptsSeconds, 0) * 1_000_000)
    context.appendAudioSamples(
        samples,
        sampleCount: UInt32(frame.pointee.sampleCount),
        ptsMicroseconds: ptsMicroseconds
    )
    return context.shouldAbort ? -3 : 0
}
#endif
