import Foundation

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
        outputContainer: TaptionVideoContainer = .mkv,
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
        outputContainer: TaptionVideoContainer = .mkv,
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
        outputContainer: TaptionVideoContainer = .mkv,
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
        outputContainer: TaptionVideoContainer = .mkv,
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
