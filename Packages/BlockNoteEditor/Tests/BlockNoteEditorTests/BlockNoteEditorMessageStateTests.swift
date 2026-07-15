import XCTest
@testable import BlockNoteEditor

final class BlockNoteEditorMessageStateTests: XCTestCase {
    func testReadyHandshakeRequiresInitializationAndMatchingVersions() {
        var state = BlockNoteEditorState(editable: true)

        let premature = state.receive(.ready(protocolVersion: 2, schemaVersion: 1))
        XCTAssertFalse(premature.becameReady)
        XCTAssertFalse(state.isBridgeReady)
        XCTAssertEqual(state.availability, .failed(code: "unexpected_ready"))

        state.beginInitialization()
        let mismatch = state.receive(.ready(protocolVersion: 3, schemaVersion: 1))
        XCTAssertFalse(mismatch.becameReady)
        XCTAssertFalse(state.isBridgeReady)
        XCTAssertEqual(state.availability, .readOnly(reason: "protocol_mismatch"))

        state.beginInitialization()
        let ready = state.receive(.ready(protocolVersion: 2, schemaVersion: 1))
        XCTAssertTrue(ready.becameReady)
        XCTAssertTrue(state.isBridgeReady)
        XCTAssertEqual(state.availability, .ready)
    }

    func testEditableFalseSurfacesReadOnlyAfterValidReady() {
        var state = BlockNoteEditorState(editable: false)
        state.beginInitialization()

        let update = state.receive(.ready(protocolVersion: 2, schemaVersion: 1))

        XCTAssertTrue(update.becameReady)
        XCTAssertTrue(state.isBridgeReady)
        XCTAssertEqual(state.availability, .readOnly(reason: "editable_false"))
    }

    func testDocumentChangesAcceptStrictlyIncreasingRevisionsOnly() {
        var state = makeReadyState()

        let initial = state.receive(.documentChanged(
            revision: 0,
            contentJSON: #"[{"type":"paragraph"}]"#,
            fallbackMarkdown: "Initial"
        ))
        let latest = state.receive(.documentChanged(
            revision: 2,
            contentJSON: #"[{"type":"paragraph","content":"Latest"}]"#,
            fallbackMarkdown: "Latest"
        ))
        let stale = state.receive(.documentChanged(
            revision: 1,
            contentJSON: #"[{"type":"paragraph","content":"Stale"}]"#,
            fallbackMarkdown: "Stale"
        ))

        XCTAssertEqual(initial.events.count, 1)
        XCTAssertEqual(latest.events.count, 1)
        XCTAssertTrue(stale.events.isEmpty)
        XCTAssertEqual(state.latestDocument?.revision, 2)
        XCTAssertEqual(state.latestDocument?.fallbackMarkdown, "Latest")
    }

    func testSnapshotIsRejectedBeforeReadyAndAfterCompatibilityBlock() {
        let snapshotMessage = BlockNoteEditorMessage.snapshot(
            requestID: "save-1",
            revision: 0,
            contentJSON: "[]",
            fallbackMarkdown: ""
        )
        var loading = BlockNoteEditorState(editable: true)
        XCTAssertNil(loading.receive(snapshotMessage).snapshot)

        var blocked = makeReadyState()
        let blockUpdate = blocked.receive(.compatibilityBlocked(
            code: "unknown_block_type",
            details: "futureBlock"
        ))
        XCTAssertFalse(blocked.isBridgeReady)
        XCTAssertEqual(blocked.availability, .readOnly(reason: "unknown_block_type"))
        XCTAssertEqual(blockUpdate.snapshotFailure, .compatibilityBlocked(code: "unknown_block_type"))
        XCTAssertNil(blocked.receive(snapshotMessage).snapshot)
    }

