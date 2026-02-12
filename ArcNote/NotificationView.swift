import SwiftUI
import Combine

struct NotificationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = NotificationViewModel()
    @State private var showFilterTags = false
    @State private var selectedFilter = "All"
    @State private var hasAppeared = false
    
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
                    
                    ZStack {

                        HStack(spacing: 4) {
                            Text("Notification")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Image(systemName: showFilterTags ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .animation(.easeInOut(duration: 0.3), value: showFilterTags)
                        }
                    }
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showFilterTags.toggle()
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.markAllAsRead()
                    }) {
                        Image("check")
                            .resizable()
                            .frame(width: 30, height: 30)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)
                
                // 筛选标签
                if showFilterTags {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            NotificationFilterTag(title: "All", isSelected: selectedFilter == "All") {
                                selectedFilter = "All"
                            }
                            .frame(width: 95)
                            NotificationFilterTag(title: "Unread", isSelected: selectedFilter == "Unread") {
                                selectedFilter = "Unread"
                            }
                            .frame(width: 95)
                            NotificationFilterTag(title: "mention", isSelected: selectedFilter == "mention") {
                                selectedFilter = "mention"
                            }
                            .frame(width: 95)
                            NotificationFilterTag(title: "system", isSelected: selectedFilter == "system") {
                                selectedFilter = "system"
                            }
                            .frame(width: 95)
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 10)
                }
                
                // 通知列表
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Loading...")
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 10)
                        Spacer()
                    }
                } else if let errorMessage = viewModel.errorMessage {
                    VStack {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                        Text("Loading Failed")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.top, 10)
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 5)
                        Button("Retry") {
                            viewModel.loadNotifications()
                        }
                        .foregroundColor(.white)
                        .padding(.top, 20)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            let groupedNotifications = viewModel.groupedNotifications(by: selectedFilter)
                            
                            ForEach(Array(groupedNotifications.keys.sorted(by: { key1, key2 in
                                let order = ["Today", "Yesterday", "This Week", "Earlier"]
                                let index1 = order.firstIndex(of: key1) ?? 999
                                let index2 = order.firstIndex(of: key2) ?? 999
                                return index1 < index2
                            })), id: \.self) { groupKey in
                                VStack(alignment: .leading, spacing: 16) {
                                    Text(groupKey)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                    
                                    VStack(spacing: 0) {
                                        if let notifications = groupedNotifications[groupKey] {
                                            ForEach(Array(notifications.enumerated()), id: \.element.id) { index, notification in
                                                NavigationLink(destination: NotificationDetailView(notification: notification)) {
                                                    NotificationItemView(notification: notification)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                                
                                                if index < notifications.count - 1 {
                                                    Divider()
                                                        .background(Color.white.opacity(0.1))
                                                        .padding(.leading, 60)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 15)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white.opacity(0.1))
                                            .overlay(cardTopLeftHighlight)
                                            .overlay(cardBottomRightHighlight)
                                            .overlay(cardTopEdgeHighlight)
                                            .overlay(cardBottomEdgeHighlight)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.bottom, 100)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // 首次出现时，ViewModel 的 init() 已经加载了数据
            // 从详情页返回时，刷新数据以更新通知状态
            if hasAppeared && !viewModel.isLoading {
                viewModel.loadNotifications()
            } else {
                hasAppeared = true
            }
        }
    }
    
    // MARK: 卡片高光效果
    private var cardTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var cardBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var cardTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var cardBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
}

// MARK: 通知项视图
struct NotificationItemView: View {
    let notification: NotificationItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 未读圆点
            if !notification.isRead {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
            } else {
                Spacer()
                    .frame(width: 6, height: 6)
            }
            
            // 图标或头像
            if notification.type == .system {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: notification.type.iconName)
                        .font(.system(size: 18, weight: .medium))
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
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Image("avatar")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            }
            
            // 内容
            VStack(alignment: .leading, spacing: 4) {
                // 根据通知类型显示不同的内容格式
                if notification.type == .system {
                    // 系统通知：直接显示内容
                    Text(notification.content)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white)
                        .lineLimit(3)
                } else {
                    // 用户通知：根据type显示动作
                    let (userName, action) = getNotificationDisplayInfo(notification)
                    HStack(spacing: 0) {
                        (Text(userName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        +
                        Text(" \(action)")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(.white.opacity(0.8))
                        )
                    }
                    .lineLimit(2)
                }
                
                Text(formatTime(notification.createdAt))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }
    
    // 根据通知类型获取显示信息
    private func getNotificationDisplayInfo(_ notification: NotificationItem) -> (String, String) {
        // 获取用户名
        let userName: String
        if let relatedUser = notification.relatedUser {
            userName = relatedUser.username
        } else {
            // 从content中提取用户名（作为备用方案）
            userName = "User"
        }
        
        // 根据type获取动作文本
        let action: String
        switch notification.type {
        case .follow:
            action = "Followed you"
        case .like:
            action = "Liked your card"
        case .comment:
            action = "Commented on your card"
        case .mention:
            action = "Mentioned you"
        case .system:
            action = "" // 系统通知不显示动作
        }
        
        return (userName, action)
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
            print("无法解析时间: \(timeString)")
            // 如果无法解析，尝试简单的相对时间显示
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

// 用户交互通知项
struct NotificationItemViewOld: View {
    let avatar: String
    let name: String
    let action: String
    let highlight: String?
    let time: String
    let hasDot: Bool
    
    init(avatar: String, name: String, action: String, highlight: String? = nil, time: String, hasDot: Bool = false) {
        self.avatar = avatar
        self.name = name
        self.action = action
        self.highlight = highlight
        self.time = time
        self.hasDot = hasDot
    }
    
    private var combinedText: Text {
        let nameText = Text(name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
        
        let actionText = Text(action)
            .font(.system(size: 16, weight: .regular))
            .foregroundColor(.white.opacity(0.8))
        
        let highlightText = Text(highlight ?? "")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
        
        let spaceText = Text(" ")
        
        return nameText + spaceText + actionText + spaceText + highlightText
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 紫色圆点
            if hasDot {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6) // 向下偏移一点，与头像顶部对齐
            } else {
                Spacer()
                    .frame(width: 6, height: 6)
            }
            
            // 头像
            Image(avatar)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            
            // 内容
            VStack(alignment: .leading, spacing: 4) {
                combinedText
                    .lineLimit(nil)
                
                Text(time)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
    }
}

// 系统通知项
struct SystemNotificationItem: View {
    let title: String
    let description: String
    let time: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 紫色圆点
            Circle()
                .fill(Color.purple)
                .frame(width: 6, height: 6)
                .padding(.top, 6) // 向下偏移一点，与系统图标顶部对齐
            
            // 系统图标
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
            }
            
            // 内容
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)
                
                Text(time)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
//        .background(
//            RoundedRectangle(cornerRadius: 12)
//                .fill(Color.white.opacity(0.1))
//        )
//        .padding(.horizontal, 20)
    }
}

#Preview {
    NotificationView()
}

// MARK: 通知筛选标签组件
struct NotificationFilterTag: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(tagBackground)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
    
    private var tagBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
            .overlay(tagTopLeftHighlight)
            .overlay(tagBottomRightHighlight)
            .overlay(tagTopEdgeHighlight)
            .overlay(tagBottomEdgeHighlight)
    }
    
    private var tagTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var tagBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 20
                        )
                    )
            )
    }
    
    private var tagTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var tagBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 20)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
}
