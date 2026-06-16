import Foundation

enum TaptionCodecFixtureEvidenceMode: String, Codable, Equatable, CaseIterable {
    case softwareHEVC = "SW_HEVC"
    case hardwareHEVC = "HW_HEVC"
}

enum TaptionCodecFixtureEvidenceStatus: String, Codable, Equatable {
    case pass = "PASS"
    case fail = "FAIL"
    case skip = "SKIP"
}

enum TaptionAudioFixtureGenerationStatus: String, Codable, Equatable {
    case pass = "PASS"
    case fail = "FAIL"
    case skip = "SKIP"
}

struct TaptionCodecFixtureEvidenceRow: Codable, Equatable {
    var name: String
    var mode: TaptionCodecFixtureEvidenceMode
    var status: TaptionCodecFixtureEvidenceStatus
    var sourceFile: String
    var outputFile: String
    var outputVideoCodec: String
    var sourceAudioStreams: Int
    var outputAudioStreams: Int
    var audioStatus: String
    var sourceAudioPeakDB: String
    var outputAudioPeakDB: String
    var elapsedSeconds: Int
    var message: String

    var hasSourceAudio: Bool {
        sourceAudioStreams > 0
    }

    var provesHEVCOutputWithAudioSignal: Bool {
        guard status == .pass, outputVideoCodec == "hevc" else {
            return false
        }
        guard hasSourceAudio else {
            return true
        }
        return outputAudioStreams > 0 && audioStatus == "SIGNAL_PASS"
    }
}

struct TaptionCodecFixtureEvidenceSummary: Codable, Equatable {
    var fixtureCount: Int
    var verifiedTranscodeCount: Int
    var verifiedAudioSignalCount: Int
    var noSourceAudioAttemptCount: Int
    var failures: [String]

    var isPassing: Bool {
        failures.isEmpty
    }
}

struct TaptionCodecFixtureExecutionEvidenceSummary: Codable, Equatable {
    var jobCount: Int
    var verifiedModeCount: Int
    var verifiedAudioSignalModeCount: Int
    var noSourceAudioModeCount: Int
    var failures: [String]

    var isPassing: Bool {
        failures.isEmpty
    }
}

struct TaptionVideoFixtureAllToAllCommandPlanCoverageSummary: Codable, Equatable {
    var sourceFixtureCount: Int
    var sourceCodecCount: Int
    var outputCodecCount: Int
    var expectedJobCount: Int
    var plannedJobCount: Int
    var expectedRouteCount: Int
    var plannedRouteCount: Int
    var outputCodecs: [TaptionVideoCodec]
    var missingRoutes: [TaptionCodecRoute]
    var duplicateJobIDs: [String]
    var failures: [String]

    var isComplete: Bool {
        plannedJobCount == expectedJobCount
            && plannedRouteCount == expectedRouteCount
            && missingRoutes.isEmpty
            && duplicateJobIDs.isEmpty
    }

    var isPassing: Bool {
        failures.isEmpty
    }
}

struct TaptionAudioFixtureAllToAllCommandPlanCoverageSummary: Codable, Equatable {
    var sourceFixtureCount: Int
    var sourceCodecCount: Int
    var outputCodecCount: Int
    var expectedJobCount: Int
    var plannedJobCount: Int
    var expectedRouteCount: Int
    var plannedRouteCount: Int
    var outputCodecs: [TaptionAudioCodec]
    var missingRoutes: [TaptionAudioCodecRoute]
    var duplicateJobIDs: [String]
    var failures: [String]

    var isComplete: Bool {
        plannedJobCount == expectedJobCount
            && plannedRouteCount == expectedRouteCount
            && missingRoutes.isEmpty
            && duplicateJobIDs.isEmpty
    }

    var isPassing: Bool {
        failures.isEmpty
    }
}

struct TaptionAudioFixtureGenerationRow: Codable, Equatable {
    var name: String
    var file: String
    var targetAudioCodec: TaptionAudioCodec
    var audioEncoder: String
    var status: TaptionAudioFixtureGenerationStatus
    var message: String
}

struct TaptionAudioFixtureGenerationSummary: Codable, Equatable {
    var coveredCodecCount: Int
    var pendingCodecCount: Int
    var generatedCodecs: [TaptionAudioCodec]
    var pendingAttemptCodecs: [TaptionAudioCodec]
    var pendingAttemptNames: [String]
    var failures: [String]

    var isPassing: Bool {
        failures.isEmpty
    }
}

struct TaptionAudioFixtureCatalogCoverageSummary: Codable, Equatable {
    var universalAudioCodecCount: Int
    var trackedUniversalAudioCodecCount: Int
    var generatedFixtureAudioCodecCount: Int
    var pendingFixtureAudioCodecCount: Int
    var generatedAudioCodecs: [TaptionAudioCodec]
    var pendingAudioCodecs: [TaptionAudioCodec]
    var untrackedUniversalAudioCodecs: [TaptionAudioCodec]
    var fixtureOnlyAudioCodecs: [TaptionAudioCodec]
    var failures: [String]

    var universalFixtureTrackingIsComplete: Bool {
        untrackedUniversalAudioCodecs.isEmpty
            && fixtureOnlyAudioCodecs.isEmpty
    }

    var isPassing: Bool {
        failures.isEmpty
    }
}

enum TaptionRouteMatrixPriority: String, Codable, Equatable {
    case hardware
    case softwareOrUnavailable = "software_or_unavailable"
}

struct TaptionRouteMatrixEvidenceRow: Codable, Equatable {
    var profile: String
    var sourceCodec: TaptionVideoCodec
    var outputCodec: TaptionVideoCodec
    var support: TaptionCodecRouteSupport
    var path: TaptionCodecRouteExecutionKind
    var selectedMode: TaptionEncoderMode
    var decodeBackend: TaptionEncodingBackend?
    var encodeBackend: TaptionEncodingBackend?
    var expectedDecodePriority: TaptionRouteMatrixPriority
    var expectedEncodePriority: TaptionRouteMatrixPriority
    var encodableNow: Bool
    var reason: String

    var route: TaptionCodecRoute {
        TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
    }
}

struct TaptionRouteMatrixEvidenceSummary: Codable, Equatable {
    var profileCount: Int
    var rowCount: Int
    var implementedRowCount: Int
    var plannedRowCount: Int
    var failures: [String]

    var isPassing: Bool {
        failures.isEmpty
    }
}

struct TaptionVideoFixtureManifestRow: Codable, Equatable {
    var name: String
    var file: String
    var videoEncoder: String
    var audioEncoder: String
    var videoCodec: TaptionVideoCodec
    var audioCodec: TaptionAudioCodec
    var container: TaptionVideoContainer
}

struct TaptionVideoFixtureGenerationRow: Codable, Equatable {
    var name: String
    var file: String
    var videoEncoder: String
    var audioEncoder: String
    var status: TaptionCodecFixtureEvidenceStatus
    var message: String
}

struct TaptionVideoFixtureManifestSummary: Codable, Equatable {
    var fixtureCount: Int
    var coveredVideoCodecs: Set<TaptionVideoCodec>
    var coveredAudioCodecs: Set<TaptionAudioCodec>
    var coveredContainers: Set<TaptionVideoContainer>
    var failures: [String]

    var isPassing: Bool {
        failures.isEmpty
    }
}

struct TaptionVideoFixtureGenerationSummary: Codable, Equatable {
    var passCount: Int
    var skipCount: Int
    var failCount: Int
    var implementedTargetCount: Int
    var implementedPassCount: Int
    var optionalAttemptCount: Int
    var optionalAttemptNames: [String]
    var failures: [String]

