import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// SwiftUI owns presentation, while UIKit owns navigation inside the picker.
/// Configure its starting location once, just as Taption Studio does.
struct VideoDocumentPicker: UIViewControllerRepresentable {
    var contentTypes: [UTType]
    var allowsMultipleSelection = false
    var directoryURL: URL?
    var accessibilityIdentifier: String
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void

    static func localDocumentsDirectory(fileManager: FileManager = .default) -> URL? {
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        do {
            // Keep the app's local location visible even before the first import.
            try fileManager.createDirectory(at: documents.appendingPathComponent("Videos", isDirectory: true),
                                            withIntermediateDirectories: true)
            return documents
        } catch { return nil }
    }

    func makePicker() -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
        picker.directoryURL = directoryURL
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.view.accessibilityIdentifier = accessibilityIdentifier
        return picker
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = makePicker()
        updatePicker(picker, coordinator: context.coordinator)
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {
        updatePicker(picker, coordinator: context.coordinator)
    }

    func updatePicker(_ picker: UIDocumentPickerViewController, coordinator: Coordinator) {
        // Reapplying directoryURL here would discard the user's navigation.
        coordinator.onPick = onPick
        coordinator.onCancel = onCancel
        picker.delegate = coordinator
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: ([URL]) -> Void
        var onCancel: () -> Void
        private var hasCompleted = false

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !hasCompleted else { return }
            hasCompleted = true
            onPick(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !hasCompleted else { return }
            hasCompleted = true
            onCancel()
        }
    }
}

/// Used as the sheet's content, never as a hidden controller presenting another modal.
struct QueuePreviewFolderAccessPresenter: View {
    var directoryURL: URL?
    @Binding var isPresented: Bool
    var allowsMultipleSelection: Bool
    var completion: ([URL]) -> Void

    init(directoryURL: URL?, isPresented: Binding<Bool>, completion: @escaping (URL?) -> Void) {
        self.init(directoryURL: directoryURL, isPresented: isPresented, allowsMultipleSelection: false) {
            completion($0.first)
        }
    }

    init(directoryURL: URL?, isPresented: Binding<Bool>, allowsMultipleSelection: Bool,
         completion: @escaping ([URL]) -> Void) {
        self.directoryURL = directoryURL
        self._isPresented = isPresented
        self.allowsMultipleSelection = allowsMultipleSelection
        self.completion = completion
    }

    var body: some View {
        VideoDocumentPicker(contentTypes: [.folder], allowsMultipleSelection: allowsMultipleSelection,
            directoryURL: directoryURL ?? VideoDocumentPicker.localDocumentsDirectory(),
            accessibilityIdentifier: "picker.videoFolderAccess", onPick: { urls in
                isPresented = false
                completion(urls)
            }, onCancel: {
                isPresented = false
                completion([])
            })
            .ignoresSafeArea()
    }
}

struct QueuePreviewSharePresenter: UIViewControllerRepresentable {
    var sourceURL: URL
    @Binding var isPresented: Bool
    var onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController {
        let anchor = UIViewController()
        anchor.view.backgroundColor = .clear
        anchor.view.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
        context.coordinator.parent = self
        if isPresented { context.coordinator.present(from: anchor) }
        else { context.coordinator.dismiss() }
    }

    static func dismantleUIViewController(_ anchor: UIViewController, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate, UIPopoverPresentationControllerDelegate {
        var parent: QueuePreviewSharePresenter
        private weak var activityController: UIActivityViewController?
        private var scopedURL: URL?
        private var isPreparing = false
        private var requestID: UUID?

        init(parent: QueuePreviewSharePresenter) { self.parent = parent }

        func present(from anchor: UIViewController) {
            guard !isPreparing, activityController == nil else { return }
            isPreparing = true
            let requestID = UUID()
            self.requestID = requestID
            DispatchQueue.main.async { [weak self, weak anchor] in
                guard let self, self.requestID == requestID else { return }
                self.isPreparing = false
                guard self.parent.isPresented, let anchor, anchor.view.window != nil,
                      anchor.presentedViewController == nil else { return }
                let url = self.parent.sourceURL
                if url.startAccessingSecurityScopedResource() { self.scopedURL = url }
                guard url.isFileURL, FileManager.default.isReadableFile(atPath: url.path) else {
                    self.finish()
                    self.parent.onError("This video is no longer available. Open the file again and try sharing it.")
                    return
                }
                let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                self.activityController = controller
                // UIKit requires an anchored popover on iPad; iPhone uses the native modal share sheet.
                if let popover = controller.popoverPresentationController {
                    popover.sourceView = anchor.view
                    popover.sourceRect = anchor.view.bounds
                    popover.permittedArrowDirections = [.up, .down]
                    popover.delegate = self
                }
                controller.completionWithItemsHandler = { [weak self] _, _, _, error in
                    DispatchQueue.main.async {
                        self?.finish()
                        if let error { self?.parent.onError(error.localizedDescription) }
                    }
                }
                anchor.present(controller, animated: true) {
                    controller.presentationController?.delegate = self
                }
            }
        }

        func dismiss() {
            requestID = nil
            isPreparing = false
            guard let controller = activityController else { return }
            controller.dismiss(animated: true) { [weak self] in self?.finish() }
        }

        private func finish() {
            activityController = nil
            if let url = scopedURL {
                url.stopAccessingSecurityScopedResource()
                scopedURL = nil
            }
            if parent.isPresented { parent.isPresented = false }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish() }
        func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) { finish() }

        deinit { scopedURL?.stopAccessingSecurityScopedResource() }
    }
}

