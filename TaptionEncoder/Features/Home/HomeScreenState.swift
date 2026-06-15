import Foundation

enum HomeSourceKind: String, Equatable {
    case files = "Files"
    case photos = "Photos"
}

struct HomeSelectedSource: Identifiable, Equatable {
    var id: UUID
    var kind: HomeSourceKind
    var displayName: String
    var url: URL

    init(
        id: UUID = UUID(),
        kind: HomeSourceKind,
        displayName: String,
        url: URL
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.url = url
    }
}

struct StorageIssue: Equatable {
    var requiredBytes: Int64
    var availableBytes: Int64?
    var message: String
}

struct EncodingProgressSnapshot: Equatable {
    var stage: TaptionEncodingStage
    var fractionCompleted: Double
    var elapsedTime: TimeInterval
    var estimatedRemainingTime: TimeInterval?
    var backendLabel: String

    init(
        stage: TaptionEncodingStage,
        fractionCompleted: Double,
        elapsedTime: TimeInterval,
        estimatedRemainingTime: TimeInterval?,
        backendLabel: String
    ) {
        self.stage = stage
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.elapsedTime = max(0, elapsedTime)
        self.estimatedRemainingTime = estimatedRemainingTime
        self.backendLabel = backendLabel
    }

    var percentText: String {
        "\(Int((fractionCompleted * 100).rounded()))%"
    }

    var stageTitle: String {
        switch stage {
        case .queued:
            return "Queued"
        case .inspecting:
            return "Inspecting"
        case .preparing:
            return "Preparing"
        case .encoding:
            return "Encoding"
        case .waitingForSaveGate:
            return "Waiting to save"
        case .saving:
            return "Saving"
        case .completed:
            return "Complete"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        }
    }

    static let empty = EncodingProgressSnapshot(
        stage: .queued,
        fractionCompleted: 0,
        elapsedTime: 0,
        estimatedRemainingTime: nil,
        backendLabel: "Hardware Encoder"
    )
}

struct CompletedTemporaryOutput: Equatable {
    var planID: UUID
    var sourceName: String
    var temporaryOutputURL: URL
    var finalOutputURL: URL?
    var pendingSaveState: TaptionPendingSaveState
    var usedEncoderMode: TaptionEncoderMode
    var usedBackend: TaptionEncodingBackend
}

struct PendingSaveJob: Identifiable, Equatable {
    var id: UUID
    var sourceName: String
    var state: TaptionPendingSaveState

    init(sourceName: String, state: TaptionPendingSaveState) {
        self.id = state.id
        self.sourceName = sourceName
        self.state = state
    }
}

struct SavedOutput: Equatable {
    var displayName: String
    var destinationDescription: String
}

struct HomeEncodingError: Equatable {
    var title: String
    var message: String
}

enum HomeScreenState: Equatable {
    case idle
    case importing(HomeSelectedSource)
    case inspecting(HomeSelectedSource)
    case storageChecking(HomeSelectedSource)
    case storageBlocked(StorageIssue)
    case encoding(EncodingProgressSnapshot)
    case cancelling
    case waitingForReward(CompletedTemporaryOutput)
    case pendingSave(PendingSaveJob)
    case saving(PendingSaveJob)
    case completed(SavedOutput)
    case failed(HomeEncodingError)
    case cancelled

