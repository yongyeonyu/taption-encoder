import SwiftUI

struct SourceActionBar: View {
    var canSelectSource: Bool
    var canReset: Bool
    var onFiles: () -> Void
    var onPhotos: () -> Void
    var onReset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            PrimaryActionButton(
                title: "Files",
                systemImage: "folder",
                isProminent: true,
                isEnabled: canSelectSource,
                action: onFiles
            )

            HStack(spacing: 10) {
                PrimaryActionButton(
                    title: "Photos",
                    systemImage: "photo.on.rectangle",
                    isProminent: false,
                    isEnabled: canSelectSource,
                    action: onPhotos
                )

                PrimaryActionButton(
                    title: "Reset",
                    systemImage: "arrow.counterclockwise",
                    isProminent: false,
                    isEnabled: canReset,
                    action: onReset
                )
            }
        }
    }
}