    var isPassing: Bool {
        failures.isEmpty
    }
}

struct TaptionVideoFixtureCatalogCoverageSummary: Codable, Equatable {
    var universalVideoCodecCount: Int
    var trackedUniversalVideoCodecCount: Int
    var implementedFixtureVideoCodecCount: Int
    var conditionalFixtureVideoCodecCount: Int
    var realWorldSampleRequiredVideoCodecCount: Int
    var plannedFixtureVideoCodecCount: Int
    var implementedVideoCodecs: [TaptionVideoCodec]
    var conditionalVideoCodecs: [TaptionVideoCodec]
    var realWorldSampleRequiredVideoCodecs: [TaptionVideoCodec]
    var plannedVideoCodecs: [TaptionVideoCodec]
    var untrackedUniversalVideoCodecs: [TaptionVideoCodec]
    var fixtureOnlyVideoCodecs: [TaptionVideoCodec]
    var duplicateFixtureTargetNames: [String]
    var failures: [String]

    var universalFixtureTrackingIsComplete: Bool {
        untrackedUniversalVideoCodecs.isEmpty
            && fixtureOnlyVideoCodecs.isEmpty
    }

    var isPassing: Bool {
        failures.isEmpty
    }
}

struct TaptionVideoContainerFixtureCoverageSummary: Codable, Equatable {
    var expectedContainerCount: Int
    var trackedContainerCount: Int
    var readableContainerCount: Int
    var writableContainerCount: Int
    var trackedContainers: [TaptionVideoContainer]
    var missingExpectedContainers: [TaptionVideoContainer]
    var fixtureOnlyContainers: [TaptionVideoContainer]
    var missingReadableContainers: [TaptionVideoContainer]
    var missingWritableContainers: [TaptionVideoContainer]
    var extensionAliasCount: Int
    var extensionRoundTripFailures: [String]
    var failures: [String]

    var fixtureTrackingIsComplete: Bool {
        missingExpectedContainers.isEmpty
            && fixtureOnlyContainers.isEmpty
            && missingReadableContainers.isEmpty
    }

    var isPassing: Bool {
        failures.isEmpty
    }
}

enum TaptionCodecFixtureEvidenceError: LocalizedError, Equatable {
    case missingColumn(String)
    case invalidRow(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingColumn(let column):
            return "Codec fixture evidence is missing the \(column) column."
        case .invalidRow(let line, let reason):
            return "Codec fixture evidence line \(line) is invalid: \(reason)"
        }
    }
}

enum TaptionCodecFixtureEvidence {
    static let requiredModes: [TaptionCodecFixtureEvidenceMode] = [
        .softwareHEVC,
        .hardwareHEVC
    ]

