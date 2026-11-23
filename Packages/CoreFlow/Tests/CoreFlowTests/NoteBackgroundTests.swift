import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class NoteBackgroundTests: XCTestCase {
    private let image = CardEditingImage(data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jAhkAAAAASUVORK5CYII=")!,
        filename: "picker.jpg", mimeType: "image/jpeg")
    private let scope = NoteStoreScope(actorID: "owner", environmentID: "offline")
    private let localID = "draft"

    private func temporaryStore() async throws -> NoteLocalStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        addTeardownBlock { try await store.close(); try FileManager.default.removeItem(at: root) }
        return store
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
            image: image, expected: nil, createPlaceholder: true)
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
        let bound = try await alias.store.advanceBackground(staged, assetID: asset, phase: .submitted)
        XCTAssertEqual(bound.baseline, 0)
        XCTAssertEqual(bound.id, staged.id)
        let bytes = try await alias.store.backgroundImage(bound)
        XCTAssertEqual(bytes?.data, image.data)
    }

    func testUnreadablePresentationSurvivesBodySaveAndFailedReplacement() async throws {
        let store = try await temporaryStore()
        let original = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0,
            image: image, expected: nil, createPlaceholder: true)
        let folder = store.directoryURL.appendingPathComponent("background-commands")
        let slot = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        let broken = Data("unreadable".utf8)
        try broken.write(to: slot)
        _ = try await store.saveBody(localID: localID, body: .init(content: "independent body"))
        do { _ = try await store.background(localID: localID); XCTFail("Unreadable command became absent") }
        catch NoteBackgroundError.unreadable {}
        do {
            _ = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: original, createPlaceholder: false)
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
            _ = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: nil, createPlaceholder: false)
            XCTFail("Staged with unusable command storage")
        } catch {}
        try FileManager.default.removeItem(at: path)
        let old = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: nil, createPlaceholder: false)
        let replacement = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: old, createPlaceholder: false)
        do { try await store.retireBackground(old, current: nil, cancel: true); XCTFail("Stale removal") }
        catch NoteBackgroundError.changed {}
        let bytes = try await store.backgroundImage(replacement)
        XCTAssertEqual(bytes?.data, image.data)
        try await store.retireBackground(replacement, current: nil, cancel: true)
        let preserved = try await store.note(localID: localID)
        XCTAssertEqual(preserved?.body.content, "Keep me")
    }

    func testStrictDescriptorObservationAndRejectionEnvelopes() async throws {
        let store = try await temporaryStore()
        let command = try await store.stageBackground(localID: localID, assetID: nil, baseline: 0, image: image, expected: nil, createPlaceholder: true)
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
