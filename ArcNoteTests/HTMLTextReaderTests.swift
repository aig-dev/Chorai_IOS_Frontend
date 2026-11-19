import XCTest
import SwiftUI
import CoreFlow
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
