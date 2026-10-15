import Foundation

/// Owns each successful scope acquisition exactly once. Use from the owning actor.
final class SecurityScopedAccessStore {
    private var acquired: [URL: URL] = [:]
    private let start: (URL) -> Bool
    private let stop: (URL) -> Void

    init(start: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stop: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.start = start
        self.stop = stop
    }

    var count: Int { acquired.count }
    func contains(_ url: URL) -> Bool { acquired[url.standardizedFileURL] != nil }

    @discardableResult
    func acquire(_ url: URL) -> Bool {
        let key = url.standardizedFileURL
        if acquired[key] != nil { return true }
        guard start(url) else { return false }
        acquired[key] = url
        return true
    }

    func release(_ url: URL) {
        if let original = acquired.removeValue(forKey: url.standardizedFileURL) { stop(original) }
    }

    func replace(with urls: [URL]) {
        // A picker-to-player handoff must not briefly revoke a shared folder grant.
        let requested = Set(urls.map(\.standardizedFileURL))
        for url in urls { acquire(url) }
        for key in Array(acquired.keys) where !requested.contains(key) { release(key) }
    }

    func releaseAll() {
        let urls = Array(acquired.values)
        acquired.removeAll()
        for url in urls { stop(url) }
    }

    deinit { releaseAll() }
}
