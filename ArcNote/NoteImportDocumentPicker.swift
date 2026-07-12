import CoreFlow
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

enum NoteImportDocumentDescriptorBuilder {
    static let supportedContentTypes: [UTType] = [
        UTType(importedAs: "net.daringfireball.markdown"),
        .html
    ]
    static let allowsMultipleSelection = true

    static func descriptor(for url: URL) -> NoteImportFile {
        descriptor(for: url, byteCount: -1)
    }

    static func descriptor(for url: URL, byteCount: Int64) -> NoteImportFile {
        let filename = url.lastPathComponent
        let selectionID = UUID().uuidString
        let sourceIdentity = url.standardizedFileURL.absoluteString
        let sourceDigest = SHA256.hash(data: Data(sourceIdentity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let format: NoteImportFormat
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            format = .markdown
        case "html", "htm":
            format = .html
        default:
            format = NoteImportFormat(rawValue: "unsupported")
        }
        let label = url.deletingPathExtension().lastPathComponent
        return NoteImportFile(
            id: selectionID,
            sourceKey: "ios-\(sourceDigest)",
            url: url,
            filename: filename,
            label: label.isEmpty ? filename : label,
            format: format,
            byteCount: byteCount
        )
    }
}

struct NoteImportDocumentPicker: UIViewControllerRepresentable {
    let onSelection: ([NoteImportFile]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: NoteImportDocumentDescriptorBuilder
                .supportedContentTypes,
            asCopy: false
        )
        picker.allowsMultipleSelection = NoteImportDocumentDescriptorBuilder
            .allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onSelection: ([NoteImportFile]) -> Void

        init(onSelection: @escaping ([NoteImportFile]) -> Void) {
            self.onSelection = onSelection
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onSelection(urls.map(NoteImportDocumentDescriptorBuilder.descriptor))
        }
    }
}
