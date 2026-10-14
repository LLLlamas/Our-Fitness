// Reusable "take or pick a photo" wrapper around UIImagePickerController. The
// single shared picker for the whole app — the food-label scanner
// (Features/Nutrition/CameraFoodLogSheet.swift) uses this instead of its own
// copy, passing an explicit sourceType; callers that don't care can pass
// `ImagePickerView.preferredSourceType` (camera when available, else the
// photo library — Simulator, or a camera-less device).
//
// Present via `.sheet` (or `.fullScreenCover`); the picker fills whatever
// container presents it.

import SwiftUI
import UIKit

public struct ImagePickerView: UIViewControllerRepresentable {
    public let sourceType: UIImagePickerController.SourceType
    public let onCapture: (UIImage) -> Void
    public let onCancel: () -> Void

    /// Camera when the device has one, otherwise the photo library.
    public static var preferredSourceType: UIImagePickerController.SourceType {
        UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    }

    public init(
        sourceType: UIImagePickerController.SourceType = preferredSourceType,
        onCapture: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceType = sourceType
        self.onCapture = onCapture
        self.onCancel = onCancel
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    public func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    public final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        public func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let img = info[.originalImage] as? UIImage {
                onCapture(img)
            } else {
                onCancel()
            }
        }

        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
