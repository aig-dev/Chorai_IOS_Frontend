import CFNetwork
import CoreImage
import CryptoKit
import Network
import UIKit
import XCTest
import os

@MainActor
final class RecentNotesSyncUITests: XCTestCase {
    func testUnrelatedSameSessionCreateCannotAuthorizeCleanup() async throws {
        let server = try RecentNotesServer(libraryFixture: .twoCreates)
        defer { server.stop() }
        let upstream = try server.start()
        let proxy = try OrdinaryGoProxy(upstreamOrigin: upstream)
        defer { proxy.stop() }
        let origin = try proxy.start()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try OrdinaryFixtureJournal(directory: directory, actor: server.actorID, origin: upstream)
        let local = "local-note:T"
        try journal.expectLocal(local, appOrigin: origin)
        proxy.captureCreation(journal, token: server.token)

        @Sendable func post(_ key: String) async throws -> String {
            var request = URLRequest(url: try XCTUnwrap(URL(string: origin + "/api/cards")))
            request.httpMethod = "POST"
            request.setValue("Bearer " + server.token, forHTTPHeaderField: "Authorization")
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
            let (bytes, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            return try XCTUnwrap((envelope["data"] as? [String: Any])?["id"] as? String)
        }
        async let target = post("target-create")
        await fulfillment(of: [server.targetRequested], timeout: 5)
        let other = try await post("other-create")
        XCTAssertEqual(other, "asset-other-create")
        var dispatched: [String] = []
        func teardown() throws {
            try journal.clean(actor: server.actorID, origin: upstream, token: server.token, baseline: { _ in "base" }, send: { req in
                dispatched.append(try XCTUnwrap(req.url?.path))
                let key = try XCTUnwrap(req.value(forHTTPHeaderField: "Idempotency-Key"))
                let asset = "asset-target-create"
                let data: [String: Any] = req.url?.lastPathComponent == "permanent"
                    ? ["asset_id": asset, "request_id": key, "state": "ERASED", "activity_id": "act", "action_log_id": "log", "certificate_id": "cert", "cleanup_state": "COMPLETE"]
                    : ["sync_receipt": ["asset_id": asset, "operation_id": key, "lifecycle": "trashed"]]
                return try JSONSerialization.data(withJSONObject: ["success": true, "data": data])
            })
        }
        XCTAssertThrowsError(try teardown())
        XCTAssertTrue(dispatched.isEmpty, "A valid receipt for another note cannot authorize cleanup of T")
        server.releaseTargetCreation()
        let targetAsset = try await target
        XCTAssertEqual(targetAsset, "asset-target-create")
        // The confirmed local mapping for T becomes visible after its receipt.
        XCTAssertThrowsError(try proxy.bindAcknowledgement(journal, actor: server.actorID, appOrigin: origin, local: "local-note:other", asset: other))
        XCTAssertThrowsError(try proxy.bindAcknowledgement(journal, actor: server.actorID, appOrigin: upstream, local: local, asset: targetAsset))
        XCTAssertThrowsError(try proxy.bindAcknowledgement(journal, actor: "other", appOrigin: origin, local: local, asset: targetAsset))
        XCTAssertThrowsError(try proxy.bindAcknowledgement(journal, actor: server.actorID, appOrigin: origin, local: local, asset: "no-receipt"))
        XCTAssertThrowsError(try teardown())
        XCTAssertTrue(dispatched.isEmpty)
        try proxy.bindAcknowledgement(journal, actor: server.actorID, appOrigin: origin, local: local, asset: targetAsset)
        XCTAssertThrowsError(try proxy.bindAcknowledgement(journal, actor: server.actorID, appOrigin: origin, local: local, asset: other))
        try teardown()
        XCTAssertEqual(dispatched, ["/api/cards/" + targetAsset, "/api/cards/trash/" + targetAsset + "/permanent"])
    }

    func testOrdinaryCleanupPersistsBothRequestsBeforeSendingAndResumesAfterLostReceipt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let origin = "http://localhost"
        let journal = try OrdinaryFixtureJournal(directory: directory, actor: "owner", origin: origin)
        try journal.recordDirectCreate(asset: "owned")
        XCTAssertThrowsError(try journal.recordDirectCreate(asset: "unrelated"))
        var attempts = [OrdinaryFixtureJournal.Command]()
        var baselines = ["active-base", "trash-base"]
        var acknowledged = Set<String>()

        func exercise(_ entry: OrdinaryFixtureJournal, actor: String = "owner") throws {
            try entry.clean(actor: actor, origin: origin, token: "fixture-token", baseline: { asset in
                XCTAssertEqual(asset, "owned")
                return try XCTUnwrap(baselines.isEmpty ? nil : baselines.removeFirst())
            }, send: { request in
                let disk = try OrdinaryFixtureJournal(reopening: journal.file).snapshot()
                let command = try XCTUnwrap(disk.commands.last)
                XCTAssertEqual(request.httpMethod, command.method)
                XCTAssertEqual(request.url?.absoluteString, origin + command.path)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), command.key)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), command.contentType)
                XCTAssertEqual(request.httpBody, command.body, "The exact outgoing bytes must already be on disk")
                XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: command.body),
                               ["base_sync_token": command.baseline])
                attempts.append(command)
                // Each first request commits at the fixture. Its acknowledgement is lost.
                guard !acknowledged.insert(command.key).inserted else { throw URLError(.networkConnectionLost) }
                let data: [String: Any]
                if command.path.hasSuffix("/permanent") {
                    data = ["asset_id": "owned", "request_id": command.key, "state": "ERASED",
                            "activity_id": "activity", "action_log_id": "log", "certificate_id": "cert", "cleanup_state": "COMPLETE"]
                } else {
                    data = ["sync_receipt": ["asset_id": "owned", "operation_id": command.key, "lifecycle": "trashed"]]
                }
                return try JSONSerialization.data(withJSONObject: ["success": true, "data": data])
            })
        }
        XCTAssertThrowsError(try exercise(journal, actor: "other"))
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertThrowsError(try exercise(journal))
        XCTAssertFalse(try XCTUnwrap(journal.snapshot().commands.last).acknowledged)
        XCTAssertThrowsError(try exercise(OrdinaryFixtureJournal(reopening: journal.file)))
        XCTAssertFalse(try XCTUnwrap(journal.snapshot().commands.last).acknowledged)
        try exercise(OrdinaryFixtureJournal(reopening: journal.file))
        try exercise(OrdinaryFixtureJournal(reopening: journal.file))
        XCTAssertEqual(attempts.count, 4)
        XCTAssertEqual(attempts[0], attempts[1])
        XCTAssertEqual(attempts[2], attempts[3])
        XCTAssertNotEqual(attempts[0].key, attempts[2].key)
        XCTAssertEqual(acknowledged.count, 2)
        XCTAssertTrue(try journal.snapshot().commands.allSatisfy(\.acknowledged))
    }

    func testOrdinaryProxyRecordsKeylessWritesAtIngress() async throws {
        let proxy = try OrdinaryGoProxy()
        defer { proxy.stop() }
        let origin = try proxy.start()
        proxy.setOffline(true)
        try await sendIsolatedUpdate(origin, key: nil, body: "keyless")
        let mutation = try XCTUnwrap(proxy.mutations.first)
        XCTAssertEqual(mutation.method, "PUT")
        XCTAssertEqual(mutation.path, "/api/cards/fixture")
        XCTAssertEqual(mutation.digest, Data(SHA256.hash(data: Data("keyless".utf8))))
        XCTAssertNil(mutation.key)
        XCTAssertTrue(mutation.transportFailed)
        XCTAssertEqual(proxy.mutations.count, 1)
    }

    func testOrdinaryReplayRejectsIntermediateKeyAndBodyChanges() async throws {
        let proxy = try OrdinaryGoProxy()
        defer { proxy.stop() }
        let origin = try proxy.start()
        proxy.setOffline(true)
        for (key, body) in [("original", "body"), ("different", "body"), ("original", "changed"), ("original", "body")] {
            try await sendIsolatedUpdate(origin, key: key, body: body)
        }
        let attempts = proxy.mutations
        XCTAssertEqual(attempts.count, 4)
        XCTAssertFalse(OrdinaryGoProxy.sameFrozenRequest([attempts[0], attempts[1], attempts[3]]))
        XCTAssertFalse(OrdinaryGoProxy.sameFrozenRequest([attempts[0], attempts[2], attempts[3]]))
        XCTAssertTrue(OrdinaryGoProxy.sameFrozenRequest([attempts[0], attempts[3]]))
    }

    private func sendIsolatedUpdate(_ origin: String, key: String?, body: String) async throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: origin + "/api/cards/fixture")))
        request.httpMethod = "PUT"
        request.httpBody = Data(body.utf8)
        request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        do {
            _ = try await URLSession.shared.data(for: request)
            XCTFail("The isolated transport must drop this request")
        } catch is URLError {}
    }

    func testOnlineRestrictedVerificationRemovesExistingLocalAccess() throws {
        let server = try RecentNotesServer()
        defer { server.stop() }
        let app = XCUIApplication()
        app.launchEnvironment = [
            APIEnvironment.overrideEnvironmentKey: try server.start(),
            "CHORAI_UI_TEST": "1",
            "CHORAI_UI_TEST_AUTH_TOKEN": server.token,
            "CHORAI_UI_TEST_ACTOR_ID": server.actorID
        ]
        defer { app.terminate() }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "CHORAI_UI_TEST_AUTH_TOKEN")
        app.launchEnvironment.removeValue(forKey: "CHORAI_UI_TEST_ACTOR_ID")
        server.restrictVerification()
        app.launch()
        XCTAssertTrue(app.textFields["access.code"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
        app.terminate()
        server.stop()
        app.launch()
        XCTAssertTrue(app.textFields["access.code"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
    }

    func testOtherDevicePhotoRendersOnHomeAfterOfflineRelaunch() throws {
        continueAfterFailure = false
        let server = try RecentNotesServer(includesRemoteImage: true)
        let tile = CGRect(x: 0, y: 0, width: 64, height: 48)
        server.serveImage(UIGraphicsImageRenderer(size: tile.size).pngData { canvas in
            UIColor.magenta.setFill()
            canvas.fill(tile)
        })
        defer { server.stop() }
        let app = XCUIApplication()
        app.launchEnvironment = [
            APIEnvironment.overrideEnvironmentKey: try server.start(),
            "CHORAI_UI_TEST": "1",
            "CHORAI_UI_TEST_AUTH_TOKEN": server.token,
            "CHORAI_UI_TEST_ACTOR_ID": server.actorID
        ]
        defer { app.terminate() }

        func openLibraryAndVerifyPhoto() {
            app.launch()
            let home = app.tabBars.buttons["Home"]
            XCTAssertTrue(home.waitForExistence(timeout: 15))
            home.tap()
            // Check the rendered image itself. The row's label is also present on loading and failure placeholders.
            let context = CIContext()
            let showsPhoto = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard let shot = app.screenshot().image.cgImage else { return false }
                let sample = CIImage(cgImage: shot).transformed(by: CGAffineTransform(scaleX: 0.1, y: 0.1))
                let bounds = sample.extent.integral
                let rowBytes = Int(bounds.width) * 4
                var bytes = [UInt8](repeating: 0, count: rowBytes * Int(bounds.height))
                context.render(sample, toBitmap: &bytes, rowBytes: rowBytes, bounds: bounds, format: .RGBA8,
                               colorSpace: CGColorSpaceCreateDeviceRGB())
                return stride(from: 0, to: bytes.count, by: 4).filter { i in
                    bytes[i] > 220 && bytes[i + 1] < 45 && bytes[i + 2] > 210
                }.count > 120
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [showsPhoto], timeout: 12), .completed)
        }

        openLibraryAndVerifyPhoto()
        XCTAssertEqual(server.imageContentReads, 1)
        app.terminate()
        server.serveImage(nil)
        openLibraryAndVerifyPhoto()
        XCTAssertEqual(server.imageContentReads, 1)
    }

    func testBackKeepsLocalEditsAndCloudConflictOfflineWithUndownloadedImage() throws {
        try assertBackKeepsLocalEdits(after: .changed)
    }

    func testBackKeepsLocalEditsWhenCloudNoteIsUnavailable() throws {
        try assertBackKeepsLocalEdits(after: .removed)
    }

    private func assertBackKeepsLocalEdits(after change: RecentNotesServer.RemoteChange) throws {
        continueAfterFailure = false
        let server = try RecentNotesServer(includesRemoteImage: true)
        defer { server.stop() }
        let app = XCUIApplication()
        app.launchEnvironment = [
            APIEnvironment.overrideEnvironmentKey: try server.start(),
            "CHORAI_UI_TEST": "1",
            "CHORAI_UI_TEST_AUTH_TOKEN": server.token,
            "CHORAI_UI_TEST_ACTOR_ID": server.actorID
        ]
        defer { app.terminate() }

        let home = app.tabBars.buttons["Home"]
        let editor = app.descendants(matching: .any).matching(identifier: "cardEditorBodyWebView").firstMatch
        let close = app.buttons["cardEditorLeadingAction"]
        func openLibrary() {
            app.launch()
            XCTAssertTrue(home.waitForExistence(timeout: 15))
            home.tap()
        }
        func preview(containing text: String) -> XCUIElement {
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        func typeInNote(_ text: String) {
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            editor.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.035)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
            app.typeText(text)
        }

        openLibrary()
        let recent = preview(containing: "Recent field note 22")
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        if change == .removed {
            // The server removes this note before the user opens or edits it.
            server.releaseManifest(changingRecentNote: change)
            XCTAssertTrue(preview(containing: "Archived field note 2").waitForExistence(timeout: 10))
        }
        recent.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        if change == .changed {
            typeInNote("First edit ")
            XCTAssertTrue(app.staticTexts["Saved on this device · Waiting to sync"].waitForExistence(timeout: 10))
            server.releaseManifest(changingRecentNote: change)
        }
        // Wait until the editor has observed the remote decision, then take its only server offline.
        let status = change == .changed ? "Cloud version changed" : "Cloud version unavailable"
        let versions = app.buttons["cardEditorVersionOptions"]
        XCTAssertTrue(versions.waitForExistence(timeout: 15))
        XCTAssertTrue(versions.label.contains(status))
        XCTAssertEqual(XCTWaiter.wait(for: [server.remoteImageRequested], timeout: 5), .completed)
        server.stop()

        let edit = "Kept on this phone"
        typeInNote(edit)
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Close note"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 8), .completed)
        close.tap()
        XCTAssertTrue(home.waitForExistence(timeout: 5), "Back must leave a locally saved note while resolution is deferred")
        XCTAssertFalse(editor.exists)
        app.terminate()
        openLibrary()
        let savedPreview = preview(containing: edit)
        XCTAssertTrue(savedPreview.waitForExistence(timeout: 10))
        savedPreview.tap()
        XCTAssertTrue(versions.waitForExistence(timeout: 10), "The original note must retain the unresolved remote state")
        XCTAssertTrue(versions.label.contains(status))
        versions.tap()
        let cloud = app.buttons["Use cloud version"]
        let keep = app.buttons["Keep mine as a new note"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        XCTAssertEqual(cloud.exists, change == .changed, "Replacing local edits requires a retained cloud snapshot")
        if change == .changed {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS %@", "replaces your local edits"
            )).firstMatch.exists)
            cloud.tap()
            XCTAssertTrue(preview(containing: "Changed on the server").waitForExistence(timeout: 10))
            XCTAssertFalse(savedPreview.exists)
        } else {
            XCTAssertTrue(app.staticTexts["Cloud version unavailable"].exists)
            let cancel = app.buttons["Cancel"].firstMatch
            let dismiss = cancel.exists ? cancel : app.otherElements["PopoverDismissRegion"].firstMatch
            XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
            dismiss.tap()
            XCTAssertTrue(editor.exists)
            XCTAssertFalse(keep.exists)
        }
    }

    func testLocallySavedPhotoCanCloseAndReopenWhileSyncIsUnavailable() throws {
        try assertPhotoCanReopen(newNote: false)
    }

    func testPhotoOnlyDraftCanReopenFromLibraryWhileSyncIsUnavailable() throws {
        try assertPhotoCanReopen(newNote: true)
    }

    private func assertPhotoCanReopen(newNote: Bool) throws {
        continueAfterFailure = false
        let server = try RecentNotesServer()
        defer { server.stop() }
        let app = XCUIApplication()
        app.launchEnvironment = [
            APIEnvironment.overrideEnvironmentKey: try server.start(),
            "CHORAI_UI_TEST": "1",
            "CHORAI_UI_TEST_AUTH_TOKEN": server.token,
            "CHORAI_UI_TEST_ACTOR_ID": server.actorID
        ]
        defer { app.terminate() }

        let home = app.tabBars.buttons["Home"]
        let recent = app.staticTexts.matching(NSPredicate(format: "label == %@", "Recent field note 22")).firstMatch
        let editor = app.descendants(matching: .any).matching(identifier: "cardEditorBodyWebView").firstMatch
        let image = app.images.matching(NSPredicate(format: "label == %@", "Inline image")).firstMatch
        func openLibrary() {
            app.launch()
            XCTAssertTrue(home.waitForExistence(timeout: 15))
            home.tap()
            XCTAssertTrue(recent.waitForExistence(timeout: 15))
        }

        // Withholding the manifest for both launches keeps every local change unacknowledged.
        openLibrary()
        if newNote {
            app.buttons.matching(identifier: "note.create").firstMatch.tap()
        } else {
            recent.tap()
        }
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.10)).tap()
        let insertPhoto = app.buttons["cardEditorFormatInlineImage"]
        XCTAssertTrue(insertPhoto.waitForExistence(timeout: 8))
        insertPhoto.tap()
        app.buttons.matching(identifier: "cardEditorInlineImagePhotoLibrary").firstMatch.tap()
        let pickerImage = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        let item = pickerImage.waitForExistence(timeout: 5) ? pickerImage : app.collectionViews.cells.firstMatch
        guard item.waitForExistence(timeout: 3) else { throw XCTSkip("The simulator photo library needs a fixture image") }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: item.frame.midX, dy: item.frame.midY)).tap()
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Saved on this device · Waiting to sync"].waitForExistence(timeout: 10))

        let close = app.buttons["cardEditorLeadingAction"]
        XCTAssertEqual(close.label, "Close note")
        close.tap()
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists, "The current editor snapshot was already saved locally")

        app.terminate()
        openLibrary()
        if newNote {
            // This fixture has exactly one note containing a picture.
            let thumbnail = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "home.card.body.local-note:", "Inline image")
            ).firstMatch
            XCTAssertTrue(thumbnail.waitForExistence(timeout: 10), "A photo-only note needs a visible, tappable preview")
            XCTAssertGreaterThan(thumbnail.frame.height, 0)
            thumbnail.tap()
        } else {
            recent.tap()
        }
        XCTAssertTrue(image.waitForExistence(timeout: 10), "Reopening must load the saved local bytes")
    }

    func testNewPhoneCanEditRecentNoteWhileHistoryIsUnavailable() throws {
        continueAfterFailure = false
        let server = try RecentNotesServer()
        defer { server.stop() }
        let app = XCUIApplication()
        app.launchEnvironment = [
            APIEnvironment.overrideEnvironmentKey: try server.start(),
            "CHORAI_UI_TEST": "1",
            "CHORAI_UI_TEST_AUTH_TOKEN": server.token,
            "CHORAI_UI_TEST_ACTOR_ID": server.actorID
        ]
        defer { app.terminate() }

        func openLibrary() {
            app.launch()
            let home = app.tabBars.buttons["Home"]
            XCTAssertTrue(home.waitForExistence(timeout: 15), "The verified account should enter the normal app")
            home.tap()
        }
        func preview(_ text: String) -> XCUIElement {
            app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
        }

        openLibrary()
        XCTAssertEqual(XCTWaiter.wait(for: [server.manifestRequested], timeout: 10), .completed)
        let recent = preview("Recent field note 22")
        XCTAssertTrue(recent.waitForExistence(timeout: 6), "The newest full note must be readable while the complete manifest is withheld")
        XCTAssertTrue(preview("Recent field note 21").exists)
        XCTAssertFalse(preview("Archived field note 2").exists)

        recent.tap()
        let editor = app.descendants(matching: .any).matching(identifier: "cardEditorBodyWebView").firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.10)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        let edit = "Changed on this phone"
        app.typeText(edit)
        XCTAssertTrue(app.staticTexts["Saved on this device · Waiting to sync"].waitForExistence(timeout: 10))

        // Relaunch with the same identity and still no manifest, history or acknowledged edits.
        app.terminate()
        openLibrary()
        let editedPreview = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", edit)).firstMatch
        XCTAssertTrue(editedPreview.waitForExistence(timeout: 10), "The editor must save to this account's disk store")
        XCTAssertTrue(preview("Recent field note 21").exists)
        XCTAssertFalse(preview("Archived field note 2").exists)

        // Older notes are pinned so both can be inspected without scrolling through 20 newer notes.
        server.releaseManifest()
        XCTAssertTrue(preview("Archived field note 2").waitForExistence(timeout: 10))
        XCTAssertTrue(preview("Archived field note 1").exists)
        XCTAssertTrue(editedPreview.exists)
        XCTAssertEqual(server.recentReadCount, 1, "Restarting a partially restored account must reuse its recent bodies")
        XCTAssertEqual(server.backfillIDs.sorted(), ["ast_1", "ast_2"])
        XCTAssertEqual(server.singleReads, [], "History should come from the batch endpoint")
    }
}

