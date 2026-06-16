import UniformTypeIdentifiers

enum SupportedVideoFileExtensions {
    static let fileExtensions: [String] = Array(
        Set(
            TaptionVideoContainer.allCases
                .flatMap(\.supportedFileExtensions)
        )
    ).sorted()

    static let fileExtensionSet = Set(fileExtensions)

    static func contains(_ fileExtension: String) -> Bool {
        let normalizedExtension = fileExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return fileExtensionSet.contains(normalizedExtension)
    }
}

enum ImportableVideoTypes {
    static let fileExtensions = SupportedVideoFileExtensions.fileExtensions

    static let all: [UTType] = {
        var types: [UTType] = [
            .audiovisualContent,
            .video,
            .movie,
            .mpeg4Movie,
            .quickTimeMovie
        ]

        if let taptionVideoType = UTType("com.taption.video") {
            types.append(taptionVideoType)
        }

        for pathExtension in fileExtensions {
            if let type = UTType(filenameExtension: pathExtension),
               !types.contains(type) {
                types.append(type)
            }
        }

        return types
    }()
}
