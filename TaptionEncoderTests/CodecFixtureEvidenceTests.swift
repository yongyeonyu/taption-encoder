import XCTest
@testable import Taption_Encoder

final class CodecFixtureEvidenceTests: XCTestCase {
    func testVideoFixtureManifestMatchesSoftwareFixtureCatalog() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/generated_smoke/fixtures.tsv")

        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseVideoFixtureManifestTSV(manifestText)
        let summary = TaptionCodecFixtureEvidence.verifyVideoFixtureManifest(rows: rows)
        let implementedTargetCount = SW_CodecSupportCatalog.fixtureTargets
            .filter { $0.generationStatus == .implemented }
            .count

        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(summary.fixtureCount, implementedTargetCount)
        XCTAssertTrue(summary.coveredVideoCodecs.isSuperset(of: requiredVideoFixtureCodecs))
        XCTAssertTrue(summary.coveredAudioCodecs.isSuperset(of: requiredVideoFixtureAudioCodecs))
        XCTAssertTrue(summary.coveredContainers.isSuperset(of: requiredVideoFixtureContainers))
    }

    func testVideoFixtureGenerationTracksImplementedAndOptionalAttempts() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let generationURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/generated_smoke/video_fixture_generation.tsv")

        let generationText = try String(contentsOf: generationURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseVideoFixtureGenerationTSV(generationText)
        let summary = TaptionCodecFixtureEvidence.verifyVideoFixtureGeneration(rows: rows)
        let implementedTargetCount = SW_CodecSupportCatalog.fixtureTargets
            .filter { $0.generationStatus == .implemented }
            .count

        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertEqual(summary.implementedTargetCount, implementedTargetCount)
        XCTAssertEqual(summary.implementedPassCount, implementedTargetCount)
        XCTAssertGreaterThanOrEqual(summary.passCount, implementedTargetCount)
        XCTAssertGreaterThanOrEqual(summary.optionalAttemptCount, 2)
        XCTAssertTrue(summary.optionalAttemptNames.contains("vc1_raw_elementary"))
        XCTAssertTrue(summary.optionalAttemptNames.contains("theora_ogv_vorbis"))

        let vc1Row = rows.first { $0.name == "vc1_raw_elementary" }
        XCTAssertEqual(vc1Row?.status, .skip)
        XCTAssertEqual(vc1Row?.videoEncoder, "vc1")
        XCTAssertTrue(vc1Row?.message.contains("real-world VC-1") == true)

        let theoraRow = rows.first { $0.name == "theora_ogv_vorbis" }
        XCTAssertEqual(theoraRow?.status, .skip)
        XCTAssertEqual(theoraRow?.videoEncoder, "libtheora")
        XCTAssertTrue(theoraRow?.message.contains("missing libtheora") == true)
    }

    func testVideoFixtureGenerationRequiresUsefulOptionalAttemptReasons() {
        let rows = [
            TaptionVideoFixtureGenerationRow(
                name: "h264_fixture",
                file: "h264_fixture.mp4",
                videoEncoder: "libx264",
                audioEncoder: "aac",
                status: .pass,
                message: "ok"
            ),
            TaptionVideoFixtureGenerationRow(
                name: "vc1_fixture",
                file: "vc1_fixture.vc1",
                videoEncoder: "vc1",
                audioEncoder: "none",
                status: .skip,
                message: ""
            ),
            TaptionVideoFixtureGenerationRow(
                name: "planned_fixture",
                file: "planned_fixture.mov",
                videoEncoder: "planned",
                audioEncoder: "aac",
                status: .pass,
                message: "ok"
            )
        ]
        let fixtureTargets = [
            TaptionSoftwareFixtureTarget(
                name: "h264_fixture",
                videoCodec: .h264,
                audioCodec: .aac,
                container: .mp4,
                sourceFamily: "test",
                generationStatus: .implemented
            ),
            TaptionSoftwareFixtureTarget(
                name: "vc1_fixture",
                videoCodec: .vc1,
                audioCodec: .unknown,
                container: .rawElementaryStream,
                sourceFamily: "test",
                generationStatus: .realWorldSampleRequired
            ),
            TaptionSoftwareFixtureTarget(
                name: "planned_fixture",
                videoCodec: .hevcWithAlpha,
                audioCodec: .aac,
                container: .mov,
                sourceFamily: "test",
                generationStatus: .planned
            )
        ]

        let summary = TaptionCodecFixtureEvidence.verifyVideoFixtureGeneration(
            rows: rows,
            fixtureTargets: fixtureTargets
        )

        XCTAssertFalse(summary.isPassing)
        XCTAssertEqual(summary.implementedPassCount, 1)
        XCTAssertEqual(summary.optionalAttemptNames, ["planned_fixture", "vc1_fixture"])
        XCTAssertTrue(summary.failures.contains { $0.contains("vc1_fixture skipped but did not record a useful generator-blocking reason") })
        XCTAssertTrue(summary.failures.contains { $0.contains("planned_fixture generated successfully but is still marked planned") })
    }

    func testVideoFixtureCatalogTracksEveryReadableContainer() {
        let catalogContainers = Set(SW_CodecSupportCatalog.fixtureTargets.map(\.container))
        let readableContainers = SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.readableContainers

        XCTAssertTrue(
            catalogContainers.isSuperset(of: readableContainers),
            "Missing readable containers: \(readableContainers.subtracting(catalogContainers).map(\.rawValue).sorted().joined(separator: ", "))"
        )
    }

    func testVideoFixtureCatalogTracksEveryDeclaredContainerAndAlias() {
        let summary = TaptionCodecFixtureEvidence.verifyVideoContainerFixtureCoverage()
        let expectedContainers = Set(TaptionVideoContainer.allCases.filter { $0 != .unknown })

        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertTrue(summary.fixtureTrackingIsComplete)
        XCTAssertEqual(summary.expectedContainerCount, expectedContainers.count)
        XCTAssertEqual(summary.trackedContainerCount, expectedContainers.count)
        XCTAssertEqual(summary.readableContainerCount, expectedContainers.count)
        XCTAssertEqual(
            summary.writableContainerCount,
            SW_SoftwareCodecBackendRegistry.ffmpegFamilyCandidate.writableContainers.count
        )
        XCTAssertEqual(Set(summary.trackedContainers), expectedContainers)
        XCTAssertTrue(summary.missingExpectedContainers.isEmpty)
        XCTAssertTrue(summary.fixtureOnlyContainers.isEmpty)
        XCTAssertTrue(summary.missingReadableContainers.isEmpty)
        XCTAssertTrue(summary.missingWritableContainers.isEmpty)
        XCTAssertTrue(summary.extensionRoundTripFailures.isEmpty)
        XCTAssertGreaterThan(summary.extensionAliasCount, expectedContainers.count)
    }

    func testVideoFixtureCatalogTracksEveryUniversalSourceCodec() {
        let summary = TaptionCodecFixtureEvidence.verifyVideoFixtureCatalogCoverage()

        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertTrue(summary.universalFixtureTrackingIsComplete)
        XCTAssertEqual(summary.universalVideoCodecCount, TaptionCodecRegistry.universalSourceCodecs.count)
        XCTAssertEqual(summary.trackedUniversalVideoCodecCount, summary.universalVideoCodecCount)
        XCTAssertTrue(summary.untrackedUniversalVideoCodecs.isEmpty)
        XCTAssertTrue(summary.fixtureOnlyVideoCodecs.isEmpty)
        XCTAssertTrue(summary.duplicateFixtureTargetNames.isEmpty)
        XCTAssertGreaterThanOrEqual(summary.implementedFixtureVideoCodecCount, requiredVideoFixtureCodecs.count)
        XCTAssertTrue(Set(summary.implementedVideoCodecs).isSuperset(of: requiredVideoFixtureCodecs))
        XCTAssertTrue(summary.conditionalVideoCodecs.contains(.theora))
        XCTAssertTrue(summary.realWorldSampleRequiredVideoCodecs.contains(.vc1))
        XCTAssertTrue(summary.realWorldSampleRequiredVideoCodecs.contains(.dolbyVisionHEVC))
        XCTAssertTrue(summary.realWorldSampleRequiredVideoCodecs.contains(.proResRaw))
        XCTAssertTrue(summary.realWorldSampleRequiredVideoCodecs.contains(.sorensonVideo3))
        XCTAssertTrue(summary.plannedVideoCodecs.contains(.hevcWithAlpha))
        XCTAssertTrue(summary.plannedVideoCodecs.contains(.jpeg))
        XCTAssertTrue(summary.plannedVideoCodecs.contains(.jpegXL))
        XCTAssertTrue(summary.plannedVideoCodecs.contains(.dvcPro))
        XCTAssertTrue(summary.plannedVideoCodecs.contains(.dvcProHD))
        XCTAssertTrue(summary.implementedVideoCodecs.contains(.rawVideo))
        XCTAssertTrue(summary.implementedVideoCodecs.contains(.sorensonVideo))
        XCTAssertTrue(summary.implementedVideoCodecs.contains(.flashVideo))
        XCTAssertTrue(summary.implementedVideoCodecs.contains(.microsoftMPEG4V2))
        XCTAssertTrue(summary.implementedVideoCodecs.contains(.microsoftMPEG4V3))
        XCTAssertTrue(summary.implementedVideoCodecs.contains(.realVideo1))
        XCTAssertTrue(summary.implementedVideoCodecs.contains(.quickTimeVideo))
        XCTAssertTrue(summary.implementedVideoCodecs.contains(.jpeg2000))
        XCTAssertTrue(summary.implementedVideoCodecs.contains(.jpegLS))
    }

    func testSmokeLatestTranscodeResultsProveSWAndHWH265WithAudioSignal() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/generated_smoke/fixtures.tsv")
        let resultsURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/transcode_reports/smoke_latest/transcode_results.tsv")

        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let resultText = try String(contentsOf: resultsURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseTranscodeResultsTSV(resultText)
        let fixtureNames = TaptionCodecFixtureEvidence.parseFixtureNamesTSV(manifestText)
        let summary = TaptionCodecFixtureEvidence.verify(
            rows: rows,
            fixtureNames: fixtureNames
        )

        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(summary.fixtureCount, 90)
        XCTAssertEqual(summary.verifiedTranscodeCount, summary.fixtureCount * 2)
        XCTAssertEqual(
            summary.verifiedAudioSignalCount + summary.noSourceAudioAttemptCount,
            summary.verifiedTranscodeCount
        )
        XCTAssertEqual(summary.noSourceAudioAttemptCount % TaptionCodecFixtureEvidence.requiredModes.count, 0)
    }

    func testGeneratedVideoFixturesCanBuildAppCoreHEVCCommandPlans() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/generated_smoke")
        let manifestURL = fixtureDirectoryURL
            .appendingPathComponent("fixtures.tsv")

        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseVideoFixtureManifestTSV(manifestText)

        XCTAssertGreaterThanOrEqual(rows.count, 90)

        for row in rows {
            let sourceURL = fixtureDirectoryURL.appendingPathComponent(row.file)
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(row.name)_taption.mp4")
            let asset = makeFixtureAsset(row: row)
            let plan = TaptionEncodingPlanner.makeSingleAssetPlan(
                asset: asset,
                sourceURL: sourceURL,
                temporaryOutputURL: temporaryURL,
                outputPolicy: TaptionVideoOutputPolicy(videoCodec: .hevc, container: .mp4),
                savePolicy: TaptionSavePolicy(destination: .temporaryOnly, saveGate: .none)
            )
            let commandPlan = try SW_FFmpegCodecCommandPlanner.makeSingleAssetCommandPlan(plan: plan)

            XCTAssertEqual(plan.codecRoute, TaptionCodecRoute(sourceCodec: row.videoCodec, outputCodec: .hevc), row.name)
            XCTAssertEqual(plan.outputPolicy.videoCodec, .hevc, row.name)
            XCTAssertEqual(plan.outputPolicy.container, .mp4, row.name)
            XCTAssertEqual(plan.outputPolicy.qualityPolicy, .preserveSourceVisuals, row.name)
            XCTAssertEqual(plan.outputPolicy.advancedOptions.resizeTo, TaptionPixelSize(width: 640, height: 360), row.name)
            XCTAssertEqual(plan.outputPolicy.advancedOptions.frameRate, TaptionRationalFrameRate(numerator: 30), row.name)
            XCTAssertEqual(plan.outputPolicy.advancedOptions.targetBitrate, 2_000_000, row.name)
            XCTAssertEqual(commandPlan.routeSummary, TaptionCodecRoute(sourceCodec: row.videoCodec, outputCodec: .hevc).displayName, row.name)
            XCTAssertEqual(commandPlan.sourceURL, sourceURL, row.name)
            XCTAssertEqual(commandPlan.outputURL, temporaryURL, row.name)
            XCTAssertTrue(commandPlan.arguments.contains("libx265"), row.name)
            XCTAssertTrue(commandPlan.arguments.contains("+faststart"), row.name)

            if row.audioCodec == .unknown {
                XCTAssertNil(plan.audioPlan, row.name)
                XCTAssertTrue(commandPlan.arguments.contains("-an"), row.name)
            } else {
                XCTAssertEqual(plan.audioPlan?.route, TaptionAudioCodecRoute(sourceCodec: row.audioCodec, outputCodec: .aac), row.name)
                XCTAssertEqual(plan.audioPlan?.options.sampleRate, 48_000, row.name)
                XCTAssertEqual(plan.audioPlan?.options.channelCount, 2, row.name)
                XCTAssertTrue(commandPlan.arguments.contains("0:a?"), row.name)
                XCTAssertTrue(commandPlan.arguments.contains("-c:a"), row.name)
            }
        }
    }

    func testGeneratedVideoFixturesCanBuildH265MP4CommandPlans() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/generated_smoke")
        let manifestURL = fixtureDirectoryURL
            .appendingPathComponent("fixtures.tsv")
        let outputDirectoryURL = temporaryOutputDirectory()
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseVideoFixtureManifestTSV(manifestText)
        let outputCodecs = SW_FFmpegCodecCommandPlanner.plannableVideoOutputCodecs
        let sourceCodecs = Set(rows.map(\.videoCodec))

        XCTAssertGreaterThanOrEqual(rows.count, 90)
        XCTAssertEqual(outputCodecs, [.hevc])

        var plannedRoutes = Set<TaptionCodecRoute>()
        var allJobs: [TaptionCodecFixtureExecutionJob] = []
        for outputCodec in outputCodecs {
            let jobs = try TaptionCodecFixtureExecutionPlanner.makeVideoCodecJobs(
                rows: rows,
                fixtureDirectoryURL: fixtureDirectoryURL,
                outputDirectoryURL: outputDirectoryURL,
                outputCodec: outputCodec,
                outputContainer: .mp4
            )
            allJobs += jobs

            XCTAssertEqual(jobs.count, rows.count, outputCodec.rawValue)
            XCTAssertTrue(jobs.allSatisfy { $0.kind == .videoCodecTranscode }, outputCodec.rawValue)
            XCTAssertTrue(jobs.allSatisfy { $0.outputVideoCodec == outputCodec }, outputCodec.rawValue)
            XCTAssertTrue(jobs.allSatisfy { $0.outputURL.pathExtension == TaptionVideoContainer.mp4.defaultFileExtension }, outputCodec.rawValue)

            for job in jobs {
                let sourceCodec = try XCTUnwrap(job.sourceVideoCodec, job.fixtureName)
                let expectedRoute = TaptionCodecRoute(
                    sourceCodec: sourceCodec,
                    outputCodec: outputCodec
                )
                plannedRoutes.insert(expectedRoute)
                XCTAssertEqual(job.commandPlan.routeSummary, expectedRoute.displayName, job.fixtureName)
                XCTAssertTrue(job.commandPlan.arguments.contains("0:v:0"), job.fixtureName)
                XCTAssertTrue(
                    job.commandPlan.arguments.contains(
                        try XCTUnwrap(SW_FFmpegCodecCommandPlanner.videoEncoderName(for: outputCodec))
                    ),
                    job.fixtureName
                )
                if job.sourceHasAudio {
                    XCTAssertEqual(job.outputAudioCodec, .aac, job.fixtureName)
                    XCTAssertTrue(job.commandPlan.arguments.contains("0:a?"), job.fixtureName)
                    XCTAssertTrue(job.commandPlan.arguments.contains("-c:a"), job.fixtureName)
                } else {
                    XCTAssertNil(job.outputAudioCodec, job.fixtureName)
                    XCTAssertTrue(job.commandPlan.arguments.contains("-an"), job.fixtureName)
                }
            }
        }

        let expectedRoutes = Set(sourceCodecs.flatMap { sourceCodec in
            outputCodecs.map { outputCodec in
                TaptionCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
            }
        })
        XCTAssertEqual(plannedRoutes, expectedRoutes)

        let summary = TaptionCodecFixtureEvidence.verifyVideoFixtureInputToHEVCCommandPlanCoverage(
            jobs: allJobs,
            sourceRows: rows,
            outputCodecs: outputCodecs,
            outputContainer: .mp4
        )
        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertTrue(summary.isComplete)
        XCTAssertEqual(summary.expectedJobCount, rows.count * outputCodecs.count)
        XCTAssertEqual(summary.plannedJobCount, summary.expectedJobCount)
        XCTAssertEqual(summary.expectedRouteCount, expectedRoutes.count)
        XCTAssertEqual(summary.plannedRouteCount, summary.expectedRouteCount)
        XCTAssertTrue(summary.missingRoutes.isEmpty)
    }

    func testAudioSmokeLatestTranscodeResultsProveSWAndHWH265WithAudioSignal() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/audio_generated_smoke/fixtures.tsv")
        let resultsURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/transcode_reports/audio_smoke_latest/transcode_results.tsv")

        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        let resultText = try String(contentsOf: resultsURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseTranscodeResultsTSV(resultText)
        let fixtureNames = TaptionCodecFixtureEvidence.parseFixtureNamesTSV(manifestText)
        let summary = TaptionCodecFixtureEvidence.verify(
            rows: rows,
            fixtureNames: fixtureNames
        )

        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(summary.fixtureCount, 22)
        XCTAssertEqual(summary.verifiedTranscodeCount, summary.fixtureCount * 2)
        XCTAssertEqual(summary.verifiedAudioSignalCount, summary.fixtureCount * 2)
        XCTAssertEqual(summary.noSourceAudioAttemptCount, 0)
    }

    func testAudioFixtureGenerationTracksGeneratedAndPendingCodecs() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let generationURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/audio_generated_smoke/audio_fixture_generation.tsv")

        let generationText = try String(contentsOf: generationURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseAudioFixtureGenerationTSV(generationText)
        let summary = TaptionCodecFixtureEvidence.verifyAudioFixtureGeneration(rows: rows)

        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertEqual(summary.coveredCodecCount, SW_AudioCodecSupportCatalog.fixtureCoveredCodecs.count)
        XCTAssertEqual(summary.pendingCodecCount, SW_AudioCodecSupportCatalog.fixturePendingCodecs.count)
        XCTAssertEqual(Set(summary.generatedCodecs), SW_AudioCodecSupportCatalog.fixtureCoveredCodecs)
        XCTAssertEqual(Set(summary.pendingAttemptCodecs), SW_AudioCodecSupportCatalog.fixturePendingCodecs)
        XCTAssertEqual(
            Set(summary.pendingAttemptNames),
            ["audio_xhe_aac_unavailable", "audio_amr_nb_3gp", "audio_amr_wb_3gp"]
        )

        let pendingRows = rows.filter {
            SW_AudioCodecSupportCatalog.fixturePendingCodecs.contains($0.targetAudioCodec)
        }
        XCTAssertGreaterThanOrEqual(pendingRows.count, SW_AudioCodecSupportCatalog.fixturePendingCodecs.count)
        for row in pendingRows {
            XCTAssertEqual(row.status, .skip, row.name)
            XCTAssertTrue(row.file.isEmpty, row.name)
            XCTAssertTrue(row.message.contains("missing audio encoder"), row.name)
            XCTAssertTrue(row.message.contains("afconvert alternate"), row.name)
        }

        let amrAttemptNames = Set(pendingRows.filter { $0.targetAudioCodec == .amr }.map(\.name))
        XCTAssertTrue(amrAttemptNames.contains("audio_amr_nb_3gp"))
        XCTAssertTrue(amrAttemptNames.contains("audio_amr_wb_3gp"))
    }

    func testAudioFixtureGenerationRequiresPendingAttemptReasons() {
        let rows = [
            TaptionAudioFixtureGenerationRow(
                name: "aac_fixture",
                file: "aac_fixture.mp4",
                targetAudioCodec: .aac,
                audioEncoder: "aac",
                status: .pass,
                message: "ok"
            ),
            TaptionAudioFixtureGenerationRow(
                name: "xhe_pending",
                file: "",
                targetAudioCodec: .xheAAC,
                audioEncoder: "xhe_aac",
                status: .skip,
                message: ""
            )
        ]
        let summary = TaptionCodecFixtureEvidence.verifyAudioFixtureGeneration(
            rows: rows,
            coveredCodecs: [.aac],
            pendingCodecs: [.xheAAC, .amr]
        )

        XCTAssertFalse(summary.isPassing)
        XCTAssertEqual(summary.coveredCodecCount, 1)
        XCTAssertEqual(summary.pendingCodecCount, 1)
        XCTAssertEqual(summary.pendingAttemptCodecs, [.xheAAC])
        XCTAssertTrue(summary.failures.contains { $0.contains("xhe_pending is pending but did not record a useful generator-blocking reason") })
        XCTAssertTrue(summary.failures.contains { $0.contains("amr is pending but has no generation attempt row") })
    }

    func testAudioFixtureCatalogTracksEveryUniversalAudioCodec() {
        let summary = TaptionCodecFixtureEvidence.verifyAudioFixtureCatalogCoverage()

        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertTrue(summary.universalFixtureTrackingIsComplete)
        XCTAssertEqual(summary.universalAudioCodecCount, TaptionAudioCodecRoutePlanner.universalAudioCodecs.count)
        XCTAssertEqual(summary.trackedUniversalAudioCodecCount, summary.universalAudioCodecCount)
        XCTAssertEqual(summary.generatedFixtureAudioCodecCount, SW_AudioCodecSupportCatalog.fixtureCoveredCodecs.count)
        XCTAssertEqual(summary.pendingFixtureAudioCodecCount, SW_AudioCodecSupportCatalog.fixturePendingCodecs.count)
        XCTAssertEqual(
            Set(summary.generatedAudioCodecs).union(summary.pendingAudioCodecs),
            Set(TaptionAudioCodecRoutePlanner.universalAudioCodecs)
        )
        XCTAssertTrue(summary.untrackedUniversalAudioCodecs.isEmpty)
        XCTAssertTrue(summary.fixtureOnlyAudioCodecs.isEmpty)
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.aac))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.pcm))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.opus))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.dts))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.trueHD))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.g722))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.g723))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.mlp))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.tta))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.realAudio))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.roqDPCM))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.wavPack))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.adpcm))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.aLaw))
        XCTAssertTrue(summary.generatedAudioCodecs.contains(.muLaw))
        XCTAssertTrue(summary.pendingAudioCodecs.contains(.xheAAC))
        XCTAssertTrue(summary.pendingAudioCodecs.contains(.amr))
    }

    func testGeneratedAudioFixturesCanBuildAppCoreAACPlansAndSoftwareFallbackCommands() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/audio_generated_smoke")
        let generationURL = fixtureDirectoryURL
            .appendingPathComponent("audio_fixture_generation.tsv")

        let generationText = try String(contentsOf: generationURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseAudioFixtureGenerationTSV(generationText)
        let generatedRows = rows.filter { $0.status == .pass }

        XCTAssertGreaterThanOrEqual(generatedRows.count, SW_AudioCodecSupportCatalog.fixtureCoveredCodecs.count)

        var plannedSourceCodecs = Set<TaptionAudioCodec>()
        for row in generatedRows {
            XCTAssertFalse(row.file.isEmpty, row.name)

            let shape = audioFixtureSignalShape(for: row)
            let sourceURL = fixtureDirectoryURL.appendingPathComponent(row.file)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(row.name)_audio_taption.mp4")
            let sourceTrack = TaptionAudioTrackInfo(
                codec: row.targetAudioCodec,
                channelCount: shape.channelCount,
                sampleRate: shape.sampleRate,
                estimatedBitrate: shape.bitrate
            )
            let route = TaptionAudioCodecRoute(
                sourceCodec: row.targetAudioCodec,
                outputCodec: .aac
            )
            let plan = TaptionAudioTranscodePlanner.makePlan(
                sourceTrack: sourceTrack,
                trackIndex: 0,
                sourceURL: sourceURL,
                outputURL: outputURL,
                outputCodec: .aac,
                outputContainer: .mp4
            )
            let softwareCommandPlan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(
                request: TaptionAudioCodecTranscodeRequest(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    route: route,
                    options: plan.options
                )
            )

            plannedSourceCodecs.insert(row.targetAudioCodec)
            XCTAssertEqual(plan.route, route, row.name)
            XCTAssertEqual(plan.options.outputCodec, .aac, row.name)
            XCTAssertEqual(plan.options.outputContainer, .mp4, row.name)
            XCTAssertEqual(plan.options.sampleRate, shape.sampleRate, row.name)
            XCTAssertEqual(plan.options.channelCount, shape.channelCount, row.name)
            XCTAssertEqual(plan.options.targetBitrate, shape.bitrate, row.name)
            XCTAssertTrue(plan.readiness.hasCommandPlan || plan.isRunnableInCurrentBuild, row.name)
            if plan.readiness.hasCommandPlan {
                XCTAssertNotNil(plan.commandPlan, row.name)
            }

            XCTAssertEqual(softwareCommandPlan.routeSummary, route.displayName, row.name)
            XCTAssertEqual(softwareCommandPlan.sourceURL, sourceURL, row.name)
            XCTAssertEqual(softwareCommandPlan.outputURL, outputURL, row.name)
            XCTAssertTrue(softwareCommandPlan.arguments.contains("-vn"), row.name)
            XCTAssertTrue(containsArgumentPair(softwareCommandPlan.arguments, "-map", "0:a:0?"), row.name)
            XCTAssertTrue(softwareCommandPlan.arguments.contains("+faststart"), row.name)

            if row.targetAudioCodec == .aac {
                XCTAssertTrue(containsArgumentPair(softwareCommandPlan.arguments, "-c:a", "copy"), row.name)
                XCTAssertFalse(softwareCommandPlan.arguments.contains("-ar"), row.name)
                XCTAssertFalse(softwareCommandPlan.arguments.contains("-ac"), row.name)
                XCTAssertFalse(softwareCommandPlan.arguments.contains("-b:a"), row.name)
            } else {
                XCTAssertTrue(containsArgumentPair(softwareCommandPlan.arguments, "-c:a", "aac"), row.name)
                XCTAssertTrue(containsArgumentPair(softwareCommandPlan.arguments, "-ar", "\(Int(shape.sampleRate))"), row.name)
                XCTAssertTrue(containsArgumentPair(softwareCommandPlan.arguments, "-ac", "\(shape.channelCount)"), row.name)
                XCTAssertTrue(containsArgumentPair(softwareCommandPlan.arguments, "-b:a", "\(shape.bitrate)"), row.name)
            }
        }

        XCTAssertEqual(plannedSourceCodecs, SW_AudioCodecSupportCatalog.fixtureCoveredCodecs)
    }

    func testGeneratedAudioFixturesCanBuildPlannableMP4CommandPlans() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/audio_generated_smoke")
        let generationURL = fixtureDirectoryURL
            .appendingPathComponent("audio_fixture_generation.tsv")
        let outputDirectoryURL = temporaryOutputDirectory()
        let generationText = try String(contentsOf: generationURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseAudioFixtureGenerationTSV(generationText)
        let generatedRows = rows.filter { $0.status == .pass }
        let outputCodecs = SW_FFmpegCodecCommandPlanner.plannableAudioOutputCodecs
        let sourceCodecs = Set(generatedRows.map(\.targetAudioCodec))

        XCTAssertGreaterThanOrEqual(generatedRows.count, SW_AudioCodecSupportCatalog.fixtureCoveredCodecs.count)
        XCTAssertTrue(outputCodecs.contains(.aac))
        XCTAssertTrue(outputCodecs.contains(.opus))
        XCTAssertTrue(outputCodecs.contains(.flac))
        XCTAssertTrue(outputCodecs.contains(.trueHD))
        XCTAssertTrue(outputCodecs.contains(.g722))
        XCTAssertTrue(outputCodecs.contains(.g723))
        XCTAssertTrue(outputCodecs.contains(.g726))
        XCTAssertTrue(outputCodecs.contains(.mlp))
        XCTAssertTrue(outputCodecs.contains(.tta))
        XCTAssertTrue(outputCodecs.contains(.realAudio))
        XCTAssertTrue(outputCodecs.contains(.wavPack))
        XCTAssertTrue(outputCodecs.contains(.aLaw))
        XCTAssertTrue(outputCodecs.contains(.muLaw))

        var plannedRoutes = Set<TaptionAudioCodecRoute>()
        var allJobs: [TaptionCodecFixtureExecutionJob] = []
        for outputCodec in outputCodecs {
            let jobs = try TaptionCodecFixtureExecutionPlanner.makeAudioCodecJobs(
                rows: rows,
                fixtureDirectoryURL: fixtureDirectoryURL,
                outputDirectoryURL: outputDirectoryURL,
                outputCodec: outputCodec,
                outputContainer: .mp4
            )
            allJobs += jobs

            XCTAssertEqual(jobs.count, generatedRows.count, outputCodec.rawValue)
            XCTAssertTrue(jobs.allSatisfy { $0.kind == .audioCodecTranscode }, outputCodec.rawValue)
            XCTAssertTrue(jobs.allSatisfy { $0.outputAudioCodec == outputCodec }, outputCodec.rawValue)
            XCTAssertTrue(jobs.allSatisfy { $0.outputURL.pathExtension == TaptionVideoContainer.mp4.defaultFileExtension }, outputCodec.rawValue)

            for job in jobs {
                let sourceCodec = try XCTUnwrap(job.sourceAudioCodec, job.fixtureName)
                let expectedRoute = TaptionAudioCodecRoute(
                    sourceCodec: sourceCodec,
                    outputCodec: outputCodec
                )
                plannedRoutes.insert(expectedRoute)
                XCTAssertEqual(job.commandPlan.routeSummary, expectedRoute.displayName, job.fixtureName)
                XCTAssertTrue(job.commandPlan.arguments.contains("0:a:0?"), job.fixtureName)
                XCTAssertTrue(job.commandPlan.arguments.contains("-c:a"), job.fixtureName)
                let expectedEncoderArgument = sourceCodec == outputCodec
                    && HW_AudioCodecCapabilityCatalog.canCopyWithoutTranscode(
                        codec: sourceCodec,
                        into: .mp4
                    )
                    ? "copy"
                    : try XCTUnwrap(SW_FFmpegCodecCommandPlanner.audioEncoderName(for: outputCodec))
                XCTAssertTrue(
                    job.commandPlan.arguments.contains(expectedEncoderArgument),
                    job.fixtureName
                )
            }
        }

        let expectedRoutes = Set(sourceCodecs.flatMap { sourceCodec in
            outputCodecs.map { outputCodec in
                TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec)
            }
        })
        XCTAssertEqual(plannedRoutes, expectedRoutes)

        let summary = TaptionCodecFixtureEvidence.verifyAudioFixturePlannableCommandPlanCoverage(
            jobs: allJobs,
            sourceRows: rows,
            outputCodecs: outputCodecs,
            outputContainer: .mp4
        )
        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertTrue(summary.isComplete)
        XCTAssertEqual(summary.expectedJobCount, generatedRows.count * outputCodecs.count)
        XCTAssertEqual(summary.plannedJobCount, summary.expectedJobCount)
        XCTAssertEqual(summary.expectedRouteCount, expectedRoutes.count)
        XCTAssertEqual(summary.plannedRouteCount, summary.expectedRouteCount)
        XCTAssertTrue(summary.missingRoutes.isEmpty)
    }

    func testGeneratedFixturesCanBuildExecutionJobsAndRunThroughInjectedExecutorWhenReady() async throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let videoFixtureDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/generated_smoke")
        let audioFixtureDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/audio_generated_smoke")
        let outputDirectoryURL = temporaryOutputDirectory()
        try FileManager.default.createDirectory(
            at: outputDirectoryURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: outputDirectoryURL)
        }

        let videoRows = try TaptionCodecFixtureEvidence.parseVideoFixtureManifestTSV(
            String(
                contentsOf: videoFixtureDirectoryURL.appendingPathComponent("fixtures.tsv"),
                encoding: .utf8
            )
        )
        let audioRows = try TaptionCodecFixtureEvidence.parseAudioFixtureGenerationTSV(
            String(
                contentsOf: audioFixtureDirectoryURL.appendingPathComponent("audio_fixture_generation.tsv"),
                encoding: .utf8
            )
        )
        let blockedVideoJobs = try TaptionCodecFixtureExecutionPlanner.makeVideoHEVCJobs(
            rows: videoRows,
            fixtureDirectoryURL: videoFixtureDirectoryURL,
            outputDirectoryURL: outputDirectoryURL
        )
        let blockedAudioJobs = try TaptionCodecFixtureExecutionPlanner.makeAudioAACJobs(
            rows: audioRows,
            fixtureDirectoryURL: audioFixtureDirectoryURL,
            outputDirectoryURL: outputDirectoryURL
        )

        XCTAssertEqual(blockedVideoJobs.count, videoRows.count)
        XCTAssertGreaterThanOrEqual(blockedAudioJobs.count, SW_AudioCodecSupportCatalog.fixtureCoveredCodecs.count)
        XCTAssertTrue(blockedVideoJobs.allSatisfy { !$0.isExecutableInCurrentBuild })
        XCTAssertTrue(blockedAudioJobs.allSatisfy { !$0.isExecutableInCurrentBuild })
        XCTAssertTrue(blockedVideoJobs.allSatisfy { !$0.openBackendGates.isEmpty })
        XCTAssertTrue(blockedAudioJobs.allSatisfy { !$0.openBackendGates.isEmpty })

        let readyReport = readyBroadSoftwareBackendReport()
        let readyVideoJobs = try TaptionCodecFixtureExecutionPlanner.makeVideoHEVCJobs(
            rows: videoRows,
            fixtureDirectoryURL: videoFixtureDirectoryURL,
            outputDirectoryURL: outputDirectoryURL,
            backendReadiness: readyReport
        )
        let readyAudioJobs = try TaptionCodecFixtureExecutionPlanner.makeAudioAACJobs(
            rows: audioRows,
            fixtureDirectoryURL: audioFixtureDirectoryURL,
            outputDirectoryURL: outputDirectoryURL,
            backendReadiness: readyReport
        )

        XCTAssertTrue(readyVideoJobs.allSatisfy(\.isExecutableInCurrentBuild))
        XCTAssertTrue(readyAudioJobs.allSatisfy(\.isExecutableInCurrentBuild))
        XCTAssertTrue(readyVideoJobs.allSatisfy { $0.outputVideoCodec == .hevc })
        XCTAssertTrue(readyAudioJobs.allSatisfy { $0.outputAudioCodec == .aac })
        XCTAssertEqual(
            readyVideoJobs.filter(\.requiresAudioSignalVerification).count,
            videoRows.filter { $0.audioCodec != .unknown }.count
        )
        XCTAssertEqual(
            readyAudioJobs.filter(\.requiresAudioSignalVerification).count,
            readyAudioJobs.count
        )

        let executor = SW_FFmpegCommandExecutor(
            runner: FakeFFmpegCommandRunner { plan in
                try FileManager.default.createDirectory(
                    at: plan.outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("fake fixture output".utf8).write(to: plan.outputURL)
                return SW_FFmpegCommandRunResult(
                    exitCode: 0,
                    stdout: "encoded \(plan.routeSummary)",
                    stderr: "frame=3"
                )
            }
        )
        let videoExecution = try await executor.execute(readyVideoJobs[0], progress: { _ in })
        let audioExecution = try await executor.execute(readyAudioJobs[0], progress: { _ in })

        XCTAssertTrue(videoExecution.didCreateOutput)
        XCTAssertTrue(audioExecution.didCreateOutput)
        XCTAssertEqual(videoExecution.commandPlan, readyVideoJobs[0].commandPlan)
        XCTAssertEqual(audioExecution.commandPlan, readyAudioJobs[0].commandPlan)
    }

    func testGeneratedAudioFixtureJobsRunThroughFunctionStyleAudioExecutorWhenReady() async throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let audioFixtureDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/audio_generated_smoke")
        let outputDirectoryURL = temporaryOutputDirectory()
        try FileManager.default.createDirectory(
            at: outputDirectoryURL,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: outputDirectoryURL)
        }

        let audioRows = try TaptionCodecFixtureEvidence.parseAudioFixtureGenerationTSV(
            String(
                contentsOf: audioFixtureDirectoryURL.appendingPathComponent("audio_fixture_generation.tsv"),
                encoding: .utf8
            )
        )
        let readyReport = readyBroadSoftwareBackendReport()
        let readyAudioJobs = try TaptionCodecFixtureExecutionPlanner.makeAudioAACJobs(
            rows: audioRows,
            fixtureDirectoryURL: audioFixtureDirectoryURL,
            outputDirectoryURL: outputDirectoryURL,
            backendReadiness: readyReport
        )
        let audioExecutor = SW_FFmpegAudioCodecTranscodeExecutor(
            executor: SW_FFmpegCommandExecutor(
                readinessReport: readyReport,
                runner: FakeFFmpegCommandRunner { plan in
                    try FileManager.default.createDirectory(
                        at: plan.outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data("fake audio fixture output".utf8).write(to: plan.outputURL)
                    return SW_FFmpegCommandRunResult(
                        exitCode: 0,
                        stdout: "encoded \(plan.routeSummary)",
                        stderr: "size=1"
                    )
                }
            )
        )

        XCTAssertGreaterThanOrEqual(readyAudioJobs.count, SW_AudioCodecSupportCatalog.fixtureCoveredCodecs.count)

        for job in readyAudioJobs {
            let sourceCodec = try XCTUnwrap(job.sourceAudioCodec, job.fixtureName)
            let outputCodec = try XCTUnwrap(job.outputAudioCodec, job.fixtureName)
            let request = try XCTUnwrap(job.audioTranscodeRequest, job.fixtureName)
            let rebuiltCommandPlan = try SW_FFmpegCodecCommandPlanner.makeAudioCommandPlan(
                request: request
            )
            var progressStages: [TaptionEncodingStage] = []

            XCTAssertEqual(
                request.route,
                TaptionAudioCodecRoute(sourceCodec: sourceCodec, outputCodec: outputCodec),
                job.fixtureName
            )
            XCTAssertEqual(Optional(request.options), job.audioOptions, job.fixtureName)
            XCTAssertEqual(rebuiltCommandPlan, job.commandPlan, job.fixtureName)

            let output = try await audioExecutor.transcode(
                request: request,
                progress: { progressStages.append($0.stage) }
            )

            XCTAssertEqual(output.outputURL, job.outputURL, job.fixtureName)
            XCTAssertEqual(output.route, request.route, job.fixtureName)
            XCTAssertEqual(output.usedMode, .software, job.fixtureName)
            XCTAssertEqual(output.usedBackend, .ffmpegFamily, job.fixtureName)
            XCTAssertEqual(output.outputAudioCodec, .aac, job.fixtureName)
            XCTAssertEqual(output.outputContainer, .mp4, job.fixtureName)
            XCTAssertEqual(progressStages, [.preparing, .encoding, .completed], job.fixtureName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: job.outputURL.path), job.fixtureName)
        }
    }

    func testGeneratedFixtureExecutionJobsMatchLatestH265Evidence() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let videoFixtureDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/generated_smoke")
        let audioFixtureDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/audio_generated_smoke")
        let transcodeReportDirectoryURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/transcode_reports")
        let outputDirectoryURL = temporaryOutputDirectory()
        let videoRows = try TaptionCodecFixtureEvidence.parseVideoFixtureManifestTSV(
            String(
                contentsOf: videoFixtureDirectoryURL.appendingPathComponent("fixtures.tsv"),
                encoding: .utf8
            )
        )
        let audioRows = try TaptionCodecFixtureEvidence.parseAudioFixtureGenerationTSV(
            String(
                contentsOf: audioFixtureDirectoryURL.appendingPathComponent("audio_fixture_generation.tsv"),
                encoding: .utf8
            )
        )
        let videoEvidenceRows = try TaptionCodecFixtureEvidence.parseTranscodeResultsTSV(
            String(
                contentsOf: transcodeReportDirectoryURL
                    .appendingPathComponent("smoke_latest/transcode_results.tsv"),
                encoding: .utf8
            )
        )
        let audioEvidenceRows = try TaptionCodecFixtureEvidence.parseTranscodeResultsTSV(
            String(
                contentsOf: transcodeReportDirectoryURL
                    .appendingPathComponent("audio_smoke_latest/transcode_results.tsv"),
                encoding: .utf8
            )
        )
        let videoJobs = try TaptionCodecFixtureExecutionPlanner.makeVideoHEVCJobs(
            rows: videoRows,
            fixtureDirectoryURL: videoFixtureDirectoryURL,
            outputDirectoryURL: outputDirectoryURL
        )
        let audioJobs = try TaptionCodecFixtureExecutionPlanner.makeAudioAACJobs(
            rows: audioRows,
            fixtureDirectoryURL: audioFixtureDirectoryURL,
            outputDirectoryURL: outputDirectoryURL
        )
        let videoSummary = TaptionCodecFixtureEvidence.verifyExecutionJobsHaveLatestH265Evidence(
            jobs: videoJobs,
            rows: videoEvidenceRows
        )
        let audioSummary = TaptionCodecFixtureEvidence.verifyExecutionJobsHaveLatestH265Evidence(
            jobs: audioJobs,
            rows: audioEvidenceRows
        )

        XCTAssertTrue(videoSummary.isPassing, videoSummary.failures.joined(separator: "\n"))
        XCTAssertEqual(videoSummary.jobCount, videoJobs.count)
        XCTAssertEqual(videoSummary.verifiedModeCount, videoJobs.count * 2)
        XCTAssertEqual(videoSummary.verifiedAudioSignalModeCount, videoJobs.filter(\.requiresAudioSignalVerification).count * 2)
        XCTAssertEqual(videoSummary.noSourceAudioModeCount, videoJobs.filter { !$0.requiresAudioSignalVerification }.count * 2)
        XCTAssertEqual(
            videoSummary.verifiedAudioSignalModeCount + videoSummary.noSourceAudioModeCount,
            videoSummary.verifiedModeCount
        )
        XCTAssertEqual(videoSummary.noSourceAudioModeCount % TaptionCodecFixtureEvidence.requiredModes.count, 0)

        XCTAssertTrue(audioSummary.isPassing, audioSummary.failures.joined(separator: "\n"))
        XCTAssertEqual(audioSummary.jobCount, audioJobs.count)
        XCTAssertEqual(audioSummary.verifiedModeCount, audioJobs.count * 2)
        XCTAssertEqual(audioSummary.verifiedAudioSignalModeCount, audioJobs.count * 2)
        XCTAssertEqual(audioSummary.noSourceAudioModeCount, 0)
    }

    func testRouteMatrixLatestProvesAllProfilesPreferHardwareWhenAvailable() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let routeMatrixURL = rootURL
            .appendingPathComponent("Samples/CodecFixtures/transcode_reports/route_matrix_latest/codec_route_matrix.tsv")

        let routeMatrixText = try String(contentsOf: routeMatrixURL, encoding: .utf8)
        let rows = try TaptionCodecFixtureEvidence.parseRouteMatrixTSV(routeMatrixText)
        let summary = TaptionCodecFixtureEvidence.verifyRouteMatrix(rows: rows)
        let expectedProfileCount = TaptionCodecHardwareSupportProfile.simulationProfiles.count
        let expectedRouteCount = TaptionCodecRegistry.plannedUniversalRoutes.count

        XCTAssertTrue(summary.isPassing, summary.failures.joined(separator: "\n"))
        XCTAssertEqual(summary.profileCount, expectedProfileCount)
        XCTAssertEqual(summary.rowCount, expectedProfileCount * expectedRouteCount)
        XCTAssertEqual(summary.implementedRowCount, rows.filter(\.encodableNow).count)
        XCTAssertGreaterThanOrEqual(
            summary.implementedRowCount,
            expectedProfileCount * TaptionCodecRegistry.softwareImplementedRoutes.count
        )
        XCTAssertLessThan(
            summary.implementedRowCount,
            expectedProfileCount * TaptionCodecRegistry.implementedRoutes.count
        )
        XCTAssertEqual(summary.plannedRowCount, summary.rowCount - summary.implementedRowCount)
    }

    private var requiredVideoFixtureCodecs: Set<TaptionVideoCodec> {
        [
            .av1,
            .h264,
            .hevc,
            .vp9,
            .vp8,
            .proRes,
            .mpeg1,
            .mpeg2,
            .mpeg4Visual,
            .h263,
            .motionJPEG,
            .animation,
            .cinepak,
            .realVideo,
            .roqVideo,
            .wmv,
            .rawVideo,
            .dv
        ]
    }

    private var requiredVideoFixtureAudioCodecs: Set<TaptionAudioCodec> {
        [
            .aac,
            .opus,
            .pcm,
            .flac,
            .vorbis,
            .ac3,
            .eac3,
            .alac,
            .mp2,
            .mp3,
            .wma
        ]
    }

    private var requiredVideoFixtureContainers: Set<TaptionVideoContainer> {
        [
            .mp4,
            .webm,
            .mkv,
            .mov,
            .m4v,
            .lrf,
            .mpegTransportStream,
            .mxf,
            .mpegProgramStream,
            .avi,
            .flv,
            .threeGP,
            .threeGPP2,
            .asf,
            .wmv,
            .nut,
            .roq,
            .realMedia,
            .rawElementaryStream,
            .dv
        ]
    }

    private func makeFixtureAsset(row: TaptionVideoFixtureManifestRow) -> TaptionVideoAsset {
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

    private struct FakeFFmpegCommandRunner: SW_FFmpegCommandRunning {
        var runBlock: @Sendable (SW_FFmpegCommandPlan) async throws -> SW_FFmpegCommandRunResult

        func run(commandPlan: SW_FFmpegCommandPlan) async throws -> SW_FFmpegCommandRunResult {
            try await runBlock(commandPlan)
        }
    }

    private func readyBroadSoftwareBackendReport() -> TaptionSoftwareCodecBackendReadinessReport {
        SW_SoftwareCodecBackendRegistry.broadBackendReadinessReport(
            isBundledInCurrentBuild: true,
            satisfiedGates: Set(TaptionSoftwareCodecBackendReadinessGate.allCases)
        )
    }

    private func temporaryOutputDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TaptionEncoderFixtureJobs-\(UUID().uuidString)", isDirectory: true)
    }

    private func audioFixtureSignalShape(
        for row: TaptionAudioFixtureGenerationRow
    ) -> (sampleRate: Double, channelCount: Int, bitrate: Int) {
        switch row.targetAudioCodec {
        case .aLaw, .muLaw, .amr, .ilbc:
            return (8_000, 1, 64_000)
        case .g722:
            return (16_000, 1, 64_000)
        case .g723, .g726, .nellymoser, .realAudio:
            return (8_000, 1, 64_000)
        case .adpcm, .roqDPCM:
            return (22_050, 1, 96_000)
        default:
            return (48_000, 2, 192_000)
        }
    }

    private func containsArgumentPair(
        _ arguments: [String],
        _ key: String,
        _ value: String
    ) -> Bool {
        arguments.indices.contains { index in
            let nextIndex = arguments.index(after: index)
            return nextIndex < arguments.endIndex
                && arguments[index] == key
                && arguments[nextIndex] == value
        }
    }
}
