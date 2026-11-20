import XCTest
import Combine
import os
@testable import ArcNote

@MainActor
final class CardDetailReaderTests: XCTestCase {
    func testChatReferenceAndDetailShareReadWhilePublisherCancellationOnlyRetiresItsWaiter() async throws {
        let started = expectation(description: "started")
        let received = expectation(description: "chat received")
        let fixture = HTTPFixture(onStart: { started.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        let reader = CardDetailReader(session: { 1 }, fetch: { network.getCardDetailPublisher(cardId: $0, presentsError: false) })
        let unusedPublisher = reader.referencedNote(cardID: "card")
        XCTAssertEqual(fixture.count, 0)
        let cancelled = unusedPublisher.sink(receiveCompletion: { _ in }, receiveValue: { _ in XCTFail("Cancelled subscriber received") })
        let chat = reader.referencedNote(cardID: "card").sink(receiveCompletion: { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
        }, receiveValue: { note in XCTAssertEqual(note.id, "card"); received.fulfill() })
        let detail = Task { try await reader.confirmed(cardID: "card") }
        await fulfillment(of: [started], timeout: 3)
        cancelled.cancel()
        fixture.respond(HTTPFixture.detail)
        _ = try await detail.value
        await fulfillment(of: [received], timeout: 3)
        XCTAssertEqual(fixture.count, 1)
        chat.cancel()
    }

    func testSharedReadSurvivesOneCancelledWaiter() async throws {
        let started = expectation(description: "started")
        let stopped = expectation(description: "not stopped"); stopped.isInverted = true
        let fixture = HTTPFixture(onStart: { started.fulfill() }, onStop: { stopped.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        let reader = CardDetailReader(session: { 1 }, fetch: { network.getCardDetailPublisher(cardId: $0, presentsError: false) })
        let one = Task { try await reader.confirmed(cardID: "card") }
        let two = Task { try await reader.confirmed(cardID: "card") }
        await fulfillment(of: [started], timeout: 3)
        one.cancel()
        fixture.respond(HTTPFixture.detail)
        let detail = try await two.value
        XCTAssertEqual(detail.id, "card")
        do { _ = try await one.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(fixture.count, 1)
        XCTAssertNotNil(reader.cached(cardID: "card"))
        await fulfillment(of: [stopped], timeout: 0.05)
    }

    func testSessionInvalidationCancelsHTTPAndNextConfirmationStartsAgain() async throws {
        let started = expectation(description: "first")
        let nextStarted = expectation(description: "next")
        let stopped = expectation(description: "HTTP canceled")
        let sequence = OSAllocatedUnfairLock(initialState: 0)
        let fixture = HTTPFixture(onStart: {
            let count = sequence.withLock { $0 += 1; return $0 }
            if count == 1 { started.fulfill() } else { nextStarted.fulfill() }
        }, onStop: { stopped.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        var generation: UInt64? = 1
        let reader = CardDetailReader(session: { generation }, fetch: { network.getCardDetailPublisher(cardId: $0, presentsError: false) })
        let first = Task { try await reader.confirmed(cardID: "card") }
        await fulfillment(of: [started], timeout: 3)
        generation = 2
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        await fulfillment(of: [stopped], timeout: 3)
        fixture.respond(HTTPFixture.detail)
        do { _ = try await first.value; XCTFail("Old result accepted") } catch {}
        XCTAssertNil(reader.cached(cardID: "card"))
        let next = Task { try await reader.confirmed(cardID: "card") }
        await fulfillment(of: [nextStarted], timeout: 3)
        fixture.respond(HTTPFixture.detail, at: 1)
        let detail = try await next.value
        XCTAssertEqual(detail.id, "card")
        XCTAssertEqual(fixture.count, 2)
    }

    func testDetailGETStartsOnlyOnSubscriptionAndCancelsRealRequest() async {
        let started = expectation(description: "started")
        let stopped = expectation(description: "stopped")
        let fixture = HTTPFixture(onStart: { started.fulfill() }, onStop: { stopped.fulfill() })
        let network = NetworkManager(baseURL: fixture.baseURL, session: fixture.session)
        let publisher = network.getCardDetailPublisher(cardId: "card", presentsError: false)
        XCTAssertEqual(fixture.count, 0)
        let token = publisher.sink(receiveCompletion: { _ in XCTFail("Canceled request delivered") }, receiveValue: { _ in XCTFail("Canceled request delivered") })
        await fulfillment(of: [started], timeout: 3)
        token.cancel()
        await fulfillment(of: [stopped], timeout: 3)
    }
}
