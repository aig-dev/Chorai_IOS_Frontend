import XCTest
import SwiftUI
import CoreFlow
import BlockNoteEditor
import WebKit
@testable import ArcNote

@MainActor
final class HTMLTextReaderTests: XCTestCase {
    func testSuppliedAnonymousTextSharesBackgroundWorkAndOneReaderMayCancel() async {
        let probe = HTMLParseProbe()
        let entered = expectation(description: "parsing")
        let gate = DispatchSemaphore(value: 0)
        let reader = HTMLTextReader(cache: LibraryCardPreviewCache(parse: { input in
            probe.record(); entered.fulfill(); _ = gate.wait(timeout: .now() + 5)
            return LegacyHTMLTextFormatter.presentation(input.content)
        }), notifications: NotificationCenter())
        let request = reader.request(cardID: "public-note", html: "<p>Hello &amp; 世界</p>")
        let one = Task { await reader.read(request) }
        let two = Task { await reader.read(request) }
        await fulfillment(of: [entered], timeout: 3)
        await settle()
        one.cancel()
        let cancelled = await one.value
        XCTAssertNil(cancelled)
        gate.signal()
        let value = await two.value
        let warm = await reader.read(reader.request(cardID: "public-note", html: "<p>Hello &amp; 世界</p>"))
        XCTAssertEqual(value, "Hello & 世界"); XCTAssertEqual(value, warm)
        XCTAssertEqual(probe.count, 1); XCTAssertFalse(probe.onMain)
    }

    func testChangedTextMemoryPressureAndByteBudgetDoNotReturnStaleText() async {
        let probe = HTMLParseProbe()
        let notifications = NotificationCenter()
        let reader = HTMLTextReader(cache: LibraryCardPreviewCache(parse: { input in
            probe.record(); return LegacyHTMLTextFormatter.presentation(input.content)
        }), notifications: notifications)
        for (html, expected) in [("<p>one</p>", "one"), ("<p>two</p>", "two"), ("<p>two</p>", "two")] {
            let value = await reader.read(reader.request(cardID: "same", html: html))
            XCTAssertEqual(value, expected)
        }
        XCTAssertEqual(probe.count, 2)
        notifications.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        _ = await reader.read(reader.request(cardID: "same", html: "<p>two</p>"))
        XCTAssertEqual(probe.count, 3)
        let small = HTMLTextReader(cache: LibraryCardPreviewCache(byteLimit: 1, parse: { input in
            probe.record(); return LegacyHTMLTextFormatter.presentation(input.content)
        }), notifications: NotificationCenter())
        for _ in 0..<2 { _ = await small.read(small.request(cardID: "large", html: "<p>large</p>")) }
        XCTAssertEqual(probe.count, 5)
    }

    func testRetiredSessionRejectsCachedAndLateResultsButNewAnonymousInputStillRenders() async {
        let notifications = NotificationCenter()
        let entered = expectation(description: "old parse")
        let gate = DispatchSemaphore(value: 0)
        let reader = HTMLTextReader(cache: LibraryCardPreviewCache(parse: { input in
            if input.content == "old" { entered.fulfill(); _ = gate.wait(timeout: .now() + 5) }
            return LegacyHTMLTextFormatter.presentation(input.content)
        }), notifications: notifications)
        let cached = reader.request(cardID: "cached", html: "cached")
        _ = await reader.read(cached)
        let old = reader.request(cardID: "same", html: "old")
        let pending = Task { await reader.read(old) }
        await fulfillment(of: [entered], timeout: 3)
        notifications.post(name: .cardReadSessionDidChange, object: nil)
        gate.signal()
        let late = await pending.value
        let retiredCache = await reader.read(cached)
        XCTAssertNil(late); XCTAssertNil(retiredCache)
        let current = await reader.read(reader.request(cardID: "same", html: "public text"))
        XCTAssertEqual(current, "public text")
    }

