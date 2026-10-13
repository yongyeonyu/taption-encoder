import Foundation

/// Reset captures job identities before returning to idle. New work is never swept.
enum PendingSaveCleanup {
    static func removeCapturedStates(_ states: [TaptionPendingSaveState], from store: any TaptionPendingSavePersisting) async {
        for state in states {
            do {
                try await store.removePendingState(id: state.id)
                if FileManager.default.fileExists(atPath: state.temporaryOutputURL.path) {
                    try FileManager.default.removeItem(at: state.temporaryOutputURL)
                }
            } catch {
                AppLogger.warning("Captured pending output cleanup failed", category: .saving,
                                  metadata: ["id": state.id.uuidString, "error": error.localizedDescription])
            }
        }
    }
}
