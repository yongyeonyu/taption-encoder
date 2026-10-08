import SwiftUI

struct SourceActionBar: View {
    var canSelectSource: Bool
    var onFiles: () -> Void
    var onFolder: () -> Void
    var onPhotos: () -> Void
    var controlHeight: CGFloat = 44
    var buttonFont: Font = .body

    var body: some View {
            HStack(spacing: 10) {
                PrimaryActionButton(
                    title: "File",
                    systemImage: "doc",
                    isProminent: false,
                    isEnabled: canSelectSource,
                    height: controlHeight,
                    font: buttonFont,
                    action: onFiles
                )

                PrimaryActionButton(
                    title: "Album",
                    systemImage: "photo.on.rectangle",
                    isProminent: false,
                    isEnabled: canSelectSource,
                    height: controlHeight,
                    font: buttonFont,
                    action: onPhotos
                )

                PrimaryActionButton(
                    title: "Folder",
                    systemImage: "folder",
                    isProminent: false,
                    isEnabled: canSelectSource,
                    height: controlHeight,
                    font: buttonFont,
                    action: onFolder
                )
            }

    }
}
