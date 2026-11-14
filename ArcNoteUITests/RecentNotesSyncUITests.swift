import CFNetwork
import Network
import XCTest

final class RecentNotesSyncUITests: XCTestCase {
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
        app.typeKey("a", modifierFlags: .command)
        app.typeText("Changed on this phone")
        XCTAssertTrue(app.staticTexts["Saved on this device · Waiting to sync"].waitForExistence(timeout: 10))

        // Relaunch with the same identity and still no manifest, history or acknowledged edits.
        app.terminate()
        openLibrary()
        XCTAssertTrue(preview("Changed on this phone").waitForExistence(timeout: 10), "The editor must save to this account's disk store")
        XCTAssertTrue(preview("Recent field note 21").exists)
        XCTAssertFalse(preview("Archived field note 2").exists)

        // Older notes are pinned so both can be inspected without scrolling through 20 newer notes.
        server.releaseManifest()
        XCTAssertTrue(preview("Archived field note 2").waitForExistence(timeout: 10))
        XCTAssertTrue(preview("Archived field note 1").exists)
        XCTAssertTrue(preview("Changed on this phone").exists)
        XCTAssertEqual(server.recentReadCount, 1, "Restarting a partially restored account must reuse its recent bodies")
        XCTAssertEqual(server.backfillIDs.sorted(), ["ast_1", "ast_2"])
        XCTAssertEqual(server.singleReads, [], "History should come from the batch endpoint")
    }
}

/// The app uses its regular verified session, disk store and HTTP stack. Only this test owns the loopback listener.
private final class RecentNotesServer {
    let actorID = "act_" + UUID().uuidString
    let token = UUID().uuidString
    let manifestRequested = XCTestExpectation(description: "The app requested the complete manifest")
    private let queue = DispatchQueue(label: "RecentNotesServer")
    private let listener: NWListener
    private var manifestIsReleased = false
    private var sawManifest = false
    private var waiting: [NWConnection] = []
    private var recentReads = 0
    private var batchIDs: [String] = []
    private var detailIDs: [String] = []
    private lazy var cards = (1...22).map(makeCard)

    var recentReadCount: Int { queue.sync { recentReads } }
    var backfillIDs: [String] { queue.sync { batchIDs } }
    var singleReads: [String] { queue.sync { detailIDs } }

    init() throws {
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
            receive(connection, CFHTTPMessageCreateEmpty(nil, true).takeRetainedValue())
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

    func releaseManifest() {
        queue.sync {
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

    private func receive(_ connection: NWConnection, _ request: CFHTTPMessage) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
            guard error == nil, let data, !data.isEmpty,
                  data.withUnsafeBytes({ CFHTTPMessageAppendBytes(request, $0.bindMemory(to: UInt8.self).baseAddress!, data.count) })
            else { connection.cancel(); return }
            let body = CFHTTPMessageCopyBody(request)?.takeRetainedValue() as Data? ?? Data()
            let length = Self.header("Content-Length", in: request).flatMap(Int.init) ?? 0
            if CFHTTPMessageIsHeaderComplete(request), body.count >= length {
                self.respond(connection, request: request, body: body)
            } else if !complete {
                self.receive(connection, request)
            } else {
                connection.cancel()
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
                send(connection, payload: Array(cards.suffix(20).reversed()))
                return
            }
            guard query.count == 1, query[0].name == "ids", let ids = query[0].value?.components(separatedBy: ","),
                  ids.count <= 20, Set(ids).count == ids.count, manifestIsReleased else { send(connection, status: 400); return }
            batchIDs.append(contentsOf: ids)
            send(connection, payload: cards.filter { ids.contains($0["id"] as? String ?? "") })
        case ("GET", "/api/cards/sync-manifest"):
            if !sawManifest { sawManifest = true; manifestRequested.fulfill() }
            if manifestIsReleased { sendManifest(connection) } else { waiting.append(connection) }
        case ("GET", _) where path.hasSuffix("/links"):
            send(connection, payload: ["outgoing_links": [], "incoming_links": [], "linked_cards": []] as [String: [String]])
        case ("GET", _) where path.hasPrefix("/api/cards/ast_"):
            detailIDs.append(url.lastPathComponent)
            send(connection, status: 404)
        case ("PUT", "/api/cards/ast_22"):
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
        let entries = cards.map { ["asset_id": $0["id"]!, "sync_token": $0["sync_token"]!, "lifecycle": "active"] }
        send(connection, payload: ["protocol_version": 3, "complete": true, "notes": entries] as [String: Any])
    }

    private func makeCard(_ number: Int) -> [String: Any] {
        let id = "ast_\(number)"
        let text = number <= 2 ? "Archived field note \(number)" : "Recent field note \(number)"
        let date = String(format: "2026-10-%02dT12:00:00Z", number)
        let document = #"[{"id":"block-\#(number)","type":"paragraph","props":{"backgroundColor":"default","textColor":"default","textAlignment":"left"},"content":[{"type":"text","text":"\#(text)","styles":{}}],"children":[]}]"#
        return ["id": id, "owner_actor_id": actorID, "lifecycle": "active", "sync_token": "token-\(number)",
                "note_document_version_id": "ver_\(number)", "title": "", "content": text, "content_json": document,
                "tags": [], "is_public": false, "editor_atmosphere": "none", "created_at": date, "updated_at": date,
                "is_pinned": number <= 2, "is_owner": true, "is_favorited": false, "is_liked": false, "is_following_author": false,
                "content_hash": "hash-\(number)", "favorite_count": 0, "view_count": 0, "like_count": 0,
                "comment_count": 0, "rate": 0, "credit_score": 0, "pinned_at": NSNull(),
                "author": ["actor_id": actorID, "username": "Reader"]]
    }

    private func send(_ connection: NWConnection, status: Int = 200, payload: Any = NSNull()) {
        let json = try! JSONSerialization.data(withJSONObject: ["success": status == 200, "data": payload])
        let header = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + json, completion: .contentProcessed { _ in connection.cancel() })
    }
}
