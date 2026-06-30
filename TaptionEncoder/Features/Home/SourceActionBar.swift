import SwiftUI

struct SourceActionBar: View {
    var canSelectSource: Bool
    var canReset: Bool
    var onFiles: () -> Void
    var onFolder: () -> Void
    var onPhotos: () -> Void
    var onReset: () -> Void
    var controlHeight: CGFloat = 44
    var buttonFont: Font = .body

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PrimaryActionButton(
                    title: "File",
                    systemImage: "doc",
                    isProminent: true,
                    isEnabled: canSelectSource,
                    height: controlHeight,
                    font: buttonFont,
                    action: onFiles
                )

                PrimaryActionButton(
                    title: "Album",
                    systemImage: "photo.on.rectangle",
                    isProminent: true,
                    isEnabled: canSelectSource,
                    height: controlHeight,
                    font: buttonFont,
                    action: onPhotos
                )

                PrimaryActionButton(
                    title: "Folder",
                    systemImage: "folder",
                    isProminent: true,
                    isEnabled: canSelectSource,
                    height: controlHeight,
                    font: buttonFont,
                    action: onFolder
                )
            }

            PrimaryActionButton(
                title: "Reset",
                systemImage: "arrow.counterclockwise",
                isProminent: false,
                isEnabled: canReset,
                height: controlHeight,
                font: buttonFont,
                action: onReset
            )
        }
    }
}
