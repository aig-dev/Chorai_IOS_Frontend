import CryptoKit
import Foundation

public struct NoteAttachmentFiles: Sendable {
    public static let previewScheme = "chorai-note-media"
    public let directoryURL: URL

    static func downloadID(assetID: String, mediaRef: String) -> String {
        // Length-delimited input prevents different asset/ref pairs from aliasing.
        "download-" + digest(Data("\(assetID.utf8.count):\(assetID)\(mediaRef)".utf8))
    }

    public static func previewURL(uploadID: String) throws -> URL {
        guard !uploadID.isEmpty, uploadID.utf8.count <= 128,
              uploadID.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
              let url = URL(string: previewScheme + "://attachment/" + uploadID) else {
            throw NoteLocalStoreError.invalidAttachment
        }
        return url
    }

    public static func previewUploadID(_ url: URL) throws -> String {
        let id = String(url.path.dropFirst())
        guard url.absoluteString == (try previewURL(uploadID: id)).absoluteString else {
            throw NoteLocalStoreError.invalidAttachment
        }
        return id
    }

    public init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directoryURL.path)
        #endif
    }

    public func retain(data: Data, filename: String, mimeType: String, uploadID: String = UUID().uuidString) throws -> NoteLocalAttachment {
        guard !data.isEmpty, !uploadID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              mimeType.hasPrefix("image/") else { throw NoteLocalStoreError.invalidAttachment }
        let relativePath = Self.digest(Data(uploadID.utf8)) + ".data"
        let attachment = NoteLocalAttachment(
            uploadID: uploadID, relativePath: relativePath, originalFilename: filename,
            mimeType: mimeType, sha256: Self.digest(data), byteCount: data.count, mediaRef: nil
        )
        let destination = directoryURL.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try read(attachment)
            return attachment
        }
        // Link a completed file exclusively: concurrent reuse of an upload ID cannot overwrite it.
        let temporary = directoryURL.appendingPathComponent(".incoming-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: temporary, options: options)
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        do { try FileManager.default.linkItem(at: temporary, to: destination) }
        catch {
            guard FileManager.default.fileExists(atPath: destination.path) else { throw error }
            _ = try read(attachment)
        }
        return attachment
    }

    public func read(_ attachment: NoteLocalAttachment) throws -> Data {
        guard attachment.relativePath == Self.digest(Data(attachment.uploadID.utf8)) + ".data" else {
            throw NoteLocalStoreError.invalidAttachment
        }
        let data = try Data(contentsOf: directoryURL.appendingPathComponent(attachment.relativePath))
        guard data.count == attachment.byteCount, Self.digest(data) == attachment.sha256 else {
            throw NoteLocalStoreError.attachmentMismatch
        }
        return data
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
