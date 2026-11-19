import Foundation
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
    
    enum CodingKeys: String, CodingKey {
        case content
        case attachedCardId = "referenced_asset_id"
        case messageType = "message_type"
    }
    
    init(content: String, attachedCardId: String? = nil) {
        self.content = content
        self.attachedCardId = attachedCardId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decode(String.self, forKey: .content)
        attachedCardId = try container.decodeIfPresent(String.self, forKey: .attachedCardId)
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
    
    enum CodingKeys: String, CodingKey {
        case id = "message_id"
        case content
        case senderId = "sender_actor_id"
        case receiverId = "receiver_actor_id"
        case createdAt = "created_at"
        case messageType = "message_type"
        case referencedAssetId = "referenced_asset_id"
    }
    
    // 普通初始化方法
    init(id: String, content: String, senderId: String, receiverId: String, createdAt: String, messageType: String, referencedAssetId: String? = nil, isFromCurrentUser: Bool, attachedCards: [NoteCard] = []) {
        self.id = id
        self.content = content
        self.senderId = senderId
        self.receiverId = receiverId
        self.createdAt = createdAt
        self.messageType = messageType
        self.referencedAssetId = referencedAssetId
        self.isFromCurrentUser = isFromCurrentUser
        self.attachedCards = attachedCards
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
        
        // 这里需要根据当前用户ID来判断，暂时设为false，在ChatDetailManager中处理
        isFromCurrentUser = false
        attachedCards = []
    }
}

// MARK: 聊天详情管理器
@MainActor
class ChatDetailManager: ObservableObject {
    @Published var conversation: ChatDetailConversation?
    @Published var messages: [APIChatMessage] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published private(set) var agentDeliveryState: ChatAgentDeliveryState = .idle
    
    private let fetcher: any ChatDetailFetching
    private let humanActorID: String
    private let currentUserAvatarURL: String?
    private let participantAvatarURL: String?
    private var canonicalMessages: [APIChatMessage] = []
    private weak var visibilityDependency: ChatHistoryVisibilityDependency?
    private var visibilityCancellable: AnyCancellable?
    private var avatarUpdateCancellable: AnyCancellable?
    private var eventCancellable: AnyCancellable?
    private var agentReplyRecoveryCancellable: AnyCancellable?
    private var agentReplyRecoveryRequestID: UUID?
    private var eventReconnectTask: Task<Void, Never>?
    private var eventConversationID: String?
    private var eventCursor = ChatConversationEventCursor()
    private var cancellables = Set<AnyCancellable>()
    
    // 从AuthManager获取当前用户ID
    private var currentUserId: String? {
        humanActorID.isEmpty ? nil : humanActorID
    }

    init(
        humanActorID: String = AuthManager.shared.currentUser?.id ?? "",
        currentUserAvatarURL: String? = AuthManager.shared.userAvatar,
        participantAvatarURL: String? = nil,
        fetcher: any ChatDetailFetching = NetworkManager.shared
    ) {
        self.humanActorID = humanActorID
        self.currentUserAvatarURL = currentUserAvatarURL
        self.participantAvatarURL = participantAvatarURL
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
            .sink { [weak self] _ in self?.publishVisibleMessages() }
    }
    
    func loadConversationDetail(conversationId: String) {
        startConversationEvents(conversationId: conversationId)
        isLoading = true
        error = nil
        
        self.loadMessages(conversationId: conversationId)
        fetcher.getConversationDetail(conversationId: conversationId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("获取聊天详情失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.conversation = response.conversation
                    print("获取成功: \(response.conversation.partner.username ?? response.conversation.partner.id)")
                    print("加载列表conversationId: \(response.conversation.id)")
                    
                    // 对话详情加载完成后，加载消息
                }
            )
            .store(in: &cancellables)
    }

    func startConversationEvents(conversationId: String) {
        guard eventConversationID != conversationId else {
            if eventCancellable == nil {
                connectConversationEvents(conversationId: conversationId)
            }
            return
        }

        stopConversationEvents()
        eventConversationID = conversationId
        connectConversationEvents(conversationId: conversationId)
    }

    func stopConversationEvents() {
        eventConversationID = nil
        eventCursor = ChatConversationEventCursor()
        eventReconnectTask?.cancel()
        eventReconnectTask = nil
        eventCancellable?.cancel()
        eventCancellable = nil
        agentReplyRecoveryCancellable?.cancel()
        agentReplyRecoveryCancellable = nil
        agentReplyRecoveryRequestID = nil
        agentDeliveryState = .idle
    }
    
