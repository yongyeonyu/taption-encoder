import Foundation

/// Persisted folder grants never invoke UI during restoration.
struct PreviewFolderBookmarkStore {
    static let key = "preview.authorizedFolderBookmarks"
    struct Resolution { var url: URL; var isStale: Bool }
    var defaults: UserDefaults
    var resolve: (Data) -> Resolution? = { data in
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI],
                                relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return Resolution(url: url, isStale: stale)
    }
    var create: (URL) -> Data? = { try? $0.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }

    func folders(containing file: URL) -> [URL] {
        reconciled().filter { MediaFileIdentity.folder($0.1, contains: file) }.map { $0.1 }
    }

    func remember(_ folder: URL) {
        guard let bookmark = create(folder) else { return }
        let path = MediaFileIdentity.canonicalURL(folder)
        let other = reconciled().filter { MediaFileIdentity.canonicalURL($0.1) != path }.map { $0.0 }
        defaults.set(Array(([bookmark] + other).prefix(20)), forKey: Self.key)
    }

    private func reconciled() -> [(Data, URL)] {
        let stored = defaults.array(forKey: Self.key) as? [Data] ?? []
        var seen: Set<URL> = []
        let resolved = stored.compactMap { data -> (Data, URL)? in
            guard let result = resolve(data), result.url.isFileURL,
                  seen.insert(MediaFileIdentity.canonicalURL(result.url)).inserted else { return nil }
            let renewed = result.isStale ? create(result.url) ?? data : data
            return (renewed, result.url)
        }
        let updated = resolved.map { $0.0 }
        if updated != stored { defaults.set(updated, forKey: Self.key) }
        return resolved
    }
}
