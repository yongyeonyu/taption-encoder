import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct QueuePreviewFolderAccessPresenter: UIViewControllerRepresentable {
    var directoryURL: URL?
    @Binding var isPresented: Bool
    var completion: (URL?) -> Void

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

    final class Coordinator: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
        var parent: QueuePreviewFolderAccessPresenter
        private weak var picker: UIDocumentPickerViewController?
        private var isPreparing = false
        private var requestID: UUID?

        init(parent: QueuePreviewFolderAccessPresenter) { self.parent = parent }

        func present(from anchor: UIViewController) {
            guard !isPreparing, picker == nil else { return }
            isPreparing = true
            let requestID = UUID()
            self.requestID = requestID
            DispatchQueue.main.async { [weak self, weak anchor] in
                guard let self, self.requestID == requestID else { return }
                self.isPreparing = false
                guard self.parent.isPresented, let anchor, anchor.view.window != nil,
                      anchor.presentedViewController == nil else { return }
                // Let UIKit own the picker and its dismissal gestures directly.
                let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
                controller.directoryURL = self.parent.directoryURL
                controller.allowsMultipleSelection = false
                controller.delegate = self
                self.picker = controller
                anchor.present(controller, animated: true) {
                    controller.presentationController?.delegate = self
                }
            }
        }
        func dismiss() {
            requestID = nil
            isPreparing = false
            guard let controller = picker else { return }
            controller.dismiss(animated: true) { [weak self] in self?.finish(nil) }
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard picker === controller else { return }
            finish(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish(nil) }

        private func finish(_ url: URL?) {
            guard picker != nil else { return }
            picker = nil
            parent.isPresented = false
            parent.completion(url)
        }
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