    func testHostedViewClearsPreviousTextWhileChangedInputIsPreparing() async {
        let entered = expectation(description: "new parse")
        let gate = DispatchSemaphore(value: 0)
        let reader = HTMLTextReader(cache: LibraryCardPreviewCache(parse: { input in
            if input.content == "<p>new</p>" { entered.fulfill(); _ = gate.wait(timeout: .now() + 5) }
            return LegacyHTMLTextFormatter.presentation(input.content)
        }), notifications: NotificationCenter())
        let owner = HTMLRenderingOwner()
        let host = UIHostingController(rootView: HTMLRenderingHost(owner: owner, reader: reader))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        await settle()
        XCTAssertEqual(owner.displayed, "old")
        owner.html = "<p>new</p>"
        await fulfillment(of: [entered], timeout: 3)
        await settle()
        XCTAssertEqual(owner.displayed, "", "A changed source cannot keep showing the previous prepared result")
        gate.signal()
        await settle()
        XCTAssertEqual(owner.displayed, "new")
    }

    func testLongHTMLColdAndWarmWork() async {
        let probe = HTMLParseProbe()
        let reader = HTMLTextReader(cache: LibraryCardPreviewCache(parse: { input in
            probe.record(); return LegacyHTMLTextFormatter.presentation(input.content)
        }), notifications: NotificationCenter())
        let html = String(repeating: "<p>背景文本 &amp; content<br>next line</p>", count: 3_000)
        let request = reader.request(cardID: "long-fixture", html: html)
        let start = CACurrentMediaTime()
        let cold = await reader.read(request)
        let coldMS = (CACurrentMediaTime() - start) * 1000
        let warmStart = CACurrentMediaTime()
        for _ in 0..<10 {
            let warm = await reader.read(reader.request(cardID: "long-fixture", html: html))
            XCTAssertEqual(warm, cold)
        }
        let warmMS = (CACurrentMediaTime() - warmStart) * 1000 / 10
        XCTAssertNotNil(cold); XCTAssertEqual(probe.count, 1); XCTAssertFalse(probe.onMain)
        print("EXECUTION_METRIC legacy_html bytes=\(html.utf8.count) cold_ms=\(coldMS) warm_mean_ms=\(warmMS) parses=\(probe.count)")
    }

    private func settle() async {
        let turn = expectation(description: "render scheduled work")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { turn.fulfill() }
        await fulfillment(of: [turn], timeout: 2)
    }
}

@MainActor
private final class HTMLRenderingOwner: ObservableObject {
    @Published var html = "<p>old</p>"
    var displayed = ""
}

private struct HTMLRenderingHost: View {
    @ObservedObject var owner: HTMLRenderingOwner
    let reader: HTMLTextReader
    var body: some View {
        HTMLTextValue(cardID: "note", html: owner.html, reader: reader) { text in
            Text(text).onAppear { owner.displayed = text }.onChange(of: text) { owner.displayed = $0 }
        }
    }
}

private final class HTMLParseProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var main = false
    func record() { lock.lock(); defer { lock.unlock() }; calls += 1; main = main || Thread.isMainThread }
    var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
    var onMain: Bool { lock.lock(); defer { lock.unlock() }; return main }
}

