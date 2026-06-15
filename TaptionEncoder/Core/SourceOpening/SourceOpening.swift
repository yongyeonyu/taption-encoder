import Foundation

enum SourceOpenRequest: Equatable {
    case files
    case photos
}

struct SourceOpenResult: Equatable {
    var sourceName: String
    var url: URL?

    init(sourceName: String, url: URL? = nil) {
        self.sourceName = sourceName
        self.url = url
    }
}

protocol SourceOpening {
    func open(request: SourceOpenRequest) async throws -> SourceOpenResult
}

struct FakeSourceOpener: SourceOpening {
    func open(request: SourceOpenRequest) async throws -> SourceOpenResult {
        switch request {
        case .files:
            return SourceOpenResult(sourceName: "Files")
        case .photos:
            return SourceOpenResult(sourceName: "Photos")
        }
    }
}
