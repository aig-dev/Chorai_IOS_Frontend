import Foundation
import UIKit
import Combine
import CoreFlow

@MainActor
protocol ChatConversationFetching {
    func getConversations() -> AnyPublisher<ConversationsResponse, NetworkError>
}

@MainActor
protocol ChatDetailFetching {
    func getConversationDetail(
        conversationId: String
    ) -> AnyPublisher<ChatDetailResponse, NetworkError>
    func getMessages(
        conversationId: String,
        page: Int,
        perPage: Int
    ) -> AnyPublisher<MessagesListResponse, NetworkError>
    func sendMessage(
        conversationId: String,
        request: SendMessageRequest
    ) -> AnyPublisher<SendMessageResponse, NetworkError>
    func retryAgentReply(
        conversationId: String,
        sourceMessageId: String
    ) -> AnyPublisher<AgentReplyRetryResponse, NetworkError>
    func streamConversationEvents(
        conversationId: String,
        lastEventID: String?
    ) -> AnyPublisher<ChatConversationEvent, NetworkError>
    func getReferencedNote(
        cardId: String
    ) -> AnyPublisher<NoteCard, NetworkError>
}

extension NetworkManager: ChatConversationFetching, ChatDetailFetching {
    func getReferencedNote(
        cardId: String
    ) -> AnyPublisher<NoteCard, NetworkError> {
        CardDetailReader.shared.referencedNote(cardID: cardId)
    }
}

@MainActor
final class ChatHistoryVisibilityDependency: ObservableObject {
    let visibility: ChatHistoryVisibility
    @Published private(set) var revision = 0

    init(visibility: ChatHistoryVisibility = ChatHistoryVisibility()) {
        self.visibility = visibility
    }

    func clear(actorID: String, at date: Date) {
        visibility.clear(actorID: actorID, at: date)
        revision &+= 1
    }

    func isVisible(timestampString: String?, actorID: String) -> Bool {
        visibility.isVisible(timestampString: timestampString, actorID: actorID)
    }
}

// MARK: 对话伙伴模型
struct ChatPartner: Codable {
    let id: String
    let username: String?
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "actor_id"
        case username
        case avatarUrl = "avatar_url"
    }

    init(id: String, username: String?, avatarUrl: String?) {
        self.id = id
        self.username = username
        self.avatarUrl = avatarUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
    }
}

// MARK: 最后消息模型
struct LastMessage: Codable {
    let content: String
    let createdAt: String
    let senderId: String
    
    enum CodingKeys: String, CodingKey {
        case content
        case createdAt = "created_at"
        case senderId = "sender_actor_id"
    }
}

// MARK: 对话模型
struct Conversation: Codable, Identifiable {
    let id: String
    let partner: ChatPartner
    let lastMessage: LastMessage?
    let unreadCount: Int
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id = "conversation_id"
        case partner = "participant"
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case createdAt = "created_at"
    }
}

// MARK: 分页信息模型
struct ChatPagination: Codable {
    let page: Int
    let perPage: Int
    let total: Int
    let pages: Int
    let hasNext: Bool
    let hasPrev: Bool
    
    enum CodingKeys: String, CodingKey {
        case page, total, pages
        case perPage = "per_page"
        case hasNext = "has_next"
        case hasPrev = "has_prev"
    }
}

// MARK: 对话列表响应模型
struct ConversationsResponse: Codable {
    let success: Bool
    let data: ConversationsData

    var conversations: [Conversation] { data.items }
    var pagination: ChatPagination { data.pagination }
}

struct ConversationsData: Codable {
    let items: [Conversation]
    let pagination: ChatPagination
}

// MARK: 聊天详情响应模型
struct ChatDetailResponse: Codable {
    let success: Bool
    let data: ChatDetailConversation

    var conversation: ChatDetailConversation { data }
}

struct ChatDetailConversation: Codable {
    let id: String
    let partner: ChatPartner
    let createdAt: String
    let lastMessageTime: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "conversation_id"
        case partner = "participant"
        case createdAt = "created_at"
        case lastMessageTime = "last_message_at"
    }
}

// MARK: 消息列表响应模型
struct MessagesListResponse: Codable {
    let success: Bool
    let data: MessagesListData

    var messages: [APIChatMessage] { data.items }
    var pagination: ChatPagination { data.pagination }
}

struct MessagesListData: Codable {
    let items: [APIChatMessage]
    let pagination: ChatPagination
}

// MARK: 发送消息请求模型
struct SendMessageRequest: Codable {
    let content: String
    let attachedCardId: String?
    let idempotencyKey: UUID
    
    enum CodingKeys: String, CodingKey {
        case content
        case attachedCardId = "referenced_asset_id"
        case messageType = "message_type"
    }
    
