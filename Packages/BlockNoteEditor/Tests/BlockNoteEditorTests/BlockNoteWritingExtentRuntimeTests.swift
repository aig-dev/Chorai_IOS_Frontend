import WebKit
import XCTest
@testable import BlockNoteEditor

@MainActor
final class BlockNoteWritingExtentRuntimeTests: XCTestCase {
    func testWritingFloorFillsEditableDOMAndCanShrinkWithoutEditingTheDocument() async throws {
        let ready = expectation(description: "editor becomes ready")
        let controller = BlockNoteEditorController()
        var didBecomeReady = false
        let coordinator = BlockNoteEditorCoordinator(
            document: .init(contentJSON: nil, fallbackMarkdown: "A short existing note."),
            editable: true,
            controller: controller
        ) { event in
            if case .availabilityChanged(.ready) = event, !didBecomeReady {
                didBecomeReady = true
                ready.fulfill()
            }
        }
        let webView = coordinator.makeWebView(minimumWritingHeight: 520)
        webView.frame = CGRect(x: 0, y: 0, width: 390, height: 520)
        defer { coordinator.teardown() }
        await fulfillment(of: [ready], timeout: 15)
        let initial = try await controller.requestSnapshot()
        // `ready` acknowledges initialize before React's editable-state render
        // and delayed onChange notifications have settled. Establish the layout
        // regression's baseline before issuing any appearance update.
        let before = try await settledSnapshot(using: controller)
        print("Writing extent baseline before CSS updates: initial revision \(initial.revision), settled revision \(before.revision)")

        let filled = try await geometry(in: webView, hitY: 420)
        XCTAssertEqual(try XCTUnwrap(filled["editorHeight"] as? Double), 520, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(filled["rootHeight"] as? Double), 520, accuracy: 1)
        XCTAssertEqual(filled["hitIsEditable"] as? Bool, true,
                       "The lower blank page must hit the actual editable DOM")

        // Keep the WKWebView itself at 520pt. A viewport-based CSS floor would
        // latch that old height; the independent page minimum must shrink.
        coordinator.updateMinimumWritingHeight(280)
        let reduced = try await geometry(in: webView, hitY: 240)
        XCTAssertEqual(try XCTUnwrap(reduced["editorHeight"] as? Double), 280, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(reduced["rootHeight"] as? Double), 280, accuracy: 1)
        XCTAssertEqual(reduced["hitIsEditable"] as? Bool, true)

        coordinator.updateMinimumWritingHeight(0)
        let compact = try await geometry(in: webView, hitY: 30)
        XCTAssertLessThan(try XCTUnwrap(compact["rootHeight"] as? Double), 280)
        let after = try await settledSnapshot(using: controller)
        XCTAssertEqual(after.contentJSON, before.contentJSON)
        XCTAssertEqual(after.fallbackMarkdown, before.fallbackMarkdown)
        XCTAssertEqual(after.revision, before.revision)
    }

    private func settledSnapshot(using controller: BlockNoteEditorController) async throws -> BlockNoteSnapshot {
        var previous = try await controller.requestSnapshot()
        var stableWindows = 0
        // The bundled document bridge debounces onChange by 180ms. Two stable
        // windows cover its deferred initial render without ignoring revisions.
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 200_000_000)
            let current = try await controller.requestSnapshot()
            if current.revision == previous.revision,
               current.contentJSON == previous.contentJSON,
               current.fallbackMarkdown == previous.fallbackMarkdown {
                stableWindows += 1
                if stableWindows == 2 { return current }
            } else {
                stableWindows = 0
            }
            previous = current
        }
        XCTFail("The document did not settle before checking appearance-only changes")
        return previous
    }

    private func geometry(in webView: WKWebView, hitY: Int) async throws -> [String: Any] {
        let value = try await webView.evaluateJavaScript("""
        (() => {
          const root = document.querySelector('.ios-editor-root');
          const editor = root.querySelector('[contenteditable="true"]');
          const hit = document.elementFromPoint(40, \(hitY));
          return {
            editorHeight: editor.getBoundingClientRect().height,
            rootHeight: Math.max(root.scrollHeight, root.getBoundingClientRect().height),
            hitIsEditable: Boolean(hit && hit.isContentEditable)
          };
        })();
        """)
        return try XCTUnwrap(value as? [String: Any])
    }
}