/// The app uses its regular verified session, disk store and HTTP stack. Only this test owns the loopback listener.
// Network callbacks and mutable fixture state belong to `queue`. Public state
// reads/writes use queue.sync; immutable configuration and SDK handles are shared.
final class RecentNotesServer: @unchecked Sendable {
    enum RemoteChange { case changed, removed }
    enum LibraryFixture { case activeNote, trashedNote, twoCreates }

    let actorID: String
    let token: String
    let manifestRequested = XCTestExpectation(description: "The app requested the complete manifest")
    let remoteImageRequested = XCTestExpectation(description: "The app requested the uncached image")
    private let queue = DispatchQueue(label: "RecentNotesServer")
    private let listener: NWListener
    private let includesRemoteImage: Bool
    private let libraryFixture: LibraryFixture?
    let targetRequested = XCTestExpectation(description: "Upstream is holding the target create")
    private var pendingCreate: NWConnection?
    func releaseTargetCreation() {
        queue.sync {
            if let connection = pendingCreate { sendCreateReceipt(connection, key: "target-create") }
            pendingCreate = nil
        }
    }
    private func sendCreateReceipt(_ connection: NWConnection, key: String) {
        let asset = "asset-" + key
        send(connection, payload: ["id": asset, "sync_receipt": ["asset_id": asset, "operation_id": key]] as [String: Any])
    }
    let privacyCommitLost = XCTestExpectation(description: "First committed visibility response lost")
    private var policyAttempts: [(key: String, bytes: Data)] = []
    var replayedPrivacyExactly: Bool {
        queue.sync { policyAttempts.count == 2 && policyAttempts[0].key == policyAttempts[1].key && policyAttempts[0].bytes == policyAttempts[1].bytes }
    }
    private var profileKeys: [String] = []
    var confirmedFreshProfileDecision: Bool { queue.sync { profileKeys.count == 2 && Set(profileKeys).count == 2 } }
    private var deleteRequests = 0
    var permanentDeleteRequests: Int { queue.sync { deleteRequests } }
    private var recentNoteChange: RemoteChange?
    private var sawRemoteImage = false
    private var imageBytes: Data?
    private var contentReads = 0
    var imageContentReads: Int { queue.sync { contentReads } }
    func serveImage(_ data: Data?) { queue.sync { imageBytes = data } }
    private var verificationRestricted = false
    func restrictVerification() { queue.sync { verificationRestricted = true } }
    private var manifestIsReleased = false
    private var sawManifest = false
    private var waiting: [NWConnection] = []
    private var recentReads = 0
    private var batchIDs: [String] = []
    private var detailIDs: [String] = []
    private lazy var cards = libraryFixture == nil ? (1...22).map(makeCard) : [makeCard(22)]

