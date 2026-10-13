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
        let estimatedOutputBytes = StorageByteBudget.outputBytes(plan.estimatedOutputBytes ?? sourceBytes)
        let requiredWorkingBytes = StorageByteBudget.workingBytes(source: sourceBytes, output: estimatedOutputBytes)
        let capacityURL = plan.temporaryOutputURL?.deletingLastPathComponent()
            ?? FileManager.default.temporaryDirectory
        let availableBytes = availableCapacity(at: Self.existingAncestor(of: capacityURL))

        return TaptionStorageRequirement(
            estimatedOutputBytes: estimatedOutputBytes,
            requiredWorkingBytes: requiredWorkingBytes,
            availableBytes: availableBytes
        )
    }

    static func existingAncestor(of url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { break }
            candidate = parent
        }
        return candidate
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

/// Filesystem metadata and estimates are untrusted numeric inputs.
enum StorageByteBudget {
    static func outputBytes(_ estimate: Int64) -> Int64 { max(estimate, 16 * 1024 * 1024) }
    static func workingBytes(source: Int64, output: Int64) -> Int64 {
        let output = outputBytes(output)
        return max(adding(max(0, source), output), adding(output, 256 * 1024 * 1024))
    }
    private static func adding(_ left: Int64, _ right: Int64) -> Int64 {
        let (value, overflow) = left.addingReportingOverflow(right)
        return overflow ? Int64.max : value
    }
}
