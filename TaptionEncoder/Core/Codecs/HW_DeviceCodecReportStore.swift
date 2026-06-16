import Foundation

struct HW_DeviceCodecReportSnapshot: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = 6

    var id: String
    var schemaVersion: Int
    var createdAt: Date
    var report: TaptionDeviceCodecCapabilityReport
    var routeSimulationSummary: HW_CodecRouteSimulationSummary
    var staticMatrixReconciliation: HW_DeviceCodecReportReconciliation?
    var universalCodecCompletionAudit: TaptionUniversalCodecCompletionAuditReport?
    var outputReadinessCatalog: TaptionOutputReadinessCatalogReport?
    var audioOutputReadinessCatalog: TaptionAudioOutputReadinessCatalogReport?

    init(
        id: String? = nil,
        schemaVersion: Int = Self.currentSchemaVersion,
        createdAt: Date,
        report: TaptionDeviceCodecCapabilityReport,
        routeSimulationSummary: HW_CodecRouteSimulationSummary,
        staticMatrixReconciliation: HW_DeviceCodecReportReconciliation? = nil,
        universalCodecCompletionAudit: TaptionUniversalCodecCompletionAuditReport? = nil,
        outputReadinessCatalog: TaptionOutputReadinessCatalogReport? = nil,
        audioOutputReadinessCatalog: TaptionAudioOutputReadinessCatalogReport? = nil
    ) {
        self.id = id ?? Self.makeID(
            modelIdentifier: report.modelIdentifier,
            createdAt: createdAt
        )
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.report = report
        self.routeSimulationSummary = routeSimulationSummary
        self.staticMatrixReconciliation = staticMatrixReconciliation
        self.universalCodecCompletionAudit = universalCodecCompletionAudit
        self.outputReadinessCatalog = outputReadinessCatalog
        self.audioOutputReadinessCatalog = audioOutputReadinessCatalog
    }

    private static func makeID(
        modelIdentifier: String,
        createdAt: Date
    ) -> String {
        let timestamp = Int(createdAt.timeIntervalSince1970.rounded(.down))
        return "\(HW_DeviceCodecReportStore.sanitizedFileComponent(modelIdentifier))-\(timestamp)"
    }
}

struct HW_DeviceCodecReportReconciliation: Codable, Equatable {
    var modelIdentifier: String
    var matchedMarketingName: String?
    var matchedProfileID: String?
    var expectedHardwareDecodeCodecs: [TaptionVideoCodec]
    var expectedHardwareEncodeCodecs: [TaptionVideoCodec]
    var probedHardwareDecodeCodecs: [TaptionVideoCodec]
    var probedHardwareEncodeCodecs: [TaptionVideoCodec]
    var missingExpectedDecodeCodecs: [TaptionVideoCodec]
    var missingExpectedEncodeCodecs: [TaptionVideoCodec]
    var unexpectedDecodeCodecs: [TaptionVideoCodec]
    var unexpectedEncodeCodecs: [TaptionVideoCodec]

    var isKnownModel: Bool {
        matchedProfileID != nil
    }

    var isConsistentWithStaticMatrix: Bool {
        isKnownModel
            && missingExpectedDecodeCodecs.isEmpty
            && missingExpectedEncodeCodecs.isEmpty
            && unexpectedDecodeCodecs.isEmpty
            && unexpectedEncodeCodecs.isEmpty
    }

    var statusSummary: String {
        guard isKnownModel else {
            return "Runtime model is not in the static matrix yet."
        }
        if isConsistentWithStaticMatrix {
            return "Runtime probe matches the static matrix."
        }
        return "Runtime probe differs from the static matrix."
    }
}