    var recentReadCount: Int { queue.sync { recentReads } }
    var backfillIDs: [String] { queue.sync { batchIDs } }
    var singleReads: [String] { queue.sync { detailIDs } }

    init(includesRemoteImage: Bool = false, libraryFixture: LibraryFixture? = nil,
         actorID: String = "act_" + UUID().uuidString, token: String = UUID().uuidString) throws {
        self.actorID = actorID
        self.token = token
        self.includesRemoteImage = includesRemoteImage
        self.libraryFixture = libraryFixture
        manifestIsReleased = libraryFixture != nil
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() throws -> String {
        let ready = XCTestExpectation(description: "Bound loopback port")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: queue)
            receive(connection, OSAllocatedUnfairLock(
                uncheckedState: CFHTTPMessageCreateEmpty(nil, true).takeRetainedValue()
            ))
        }
        listener.start(queue: queue)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        let port = try XCTUnwrap(listener.port)
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port.rawValue)
        return try XCTUnwrap(components.string)
    }

    func releaseManifest(changingRecentNote change: RemoteChange? = nil) {
        queue.sync {
            recentNoteChange = change
            if change == .changed {
                let index = cards.count - 1
                cards[index]["sync_token"] = "token-concurrent"
                cards[index]["content"] = "Changed on the server"
                cards[index]["content_json"] = #"[{"id":"blk_remote","type":"paragraph","props":{},"content":[{"type":"text","text":"Changed on the server","styles":{}}],"children":[]}]"#
            } else if change == .removed {
                cards.removeAll { $0["id"] as? String == "ast_22" }
            }
            manifestIsReleased = true
            for connection in waiting { sendManifest(connection) }
            waiting.removeAll()
        }
    }

    func stop() {
        queue.sync {
            waiting.forEach { $0.cancel() }
            listener.cancel()
        }
    }

    private func receive(_ connection: NWConnection, _ request: OSAllocatedUnfairLock<CFHTTPMessage>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
            dispatchPrecondition(condition: .onQueue(self.queue))
            // CFNetwork's mutable parser never leaves this lock. The next receive
            // retains the same parser, preserving fragmented header/body handling.
            request.withLock { message in
                guard error == nil, let data, !data.isEmpty,
                      data.withUnsafeBytes({ CFHTTPMessageAppendBytes(message, $0.bindMemory(to: UInt8.self).baseAddress!, data.count) })
                else { connection.cancel(); return }
                let body = CFHTTPMessageCopyBody(message)?.takeRetainedValue() as Data? ?? Data()
                let length = Self.header("Content-Length", in: message).flatMap(Int.init) ?? 0
                if CFHTTPMessageIsHeaderComplete(message), body.count >= length {
                    self.respond(connection, request: message, body: body)
                } else if !complete {
                    self.receive(connection, request)
                } else {
                    connection.cancel()
                }
            }
        }
    }

    private static func header(_ name: String, in request: CFHTTPMessage) -> String? {
        CFHTTPMessageCopyHeaderFieldValue(request, name as CFString)?.takeRetainedValue() as String?
    }

    private func respond(_ connection: NWConnection, request: CFHTTPMessage, body: Data) {
        guard let url = CFHTTPMessageCopyRequestURL(request)?.takeRetainedValue() as URL?,
              let method = CFHTTPMessageCopyRequestMethod(request)?.takeRetainedValue() as String?,
              Self.header("Authorization", in: request) == "Bearer " + token else {
            send(connection, status: 401)
            return
        }
        let path = url.path
        switch (method, path) {
        case ("GET", "/api/v1/assets/my-profile-actions-fixture/visibility"):
            let head = profileKeys.isEmpty ? "A" : "E"
            send(connection, payload: ["current_policy": ["asset_id": "my-profile-actions-fixture", "space_id": NSNull(),
                "visibility": "WORKSPACE", "policy_token": "vp1." + String(repeating: head, count: 43)] as [String: Any]])
        case ("POST", "/api/v1/assets/my-profile-actions-fixture/visibility"):
            let head = profileKeys.isEmpty ? "A" : "E"
            let base = "vp1." + String(repeating: head, count: 43)
            let desired = profileKeys.isEmpty ? "PUBLIC" : "PRIVATE"
            guard let key = Self.header("Idempotency-Key", in: request), !key.isEmpty,
                  let payload = try? JSONSerialization.jsonObject(with: body) as? [String: String],
                  payload == ["visibility": desired, "base_policy_token": base] else { send(connection, status: 400); return }
            profileKeys.append(key)
            if profileKeys.count == 1 { send(connection, status: 409, reason: "stale_policy"); return }
            let asset = "my-profile-actions-fixture", result = "vp1." + String(repeating: "I", count: 43)
            let current: [String: Any] = ["asset_id": asset, "space_id": NSNull(), "visibility": desired, "policy_token": result]
            let receipt: [String: Any] = ["client_request_id": key, "actor_id": actorID, "asset_id": asset, "action": "SET_VISIBILITY",
                "requested_visibility": desired, "requested_space_id": NSNull(), "base_policy_token": base, "result_policy_token": result,
                "activity_id": "activity", "action_log_id": "log"]
            send(connection, payload: ["current_policy": current, "visibility_receipt": receipt])
        case ("GET", "/api/v1/assets/ast_22/visibility"):
            send(connection, payload: ["current_policy": fixturePolicy()])
        case ("POST", "/api/v1/assets/ast_22/visibility"):
            let base = "vp1." + String(repeating: "A", count: 43)
            guard let key = Self.header("Idempotency-Key", in: request), !key.isEmpty,
                  let json = try? JSONSerialization.jsonObject(with: body) as? [String: String],
                  json == ["visibility": "PUBLIC", "base_policy_token": base]
            else { send(connection, status: 428); return }
            policyAttempts.append((key, body))
            if policyAttempts.count == 1 {
                privacyCommitLost.fulfill()
                connection.cancel()
            } else {
                let receipt: [String: Any] = ["client_request_id": key, "asset_id": "ast_22", "actor_id": actorID,
                    "action": "SET_VISIBILITY", "requested_visibility": "PUBLIC", "requested_space_id": NSNull(),
                    "base_policy_token": base, "result_policy_token": "vp1." + String(repeating: "E", count: 43),
                    "activity_id": "activity", "action_log_id": "log"]
                send(connection, payload: ["visibility_receipt": receipt, "current_policy": fixturePolicy()])
            }
        case ("POST", "/api/cards") where libraryFixture == .twoCreates:
            guard let key = Self.header("Idempotency-Key", in: request) else { send(connection, status: 400); return }
            if key == "target-create" {
                pendingCreate = connection
                targetRequested.fulfill()
            } else { sendCreateReceipt(connection, key: key) }

        case ("GET", "/api/auth/verify-token") where verificationRestricted:
            send(connection, status: 403, reason: "account_restricted")
        case ("GET", "/api/auth/verify-token"):
            send(connection, payload: [
                "valid": true, "issued_at": "2026-01-01T00:00:00Z", "expires_at": "2030-01-01T00:00:00Z",
                "user": ["id": actorID, "username": "Reader", "email": "reader@example.invalid", "credit": 0,
                         "created_at": "2026-01-01T00:00:00Z"] as [String: Any],
                "product_access": ["mode": "private_beta", "status": "allowed", "scope": "product_full"]
            ] as [String: Any])
        case ("GET", "/api/v1/onboarding/status"):
            send(connection, payload: ["completed": true, "needs_onboarding": false])
        case ("GET", "/api/cards/sync-page"):
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard !query.isEmpty else {
                recentReads += 1
                send(connection, payload: Array(cards.filter { $0["lifecycle"] as? String == "active" }.suffix(20).reversed()))
                return
            }
            guard query.count == 1, query[0].name == "ids", let ids = query[0].value?.components(separatedBy: ","),
                  ids.count <= 20, Set(ids).count == ids.count, manifestIsReleased else { send(connection, status: 400); return }
            batchIDs.append(contentsOf: ids)
            send(connection, payload: cards.filter { ids.contains($0["id"] as? String ?? "") })
        case ("GET", "/api/cards/sync-manifest"):
            if !sawManifest { sawManifest = true; manifestRequested.fulfill() }
            if manifestIsReleased { sendManifest(connection) } else { waiting.append(connection) }
        case ("DELETE", "/api/cards/ast_22") where libraryFixture == .activeNote:
            send(connection, status: 503, reason: "fixture_sync_unavailable")
        case ("DELETE", "/api/cards/trash/ast_22/permanent") where libraryFixture == .trashedNote:
            deleteRequests += 1
            send(connection, status: 503, reason: "fixture_delete_rejected")
        case ("GET", "/api/v1/media/media_trail"):
            if !sawRemoteImage { sawRemoteImage = true; remoteImageRequested.fulfill() }
            guard let imageBytes, URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(
                URLQueryItem(name: "asset_id", value: "ast_22")) == true else { send(connection, status: 404); return }
            send(connection, payload: ["asset_id": "ast_22", "media_ref": "media_trail",
                 "public_url": "/api/media/media_trail/content?asset_id=ast_22", "mime": "image/png",
                 "sha256": SHA256.hash(data: imageBytes).map { String(format: "%02x", $0) }.joined(),
                 "size_bytes": imageBytes.count] as [String: Any])
        case ("GET", "/api/media/media_trail/content"):
            contentReads += 1
            guard let imageBytes else { send(connection, status: 503); return }
            let header = "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: \(imageBytes.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + imageBytes, completion: .contentProcessed { _ in connection.cancel() })
        case ("GET", _) where path.hasSuffix("/links"):
            send(connection, payload: ["outgoing_links": [], "incoming_links": [], "linked_cards": []] as [String: [String]])
        case ("GET", _) where path.hasPrefix("/api/cards/ast_"):
            detailIDs.append(url.lastPathComponent)
            if recentNoteChange == .changed, path == "/api/cards/ast_22", let recent = cards.last {
                send(connection, payload: recent)
            } else {
                send(connection, status: 404)
            }
        case ("PUT", "/api/cards/ast_22"):
            if recentNoteChange == .changed {
                send(connection, status: 409, reason: "stale_version")
                return
            }
            let index = cards.count - 1
            guard manifestIsReleased, let operation = Self.header("Idempotency-Key", in: request), !operation.isEmpty,
                  let update = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let base = update["base_sync_token"] as? String, base == cards[index]["sync_token"] as? String,
                  let content = update["content"] as? String, let document = update["content_json"] as? String
            else { send(connection, status: 409); return }
            cards[index]["content"] = content
            cards[index]["content_json"] = document
            cards[index]["sync_token"] = "token-edited"
            send(connection, payload: ["sync_receipt": ["operation_id": operation, "asset_id": "ast_22", "sync_token": "token-edited",
                                                         "note_document_version_id": "version-edited", "lifecycle": "active"]])
        default:
            send(connection, status: 404)
        }
    }

    private func fixturePolicy() -> [String: Any] {
        // A second writer restricted the note after the first command committed.
        let digit = policyAttempts.isEmpty ? "A" : "I"
        return ["asset_id": "ast_22", "space_id": NSNull(), "visibility": "PRIVATE",
                "policy_token": "vp1." + String(repeating: digit, count: 43)]
    }

    private func sendManifest(_ connection: NWConnection) {
        let entries = cards.map { ["asset_id": $0["id"]!, "sync_token": $0["sync_token"]!, "lifecycle": $0["lifecycle"]!] }
        send(connection, payload: ["protocol_version": 3, "complete": true, "notes": entries] as [String: Any])
    }

    private func makeCard(_ number: Int) -> [String: Any] {
        let id = "ast_\(number)"
        let text = number <= 2 ? "Archived field note \(number)" : "Recent field note \(number)"
        let date = String(format: "2026-10-%02dT12:00:00Z", number)
        let paragraph = #"{"id":"block-\#(number)","type":"paragraph","props":{"backgroundColor":"default","textColor":"default","textAlignment":"left"},"content":[{"type":"text","text":"\#(text)","styles":{}}],"children":[]}"#
        let imageURL = imageBytes == nil ? "" : #","url":"/api/media/media_trail/content?asset_id=ast_22""#
        let image = #"{"id":"blk_image","type":"image","props":{"mediaRef":"media_trail","name":"Trail picture"\#(imageURL)},"children":[]}"#
        let document = includesRemoteImage && number == 22 ? "[\(paragraph),\(image)]" : "[\(paragraph)]"
        return ["id": id, "owner_actor_id": actorID,
                "lifecycle": libraryFixture == .trashedNote ? "trashed" : "active", "sync_token": "token-\(number)",
                "note_document_version_id": "ver_\(number)", "title": "", "content": text, "content_json": document,
                "tags": [], "is_public": false, "editor_atmosphere": "none", "created_at": date, "updated_at": date,
                "is_pinned": number <= 2, "is_owner": true, "is_favorited": false, "is_liked": false, "is_following_author": false,
                "content_hash": "hash-\(number)", "favorite_count": 0, "view_count": 0, "like_count": 0,
                "comment_count": 0, "rate": 0, "credit_score": 0, "pinned_at": NSNull(),
                "author": ["actor_id": actorID, "username": "Reader"]]
    }

    private func send(_ connection: NWConnection, status: Int = 200, payload: Any = NSNull(), reason: String? = nil) {
        var response: [String: Any] = ["success": status == 200, "data": payload]
        if let reason { response["error"] = ["reason": reason, "code": reason, "message": reason] }
        let json = try! JSONSerialization.data(withJSONObject: response)
        let header = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + json, completion: .contentProcessed { _ in connection.cancel() })
    }
}

