import Foundation

enum TaptionFinalSaveConflictError: LocalizedError, Equatable {
    case destinationAlreadyExists(URL)

    var errorDescription: String? {
        switch self {
        case .destinationAlreadyExists(let url):
            return "A file named \(url.lastPathComponent) already exists at the save destination."
        }
    }

    static func isDestinationAlreadyExistsError(_ error: Error) -> Bool {
        if case .destinationAlreadyExists = error as? TaptionFinalSaveConflictError {
            return true
        }

        return isDestinationAlreadyExistsNSError(error as NSError)
    }

    private static func isDestinationAlreadyExistsNSError(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain,
           CocoaError.Code(rawValue: error.code) == .fileWriteFileExists {
            return true
        }

        if error.domain == NSPOSIXErrorDomain,
           error.code == Int(POSIXErrorCode.EEXIST.rawValue) {
            return true
        }

        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isDestinationAlreadyExistsNSError(underlying)
        }

        return false
    }
}

struct SaveFailurePresentation {
    var summary: String
    var cause: String
    var action: String
    var diagnostic: String

    var displayMessage: String {
        [
            summary,
            "Cause: \(cause)",
            "Fix: \(action)",
            "Log: \(diagnostic)"
        ].joined(separator: "\n")
    }

    var cardMessage: String {
        [
            "Cause: \(cause)",
            "Fix: \(action)",
            "Log: \(diagnostic)"
        ].joined(separator: "\n")
    }
}

enum TaptionSaveFailurePresenter {
    static func presentation(
        for error: Error,
        saveDestination: TaptionSaveDestinationKind,
        requiresRewardedAd: Bool
    ) -> SaveFailurePresentation {
        let diagnostic = diagnosticDescription(for: error)
        let message = error.localizedDescription
        let lowercasedMessage = message.lowercased()

        func actionWithRewardNote(_ action: String) -> String {
            guard !requiresRewardedAd else {
                return action
            }
            return action + " Retry will save without another ad."
        }

        if case .destinationAlreadyExists(let url)? = error as? TaptionFinalSaveConflictError {
            return SaveFailurePresentation(
                summary: "Could not save the encoded video.",
                cause: "A file named \(url.lastPathComponent) already exists.",
                action: actionWithRewardNote("Choose where to save the encoded video, then the export will continue."),
                diagnostic: diagnostic
            )
        }

        if TaptionFinalSaveConflictError.isDestinationAlreadyExistsError(error) {
            return SaveFailurePresentation(
                summary: "Could not save the encoded video.",
                cause: "A file already exists at the save destination.",
                action: actionWithRewardNote("Choose where to save the encoded video, then the export will continue."),
                diagnostic: diagnostic
            )
        }

        if let coreError = error as? TaptionVideoCoreError {
            switch coreError {
            case .finalSaveFailed(let detail) where containsAny(
                detail,
                ["temporary", "missing", "not found"]
            ):
                return SaveFailurePresentation(
                    summary: "Could not save the encoded video.",
                    cause: "The completed H.265 temporary file is missing.",
                    action: actionWithRewardNote("Encode this video again. If this happened after reinstalling the app, the old temporary file was removed by iOS."),
                    diagnostic: diagnostic
                )
            case .finalSaveFailed(let detail) where containsAny(
                detail,
                ["photos", "permission", "authorization", "not granted"]
            ):
                return SaveFailurePresentation(
                    summary: "Could not save the encoded video.",
                    cause: "Photos permission was not available for the final save.",
                    action: actionWithRewardNote("Allow Photos access in Settings, then retry the pending save."),
                    diagnostic: diagnostic
                )
            case .insufficientStorage:
                return SaveFailurePresentation(
                    summary: "Could not save the encoded video.",
                    cause: "The device does not have enough free storage.",
                    action: actionWithRewardNote("Free up storage, then retry the pending save."),
                    diagnostic: diagnostic
                )
            default:
                break
            }
        }

        let nsError = error as NSError
        let cocoaCode = CocoaError.Code(rawValue: nsError.code)
        if nsError.domain == NSCocoaErrorDomain,
           cocoaCode == .fileWriteOutOfSpace || containsAny(lowercasedMessage, ["no space", "not enough space"]) {
            return SaveFailurePresentation(
                summary: "Could not save the encoded video.",
                cause: "The final copy failed because the device storage is full.",
                action: actionWithRewardNote("Free up storage, then retry the pending save."),
                diagnostic: diagnostic
            )
        }

        if nsError.domain == NSCocoaErrorDomain,
           cocoaCode == .fileNoSuchFile || containsAny(lowercasedMessage, ["no such file", "missing", "not found"]) {
            return SaveFailurePresentation(
                summary: "Could not save the encoded video.",
                cause: "The app could not find the temporary encoded file or the destination folder.",
                action: actionWithRewardNote("Keep the pending item if it is shown. Reopen the original file or folder, then retry; if the temporary file is gone, encode again."),
                diagnostic: diagnostic
            )
        }

        if nsError.domain == NSCocoaErrorDomain,
           cocoaCode == .fileReadNoPermission || cocoaCode == .fileWriteNoPermission || containsAny(
            lowercasedMessage,
            ["permission", "not permitted", "operation not permitted", "access"]
        ) {
            return SaveFailurePresentation(
                summary: "Could not save the encoded video.",
                cause: "The app no longer has permission to write to the original folder.",
                action: actionWithRewardNote("Open the same file or folder again so iOS grants access, then retry the pending save."),
                diagnostic: diagnostic
            )
        }

        if saveDestination == .photosLibrary,
           containsAny(lowercasedMessage, ["photos", "album", "library"]) {
            return SaveFailurePresentation(
                summary: "Could not save the encoded video.",
                cause: "The Photos library rejected the saved video.",
                action: actionWithRewardNote("Check Photos permission and available storage, then retry the pending save."),
                diagnostic: diagnostic
            )
        }

        return SaveFailurePresentation(
            summary: "Could not save the encoded video.",
            cause: "The final save failed before the output copy completed.",
            action: actionWithRewardNote("Review the log below, fix the listed condition, then retry the pending save."),
            diagnostic: diagnostic
        )
    }

    private static func diagnosticDescription(for error: Error) -> String {
        let nsError = error as NSError
        var parts = [
            "type=\(String(reflecting: Swift.type(of: error)))",
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "message=\(nsError.localizedDescription)"
        ]

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlyingDomain=\(underlying.domain)")
            parts.append("underlyingCode=\(underlying.code)")
            parts.append("underlyingMessage=\(underlying.localizedDescription)")
        }

        return parts.joined(separator: " | ")
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