enum HW_DeviceCodecReportReconciler {
    static func reconcile(
        report: TaptionDeviceCodecCapabilityReport,
        modelMatrix: [HW_AppleDeviceCodecModel] = HW_AppleDeviceCodecModelMatrix.all
    ) -> HW_DeviceCodecReportReconciliation {
        let model = modelMatrix.first { $0.modelIdentifier == report.modelIdentifier }
        let expectedDecodeCodecs = model?.profile?.hardwareDecodeCodecs ?? []
        let expectedEncodeCodecs = model?.profile?.hardwareEncodeCodecs ?? []
        let probedDecodeCodecs = Set(report.videoCapabilities.compactMap { capability in
            capability.hardwareDecodeSupported == true ? capability.videoCodec : nil
        })
        let probedEncodeCodecs = Set(report.videoCapabilities.compactMap { capability in
            capability.hardwareEncodeSupported == true ? capability.videoCodec : nil
        })

        return HW_DeviceCodecReportReconciliation(
            modelIdentifier: report.modelIdentifier,
            matchedMarketingName: model?.marketingName,
            matchedProfileID: model?.profileID,
            expectedHardwareDecodeCodecs: sortCodecs(expectedDecodeCodecs),
            expectedHardwareEncodeCodecs: sortCodecs(expectedEncodeCodecs),
            probedHardwareDecodeCodecs: sortCodecs(probedDecodeCodecs),
            probedHardwareEncodeCodecs: sortCodecs(probedEncodeCodecs),
            missingExpectedDecodeCodecs: sortCodecs(expectedDecodeCodecs.subtracting(probedDecodeCodecs)),
            missingExpectedEncodeCodecs: sortCodecs(expectedEncodeCodecs.subtracting(probedEncodeCodecs)),
            unexpectedDecodeCodecs: sortCodecs(probedDecodeCodecs.subtracting(expectedDecodeCodecs)),
            unexpectedEncodeCodecs: sortCodecs(probedEncodeCodecs.subtracting(expectedEncodeCodecs))
        )
    }

    private static func sortCodecs(_ codecs: Set<TaptionVideoCodec>) -> [TaptionVideoCodec] {
        codecs.sorted { $0.rawValue < $1.rawValue }
    }
}

struct HW_DeviceCodecReportArchiveDivergence: Codable, Equatable, Identifiable {
    var id: String { snapshotID }

    var snapshotID: String
    var modelIdentifier: String
    var matchedProfileID: String?
    var missingExpectedDecodeCodecs: [TaptionVideoCodec]
    var missingExpectedEncodeCodecs: [TaptionVideoCodec]
    var unexpectedDecodeCodecs: [TaptionVideoCodec]
    var unexpectedEncodeCodecs: [TaptionVideoCodec]
}

struct HW_DeviceCodecReportArchiveSummary: Codable, Equatable {
    var snapshotCount: Int
    var knownModelSnapshotCount: Int
    var unknownModelIdentifiers: [String]
    var consistentSnapshotIDs: [String]
    var divergentSnapshotIDs: [String]
    var divergences: [HW_DeviceCodecReportArchiveDivergence]

    var hasSnapshots: Bool {
        snapshotCount > 0
    }

    var needsStaticMatrixUpdates: Bool {
        !unknownModelIdentifiers.isEmpty || !divergences.isEmpty
    }
}

enum HW_DeviceCodecReportArchiveAnalyzer {
    static func summarize(
        _ snapshots: [HW_DeviceCodecReportSnapshot]
    ) -> HW_DeviceCodecReportArchiveSummary {
        let reconciliations = snapshots.map { snapshot in
            (
                snapshot: snapshot,
                reconciliation: snapshot.staticMatrixReconciliation
                    ?? HW_DeviceCodecReportReconciler.reconcile(report: snapshot.report)
            )
        }
        let knownModelSnapshotCount = reconciliations.filter { $0.reconciliation.isKnownModel }.count
        let unknownModelIdentifiers = Set(
            reconciliations.compactMap { item in
                item.reconciliation.isKnownModel ? nil : item.reconciliation.modelIdentifier
            }
        ).sorted()
        let consistentSnapshotIDs = reconciliations
            .filter { $0.reconciliation.isConsistentWithStaticMatrix }
            .map(\.snapshot.id)
            .sorted()
        let divergentItems = reconciliations.filter { item in
            item.reconciliation.isKnownModel
                && !item.reconciliation.isConsistentWithStaticMatrix
        }
        let divergentSnapshotIDs = divergentItems
            .map(\.snapshot.id)
            .sorted()
        let divergences = divergentItems
            .map { item in
                HW_DeviceCodecReportArchiveDivergence(
                    snapshotID: item.snapshot.id,
                    modelIdentifier: item.reconciliation.modelIdentifier,
                    matchedProfileID: item.reconciliation.matchedProfileID,
                    missingExpectedDecodeCodecs: item.reconciliation.missingExpectedDecodeCodecs,
                    missingExpectedEncodeCodecs: item.reconciliation.missingExpectedEncodeCodecs,
                    unexpectedDecodeCodecs: item.reconciliation.unexpectedDecodeCodecs,
                    unexpectedEncodeCodecs: item.reconciliation.unexpectedEncodeCodecs
                )
            }
            .sorted { $0.snapshotID < $1.snapshotID }

        return HW_DeviceCodecReportArchiveSummary(
            snapshotCount: snapshots.count,
            knownModelSnapshotCount: knownModelSnapshotCount,
            unknownModelIdentifiers: unknownModelIdentifiers,
            consistentSnapshotIDs: consistentSnapshotIDs,
            divergentSnapshotIDs: divergentSnapshotIDs,
            divergences: divergences
        )
    }
}

