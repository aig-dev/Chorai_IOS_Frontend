import SwiftUI
import Combine

// MARK: 通知详情数据模型
struct NotificationDetail: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let time: String
    let content: String
    let type: NotificationType
}

// MARK: 通知详情视图
struct NotificationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let notification: NotificationItem
    @StateObject private var viewModel = NotificationDetailViewModel()
    
    init(notification: NotificationItem) {
        self.notification = notification
    }
    
    var body: some View {
        ZStack {
            // 背景图片
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Notification")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // 占位，保持标题居中
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)
                
                // 通知详情内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 通知头部
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 12) {
                                // 图标
                                if notification.type == .system {
                                    ZStack {
                                        Circle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 48, height: 48)
                                        
                                        Image(systemName: notification.type.iconName)
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.white)
                                    }
                                } else if let relatedUser = notification.relatedUser {
                                    AsyncImage(url: URL(string: relatedUser.avatarUrl ?? "")) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image("avatar")
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    }
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                } else {
                                    Image("avatar")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 48, height: 48)
                                        .clipShape(Circle())
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    // 根据通知类型显示不同内容
                                    if notification.type == .system {
                                        // 系统通知：显示通知类型
                                        Text(notification.type.displayName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    } else {
                                        // 用户通知：显示用户名
                                        if let relatedUser = notification.relatedUser {
                                            Text(relatedUser.username)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                        } else {
                                            Text("User")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    
                                    Text(formatTime(notification.createdAt))
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // 通知内容
                        VStack(alignment: .leading, spacing: 16) {
                            
                            Text(notification.content)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white.opacity(0.9))
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // 进入页面时自动标记为已读
            viewModel.markNotificationAsRead(notification: notification)
        }
    }
    
    private func formatTime(_ timeString: String) -> String {
        var date: Date?
        
        // 首先尝试 ISO8601DateFormatter
        let iso8601Formatter = ISO8601DateFormatter()
        if let parsedDate = iso8601Formatter.date(from: timeString) {
            date = parsedDate
        } else {
            // 如果 ISO8601 失败，尝试其他格式
            let customFormatter1: DateFormatter = {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                formatter.timeZone = TimeZone(abbreviation: "UTC")
                return formatter
            }()
            
            let customFormatter2: DateFormatter = {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                formatter.timeZone = TimeZone(abbreviation: "UTC")
                return formatter
            }()
            
            let formatters: [DateFormatter] = [customFormatter1, customFormatter2]
            
            for formatter in formatters {
                if let parsedDate = formatter.date(from: timeString) {
                    date = parsedDate
                    break
                }
            }
        }
        
        guard let validDate = date else {
            return "Recently"
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        // 检查是否是今天
        if calendar.isDateInToday(validDate) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            return "Today \(timeFormatter.string(from: validDate))"
        }
        
        // 检查是否是昨天
        if calendar.isDateInYesterday(validDate) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            return "Yesterday \(timeFormatter.string(from: validDate))"
        }
        
        // 检查是否是本周
        if calendar.isDate(validDate, equalTo: now, toGranularity: .weekOfYear) {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            return "\(dayFormatter.string(from: validDate)) \(timeFormatter.string(from: validDate))"
        }
        
        // 计算相对时间
        let components = calendar.dateComponents([.day, .hour, .minute], from: validDate, to: now)
        
        if let days = components.day, days > 0 {
            if days < 7 {
                return "\(days) days ago"
            } else {
                return "\(days / 7) weeks ago"
            }
        } else if let hours = components.hour, hours > 0 {
            return "\(hours) hours ago"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes) minutes ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: 通知详情视图模型
class NotificationDetailViewModel: ObservableObject {
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    func markNotificationAsRead(notification: NotificationItem) {
        guard let userId = authManager.currentUser?.id else {
            return
        }
        
        // 如果通知已经是已读状态
        if notification.isRead {
            return
        }
        
        print("标记通知为已读: \(notification.id)")
        
        networkManager.markNotificationAsRead(notificationId: notification.id, userId: userId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("标记通知为已读失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    if response.success {
                        print("通知已标记为已读")
                    } else {
                        print("标记通知为已读失败: \(response.message)")
                    }
                }
            )
            .store(in: &cancellables)
    }
}

#Preview {
    NotificationDetailView(
        notification: NotificationItem(
            id: 1,
            type: .system,
            content: "We are excited to notify the magics updated features that will enhance your note-taking experience. The new collaboration feature allows you to work together with your team members in real-time, making it easier than ever to share ideas and collaborate on projects. We hope you enjoy these new features and find them helpful in your daily workflow.",
            relatedId: nil,
            isRead: false,
            createdAt: "2025-01-23T21:25:43",
            relatedUser: nil
        )
    )
} 
