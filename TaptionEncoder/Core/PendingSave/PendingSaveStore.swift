import Foundation

protocol PendingSaveStoring: TaptionPendingSavePersisting {}

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