// Loopback transport for the ordinary Go scenarios. The serial queue owns all
// connections, barriers and observations. Authentication and responses come from Go.
final class OrdinaryGoProxy: @unchecked Sendable {
    struct Mutation: Equatable {
        let key: String?
        let method: String
        let digest: Data
        let path: String
        var transportFailed = false
        var status: Int?
        var receipt: String?
        var audience: String?
        var policyToken: String?
        var basePolicy: String?
        var initialIsPublic: Bool?
    }

    static func sameFrozenRequest(_ attempts: [Mutation]) -> Bool {
        guard let first = attempts.first, let key = first.key, !key.isEmpty else { return false }
        return attempts.allSatisfy {
            $0.method == first.method && $0.path == first.path && $0.key == key && $0.digest == first.digest
        }
    }

    private let queue = DispatchQueue(label: "OrdinaryGoProxy")
    private let listener: NWListener
    private let session: URLSession
    private let upstream: URL
    private var connections = [ObjectIdentifier: NWConnection]()
    private var offline = false
    private var holdPath: String?
    private var dropPath: String?
    private var held: (() -> Void)?
    private var records = [Mutation]()
    private struct CreateCapture {
        let journal: OrdinaryFixtureJournal
        let token: String
        var recordReceiptImmediately = false
        var keysByAsset: [String: Set<String>] = [:]
    }
    private var creating: CreateCapture?
    private(set) var origin = ""

