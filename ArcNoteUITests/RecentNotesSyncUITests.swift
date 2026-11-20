import CFNetwork
import CoreImage
import CryptoKit
import Network
import UIKit
import XCTest
import os

@MainActor
final class RecentNotesSyncUITests: XCTestCase {
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
    enum LibraryFixture { case activeNote, trashedNote }

    let actorID = "act_" + UUID().uuidString
    let token = UUID().uuidString
    let manifestRequested = XCTestExpectation(description: "The app requested the complete manifest")
    let remoteImageRequested = XCTestExpectation(description: "The app requested the uncached image")
    private let queue = DispatchQueue(label: "RecentNotesServer")
    private let listener: NWListener
    private let includesRemoteImage: Bool
    private let libraryFixture: LibraryFixture?
    private var deleteRequests = 0
    var permanentDeleteRequests: Int { queue.sync { deleteRequests } }
    private var recentNoteChange: RemoteChange?
    private var sawRemoteImage = false
    private var imageBytes: Data?
    private var contentReads = 0
    var imageContentReads: Int { queue.sync { contentReads } }
    func serveImage(_ data: Data?) { queue.sync { imageBytes = data } }
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

    init(includesRemoteImage: Bool = false, libraryFixture: LibraryFixture? = nil) throws {
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
        if let reason { response["error"] = ["reason": reason] }
        let json = try! JSONSerialization.data(withJSONObject: response)
        let header = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + json, completion: .contentProcessed { _ in connection.cancel() })
    }
}
