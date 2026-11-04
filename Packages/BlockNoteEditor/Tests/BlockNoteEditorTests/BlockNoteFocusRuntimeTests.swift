import WebKit
import XCTest
@testable import BlockNoteEditor

@MainActor
final class BlockNoteFocusRuntimeTests: XCTestCase {
    func testFocusAndBlurReconcileActualDOMWhenFocusEventsWereMissed() async throws {
        let ready = expectation(description: "editor becomes ready")
        let focused = expectation(description: "already focused body is acknowledged")
        let blurred = expectation(description: "explicit blur is acknowledged")
        let controller = BlockNoteEditorController()
        var observedFocus: [Bool] = []
        let coordinator = BlockNoteEditorCoordinator(
            document: .init(contentJSON: nil, fallbackMarkdown: ""),
            editable: true,
            controller: controller
        ) { event in
            switch event {
            case .availabilityChanged(.ready): ready.fulfill()
            case .bodyFocusChanged(isFocused: true):
                observedFocus.append(true)
                focused.fulfill()
            case .bodyFocusChanged(isFocused: false):
                observedFocus.append(false)
                blurred.fulfill()
            default: break
            }
        }
        let webView = coordinator.makeWebView()
        defer { coordinator.teardown() }
        await fulfillment(of: [ready], timeout: 15)

        // Reproduce a focus acquired before the React bridge could observe it.
        // No event is available, and focusing this same DOM node again is a no-op.
        let isFocused = try await webView.evaluateJavaScript(#"""
        (() => {
          for (const name of ["focus", "blur", "focusin", "focusout"]) {
            window.addEventListener(name, event => event.stopImmediatePropagation(), true);
          }
          const body = document.querySelector('.ios-editor-root [contenteditable="true"]');
          if (!body) return false;
          body.focus();
          return document.activeElement === body;
        })();
        """#) as? Bool
        XCTAssertEqual(isFocused, true)
        XCTAssertTrue(observedFocus.isEmpty)

        controller.focus()
        await fulfillment(of: [focused], timeout: 5)
        XCTAssertEqual(observedFocus, [true])
        controller.blur()
        await fulfillment(of: [blurred], timeout: 5)
        XCTAssertEqual(observedFocus, [true, false])
    }

    func testNaturalBlurIsReportedAfterInitialFocusWasMissed() async throws {
        let ready = expectation(description: "editor becomes ready")
        let focused = expectation(description: "missed initial focus is reconciled")
        let blurred = expectation(description: "natural blur reaches native focus owner")
        let controller = BlockNoteEditorController()
        var observedFocus: [Bool] = []
        let coordinator = BlockNoteEditorCoordinator(
            document: .init(contentJSON: nil, fallbackMarkdown: ""),
            editable: true,
            controller: controller
        ) { event in
            switch event {
            case .availabilityChanged(.ready): ready.fulfill()
            case .bodyFocusChanged(isFocused: true):
                observedFocus.append(true)
                focused.fulfill()
            case .bodyFocusChanged(isFocused: false):
                observedFocus.append(false)
                blurred.fulfill()
            default: break
            }
        }
        let webView = coordinator.makeWebView()
        defer { coordinator.teardown() }
        await fulfillment(of: [ready], timeout: 15)
        let isFocused = try await webView.evaluateJavaScript(#"""
        (() => {
          const block = event => event.stopImmediatePropagation();
          window.__choraiTestFocusBlock = block;
          for (const name of ["focus", "blur", "focusin", "focusout"]) {
            window.addEventListener(name, block, true);
          }
          const body = document.querySelector('.ios-editor-root [contenteditable="true"]');
          if (!body) return false;
          body.focus();
          return document.activeElement === body;
        })();
        """#) as? Bool
        XCTAssertEqual(isFocused, true)
        XCTAssertTrue(observedFocus.isEmpty)
        controller.focus()
        await fulfillment(of: [focused], timeout: 5)

        // Restore natural DOM events, then leave the body without a native blur
        // command, as system Done or focus transfer to another input would do.
        _ = try await webView.evaluateJavaScript(#"""
        (() => {
          for (const name of ["focus", "blur", "focusin", "focusout"]) {
            window.removeEventListener(name, window.__choraiTestFocusBlock, true);
          }
          delete window.__choraiTestFocusBlock;
          document.activeElement.blur();
        })();
        """#)
        await fulfillment(of: [blurred], timeout: 5)
        XCTAssertEqual(observedFocus, [true, false])
    }

}