    func captureCreation(_ journal: OrdinaryFixtureJournal, token: String, recordReceiptImmediately: Bool = false) {
        queue.sync { creating = CreateCapture(journal: journal, token: token, recordReceiptImmediately: recordReceiptImmediately) }
    }

    func bindAcknowledgement(_ journal: OrdinaryFixtureJournal, actor: String, appOrigin: String,
                             local: String, asset: String) throws {
        try queue.sync {
            guard appOrigin == origin, let capture = creating, capture.journal.file == journal.file,
                  let keys = capture.keysByAsset[asset], keys.count == 1, let key = keys.first else {
                throw URLError(.badServerResponse)
            }
            try journal.confirmLocal(actor: actor, appOrigin: appOrigin, local: local, asset: asset, key: key)
            creating = nil
        }
    }
    private var login: Data?
    private var uploads = [Data]()
    private var admitted = Set<String>()

    var mutations: [Mutation] { queue.sync { records } }
    var hasHeldResponse: Bool { queue.sync { held != nil } }
    var lastLogin: Data? { queue.sync { login } }
    var uploadedImages: [Data] { queue.sync { uploads } }
    func verifiedFullAccess(_ actor: String) -> Bool { queue.sync { admitted.contains(actor) } }
    func setOffline(_ value: Bool) { queue.sync { offline = value } }
    func dropFirstUpdateReceipt(asset: String) { queue.sync { dropPath = "/api/cards/" + asset } }
    func holdSuccessfulUpdate(asset: String) { queue.sync { holdPath = "/api/cards/" + asset } }
    func release() { queue.sync { held?(); held = nil } }