@MainActor
final class NoteReaderMediaTests: XCTestCase {
    private let scope = NoteStoreScope(actorID: "ordinary-reader", environmentID: APIConfiguration.baseURL)
    private let ref = "med_0123456789abcdef"
    private var path: String { APIEnvironment.mediaContentPath(ref) + "?asset_id=note" }
    private func request(version: String = "v1", generation: UInt64 = 7) -> NoteReaderMedia.Request {
        .init(content: "summary must not replace authored blocks", contentJSON: """
        {"schema_version":1,"editor_kind":"blocknote","blocks":[
          {"id":"heading","type":"heading","props":{"level":2},"content":[{"type":"text","text":"Authored heading","styles":{"bold":true}}],"children":[]},
          {"id":"image","type":"image","props":{"mediaRef":"\(ref)","url":"https://external.invalid/ignored.png","caption":"Retained image","name":"image.png","previewWidth":320},"children":[]}]}
        """, assetID: "note", documentVersionID: version, scope: scope, generation: generation)
    }
    private func locator(_ document: BlockNoteInitialDocument?) throws -> URL {
        let value = try XCTUnwrap(document?.displayURLsByMediaReference[ref])
        return try XCTUnwrap(URL(string: value))
    }
    private func png(width: Int = 3) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: 2), format: format).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: 2))
        }.pngData()!
    }

    func testPreviewAcceptsOnlyCurrentOriginAndExactNoteContentSelector() throws {
        let origin = try XCTUnwrap(URL(string: scope.environmentID))
        let target = try XCTUnwrap(URL(string: path, relativeTo: origin)?.absoluteURL)
        XCTAssertEqual(NoteReaderMediaURL.target(target, assetID: "note", origin: origin), target)
        var controls: [URL] = []
        for raw in [path + "&asset_id=note", path + "&x=1", path + "#fragment",
                    path.replacingOccurrences(of: "asset_id=note", with: "asset_id=foreign"),
                    "https://external.invalid" + path, "//external.invalid" + path,
                    APIEnvironment.mediaContentPath(ref), path.replacingOccurrences(of: ref, with: "med_invalid")] {
            controls.append(try XCTUnwrap(URL(string: raw, relativeTo: origin)?.absoluteURL))
        }
        var port = URLComponents(url: target, resolvingAgainstBaseURL: false)!; port.port = (origin.port ?? 443) + 1
        var credentials = URLComponents(url: target, resolvingAgainstBaseURL: false)!; credentials.user = "injected"
        var encoded = URLComponents(url: target, resolvingAgainstBaseURL: false)!; encoded.percentEncodedPath = encoded.path.replacingOccurrences(of: "media", with: "%6dedia")
        controls += [port.url!, credentials.url!, encoded.url!]
        for url in controls { XCTAssertNil(NoteReaderMediaURL.target(url, assetID: "note", origin: origin), url.absoluteString) }
    }

    func testShippedReadOnlyRendererUsesStructuredBodyAndScopedImagePixels() async throws {
        let bytes = png(), retriedBytes = png(width: 4), scope = self.scope
        var calls = 0
        let loader = NoteReaderMedia(currentSession: { (scope, 7) }, download: { actual, url in
            XCTAssertEqual(actual, scope)
            XCTAssertEqual(url.path, APIEnvironment.mediaContentPath(self.ref))
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "asset_id", value: "note")])
            calls += 1; return calls == 1 ? bytes : retriedBytes
        })
        let prepared = await loader.prepare(request())
        let document = try XCTUnwrap(prepared)
        XCTAssertEqual(document.contentJSON, request().contentJSON, "Projection must not rewrite saved content")
        let model = BlockNoteCardEditorModel(document: document, editable: false, localImageSource: loader.source)
        let host = UIHostingController(rootView: BlockNoteCardEditor(model: model))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            model.controller.beginClosing(); loader.retire()
            window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey()
        }
        host.view.layoutIfNeeded()
        func webViews(_ view: UIView) -> [WKWebView] {
            if let web = view as? WKWebView { return [web] }
            return view.subviews.flatMap(webViews)
        }
        var result: [String: Any] = [:]
        for _ in 0..<100 {
            if let web = webViews(host.view).first {
                result = (try? await web.evaluateJavaScript("({width:document.images[0]?.naturalWidth||0, heading:document.querySelector('h2')?.textContent||'', editable:!!document.querySelector('[contenteditable=true]'), text:document.body.innerText})")) as? [String: Any] ?? [:]
            }
            if result["width"] as? Int == 3 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(result["width"] as? Int, 3)
        XCTAssertEqual(result["heading"] as? String, "Authored heading")
        XCTAssertEqual(result["editable"] as? Bool, false)
        XCTAssertFalse((result["text"] as? String ?? "").contains("summary must not replace"))
        let web = try XCTUnwrap(webViews(host.view).first)
        let outlines = try await web.evaluateJavaScript("""
            (() => {
              const probe = document.createElement('div');
              probe.className = 'ios-blocknote-view';
              probe.innerHTML = '<div class="bn-editor" contenteditable="false"><div class="bn-block-content ProseMirror-selectednode"><span>readonly</span></div></div><div class="bn-editor" contenteditable="true"><div class="bn-block-content ProseMirror-selectednode"><span>editable</span></div></div>';
              document.body.append(probe);
              const spans = probe.querySelectorAll('span');
              const read = getComputedStyle(spans[0]).outlineWidth;
              const edit = getComputedStyle(spans[1]).outlineWidth;
              probe.remove();
              return [read, edit];
            })()
            """) as? [String]
        XCTAssertEqual(outlines, ["0px", "4px"], "Only the read-only editor selection decoration is hidden")
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(model.canMutate); XCTAssertFalse(model.canSave)
        XCTAssertNil(model.bridgeFailureNotice); XCTAssertNil(model.compatibilityNotice)
        let firstInstance = model.editorInstanceID
        let firstAttachment = model.controller.attachment?.id
        model.receive(.bridgeError(code: "web_process_terminated"))
        // A user can tap Retry only after the failure fallback is mounted.
        for _ in 0..<30 {
            host.view.layoutIfNeeded()
            if webViews(host.view).isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(webViews(host.view).isEmpty, "The visible failure fallback must replace the failed renderer")
        model.retryAfterBridgeFailure()
        XCTAssertNotEqual(model.editorInstanceID, firstInstance)
        var recoveredWidth = 0
        for _ in 0..<100 {
            host.view.layoutIfNeeded()
            if let visible = webViews(host.view).first {
                recoveredWidth = (try? await visible.evaluateJavaScript("document.images[0]?.naturalWidth || 0")) as? Int ?? 0
            }
            if recoveredWidth == 4 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNotNil(model.controller.attachment)
        XCTAssertNotEqual(model.controller.attachment?.id, firstAttachment)
        XCTAssertEqual(recoveredWidth, 4, "The visible reader must show the new download, not retained pre-failure pixels")
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(model.canMutate); XCTAssertFalse(model.canSave)
    }

    func testDegradedSessionKeepsDeliveredBodyWithoutStartingImageDownloads() async throws {
        let state = ReaderMediaSession(scope: scope), bytes = png()
        var calls = 0
        let loader = NoteReaderMedia(currentSession: { (state.scope, 7) }, download: { _, _ in
            calls += 1; return bytes
        })
        let original = request()
        let old = try locator(await loader.prepare(original))
        state.scope = nil // The same login temporarily cannot start product requests.
        let degraded = NoteReaderMedia.Request(content: original.content, contentJSON: original.contentJSON,
            assetID: original.assetID, documentVersionID: original.documentVersionID,
            scope: nil, generation: original.generation)
        let document = await loader.prepare(degraded)
        XCTAssertNotNil(document, "A temporary verification failure must not discard delivered structured text")
        XCTAssertEqual(document?.contentJSON, original.contentJSON)
        let unavailable = try locator(document)
        do { _ = try await loader.load(unavailable); XCTFail("degraded image fell back to network") } catch {}
        do { _ = try await loader.load(old); XCTFail("read images during degraded admission") } catch {}
        XCTAssertEqual(calls, 0)
        state.scope = scope
        let recovered = try locator(await loader.prepare(original))
        let image = try await loader.load(recovered)
        XCTAssertEqual(image.data, bytes); XCTAssertEqual(calls, 1)
    }

    func testReadOnlyBridgeFailureRetriesTheOriginalDocumentWithoutEnablingEdits() async throws {
        let scope = self.scope
        let loader = NoteReaderMedia(currentSession: { (scope, 7) }, download: { _, _ in self.png() })
        let value = await loader.prepare(request())
        let document = try XCTUnwrap(value)
        let model = BlockNoteCardEditorModel(document: document, editable: false, localImageSource: loader.source)
        let original = model.editorInstanceID
        model.receive(.bridgeError(code: "web_process_terminated"))
        XCTAssertNotNil(model.bridgeFailureNotice)
        model.retryAfterBridgeFailure()
        XCTAssertNotEqual(model.editorInstanceID, original)
        XCTAssertNil(model.bridgeFailureNotice)
        XCTAssertEqual(model.initialDocument, document)
        XCTAssertFalse(model.isInitiallyEditable); XCTAssertFalse(model.canMutate); XCTAssertFalse(model.canSave)
    }

    func testSessionDocumentReplacementCancellationAndRetirementRejectLateBytes() async throws {
        for change in ["session", "account", "version", "retire", "cancel"] {
            let state = ReaderMediaSession(scope: scope)
            let entered = expectation(description: change)
            let gate = ReaderMediaGate(entered)
            let loader = NoteReaderMedia(currentSession: { (state.scope, state.generation) }, download: { _, _ in try await gate.wait() })
            let first = try locator(await loader.prepare(request()))
            let pending = Task { try await loader.load(first) }
            await fulfillment(of: [entered], timeout: 2)
            switch change {
            case "session": state.generation += 1
            case "account": state.scope = nil
            case "version": _ = await loader.prepare(request(version: "v2"))
            case "retire": loader.retire()
            default: pending.cancel()
            }
            gate.release(png())
            do { _ = try await pending.value; XCTFail("accepted late bytes after \(change)") } catch {}
            if change != "cancel" {
                do { _ = try await loader.load(first); XCTFail("accepted retired locator after \(change)") } catch {}
            }
        }
    }

    func testAlreadyCanceledOrRetiredPreparationCannotInvalidateCurrentDocument() async throws {
        let scope = self.scope, bytes = png()
        let loader = NoteReaderMedia(currentSession: { (scope, 7) }, download: { _, _ in bytes })
        let current = try locator(await loader.prepare(request(version: "v2")))
        let old = Task { await loader.prepare(request(version: "v1")) }
        old.cancel() // This MainActor task has not been scheduled yet.
        let discarded = await old.value
        XCTAssertNil(discarded)
        let retired = await loader.prepare(request(generation: 6))
        XCTAssertNil(retired)
        let accepted = try await loader.load(current)
        XCTAssertEqual(accepted.data, bytes)
    }

    func testUnknownLocatorAndInvalidImagesNeverReturnBytes() async throws {
        var calls = 0
        let scope = self.scope
        let loader = NoteReaderMedia(currentSession: { (scope, 7) }, download: { _, _ in calls += 1; return Data("not an image".utf8) })
        let original = try locator(await loader.prepare(request()))
        var forged = URLComponents(url: original, resolvingAgainstBaseURL: false)!; forged.path = "/unregistered"
        do { _ = try await loader.load(forged.url!); XCTFail("accepted unknown locator") } catch {}
        XCTAssertEqual(calls, 0)
        do { _ = try await loader.load(original); XCTFail("accepted invalid image") } catch {}
        XCTAssertEqual(calls, 1)
    }
}

@MainActor
private final class ReaderMediaSession {
    var scope: NoteStoreScope?
    var generation: UInt64 = 7
    init(scope: NoteStoreScope) { self.scope = scope }
}

@MainActor
private final class ReaderMediaGate {
    let entered: XCTestExpectation
    var continuation: CheckedContinuation<Data, Error>?
    init(_ entered: XCTestExpectation) { self.entered = entered }
    func wait() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation; entered.fulfill()
        }
    }
    func release(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
}
