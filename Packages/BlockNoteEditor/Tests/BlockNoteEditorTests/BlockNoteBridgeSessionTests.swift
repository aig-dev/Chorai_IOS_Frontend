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
                protocolVersion: 3,
                documentJSON: nil,
                fallbackMarkdown: "Legacy",
                editable: true
            )]
        )

        let mismatch = session.receive(.ready(protocolVersion: 4, schemaVersion: 1))
        XCTAssertTrue(mismatch.commands.isEmpty)
        XCTAssertFalse(session.state.isBridgeReady)

        XCTAssertEqual(
            session.navigationFinished().commands,
            [.initialize(
                protocolVersion: 3,
                documentJSON: nil,
                fallbackMarkdown: "Legacy",
                editable: true
            )]
        )
        XCTAssertTrue(session.request(.blur).commands.isEmpty)

        let ready = session.receive(.ready(protocolVersion: 3, schemaVersion: 1))
        XCTAssertEqual(ready.commands, [.blur])
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

        let ready = session.receive(.ready(protocolVersion: 3, schemaVersion: 1))

        XCTAssertEqual(ready.commands, [.focus])
        XCTAssertTrue(ready.events.contains(.bridgeError(code: "read_only")))
        XCTAssertEqual(session.state.availability, .readOnly(reason: "editable_false"))
    }

    func testCompatibilityFailureClearsQueueAndInvalidatesSnapshots() {
        var session = BlockNoteEditorBridgeSession(
            document: .init(contentJSON: "[]", fallbackMarkdown: ""),
            editable: true
        )
        _ = session.request(.applyFormat(.bold))
        _ = session.request(.focus)
        _ = session.request(.requestSnapshot(requestID: "save-queued"))
        _ = session.navigationFinished()

        let blocked = session.receive(.compatibilityBlocked(
            code: "malformed_document",
            details: "Bad document"
        ))

        XCTAssertTrue(blocked.commands.isEmpty)
        XCTAssertEqual(blocked.snapshotFailure, .compatibilityBlocked(code: "malformed_document"))
        XCTAssertFalse(session.state.isBridgeReady)

        XCTAssertTrue(session.request(.applyFormat(.italic)).commands.isEmpty)
        XCTAssertTrue(session.request(.blur).commands.isEmpty)
        XCTAssertEqual(
            session.request(.requestSnapshot(requestID: "save-blocked")).snapshotFailure,
            .compatibilityBlocked(code: "malformed_document")
        )

        _ = session.navigationFinished()
        let recovered = session.receive(.ready(protocolVersion: 3, schemaVersion: 1))
        XCTAssertTrue(recovered.commands.isEmpty)
    }

    func testBridgeFailureClearsAllQueuedCommandsAndRejectsCommandsWhileFailed() {
        var session = BlockNoteEditorBridgeSession(
            document: .init(contentJSON: "[]", fallbackMarkdown: ""),
            editable: true
        )
        _ = session.request(.focus)
        _ = session.request(.undo)
        _ = session.request(.requestSnapshot(requestID: "save-before-failure"))
        _ = session.navigationFinished()

        let failed = session.bridgeFailure(code: "javascript_evaluation_failed")

        XCTAssertEqual(
            failed.snapshotFailure,
            .bridgeFailed(code: "javascript_evaluation_failed")
        )
        XCTAssertTrue(session.request(.blur).commands.isEmpty)
        XCTAssertTrue(session.request(.redo).commands.isEmpty)
        XCTAssertEqual(
            session.request(.requestSnapshot(requestID: "save-after-failure")).snapshotFailure,
            .bridgeFailed(code: "javascript_evaluation_failed")
        )

        _ = session.navigationFinished()
        let recovered = session.receive(.ready(protocolVersion: 3, schemaVersion: 1))
        XCTAssertTrue(recovered.commands.isEmpty)
    }

    @MainActor
    func testReadySubmitsDrainedCommandsBeforeReentrantReadyCallbackCommands() {
        let harness = ReentrantReadyHarness()

        harness.controller.focus()
        _ = harness.session.navigationFinished()
        harness.dispatch(harness.session.receive(.ready(
            protocolVersion: 3,
            schemaVersion: 1
        )))

        XCTAssertEqual(harness.submittedCommands, [.focus, .blur])
    }
}

@MainActor
private final class ReentrantReadyHarness {
    let controller = BlockNoteEditorController()
    var session = BlockNoteEditorBridgeSession(
        document: .init(contentJSON: "[]", fallbackMarkdown: ""),
        editable: true
    )
    var submittedCommands: [BlockNoteEditorCommand] = []

    init() {
        controller.attach { [weak self] command in
            guard let self else { return }
            dispatch(session.request(command))
        }
    }

    func dispatch(_ output: BlockNoteBridgeSessionOutput) {
        BlockNoteBridgeOutputDispatcher(
            submitCommand: { [weak self] command in
                self?.submittedCommands.append(command)
            },
            emitEvent: { [weak self] event in
                guard let self else { return }
                if event == .availabilityChanged(.ready) {
                    controller.blur()
                }
            }
        ).dispatch(output)
    }
}
