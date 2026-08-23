import Foundation
import XCTest

final class ChatAgentDeliverySourceContractTests: XCTestCase {
    func testNetworkManagerStreamsTheConversationSSEContract() throws {
        let source = try source("ArcNote/NetworkManager.swift")

        XCTAssertTrue(source.contains("func streamConversationEvents("))
        XCTAssertTrue(source.contains("/events"))
        XCTAssertTrue(source.contains("text/event-stream"))
        XCTAssertTrue(source.contains("Last-Event-ID"))
        XCTAssertTrue(source.contains("ChatServerSentEventParser"))
    }

    func testChatManagerRefreshesOnReadyAndOwnsStreamLifecycle() throws {
        let source = try source("ArcNote/Models/ChatModels.swift")

        XCTAssertTrue(source.contains("func startConversationEvents("))
        XCTAssertTrue(source.contains("func stopConversationEvents()"))
        XCTAssertTrue(source.contains("ChatAgentDeliveryReducer.reduce"))
        XCTAssertTrue(source.contains("update.shouldRefreshMessages"))
        XCTAssertTrue(source.contains("loadMessages(conversationId: conversationId)"))
        XCTAssertTrue(source.contains("eventConversationID != conversationId"))
        XCTAssertTrue(source.contains("eventCancellable?.cancel()"))
        XCTAssertTrue(source.contains("eventCursor.advance(to: eventID)"))
        XCTAssertTrue(
            source.contains(
                "self.connectConversationEvents(\n                            conversationId: conversationId"
            )
        )
    }

    func testChatViewStopsStreamOnDisappear() throws {
        let source = try source("ArcNote/ChatDetailView.swift")

        XCTAssertTrue(source.contains(".onDisappear"))
        XCTAssertTrue(source.contains("stopConversationEvents()"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