    static func parseTranscodeResultsTSV(_ text: String) throws -> [TaptionCodecFixtureEvidenceRow] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let header = lines.first else {
            return []
        }
        let columns = header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let indexByColumn = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element, $0.offset) })
        let requiredColumns = [
            "name",
            "mode",
            "status",
            "source_file",
            "output_file",
            "output_video_codec",
            "source_audio_streams",
            "output_audio_streams",
            "audio_status",
            "source_audio_peak_db",
            "output_audio_peak_db",
            "elapsed_seconds",
            "message"
        ]

        for column in requiredColumns where indexByColumn[column] == nil {
            throw TaptionCodecFixtureEvidenceError.missingColumn(column)
        }

        return try lines.dropFirst().enumerated().compactMap { offset, line in
            let lineNumber = offset + 2
            let values = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard values.contains(where: { !$0.isEmpty }) else {
                return nil
            }

            func value(_ column: String) throws -> String {
                guard let index = indexByColumn[column], index < values.count else {
                    throw TaptionCodecFixtureEvidenceError.invalidRow(lineNumber, "missing \(column)")
                }
                return values[index]
            }

            guard let mode = TaptionCodecFixtureEvidenceMode(rawValue: try value("mode")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown mode \(try value("mode"))"
                )
            }
            guard let status = TaptionCodecFixtureEvidenceStatus(rawValue: try value("status")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown status \(try value("status"))"
                )
            }

            return TaptionCodecFixtureEvidenceRow(
                name: try value("name"),
                mode: mode,
                status: status,
                sourceFile: try value("source_file"),
                outputFile: try value("output_file"),
                outputVideoCodec: try value("output_video_codec"),
                sourceAudioStreams: Int(try value("source_audio_streams")) ?? 0,
                outputAudioStreams: Int(try value("output_audio_streams")) ?? 0,
                audioStatus: try value("audio_status"),
                sourceAudioPeakDB: try value("source_audio_peak_db"),
                outputAudioPeakDB: try value("output_audio_peak_db"),
                elapsedSeconds: Int(try value("elapsed_seconds")) ?? 0,
                message: try value("message")
            )
        }
    }

    static func parseFixtureNamesTSV(_ text: String) -> Set<String> {
        Set(text
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line in
                line.split(separator: "\t", omittingEmptySubsequences: false).first.map(String.init)
            }
            .filter { !$0.isEmpty })
    }

    static func parseVideoFixtureManifestTSV(_ text: String) throws -> [TaptionVideoFixtureManifestRow] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let header = lines.first else {
            return []
        }
        let columns = header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let indexByColumn = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element, $0.offset) })
        let requiredColumns = [
            "name",
            "file",
            "video_encoder",
            "audio_encoder"
        ]

        for column in requiredColumns where indexByColumn[column] == nil {
            throw TaptionCodecFixtureEvidenceError.missingColumn(column)
        }

        return try lines.dropFirst().enumerated().compactMap { offset, line in
            let lineNumber = offset + 2
            let values = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard values.contains(where: { !$0.isEmpty }) else {
                return nil
            }

            func value(_ column: String) throws -> String {
                guard let index = indexByColumn[column], index < values.count else {
                    throw TaptionCodecFixtureEvidenceError.invalidRow(lineNumber, "missing \(column)")
                }
                return values[index]
            }

            let file = try value("file")
            let videoEncoder = try value("video_encoder")
            let audioEncoder = try value("audio_encoder")
            guard let videoCodec = videoCodec(forEncoder: videoEncoder) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown video encoder \(videoEncoder)"
                )
            }
            guard let audioCodec = audioCodec(forEncoder: audioEncoder) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown audio encoder \(audioEncoder)"
                )
            }
            guard let container = container(forFileName: file) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown fixture file extension \(file)"
                )
            }

            return TaptionVideoFixtureManifestRow(
                name: try value("name"),
                file: file,
                videoEncoder: videoEncoder,
                audioEncoder: audioEncoder,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                container: container
            )
        }
    }

    static func parseVideoFixtureGenerationTSV(_ text: String) throws -> [TaptionVideoFixtureGenerationRow] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let header = lines.first else {
            return []
        }
        let columns = header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let indexByColumn = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element, $0.offset) })
        let requiredColumns = [
            "name",
            "file",
            "video_encoder",
            "audio_encoder",
            "status",
            "message"
        ]

        for column in requiredColumns where indexByColumn[column] == nil {
            throw TaptionCodecFixtureEvidenceError.missingColumn(column)
        }

        return try lines.dropFirst().enumerated().compactMap { offset, line in
            let lineNumber = offset + 2
            let values = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard values.contains(where: { !$0.isEmpty }) else {
                return nil
            }

            func value(_ column: String) throws -> String {
                guard let index = indexByColumn[column], index < values.count else {
                    throw TaptionCodecFixtureEvidenceError.invalidRow(lineNumber, "missing \(column)")
                }
                return values[index]
            }

            guard let status = TaptionCodecFixtureEvidenceStatus(rawValue: try value("status")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown status \(try value("status"))"
                )
            }

            return TaptionVideoFixtureGenerationRow(
                name: try value("name"),
                file: try value("file"),
                videoEncoder: try value("video_encoder"),
                audioEncoder: try value("audio_encoder"),
                status: status,
                message: try value("message")
            )
        }
    }

    static func parseAudioFixtureGenerationTSV(
        _ text: String
    ) throws -> [TaptionAudioFixtureGenerationRow] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let header = lines.first else {
            return []
        }
        let columns = header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let indexByColumn = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element, $0.offset) })
        let requiredColumns = [
            "name",
            "file",
            "target_audio_codec",
            "audio_encoder",
            "status",
            "message"
        ]

        for column in requiredColumns where indexByColumn[column] == nil {
            throw TaptionCodecFixtureEvidenceError.missingColumn(column)
        }

        return try lines.dropFirst().enumerated().compactMap { offset, line in
            let lineNumber = offset + 2
            let values = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard values.contains(where: { !$0.isEmpty }) else {
                return nil
            }

            func value(_ column: String) throws -> String {
                guard let index = indexByColumn[column], index < values.count else {
                    throw TaptionCodecFixtureEvidenceError.invalidRow(lineNumber, "missing \(column)")
                }
                return values[index]
            }

            guard let targetAudioCodec = TaptionAudioCodec(rawValue: try value("target_audio_codec")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown target audio codec \(try value("target_audio_codec"))"
                )
            }
            guard let status = TaptionAudioFixtureGenerationStatus(rawValue: try value("status")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown status \(try value("status"))"
                )
            }

            return TaptionAudioFixtureGenerationRow(
                name: try value("name"),
                file: try value("file"),
                targetAudioCodec: targetAudioCodec,
                audioEncoder: try value("audio_encoder"),
                status: status,
                message: try value("message")
            )
        }
    }

    static func parseRouteMatrixTSV(_ text: String) throws -> [TaptionRouteMatrixEvidenceRow] {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard let header = lines.first else {
            return []
        }
        let columns = header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let indexByColumn = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($0.element, $0.offset) })
        let requiredColumns = [
            "profile",
            "source_codec",
            "output_codec",
            "support",
            "path",
            "selected_mode",
            "decode_backend",
            "encode_backend",
            "expected_decode_priority",
            "expected_encode_priority",
            "encodable_now",
            "reason"
        ]

        for column in requiredColumns where indexByColumn[column] == nil {
            throw TaptionCodecFixtureEvidenceError.missingColumn(column)
        }

        return try lines.dropFirst().enumerated().compactMap { offset, line in
            let lineNumber = offset + 2
            let values = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard values.contains(where: { !$0.isEmpty }) else {
                return nil
            }

            func value(_ column: String) throws -> String {
                guard let index = indexByColumn[column], index < values.count else {
                    throw TaptionCodecFixtureEvidenceError.invalidRow(lineNumber, "missing \(column)")
                }
                return values[index]
            }

            guard let sourceCodec = TaptionVideoCodec(rawValue: try value("source_codec")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown source codec \(try value("source_codec"))"
                )
            }
            guard let outputCodec = TaptionVideoCodec(rawValue: try value("output_codec")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown output codec \(try value("output_codec"))"
                )
            }
            guard let support = TaptionCodecRouteSupport(rawValue: try value("support")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown support \(try value("support"))"
                )
            }
            guard let path = TaptionCodecRouteExecutionKind(rawValue: try value("path")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown path \(try value("path"))"
                )
            }
            guard let selectedMode = TaptionEncoderMode(rawValue: try value("selected_mode")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown selected mode \(try value("selected_mode"))"
                )
            }
            guard let expectedDecodePriority = TaptionRouteMatrixPriority(rawValue: try value("expected_decode_priority")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown expected decode priority \(try value("expected_decode_priority"))"
                )
            }
            guard let expectedEncodePriority = TaptionRouteMatrixPriority(rawValue: try value("expected_encode_priority")) else {
                throw TaptionCodecFixtureEvidenceError.invalidRow(
                    lineNumber,
                    "unknown expected encode priority \(try value("expected_encode_priority"))"
                )
            }

            return TaptionRouteMatrixEvidenceRow(
                profile: try value("profile"),
                sourceCodec: sourceCodec,
                outputCodec: outputCodec,
                support: support,
                path: path,
                selectedMode: selectedMode,
                decodeBackend: TaptionEncodingBackend(rawValue: try value("decode_backend")),
                encodeBackend: TaptionEncodingBackend(rawValue: try value("encode_backend")),
                expectedDecodePriority: expectedDecodePriority,
                expectedEncodePriority: expectedEncodePriority,
                encodableNow: try value("encodable_now") == "true",
                reason: try value("reason")
            )
        }
    }

    static func verify(
        rows: [TaptionCodecFixtureEvidenceRow],
        fixtureNames: Set<String> = [],
        requiredModes: [TaptionCodecFixtureEvidenceMode] = Self.requiredModes
    ) -> TaptionCodecFixtureEvidenceSummary {
        var allFixtureNames = Set(rows.map(\.name))
        allFixtureNames.formUnion(fixtureNames)
        var rowByKey: [String: TaptionCodecFixtureEvidenceRow] = [:]
        for row in rows {
            rowByKey[key(name: row.name, mode: row.mode)] = row
        }

        var failures: [String] = []
        if allFixtureNames.isEmpty {
            failures.append("No codec fixture evidence rows were found.")
        }

        var verifiedCount = 0
        var verifiedAudioSignalCount = 0
        var noSourceAudioAttemptCount = 0
        for name in allFixtureNames.sorted() {
            for mode in requiredModes {
                guard let row = rowByKey[key(name: name, mode: mode)] else {
                    failures.append("\(name) \(mode.rawValue) is missing.")
                    continue
                }
                if row.provesHEVCOutputWithAudioSignal {
                    verifiedCount += 1
                    if row.hasSourceAudio {
                        verifiedAudioSignalCount += 1
                    } else {
                        noSourceAudioAttemptCount += 1
                    }
                } else {
                    failures.append(
                        "\(name) \(mode.rawValue) did not prove H.265 output with preserved audio signal: \(row.message)"
                    )
                }
            }
        }

        return TaptionCodecFixtureEvidenceSummary(
            fixtureCount: allFixtureNames.count,
            verifiedTranscodeCount: verifiedCount,
            verifiedAudioSignalCount: verifiedAudioSignalCount,
            noSourceAudioAttemptCount: noSourceAudioAttemptCount,
            failures: failures
        )
    }

    static func verifyExecutionJobsHaveLatestH265Evidence(
        jobs: [TaptionCodecFixtureExecutionJob],
        rows: [TaptionCodecFixtureEvidenceRow],
        requiredModes: [TaptionCodecFixtureEvidenceMode] = Self.requiredModes
    ) -> TaptionCodecFixtureExecutionEvidenceSummary {
        var failures: [String] = []
        var rowByKey: [String: TaptionCodecFixtureEvidenceRow] = [:]
        for row in rows {
            rowByKey[key(name: row.name, mode: row.mode)] = row
        }

        if jobs.isEmpty {
            failures.append("No app-core fixture execution jobs were found.")
        }

        var seenJobIDs = Set<String>()
        var verifiedModeCount = 0
        var verifiedAudioSignalModeCount = 0
        var noSourceAudioModeCount = 0

        for job in jobs.sorted(by: { $0.id < $1.id }) {
            if !seenJobIDs.insert(job.id).inserted {
                failures.append("\(job.id) is duplicated in app-core fixture execution jobs.")
            }
            if job.sourceURL.lastPathComponent.isEmpty {
                failures.append("\(job.id) has an empty source file name.")
            }
            if job.commandPlan.sourceURL != job.sourceURL {
                failures.append("\(job.id) command source URL does not match the job source URL.")
            }
            if job.commandPlan.outputURL != job.outputURL {
                failures.append("\(job.id) command output URL does not match the job output URL.")
            }
            if job.kind == .videoToHEVC, job.outputVideoCodec != .hevc {
                failures.append("\(job.id) is not targeting H.265 output.")
            }
            if job.kind == .audioToAAC, job.outputAudioCodec != .aac {
                failures.append("\(job.id) is not targeting AAC audio output.")
            }

            for mode in requiredModes {
                guard let row = rowByKey[key(name: job.fixtureName, mode: mode)] else {
                    failures.append("\(job.fixtureName) \(mode.rawValue) is missing for app-core job \(job.id).")
                    continue
                }
                if row.sourceFile != job.sourceURL.lastPathComponent {
                    failures.append(
                        "\(job.id) \(mode.rawValue) source file mismatch: evidence has \(row.sourceFile), job has \(job.sourceURL.lastPathComponent)."
                    )
                }
                guard row.provesHEVCOutputWithAudioSignal else {
                    failures.append(
                        "\(job.id) \(mode.rawValue) did not prove H.265 output with preserved audio signal: \(row.message)"
                    )
                    continue
                }

                verifiedModeCount += 1
                if job.requiresAudioSignalVerification {
                    if !row.hasSourceAudio {
                        failures.append("\(job.id) \(mode.rawValue) expected source audio but evidence has none.")
                    } else if row.audioStatus == "SIGNAL_PASS", row.outputAudioStreams > 0 {
                        verifiedAudioSignalModeCount += 1
                    } else {
                        failures.append("\(job.id) \(mode.rawValue) did not prove output audio signal.")
                    }
                } else {
                    if row.hasSourceAudio {
                        failures.append("\(job.id) \(mode.rawValue) expected no source audio but evidence has audio.")
                    } else if row.audioStatus == "NO_SOURCE_AUDIO" {
                        noSourceAudioModeCount += 1
                    }
                }
            }
        }

        return TaptionCodecFixtureExecutionEvidenceSummary(
            jobCount: jobs.count,
            verifiedModeCount: verifiedModeCount,
            verifiedAudioSignalModeCount: verifiedAudioSignalModeCount,
            noSourceAudioModeCount: noSourceAudioModeCount,
            failures: failures
        )
    }

    static func verifyVideoFixtureAllToAllCommandPlanCoverage(
        jobs: [TaptionCodecFixtureExecutionJob],
        sourceRows: [TaptionVideoFixtureManifestRow],
        outputCodecs: [TaptionVideoCodec] = SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs,
        outputContainer: TaptionVideoContainer = .mkv
    ) -> TaptionVideoFixtureAllToAllCommandPlanCoverageSummary {
        let sourceCodecs = Set(sourceRows.map(\.videoCodec))
        let expectedRoutes = Set(sourceCodecs.flatMap { sourceCodec in
            outputCodecs.map { outputCodec in
                TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
            }
        })
        let plannedRoutes = Set(jobs.compactMap { job -> TaptionCodecRoute? in
            guard let sourceCodec = job.sourceVideoCodec,
                  let outputCodec = job.outputVideoCodec else {
                return nil
            }
            return TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
        })
        let duplicateJobIDs = duplicateIDs(in: jobs.map(\.id))
        let missingRoutes = expectedRoutes.subtracting(plannedRoutes)
        var failures: [String] = []

        if sourceRows.isEmpty {
            failures.append("No video fixture source rows were found.")
        }
        if outputCodecs.isEmpty {
            failures.append("No plannable video output codecs were found.")
        }
        if jobs.count != sourceRows.count * outputCodecs.count {
            failures.append(
                "Expected \(sourceRows.count * outputCodecs.count) video all-to-all command-plan jobs, got \(jobs.count)."
            )
        }
        if !duplicateJobIDs.isEmpty {
            failures.append("Video all-to-all command-plan jobs have duplicate IDs: \(duplicateJobIDs.joined(separator: ", "))")
        }
        if !missingRoutes.isEmpty {
            failures.append(
                "Video all-to-all command plans are missing routes: \(sortRoutes(missingRoutes).map(\.displayName).joined(separator: ", "))"
            )
        }

        for job in jobs {
            if job.kind != .videoCodecTranscode {
                failures.append("\(job.id) is not a video all-to-all transcode job.")
            }
            guard let outputCodec = job.outputVideoCodec else {
                failures.append("\(job.id) has no output video codec.")
                continue
            }
            guard outputCodecs.contains(outputCodec) else {
                failures.append("\(job.id) targets non-plannable video output \(outputCodec.rawValue).")
                continue
            }
            if job.outputURL.pathExtension != outputContainer.defaultFileExtension {
                failures.append("\(job.id) output container expected \(outputContainer.defaultFileExtension), got \(job.outputURL.pathExtension).")
            }
            guard let encoderName = SW_FFmpegCodecCommandPlanner.videoEncoderName(for: outputCodec) else {
                failures.append("\(job.id) has no FFmpeg-family encoder for \(outputCodec.rawValue).")
                continue
            }
            if !job.commandPlan.arguments.contains(encoderName) {
                failures.append("\(job.id) command plan is missing video encoder \(encoderName).")
            }
        }

        return TaptionVideoFixtureAllToAllCommandPlanCoverageSummary(
            sourceFixtureCount: sourceRows.count,
            sourceCodecCount: sourceCodecs.count,
            outputCodecCount: outputCodecs.count,
            expectedJobCount: sourceRows.count * outputCodecs.count,
            plannedJobCount: jobs.count,
            expectedRouteCount: expectedRoutes.count,
            plannedRouteCount: plannedRoutes.intersection(expectedRoutes).count,
            outputCodecs: sortVideoCodecs(Set(outputCodecs)),
            missingRoutes: sortRoutes(missingRoutes),
            duplicateJobIDs: duplicateJobIDs,
            failures: failures
        )
    }

    static func verifyAudioFixtureAllToAllCommandPlanCoverage(
        jobs: [TaptionCodecFixtureExecutionJob],
        sourceRows: [TaptionAudioFixtureGenerationRow],
        outputCodecs: [TaptionAudioCodec] = SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs,
        outputContainer: TaptionVideoContainer = .mkv
    ) -> TaptionAudioFixtureAllToAllCommandPlanCoverageSummary {
        let generatedRows = sourceRows.filter { $0.status == .pass }
        let sourceCodecs = Set(generatedRows.map(\.targetAudioCodec))
        let expectedRoutes = Set(sourceCodecs.flatMap { sourceCodec in
            outputCodecs.map { outputCodec in
                TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
            }
        })
        let plannedRoutes = Set(jobs.compactMap { job -> TaptionAudioCodecRoute? in
            guard let sourceCodec = job.sourceAudioCodec,
                  let outputCodec = job.outputAudioCodec else {
                return nil
            }
            return TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
        })
        let duplicateJobIDs = duplicateIDs(in: jobs.map(\.id))
        let missingRoutes = expectedRoutes.subtracting(plannedRoutes)
        var failures: [String] = []

        if generatedRows.isEmpty {
            failures.append("No generated audio fixture source rows were found.")
        }
        if outputCodecs.isEmpty {
            failures.append("No plannable audio output codecs were found.")
        }
        if jobs.count != generatedRows.count * outputCodecs.count {
            failures.append(
                "Expected \(generatedRows.count * outputCodecs.count) audio all-to-all command-plan jobs, got \(jobs.count)."
            )
        }
        if !duplicateJobIDs.isEmpty {
            failures.append("Audio all-to-all command-plan jobs have duplicate IDs: \(duplicateJobIDs.joined(separator: ", "))")
        }
        if !missingRoutes.isEmpty {
            failures.append(
                "Audio all-to-all command plans are missing routes: \(sortAudioRoutes(missingRoutes).map(\.displayName).joined(separator: ", "))"
            )
        }

        for job in jobs {
            if job.kind != .audioCodecTranscode {
                failures.append("\(job.id) is not an audio all-to-all transcode job.")
            }
            guard let sourceCodec = job.sourceAudioCodec,
                  let outputCodec = job.outputAudioCodec else {
                failures.append("\(job.id) has incomplete audio codec metadata.")
                continue
            }
            guard outputCodecs.contains(outputCodec) else {
                failures.append("\(job.id) targets non-plannable audio output \(outputCodec.rawValue).")
                continue
            }
            if job.outputURL.pathExtension != outputContainer.defaultFileExtension {
                failures.append("\(job.id) output container expected \(outputContainer.defaultFileExtension), got \(job.outputURL.pathExtension).")
            }
            let expectedEncoder = sourceCodec == outputCodec
                ? "copy"
                : SW_FFmpegCodecCommandPlanner.audioEncoderName(for: outputCodec)
            guard let expectedEncoder else {
                failures.append("\(job.id) has no FFmpeg-family encoder for \(outputCodec.rawValue).")
                continue
            }
            if !job.commandPlan.arguments.contains(expectedEncoder) {
                failures.append("\(job.id) command plan is missing audio encoder \(expectedEncoder).")
            }
        }

        return TaptionAudioFixtureAllToAllCommandPlanCoverageSummary(
            sourceFixtureCount: generatedRows.count,
            sourceCodecCount: sourceCodecs.count,
            outputCodecCount: outputCodecs.count,
            expectedJobCount: generatedRows.count * outputCodecs.count,
            plannedJobCount: jobs.count,
            expectedRouteCount: expectedRoutes.count,
            plannedRouteCount: plannedRoutes.intersection(expectedRoutes).count,
            outputCodecs: sortAudioCodecs(Set(outputCodecs)),
            missingRoutes: sortAudioRoutes(missingRoutes),
            duplicateJobIDs: duplicateJobIDs,
            failures: failures
        )
    }

    static func verifyRouteMatrix(
        rows: [TaptionRouteMatrixEvidenceRow],
        expectedProfiles: Set<String> = Set(TaptionCodecHardwareSupportProfile.simulationProfiles.map(\.name)),
        expectedRoutes: Set<TaptionCodecRoute> = TaptionCodecRegistry.plannedUniversalRoutes,
        implementedRoutes: Set<TaptionCodecRoute> = TaptionCodecRegistry.implementedRoutes
    ) -> TaptionRouteMatrixEvidenceSummary {
        var failures: [String] = []
        let profileNames = Set(rows.map(\.profile))
        let expectedRowCount = expectedProfiles.count * expectedRoutes.count

        if rows.isEmpty {
            failures.append("No route matrix rows were found.")
        }
        if profileNames != expectedProfiles {
            let missing = expectedProfiles.subtracting(profileNames).sorted()
            let extra = profileNames.subtracting(expectedProfiles).sorted()
            if !missing.isEmpty {
                failures.append("Route matrix is missing profiles: \(missing.joined(separator: ", "))")
            }
            if !extra.isEmpty {
                failures.append("Route matrix has unexpected profiles: \(extra.joined(separator: ", "))")
            }
        }
        if rows.count != expectedRowCount {
            failures.append("Route matrix expected \(expectedRowCount) rows, got \(rows.count).")
        }

        var seenKeys = Set<String>()
        for row in rows {
            let key = "\(row.profile)\u{1F}\(row.sourceCodec.rawValue)\u{1F}\(row.outputCodec.rawValue)"
            if !seenKeys.insert(key).inserted {
                failures.append("Route matrix contains duplicate row for \(row.profile) \(row.sourceCodec.rawValue) -> \(row.outputCodec.rawValue).")
            }
            if row.support == .unsupported {
                failures.append("\(row.profile) \(row.route.displayName) is unsupported in route matrix evidence.")
            }
            if row.expectedDecodePriority == .hardware,
               row.decodeBackend != .appleAVAssetExport {
                failures.append("\(row.profile) \(row.route.displayName) did not prefer hardware decode.")
            }
            if row.expectedEncodePriority == .hardware,
               row.encodeBackend != .appleVideoToolbox {
                failures.append("\(row.profile) \(row.route.displayName) did not prefer hardware encode.")
            }
            if row.encodableNow {
                if !implementedRoutes.contains(row.route) {
                    failures.append("\(row.profile) \(row.route.displayName) is implemented in evidence but not in registry.")
                }
                if row.support != .implemented {
                    failures.append("\(row.profile) \(row.route.displayName) is encodable but not marked implemented.")
                }
                if ![.hardware, .mixed, .software].contains(row.path) {
                    failures.append("\(row.profile) \(row.route.displayName) has invalid implemented path \(row.path.rawValue).")
                }
            } else if row.support == .implemented {
                failures.append("\(row.profile) \(row.route.displayName) is implemented but not encodable.")
            }
        }

        for profile in expectedProfiles.sorted() {
            let routesForProfile = Set(rows.filter { $0.profile == profile }.map(\.route))
            let missingRoutes = expectedRoutes.subtracting(routesForProfile)
            if !missingRoutes.isEmpty {
                failures.append("\(profile) is missing \(missingRoutes.count) route matrix rows.")
            }
        }

        let implementedRowCount = rows.filter(\.encodableNow).count
        let plannedRowCount = rows.filter { $0.support == .planned }.count
        let profileByName = Dictionary(
            uniqueKeysWithValues: TaptionCodecHardwareSupportProfile.simulationProfiles.map { ($0.name, $0) }
        )
        let expectedImplementedRowCount = expectedProfiles.reduce(0) { count, profileName in
            guard let profile = profileByName[profileName] else {
                return count
            }
            return count + expectedRoutes.filter { route in
                TaptionCodecRoutePlanner.selectRoute(
                    for: routeMatrixVideoAsset(sourceCodec: route.sourceCodec),
                    outputCodec: route.outputCodec,
                    hardwareSupport: profile
                ).isEncodableNow
            }.count
        }
        if implementedRowCount != expectedImplementedRowCount {
            failures.append("Route matrix expected \(expectedImplementedRowCount) implemented rows, got \(implementedRowCount).")
        }

        return TaptionRouteMatrixEvidenceSummary(
            profileCount: profileNames.count,
            rowCount: rows.count,
            implementedRowCount: implementedRowCount,
            plannedRowCount: plannedRowCount,
            failures: failures
        )
    }

    private static func routeMatrixVideoAsset(sourceCodec: TaptionVideoCodec) -> TaptionVideoAsset {
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
            ),
            audioTracks: [
                TaptionAudioTrackInfo(codec: .aac, channelCount: 2, sampleRate: 48_000)
            ]
        )
    }

    static func verifyVideoFixtureManifest(
        rows: [TaptionVideoFixtureManifestRow],
        fixtureTargets: [TaptionSoftwareFixtureTarget] = SW_CodecSupportCatalog.fixtureTargets
    ) -> TaptionVideoFixtureManifestSummary {
        var failures: [String] = []
        var rowByName: [String: TaptionVideoFixtureManifestRow] = [:]
        for row in rows {
            if rowByName[row.name] != nil {
                failures.append("\(row.name) is duplicated in the video fixture manifest.")
            }
            rowByName[row.name] = row
        }
        let implementedTargets = fixtureTargets.filter { $0.generationStatus == .implemented }

        if rows.isEmpty {
            failures.append("No video fixture manifest rows were found.")
        }

        for target in implementedTargets {
            guard let row = rowByName[target.name] else {
                failures.append("\(target.name) is missing from the video fixture manifest.")
                continue
            }
            if row.videoCodec != target.videoCodec {
                failures.append("\(target.name) video codec expected \(target.videoCodec.rawValue), got \(row.videoCodec.rawValue).")
            }
            if row.audioCodec != target.audioCodec {
                failures.append("\(target.name) audio codec expected \(target.audioCodec.rawValue), got \(row.audioCodec.rawValue).")
            }
            if row.container != target.container {
                failures.append("\(target.name) container expected \(target.container.rawValue), got \(row.container.rawValue).")
            }
        }

        for row in rows where fixtureTargets.allSatisfy({ $0.name != row.name }) {
            failures.append("\(row.name) is present in the manifest but missing from SW_CodecSupportCatalog.fixtureTargets.")
        }

        return TaptionVideoFixtureManifestSummary(
            fixtureCount: rows.count,
            coveredVideoCodecs: Set(rows.map(\.videoCodec)),
            coveredAudioCodecs: Set(rows.map(\.audioCodec)),
            coveredContainers: Set(rows.map(\.container)),
            failures: failures
        )
    }

    static func verifyVideoFixtureGeneration(
        rows: [TaptionVideoFixtureGenerationRow],
        fixtureTargets: [TaptionSoftwareFixtureTarget] = SW_CodecSupportCatalog.fixtureTargets
    ) -> TaptionVideoFixtureGenerationSummary {
        let targetNames = fixtureTargets.map(\.name)
        let duplicateTargetNames = targetNames
            .reduce(into: [String: Int]()) { counts, name in
                counts[name, default: 0] += 1
            }
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        let rowNames = rows.map(\.name)
        let duplicateRowNames = rowNames
            .reduce(into: [String: Int]()) { counts, name in
                counts[name, default: 0] += 1
            }
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        let fixtureTargetByName = fixtureTargets.reduce(into: [String: TaptionSoftwareFixtureTarget]()) { result, target in
            result[target.name] = result[target.name] ?? target
        }
        let rowByName = rows.reduce(into: [String: TaptionVideoFixtureGenerationRow]()) { result, row in
            result[row.name] = result[row.name] ?? row
        }
        let implementedTargets = fixtureTargets.filter { $0.generationStatus == .implemented }
        let optionalRows = rows.filter { row in
            fixtureTargetByName[row.name]?.generationStatus != .implemented
        }
        var failures: [String] = []

        if rows.isEmpty {
            failures.append("No video fixture generation rows were found.")
        }
        if !duplicateTargetNames.isEmpty {
            failures.append("Video fixture catalog has duplicate target names: \(duplicateTargetNames.joined(separator: ", "))")
        }
        if !duplicateRowNames.isEmpty {
            failures.append("Video fixture generation has duplicate rows: \(duplicateRowNames.joined(separator: ", "))")
        }

        for row in rows where fixtureTargetByName[row.name] == nil {
            failures.append("\(row.name) is present in video generation evidence but missing from SW_CodecSupportCatalog.fixtureTargets.")
        }

        for target in implementedTargets {
            guard let row = rowByName[target.name] else {
                failures.append("\(target.name) is implemented but has no video generation row.")
                continue
            }
            if row.status != .pass {
                failures.append("\(target.name) is implemented but generation status is \(row.status.rawValue): \(row.message)")
            }
        }

        for row in rows {
            if row.status == .pass && row.file.isEmpty {
                failures.append("\(row.name) generated but did not record a fixture file.")
            }
            if row.status == .fail {
                failures.append("\(row.name) failed to generate: \(row.message)")
            }
            if row.status == .skip && (row.message.isEmpty || row.message == "ok") {
                failures.append("\(row.name) skipped but did not record a useful generator-blocking reason.")
            }

            guard let target = fixtureTargetByName[row.name] else {
                continue
            }
            if target.generationStatus == .realWorldSampleRequired && row.status == .pass {
                failures.append("\(row.name) generated successfully but is marked real-world-sample-required; update fixture coverage status.")
            }
            if target.generationStatus == .planned && row.status == .pass {
                failures.append("\(row.name) generated successfully but is still marked planned; update fixture coverage status.")
            }
        }

        return TaptionVideoFixtureGenerationSummary(
            passCount: rows.filter { $0.status == .pass }.count,
            skipCount: rows.filter { $0.status == .skip }.count,
            failCount: rows.filter { $0.status == .fail }.count,
            implementedTargetCount: implementedTargets.count,
            implementedPassCount: implementedTargets.filter {
                rowByName[$0.name]?.status == .pass
            }.count,
            optionalAttemptCount: optionalRows.count,
            optionalAttemptNames: optionalRows.map(\.name).sorted(),
            failures: failures
        )
    }

    static func verifyVideoFixtureCatalogCoverage(
        fixtureTargets: [TaptionSoftwareFixtureTarget] = SW_CodecSupportCatalog.fixtureTargets,
        universalVideoCodecs: Set<TaptionVideoCodec> = Set(TaptionCodecRegistry.universalSourceCodecs)
    ) -> TaptionVideoFixtureCatalogCoverageSummary {
        let targetNames = fixtureTargets.map(\.name)
        let duplicateNames = targetNames
            .reduce(into: [String: Int]()) { counts, name in
                counts[name, default: 0] += 1
            }
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()

        let implementedCodecs = videoCodecs(
            in: fixtureTargets,
            withStatus: .implemented
        )
        let conditionalCodecs = videoCodecs(
            in: fixtureTargets,
            withStatus: .conditionalOnLocalFFmpeg
        )
        let realWorldSampleRequiredCodecs = videoCodecs(
            in: fixtureTargets,
            withStatus: .realWorldSampleRequired
        )
        let plannedCodecs = videoCodecs(
            in: fixtureTargets,
            withStatus: .planned
        )
        let trackedCodecs = Set(fixtureTargets.map(\.videoCodec))
        let untrackedUniversalCodecs = universalVideoCodecs.subtracting(trackedCodecs)
        let fixtureOnlyCodecs = trackedCodecs.subtracting(universalVideoCodecs)

        var failures: [String] = []
        if fixtureTargets.isEmpty {
            failures.append("No video fixture catalog targets were found.")
        }
        if !duplicateNames.isEmpty {
            failures.append("Video fixture catalog has duplicate target names: \(duplicateNames.joined(separator: ", "))")
        }
        if !untrackedUniversalCodecs.isEmpty {
            failures.append(
                "Universal video codecs without fixture tracking: \(sortVideoCodecs(untrackedUniversalCodecs).map(\.rawValue).joined(separator: ", "))"
            )
        }
        if !fixtureOnlyCodecs.isEmpty {
            failures.append(
                "Fixture catalog tracks codecs outside the universal source contract: \(sortVideoCodecs(fixtureOnlyCodecs).map(\.rawValue).joined(separator: ", "))"
            )
        }
        if implementedCodecs.isEmpty {
            failures.append("Video fixture catalog has no implemented fixture codec targets.")
        }

        return TaptionVideoFixtureCatalogCoverageSummary(
            universalVideoCodecCount: universalVideoCodecs.count,
            trackedUniversalVideoCodecCount: trackedCodecs.intersection(universalVideoCodecs).count,
            implementedFixtureVideoCodecCount: implementedCodecs.count,
            conditionalFixtureVideoCodecCount: conditionalCodecs.count,
            realWorldSampleRequiredVideoCodecCount: realWorldSampleRequiredCodecs.count,
            plannedFixtureVideoCodecCount: plannedCodecs.count,
            implementedVideoCodecs: implementedCodecs,
            conditionalVideoCodecs: conditionalCodecs,
            realWorldSampleRequiredVideoCodecs: realWorldSampleRequiredCodecs,
            plannedVideoCodecs: plannedCodecs,
            untrackedUniversalVideoCodecs: sortVideoCodecs(untrackedUniversalCodecs),
            fixtureOnlyVideoCodecs: sortVideoCodecs(fixtureOnlyCodecs),
            duplicateFixtureTargetNames: duplicateNames,
            failures: failures
        )
    }

    static func verifyVideoContainerFixtureCoverage(
        fixtureTargets: [TaptionSoftwareFixtureTarget] = SW_CodecSupportCatalog.fixtureTargets,
        backendProfile: TaptionSoftwareCodecBackendProfile = SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate,
        expectedContainers: Set<TaptionVideoContainer> = Set(TaptionVideoContainer.allCases.filter { $0 != .unknown })
    ) -> TaptionVideoContainerFixtureCoverageSummary {
        let trackedContainers = Set(fixtureTargets.map(\.container))
        let missingExpectedContainers = expectedContainers.subtracting(trackedContainers)
        let fixtureOnlyContainers = trackedContainers.subtracting(expectedContainers)
        let missingReadableContainers = backendProfile.readableContainers.subtracting(trackedContainers)
        let missingWritableContainers = backendProfile.writableContainers.subtracting(expectedContainers)
        let extensionRoundTripFailures = expectedContainers
            .sorted { $0.rawValue < $1.rawValue }
            .flatMap { container in
                container.supportedFileExtensions.compactMap { fileExtension in
                    let inferred = TaptionVideoContainer.inferred(fromFileExtension: fileExtension)
                    return inferred == container
                        ? nil
                        : "\(fileExtension) expected \(container.rawValue), got \(inferred.rawValue)"
                }
            }
        let extensionAliasCount = expectedContainers
            .map(\.supportedFileExtensions.count)
            .reduce(0, +)

        var failures: [String] = []
        if fixtureTargets.isEmpty {
            failures.append("No video fixture catalog targets were found.")
        }
        if !missingExpectedContainers.isEmpty {
            failures.append(
                "Video containers without fixture tracking: \(sortContainers(missingExpectedContainers).map(\.rawValue).joined(separator: ", "))"
            )
        }
        if !fixtureOnlyContainers.isEmpty {
            failures.append(
                "Fixture catalog tracks containers outside the expected container contract: \(sortContainers(fixtureOnlyContainers).map(\.rawValue).joined(separator: ", "))"
            )
        }
        if !missingReadableContainers.isEmpty {
            failures.append(
                "Readable containers without fixture tracking: \(sortContainers(missingReadableContainers).map(\.rawValue).joined(separator: ", "))"
            )
        }
        if !missingWritableContainers.isEmpty {
            failures.append(
                "Writable containers outside the expected container contract: \(sortContainers(missingWritableContainers).map(\.rawValue).joined(separator: ", "))"
            )
        }
        if !extensionRoundTripFailures.isEmpty {
            failures.append(
                "Container extension inference failures: \(extensionRoundTripFailures.joined(separator: "; "))"
            )
        }

        return TaptionVideoContainerFixtureCoverageSummary(
            expectedContainerCount: expectedContainers.count,
            trackedContainerCount: trackedContainers.intersection(expectedContainers).count,
            readableContainerCount: backendProfile.readableContainers.count,
            writableContainerCount: backendProfile.writableContainers.count,
            trackedContainers: sortContainers(trackedContainers),
            missingExpectedContainers: sortContainers(missingExpectedContainers),
            fixtureOnlyContainers: sortContainers(fixtureOnlyContainers),
            missingReadableContainers: sortContainers(missingReadableContainers),
            missingWritableContainers: sortContainers(missingWritableContainers),
            extensionAliasCount: extensionAliasCount,
            extensionRoundTripFailures: extensionRoundTripFailures,
            failures: failures
        )
    }

    static func verifyAudioFixtureGeneration(
        rows: [TaptionAudioFixtureGenerationRow],
        coveredCodecs: Set<TaptionAudioCodec> = SW_AudioCodecSupportCatalog.fixtureCoveredCodecs,
        pendingCodecs: Set<TaptionAudioCodec> = SW_AudioCodecSupportCatalog.fixturePendingCodecs
    ) -> TaptionAudioFixtureGenerationSummary {
        var failures: [String] = []
        let generatedRows = rows.filter { $0.status == .pass }
        let generatedCodecs = Set(generatedRows.map(\.targetAudioCodec))
        let pendingAttemptRows = rows.filter {
            pendingCodecs.contains($0.targetAudioCodec) && $0.status != .pass
        }
        let pendingAttemptCodecs = Set(pendingAttemptRows.map(\.targetAudioCodec))
        let pendingGeneratedRows = generatedRows.filter {
            pendingCodecs.contains($0.targetAudioCodec)
        }
        let failedRows = rows.filter { $0.status == .fail }

        if rows.isEmpty {
            failures.append("No audio fixture generation rows were found.")
        }

        for row in generatedRows where row.file.isEmpty {
            failures.append("\(row.name) generated but did not record a fixture file.")
        }

        for row in failedRows {
            failures.append("\(row.name) failed to generate: \(row.message)")
        }

        for codec in coveredCodecs.sorted(by: { $0.rawValue < $1.rawValue })
            where !generatedCodecs.contains(codec) {
            failures.append("\(codec.rawValue) has no generated audio fixture.")
        }

        for row in pendingGeneratedRows {
            failures.append("\(row.targetAudioCodec.rawValue) generated successfully in \(row.name); move it from pending to generated fixture coverage.")
        }

        for row in pendingAttemptRows {
            if row.audioEncoder.isEmpty {
                failures.append("\(row.name) is pending but did not record the attempted encoder.")
            }
            if row.message.isEmpty || row.message == "ok" {
                failures.append("\(row.name) is pending but did not record a useful generator-blocking reason.")
            }
            if !row.file.isEmpty {
                failures.append("\(row.name) is pending but unexpectedly recorded an output file.")
            }
        }

        for codec in pendingCodecs.sorted(by: { $0.rawValue < $1.rawValue })
            where !pendingAttemptCodecs.contains(codec) {
            failures.append("\(codec.rawValue) is pending but has no generation attempt row.")
        }

        return TaptionAudioFixtureGenerationSummary(
            coveredCodecCount: generatedCodecs.intersection(coveredCodecs).count,
            pendingCodecCount: pendingAttemptCodecs.intersection(pendingCodecs).count,
            generatedCodecs: sortAudioCodecs(generatedCodecs),
            pendingAttemptCodecs: sortAudioCodecs(pendingAttemptCodecs),
            pendingAttemptNames: pendingAttemptRows.map(\.name).sorted(),
            failures: failures
        )
    }

    static func verifyAudioFixtureCatalogCoverage(
        generatedCodecs: Set<TaptionAudioCodec> = SW_AudioCodecSupportCatalog.fixtureCoveredCodecs,
        pendingCodecs: Set<TaptionAudioCodec> = SW_AudioCodecSupportCatalog.fixturePendingCodecs,
        universalAudioCodecs: Set<TaptionAudioCodec> = Set(TaptionAudioCodecRoutePlanner.universalAudioCodecs)
    ) -> TaptionAudioFixtureCatalogCoverageSummary {
        let trackedCodecs = generatedCodecs.union(pendingCodecs)
        let untrackedUniversalCodecs = universalAudioCodecs.subtracting(trackedCodecs)
        let fixtureOnlyCodecs = trackedCodecs.subtracting(universalAudioCodecs)

        var failures: [String] = []
        if universalAudioCodecs.isEmpty {
            failures.append("No universal audio codecs were found.")
        }
        if generatedCodecs.isEmpty {
            failures.append("Audio fixture catalog has no generated fixture codec targets.")
        }
        if !untrackedUniversalCodecs.isEmpty {
            failures.append(
                "Universal audio codecs without fixture tracking: \(sortAudioCodecs(untrackedUniversalCodecs).map(\.rawValue).joined(separator: ", "))"
            )
        }
        if !fixtureOnlyCodecs.isEmpty {
            failures.append(
                "Audio fixture catalog tracks codecs outside the universal audio contract: \(sortAudioCodecs(fixtureOnlyCodecs).map(\.rawValue).joined(separator: ", "))"
            )
        }

        return TaptionAudioFixtureCatalogCoverageSummary(
            universalAudioCodecCount: universalAudioCodecs.count,
            trackedUniversalAudioCodecCount: trackedCodecs.intersection(universalAudioCodecs).count,
            generatedFixtureAudioCodecCount: generatedCodecs.count,
            pendingFixtureAudioCodecCount: pendingCodecs.count,
            generatedAudioCodecs: sortAudioCodecs(generatedCodecs),
            pendingAudioCodecs: sortAudioCodecs(pendingCodecs),
            untrackedUniversalAudioCodecs: sortAudioCodecs(untrackedUniversalCodecs),
            fixtureOnlyAudioCodecs: sortAudioCodecs(fixtureOnlyCodecs),
            failures: failures
        )
    }

    private static func key(
        name: String,
        mode: TaptionCodecFixtureEvidenceMode
    ) -> String {
        "\(name)\u{1F}\(mode.rawValue)"
    }

    private static func videoCodec(forEncoder encoder: String) -> TaptionVideoCodec? {
        switch encoder {
        case "libsvtav1":
            return .av1
        case "libx264", "h264_videotoolbox":
            return .h264
        case "libx265", "hevc_videotoolbox":
            return .hevc
        case "libvpx-vp9":
            return .vp9
        case "libvpx":
            return .vp8
        case "prores_ks":
            return .proRes
        case "mpeg1video":
            return .mpeg1
        case "mpeg2video":
            return .mpeg2
        case "mpeg4":
            return .mpeg4Visual
        case "h263":
            return .h263
        case "mjpeg":
            return .motionJPEG
        case "qtrle":
            return .animation
        case "cinepak":
            return .cinepak
        case "wmv2":
            return .wmv
        case "ffv1":
            return .ffv1
        case "huffyuv", "ffvhuff":
            return .huffYUV
        case "utvideo":
            return .utVideo
        case "magicyuv":
            return .magicYUV
        case "cfhd":
            return .cineForm
        case "dnxhd":
            return .dnxhd
        case "png":
            return .pngVideo
        case "r10k":
            return .r10k
        case "v210":
            return .v210
        case "msrle":
            return .microsoftRLE
        case "smc":
            return .quickTimeGraphics
        case "v308":
            return .v308
        case "v408":
            return .v408
        case "yuv4":
            return .yuv4
        case "dvvideo":
            return .dv
        case "libtheora":
            return .theora
        case "rv20":
            return .realVideo
        case "roqvideo":
            return .roqVideo
        case "rawvideo":
            return .rawVideo
        default:
            return nil
        }
    }

    private static func audioCodec(forEncoder encoder: String) -> TaptionAudioCodec? {
        switch encoder {
        case "aac":
            return .aac
        case "libopus":
            return .opus
        case "pcm_s16le", "pcm_s24le", "pcm_f32le":
            return .pcm
        case "flac":
            return .flac
        case "vorbis", "libvorbis":
            return .vorbis
        case "ac3":
            return .ac3
        case "eac3":
            return .eac3
        case "alac":
            return .alac
        case "mp2":
            return .mp2
        case "libmp3lame":
            return .mp3
        case "dca":
            return .dts
        case "truehd":
            return .trueHD
        case "ilbc_at":
            return .ilbc
        case "g722":
            return .g722
        case "g723_1":
            return .g723
        case "g726":
            return .g726
        case "mlp":
            return .mlp
        case "tta":
            return .tta
        case "nellymoser":
            return .nellymoser
        case "real_144":
            return .realAudio
        case "roq_dpcm":
            return .roqDPCM
        case "wavpack":
            return .wavPack
        case "wmav2":
            return .wma
        case "adpcm_ima_wav", "adpcm_ms":
            return .adpcm
        case "pcm_alaw":
            return .aLaw
        case "pcm_mulaw":
            return .muLaw
        case "none":
            return .unknown
        default:
            return nil
        }
    }

    private static func container(forFileName fileName: String) -> TaptionVideoContainer? {
        let container = TaptionVideoContainer.inferred(from: URL(fileURLWithPath: fileName))
        return container == .unknown ? nil : container
    }

    private static func videoCodecs(
        in targets: [TaptionSoftwareFixtureTarget],
        withStatus status: TaptionSoftwareFixtureTarget.GenerationStatus
    ) -> [TaptionVideoCodec] {
        sortVideoCodecs(Set(targets.compactMap { target in
            target.generationStatus == status ? target.videoCodec : nil
        }))
    }

    private static func sortVideoCodecs(
        _ codecs: Set<TaptionVideoCodec>
    ) -> [TaptionVideoCodec] {
        codecs.sorted { $0.rawValue < $1.rawValue }
    }

    private static func sortAudioCodecs(
        _ codecs: Set<TaptionAudioCodec>
    ) -> [TaptionAudioCodec] {
        codecs.sorted { $0.rawValue < $1.rawValue }
    }

    private static func sortRoutes(
        _ routes: Set<TaptionCodecRoute>
    ) -> [TaptionCodecRoute] {
        routes.sorted {
            if $0.sourceCodec.rawValue == $1.sourceCodec.rawValue {
                return $0.outputCodec.rawValue < $1.outputCodec.rawValue
            }
            return $0.sourceCodec.rawValue < $1.sourceCodec.rawValue
        }
    }

    private static func sortAudioRoutes(
        _ routes: Set<TaptionAudioCodecRoute>
    ) -> [TaptionAudioCodecRoute] {
        routes.sorted {
            if $0.sourceCodec.rawValue == $1.sourceCodec.rawValue {
                return $0.outputCodec.rawValue < $1.outputCodec.rawValue
            }
            return $0.sourceCodec.rawValue < $1.sourceCodec.rawValue
        }
    }

    private static func sortContainers(
        _ containers: Set<TaptionVideoContainer>
    ) -> [TaptionVideoContainer] {
        containers.sorted { $0.rawValue < $1.rawValue }
    }

    private static func duplicateIDs(in ids: [String]) -> [String] {
        ids.reduce(into: [String: Int]()) { counts, id in
            counts[id, default: 0] += 1
        }
        .filter { $0.value > 1 }
        .map(\.key)
        .sorted()
    }
}