    var title: String {
        switch self {
        case .idle:
            return "Ready"
        case .importing:
            return "Importing"
        case .inspecting:
            return "Inspecting"
        case .storageChecking:
            return "Checking storage"
        case .storageBlocked:
            return "Storage needed"
        case .encoding(let progress):
            return progress.stageTitle
        case .cancelling:
            return "Cancelling"
        case .waitingForReward:
            return "Ready to save"
        case .pendingSave:
            return "Pending save"
        case .saving:
            return "Saving"
        case .completed:
            return "Complete"
        case .failed(let error):
            return error.title
        case .cancelled:
            return "Cancelled"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "Choose a video to begin."
        case .importing(let source):
            return "Importing \(source.displayName)."
        case .inspecting(let source):
            return "Reading codec and track details for \(source.displayName)."
        case .storageChecking:
            return "Checking temporary and final output space."
        case .storageBlocked(let issue):
            return issue.message
        case .encoding(let progress):
            return "\(progress.backendLabel) is converting the source to H.265."
        case .cancelling:
            return "Stopping the current job."
        case .waitingForReward(let output):
            if let finalOutputURL = output.finalOutputURL {
                return "\(output.sourceName) finished encoding. Watch a rewarded ad to save \(finalOutputURL.lastPathComponent)."
            }
            return "\(output.sourceName) finished encoding. Watch a rewarded ad to save."
        case .pendingSave(let job):
            return "\(job.sourceName) can be saved without re-encoding."
        case .saving(let job):
            return "Saving \(job.sourceName)."
        case .completed(let output):
            return "\(output.displayName) saved to \(output.destinationDescription)."
        case .failed(let error):
            return error.message
        case .cancelled:
            return "The encoding job was cancelled."
        }
    }

    var isBusy: Bool {
        switch self {
        case .importing, .inspecting, .storageChecking, .encoding, .cancelling, .saving:
            return true
        case .idle, .storageBlocked, .waitingForReward, .pendingSave, .completed, .failed, .cancelled:
            return false
        }
    }

    var canSelectSource: Bool {
        !isBusy
    }

    var canCancel: Bool {
        switch self {
        case .importing, .inspecting, .storageChecking, .encoding:
            return true
        case .idle, .storageBlocked, .cancelling, .waitingForReward, .pendingSave, .saving, .completed, .failed, .cancelled:
            return false
        }
    }

    var canReset: Bool {
        switch self {
        case .idle, .importing, .inspecting, .storageChecking, .encoding, .cancelling, .saving:
            return false
        case .storageBlocked, .waitingForReward, .pendingSave, .completed, .failed, .cancelled:
            return true
        }
    }

    var selectedSourceName: String? {
        switch self {
        case .importing(let source), .inspecting(let source), .storageChecking(let source):
            return source.displayName
        case .waitingForReward(let output):
            return output.sourceName
        case .pendingSave(let job), .saving(let job):
            return job.sourceName
        case .completed(let output):
            return output.displayName
        case .idle, .storageBlocked, .encoding, .cancelling, .failed, .cancelled:
            return nil
        }
    }

    var progress: EncodingProgressSnapshot? {
        switch self {
        case .encoding(let progress):
            return progress
        case .waitingForReward:
            return EncodingProgressSnapshot(
                stage: .waitingForSaveGate,
                fractionCompleted: 1,
                elapsedTime: 0,
                estimatedRemainingTime: 0,
                backendLabel: "Encoder"
            )
        case .saving:
            return EncodingProgressSnapshot(
                stage: .saving,
                fractionCompleted: 1,
                elapsedTime: 0,
                estimatedRemainingTime: 0,
                backendLabel: "Encoder"
            )
        case .completed:
            return EncodingProgressSnapshot(
                stage: .completed,
                fractionCompleted: 1,
                elapsedTime: 0,
                estimatedRemainingTime: 0,
                backendLabel: "Encoder"
            )
        case .idle, .importing, .inspecting, .storageChecking, .storageBlocked, .cancelling, .pendingSave, .failed, .cancelled:
            return nil
        }
    }

    var completedTemporaryOutput: CompletedTemporaryOutput? {
        switch self {
        case .waitingForReward(let output):
            return output
        case .idle, .importing, .inspecting, .storageChecking, .storageBlocked, .encoding, .cancelling, .pendingSave, .saving, .completed, .failed, .cancelled:
            return nil
        }
    }

    var pendingSaveJob: PendingSaveJob? {
        switch self {
        case .pendingSave(let job), .saving(let job):
            return job
        case .idle, .importing, .inspecting, .storageChecking, .storageBlocked, .encoding, .cancelling, .waitingForReward, .completed, .failed, .cancelled:
            return nil
        }
    }
}
