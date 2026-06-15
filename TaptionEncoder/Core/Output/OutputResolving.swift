import Foundation

protocol OutputResolving {
    func outputURL(for sourceURL: URL, container: TaptionVideoContainer) throws -> URL
}

struct DefaultOutputResolver: OutputResolving {
    var namingPolicy: TaptionOutputNamingPolicy

    init(namingPolicy: TaptionOutputNamingPolicy = TaptionOutputNamingPolicy()) {
        self.namingPolicy = namingPolicy
    }

    func outputURL(for sourceURL: URL, container: TaptionVideoContainer) throws -> URL {
        namingPolicy.outputURL(for: sourceURL, container: container)
    }
}
