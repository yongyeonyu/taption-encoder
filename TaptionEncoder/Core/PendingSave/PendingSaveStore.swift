import Foundation

enum TaptionEncoderStorageLocations {
    static var documentsDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var exportedVideosDirectoryURL: URL {
        documentsDirectoryURL
            .appendingPathComponent("Taption Encoder Outputs", isDirectory: true)
    }

    static var appSupportDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaptionEncoder", isDirectory: true)
    }

    static var pendingEncodedVideosDirectoryURL: URL {
        appSupportDirectoryURL
            .appendingPathComponent("PendingEncodedVideos", isDirectory: true)
    }

    static var pendingSaveManifestURL: URL {
        appSupportDirectoryURL
            .appendingPathComponent("pending-saves.json", isDirectory: false)
    }

    static var deviceCodecReportsDirectoryURL: URL {
        appSupportDirectoryURL
            .appendingPathComponent("DeviceCodecReports", isDirectory: true)
    }
}

protocol PendingSaveStoring: TaptionPendingSavePersisting {}

actor FilePendingSaveStore: PendingSaveStoring {
    static let shared = FilePendingSaveStore()

    private let fileURL: URL
    private let recoveryDirectoryURL: URL
    private let isRegularFile: (URL) throws -> Bool

    init(fileURL: URL = FilePendingSaveStore.defaultFileURL(),
         recoveryDirectoryURL: URL = TaptionEncoderStorageLocations.pendingEncodedVideosDirectoryURL,
         isRegularFile: @escaping (URL) throws -> Bool = FilePendingSaveStore.isRegularFile) {
        self.fileURL = fileURL
        self.recoveryDirectoryURL = recoveryDirectoryURL
        self.isRegularFile = isRegularFile
    }

    static func isRegularFile(at url: URL) throws -> Bool {
        do { return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
        catch {
            let error = error as NSError
            if (error.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code))
                || (error.domain == NSPOSIXErrorDomain && error.code == 2) { return false }
            throw error
        }
    }

    func savePendingState(_ state: TaptionPendingSaveState) async throws {
        var states = try loadStoredStates()
        states.removeAll { $0.id == state.id }
        states.append(state)
        try writeStates(states.sorted { $0.createdAt < $1.createdAt })
        AppLogger.info(
            "Pending save state persisted",
            category: .saving,
            metadata: [
                "id": state.id.uuidString,
                "temporary": state.temporaryOutputURL.lastPathComponent
            ]
        )
    }

    func loadPendingStates() async throws -> [TaptionPendingSaveState] {
        let states = try loadStoredStates()
        var recoveredCount = 0
        var missingCount = 0
        var validStates: [TaptionPendingSaveState] = []

        for state in states {
            if try isRegularFile(state.temporaryOutputURL) {
                validStates.append(state)
                continue
            }

            let recoveredURL = recoveryDirectoryURL
                .appendingPathComponent(state.temporaryOutputURL.lastPathComponent)
            if try isRegularFile(recoveredURL) {
                var recoveredState = state
                recoveredState.temporaryOutputURL = recoveredURL
                validStates.append(recoveredState)
                recoveredCount += 1
            } else {
                missingCount += 1
            }
        }

        validStates.sort { $0.createdAt < $1.createdAt }

        if recoveredCount > 0 || missingCount > 0 {
            try writeStates(validStates)
            AppLogger.warning(
                "Pending save manifest was reconciled with temporary outputs",
                category: .saving,
                metadata: [
                    "stored": "\(states.count)",
                    "valid": "\(validStates.count)",
                    "recovered": "\(recoveredCount)",
                    "missing": "\(missingCount)"
                ]
            )
        }

        return validStates
    }

    func removePendingState(id: UUID) async throws {
        var states = try loadStoredStates()
        states.removeAll { $0.id == id }
        try writeStates(states)
        AppLogger.info(
            "Pending save state removed",
            category: .saving,
            metadata: ["id": id.uuidString]
        )
    }

    private func loadStoredStates() throws -> [TaptionPendingSaveState] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        return try JSONDecoder.taptionPendingSaveDecoder.decode(
            [TaptionPendingSaveState].self,
            from: data
        )
    }

    private func writeStates(_ states: [TaptionPendingSaveState]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.taptionPendingSaveEncoder.encode(states)
        try data.write(to: fileURL, options: [.atomic])
    }

    private static func defaultFileURL() -> URL {
        TaptionEncoderStorageLocations.pendingSaveManifestURL
    }
}

actor FakePendingSaveStore: PendingSaveStoring {
    static let shared = FakePendingSaveStore()

    private var states: [TaptionPendingSaveState] = []

    func savePendingState(_ state: TaptionPendingSaveState) async throws {
        states.removeAll { $0.id == state.id }
        states.append(state)
    }

    func loadPendingStates() async throws -> [TaptionPendingSaveState] {
        states
    }

    func removePendingState(id: UUID) async throws {
        states.removeAll { $0.id == id }
    }
}

private extension JSONEncoder {
    static let taptionPendingSaveEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let taptionPendingSaveDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
