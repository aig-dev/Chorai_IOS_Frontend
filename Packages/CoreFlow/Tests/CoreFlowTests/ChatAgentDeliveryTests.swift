import Foundation
import XCTest
@testable import CoreFlow

final class ChatAgentDeliveryTests: XCTestCase {
    func testParserReassemblesFragmentedUnicodeFrame() throws {
        var parser = ChatServerSentEventParser()

        XCTAssertTrue(
            parser.append(
                Data("event: agent.response_ready\nid: 15\ndata: {\"status\":\"suc".utf8)
            ).isEmpty
        )

        let events = parser.append(
            Data("ceeded\",\"message_id\":\"消息_1\"}\n\n".utf8)
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(event.name, "agent.response_ready")
        XCTAssertEqual(event.id, "15")
        XCTAssertEqual(
            String(decoding: event.data, as: UTF8.self),
            #"{"status":"succeeded","message_id":"消息_1"}"#
        )
    }

    func testParserIgnoresHeartbeatAndJoinsMultilineData() throws {
        var parser = ChatServerSentEventParser()

        XCTAssertTrue(parser.append(Data(": ping\n\n".utf8)).isEmpty)

        let events = parser.append(
            Data("event: test\ndata: first\ndata: second\n\n".utf8)
        )

        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(String(decoding: event.data, as: UTF8.self), "first\nsecond")
    }

    func testThinkingEventTransitionsToThinkingWithoutRefresh() {
        let update = ChatAgentDeliveryReducer.reduce(
            event: event(name: "agent.thinking", json: #"{}"#)
        )

        XCTAssertEqual(
            update,
            ChatAgentDeliveryUpdate(state: .thinking, shouldRefreshMessages: false)
        )
    }

    func testSuccessfulResponseReadyTransitionsToIdleAndRefreshes() {
        let update = ChatAgentDeliveryReducer.reduce(
            event: event(
                name: "agent.response_ready",
                json: #"{"status":"succeeded","message_id":"msg_1"}"#
            )
        )

        XCTAssertEqual(
            update,
            ChatAgentDeliveryUpdate(state: .idle, shouldRefreshMessages: true)
        )
    }

    func testFailedResponseReadyTransitionsToUserSafeFailure() {
        let update = ChatAgentDeliveryReducer.reduce(
            event: event(
                name: "agent.response_ready",
                json: #"{"status":"failed","error_code":"AGENT_MESSAGE_PERSIST_FAILED","error_detail":"mysql: internal schema detail"}"#
            )
        )

        XCTAssertEqual(update?.shouldRefreshMessages, false)
        guard case .failed(let message) = update?.state else {
            return XCTFail("expected failed delivery state")
        }
        XCTAssertEqual(message, "Chora couldn't reply. Please try again.")
        XCTAssertFalse(message.contains("mysql"))
        XCTAssertFalse(message.contains("AGENT_MESSAGE_PERSIST_FAILED"))
    }

    func testMalformedResponseReadyTransitionsToSafeFailure() {
        let update = ChatAgentDeliveryReducer.reduce(
            event: event(name: "agent.response_ready", json: #"{"unexpected":true}"#)
        )

        XCTAssertEqual(update?.shouldRefreshMessages, false)
        guard case .failed(let message) = update?.state else {
            return XCTFail("expected malformed ready payload to fail closed")
        }
        XCTAssertEqual(message, "Chora couldn't reply. Please try again.")
    }

    func testEventCursorAdvancesMonotonicallyAcrossRacingSources() {
        var cursor = ChatConversationEventCursor()

        cursor.advance(to: 14)
        cursor.advance(to: "13")
        cursor.advance(to: "15")
        cursor.advance(to: "not-an-event-id")

        XCTAssertEqual(cursor.lastEventID, "15")
    }

    private func event(name: String, json: String) -> ChatConversationEvent {
        ChatConversationEvent(name: name, id: nil, data: Data(json.utf8))
    }
}
