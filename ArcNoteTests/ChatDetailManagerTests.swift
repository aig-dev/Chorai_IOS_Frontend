import XCTest
import Combine
import CoreFlow
@testable import ArcNote

@MainActor
final class ChatDetailManagerTests: XCTestCase {
    func testOlderMessageRefreshCannotReplaceNewerResponse() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.loadConversationDetail(conversationId: "old")
        manager.loadConversationDetail(conversationId: "new")
        fetcher.finishMessages(1, ids: ["new-message"])
        await drainDelivery()
        fetcher.finishMessages(0, ids: ["old-message"])
        fetcher.details[0].send(detail("old"))
        fetcher.details[0].send(completion: .finished)
        await drainDelivery()
        XCTAssertEqual(manager.messages.map(\.id), ["new-message"])
        XCTAssertNil(manager.conversation)
        XCTAssertTrue(manager.isLoading, "The new detail read is still pending")
        fetcher.details[1].send(detail("new"))
        fetcher.details[1].send(completion: .finished)
        await drainDelivery()
        XCTAssertEqual(manager.conversation?.id, "new")
        XCTAssertFalse(manager.isLoading)
        manager.stopConversationEvents()
    }

    func testOldFailureCannotChangeNewErrorOrLoadingState() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.loadConversationDetail(conversationId: "old")
        manager.loadConversationDetail(conversationId: "new")
        fetcher.messageReads[0].subject.send(completion: .failure(.unauthorized))
        fetcher.details[0].send(completion: .failure(.forbidden))
        await drainDelivery()
        XCTAssertNil(manager.error)
        XCTAssertTrue(manager.isLoading)
        manager.stopConversationEvents()
    }

    func testEventBurstCoalescesRefreshWithoutLosingLatestMessage() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.startConversationEvents(conversationId: "chat")
        manager.loadMessages(conversationId: "chat")
        for id in 1...12 {
            fetcher.streams[0].subject.send(ready(id: String(id)))
        }
        await drainDelivery()
        XCTAssertEqual(fetcher.messageReads.count, 1, "Events share the in-flight read")
        fetcher.finishMessages(0, ids: ["before-events"])
        await drainDelivery()
        XCTAssertEqual(fetcher.messageReads.count, 2, "One trailing read must observe the last event")
        XCTAssertTrue(manager.isLoading)
        guard fetcher.messageReads.count >= 2 else { return }
        fetcher.finishMessages(1, ids: ["latest"])
        await drainDelivery()
        XCTAssertEqual(manager.messages.map(\.id), ["latest"])
        XCTAssertFalse(manager.isLoading)
        manager.stopConversationEvents()
    }

    func testRetiredConversationRejectsLateMessagesAndHydration() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.startConversationEvents(conversationId: "same")
        manager.loadMessages(conversationId: "same")
        fetcher.finishMessages(0, ids: ["before-retirement"], reference: "note")
        await drainDelivery()
        XCTAssertEqual(fetcher.references.count, 1)
        manager.loadMessages(conversationId: "same")
        manager.stopConversationEvents()
        manager.startConversationEvents(conversationId: "same")
        manager.loadMessages(conversationId: "same")
        fetcher.finishMessages(2, ids: ["after-retirement"], reference: "note")
        await drainDelivery()
        fetcher.references[0].send(NoteCard(id: "note", title: "retired", description: "", isPublic: false, username: "", avatarUrl: nil))
        fetcher.references[0].send(completion: .finished)
        await drainDelivery()
        XCTAssertTrue(manager.messages.first?.attachedCards.isEmpty == true, "A retired hydration must not attach old content to the current message")
        fetcher.finishMessages(1, ids: ["late-old-read"])
        await drainDelivery()
        XCTAssertEqual(manager.messages.map(\.id), ["after-retirement"])
        XCTAssertTrue(manager.messages.first?.attachedCards.isEmpty == true)
        manager.stopConversationEvents()
    }

    func testLatestPageStillUsesServerPagination() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.loadMessages(conversationId: "chat")
        fetcher.finishMessages(0, ids: ["oldest"], pages: 3)
        await drainDelivery()
        XCTAssertEqual(fetcher.messageReads.map(\.page), [1, 3])
        XCTAssertEqual(fetcher.messageReads.map(\.perPage), [20, 20])
        fetcher.finishMessages(1, ids: ["newest"], pages: 3)
        await drainDelivery()
        XCTAssertEqual(manager.messages.map(\.id), ["newest"])
        manager.stopConversationEvents()
    }

    func testDuplicateEventsDoNotRefreshAgainOrRestoreOldFailure() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.startConversationEvents(conversationId: "chat")
        fetcher.streams[0].subject.send(ready(id: "20"))
        await drainDelivery()
        fetcher.finishMessages(0, ids: ["reply"])
        await drainDelivery()
        fetcher.streams[0].subject.send(ready(id: "20"))
        fetcher.streams[0].subject.send(ChatConversationEvent(name: "agent.response_ready", id: "19", data: Data(#"{"status":"retry_available","source_message_id":"source"}"#.utf8)))
        await drainDelivery()
        XCTAssertEqual(fetcher.messageReads.count, 1)
        XCTAssertEqual(manager.agentDeliveryState, .idle)
        manager.stopConversationEvents()
    }

    func testOldFailureDoesNotHideNewReplyAndRemainsRecoverableAfterItsSuccess() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.startConversationEvents(conversationId: "chat")
        let events = [
            ("agent.thinking", #"{"source_message_id":"old"}"#),
            ("agent.thinking", #"{"source_message_id":"new"}"#),
            ("agent.response_ready", #"{"status":"retry_available","source_message_id":"old"}"#)
        ]
        for (index, event) in events.enumerated() {
            fetcher.streams[0].subject.send(ChatConversationEvent(name: event.0, id: String(index + 1), data: Data(event.1.utf8)))
        }
        await drainDelivery()
        XCTAssertEqual(manager.agentDeliveryState, .thinking)
        fetcher.streams[0].subject.send(ChatConversationEvent(name: "agent.response_ready", id: "4", data: Data(#"{"status":"succeeded","source_message_id":"batch","source_message_ids":["new"]}"#.utf8)))
        await drainDelivery()
        XCTAssertEqual(manager.agentDeliveryState, .retryAvailable(sourceMessageID: "old"))
        manager.stopConversationEvents()
    }

    func testReconnectUsesLastAcceptedCursorAndStopsAfterRetirement() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.startConversationEvents(conversationId: "chat")
        fetcher.streams[0].subject.send(ChatConversationEvent(name: "agent.thinking", id: "42", data: Data(#"{"source_message_id":"source"}"#.utf8)))
        fetcher.streams[0].subject.send(completion: .finished)
        let reconnected = expectation(description: "reconnected")
        fetcher.onStream = { reconnected.fulfill() }
        await fulfillment(of: [reconnected], timeout: 3)
        XCTAssertEqual(fetcher.streams.last?.cursor, "42")
        manager.stopConversationEvents()
        let extraConnection = expectation(description: "no connection after stop")
        extraConnection.isInverted = true
        fetcher.onStream = { extraConnection.fulfill() }
        fetcher.streams.last?.subject.send(completion: .finished)
        await fulfillment(of: [extraConnection], timeout: 1.2)
    }

    func testLateSendCannotReopenRetiredConversation() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.startConversationEvents(conversationId: "old")
        manager.sendMessage(conversationId: "old", content: "hello", attachedNotes: [])
        // Queue delivery before changing scope; correctness must not depend on
        // whether the network still supports canceling an already committed send.
        fetcher.sends[0].send(SendMessageResponse(success: true, data: SendMessageData(message: message("late"), eventId: 12)))
        manager.startConversationEvents(conversationId: "new")
        await drainDelivery()
        XCTAssertTrue(manager.messages.isEmpty)
        XCTAssertTrue(fetcher.messageReads.isEmpty)
        XCTAssertEqual(fetcher.streams.last?.conversationID, "new")
        manager.stopConversationEvents()
    }

    func testAuthenticationRetirementSynchronouslyClearsAndRejectsOldCallbacks() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.loadMessages(conversationId: "chat")
        fetcher.finishMessages(0, ids: ["private"])
        await drainDelivery()
        NotificationCenter.default.post(name: .cardReadSessionDidChange, object: nil)
        XCTAssertTrue(manager.messages.isEmpty, "Revocation must not wait for a later main-queue turn")
        manager.loadMessages(conversationId: "chat")
        XCTAssertEqual(fetcher.messageReads.count, 1, "An old account's manager cannot reactivate")
        manager.stopConversationEvents()
    }

    func testSendAcknowledgementDoesNotSkipUnconsumedStreamEvents() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.startConversationEvents(conversationId: "chat")
        fetcher.streams[0].subject.send(ChatConversationEvent(name: "agent.thinking", id: "40", data: Data(#"{"source_message_id":"old"}"#.utf8)))
        await drainDelivery()
        manager.sendMessage(conversationId: "chat", content: "next", attachedNotes: [])
        fetcher.sends[0].send(SendMessageResponse(success: true, data: SendMessageData(message: message("next"), eventId: 50)))
        await drainDelivery()
        XCTAssertEqual(fetcher.streams.count, 1, "An acknowledgement is not proof that events 41...49 were consumed")
        fetcher.streams[0].subject.send(ChatConversationEvent(name: "agent.response_ready", id: "45", data: Data(#"{"status":"retry_available","source_message_id":"old"}"#.utf8)))
        await drainDelivery()
        XCTAssertEqual(manager.agentDeliveryState, .retryAvailable(sourceMessageID: "old"))
        manager.stopConversationEvents()
    }

    func testLateRetryAcceptanceCannotReopenReplyCompletedByStream() async {
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.startConversationEvents(conversationId: "chat")
        manager.retryAgentReply(conversationId: "chat", sourceMessageId: "source")
        fetcher.streams[0].subject.send(ready(id: "1"))
        await drainDelivery()
        fetcher.retries[0].send(AgentReplyRetryResponse(success: true, data: AgentReplyRetryData(status: "accepted", sourceMessageId: "source")))
        fetcher.retries[0].send(completion: .finished)
        await drainDelivery()
        XCTAssertEqual(manager.agentDeliveryState, .idle)
        manager.stopConversationEvents()
    }

    func testPresentationPreservesOrderOwnershipAndSyntheticBaseline() async {
        for count in [20, 500] {
            let fetcher = ControlledChatFetcher()
            let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
            manager.loadMessages(conversationId: "chat")
            let values = (0..<count).reversed().map { index in
                APIChatMessage(id: "m-\(index)", content: "Synthetic \(index)", senderId: index.isMultiple(of: 2) ? "human" : "agent", receiverId: "human", createdAt: String(format: "2010-01-02T00:%02d:%02dZ", index / 60, index % 60), messageType: "text", isFromCurrentUser: false)
            }
            fetcher.messageReads[0].subject.send(MessagesListResponse(success: true, data: MessagesListData(items: values, pagination: ChatPagination(page: 1, perPage: count, total: count, pages: 1, hasNext: false, hasPrev: false))))
            let preparationStart = ContinuousClock.now
            await drainDelivery()
            let preparation = preparationStart.duration(to: .now)
            let readStart = ContinuousClock.now
            var displayed: [ChatMessage] = []
            for _ in 0..<10 { displayed = manager.displayMessages }
            let repeatedReads = readStart.duration(to: .now)
            XCTAssertEqual(displayed.first?.id, "m-0")
            XCTAssertEqual(displayed.last?.id, "m-\(count - 1)")
            XCTAssertTrue(displayed.first?.isFromMe == true)
            XCTAssertFalse(displayed[1].isFromMe)
            XCTAssertEqual(displayed.count, count)
            print("CHAT_SYNTHETIC count=\(count) publication=\(preparation) displayReads10=\(repeatedReads)")
            manager.stopConversationEvents()
        }
    }

    func testPresentationTracksHydrationPartnerAvatarAndHistoryClear() async throws {
        let suite = "ChatDetailManagerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let visibility = ChatHistoryVisibilityDependency(visibility: ChatHistoryVisibility(persistence: UserDefaultsChatHistoryCutoffPersistence(defaults: defaults)))
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.bindVisibility(visibility)
        manager.loadConversationDetail(conversationId: "chat")
        fetcher.details[0].send(detail("chat"))
        fetcher.details[0].send(completion: .finished)
        fetcher.finishMessages(0, ids: ["with-note"], reference: "note")
        await drainDelivery()
        let note = NoteCard(id: "note", title: "Hydrated", description: "", isPublic: false, username: "", avatarUrl: nil)
        fetcher.references[0].send(note)
        fetcher.references[0].send(completion: .finished)
        ChoraAvatarUpdate(actorID: "agent", avatarURL: "avatar-new")?.post()
        await drainDelivery()
        XCTAssertEqual(manager.displayMessages.first?.attachedNotes, [note])
        XCTAssertEqual(manager.displayMessages.first?.avatarURL, "avatar-new")
        visibility.clear(actorID: "human", at: Date(timeIntervalSince1970: 2_000_000_000))
        await drainDelivery()
        XCTAssertTrue(manager.displayMessages.isEmpty)
        manager.stopConversationEvents()
    }

    func testEventParserSyntheticBaseline() {
        for count in [20, 500] {
            let bytes = Data((0..<count).map { "event: agent.response_ready\nid: \($0)\ndata: {\"status\":\"succeeded\",\"source_message_id\":\"synthetic\"}\n\n" }.joined().utf8)
            var parser = ChatServerSentEventParser()
            let start = ContinuousClock.now
            let events = parser.append(bytes)
            let updates = events.compactMap(ChatAgentDeliveryReducer.reduce)
            let elapsed = start.duration(to: .now)
            XCTAssertEqual(events.count, count)
            XCTAssertEqual(updates.count, count)
            print("CHAT_SSE_SYNTHETIC events=\(count) bytes=\(bytes.count) parseAndReduce=\(elapsed)")
        }
    }

    func testCachedPresentationRespondsToTimeZoneChange() async throws {
        let previousZone = NSTimeZone.default
        defer { NSTimeZone.default = previousZone }
        NSTimeZone.default = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let fetcher = ControlledChatFetcher()
        let manager = ChatDetailManager(humanActorID: "human", fetcher: fetcher)
        manager.loadMessages(conversationId: "chat")
        let value = APIChatMessage(id: "midnight", content: "hello", senderId: "human", receiverId: "agent", createdAt: "2010-01-01T23:00:00Z", messageType: "text", isFromCurrentUser: true)
        fetcher.messageReads[0].subject.send(MessagesListResponse(success: true, data: MessagesListData(items: [value], pagination: ChatPagination(page: 1, perPage: 20, total: 1, pages: 1, hasNext: false, hasPrev: false))))
        await drainDelivery()
        XCTAssertEqual(manager.displayMessages.first?.timestamp, "2010-01-01")
        NSTimeZone.default = try XCTUnwrap(TimeZone(secondsFromGMT: 7200))
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await drainDelivery()
        XCTAssertEqual(manager.displayMessages.first?.timestamp, "2010-01-02")
        XCTAssertEqual(fetcher.messageReads.count, 1, "A display condition change must not refetch messages")
        manager.stopConversationEvents()
    }

    private func detail(_ id: String) -> ChatDetailResponse {
        ChatDetailResponse(success: true, data: ChatDetailConversation(id: id, partner: ChatPartner(id: "agent", username: nil, avatarUrl: nil), createdAt: "2026-11-20T00:00:00Z", lastMessageTime: nil))
    }

    private func ready(id: String) -> ChatConversationEvent {
        ChatConversationEvent(name: "agent.response_ready", id: id, data: Data(#"{"status":"succeeded","source_message_id":"source"}"#.utf8))
    }

    private func message(_ id: String) -> APIChatMessage {
        APIChatMessage(id: id, content: "hello", senderId: "human", receiverId: "agent", createdAt: "2026-11-20T00:00:00Z", messageType: "text", isFromCurrentUser: true)
    }

    private func drainDelivery() async {
        // The publishers deliver through the main queue. A FIFO barrier observes
        // callbacks already queued by the controlled transport, without sleeps.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class ControlledChatFetcher: ChatDetailFetching {
    struct MessageRead {
        let conversationID: String
        let page: Int
        let perPage: Int
        let subject = PassthroughSubject<MessagesListResponse, NetworkError>()
    }
    struct Stream {
        let conversationID: String
        let cursor: String?
        let subject = PassthroughSubject<ChatConversationEvent, NetworkError>()
    }
    var messageReads: [MessageRead] = []
    var details: [PassthroughSubject<ChatDetailResponse, NetworkError>] = []
    var streams: [Stream] = []
    var references: [PassthroughSubject<NoteCard, NetworkError>] = []
    var sends: [PassthroughSubject<SendMessageResponse, NetworkError>] = []
    var retries: [PassthroughSubject<AgentReplyRetryResponse, NetworkError>] = []
    var onStream: (() -> Void)?

    func getConversationDetail(conversationId: String) -> AnyPublisher<ChatDetailResponse, NetworkError> {
        let subject = PassthroughSubject<ChatDetailResponse, NetworkError>()
        details.append(subject)
        return subject.eraseToAnyPublisher()
    }
    func getMessages(conversationId: String, page: Int, perPage: Int) -> AnyPublisher<MessagesListResponse, NetworkError> {
        let read = MessageRead(conversationID: conversationId, page: page, perPage: perPage)
        messageReads.append(read)
        return read.subject.eraseToAnyPublisher()
    }
    func sendMessage(conversationId: String, request: SendMessageRequest) -> AnyPublisher<SendMessageResponse, NetworkError> {
        let subject = PassthroughSubject<SendMessageResponse, NetworkError>()
        sends.append(subject)
        return subject.eraseToAnyPublisher()
    }
    func retryAgentReply(conversationId: String, sourceMessageId: String) -> AnyPublisher<AgentReplyRetryResponse, NetworkError> {
        let subject = PassthroughSubject<AgentReplyRetryResponse, NetworkError>()
        retries.append(subject)
        return subject.eraseToAnyPublisher()
    }
    func streamConversationEvents(conversationId: String, lastEventID: String?) -> AnyPublisher<ChatConversationEvent, NetworkError> {
        let stream = Stream(conversationID: conversationId, cursor: lastEventID)
        streams.append(stream)
        onStream?()
        return stream.subject.eraseToAnyPublisher()
    }
    func getReferencedNote(cardId: String) -> AnyPublisher<NoteCard, NetworkError> {
        let subject = PassthroughSubject<NoteCard, NetworkError>()
        references.append(subject)
        return subject.eraseToAnyPublisher()
    }
    func finishMessages(_ index: Int, ids: [String], pages: Int = 1, reference: String? = nil) {
        let read = messageReads[index]
        let messages = ids.map { APIChatMessage(id: $0, content: $0, senderId: "agent", receiverId: "human", createdAt: "2026-11-20T00:00:00Z", messageType: "text", referencedAssetId: reference, isFromCurrentUser: false) }
        read.subject.send(MessagesListResponse(success: true, data: MessagesListData(items: messages, pagination: ChatPagination(page: read.page, perPage: read.perPage, total: pages * 20, pages: pages, hasNext: read.page < pages, hasPrev: read.page > 1))))
        read.subject.send(completion: .finished)
    }
}
