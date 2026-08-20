import CoreFlow
import WebKit
import XCTest
@testable import BlockNoteEditor

@MainActor
final class BlockNoteMergeRuntimeTests: XCTestCase {
    func testCompleteStandardCardSnapshotPreservesMediaReferenceAndDisplayURL() async throws {
        let terminal = expectation(description: "complete Card reaches terminal availability")
        var terminalAvailability: BlockNoteEditorAvailability?
        let controller = BlockNoteEditorController()
        let document = BlockNoteInitialDocument.existingCard(
            contentJSON: Self.completeStandardEnvelope,
            fallbackMarkdown: "Regular body"
        )
        XCTAssertEqual(document.profile, .standard)
        let coordinator = BlockNoteEditorCoordinator(
            document: document,
            editable: true,
            controller: controller
        ) { event in
            if case let .availabilityChanged(availability) = event,
               availability != .loading,
               terminalAvailability == nil {
                terminalAvailability = availability
                terminal.fulfill()
            }
        }
        let webView = coordinator.makeWebView()
        defer { coordinator.teardown() }

        await fulfillment(of: [terminal], timeout: 15)
        XCTAssertEqual(terminalAvailability, .ready)
        guard terminalAvailability == .ready else { return }
        let snapshot = try await controller.requestSnapshot(
            timeoutNanoseconds: 5_000_000_000
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(snapshot.contentJSON.utf8))
                as? [String: Any]
        )
        let blocks = try XCTUnwrap(root["blocks"] as? [[String: Any]])
        let image = try XCTUnwrap(blocks.last)
        let props = try XCTUnwrap(image["props"] as? [String: Any])
        XCTAssertEqual(props["mediaRef"] as? String, "med_0123456789abcdef")
        XCTAssertEqual(props["semanticRole"] as? String, "evidence")
        XCTAssertEqual(
            props["url"] as? String,
            "https://cdn.chorai.example/history/image.png"
        )