    init(content: String, attachedCardId: String? = nil, idempotencyKey: UUID = UUID()) {
        self.content = content
        self.attachedCardId = attachedCardId
        self.idempotencyKey = idempotencyKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(String.self, forKey: .content)
        attachedCardId = try container.decodeIfPresent(String.self, forKey: .attachedCardId)
        idempotencyKey = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(content, forKey: .content)
        try container.encode("text", forKey: .messageType)
        if let attachedCardId {
            try container.encode(attachedCardId, forKey: .attachedCardId)
        }
    }
}

// MARK: 发送消息响应模型
struct SendMessageResponse: Codable {
    let success: Bool
    let data: SendMessageData

    var message: APIChatMessage { data.message }
}

struct SendMessageData: Codable {
    let message: APIChatMessage
    let eventId: UInt64?

    enum CodingKeys: String, CodingKey {
        case message
        case eventId = "event_id"
    }

    init(message: APIChatMessage, eventId: UInt64? = nil) {
        self.message = message
        self.eventId = eventId
    }
}

struct AgentReplyRetryResponse: Codable {
    let success: Bool
    let data: AgentReplyRetryData
}

struct AgentReplyRetryData: Codable {
    let status: String
    let sourceMessageId: String

    enum CodingKeys: String, CodingKey {
        case status
        case sourceMessageId = "source_message_id"
    }
}

// MARK: 聊天消息模型
struct APIChatMessage: Codable, Identifiable {
    let id: String
    let content: String
    let senderId: String
    let receiverId: String
    let createdAt: String
    let messageType: String
    var referencedAssetId: String?
    var isFromCurrentUser: Bool
    var attachedCards: [NoteCard]
    let conversationID: String?
    let idempotencyKey: String?
    let sourceType: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "message_id"
        case content
        case senderId = "sender_actor_id"
        case receiverId = "receiver_actor_id"
        case createdAt = "created_at"
        case messageType = "message_type"
        case referencedAssetId = "referenced_asset_id"
        case conversationID = "conversation_id"
        case idempotencyKey = "idempotency_key"
        case sourceType = "source_type"
    }
    
    // 普通初始化方法
    init(id: String, content: String, senderId: String, receiverId: String, createdAt: String, messageType: String, referencedAssetId: String? = nil, isFromCurrentUser: Bool, attachedCards: [NoteCard] = [], conversationID: String? = nil, idempotencyKey: String? = nil, sourceType: String? = nil) {
        self.id = id
        self.content = content
        self.senderId = senderId
        self.receiverId = receiverId
        self.createdAt = createdAt
        self.messageType = messageType
        self.referencedAssetId = referencedAssetId
        self.isFromCurrentUser = isFromCurrentUser
        self.attachedCards = attachedCards
        self.conversationID = conversationID
        self.idempotencyKey = idempotencyKey
        self.sourceType = sourceType
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        senderId = try container.decode(String.self, forKey: .senderId)
        receiverId = try container.decode(String.self, forKey: .receiverId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        messageType = try container.decode(String.self, forKey: .messageType)
        referencedAssetId = try container.decodeIfPresent(String.self, forKey: .referencedAssetId)
        conversationID = try container.decodeIfPresent(String.self, forKey: .conversationID)
        idempotencyKey = try container.decodeIfPresent(String.self, forKey: .idempotencyKey)
        sourceType = try container.decodeIfPresent(String.self, forKey: .sourceType)
        
        // 这里需要根据当前用户ID来判断，暂时设为false，在ChatDetailManager中处理
        isFromCurrentUser = false
        attachedCards = []
    }
}

// MARK: 聊天详情管理器
@MainActor
class ChatDetailManager: ObservableObject {
    @Published var conversation: ChatDetailConversation? {
        didSet { refreshMessagePresentation() }
    }
    @Published private(set) var displayMessages: [ChatMessage] = []
    @Published private(set) var messages: [APIChatMessage] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published private(set) var agentDeliveryState: ChatAgentDeliveryState = .idle
    @Published var composerText = ""
    @Published private(set) var composerAttachments: [NoteCard] = []
    @Published private(set) var pendingSend: ChatSendAttempt?
    @Published private(set) var isSending = false
    @Published private(set) var sendError: String?

    var composerIsEditable: Bool {
        !sessionRetired && !isSending && (pendingSend == nil || pendingSend?.state == .rejected)
    }

    private let sendPersistence: any ChatSendAttemptPersisting
    private var sendRequestID: UUID?
    
