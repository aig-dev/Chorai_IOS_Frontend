import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NoteBackgroundTests: XCTestCase {
    private let image = CardEditingImage(data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!,
        filename: "picker.jpg", mimeType: "image/jpeg")
    private let scope = NoteStoreScope(actorID: "owner", environmentID: "offline")
    private let localID = "draft"
    private let admission = NoteBackgroundGeneration().admission(for: 0)

    private func temporaryStore() async throws -> NoteLocalStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        addTeardownBlock { try await store.close(); try FileManager.default.removeItem(at: root) }
        return store
    }

    func testCorruptRasterCannotReplaceVerifiedChoice() async throws {
        let store = try await temporaryStore()
        let good = CardEditingImage(data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!, filename: "valid.png", mimeType: "image/png")
        let staged = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: good, expected: nil, createPlaceholder: true, admission: admission)
        let damaged = CardEditingImage(data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jAhkAAAAASUVORK5CYII=")!, filename: "bad.png", mimeType: "image/png")
        do {
            _ = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: damaged, expected: staged, createPlaceholder: false, admission: admission)
            XCTFail("Replaced the existing background with a corrupt PNG")
        } catch NoteBackgroundError.invalidImage {}
        let recovered = try await store.background(localID: localID)
        XCTAssertEqual(recovered, staged)
    }

    func testRotatedJPEGFreezesGoDisplayDimensions() async throws {
        let store = try await temporaryStore()
        let raster = CardEditingImage(data: Data(base64Encoded: "/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAABgAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z")!, filename: "rotated.jpg", mimeType: "image/jpeg")
        let entry = try XCTUnwrap(raster.data.range(of: Data([0x12, 1, 3, 0, 1, 0, 0, 0])))
        let hashes = [
            "87ecb3a870e460458a87271e34417f19f40c8cf8a5ef7fecabd785e6895cd327",
            "09a9c9df9e82cd0c03e0d2675eae6387ab7b134942fa3daaa297d3583777bb05",
            "93c67e03945fef7bc7285d42a408f79771e61c45e2df30dccc57cd6fe2594469",
            "6ed56dda415e9540472c7e77f7e0f51fe72f4d3a39f0bcebb27031622673e675"
        ]
        var prior: NoteBackgroundCommand?
        for (offset, hash) in hashes.enumerated() {
            var bytes = raster.data
            bytes[entry.upperBound] = UInt8(5 + offset)
            let input = CardEditingImage(data: bytes, filename: raster.filename, mimeType: raster.mimeType)
            let selected = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: input,
                expected: prior, createPlaceholder: true, admission: admission)
            XCTAssertEqual(selected.image?.sha256, hash)
            XCTAssertEqual(selected.width, 3)
            XCTAssertEqual(selected.height, 2)
            prior = selected
        }
    }

    func testFrozenRasterFormatsAndLimitsBeforeReplacingSelection() async throws {
        let store = try await temporaryStore()
        let vectors = [
            ("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "image/png", 1, 1),
            ("R0lGODlhAgABAIAAAAAAAP///ywAAAAAAQABAAACAUwALAEAAAABAAEAAAIBTAA7", "image/gif", 2, 1),
            ("UklGRoQAAABXRUJQVlA4WAoAAAACAAAAAQAAAgAAQU5JTQYAAAD/////AABBTk1GKAAAAAAAAAAAAAEAAAIAAGQAAAJWUDhMDwAAAC8BgAAABxDlj/4HIqL/AQBBTk1GKAAAAAAAAAAAAAEAAAIAAGQAAABWUDhMDwAAAC8BgAAABxDR/v4HIqL/AQA=", "image/webp", 2, 3),
            ("/9j/4QAiRXhpZgAASUkqAAgAAAABABIBAwABAAAACAAAAAAAAAD/4AAQSkZJRgABAgAAAQABAAD//gAQTGF2YzYyLjI4LjEwMgD/2wBDAAgEBAQEBAUFBQUFBQYGBgYGBgYGBgYGBgYHBwcICAgHBwcGBgcHCAgICAkJCQgICAgJCQoKCgwMCwsODg4RERT/xABMAAEBAAAAAAAAAAAAAAAAAAAABgEBAQAAAAAAAAAAAAAAAAAABgcQAQAAAAAAAAAAAAAAAAAAAAARAQAAAAAAAAAAAAAAAAAAAAD/wAARCAADAAIDASIAAhEAAxEA/9oADAMBAAIRAxEAPwCLAE1/f//Z", "image/jpeg", 3, 2)
        ]
        var last: NoteBackgroundCommand?
        for (encoded, mime, width, height) in vectors {
            let bytes = try XCTUnwrap(Data(base64Encoded: encoded))
            let input = CardEditingImage(data: bytes, filename: "picker.jpg", mimeType: "image/jpeg")
            last = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: input,
                                                  expected: last, createPlaceholder: true, admission: admission)
            XCTAssertEqual(last?.width, width)
            XCTAssertEqual(last?.height, height)
            XCTAssertEqual(last?.image?.mimeType, mime)
            let restored = try await store.backgroundImage(XCTUnwrap(last))
            XCTAssertEqual(restored?.data, bytes)
        }
        for encoded in ["iVBORw0KGgoAAAANSUhEUgAAgAEAAAABCAQAAADC/TmdAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", "iVBORw0KGgoAAAANSUhEUgAAJxEAACcQCAQAAAD/hcGSAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="] {
            let bytes = try XCTUnwrap(Data(base64Encoded: encoded))
            do {
                _ = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0,
                    image: .init(data: bytes, filename: "huge.png", mimeType: "image/png"), expected: last, createPlaceholder: false, admission: admission)
                XCTFail("Accepted out-of-bounds image dimensions")
            } catch NoteBackgroundError.invalidImage {}
            let kept = try await store.background(localID: localID)
            XCTAssertEqual(kept, last)
        }
    }

    func testCancelPreservesReopenedBlankEditorIdentityForItsNextSave() async throws {
        let store = try await temporaryStore()
        let good = CardEditingImage(data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!, filename: "valid.png", mimeType: "image/png")
        let staged = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: good, expected: nil, createPlaceholder: true, admission: admission)
        try await store.retireBackground(staged, current: nil, cancel: true, admission: admission)
        let kept = try await store.note(localID: localID)
        XCTAssertEqual(kept?.bodyRevision, 1)
        XCTAssertNil(kept?.serverAssetID)
    }

    func testPickerOnlyPlaceholderSurvivesFullSweepAndInlineAliasWithOriginalRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sync = NoteSyncTestTransport(scope: scope)
        let library = NoteLibraryStore(rootURL: root, service: { _ in sync })
        addTeardownBlock { @MainActor in
            await library.configure(scope: nil, cloudEnabled: false)
            try FileManager.default.removeItem(at: root)
        }
        await library.configure(scope: scope, cloudEnabled: false)
        let first = try await library.backgroundTarget(identifier: nil, createID: localID, scope: scope)
        let staged = try await first.store.stageBackground(localID: localID, assetID: nil, baseline: 0,
            image: image, expected: nil, createPlaceholder: true, admission: admission)
        // The actual transferable bytes are PNG, despite the advertised JPEG representation.
        XCTAssertEqual(staged.image?.mimeType, "image/png")
        await library.configure(scope: nil, cloudEnabled: false)
        await library.configure(scope: scope, cloudEnabled: true)
        await library.synchronize(forceRetry: true)
        let empty = try await library.open(identifier: "local-note:draft", scope: scope)
        let emptyOperations = await sync.operations
        XCTAssertTrue(emptyOperations.isEmpty)
        XCTAssertEqual(empty.bodyRevision, 1)
        XCTAssertNil(empty.serverAssetID)
        XCTAssertTrue(empty.attachments.isEmpty)

        let inline = try await library.retainImage(image, identifier: nil, createID: localID, scope: scope)
        XCTAssertNotEqual(inline.mediaRef, staged.image?.uploadID)
        let body = OfflineNoteBody(content: "First accepted text")
        _ = try await library.save(identifier: nil, createID: localID, body: body, scope: scope)
        _ = try await library.save(identifier: nil, createID: localID, body: body, scope: scope)
        await library.synchronize(forceRetry: true)
        let saved = try await library.open(identifier: "local-note:draft", scope: scope)
        let asset = try XCTUnwrap(saved.serverAssetID)
        let alias = try await library.backgroundTarget(identifier: asset, createID: "different", scope: scope)
        let recovered = try await alias.store.background(localID: alias.localID)
        XCTAssertEqual(recovered, staged)
        let operations = await sync.operations
        XCTAssertEqual(operations.map(\.kind), [.create])
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: operations[0].requestBody) as? [String: Any])
        XCTAssertEqual(payload["is_public"] as? Bool, false)
        XCTAssertEqual(alias.localID, localID)
        let bound = try await alias.store.advanceBackground(staged, assetID: asset, phase: .submitted, admission: admission)
        XCTAssertEqual(bound.baseline, 0)
        XCTAssertEqual(bound.id, staged.id)
        let bytes = try await alias.store.backgroundImage(bound)
        XCTAssertEqual(bytes?.data, image.data)
    }

    func testUnreadablePresentationSurvivesBodySaveAndFailedReplacement() async throws {
        let store = try await temporaryStore()
        let original = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0,
            image: image, expected: nil, createPlaceholder: true, admission: admission)
        let folder = store.directoryURL.appendingPathComponent("background-commands")
        let slot = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let broken = Data("unreadable".utf8)
        try broken.write(to: slot)
        _ = try await store.saveBody(localID: localID, body: .init(content: "independent body"))
        do { _ = try await store.background(localID: localID); XCTFail("Unreadable command became absent") }
        catch NoteBackgroundError.unreadable {}
        do {
            _ = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: original, createPlaceholder: false, admission: admission)
            XCTFail("Unreadable command was replaced")
        } catch NoteBackgroundError.unreadable {}
        XCTAssertEqual(try Data(contentsOf: slot), broken)
        let note = try await store.note(localID: localID)
        XCTAssertEqual(note?.body.content, "independent body")
    }

    func testDiskFailureAndStaleCancelCannotLoseOriginalBytesOrBody() async throws {
        let store = try await temporaryStore()
        _ = try await store.create(body: .init(content: "Keep me"), localID: localID)
        let path = store.directoryURL.appendingPathComponent("background-commands")
        try Data().write(to: path)
        do {
            _ = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: nil, createPlaceholder: false, admission: admission)
            XCTFail("Staged with unusable command storage")
        } catch {}
        try FileManager.default.removeItem(at: path)
        let old = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: nil, createPlaceholder: false, admission: admission)
        let replacement = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: old, createPlaceholder: false, admission: admission)
        do { try await store.retireBackground(old, current: nil, cancel: true, admission: admission); XCTFail("Stale removal") }
        catch NoteBackgroundError.changed {}
        let bytes = try await store.backgroundImage(replacement)
        XCTAssertEqual(bytes?.data, image.data)
        try await store.retireBackground(replacement, current: nil, cancel: true, admission: admission)
        let preserved = try await store.note(localID: localID)
        XCTAssertEqual(preserved?.body.content, "Keep me")
    }

    func testStrictDescriptorObservationAndRejectionEnvelopes() async throws {
        let store = try await temporaryStore()
        let command = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: nil, createPlaceholder: true, admission: admission)
        let ref = "med_1234567890abcdef"
        func path(_ ref: String) -> String { "/content/" + ref }
        func envelope(_ data: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["success": true, "data": data])
        }
        let misplaced = try JSONSerialization.data(withJSONObject: ["success": false,
            "error": ["code": "CONFLICT", "reason": "stale_background", "message": "stale"]])
        XCTAssertThrowsError(try NoteBackgroundWire.upload(status: 409, data: misplaced, command: command, contentPath: path)) {
            XCTAssertEqual($0 as? NoteBackgroundError, .unknown)
        }
        let file = try XCTUnwrap(command.image)
        let descriptor: [String: Any] = ["bucket":"private","object_key":"test","media_ref":ref,"public_url":path(ref),"upload_kind":"background",
            "width":1,"height":1,"size_bytes":image.data.count,"mime":"image/png","sha256":file.sha256]
        XCTAssertEqual(try NoteBackgroundWire.upload(status: 201, data: envelope(descriptor), command: command, contentPath: path), ref)
        for (key,value) in [("width",true as Any),("height","1"),("upload_kind","inline"),("sha256","wrong"),("public_url","wrong"),("extra","unexpected")] {
            var wrong = descriptor; wrong[key] = value
            XCTAssertThrowsError(try NoteBackgroundWire.upload(status: 201, data: envelope(wrong), command: command, contentPath: path))
        }
        let actor = scope.actorID
        for revision: Any in [true, "0", -1, 9_007_199_254_740_992 as Int64] {
            XCTAssertThrowsError(try NoteBackgroundWire.observation(status: 200,
                data: envelope(["id":"asset", "owner_actor_id":actor, "background_revision":revision]), scope: scope, asset: "asset", contentPath: path))
        }
        let reject = Data(#"{"success":false,"error":{"code":"VALIDATION_ERROR","message":"Please check your input and try again."}}"#.utf8)
        XCTAssertThrowsError(try NoteBackgroundWire.upload(status: 400, data: reject, command: command, contentPath: path)) {
            XCTAssertEqual($0 as? NoteBackgroundError, .rejected)
        }
        var refresh = command; refresh.logicalRef = ref; refresh.phase = .refreshUpload
        XCTAssertThrowsError(try NoteBackgroundWire.upload(status: 400, data: reject, command: refresh, contentPath: path)) {
            XCTAssertEqual($0 as? NoteBackgroundError, .unknown)
        }
    }
}
