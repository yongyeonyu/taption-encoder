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

struct FileSystemStorageChecker: StorageChecking {
    func storageRequirement(for plan: TaptionEncodingPlan) async throws -> TaptionStorageRequirement {
        let sourceBytes = plan.sourceURL.flatMap(fileSize) ?? 512 * 1024 * 1024
        let estimatedOutputBytes = max(plan.estimatedOutputBytes ?? sourceBytes, 16 * 1024 * 1024)
        let requiredWorkingBytes = max(
            sourceBytes + estimatedOutputBytes,
            estimatedOutputBytes + 256 * 1024 * 1024
        )
        let capacityURL = plan.temporaryOutputURL?.deletingLastPathComponent()
            ?? FileManager.default.temporaryDirectory
        let availableBytes = availableCapacity(at: capacityURL)

        return TaptionStorageRequirement(
            estimatedOutputBytes: estimatedOutputBytes,
            requiredWorkingBytes: requiredWorkingBytes,
            availableBytes: availableBytes
        )
    }

    private func fileSize(for url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return Int64(fileSize)
    }

    private func availableCapacity(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else {
            return nil
        }
        if let importantCapacity = values.volumeAvailableCapacityForImportantUsage {
            return importantCapacity
        }
        return values.volumeAvailableCapacity.map(Int64.init)
    }
}
