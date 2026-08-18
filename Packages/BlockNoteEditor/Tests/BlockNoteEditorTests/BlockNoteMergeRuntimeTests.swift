import CoreFlow
import WebKit
import XCTest
@testable import BlockNoteEditor

@MainActor
final class BlockNoteMergeRuntimeTests: XCTestCase {
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
                profile: .mergeArtifact
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

        let snapshot = try await controller.requestSnapshot(
            timeoutNanoseconds: 5_000_000_000
        )
        let encoded = try MergeArtifactEditorCodec.encode(
            blockNoteJSON: snapshot.contentJSON,
            preserving: editable.preservationManifest
        )

        XCTAssertEqual(encoded, cardDocument)
        XCTAssertTrue(snapshot.contentJSON.contains(#""mediaRef":"med_1111111111111111""#))
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

    private static let richCardDocument = #"{"blocks":[{"content":[{"styles":{"bold":true},"text":"Rich heading","type":"text"}],"id":"blk_rich_heading","props":{"level":2},"type":"heading"},{"content":[{"text":"Plain ","type":"text"},{"styles":{"italic":true},"text":"italic ","type":"text"},{"content":[{"styles":{"underline":true},"text":"reference","type":"text"}],"href":"https://example.com/reference","type":"link"}],"id":"blk_rich_paragraph","type":"paragraph"},{"children":[{"content":[{"text":"Nested detail","type":"text"}],"id":"blk_rich_child","type":"paragraph"}],"content":[{"text":"Parent item","type":"text"}],"id":"blk_rich_bullet","type":"bullet_list"},{"content":[{"styles":{"strike":true},"text":"Completed","type":"text"}],"id":"blk_rich_check","props":{"checked":true},"type":"checklist"},{"id":"blk_rich_image","props":{"alignment":"center","mediaRef":"med_1111111111111111","origin":"source_image","prominence":"wide","semanticRole":"evidence"},"type":"image"},{"content":[{"text":"Preserve quote","type":"text"}],"id":"blk_rich_quote","type":"quote"},{"content":[{"text":"let exact = true","type":"text"}],"id":"blk_rich_code","type":"code"},{"content":[],"id":"blk_rich_divider","type":"divider"}],"meta":{"producer":"merge.vnext","route":"text_fusion"},"schemaVersion":"card_doc.v1"}"#

    private static let paragraphCardDocument = #"{"blocks":[{"content":[{"text":"Seed","type":"text"}],"id":"blk_seed","type":"paragraph"}],"meta":{"producer":"merge.vnext","route":"text_fusion"},"schemaVersion":"card_doc.v1"}"#
}
