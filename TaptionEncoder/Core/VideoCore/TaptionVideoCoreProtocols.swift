import Foundation

protocol TaptionVideoInspecting {
    func inspectVideo(at url: URL) async throws -> TaptionVideoAsset
}

protocol TaptionVideoEncoding {
    func encode(
        plan: TaptionEncodingPlan,
        progress: @escaping (TaptionEncodingProgress) -> Void
    ) async throws -> TaptionEncodingResult

    func cancelEncoding(planID: UUID) async
}

protocol TaptionVideoStorageChecking {
    func storageRequirement(for plan: TaptionEncodingPlan) async throws -> TaptionStorageRequirement
}

protocol TaptionPendingSavePersisting {
    func savePendingState(_ state: TaptionPendingSaveState) async throws
    func loadPendingStates() async throws -> [TaptionPendingSaveState]
    func removePendingState(id: UUID) async throws
}

protocol TaptionSaveGateAuthorizing {
    func authorizeFinalSave(for state: TaptionPendingSaveState) async throws -> Bool
}

enum TaptionBackgroundEncodingSupport: String, Codable, Equatable {
    case unavailableKeepAppOpen
    case availableWhenUserChooses
}

struct TaptionBackgroundEncodingSnapshot: Codable, Equatable {
    var title: String
    var subtitle: String
    var fractionCompleted: Double

    init(
        title: String,
        subtitle: String,
        fractionCompleted: Double
    ) {
        self.title = title
        self.subtitle = subtitle
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
    }
}

protocol TaptionBackgroundEncodingCoordinating {
    var support: TaptionBackgroundEncodingSupport { get }
    func beginBackgroundEncoding(plan: TaptionEncodingPlan) async throws
    func updateBackgroundEncoding(planID: UUID, snapshot: TaptionBackgroundEncodingSnapshot) async
    func endBackgroundEncoding(planID: UUID) async
}

protocol TaptionVideoProjectPersisting {
    func saveProject(_ project: TaptionVideoProject, to url: URL) async throws
    func loadProject(from url: URL) async throws -> TaptionVideoProject
}

protocol TaptionFCPXMLWriting {
    func writeFCPXML(project: TaptionVideoProject, to url: URL) async throws
}

protocol TaptionFCPXMLReading {
    func readFCPXML(from url: URL) async throws -> TaptionVideoProject
}

struct TaptionVideoCoreServices {
    var inspector: TaptionVideoInspecting
    var encoder: TaptionVideoEncoding
    var storageChecker: TaptionVideoStorageChecking
    var pendingSaveStore: TaptionPendingSavePersisting
    var saveGateAuthorizer: TaptionSaveGateAuthorizing
    var backgroundCoordinator: TaptionBackgroundEncodingCoordinating?
    var projectStore: TaptionVideoProjectPersisting?

    init(
        inspector: TaptionVideoInspecting,
        encoder: TaptionVideoEncoding,
        storageChecker: TaptionVideoStorageChecking,
        pendingSaveStore: TaptionPendingSavePersisting,
        saveGateAuthorizer: TaptionSaveGateAuthorizing,
        backgroundCoordinator: TaptionBackgroundEncodingCoordinating? = nil,
        projectStore: TaptionVideoProjectPersisting? = nil
    ) {
        self.inspector = inspector
        self.encoder = encoder
        self.storageChecker = storageChecker
        self.pendingSaveStore = pendingSaveStore
        self.saveGateAuthorizer = saveGateAuthorizer
        self.backgroundCoordinator = backgroundCoordinator
        self.projectStore = projectStore
    }
}