enum HW_DeviceCodecReportStore {
    static func makeSnapshot(
        report: TaptionDeviceCodecCapabilityReport = HW_CodecCapabilityProbe.makeReport(),
        routeSimulationSummary: HW_CodecRouteSimulationSummary = HW_CodecRouteSimulator.summary(),
        createdAt: Date = Date()
    ) -> HW_DeviceCodecReportSnapshot {
        HW_DeviceCodecReportSnapshot(
            createdAt: createdAt,
            report: report,
            routeSimulationSummary: routeSimulationSummary,
            staticMatrixReconciliation: HW_DeviceCodecReportReconciler.reconcile(report: report),
            universalCodecCompletionAudit: TaptionUniversalCodecCompletionAuditor.makeReport(),
            outputReadinessCatalog: TaptionCodecOutputCatalog.makeReadinessReport(),
            audioOutputReadinessCatalog: TaptionAudioCodecOutputCatalog.makeReadinessReport()
        )
    }

    static func saveCurrentReport(
        to directoryURL: URL = TaptionEncoderStorageLocations.deviceCodecReportsDirectoryURL,
        fileManager: FileManager = .default,
        createdAt: Date = Date()
    ) throws -> URL {
        let report = HW_CodecCapabilityProbe.makeReport(generatedAt: createdAt)
        let snapshot = makeSnapshot(
            report: report,
            routeSimulationSummary: HW_CodecRouteSimulator.summary(),
            createdAt: createdAt
        )
        return try save(
            snapshot: snapshot,
            to: directoryURL,
            fileManager: fileManager
        )
    }

    static func save(
        snapshot: HW_DeviceCodecReportSnapshot,
        to directoryURL: URL = TaptionEncoderStorageLocations.deviceCodecReportsDirectoryURL,
        fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = directoryURL.appendingPathComponent(
            fileName(for: snapshot),
            isDirectory: false
        )
        let data = try encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    static func loadSnapshots(
        from directoryURL: URL = TaptionEncoderStorageLocations.deviceCodecReportsDirectoryURL,
        fileManager: FileManager = .default
    ) throws -> [HW_DeviceCodecReportSnapshot] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return try files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try decode(Data(contentsOf: $0)) }
    }

    static func encode(_ snapshot: HW_DeviceCodecReportSnapshot) throws -> Data {
        try JSONEncoder.hwDeviceCodecReportEncoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> HW_DeviceCodecReportSnapshot {
        try JSONDecoder.hwDeviceCodecReportDecoder.decode(
            HW_DeviceCodecReportSnapshot.self,
            from: data
        )
    }

    static func fileName(for snapshot: HW_DeviceCodecReportSnapshot) -> String {
        let model = sanitizedFileComponent(snapshot.report.modelIdentifier)
        let timestamp = Int(snapshot.createdAt.timeIntervalSince1970.rounded(.down))
        return "hw-codec-report-\(model)-\(timestamp).json"
    }

    static func sanitizedFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let pieces = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let sanitized = pieces.joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return sanitized.isEmpty ? "unknown" : sanitized
    }
}

private extension JSONEncoder {
    static let hwDeviceCodecReportEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let hwDeviceCodecReportDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
