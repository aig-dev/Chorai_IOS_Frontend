import Foundation
import XCTest
@testable import CoreFlow

final class NoteAttachmentFilesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }

    // Break caught: retaining the temporary photo picker path instead of durable original bytes.
    func testOriginalBytesAndUploadIdentitySurviveReopening() throws {
        let bytes = Data([0, 1, 255, 2, 0])
        let files = try NoteAttachmentFiles(directoryURL: root)
        let attachment = try files.retain(
            data: bytes, filename: "../../photo.png", mimeType: "image/png", uploadID: "upload-a"
        )
        let reopened = try NoteAttachmentFiles(directoryURL: root)
        XCTAssertEqual(try reopened.read(attachment), bytes)
        XCTAssertEqual(attachment.uploadID, "upload-a")
        XCTAssertEqual(attachment.originalFilename, "../../photo.png")
        XCTAssertFalse(attachment.relativePath.contains("/"))
        XCTAssertEqual(attachment.byteCount, 5)
    }

    // Break caught: allowing an existing logical upload to change content during retry.
    func testSameUploadIdentityCannotReplaceOriginalBytes() throws {
        let files = try NoteAttachmentFiles(directoryURL: root)
        let original = try files.retain(data: Data("first".utf8), filename: "a.png", mimeType: "image/png", uploadID: "same-upload")
        let replay = try files.retain(data: Data("first".utf8), filename: "a.png", mimeType: "image/png", uploadID: "same-upload")
        XCTAssertEqual(replay, original)
        XCTAssertThrowsError(try files.retain(data: Data("changed".utf8), filename: "a.png", mimeType: "image/png", uploadID: "same-upload"))
        XCTAssertEqual(try files.read(original), Data("first".utf8))
    }

    // Break caught: trusting metadata without verifying bytes after disk damage or replacement.
    func testCorruptAttachmentFailsInsteadOfUploadingDifferentBytes() throws {
        let files = try NoteAttachmentFiles(directoryURL: root)
        let original = try files.retain(data: Data("first".utf8), filename: "a.png", mimeType: "image/png", uploadID: "upload-a")
        try Data("other".utf8).write(to: root.appendingPathComponent(original.relativePath))
        XCTAssertThrowsError(try files.read(original))
    }
}
