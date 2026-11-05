import Foundation
import WebKit
import XCTest
@testable import BlockNoteEditor

@MainActor
final class BlockNoteLocalImagesTests: XCTestCase {
    func testBundledEditorCanDecodeItsScopedLocalImageUnderTheActualCSP() async throws {
        let ready = expectation(description: "editor ready")
        let bytes = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jZQAAAABJRU5ErkJggg=="))
        var requested = false
        let source = BlockNoteLocalImageSource(scheme: "chorai-note-media") { _ in
            requested = true
            return (bytes, "image/png")
        }
        let coordinator = BlockNoteEditorCoordinator(
            document: .init(contentJSON: nil, fallbackMarkdown: ""),
            editable: true, controller: BlockNoteEditorController(), localImageSource: source
        ) { event in
            if case .availabilityChanged(.ready) = event { ready.fulfill() }
        }
        let webView = coordinator.makeWebView()
        defer { coordinator.teardown() }
        await fulfillment(of: [ready], timeout: 15)
        let width = try await webView.callAsyncJavaScript("""
            return await new Promise(resolve => {
              const image = document.createElement('img');
              image.onload = () => resolve(image.naturalWidth);
              image.onerror = () => resolve(0);
              image.src = 'chorai-note-media://attachment/owned';
              document.body.append(image);
            });
            """, arguments: [:], in: nil, contentWorld: .page) as? Int
        XCTAssertTrue(requested)
        XCTAssertEqual(width, 1)
    }

    func testSchemeServesOnlyBytesReturnedByItsNoteScopedSource() async throws {
        let finished = expectation(description: "image finished")
        let bytes = Data([7, 8, 9])
        let source = BlockNoteLocalImageSource(scheme: "chorai-note-media") { url in
            XCTAssertEqual(url.absoluteString, "chorai-note-media://attachment/owned")
            return (bytes, "image/png")
        }
        let handler = BlockNoteLocalImageHandler(source: source)
        let request = LocalImageTask(url: try XCTUnwrap(URL(string: "chorai-note-media://attachment/owned")), terminal: finished)
        handler.webView(WKWebView(), start: request)
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(request.bytes, bytes)
        XCTAssertEqual(request.response?.mimeType, "image/png")
        XCTAssertNil(request.failure)
        handler.close()
    }

    func testDeniedSourceNeverReturnsImageBytes() async throws {
        let finished = expectation(description: "image denied")
        let source = BlockNoteLocalImageSource(scheme: "chorai-note-media") { _ in throw URLError(.userAuthenticationRequired) }
        let handler = BlockNoteLocalImageHandler(source: source)
        let request = LocalImageTask(url: try XCTUnwrap(URL(string: "chorai-note-media://attachment/other-account")), terminal: finished)
        handler.webView(WKWebView(), start: request)
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertTrue(request.bytes.isEmpty)
        XCTAssertNotNil(request.failure)
        handler.close()
    }

    func testStoppedRequestCannotReceiveLateBytes() async throws {
        let started = expectation(description: "source started")
        let returned = expectation(description: "source returned")
        let unexpected = expectation(description: "stopped request callback"); unexpected.isInverted = true
        var resume: CheckedContinuation<Void, Never>?
        let source = BlockNoteLocalImageSource(scheme: "chorai-note-media") { _ in
            await withCheckedContinuation { resume = $0; started.fulfill() }
            returned.fulfill()
            return (Data([1]), "image/png")
        }
        let handler = BlockNoteLocalImageHandler(source: source)
        let request = LocalImageTask(url: try XCTUnwrap(URL(string: "chorai-note-media://attachment/late")), terminal: unexpected)
        let webView = WKWebView()
        handler.webView(webView, start: request)
        await fulfillment(of: [started], timeout: 2)
        handler.webView(webView, stop: request)
        resume?.resume()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [unexpected], timeout: 0.05)
        XCTAssertTrue(request.bytes.isEmpty)
        XCTAssertNil(request.response)
        handler.close()
    }
}

@MainActor
private final class LocalImageTask: NSObject, @preconcurrency WKURLSchemeTask {
    let request: URLRequest
    let terminal: XCTestExpectation
    var bytes = Data()
    var response: URLResponse?
    var failure: Error?
    init(url: URL, terminal: XCTestExpectation) {
        request = URLRequest(url: url); self.terminal = terminal
    }
    func didReceive(_ response: URLResponse) { self.response = response }
    func didReceive(_ data: Data) { bytes.append(data) }
    func didFinish() { terminal.fulfill() }
    func didFailWithError(_ error: Error) { failure = error; terminal.fulfill() }
}
