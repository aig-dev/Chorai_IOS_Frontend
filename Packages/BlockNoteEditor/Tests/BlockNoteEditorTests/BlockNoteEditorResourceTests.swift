import Foundation
import XCTest
@testable import BlockNoteEditor

final class BlockNoteEditorResourceTests: XCTestCase {
    func testManifestDecodesTypedVersionsAndHashes() throws {
        let data = Data(#"""
        {
          "protocolVersion": 1,
          "schemaVersion": 1,
          "blockNoteVersion": "0.46.2",
          "hashes": {
            "editor.css": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "editor.js": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            "index.html": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
          }
        }
        """#.utf8)

        let manifest = try BlockNoteEditorResources.decodeManifest(data)

        XCTAssertEqual(manifest.protocolVersion, 1)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.blockNoteVersion, "0.46.2")
        XCTAssertEqual(manifest.hashes.editorCSS, String(repeating: "a", count: 64))
        XCTAssertEqual(manifest.hashes.editorJS, String(repeating: "b", count: 64))
        XCTAssertEqual(manifest.hashes.indexHTML, String(repeating: "c", count: 64))
    }

    func testBundledManifestMatchesSupportedProtocolAndEveryResourceHash() throws {
        let manifest = try BlockNoteEditorResources.validateBundledResources()

        XCTAssertEqual(manifest.protocolVersion, BlockNoteEditorProtocol.version)
        XCTAssertEqual(manifest.schemaVersion, BlockNoteEditorProtocol.schemaVersion)
    }

    func testBundledContentSecurityPolicyAllowsHTTPSImagesWithoutExternalNavigation() throws {
        let indexURL = try BlockNoteEditorResources.indexURL()
        let indexHTML = try String(contentsOf: indexURL, encoding: .utf8)

        XCTAssertTrue(indexHTML.contains("img-src 'self' data: blob: https:"))
        XCTAssertTrue(indexHTML.contains("connect-src 'none'"))
    }

    func testValidationRejectsUnsupportedProtocolVersionBeforeLoadingEditor() throws {
        let manifest = BlockNoteEditorResourceManifest(
            protocolVersion: 2,
            schemaVersion: 1,
            blockNoteVersion: "0.46.2",
            hashes: .init(
                editorCSS: String(repeating: "a", count: 64),
                editorJS: String(repeating: "b", count: 64),
                indexHTML: String(repeating: "c", count: 64)
            )
        )

        XCTAssertThrowsError(try BlockNoteEditorResources.validateManifest(manifest)) { error in
            XCTAssertEqual(error as? BlockNoteEditorResourceError, .unsupportedProtocolVersion(2))
        }
    }

    func testValidationRejectsAResourceWhoseBytesDoNotMatchManifest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data("css".utf8).write(to: directory.appendingPathComponent("editor.css"))
        try Data("js".utf8).write(to: directory.appendingPathComponent("editor.js"))
        try Data("html".utf8).write(to: directory.appendingPathComponent("index.html"))

        let manifest = BlockNoteEditorResourceManifest(
            protocolVersion: 1,
            schemaVersion: 1,
            blockNoteVersion: "0.46.2",
            hashes: .init(
                editorCSS: String(repeating: "0", count: 64),
                editorJS: String(repeating: "0", count: 64),
                indexHTML: String(repeating: "0", count: 64)
            )
        )

        XCTAssertThrowsError(
            try BlockNoteEditorResources.validateResourceHashes(manifest, in: directory)
        ) { error in
            guard case .hashMismatch(file: "editor.css") = error as? BlockNoteEditorResourceError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
