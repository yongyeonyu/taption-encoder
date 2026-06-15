import Foundation

protocol StorageChecking: TaptionVideoStorageChecking {}

struct FakeStorageChecker: StorageChecking {
    func storageRequirement(for plan: TaptionEncodingPlan) async throws -> TaptionStorageRequirement {
        TaptionStorageRequirement(
            estimatedOutputBytes: 512 * 1024 * 1024,
            requiredWorkingBytes: 1024 * 1024 * 1024,
            availableBytes: 8 * 1024 * 1024 * 1024
        )
    }
}