    private let fetcher: any ChatDetailFetching
    private let humanActorID: String
    private let currentUserAvatarURL: String?
    private let participantAvatarURL: String?
    private var canonicalMessages: [APIChatMessage] = []
    private var visibleMessageDates: [Date?] = []
    private var timeChangeCancellable: AnyCancellable?
    private let messageTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private let messageDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private weak var visibilityDependency: ChatHistoryVisibilityDependency?
    private var visibilityCancellable: AnyCancellable?
    private var avatarUpdateCancellable: AnyCancellable?
    private var eventCancellable: AnyCancellable?
    private var eventConnectionID: UUID?
    private var sessionCancellable: AnyCancellable?
    private var sessionRetired = false
    private var thinkingSourceIDs: Set<String> = []
    private var recoverySourceIDs: [String] = []
    private var unscopedDeliveryState: ChatAgentDeliveryState = .idle
    private var agentReplyRecoveryCancellable: AnyCancellable?
    private var agentReplyRecoveryRequestID: UUID?
    private var agentReplyRecoverySourceID: String?
    private var eventReconnectTask: Task<Void, Never>?
    private var eventConversationID: String?
    private var eventCursor = ChatConversationEventCursor()
    private var conversationEpoch = UUID()
    private var detailRequestID: UUID?
    private var detailCancellable: AnyCancellable?
    private var messageRequestID: UUID?
    private var messageCancellable: AnyCancellable?
    private var refreshPending = false
    private var hydrationRequestID: UUID?
    private var hydrationCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    // 从AuthManager获取当前用户ID
    private var currentUserId: String? {
        humanActorID.isEmpty ? nil : humanActorID
    }

