import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct ImportedPhotoVideo: Transferable {
    var url: URL
    var displayName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("TaptionPhotoImports", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let sourceName = received.file.lastPathComponent.isEmpty
                ? "PhotosVideo.mov"
                : received.file.lastPathComponent
            let destinationURL = directoryURL
                .appendingPathComponent(UUID().uuidString + "_" + sourceName)
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: received.file, to: destinationURL)
            return ImportedPhotoVideo(url: destinationURL, displayName: sourceName)
        }
    }
}
