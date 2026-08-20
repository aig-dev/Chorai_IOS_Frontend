import XCTest
@testable import BlockNoteEditor

final class BlockNoteBridgeSessionTests: XCTestCase {
    func testExistingCardSelectsMergeProfileOnlyForExactAdaptableEnvelope() throws {
        let committed = #"{"blocks":[{"children":[],"content":[{"styles":{},"text":"Merged body","type":"text"}],"id":"blk_sec_01","props":{},"type":"paragraph"}],"editor_kind":"blocknote","schema_version":1}"#
        XCTAssertEqual(
            BlockNoteInitialDocument.existingCard(
                contentJSON: committed,
                fallbackMarkdown: "Merged body"
            ).profile,
            .mergeArtifact
        )

        let standard = #"{"blocks":[{"children":[{"children":[],"content":[{"styles":{"italic":true},"text":"Nested detail","type":"text"}],"id":"blk_nested","props":{"backgroundColor":"default","textAlignment":"left","textColor":"default"},"type":"paragraph"}],"content":[{"styles":{},"text":"Regular body","type":"text"}],"id":"blk_regular","props":{"backgroundColor":"default","textAlignment":"left","textColor":"default"},"type":"paragraph"},{"children":[],"content":[],"id":"blk_image","props":{"backgroundColor":"default","caption":"Evidence","mediaRef":"med_0123456789abcdef","name":"Merged image","previewWidth":960,"semanticRole":"evidence","showPreview":true,"textAlignment":"right","url":"https://cdn.chorai.example/history/image.png"},"type":"image"}],"content":"Regular body\nNested detail","editor_kind":"blocknote","schema_version":1,"tags":["Design","Merged"],"title":"Regular body"}"#
        let standardDocument = BlockNoteInitialDocument.existingCard(
            contentJSON: standard,
            fallbackMarkdown: "Regular body"
        )
        XCTAssertEqual(standardDocument.profile, .standard)
        var standardSession = BlockNoteEditorBridgeSession(
            document: standardDocument,
            editable: true
        )
        guard case let .initialize(_, initializedJSON, _, _, profile) =
            standardSession.navigationFinished().commands.first else {
            return XCTFail("Expected the complete Card initialize command")
        }
        XCTAssertEqual(profile, .standard)
        let initializedRoot = try? Self.object(from: XCTUnwrap(initializedJSON))
        let initializedBlocks = initializedRoot?["blocks"] as? [[String: Any]]
        let initializedImage = initializedBlocks?.last
        let initializedImageProps = initializedImage?["props"] as? [String: Any]
        XCTAssertEqual(initializedBlocks?.count, 2)
        XCTAssertNil(initializedImageProps?["mediaRef"])
        XCTAssertNil(initializedImageProps?["semanticRole"])
        XCTAssertEqual(
            initializedImageProps?["url"] as? String,
            "https://cdn.chorai.example/history/image.png"
        )
        _ = standardSession.receive(.ready(protocolVersion: 3, schemaVersion: 1))
        let standardUpdate = standardSession.receive(.snapshot(
            requestID: "save-complete-card",
            revision: 1,
            contentJSON: try XCTUnwrap(initializedJSON),
            fallbackMarkdown: "Regular body"
        ))
        let standardSnapshot = try? XCTUnwrap(standardUpdate.snapshot)
        let persistedRoot = try? Self.object(
            from: XCTUnwrap(standardSnapshot?.contentJSON)
        )
        let expectedRoot = try? Self.object(from: standard)
        XCTAssertEqual(
            persistedRoot as NSDictionary?,
            expectedRoot as NSDictionary?,
            "The standard runtime projection must round-trip the complete Card semantically"
        )

        var replacementRoot = try XCTUnwrap(initializedRoot)
        var replacementBlocks = try XCTUnwrap(
            replacementRoot["blocks"] as? [[String: Any]]
        )
        var replacementImage = try XCTUnwrap(replacementBlocks.last)
        var replacementProps = try XCTUnwrap(
            replacementImage["props"] as? [String: Any]
        )
        replacementProps["url"] = "https://uploads.chorai.example/staged/replacement.png"
        replacementImage["props"] = replacementProps
        replacementBlocks[replacementBlocks.count - 1] = replacementImage
        replacementRoot["blocks"] = replacementBlocks
        let replacementJSON = String(decoding: try JSONSerialization.data(
            withJSONObject: replacementRoot,
            options: [.sortedKeys]
        ), as: UTF8.self)
        let replacementUpdate = standardSession.receive(.snapshot(
            requestID: "replace-complete-card-image",
            revision: 2,
            contentJSON: replacementJSON,
            fallbackMarkdown: "Regular body"
        ))
        let replacementSnapshot = try XCTUnwrap(replacementUpdate.snapshot)
        let replacementPersistedRoot = try Self.object(
            from: replacementSnapshot.contentJSON
        )
        let replacementPersistedBlocks = try XCTUnwrap(
            replacementPersistedRoot["blocks"] as? [[String: Any]]
        )
        let replacementPersistedImage = try XCTUnwrap(replacementPersistedBlocks.last)
        let replacementPersistedProps = try XCTUnwrap(
            replacementPersistedImage["props"] as? [String: Any]
        )
        XCTAssertNil(
            replacementPersistedProps["mediaRef"],
            "A replacement upload must not retain the prior image authority"
        )
        XCTAssertEqual(
            replacementPersistedProps["url"] as? String,
            "https://uploads.chorai.example/staged/replacement.png"
        )

        let futureEnvelope = #"{"blocks":[{"children":[],"content":[],"id":"blk_future","props":{},"type":"futureBlock"}],"editor_kind":"blocknote","future_contract":"preserve","schema_version":1}"#
        XCTAssertEqual(
            BlockNoteInitialDocument.existingCard(
                contentJSON: futureEnvelope,
                fallbackMarkdown: "Future"
            ).profile,
            .standard,
            "Unknown envelope metadata must remain on the strict fail-closed path"
        )
    }

