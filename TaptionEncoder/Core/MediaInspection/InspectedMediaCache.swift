import Foundation

struct TaptionInspectedMediaCache {
    private var assetsByURL: [URL: TaptionVideoAsset] = [:]
    private var recency: [URL] = []
    private let capacity: Int

    init(capacity: Int = 128) { self.capacity = max(1, capacity) }

    mutating func store(_ asset: TaptionVideoAsset, for url: URL) {
        let key = url.standardizedFileURL
        recency.removeAll { $0 == key }
        recency.append(key)
        assetsByURL[key] = asset
        while recency.count > capacity { assetsByURL.removeValue(forKey: recency.removeFirst()) }
    }

    mutating func asset(for url: URL, currentFingerprint: TaptionMediaFingerprint) -> TaptionVideoAsset? {
        let key = url.standardizedFileURL
        guard let asset = assetsByURL[key] else { return nil }
        guard asset.fingerprint == currentFingerprint else {
            assetsByURL.removeValue(forKey: key)
            recency.removeAll { $0 == key }
            return nil
        }
        recency.removeAll { $0 == key }
        recency.append(key)
        return asset
    }

    mutating func removeAll() { assetsByURL.removeAll(); recency.removeAll() }
}
