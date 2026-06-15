import Foundation

protocol ProjectDocumentStoring: TaptionVideoProjectPersisting {
    func saveProject(_ project: TaptionVideoProject, to url: URL, as kind: TaptionProjectDocumentKind) async throws
}

struct FakeProjectFileStore: ProjectDocumentStoring {
    func saveProject(_ project: TaptionVideoProject, to url: URL) async throws {}

    func saveProject(_ project: TaptionVideoProject, to url: URL, as kind: TaptionProjectDocumentKind) async throws {}

    func loadProject(from url: URL) async throws -> TaptionVideoProject {
        TaptionVideoProject(title: url.deletingPathExtension().lastPathComponent)
    }
}