    func testMergeCommittedEnvelopeGetsRuntimeDefaultsAndRoundTripsLosslessly() throws {
        let committed = #"{"blocks":[{"children":[],"content":[{"styles":{},"text":"Merged body","type":"text"}],"id":"blk_sec_01","props":{},"type":"paragraph"}],"editor_kind":"blocknote","schema_version":1}"#
        var session = BlockNoteEditorBridgeSession(
            document: .init(
                contentJSON: committed,
                fallbackMarkdown: "Merged body",
                profile: .mergeArtifact
            ),
            editable: true
        )

        let initialization = try XCTUnwrap(session.navigationFinished().commands.first)
        guard case let .initialize(_, runtimeJSON, _, _, profile) = initialization else {
            return XCTFail("Expected an initialize command")
        }
        XCTAssertEqual(profile, .mergeArtifact)
        let runtimeRoot = try Self.object(from: try XCTUnwrap(runtimeJSON))
        XCTAssertEqual(runtimeRoot["schema_version"] as? Int, 1)
        XCTAssertEqual(runtimeRoot["editor_kind"] as? String, "blocknote")
        let runtimeBlock = try Self.firstBlock(in: runtimeRoot)
        XCTAssertEqual(runtimeBlock["props"] as? [String: String], [
            "backgroundColor": "default",
            "textAlignment": "left",
            "textColor": "default",
        ])

        _ = session.receive(.ready(protocolVersion: 3, schemaVersion: 1))
        let runtimeSnapshot = #"{"blocks":[{"children":[],"content":[{"styles":{},"text":"Edited body","type":"text"}],"id":"blk_sec_01","props":{"backgroundColor":"default","textAlignment":"left","textColor":"default"},"type":"paragraph"}],"editor_kind":"blocknote","schema_version":1}"#
        let update = session.receive(.snapshot(
            requestID: "save-merge-card",
            revision: 1,
            contentJSON: runtimeSnapshot,
            fallbackMarkdown: "Edited body"
        ))
        let snapshot = try XCTUnwrap(update.snapshot)
        let persistedRoot = try Self.object(from: snapshot.contentJSON)
        XCTAssertEqual(Set(persistedRoot.keys), ["blocks", "editor_kind", "schema_version"])
        XCTAssertEqual(persistedRoot["schema_version"] as? Int, 1)
        XCTAssertEqual(persistedRoot["editor_kind"] as? String, "blocknote")
        let persistedBlock = try Self.firstBlock(in: persistedRoot)
        XCTAssertEqual(persistedBlock["props"] as? [String: String], [:])
        let content = try XCTUnwrap(persistedBlock["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "Edited body")
    }

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
                editable: true,
                profile: .standard
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
                editable: true,
                profile: .standard
            )]
        )
        XCTAssertTrue(session.request(.blur).commands.isEmpty)

        let ready = session.receive(.ready(protocolVersion: 3, schemaVersion: 1))
        XCTAssertEqual(ready.commands, [.blur])
        XCTAssertTrue(session.state.isBridgeReady)
    }

    func testNavigationForwardsMergeArtifactProfileWithoutChangingStandardDefault() {
        var session = BlockNoteEditorBridgeSession(
            document: .init(
                contentJSON: "[]",
                fallbackMarkdown: "",
                profile: .mergeArtifact
            ),
            editable: true
        )

        XCTAssertEqual(
            session.navigationFinished().commands,
            [.initialize(
                protocolVersion: 3,
                documentJSON: "[]",
                fallbackMarkdown: "",
                editable: true,
                profile: .mergeArtifact
            )]
        )
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

    private static func object(from json: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
    }

    private static func firstBlock(in root: [String: Any]) throws -> [String: Any] {
        let blocks = try XCTUnwrap(root["blocks"] as? [[String: Any]])
        return try XCTUnwrap(blocks.first)
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
