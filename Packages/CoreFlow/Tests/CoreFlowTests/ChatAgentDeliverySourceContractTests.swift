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

    // Manager ordering, replay and lifetime are exercised by hosted
    // ChatDetailManagerTests with controlled callbacks, not source substrings.

    func testChatViewStopsStreamOnDisappear() throws {
        let source = try source("ArcNote/ChatDetailView.swift")

        XCTAssertTrue(source.contains(".onDisappear"))
        XCTAssertTrue(source.contains("stopConversationEvents()"))
    }

    func testManualRecoveryUsesTypedAPIAndRestoresCalmState() throws {
        let models = try source("ArcNote/Models/ChatModels.swift")
        let network = try source("ArcNote/NetworkManager.swift")
        let view = try source("ArcNote/ChatDetailView.swift")

        XCTAssertTrue(models.contains("func retryAgentReply("))
        XCTAssertTrue(models.contains("AgentReplyRetryResponse"))
        XCTAssertTrue(network.contains("/agent-reply/retry"))
        XCTAssertTrue(
            network.contains(
                "func retryAgentReply(\n        conversationId: String,\n        sourceMessageId: String\n    ) -> AnyPublisher<AgentReplyRetryResponse, NetworkError> {\n        Deferred"
            ),
            "The recovery publisher must create a fresh HTTP Future for each retry subscription"
        )
        XCTAssertTrue(models.contains(".retryAvailable("))
        XCTAssertTrue(models.contains("sourceMessageID: sourceMessageID"))
        XCTAssertTrue(view.contains("chat.agent.retry"))
        XCTAssertTrue(view.contains("Continue "))
        XCTAssertFalse(view.contains("chat.agent.failed"))
        XCTAssertFalse(models.contains("agentDeliveryState = .failed"))
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