    func loadMessages(conversationId: String) {
        print("加载conversationId: \(conversationId)")
        
        isLoading = true
        error = nil
        
        fetcher.getMessages(
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
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("获取失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    self?.canonicalMessages = response.messages
                    self?.publishVisibleMessages()
                    self?.hydrateReferencedNotes()
                    print("获取成功")
                }
            )
            .store(in: &cancellables)
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
    
    func sendMessage(conversationId: String, content: String, attachedNotes: [NoteCard]) {
        let attachedCardId = attachedNotes.first?.id
        print("发送消息conversationId: \(conversationId), contentLength: \(content.count), attachedCardId: \(attachedCardId ?? "")")
        agentDeliveryState = .idle
        
        let request = SendMessageRequest(content: content, attachedCardId: attachedCardId)
        
        fetcher.sendMessage(conversationId: conversationId, request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("发送消息失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self else { return }
                    if let eventID = response.data.eventId {
                        self.eventCursor.advance(to: eventID)
                        self.connectConversationEvents(
                            conversationId: conversationId
                        )
                    }
                    var message = response.message
                    message.referencedAssetId = message.referencedAssetId ?? attachedCardId
                    message.attachedCards = attachedNotes
                    self.canonicalMessages.removeAll { $0.id == message.id }
                    self.canonicalMessages.append(message)
                    self.publishVisibleMessages()
                    self.loadMessages(conversationId: conversationId)
                    print("发送消息成功: id=\(response.message.id)")
                }
            )
            .store(in: &cancellables)
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
        agentDeliveryState = .thinking

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
                if case .failure = completion {
                    self.agentDeliveryState = .retryAvailable(
                        sourceMessageID: sourceMessageID
                    )
                }
            },
            receiveValue: { [weak self] response in
                guard let self,
                      self.agentReplyRecoveryRequestID == requestID,
                      self.eventConversationID == conversationId else { return }
                let status = response.data.status.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).lowercased()
                guard response.success else {
                    self.agentDeliveryState = .retryAvailable(
                        sourceMessageID: sourceMessageID
                    )
                    return
                }
                switch status {
                case "succeeded":
                    self.agentDeliveryState = .idle
                    self.loadMessages(conversationId: conversationId)
                case "accepted":
                    self.agentDeliveryState = .thinking
                default:
                    self.agentDeliveryState = .retryAvailable(
                        sourceMessageID: sourceMessageID
                    )
                }
            }
        )
    }

    private func connectConversationEvents(conversationId: String) {
        guard eventConversationID == conversationId else { return }

        eventReconnectTask?.cancel()
        eventReconnectTask = nil
        eventCancellable?.cancel()
        eventCancellable = fetcher.streamConversationEvents(
            conversationId: conversationId,
            lastEventID: eventCursor.lastEventID
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self,
                      self.eventConversationID == conversationId else { return }
                self.eventCancellable = nil
                if case .failure(let error) = completion {
                    switch error {
                    case .unauthorized, .forbidden, .notFound:
                        self.agentDeliveryState = .idle
                        return
                    default:
                        break
                    }
                }
                self.scheduleEventReconnect(conversationId: conversationId)
            },
            receiveValue: { [weak self] event in
                guard let self,
                      self.eventConversationID == conversationId else { return }
                if let eventID = event.id?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ), !eventID.isEmpty {
                    self.eventCursor.advance(to: eventID)
                }
                guard let update = ChatAgentDeliveryReducer.reduce(
                    event: event
                ) else { return }

                self.agentDeliveryState = update.state
                if update.shouldRefreshMessages {
                    self.loadMessages(conversationId: conversationId)
                }
            }
        )
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
    
    func convertToChatMessages() -> [ChatMessage] {
        guard let userId = currentUserId else {
            print("无法获取当前用户ID")
            return []
        }
        print("转换消息原始消息数量: \(messages.count), 当前用户ID: \(userId)")
        let sortedMessages = messages.sorted { lhs, rhs in
            (ChatTimestamp.parse(lhs.createdAt) ?? .distantPast)
                < (ChatTimestamp.parse(rhs.createdAt) ?? .distantPast)
        }
        return sortedMessages.map { apiMessage in
            let isFromMe = apiMessage.senderId == userId
            print("消息: id=\(apiMessage.id), senderId: \(apiMessage.senderId), isFromMe: \(isFromMe)")
            return ChatMessage(
                id: apiMessage.id,
                content: apiMessage.content,
                isFromMe: isFromMe,
                timestamp: formatMessageTime(apiMessage.createdAt),
                avatarURL: isFromMe
                    ? currentUserAvatarURL
                    : (conversation?.partner.avatarUrl ?? participantAvatarURL),
                attachedNotes: apiMessage.attachedCards.isEmpty ? nil : apiMessage.attachedCards
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
        guard let visibilityDependency else {
            messages = canonicalMessages
            return
        }
        messages = canonicalMessages.filter {
            visibilityDependency.isVisible(
                timestampString: $0.createdAt,
                actorID: humanActorID
            )
        }
    }

    private func hydrateReferencedNotes() {
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

        Publishers.MergeMany(requests)
            .collect()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hydratedNotes in
                guard let self else { return }
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
            .store(in: &cancellables)
    }
    
    private func formatMessageTime(_ dateString: String) -> String {
        guard let date = ChatTimestamp.parse(dateString) else {
            return "Unknown"
        }
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            return timeString(from: date)
        }
        
        if calendar.isDateInYesterday(date) {
            return "Yesterday \(timeString(from: date))"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: date)
    }
    
    private func timeString(from date: Date) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        return timeFormatter.string(from: date)
    }
}

enum ChatTimestamp {
    static func parse(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
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
