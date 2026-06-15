import Foundation

enum AdGateDecision: String, Equatable {
    case allowed
    case unavailable
    case skipped
}

protocol AdGate: TaptionSaveGateAuthorizing {
    func requestSaveAuthorization(for state: TaptionPendingSaveState) async throws -> AdGateDecision
}

struct FakeAdGate: AdGate {
    func requestSaveAuthorization(for state: TaptionPendingSaveState) async throws -> AdGateDecision {
        .allowed
    }

    func authorizeFinalSave(for state: TaptionPendingSaveState) async throws -> Bool {
        try await requestSaveAuthorization(for: state) == .allowed
    }
}