    init(upstreamOrigin: String = UITestAPIConfiguration.baseURL) throws {
        upstream = try XCTUnwrap(URL(string: upstreamOrigin))
        guard upstream.scheme == "http", upstream.host == "127.0.0.1" else {
            throw URLError(.unsupportedURL)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() throws -> String {
        let ready = XCTestExpectation(description: "Go forwarder bound a loopback port")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections[ObjectIdentifier(connection)] = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                if case .cancelled = state, let connection { self?.connections.removeValue(forKey: ObjectIdentifier(connection)) }
            }
            connection.start(queue: self.queue)
            self.receive(connection, OSAllocatedUnfairLock(uncheckedState: CFHTTPMessageCreateEmpty(nil, true).takeRetainedValue()))
        }
        listener.start(queue: queue)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        var origin = URLComponents(url: upstream, resolvingAgainstBaseURL: false)
        origin?.port = Int(try XCTUnwrap(listener.port).rawValue)
        self.origin = try XCTUnwrap(origin?.string)
        return self.origin
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.values.forEach { $0.cancel() }
            session.invalidateAndCancel()
            held = nil
        }
    }

    private func receive(_ connection: NWConnection, _ parser: OSAllocatedUnfairLock<CFHTTPMessage>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { bytes, _, end, error in
            parser.withLock { message in
                guard error == nil, let bytes, !bytes.isEmpty,
                      bytes.withUnsafeBytes({ CFHTTPMessageAppendBytes(message, $0.bindMemory(to: UInt8.self).baseAddress!, bytes.count) }) else { connection.cancel(); return }
                let headers = CFHTTPMessageCopyAllHeaderFields(message)?.takeRetainedValue() as? [String: String] ?? [:]
                let size = CFHTTPMessageCopyHeaderFieldValue(message, "Content-Length" as CFString)?.takeRetainedValue() as String?
                let body = CFHTTPMessageCopyBody(message)?.takeRetainedValue() as Data? ?? Data()
                if CFHTTPMessageIsHeaderComplete(message), body.count >= (Int(size ?? "") ?? 0) {
                    guard let url = CFHTTPMessageCopyRequestURL(message)?.takeRetainedValue() as URL?,
                          let method = CFHTTPMessageCopyRequestMethod(message)?.takeRetainedValue() as String? else { connection.cancel(); return }
                    self.forward(method, url, headers, body, connection)
                } else if end { connection.cancel() } else { self.receive(connection, parser) }
            }
        }
    }

    private func forward(_ method: String, _ incoming: URL, _ headers: [String: String], _ body: Data, _ connection: NWConnection) {
        guard var target = URLComponents(url: upstream, resolvingAgainstBaseURL: false),
              let source = URLComponents(url: incoming, resolvingAgainstBaseURL: false) else { connection.cancel(); return }
        target.percentEncodedPath = source.percentEncodedPath
        target.percentEncodedQuery = source.percentEncodedQuery
        guard let url = target.url else { connection.cancel(); return }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !body.isEmpty { request.httpBody = body }
        for name in ["Content-Type", "Authorization", "Idempotency-Key", "Accept"] {
            if let field = headers.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame }) {
                request.setValue(field.value, forHTTPHeaderField: name)
            }
        }
        let key = request.value(forHTTPHeaderField: "Idempotency-Key")
        let path = url.path
        let card = (path == "/api/cards" || path.hasPrefix("/api/cards/")) && ["POST", "PUT", "PATCH", "DELETE"].contains(method)
        let policy = path.hasPrefix("/api/v1/assets/") && path.hasSuffix("/visibility")
        let tracked = card || policy || (method == "POST" && path == "/api/v1/media/upload")
        let index = tracked ? records.count : nil
        if tracked {
            var record = Mutation(key: key, method: method, digest: Data(SHA256.hash(data: body)), path: path)
            if method == "POST", path == "/api/cards", let create = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                record.initialIsPublic = create["is_public"] as? Bool
            }
            records.append(record)
        }
        let captureFile = method == "POST" && path == "/api/cards" && creating.map({
            request.value(forHTTPHeaderField: "Authorization") == "Bearer " + $0.token
        }) == true ? creating?.journal.file : nil
        if offline {
            if let index { records[index].transportFailed = true }
            connection.cancel()
            return
        }
        session.dataTask(with: request) { data, response, error in
            self.queue.async {
                if let index {
                    self.records[index].status = (response as? HTTPURLResponse)?.statusCode
                    self.records[index].transportFailed = error != nil
                }
                guard let http = response as? HTTPURLResponse, let data, error == nil else { connection.cancel(); return }
                let payload = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [String: Any]
                if http.statusCode == 200 {
                    if path == "/api/auth/login" { self.login = data }
                    if let access = payload?["product_access"] as? [String: Any], access["status"] as? String == "allowed",
                       access["scope"] as? String == "product_full", let user = payload?["user"] as? [String: Any],
                       let actor = user["id"] as? String { self.admitted.insert(actor) }
                }
                if path == "/api/v1/media/upload", (200..<300).contains(http.statusCode),
                   let start = body.range(of: Data("\r\n\r\n".utf8)),
                   let end = body.range(of: Data("\r\n--".utf8), in: start.upperBound..<body.endIndex) {
                    self.uploads.append(Data(body[start.upperBound..<end.lowerBound]))
                }
                let send = {
                    var header = "HTTP/1.1 \(http.statusCode) Response\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Length: \(data.count)\r\n"
                    if let type = http.value(forHTTPHeaderField: "Content-Type") { header += "Content-Type: \(type)\r\n" }
                    connection.send(content: Data((header + "\r\n").utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
                }
                let receipt = payload?["sync_receipt"] as? [String: Any]
                if let index {
                    self.records[index].receipt = receipt?["operation_id"] as? String
                    if policy {
                        let current = payload?["current_policy"] as? [String: Any]
                        let write = payload?["visibility_receipt"] as? [String: Any]
                        self.records[index].receipt = write?["client_request_id"] as? String
                        self.records[index].audience = current?["visibility"] as? String
                        self.records[index].policyToken = current?["policy_token"] as? String
                        self.records[index].basePolicy = write?["base_policy_token"] as? String
                    }
                }
                if let captureFile, self.creating?.journal.file == captureFile, let key, !key.isEmpty,
                   (200..<300).contains(http.statusCode), receipt?["operation_id"] as? String == key,
                   let asset = receipt?["asset_id"] as? String, payload?["id"] as? String == asset {
                    if let capture = self.creating, capture.recordReceiptImmediately {
                        do {
                            try capture.journal.recordCreateReceipt(asset: asset, operation: key)
                        } catch { connection.cancel(); return }
                    }
                    self.creating?.keysByAsset[asset, default: []].insert(key)
                }
                if card, let key {
                    if path == self.dropPath, method == "PUT", receipt?["operation_id"] as? String == key {
                        self.dropPath = nil
                        connection.cancel()
                        return
                    }
                    if path == self.holdPath, method == "PUT", receipt?["operation_id"] as? String == key {
                        self.holdPath = nil
                        self.held = send
                        return
                    }
                }
                send()
            }
        }.resume()
    }
}

