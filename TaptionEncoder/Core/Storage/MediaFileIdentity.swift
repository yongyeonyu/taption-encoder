import Foundation
import Darwin

/// Lexical aliases, symlinks and hard links must not turn an output into the source.
enum MediaFileIdentity {
    static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func refersToSameFile(_ first: URL, _ second: URL) -> Bool {
        guard first.isFileURL, second.isFileURL else { return first == second }
        if canonicalURL(first) == canonicalURL(second) { return true }
        var lhs = stat(), rhs = stat()
        let leftExists = first.withUnsafeFileSystemRepresentation { path in
            path.map { stat($0, &lhs) == 0 } ?? false
        }
        let rightExists = second.withUnsafeFileSystemRepresentation { path in
            path.map { stat($0, &rhs) == 0 } ?? false
        }
        return leftExists && rightExists && lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    static func validateEncodingOutput(source: URL, temporary: URL) throws {
        guard source.isFileURL, temporary.isFileURL,
              !refersToSameFile(source, temporary) else {
            throw TaptionVideoCoreError.exportFailed("The encoded output must be a separate local file from the source.")
        }
    }

    static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        return urls.filter { seen.insert($0.isFileURL ? $0.standardizedFileURL : $0).inserted }
    }

    static func folder(_ folder: URL, contains file: URL) -> Bool {
        guard folder.isFileURL, file.isFileURL else { return false }
        let root = canonicalURL(folder).path
        let parent = canonicalURL(file.deletingLastPathComponent()).path
        return parent == root || parent.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
