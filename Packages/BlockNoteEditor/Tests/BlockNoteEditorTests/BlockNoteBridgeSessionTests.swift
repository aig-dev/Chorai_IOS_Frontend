import XCTest
@testable import BlockNoteEditor

final class BlockNoteBridgeSessionTests: XCTestCase {
    func testNavigationSendsInitializeAndQueuedCommandsWaitForValidReady() {
        var session = BlockNoteEditorBridgeSession(
            document: .init(contentJSON: nil, fallbackMarkdown: "Legacy"),
            editable: true
        )

        XCTAssertTrue(session.request(.focus).commands.isEmpty)
        XCTAssertEqual(
            session.navigationFinished().commands,
            [.initialize(
                protocolVersion: 1,
                documentJSON: nil,
                fallbackMarkdown: "Legacy",
                editable: true
            )]
        )

        let mismatch = session.receive(.ready(protocolVersion: 2, schemaVersion: 1))
        XCTAssertTrue(mismatch.commands.isEmpty)
        XCTAssertFalse(session.state.isBridgeReady)

        XCTAssertEqual(
            session.navigationFinished().commands,
            [.initialize(
                protocolVersion: 1,
                documentJSON: nil,
                fallbackMarkdown: "Legacy",
                editable: true
            )]
        )
        XCTAssertTrue(session.request(.blur).commands.isEmpty)

        let ready = session.receive(.ready(protocolVersion: 1, schemaVersion: 1))
        XCTAssertEqual(ready.commands, [.focus, .blur])
        XCTAssertTrue(session.state.isBridgeReady)
    }

    func testReadOnlyReadyDropsQueuedMutationsButAllowsNonMutatingCommands() {
        var session = BlockNoteEditorBridgeSession(
            document: .init(contentJSON: "[]", fallbackMarkdown: ""),
            editable: false
        )
        _ = session.request(.applyFormat(.bold))
        _ = session.request(.focus)
        _ = session.navigationFinished()

        let ready = session.receive(.ready(protocolVersion: 1, schemaVersion: 1))

        XCTAssertEqual(ready.commands, [.focus])
        XCTAssertTrue(ready.events.contains(.bridgeError(code: "read_only")))
        XCTAssertEqual(session.state.availability, .readOnly(reason: "editable_false"))
    }

    func testCompatibilityFailureClearsQueueAndInvalidatesSnapshots() {
        var session = BlockNoteEditorBridgeSession(
            document: .init(contentJSON: "[]", fallbackMarkdown: ""),
            editable: true
        )
        _ = session.request(.requestSnapshot(requestID: "save-queued"))
        _ = session.navigationFinished()

        let blocked = session.receive(.compatibilityBlocked(
            code: "malformed_document",
            details: "Bad document"
        ))

        XCTAssertTrue(blocked.commands.isEmpty)
        XCTAssertEqual(blocked.snapshotFailure, .compatibilityBlocked(code: "malformed_document"))
        XCTAssertFalse(session.state.isBridgeReady)

        _ = session.navigationFinished()
        let recovered = session.receive(.ready(protocolVersion: 1, schemaVersion: 1))
        XCTAssertTrue(recovered.commands.isEmpty)
    }
}
