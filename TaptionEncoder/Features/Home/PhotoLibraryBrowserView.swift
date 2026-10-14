import Photos
import SwiftUI
import UIKit

private struct VideoAlbum: Identifiable, Sendable {
    let id: String
    let title: String
}

private enum PhotoVideoCatalog {
    static func albums() -> [VideoAlbum] {
        var albums = [VideoAlbum(id: "library", title: "Videos")]
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return albums }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil).enumerateObjects { album, _, _ in
            albums.append(VideoAlbum(id: album.localIdentifier, title: album.localizedTitle ?? "Album"))
        }
        return albums
    }

    static func videos(in albumID: String) -> [PhotoLibraryVideo] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result: PHFetchResult<PHAsset>
        if albumID == "library" { result = PHAsset.fetchAssets(with: .video, options: options) }
        else if let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject {
            result = PHAsset.fetchAssets(in: album, options: options)
        } else { return [] }
        var videos: [PhotoLibraryVideo] = []
        result.enumerateObjects { asset, _, _ in
            if let resource = PhotoLibraryVideoResource.currentResource(for: asset) {
                videos.append(PhotoLibraryVideo(id: asset.localIdentifier, fileName: resource.originalFilename, duration: asset.duration))
            }
        }
        return videos
    }
}

struct PhotoLibraryBrowserView: View {
    var onSelect: (PhotoLibrarySelection) -> Void
    var onChooseOneVideo: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var albums: [VideoAlbum] = []
    @State private var albumID = "library"
    @State private var videos: [PhotoLibraryVideo] = []
    @State private var isLoading = true
    @State private var loadOperationID = UUID()
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        NavigationStack {
            Group {
                if isLoading { ProgressView("Loading videos…") }
                else if status == .authorized || status == .limited {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 16) {
                            ForEach(videos) { video in
                                Button {
                                    onSelect(PhotoLibrarySelection(albumName: albums.first { $0.id == albumID }?.title ?? "Videos", videos: videos, selectedID: video.id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        PhotoVideoThumbnail(assetID: video.id)
                                            .frame(height: 110).clipped()
                                            .background(TaptionTheme.elevatedSurface)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        Text(video.fileName).font(.caption).lineLimit(1)
                                        Text(MediaDisplayFormatting.time(video.duration)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .foregroundStyle(TaptionTheme.primaryText)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("album.video.\(video.id)")
                                .accessibilityLabel(video.fileName)
                            }
                        }
                        .padding()
                        if videos.isEmpty { ContentUnavailableView("No videos", systemImage: "video") }
                        if status == .limited {
                            Text("Showing videos you allowed in Photos.").font(.footnote).foregroundStyle(.secondary).padding()
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Album access", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("Allow Photos access in Settings to browse an album, or choose one video.")
                    } actions: {
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                        Button("Choose one video", action: onChooseOneVideo)
                    }
                }
            }
            .navigationTitle("Album")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.accessibilityIdentifier("album.close") }
                if !albums.isEmpty {
                    ToolbarItem(placement: .principal) {
                        Picker("Album", selection: $albumID) { ForEach(albums) { Text($0.title).tag($0.id) } }
                            .pickerStyle(.menu).accessibilityIdentifier("album.collection")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task(id: albumID) { await reload(requestAccess: true) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload(requestAccess: false) } } }
    }

    @MainActor private func reload(requestAccess: Bool) async {
        let operationID = UUID()
        loadOperationID = operationID
        isLoading = true
        let access: PHAuthorizationStatus
        if requestAccess, PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else { access = PHPhotoLibrary.authorizationStatus(for: .readWrite) }
        guard loadOperationID == operationID, !Task.isCancelled else { return }
        status = access
        guard status == .authorized || status == .limited else { videos = []; albums = []; isLoading = false; return }
        let id = albumID
        let result = await Task.detached(priority: .userInitiated) { (PhotoVideoCatalog.albums(), PhotoVideoCatalog.videos(in: id)) }.value
        guard !Task.isCancelled, albumID == id, loadOperationID == operationID,
              PHPhotoLibrary.authorizationStatus(for: .readWrite) == access else { return }
        albums = result.0
        videos = result.1
        isLoading = false
    }
}

private struct PhotoVideoThumbnail: UIViewRepresentable {
    var assetID: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(); view.contentMode = .scaleAspectFill; view.clipsToBounds = true; return view
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        context.coordinator.load(assetID, into: view)
    }
    static func dismantleUIView(_ view: UIImageView, coordinator: Coordinator) { coordinator.cancel() }
    final class Coordinator {
        private var id: String?
        private var request: PHImageRequestID?
        func load(_ assetID: String, into view: UIImageView) {
            guard id != assetID else { return }
            cancel(); id = assetID; view.image = UIImage(systemName: "video")
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return }
            let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = false; options.resizeMode = .fast
            request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 320, height: 220), contentMode: .aspectFill, options: options) { [weak self, weak view] image, _ in
                DispatchQueue.main.async { guard self?.id == assetID, let image else { return }; view?.image = image }
            }
        }
        func cancel() { if let request { PHImageManager.default().cancelImageRequest(request) }; request = nil; id = nil }
        deinit { cancel() }
    }
}
