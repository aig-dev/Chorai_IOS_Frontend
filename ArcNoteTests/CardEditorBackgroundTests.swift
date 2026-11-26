import CoreFlow
import SwiftUI
import UIKit
import XCTest
@testable import ArcNote

@MainActor
final class CardEditorBackgroundTests: XCTestCase {
    private let scope = NoteStoreScope(actorID: "background-owner", environmentID: APIConfiguration.baseURL)

    private func request(_ name: String, generation: UInt64 = 7) -> CardEditorBackgroundImage.Request {
        var parts = URLComponents()
        parts.scheme = "https"; parts.host = "image.invalid"; parts.path = "/" + name
        return .init(url: parts.url!, scope: scope, sessionGeneration: generation)
    }

    private func png(width: Int) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: 2), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: 2))
        }.pngData()!
    }

    func testPublishingImageDoesNotRestartTheViewLoad() async {
        let expected = request("stable-view")
        let bytes = png(width: 3)
        let first = expectation(description: "first view download")
        let duplicate = expectation(description: "image publication must not start another task")
        duplicate.isInverted = true
        let calls = BackgroundLoadCounter()
        let model = CardEditorBackgroundImage(currentSession: { (self.scope, 7) }, load: { _, _ in
            calls.value += 1
            if calls.value == 1 { first.fulfill() }
            if calls.value == 2 { duplicate.fulfill() }
            return bytes
        })
        let host = UIHostingController(rootView: CardEditorRemoteBackground(request: expected, loader: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await fulfillment(of: [first], timeout: 2)
        await fulfillment(of: [duplicate], timeout: 0.5)
        XCTAssertEqual(calls.value, 1)
        XCTAssertNotNil(model.image(for: expected))
    }

    func testRemoteBackgroundKeepsProposedBoundsAfterImageLoads() async {
        let expected = request("bounded-view")
        let bytes = png(width: 3)
        let model = CardEditorBackgroundImage(currentSession: { (self.scope, 7) }, load: { _, _ in bytes })
        await model.load(expected)
        XCTAssertNotNil(model.image(for: expected))
        let host = UIHostingController(rootView: CardEditorRemoteBackground(request: expected, loader: model))
        let proposal = CGSize(width: 160, height: 200)
        let actual = host.sizeThatFits(in: proposal)
        XCTAssertEqual(actual.width, proposal.width, accuracy: 0.5,
                       "Aspect-fill pixels must not enlarge the decorative background's layout bounds")
        XCTAssertEqual(actual.height, proposal.height, accuracy: 0.5)
    }

    func testBecomingEligibleRetriesSameURLAndSession() async {
        let current = BackgroundTestSession(scope: nil, generation: 7)
        let eligible = request("recovered-view")
        let deferred = CardEditorBackgroundImage.Request(url: eligible.url, scope: eligible.scope,
                                                        sessionGeneration: eligible.sessionGeneration, canLoad: false)
        let bytes = png(width: 3)
        let loaded = expectation(description: "download after admission recovers")
        let calls = BackgroundLoadCounter()
        let model = CardEditorBackgroundImage(currentSession: { (current.scope, current.generation) }, load: { _, _ in
            calls.value += 1
            if calls.value == 1 { loaded.fulfill() }
            return bytes
        })
        let host = UIHostingController(rootView: CardEditorRemoteBackground(request: deferred, loader: model))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        await Task.yield()
        XCTAssertEqual(calls.value, 0)
        current.scope = scope
        host.rootView = CardEditorRemoteBackground(request: eligible, loader: model)
        await fulfillment(of: [loaded], timeout: 2)
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(current.generation, eligible.sessionGeneration)
    }

    func testLoadsExactScopeAndURLAndDecodesOffMain() async throws {
        let expected = request("accepted")
        let bytes = png(width: 3)
        var calls = 0
        let model = CardEditorBackgroundImage(currentSession: { (self.scope, 7) }, load: { scope, url in
            XCTAssertEqual(scope, expected.scope); XCTAssertEqual(url, expected.url)
            calls += 1; return bytes
        }, prepare: { data in
            XCTAssertFalse(Thread.isMainThread)
            XCTAssertEqual(data, bytes)
            return UIImage(data: data)
        })
        await model.load(expected)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try XCTUnwrap(model.image(for: expected)).size.width, 3)
    }

    func testLateOldURLCannotReplaceNewImage() async throws {
        let old = request("old"), latest = request("latest")
        let started = expectation(description: "old download entered")
        let gate = BackgroundDownloadGate(started)
        let oldBytes = png(width: 3), newBytes = png(width: 5)
        let model = CardEditorBackgroundImage(currentSession: { (self.scope, 7) }, load: { _, url in
            if url == old.url { return try await gate.wait() }
            return newBytes
        })
        let pending = Task { await model.load(old) }
        await fulfillment(of: [started], timeout: 2)
        await model.load(latest)
        gate.resume(oldBytes)
        await pending.value
        XCTAssertNil(model.image(for: old))
        XCTAssertEqual(try XCTUnwrap(model.image(for: latest)).size.width, 5)
    }

    func testAccountOrSessionChangeRejectsPendingAndAlreadyLoadedImages() async throws {
        for changeAccount in [true, false] {
            let current = BackgroundTestSession(scope: scope, generation: 7)
            let expected = request("session")
            let started = expectation(description: "pending session download")
            let gate = BackgroundDownloadGate(started)
            let bytes = png(width: 4)
            let model = CardEditorBackgroundImage(currentSession: { (current.scope, current.generation) }, load: { _, _ in
                try await gate.wait()
            })
            let pending = Task { await model.load(expected) }
            await fulfillment(of: [started], timeout: 2)
            if changeAccount { current.scope = .init(actorID: "other", environmentID: self.scope.environmentID) }
            else { current.generation += 1 }
            gate.resume(bytes)
            await pending.value
            XCTAssertNil(model.image(for: expected))

            current.scope = scope; current.generation = 7
            let accepted = CardEditorBackgroundImage(currentSession: { (current.scope, current.generation) }, load: { _, _ in bytes })
            await accepted.load(expected)
            XCTAssertNotNil(accepted.image(for: expected))
            if changeAccount { current.scope = .init(actorID: "other", environmentID: self.scope.environmentID) }
            else { current.generation += 1 }
            XCTAssertNil(accepted.image(for: expected), "A published image must stop rendering when its session retires")
        }
    }

    func testCancellationIgnoringDownloadCannotPublishImage() async {
        let expected = request("cancelled")
        let started = expectation(description: "download entered")
        let gate = BackgroundDownloadGate(started)
        let model = CardEditorBackgroundImage(currentSession: { (self.scope, 7) }, load: { _, _ in try await gate.wait() })
        let pending = Task { await model.load(expected) }
        await fulfillment(of: [started], timeout: 2)
        pending.cancel(); gate.resume(png(width: 3))
        await pending.value
        XCTAssertNil(model.image(for: expected))
    }

    func testSessionChangeDuringDecodeRejectsThePreparedImage() async {
        let current = BackgroundTestSession(scope: scope, generation: 7)
        let expected = request("decode")
        let bytes = png(width: 3)
        let started = expectation(description: "decode entered")
        let gate = DispatchSemaphore(value: 0)
        let model = CardEditorBackgroundImage(currentSession: { (current.scope, current.generation) }, load: { _, _ in bytes }, prepare: { data in
            started.fulfill(); _ = gate.wait(timeout: .now() + 3)
            return UIImage(data: data)
        })
        let pending = Task { await model.load(expected) }
        await fulfillment(of: [started], timeout: 2)
        current.generation += 1; gate.signal()
        await pending.value
        XCTAssertNil(model.image(for: expected))
    }

    func testNoCurrentSessionDoesNotStartDownload() async {
        var calls = 0
        let expected = request("denied")
        let model = CardEditorBackgroundImage(currentSession: { (nil, 7) }, load: { _, _ in
            calls += 1; return Data()
        })
        await model.load(expected)
        XCTAssertEqual(calls, 0)
        XCTAssertNil(model.image(for: expected))
    }

    func testInvalidBytesDoNotPreservePreviousImage() async {
        let valid = request("valid"), invalid = request("invalid")
        let bytes = png(width: 3)
        let model = CardEditorBackgroundImage(currentSession: { (self.scope, 7) }, load: { _, url in
            url == valid.url ? bytes : Data("invalid".utf8)
        })
        await model.load(valid)
        XCTAssertNotNil(model.image(for: valid))
        await model.load(invalid)
        XCTAssertNil(model.image(for: valid)); XCTAssertNil(model.image(for: invalid))
    }
}

@MainActor
private final class BackgroundDownloadGate {
    private let started: XCTestExpectation
    private var continuation: CheckedContinuation<Data, Error>?
    init(_ started: XCTestExpectation) { self.started = started }
    func wait() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
    func resume(_ data: Data) { continuation?.resume(returning: data); continuation = nil }
}

@MainActor
private final class BackgroundTestSession {
    var scope: NoteStoreScope?
    var generation: UInt64
    init(scope: NoteStoreScope?, generation: UInt64) { self.scope = scope; self.generation = generation }
}

@MainActor
private final class BackgroundLoadCounter { var value = 0 }