    func testStaleSnapshotRetainsRequestCorrelationForImmediateFailure() {
        var state = makeReadyState()
        _ = state.receive(.documentChanged(
            revision: 5,
            contentJSON: "[]",
            fallbackMarkdown: "Latest"
        ))

        let update = state.receive(.snapshot(
            requestID: "save-stale",
            revision: 4,
            contentJSON: "[]",
            fallbackMarkdown: "Stale"
        ))

        XCTAssertNil(update.snapshot)
        XCTAssertEqual(
            update.snapshotRequestFailure,
            .init(
                requestID: "save-stale",
                failure: .bridgeFailed(code: "stale_snapshot_revision")
            )
        )
        XCTAssertEqual(update.events, [
            .bridgeError(code: "stale_snapshot_revision"),
        ])
    }

    func testAllKnownEventsDecodeFromTaggedEnvelopes() throws {
        let cases: [(String, BlockNoteEditorMessage)] = [
            (#"{"type":"ready","protocolVersion":2,"schemaVersion":1}"#, .ready(protocolVersion: 2, schemaVersion: 1)),
            (#"{"type":"documentChanged","revision":3,"contentJSON":"[]","fallbackMarkdown":"Body"}"#, .documentChanged(revision: 3, contentJSON: "[]", fallbackMarkdown: "Body")),
            (#"{"type":"selectionChanged","selectionState":{"blockType":"heading2","formats":{"bold":true,"italic":false,"underline":false,"strike":true}}}"#, .selectionChanged(.init(blockType: .heading2, formats: .init(bold: true, italic: false, underline: false, strike: true)))),
            (#"{"type":"bodyFocusChanged","isFocused":true}"#, .bodyFocusChanged(isFocused: true)),
            (#"{"type":"heightChanged","contentHeight":240.5}"#, .heightChanged(contentHeight: 240.5)),
            (#"{"type":"snapshot","requestID":"save-3","revision":3,"contentJSON":"[]","fallbackMarkdown":"Body"}"#, .snapshot(requestID: "save-3", revision: 3, contentJSON: "[]", fallbackMarkdown: "Body")),
            (#"{"type":"compatibilityBlocked","code":"malformed_document","details":"Bad shape"}"#, .compatibilityBlocked(code: "malformed_document", details: "Bad shape")),
            (#"{"type":"bridgeError","code":"read_only"}"#, .bridgeError(code: "read_only")),
        ]

        for (json, expected) in cases {
            XCTAssertEqual(
                try JSONDecoder().decode(BlockNoteEditorMessage.self, from: Data(json.utf8)),
                expected
            )
        }
    }

    func testBodyFocusEventsAreForwardedOnlyAfterTheBridgeIsReady() {
        var loading = BlockNoteEditorState(editable: true)
        XCTAssertEqual(
            loading.receive(.bodyFocusChanged(isFocused: true)).events,
            [.bridgeError(code: "unexpected_body_focus")]
        )

        var ready = makeReadyState()
        XCTAssertEqual(
            ready.receive(.bodyFocusChanged(isFocused: true)).events,
            [.bodyFocusChanged(isFocused: true)]
        )
        XCTAssertEqual(
            ready.receive(.bodyFocusChanged(isFocused: false)).events,
            [.bodyFocusChanged(isFocused: false)]
        )
    }

    func testMalformedAndUnknownMessagesAreRejectedAndFailStateWithoutReadiness() {
        let invalidMessages = [
            #"{"type":"ready","protocolVersion":"1","schemaVersion":1}"#,
            #"{"type":"snapshot","requestID":"save-1","revision":0}"#,
            #"{"type":"futureEvent","payload":{}}"#,
            #"[]"#,
        ]

        for json in invalidMessages {
            XCTAssertThrowsError(
                try JSONDecoder().decode(BlockNoteEditorMessage.self, from: Data(json.utf8))
            )
        }

        var state = BlockNoteEditorState(editable: true)
        let update = state.failMalformedMessage()
        XCTAssertFalse(state.isBridgeReady)
        XCTAssertEqual(state.availability, .failed(code: "malformed_message"))
        XCTAssertEqual(update.snapshotFailure, .bridgeFailed(code: "malformed_message"))
    }

    private func makeReadyState() -> BlockNoteEditorState {
        var state = BlockNoteEditorState(editable: true)
        state.beginInitialization()
        _ = state.receive(.ready(protocolVersion: 2, schemaVersion: 1))
        return state
    }
}