    init(
        humanActorID: String = AuthManager.shared.currentUser?.id ?? "",
        currentUserAvatarURL: String? = AuthManager.shared.userAvatar,
        participantAvatarURL: String? = nil,
        fetcher: any ChatDetailFetching = NetworkManager.shared,
        sendPersistence: (any ChatSendAttemptPersisting)? = nil
    ) {
        self.humanActorID = humanActorID
        self.currentUserAvatarURL = currentUserAvatarURL
        self.participantAvatarURL = participantAvatarURL
        self.fetcher = fetcher
        var sendPrefix = "chorai.chat-send." + APIConfiguration.baseURL
        #if DEBUG
        if let scope = ProcessInfo.processInfo.environment["CHORAI_UI_TEST_CHAT_SEND_SCOPE"] {
            sendPrefix += "." + scope
        }
        #endif
        self.sendPersistence = sendPersistence ?? UserDefaultsChatSendAttemptStore(keyPrefix: sendPrefix)
        timeChangeCancellable = Publishers.MergeMany([
            UIApplication.significantTimeChangeNotification,
            NSLocale.currentLocaleDidChangeNotification,
            .NSSystemTimeZoneDidChange
        ].map { NotificationCenter.default.publisher(for: $0) })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMessagePresentation() }
        // AuthManager publishes this notification synchronously on MainActor.
        // Retire before any queued response can reveal the prior account's data.
        sessionCancellable = NotificationCenter.default.publisher(for: .cardReadSessionDidChange)
            .sink { [weak self] _ in
                self?.sessionRetired = true
                self?.stopConversationEvents()
            }
        avatarUpdateCancellable = NotificationCenter.default.publisher(
            for: ChoraAvatarUpdate.notification
        )
        .compactMap(ChoraAvatarUpdate.init(notification:))
        .receive(on: DispatchQueue.main)
        .sink { [weak self] update in
            self?.applyAvatarUpdate(update)
        }
    }

    func bindVisibility(_ dependency: ChatHistoryVisibilityDependency) {
        guard visibilityDependency !== dependency else { return }
        visibilityDependency = dependency
        visibilityCancellable = dependency.$revision
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publishVisibleMessages() }
    }
    
    func loadConversationDetail(conversationId: String) {
        guard !sessionRetired else { return }
        startConversationEvents(conversationId: conversationId)
        detailCancellable?.cancel()
        let epoch = conversationEpoch
        let requestID = UUID()
        detailRequestID = requestID
        error = nil
        loadMessages(conversationId: conversationId)
        detailCancellable = fetcher.getConversationDetail(conversationId: conversationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self, self.conversationEpoch == epoch,
                          self.detailRequestID == requestID else { return }
                    self.detailRequestID = nil
                    self.detailCancellable = nil
                    self.updateLoadingState()
                    if case .failure(let error) = completion {
                        self.error = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self, self.conversationEpoch == epoch,
                          self.detailRequestID == requestID else { return }
                    self.conversation = response.conversation
                }
            )
    }

    func startConversationEvents(conversationId: String) {
        guard !sessionRetired else { return }
        guard eventConversationID != conversationId else {
            if eventCancellable == nil {
                connectConversationEvents(conversationId: conversationId)
            }
            return
        }

        stopConversationEvents()
        eventConversationID = conversationId
        restorePendingSend(conversationID: conversationId)
        connectConversationEvents(conversationId: conversationId)
    }

    func stopConversationEvents() {
        // Invalidate identities before canceling: cancellation may synchronously
        // call a transport, and an already enqueued callback may still arrive.
        conversationEpoch = UUID()
        sendRequestID = nil
        isSending = false
        pendingSend = nil
        composerText = ""
        composerAttachments = []
        sendError = nil
        eventConnectionID = nil
        detailRequestID = nil
        messageRequestID = nil
        hydrationRequestID = nil
        refreshPending = false
        detailCancellable?.cancel()
        detailCancellable = nil
        messageCancellable?.cancel()
        messageCancellable = nil
        hydrationCancellable?.cancel()
        hydrationCancellable = nil
        cancellables.removeAll()
        canonicalMessages = []
        visibleMessageDates = []
        messages = []
        displayMessages = []
        conversation = nil
        error = nil
        updateLoadingState()
        eventConversationID = nil
        eventCursor = ChatConversationEventCursor()
        eventReconnectTask?.cancel()
        eventReconnectTask = nil
        eventCancellable?.cancel()
        eventCancellable = nil
        agentReplyRecoveryCancellable?.cancel()
        agentReplyRecoveryCancellable = nil
        agentReplyRecoveryRequestID = nil
        agentReplyRecoverySourceID = nil
        thinkingSourceIDs.removeAll()
        recoverySourceIDs.removeAll()
        unscopedDeliveryState = .idle
        agentDeliveryState = .idle
    }
    
    func loadMessages(conversationId: String) {
        guard !sessionRetired else { return }
        startConversationEvents(conversationId: conversationId)
        if messageRequestID != nil {
            refreshPending = true
            return
        }

        let epoch = conversationEpoch
        let requestID = UUID()
        messageRequestID = requestID
        refreshPending = false
        hydrationRequestID = nil
        hydrationCancellable?.cancel()
        hydrationCancellable = nil
        error = nil
        updateLoadingState()

        messageCancellable = fetcher.getMessages(
            conversationId: conversationId,
            page: 1,
            perPage: 20
        )
            .flatMap { [fetcher] firstPage -> AnyPublisher<MessagesListResponse, NetworkError> in
                let latestPage = max(1, firstPage.pagination.pages)
                guard latestPage > 1 else {
                    return Just(firstPage)
                        .setFailureType(to: NetworkError.self)
                        .eraseToAnyPublisher()
                }
                return fetcher.getMessages(
                    conversationId: conversationId,
                    page: latestPage,
                    perPage: firstPage.pagination.perPage
                )
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    guard let self, self.conversationEpoch == epoch,
                          self.messageRequestID == requestID else { return }
                    self.messageRequestID = nil
                    self.messageCancellable = nil
                    if self.refreshPending {
                        self.loadMessages(conversationId: conversationId)
                    } else {
                        self.updateLoadingState()
                        if case .failure(let error) = completion {
                            self.error = error.localizedDescription
                        }
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self, self.conversationEpoch == epoch,
                          self.messageRequestID == requestID,
                          !self.refreshPending else { return }
                    self.canonicalMessages = response.messages
                    self.publishVisibleMessages()
                    self.hydrateReferencedNotes()
                }
            )
    }

    private func updateLoadingState() {
        isLoading = detailRequestID != nil || messageRequestID != nil
    }

    func updateMessageOwnership() {
        guard let userId = currentUserId else {
            print("无法获取当前用户ID")
            return
        }
        canonicalMessages = canonicalMessages.map { message in
            var updatedMessage = message
            updatedMessage.isFromCurrentUser = (message.senderId == userId)
            return updatedMessage
        }
        publishVisibleMessages()
    }
    
    func updateComposerAttachments(_ notes: [NoteCard]) {
        guard eventConversationID != nil, composerIsEditable else { return }
        composerAttachments = notes
    }

    func removeComposerAttachment(_ note: NoteCard) {
        guard composerIsEditable else { return }
        composerAttachments.removeAll { $0.id == note.id }
    }

    private func restorePendingSend(conversationID: String) {
        do {
            pendingSend = try sendPersistence.load(actorID: humanActorID, conversationID: conversationID)
            guard let attempt = pendingSend else { return }
            composerText = attempt.content
            if let reference = attempt.referencedAssetID {
                // No private preview is persisted. Hydration still needs current authorization.
                composerAttachments = [NoteCard(id: reference, title: "Attached note", description: "Attached note", isPublic: false, username: "", avatarUrl: nil)]
                let epoch = conversationEpoch
                fetcher.getReferencedNote(cardId: reference)
                    .receive(on: DispatchQueue.main)
                    .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] note in
                        guard let self, self.conversationEpoch == epoch,
                              self.pendingSend?.requestID == attempt.requestID,
                              self.composerAttachments.map(\.id) == [reference] else { return }
                        self.composerAttachments = [note]
                    }).store(in: &cancellables)
            }
            sendError = attempt.state == .rejected
                ? "Your message wasn't sent. Your draft is saved."
                : "Your message hasn't been confirmed. Retry to recover it."
        } catch {
            sendError = "Couldn't restore the saved message. Reopen this conversation to try again."
        }
    }

    func retryPendingSend(conversationId: String) {
        guard let attempt = pendingSend, attempt.state != .rejected else { return }
        sendMessage(conversationId: conversationId, content: attempt.content, attachedNotes: composerAttachments)
    }

    func sendMessage(conversationId: String, content: String, attachedNotes: [NoteCard]) {
        guard !sessionRetired, eventConversationID == conversationId, !isSending else { return }
        guard attachedNotes.count <= 1 else {
            sendError = "Attach one note per message. Your draft is unchanged."
            return
        }
        let attempt: ChatSendAttempt
        do {
            var saved = try sendPersistence.load(actorID: humanActorID, conversationID: conversationId)
            if let retained = pendingSend, retained.state != .rejected {
                guard retained.conversationID == conversationId,
                      retained.content == content,
                      retained.referencedAssetID == attachedNotes.first?.id else {
                    sendError = "Recover your earlier message before sending another."
                    return
                }
                if saved == nil {
                    // Another view may have acknowledged and removed this record.
                    // Reconstruct the original identity so a late failure can only
                    // replay that send, never create a second message.
                    let restored = ChatSendAttempt(actorID: retained.actorID,
                        conversationID: retained.conversationID, requestID: retained.requestID,
                        content: retained.content, referencedAssetID: retained.referencedAssetID)
                    try sendPersistence.save(restored, replacing: nil)
                    saved = restored
                }
                guard saved?.isSameSend(as: retained) == true else {
                    sendError = "This conversation has a newer pending message. Reopen it to recover that message."
                    return
                }
            }
            if let saved, saved.state != .rejected {
                guard saved.content == content, saved.referencedAssetID == attachedNotes.first?.id else {
                    sendError = "Recover your earlier message before sending another."
                    return
                }
                // Every retry marks uncertainty before dispatch. A concurrent first
                // response can no longer classify the whole send as rejected.
                attempt = saved.uncertain()
                try sendPersistence.save(attempt, replacing: saved)
            } else {
                attempt = ChatSendAttempt(actorID: humanActorID, conversationID: conversationId,
                    content: content, referencedAssetID: attachedNotes.first?.id)
                try sendPersistence.save(attempt, replacing: saved)
            }
        } catch {
            sendError = "Couldn't save this message for recovery. Your draft is unchanged."
            return
        }
        pendingSend = attempt
        composerText = attempt.content
        if attempt.referencedAssetID == nil { composerAttachments = [] }
        else if composerAttachments.first?.id != attempt.referencedAssetID { composerAttachments = attachedNotes }
        sendError = nil
        isSending = true
        let epoch = conversationEpoch
        let requestID = UUID()
        sendRequestID = requestID
        let request = SendMessageRequest(content: attempt.content, attachedCardId: attempt.referencedAssetID, idempotencyKey: attempt.requestID)
        fetcher.sendMessage(conversationId: conversationId, request: request)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                guard let self, self.conversationEpoch == epoch, self.sendRequestID == requestID else { return }
                let failure: NetworkError
                if case .failure(let error) = completion { failure = error }
                else { failure = .noData }
                self.finishUnacknowledgedSend(attempt, failure: failure)
            }, receiveValue: { [weak self] response in
                guard let self, self.conversationEpoch == epoch, self.sendRequestID == requestID else { return }
                let message = response.message
                guard response.success, !message.id.isEmpty,
                      message.conversationID == attempt.conversationID,
                      message.senderId == attempt.actorID,
                      message.idempotencyKey == attempt.requestID.uuidString.lowercased(),
                      message.messageType.uppercased() == "TEXT", message.sourceType == "HUMAN",
                      message.content == attempt.normalizedContent,
                      message.referencedAssetId == attempt.referencedAssetID else {
                    self.finishUnacknowledgedSend(attempt, failure: .decodingError)
                    return
                }
                do { try self.sendPersistence.remove(attempt) }
                catch {
                    self.finishUnacknowledgedSend(attempt, failure: .unknown)
                    return
                }
                self.sendRequestID = nil
                self.isSending = false
                self.pendingSend = nil
                self.sendError = nil
                let visibleAttachments = self.composerAttachments
                if self.composerText == attempt.content {
                    self.composerText = ""
                    self.composerAttachments = []
                }
                if self.eventCancellable == nil { self.connectConversationEvents(conversationId: conversationId) }
                var accepted = message
                accepted.attachedCards = visibleAttachments.filter { $0.id == attempt.referencedAssetID }
                self.canonicalMessages.removeAll { $0.id == accepted.id }
                self.canonicalMessages.append(accepted)
                self.publishVisibleMessages()
                self.loadMessages(conversationId: conversationId)
            }).store(in: &cancellables)
    }

    private func finishUnacknowledgedSend(_ attempt: ChatSendAttempt, failure: NetworkError) {
        let rejected = attempt.state == .awaitingFirstReceipt
            && failure.cardReadStatus.map { [400, 401, 403, 404, 409, 413, 422].contains($0) } == true
        do {
            try sendPersistence.save(rejected ? attempt.rejected() : attempt.uncertain(), replacing: attempt)
        } catch {
            // A different view may already have retried or settled this identity.
            // Never overwrite its record with this callback's older state.
        }
        let current = try? sendPersistence.load(actorID: humanActorID, conversationID: attempt.conversationID)
        pendingSend = current?.isSameSend(as: attempt) == true ? current : attempt.uncertain()
        sendRequestID = nil
        isSending = false
        sendError = pendingSend?.state == .rejected
            ? "Your message wasn't sent. Edit your draft or try again."
            : "Your message hasn't been confirmed. Retry to recover it."
    }

    func retryAgentReply(conversationId: String, sourceMessageId: String) {
        let sourceMessageID = sourceMessageId.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !sourceMessageID.isEmpty,
              eventConversationID == conversationId else { return }

        agentReplyRecoveryCancellable?.cancel()
        let requestID = UUID()
        agentReplyRecoveryRequestID = requestID
        agentReplyRecoverySourceID = sourceMessageID
        applyDeliveryUpdate(ChatAgentDeliveryUpdate(state: .thinking, shouldRefreshMessages: false, sourceMessageIDs: [sourceMessageID]))

        agentReplyRecoveryCancellable = fetcher.retryAgentReply(
            conversationId: conversationId,
            sourceMessageId: sourceMessageID
        )
        .retry(2)
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self,
                      self.agentReplyRecoveryRequestID == requestID,
                      self.eventConversationID == conversationId else { return }
                self.agentReplyRecoveryCancellable = nil
                self.agentReplyRecoveryRequestID = nil
                self.agentReplyRecoverySourceID = nil
                if case .failure = completion {
                    self.applyDeliveryUpdate(ChatAgentDeliveryUpdate(state: .retryAvailable(sourceMessageID: sourceMessageID), shouldRefreshMessages: false))
                }
            },
            receiveValue: { [weak self] response in
                guard let self,
                      self.agentReplyRecoveryRequestID == requestID,
                      self.eventConversationID == conversationId else { return }
                let status = response.data.status.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).lowercased()
                guard response.success, response.data.sourceMessageId == sourceMessageID else {
                    self.applyDeliveryUpdate(ChatAgentDeliveryUpdate(state: .retryAvailable(sourceMessageID: sourceMessageID), shouldRefreshMessages: false))
                    return
                }
                switch status {
                case "succeeded":
                    self.applyDeliveryUpdate(ChatAgentDeliveryUpdate(state: .idle, shouldRefreshMessages: true, sourceMessageIDs: [sourceMessageID]))
                    self.loadMessages(conversationId: conversationId)
                case "accepted":
                    self.applyDeliveryUpdate(ChatAgentDeliveryUpdate(state: .thinking, shouldRefreshMessages: false, sourceMessageIDs: [sourceMessageID]))
                default:
                    self.applyDeliveryUpdate(ChatAgentDeliveryUpdate(state: .retryAvailable(sourceMessageID: sourceMessageID), shouldRefreshMessages: false))
                }
            }
        )
    }

    private func connectConversationEvents(conversationId: String) {
        guard eventConversationID == conversationId else { return }

        eventReconnectTask?.cancel()
        eventReconnectTask = nil
        let connectionID = UUID()
        eventConnectionID = connectionID
        eventCancellable?.cancel()
        eventCancellable = fetcher.streamConversationEvents(
            conversationId: conversationId,
            lastEventID: eventCursor.lastEventID
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self,
                      self.eventConversationID == conversationId,
                      self.eventConnectionID == connectionID else { return }
                self.eventConnectionID = nil
                self.eventCancellable = nil
                if case .failure(let error) = completion {
                    switch error {
                    case .unauthorized, .forbidden, .notFound:
                        self.stopConversationEvents()
                        return
                    default:
                        break
                    }
                }
                self.scheduleEventReconnect(conversationId: conversationId)
            },
            receiveValue: { [weak self] event in
                guard let self,
                      self.eventConversationID == conversationId,
                      self.eventConnectionID == connectionID else { return }
                if let eventID = event.id?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ), !eventID.isEmpty {
                    if let incoming = UInt64(eventID),
                       let previous = self.eventCursor.lastEventID.flatMap(UInt64.init),
                       incoming <= previous { return }
                    self.eventCursor.advance(to: eventID)
                }
                guard let update = ChatAgentDeliveryReducer.reduce(
                    event: event
                ) else { return }

                if update.state != .thinking,
                   let recoverySource = self.agentReplyRecoverySourceID,
                   update.sourceMessageIDs.contains(recoverySource) {
                    self.agentReplyRecoveryRequestID = nil
                    self.agentReplyRecoverySourceID = nil
                    self.agentReplyRecoveryCancellable?.cancel()
                    self.agentReplyRecoveryCancellable = nil
                }
                self.applyDeliveryUpdate(update)
                if update.shouldRefreshMessages {
                    self.loadMessages(conversationId: conversationId)
                }
            }
        )
    }

    private func applyDeliveryUpdate(_ update: ChatAgentDeliveryUpdate) {
        let sources = Set(update.sourceMessageIDs)
        if sources.isEmpty {
            unscopedDeliveryState = update.state
        } else {
            unscopedDeliveryState = .idle
            switch update.state {
            case .thinking:
                thinkingSourceIDs.formUnion(sources)
                recoverySourceIDs.removeAll { sources.contains($0) }
            case .idle:
                thinkingSourceIDs.subtract(sources)
                recoverySourceIDs.removeAll { sources.contains($0) }
            case .retryAvailable(let sourceMessageID):
                thinkingSourceIDs.subtract(sources)
                recoverySourceIDs.removeAll { sources.contains($0) || $0 == sourceMessageID }
                recoverySourceIDs.append(sourceMessageID)
            }
        }
        if !thinkingSourceIDs.isEmpty || unscopedDeliveryState == .thinking {
            agentDeliveryState = .thinking
        } else if let source = recoverySourceIDs.last {
            agentDeliveryState = .retryAvailable(sourceMessageID: source)
        } else {
            agentDeliveryState = unscopedDeliveryState
        }
    }

    private func scheduleEventReconnect(conversationId: String) {
        eventReconnectTask?.cancel()
        eventReconnectTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.connectConversationEvents(conversationId: conversationId)
        }
    }
    
    private func refreshMessagePresentation() {
        guard let userId = currentUserId else {
            displayMessages = []
            return
        }
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)
        messageTimeFormatter.timeZone = calendar.timeZone
        messageDayFormatter.timeZone = calendar.timeZone
        // Parse once when message inputs change, and use source order to break
        // timestamp ties. View updates only read the prepared values.
        displayMessages = messages.enumerated().sorted { lhs, rhs in
            let left = visibleMessageDates[lhs.offset] ?? .distantPast
            let right = visibleMessageDates[rhs.offset] ?? .distantPast
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map { index, message in
            let timestamp: String
            if let date = visibleMessageDates[index] {
                if calendar.isDate(date, inSameDayAs: now) {
                    timestamp = messageTimeFormatter.string(from: date)
                } else if let yesterday, calendar.isDate(date, inSameDayAs: yesterday) {
                    timestamp = "Yesterday \(messageTimeFormatter.string(from: date))"
                } else {
                    timestamp = messageDayFormatter.string(from: date)
                }
            } else {
                timestamp = "Unknown"
            }
            let isFromMe = message.senderId == userId
            return ChatMessage(
                id: message.id,
                content: message.content,
                isFromMe: isFromMe,
                timestamp: timestamp,
                avatarURL: isFromMe
                    ? currentUserAvatarURL
                    : (conversation?.partner.avatarUrl ?? participantAvatarURL),
                attachedNotes: message.attachedCards.isEmpty ? nil : message.attachedCards
            )
        }
    }

    private func applyAvatarUpdate(_ update: ChoraAvatarUpdate) {
        guard let conversation,
              conversation.partner.id == update.actorID else {
            return
        }
        self.conversation = ChatDetailConversation(
            id: conversation.id,
            partner: ChatPartner(
                id: conversation.partner.id,
                username: conversation.partner.username,
                avatarUrl: update.avatarURL
            ),
            createdAt: conversation.createdAt,
            lastMessageTime: conversation.lastMessageTime
        )
    }

    private func publishVisibleMessages() {
        let dated = canonicalMessages.map { (message: $0, date: ChatTimestamp.parse($0.createdAt)) }
        let visible = dated.filter {
            visibilityDependency?.visibility.isVisible(timestamp: $0.date, actorID: humanActorID) ?? true
        }
        visibleMessageDates = visible.map(\.date)
        messages = visible.map(\.message)
        refreshMessagePresentation()
    }

    private func hydrateReferencedNotes() {
        hydrationCancellable?.cancel()
        let epoch = conversationEpoch
        let requestID = UUID()
        hydrationRequestID = requestID
        let referencedIDs = Set(
            canonicalMessages.compactMap { message in
                message.attachedCards.isEmpty
                    ? message.referencedAssetId
                    : nil
            }
        )
        guard !referencedIDs.isEmpty else { return }

        let requests = referencedIDs.map { [fetcher] cardID in
            fetcher.getReferencedNote(cardId: cardID)
                .map { (cardID, Optional($0)) }
                .catch { _ in Just((cardID, nil)) }
                .eraseToAnyPublisher()
        }

        hydrationCancellable = Publishers.MergeMany(requests)
            .collect()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hydratedNotes in
                guard let self, self.conversationEpoch == epoch,
                      self.hydrationRequestID == requestID else { return }
                self.hydrationRequestID = nil
                self.hydrationCancellable = nil
                let notesByID = Dictionary(
                    uniqueKeysWithValues: hydratedNotes.compactMap { cardID, note in
                        note.map { (cardID, $0) }
                    }
                )
                guard !notesByID.isEmpty else { return }
                self.canonicalMessages = self.canonicalMessages.map { message in
                    guard
                        message.attachedCards.isEmpty,
                        let cardID = message.referencedAssetId,
                        let note = notesByID[cardID]
                    else {
                        return message
                    }
                    var hydrated = message
                    hydrated.attachedCards = [note]
                    return hydrated
                }
                self.publishVisibleMessages()
            }
    }
    
}