        let imageStateJSON = try await evaluateJavaScriptString(
            #"""
            (() => {
              const host = document.querySelector('[data-content-type="image"]');
              const image = host ? host.querySelector('img') : null;
              return JSON.stringify({src: image ? image.getAttribute('src') : null});
            })();
            """#,
            in: webView
        )
        let imageState = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(imageStateJSON.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(
            imageState["src"] as? String,
            "https://cdn.chorai.example/history/image.png"
        )
    }

    func testCompleteStandardCardCanInsertImageWithoutDroppingRuntimeProps() async throws {
        let ready = expectation(description: "complete text Card becomes editable")
        let changed = expectation(description: "standard Card inserts an image")
        var isReady = false
        let controller = BlockNoteEditorController()
        let coordinator = BlockNoteEditorCoordinator(
            document: .existingCard(
                contentJSON: Self.completeTextStandardEnvelope,
                fallbackMarkdown: "Regular body"
            ),
            editable: true,
            controller: controller
        ) { event in
            switch event {
            case .availabilityChanged(.ready):
                guard !isReady else { return }
                isReady = true
                ready.fulfill()
            case let .documentChanged(document) where isReady && document.revision > 0:
                changed.fulfill()
            default:
                break
            }
        }
        let webView = coordinator.makeWebView()
        defer {
            coordinator.teardown()
            _ = webView
        }

        await fulfillment(of: [ready], timeout: 15)
        controller.focus()
        controller.insertImage(
            url: "https://uploads.chorai.example/staged/new-image.png",
            alt: "New evidence"
        )
        await fulfillment(of: [changed], timeout: 5)

        let snapshot = try await controller.requestSnapshot(
            timeoutNanoseconds: 5_000_000_000
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(snapshot.contentJSON.utf8))
                as? [String: Any]
        )
        let blocks = try XCTUnwrap(root["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        let image = try XCTUnwrap(blocks.last)
        XCTAssertEqual(image["type"] as? String, "image")
        XCTAssertTrue(try XCTUnwrap(image["id"] as? String).hasPrefix("blk_"))
        let props = try XCTUnwrap(image["props"] as? [String: Any])
        XCTAssertEqual(
            props["url"] as? String,
            "https://uploads.chorai.example/staged/new-image.png"
        )
        XCTAssertEqual(props["name"] as? String, "New evidence")
        XCTAssertEqual(props["showPreview"] as? Bool, true)
    }

    func testCommittedMergeCardOpensEditableAndSnapshotsItsEnvelope() async throws {
        let ready = expectation(description: "committed merge card becomes editable")
        let changed = expectation(description: "committed merge card accepts an edit")
        var isReady = false
        let controller = BlockNoteEditorController()
        let document = BlockNoteInitialDocument.existingCard(
            contentJSON: Self.committedMergeEnvelope,
            fallbackMarkdown: "Merged body"
        )
        XCTAssertEqual(document.profile, .mergeArtifact)
        let coordinator = BlockNoteEditorCoordinator(
            document: document,
            editable: true,
            controller: controller
        ) { event in
            switch event {
            case .availabilityChanged(.ready):
                guard !isReady else { return }
                isReady = true
                ready.fulfill()
            case let .documentChanged(revision) where isReady && revision.revision > 0:
                changed.fulfill()
            default:
                break
            }
        }
        let webView = coordinator.makeWebView()
        defer { coordinator.teardown() }

        await fulfillment(of: [ready], timeout: 15)
        try await evaluateJavaScript(
            #"""
            (() => {
              const editor = document.querySelector('.bn-editor[contenteditable="true"]')
                || document.querySelector('[contenteditable="true"]');
              if (!editor) throw new Error('missing editable body');
              editor.focus();
              const target = editor.querySelector('[data-content-type="paragraph"]') || editor;
              const range = document.createRange();
              range.selectNodeContents(target);
              range.collapse(false);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              editor.dispatchEvent(new KeyboardEvent('keydown', {
                key: 'Enter', code: 'Enter', keyCode: 13, which: 13,
                bubbles: true, cancelable: true
              }));
            })();
            """#,
            in: webView
        )
        await fulfillment(of: [changed], timeout: 5)

        let snapshot = try await controller.requestSnapshot(
            timeoutNanoseconds: 5_000_000_000
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(snapshot.contentJSON.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(root["schema_version"] as? Int, 1)
        XCTAssertEqual(root["editor_kind"] as? String, "blocknote")
        let blocks = try XCTUnwrap(root["blocks"] as? [[String: Any]])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.first?["props"] as? [String: String], [:])
        XCTAssertTrue(
            try XCTUnwrap(blocks.last?["id"] as? String).hasPrefix("blk_")
        )
    }

    func testRuntimeInitializationSnapshotAndCodecPreserveMergeImageMediaReference() async throws {
        let cardDocument = Data(Self.richCardDocument.utf8)
        let editable = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: cardDocument
        )
        let terminal = expectation(description: "merge editor reaches a terminal availability")
        var terminalAvailability: BlockNoteEditorAvailability?
        let controller = BlockNoteEditorController()
        let coordinator = BlockNoteEditorCoordinator(
            document: BlockNoteInitialDocument(
                contentJSON: editable.blockNoteJSON,
                fallbackMarkdown: editable.fallbackMarkdown,
                profile: .mergeArtifact,
                displayURLsByMediaReference: [
                    "med_1111111111111111": Self.displayImageURL,
                ]
            ),
            editable: true,
            controller: controller
        ) { event in
            guard terminalAvailability == nil,
                  case let .availabilityChanged(availability) = event,
                  availability != .loading else {
                return
            }
            terminalAvailability = availability
            terminal.fulfill()
        }
        let webView = coordinator.makeWebView()
        defer {
            coordinator.teardown()
            _ = webView
        }

        await fulfillment(of: [terminal], timeout: 15)
        guard terminalAvailability == .ready else {
            return XCTFail("Merge document did not initialize losslessly: \(String(describing: terminalAvailability))")
        }

        let imageStateJSON = try await evaluateJavaScriptString(
            #"""
            (() => {
              const host = document.querySelector('[data-content-type="image"]');
              const image = host ? host.querySelector('img') : null;
              return JSON.stringify({
                src: image ? image.getAttribute('src') : null,
                showsAddImage: host ? host.innerText.includes('Add image') : true
              });
            })();
            """#,
            in: webView
        )
        let imageState = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(imageStateJSON.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(imageState["src"] as? String, Self.displayImageURL)
        XCTAssertEqual(imageState["showsAddImage"] as? Bool, false)

        let snapshot = try await controller.requestSnapshot(
            timeoutNanoseconds: 5_000_000_000
        )
        let encoded = try MergeArtifactEditorCodec.encode(
            blockNoteJSON: snapshot.contentJSON,
            preserving: editable.preservationManifest
        )

        XCTAssertEqual(encoded, cardDocument)
        XCTAssertTrue(snapshot.contentJSON.contains(#""mediaRef":"med_1111111111111111""#))
        XCTAssertFalse(snapshot.contentJSON.contains(Self.displayImageURL))
    }

    func testReturnCreatesServerCompatibleBlockIDInRuntimeSnapshot() async throws {
        let editable = try MergeArtifactEditorCodec.decode(
            cardDocumentJSON: Data(Self.paragraphCardDocument.utf8)
        )
        let ready = expectation(description: "editor becomes ready")
        let changed = expectation(description: "Return inserts a block")
        var isReady = false
        let controller = BlockNoteEditorController()
        let coordinator = BlockNoteEditorCoordinator(
            document: BlockNoteInitialDocument(
                contentJSON: editable.blockNoteJSON,
                fallbackMarkdown: editable.fallbackMarkdown,
                profile: .mergeArtifact
            ),
            editable: true,
            controller: controller
        ) { event in
            switch event {
            case .availabilityChanged(.ready):
                guard !isReady else { return }
                isReady = true
                ready.fulfill()
            case let .documentChanged(document) where isReady && document.revision > 0:
                changed.fulfill()
            default:
                break
            }
        }
        let webView = coordinator.makeWebView()
        defer { coordinator.teardown() }

        await fulfillment(of: [ready], timeout: 15)
        try await evaluateJavaScript(
            #"""
            (() => {
              const editor = document.querySelector('.bn-editor[contenteditable="true"]')
                || document.querySelector('[contenteditable="true"]');
              if (!editor) throw new Error('missing contenteditable');
              editor.focus();
              const target = editor.querySelector('[data-content-type="paragraph"]') || editor;
              const range = document.createRange();
              range.selectNodeContents(target);
              range.collapse(false);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              editor.dispatchEvent(new KeyboardEvent('keydown', {
                key: 'Enter',
                code: 'Enter',
                keyCode: 13,
                which: 13,
                bubbles: true,
                cancelable: true
              }));
            })();
            """#,
            in: webView
        )
        await fulfillment(of: [changed], timeout: 5)

        let snapshot = try await controller.requestSnapshot(
            timeoutNanoseconds: 5_000_000_000
        )
        let blocks = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(snapshot.contentJSON.utf8))
                as? [[String: Any]]
        )
        XCTAssertEqual(blocks.count, 2)
        let newID = try XCTUnwrap(blocks.last?["id"] as? String)
        XCTAssertTrue(newID.hasPrefix("blk_"), "Unexpected generated block ID: \(newID)")
        XCTAssertLessThanOrEqual(newID.utf8.count, 64)
        XCTAssertNoThrow(
            try MergeArtifactEditorCodec.encode(
                blockNoteJSON: snapshot.contentJSON,
                preserving: editable.preservationManifest
            )
        )
    }

    private func evaluateJavaScript(
        _ script: String,
        in webView: WKWebView
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func evaluateJavaScriptString(
        _ script: String,
        in webView: WKWebView
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result = result as? String {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(
                        throwing: CocoaError(.coderInvalidValue)
                    )
                }
            }
        }
    }

    private static let displayImageURL =
        "https://media.example.test/signed/merge-image.png?token=runtime-only"

    private static let richCardDocument = #"{"blocks":[{"content":[{"styles":{"bold":true},"text":"Rich heading","type":"text"}],"id":"blk_rich_heading","props":{"level":2},"type":"heading"},{"content":[{"text":"Plain ","type":"text"},{"styles":{"italic":true},"text":"italic ","type":"text"},{"content":[{"styles":{"underline":true},"text":"reference","type":"text"}],"href":"https://example.com/reference","type":"link"}],"id":"blk_rich_paragraph","type":"paragraph"},{"children":[{"content":[{"text":"Nested detail","type":"text"}],"id":"blk_rich_child","type":"paragraph"}],"content":[{"text":"Parent item","type":"text"}],"id":"blk_rich_bullet","type":"bullet_list"},{"content":[{"styles":{"strike":true},"text":"Completed","type":"text"}],"id":"blk_rich_check","props":{"checked":true},"type":"checklist"},{"id":"blk_rich_image","props":{"alignment":"center","mediaRef":"med_1111111111111111","origin":"source_image","prominence":"wide","semanticRole":"evidence"},"type":"image"},{"content":[{"text":"Preserve quote","type":"text"}],"id":"blk_rich_quote","type":"quote"},{"content":[{"text":"let exact = true","type":"text"}],"id":"blk_rich_code","type":"code"},{"content":[],"id":"blk_rich_divider","type":"divider"}],"meta":{"producer":"merge.vnext","route":"text_fusion"},"schemaVersion":"card_doc.v1"}"#

    private static let paragraphCardDocument = #"{"blocks":[{"content":[{"text":"Seed","type":"text"}],"id":"blk_seed","type":"paragraph"}],"meta":{"producer":"merge.vnext","route":"text_fusion"},"schemaVersion":"card_doc.v1"}"#

    private static let committedMergeEnvelope = #"{"blocks":[{"children":[],"content":[{"styles":{},"text":"Merged body","type":"text"}],"id":"blk_sec_01","props":{},"type":"paragraph"}],"editor_kind":"blocknote","schema_version":1}"#

    private static let completeStandardEnvelope = #"{"blocks":[{"children":[],"content":[{"styles":{},"text":"Regular body","type":"text"}],"id":"b_regular","props":{"backgroundColor":"default","textAlignment":"left","textColor":"default"},"type":"paragraph"},{"children":[],"content":[],"id":"b_image","props":{"backgroundColor":"default","caption":"Evidence","mediaRef":"med_0123456789abcdef","name":"Merged image","previewWidth":960,"semanticRole":"evidence","showPreview":true,"textAlignment":"right","url":"https://cdn.chorai.example/history/image.png"},"type":"image"}],"content":"Regular body","editor_kind":"blocknote","schema_version":1,"tags":["Design","Merged"],"title":"Regular body"}"#

    private static let completeTextStandardEnvelope = #"{"blocks":[{"children":[],"content":[{"styles":{},"text":"Regular body","type":"text"}],"id":"b_regular","props":{"backgroundColor":"default","textAlignment":"left","textColor":"default"},"type":"paragraph"}],"content":"Regular body","editor_kind":"blocknote","schema_version":1,"tags":[],"title":"Regular body"}"#
}
