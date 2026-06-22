import Foundation
import Combine
import SwiftUI

// MARK: 通知相关类型定义
struct NotificationItem: Codable, Identifiable {
    let id: String
    let type: NotificationType
    let content: String
    let relatedId: String?
    let isRead: Bool
    let createdAt: String
    let relatedUser: RelatedUser?

    enum CodingKeys: String, CodingKey {
        case id = "notification_id"
        case sourceType = "source_type"
        case payloadRef = "payload_ref"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
    
    init(id: String, type: NotificationType, content: String, relatedId: String?, isRead: Bool, createdAt: String, relatedUser: RelatedUser?) {
        self.id = id
        self.type = type
        self.content = content
        self.relatedId = relatedId
        self.isRead = isRead
        self.createdAt = createdAt
        self.relatedUser = relatedUser
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let sourceType = (try? container.decode(String.self, forKey: .sourceType)) ?? "system"
        let payloadRef = try? container.decode(String.self, forKey: .payloadRef)
        type = NotificationType(sourceType: sourceType)
        content = payloadRef?.isEmpty == false ? payloadRef! : sourceType
        relatedId = payloadRef
        isRead = try container.decode(Bool.self, forKey: .isRead)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        relatedUser = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type.rawValue, forKey: .sourceType)
        try container.encodeIfPresent(relatedId, forKey: .payloadRef)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

enum NotificationType: String, Codable, CaseIterable {
    case follow = "follow"
    case comment = "comment"
    case like = "like"
    case system = "system"
    case mention = "mention"
    
    init(sourceType: String) {
        switch sourceType.lowercased() {
        case "follow":
            self = .follow
        case "comment":
            self = .comment
        case "like":
            self = .like
        case "mention":
            self = .mention
        default:
            self = .system
        }
    }

    var displayName: String {
        switch self {
        case .follow:
            return "Follow"
        case .comment:
            return "Comment"
        case .like:
            return "Like"
        case .system:
            return "System"
        case .mention:
            return "Mention"
        }
    }
    
    var iconName: String {
        switch self {
        case .follow:
            return "person.badge.plus"
        case .comment:
            return "bubble.left"
        case .like:
            return "heart"
        case .system:
            return "bell"
        case .mention:
            return "at"
        }
    }
}

struct RelatedUser: Codable {
    let id: String
    let username: String
    let avatarUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username
        case avatarUrl = "avatar_url"
    }
}

// MARK: 通知请求模型
struct GetNotificationsRequest: Codable {
    let page: Int
    let perPage: Int

    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
    }
}

// MARK: 通知响应模型
struct NotificationsResponse: Codable {
    let success: Bool
    let message: String?
    let data: [NotificationItem]
    let meta: PaginationMeta?
    let unreadCount: Int
    
    var total: Int { meta?.total ?? data.count }
    var page: Int { meta?.page ?? 1 }
    var perPage: Int { meta?.perPage ?? data.count }
    var totalPages: Int {
        guard perPage > 0 else { return 1 }
        return max(1, Int(ceil(Double(total) / Double(perPage))))
    }

    enum CodingKeys: String, CodingKey {
        case success, message, data, meta
        case unreadCount = "unread_count"
    }
}

// MARK: 通知视图模型
class NotificationViewModel: ObservableObject {
    @Published var notifications: [NotificationItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var unreadCount = 0
    
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadNotifications()
    }
    
    // MARK: 加载通知
    func loadNotifications() {
        guard authManager.currentUser != nil else {
            errorMessage = "用户未登录"
            return
        }

        isLoading = true
        errorMessage = nil

        let request = GetNotificationsRequest(
            page: 1,
            perPage: 50
        )

        networkManager.getNotifications(request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    if response.success {
                        self?.notifications = response.data
                        self?.unreadCount = response.unreadCount
                    } else {
                        self?.errorMessage = response.message ?? "加载通知失败"
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 计算未读数量
    private func calculateUnreadCount() {
        unreadCount = notifications.filter { !$0.isRead }.count
    }
    
    // MARK: 按类型筛选通知
    func filteredNotifications(by filter: String) -> [NotificationItem] {
        switch filter {
        case "Unread":
            return notifications.filter { !$0.isRead }
        case "mention":
            return notifications.filter { $0.type == .mention }
        case "system":
            return notifications.filter { $0.type == .system }
        default:
            return notifications
        }
    }
    
    // MARK: 按日期分组通知
    func groupedNotifications(by filter: String) -> [String: [NotificationItem]] {
        let filtered = filteredNotifications(by: filter)
        let calendar = Calendar.current
        let now = Date()
        
        var grouped: [String: [NotificationItem]] = [:]
        
        for notification in filtered {
            let date = ISO8601DateFormatter().date(from: notification.createdAt) ?? now
            let dayDifference = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            
            let groupKey: String
            if dayDifference == 0 {
                groupKey = "Today"
            } else if dayDifference == 1 {
                groupKey = "Yesterday"
            } else if dayDifference < 7 {
                groupKey = "This Week"
            } else {
                groupKey = "Earlier"
            }
            
            if grouped[groupKey] == nil {
                grouped[groupKey] = []
            }
            grouped[groupKey]?.append(notification)
        }
        
        // 对每个分组内的通知按时间排序（最新的在前）
        for key in grouped.keys {
            grouped[key]?.sort { notification1, notification2 in
                let date1 = ISO8601DateFormatter().date(from: notification1.createdAt) ?? Date.distantPast
                let date2 = ISO8601DateFormatter().date(from: notification2.createdAt) ?? Date.distantPast
                return date1 > date2
            }
        }
        
        return grouped
    }
}
