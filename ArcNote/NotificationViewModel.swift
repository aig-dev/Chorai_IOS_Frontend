import Foundation
import Combine
import SwiftUI

// MARK: 通知相关类型定义
struct NotificationItem: Codable, Identifiable {
    let id: Int
    let type: NotificationType
    let content: String
    let relatedId: Int?
    let isRead: Bool
    let createdAt: String
    let relatedUser: RelatedUser?
    
    enum CodingKeys: String, CodingKey {
        case id, type, content
        case relatedId = "related_id"
        case isRead = "is_read"
        case createdAt = "created_at"
        case relatedUser = "related_user"
    }
}

enum NotificationType: String, Codable, CaseIterable {
    case follow = "follow"
    case comment = "comment"
    case like = "like"
    case system = "system"
    case mention = "mention"
    
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
    let id: Int
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
    let unreadOnly: Bool
    let userId: Int
    
    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case unreadOnly = "unread_only"
        case userId = "user_id"
    }
}

// MARK: 通知响应模型
struct NotificationsResponse: Codable {
    let success: Bool
    let message: String
    let data: [NotificationItem]
    let total: Int
    let page: Int
    let perPage: Int
    let totalPages: Int
    
    enum CodingKeys: String, CodingKey {
        case success, message, data, total, page
        case perPage = "per_page"
        case totalPages = "total_pages"
    }
}

// MARK: 标记已读请求模型
struct MarkNotificationsReadRequest: Codable {
    let userId: Int
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

// MARK: 标记已读响应模型
struct MarkNotificationsReadResponse: Codable {
    let success: Bool
    let message: String
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
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "用户未登录"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let request = GetNotificationsRequest(
            page: 1,
            perPage: 50,
            unreadOnly: false,
            userId: userId
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
                        self?.calculateUnreadCount()
                    } else {
                        self?.errorMessage = response.message
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 标记所有通知为已读
    func markAllAsRead() {
        guard let userId = authManager.currentUser?.id else { return }
        
        let request = MarkNotificationsReadRequest(userId: userId)
        
        networkManager.markNotificationsAsRead(request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] response in
                    if response.success {
                        // 更新本地通知状态
                        if let notifications = self?.notifications {
                            self?.notifications = notifications.map { notification in
                                NotificationItem(
                                    id: notification.id,
                                    type: notification.type,
                                    content: notification.content,
                                    relatedId: notification.relatedId,
                                    isRead: true,
                                    createdAt: notification.createdAt,
                                    relatedUser: notification.relatedUser
                                )
                            }
                        }
                        self?.unreadCount = 0
                    } else {
                        self?.errorMessage = response.message
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