// Each note gets a private file before creation. Only identities from this run
// may be bound. An unresolved step is replayed from its persisted bytes.
struct OrdinaryFixtureJournal: Sendable {
    struct Command: Codable, Equatable {
        let method: String
        let path: String
        let contentType: String
        let key: String
        let baseline: String
        let body: Data
        var acknowledged = false
    }
    enum Creation: Codable {
        case direct(asset: String)
        case acknowledged(asset: String, operation: String)

        var asset: String {
            switch self {
            case let .direct(asset), let .acknowledged(asset, _): return asset
            }
        }
    }
    struct Entry: Codable {
        let actor: String
        let origin: String
        var local: String?
        var appOrigin: String?
        var creation: Creation?
        var asset: String? { creation?.asset }
        var commands: [Command] = []
    }
    let file: URL
    private let lock = OSAllocatedUnfairLock()

    init(directory: URL, actor: String, origin: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        file = directory.appendingPathComponent(UUID().uuidString + ".json")
        try save(Entry(actor: actor, origin: origin))
    }
    init(reopening file: URL) { self.file = file }
    private func save(_ value: Entry) throws {
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let handle = try FileHandle(forWritingTo: file)
        try handle.synchronize()
        try handle.close()
    }
    private func read() throws -> Entry {
        try JSONDecoder().decode(Entry.self, from: Data(contentsOf: file))
    }
    func snapshot() throws -> Entry { try lock.withLock { try read() } }
    func expectLocal(_ local: String, appOrigin: String) throws {
        try lock.withLock {
            var entry = try read()
            guard entry.creation == nil, entry.local == nil, local.hasPrefix("local-note:") else {
                throw URLError(.badServerResponse)
            }
            entry.local = local
            entry.appOrigin = appOrigin
            try save(entry)
        }
    }