enum ChatTimestamp {
    static func parse(_ value: String) -> Date? {
        CardTimestamp.parse(value)
    }
}

// MARK: 对话列表管理器
@MainActor
class ChatManager: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let fetcher: any ChatConversationFetching
    private let humanActorID: String
    private var canonicalConversations: [Conversation] = []
    private weak var visibilityDependency: ChatHistoryVisibilityDependency?
    private var visibilityCancellable: AnyCancellable?
    private var avatarUpdateCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    init(
        humanActorID: String = AuthManager.shared.currentUser?.id ?? "",
        fetcher: any ChatConversationFetching = NetworkManager.shared
    ) {
        self.humanActorID = humanActorID
        self.fetcher = fetcher
        avatarUpdateCancellable = NotificationCenter.default.publisher(
            for: ChoraAvatarUpdate.notification
        )
        .compactMap(ChoraAvatarUpdate.init(notification:))
        .receive(on: DispatchQueue.main)
        .sink { [weak self] update in
            self?.applyAvatarUpdate(update)
        }
    }

    func bindVisibility(_ dependency: ChatHistoryVisibilityDependency) {
        guard visibilityDependency !== dependency else { return }
        visibilityDependency = dependency
        visibilityCancellable = dependency.$revision
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.publishVisibleConversations() }
    }
    
    func loadConversations() {
        isLoading = true
        error = nil
        
        fetcher.getConversations()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("获取对话列表失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.canonicalConversations = response.conversations
                    self?.publishVisibleConversations()
                    print("获取对话列表成功: \(response.conversations.count) 个对话")
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshConversations() {
        loadConversations()
    }

    private func publishVisibleConversations() {
        guard let visibilityDependency else {
            conversations = canonicalConversations
            return
        }
        conversations = canonicalConversations.filter {
            visibilityDependency.isVisible(
                timestampString: $0.lastMessage?.createdAt ?? $0.createdAt,
                actorID: humanActorID
            )
        }
    }

    private func applyAvatarUpdate(_ update: ChoraAvatarUpdate) {
        var didUpdate = false
        canonicalConversations = canonicalConversations.map { conversation in
            guard conversation.partner.id == update.actorID else {
                return conversation
            }
            didUpdate = true
            return Conversation(
                id: conversation.id,
                partner: ChatPartner(
                    id: conversation.partner.id,
                    username: conversation.partner.username,
                    avatarUrl: update.avatarURL
                ),
                lastMessage: conversation.lastMessage,
                unreadCount: conversation.unreadCount,
                createdAt: conversation.createdAt
            )
        }
        guard didUpdate else { return }
        publishVisibleConversations()
    }
}

// MARK: 发起会话相关模型
struct CreateConversationRequest: Codable {
    let participantId: String
    
    enum CodingKeys: String, CodingKey {
        case participantId = "participant_actor_id"
    }
}

struct CreateConversationParticipant: Codable {
    let id: String
    let username: String?
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id = "actor_id"
        case username
        case avatarUrl = "avatar_url"
    }
}

struct CreateConversationData: Codable {
    let id: String
    let createdAt: String
    let lastMessageTime: String?
    let participant: CreateConversationParticipant
    
    enum CodingKeys: String, CodingKey {
        case id = "conversation_id"
        case createdAt = "created_at"
        case lastMessageTime = "last_message_at"
        case participant
    }
}

struct CreateConversationResponse: Codable {
    let success: Bool
    let data: CreateConversationData

    var conversation: CreateConversationData { data }
}
