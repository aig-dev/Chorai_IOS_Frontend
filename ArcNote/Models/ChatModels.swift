import Foundation
import Combine

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
class ChatDetailManager: ObservableObject {
    @Published var conversation: ChatDetailConversation?
    @Published var messages: [APIChatMessage] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let networkManager = NetworkManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 从AuthManager获取当前用户ID
    private var currentUserId: String? {
        return AuthManager.shared.currentUser?.id
    }
    
    func loadConversationDetail(conversationId: String) {
        isLoading = true
        error = nil
        
        self.loadMessages(conversationId: conversationId)
        networkManager.getConversationDetail(conversationId: conversationId)
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
    
    func loadMessages(conversationId: String) {
        print("加载conversationId: \(conversationId)")
        
        isLoading = true
        error = nil
        
        networkManager.getMessages(conversationId: conversationId)
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
                    self?.messages = response.messages
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
        messages = messages.map { message in
            var updatedMessage = message
            updatedMessage.isFromCurrentUser = (message.senderId == userId)
            return updatedMessage
        }
    }
    
    func sendMessage(conversationId: String, content: String, attachedNotes: [NoteCard]) {
        let attachedCardId = attachedNotes.first?.id
        print("发送消息conversationId: \(conversationId), content: \(content), attachedCardId: \(attachedCardId ?? "")")
        
        let request = SendMessageRequest(content: content, attachedCardId: attachedCardId)
        
        networkManager.sendMessage(conversationId: conversationId, request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.error = error.localizedDescription
                        print("发送消息失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    // 将新消息添加到消息列表
                    var message = response.message
                    message.referencedAssetId = message.referencedAssetId ?? attachedCardId
                    message.attachedCards = attachedNotes
                    self?.messages.append(message)
                    print("发送消息成功: \(response.message.content)")
                }
            )
            .store(in: &cancellables)
    }
    
    func convertToChatMessages() -> [ChatMessage] {
        guard let userId = currentUserId else {
            print("无法获取当前用户ID")
            return []
        }
        print("转换消息原始消息数量: \(messages.count), 当前用户ID: \(userId)")
        let sortedMessages = messages.sorted { lhs, rhs in
            parseAPIDate(lhs.createdAt) < parseAPIDate(rhs.createdAt)
        }
        return sortedMessages.map { apiMessage in
            let isFromMe = apiMessage.senderId == userId
            print("消息: \(apiMessage.content), senderId: \(apiMessage.senderId), isFromMe: \(isFromMe)")
            return ChatMessage(
                content: apiMessage.content,
                isFromMe: isFromMe,
                timestamp: formatMessageTime(apiMessage.createdAt),
                avatar: "avatar",
                attachedNotes: apiMessage.attachedCards.isEmpty ? nil : apiMessage.attachedCards
            )
        }
    }
    
    private func parseAPIDate(_ dateString: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.date(from: dateString) ?? Date.distantPast
    }
    
    private func formatMessageTime(_ dateString: String) -> String {
        let date = parseAPIDate(dateString)
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

// MARK: 对话列表管理器
class ChatManager: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let networkManager = NetworkManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    func loadConversations() {
        isLoading = true
        error = nil
        
        networkManager.getConversations()
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
                    self?.conversations = response.conversations
                    print("获取对话列表成功: \(response.conversations.count) 个对话")
                }
            )
            .store(in: &cancellables)
    }
    
    func refreshConversations() {
        loadConversations()
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