    fileprivate func confirmLocal(actor: String, appOrigin: String, local: String, asset: String, key: String) throws {
        try lock.withLock {
            var entry = try read()
            guard entry.creation == nil, entry.actor == actor, entry.appOrigin == appOrigin,
                  entry.local == local, !asset.isEmpty, !key.isEmpty else { throw URLError(.badServerResponse) }
            entry.creation = .acknowledged(asset: asset, operation: key)
            try save(entry)
        }
    }

    func recordCreateReceipt(asset: String, operation: String) throws {
        try lock.withLock {
            var entry = try read()
            guard !asset.isEmpty, !operation.isEmpty else { throw URLError(.badServerResponse) }
            if let creation = entry.creation {
                guard case .acknowledged(let confirmed, let original) = creation, confirmed == asset, original == operation
                else { throw URLError(.badServerResponse) }
                return
            }
            entry.creation = .acknowledged(asset: asset, operation: operation)
            try save(entry)
        }
    }

    func recordDirectCreate(asset: String) throws {
        try lock.withLock {
            var entry = try read()
            guard entry.local == nil, entry.creation == nil, !asset.isEmpty else { throw URLError(.badServerResponse) }
            entry.creation = .direct(asset: asset)
            try save(entry)
        }
    }

    func clean(actor: String, origin: String, token: String, baseline: (String) throws -> String,
               send: (URLRequest) throws -> Data) throws {
        var entry = try snapshot()
        guard entry.actor == actor, entry.origin == origin, let asset = entry.asset else { throw URLError(.userAuthenticationRequired) }
        for (index, path) in ["/api/cards/" + asset, "/api/cards/trash/" + asset + "/permanent"].enumerated() {
            if entry.commands.count == index {
                let base = try baseline(asset)
                guard !base.isEmpty else { throw URLError(.cannotParseResponse) }
                let body = try JSONEncoder().encode(["base_sync_token": base])
                entry.commands.append(Command(method: "DELETE", path: path, contentType: "application/json", key: UUID().uuidString, baseline: base, body: body))
                try save(entry)
            }
            let command = entry.commands[index]
            guard command.method == "DELETE", command.path == path else { throw URLError(.badURL) }
            if command.acknowledged { continue }
            guard let url = URL(string: origin + command.path) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = command.method
            request.setValue(command.contentType, forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue(command.key, forHTTPHeaderField: "Idempotency-Key")
            request.httpBody = command.body
            let bytes = try send(request)
            let envelope = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            guard envelope?["success"] as? Bool == true, let data = envelope?["data"] as? [String: Any] else {
                throw URLError(.cannotParseResponse)
            }
            if index == 0 {
                guard let receipt = data["sync_receipt"] as? [String: Any],
                      receipt["asset_id"] as? String == asset, receipt["operation_id"] as? String == command.key,
                      receipt["lifecycle"] as? String == "trashed" else { throw URLError(.badServerResponse) }
            } else {
                guard data["asset_id"] as? String == asset, data["request_id"] as? String == command.key,
                      data["state"] as? String == "ERASED", let certificate = data["certificate_id"] as? String,
                      !certificate.isEmpty, let activity = data["activity_id"] as? String, !activity.isEmpty,
                      let log = data["action_log_id"] as? String, !log.isEmpty,
                      ["COMPLETE", "PENDING"].contains(data["cleanup_state"] as? String ?? "") else {
                    throw URLError(.badServerResponse)
                }
            }
            entry.commands[index].acknowledged = true
            try save(entry)
        }
    }
}
