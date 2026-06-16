import XCTest
@testable import Taption_Encoder

final class ProjectDocumentTests: XCTestCase {
    func testFCPXMLProjectDocumentStoreRoundTripsTaptionProjectMetadata() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let documentURL = directoryURL.appendingPathComponent("Road-trip.fcpxml")
        let project = makeProject()
        let store = FCPXMLProjectDocumentStore()

        try await store.saveProject(project, to: documentURL, as: .fcpxml)
        let text = try String(contentsOf: documentURL, encoding: .utf8)
        let loaded = try await store.loadProject(from: documentURL)

        XCTAssertTrue(text.contains("<fcpxml version=\"1.13\">"))
        XCTAssertTrue(text.contains("<resources>"))
        XCTAssertTrue(text.contains("<project name=\"Road Trip Merge\">"))
        XCTAssertTrue(text.contains("com.taption.encoder.project-json-v1"))
        XCTAssertTrue(text.contains("<asset-clip"))
        XCTAssertEqual(loaded, project)
    }

    func testFCPXMLValidatorAcceptsGeneratedProjectDocument() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let documentURL = directoryURL.appendingPathComponent("Valid.fcpxml")
        let project = makeProject()
        let store = FCPXMLProjectDocumentStore()

        try await store.saveProject(project, to: documentURL, as: .fcpxml)
        let result = try await FCPXMLValidator().validateFCPXML(at: documentURL)

        XCTAssertEqual(result, .valid)
    }

    func testFCPXMLValidatorRejectsDocumentsWithoutRequiredTaptionStructure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.13">
          <resources/>
          <library/>
        </fcpxml>
        """

        let result = FCPXMLValidator().validate(data: Data(xml.utf8))

        XCTAssertEqual(
            result,
            .invalid(reason: "FCPXML project section is missing.")
        )
    }

    func testPhase0EnvironmentUsesRealFCPXMLProjectDocumentStore() {
        XCTAssertTrue(AppEnvironment.phase0.projectDocumentStore is FCPXMLProjectDocumentStore)
    }

    func testFCPXMLProjectDocumentStoreRejectsBundleKindUntilFCPXMLDBundleShips() async throws {
        let documentURL = temporaryDirectoryURL().appendingPathComponent("Bundle.fcpxmld")
        let project = makeProject(
            policy: TaptionFCPXMLPolicy(
                documentKind: .fcpxmld,
                dtdVersion: "1.13",
                resolvesLatestStableDTDAtWriteTime: false,
                canBundleManagedMedia: true
            )
        )
        let store = FCPXMLProjectDocumentStore()

        do {
            try await store.saveProject(project, to: documentURL, as: .fcpxmld)
            XCTFail("FCPXMLD bundle writing should remain blocked until bundle media packaging exists.")
        } catch let error as FCPXMLProjectDocumentError {
            XCTAssertEqual(error, .unsupportedDocumentKind(.fcpxmld))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFCPXMLParserRequiresTaptionEmbeddedProjectMetadata() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.13">
          <resources/>
          <library/>
        </fcpxml>
        """

        XCTAssertThrowsError(
            try TaptionFCPXMLProjectParser().parseProject(from: Data(xml.utf8))
        ) { error in
            XCTAssertEqual(
                error as? FCPXMLProjectDocumentError,
                .missingEmbeddedProjectMetadata
            )
        }
    }

    private func makeProject(
        policy: TaptionFCPXMLPolicy = TaptionFCPXMLPolicy(
            documentKind: .fcpxml,
            dtdVersion: "1.13",
            resolvesLatestStableDTDAtWriteTime: false,
            canBundleManagedMedia: false
        )
    ) -> TaptionVideoProject {
        let assetID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let segmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let sliceA = TaptionVideoSlice(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sourceRange: TaptionTimeRange(start: 1.25, duration: 4.5),
            timelineStart: 0
        )
        let sliceB = TaptionVideoSlice(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            sourceRange: TaptionTimeRange(start: 8, duration: 2),
            timelineStart: 4.5
        )
        let createdAt = Date(timeIntervalSince1970: 1_782_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_782_000_120)

        return TaptionVideoProject(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "Road Trip Merge",
            createdAt: createdAt,
            updatedAt: updatedAt,
            fcpxmlPolicy: policy,
            assets: [
                TaptionVideoAsset(
                    id: assetID,
                    displayName: "Camera A.mp4",
                    location: TaptionVideoAssetLocation(
                        kind: .file,
                        url: URL(fileURLWithPath: "/tmp/Camera A.mp4")
                    ),
                    container: .mp4,
                    duration: 12,
                    videoTrack: TaptionVideoTrackInfo(
                        codec: .h264,
                        naturalSize: TaptionPixelSize(width: 3840, height: 2160),
                        displaySize: TaptionPixelSize(width: 3840, height: 2160),
                        nominalFrameRate: TaptionRationalFrameRate(numerator: 30000, denominator: 1001),
                        estimatedBitrate: 45_000_000,
                        color: TaptionColorDescription(
                            primaries: .bt709,
                            transfer: .sRGB,
                            matrix: .bt709,
                            bitDepth: 8,
                            isHDR: false
                        )
                    ),
                    audioTracks: [
                        TaptionAudioTrackInfo(
                            codec: .aac,
                            channelCount: 2,
                            sampleRate: 48_000,
                            estimatedBitrate: 192_000
                        )
                    ]
                )
            ],
            timeline: TaptionVideoTimeline(
                canvasSize: TaptionPixelSize(width: 3840, height: 2160),
                segments: [
                    TaptionVideoSegment(
                        id: segmentID,
                        assetID: assetID,
                        displayName: "Camera A trimmed",
                        slices: [sliceA, sliceB],
                        placement: TaptionCanvasPlacement(
                            normalizedCenterX: 0.5,
                            normalizedCenterY: 0.5,
                            scale: 1,
                            rotationDegrees: 0
                        ),
                        editOperations: [.trim, .split, .reorder, .canvasPosition]
                    )
                ],
                touchWidgetAnchors: [
                    TaptionTouchWidgetAnchor(
                        segmentID: segmentID,
                        normalizedX: 0.5,
                        normalizedY: 0.5,
                        role: "move"
                    )
                ],
                normalizationPlan: TaptionMergeNormalizationPlan(
                    targetSize: TaptionPixelSize(width: 3840, height: 2160),
                    frameRate: TaptionRationalFrameRate(numerator: 30000, denominator: 1001),
                    color: TaptionColorDescription(
                        primaries: .bt709,
                        transfer: .sRGB,
                        matrix: .bt709,
                        bitDepth: 8,
                        isHDR: false
                    ),
                    audioSampleRate: 48_000,
                    decision: .userSelectedExplicitValue
                )
            )
        )
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TaptionProjectDocumentTests-\(UUID().uuidString)", isDirectory: true)
    }
}
