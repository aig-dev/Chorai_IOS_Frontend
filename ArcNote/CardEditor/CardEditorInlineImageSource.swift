import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CardEditorInlineImageSource: Equatable {
    case photoLibrary
    case camera
}

private struct CardEditorInlineImageSourceDialog: ViewModifier {
    @Binding var isPresented: Bool
    let isCameraAvailable: Bool
    let onSelect: (CardEditorInlineImageSource) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Insert Body Image",
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button {
                onSelect(.photoLibrary)
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }
            .accessibilityIdentifier("cardEditorInlineImagePhotoLibrary")

            Button {
                onSelect(.camera)
            } label: {
                Label(
                    isCameraAvailable
                        ? "Take Photo"
                        : "Take Photo — Unavailable on this device",
                    systemImage: "camera"
                )
            }
            .accessibilityValue(isCameraAvailable ? "Available" : "Unavailable")
            .accessibilityHint(
                isCameraAvailable
                    ? "Opens the camera"
                    : "Camera isn't available on this device"
            )
            .accessibilityIdentifier("cardEditorInlineImageCamera")

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a source for the image in this note.")
        }
    }
}

extension View {
    func cardEditorInlineImageSourceDialog(
        isPresented: Binding<Bool>,
        isCameraAvailable: Bool,
        onSelect: @escaping (CardEditorInlineImageSource) -> Void
    ) -> some View {
        modifier(
            CardEditorInlineImageSourceDialog(
                isPresented: isPresented,
                isCameraAvailable: isCameraAvailable,
                onSelect: onSelect
            )
        )
    }
}

struct CardEditorCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.SourceType.camera
        picker.cameraCaptureMode = .photo
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject,
        UINavigationControllerDelegate,
        UIImagePickerControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onCancel: () -> Void

        init(
            onCapture: @escaping (UIImage) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
