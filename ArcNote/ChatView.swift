import SwiftUI
import Combine

struct ChatView: View {
    @EnvironmentObject private var chatHistoryDependency:
        ChatHistoryVisibilityDependency
    @Binding var showSideMenu: Bool
    @State private var isSearchMode = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedChat: String? = nil
    @StateObject private var chatManager: ChatManager
    private let humanActorID: String
    private let detailFetcher: any ChatDetailFetching

    init(
        showSideMenu: Binding<Bool>,
        humanActorID: String = AuthManager.shared.currentUser?.id ?? "",
        conversationFetcher: any ChatConversationFetching =
            NetworkManager.shared,
        detailFetcher: any ChatDetailFetching = NetworkManager.shared
    ) {
        _showSideMenu = showSideMenu
        self.humanActorID = humanActorID
        self.detailFetcher = detailFetcher
        _chatManager = StateObject(
            wrappedValue: ChatManager(
                humanActorID: humanActorID,
                fetcher: conversationFetcher
            )
        )
    }
    
    // MARK: 计算属性
    
    private var searchInputBackground: some View {
        RoundedRectangle(cornerRadius: 30)
            .fill(.ultraThinMaterial.opacity(0.3))
            .overlay(searchInputTopLeftHighlight)
            .overlay(searchInputBottomRightHighlight)
            .overlay(searchInputTopEdgeHighlight)
            .overlay(searchInputBottomEdgeHighlight)
    }
    
    private var searchInputTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 30)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 30)
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
    
    private var searchInputBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 30)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 30)
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
    
    private var searchInputTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 30)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var searchInputBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 30)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    var body: some View {
        KeyboardStableViewport(isFocused: isSearchFocused) { _ in
            VStack(spacing: 0) {
            // 顶部导航栏
            ZStack {
                if isSearchMode {
                    // 搜索模式
                    HStack {
                        Button(action: {
                            isSearchFocused = false
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isSearchMode = false
                                searchText = ""
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        // 搜索输入框
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white.opacity(0.7))
                            
                            TextField("Please enter your search...", text: $searchText)
                                .foregroundColor(.white)
                                .textFieldStyle(PlainTextFieldStyle())
                                .focused($isSearchFocused)
                                .accessibilityIdentifier("chat.search.input")
                                .submitLabel(.search)
                                .onSubmit {
                                    isSearchFocused = false
                                }
                                .placeholder(when: searchText.isEmpty) {
                                    Text("Please enter your search...")
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            
//                            if !searchText.isEmpty {
//                                Button(action: {
//                                    searchText = ""
//                                }) {
//                                    Image(systemName: "xmark.circle.fill")
//                                        .foregroundColor(.white.opacity(0.7))
//                                }
//                            }
                        }
                        .padding(.horizontal, 25)
                        .padding(.vertical, 13)
                        .frame(maxWidth: 280)
                        .background(searchInputBackground)
                        
                        Spacer()
                    }
                } else {
                    // 正常模式
                    // 左侧按钮
                    HStack {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showSideMenu = true
                            }
                        }) {
                            Image("menu")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                        Spacer()
                    }
                    // 标题
                    Text("Message")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    // 右侧按钮
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isSearchMode = true
                            }
                            DispatchQueue.main.async {
                                isSearchFocused = true
                            }
                        }) {
                            Image("search")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                        .accessibilityIdentifier("chat.search")
                    }
                }
            }
            .adaptiveContentGutter()
            .padding(.top, 60)
            .padding(.bottom, 18)
            
            // 聊天列表
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if chatManager.isLoading && chatManager.conversations.isEmpty {
                        // 加载状态
                        VStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            Text("Loading conversations...")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.top, 10)
                            Spacer()
                        }
                        .frame(height: 200)
                    } else if chatManager.conversations.isEmpty {
                        // 空状态
                        VStack {
                            Spacer()
                            Text("No conversations yet")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.top, 16)
                            Text("Start a conversation")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.top, 5)
                            Spacer()
                        }
                        .frame(height: 200)
                        .accessibilityIdentifier("chat.empty")
                    } else {
                        // 对话列表
                        ForEach(Array(chatManager.conversations.enumerated()), id: \.element.id) { index, conversation in
                            NavigationLink(destination: ChatDetailView(
                                conversationId: conversation.id,
                                contactName: conversation.partner.username ?? conversation.partner.id,
                                contactStatus: "Online",
                                contactAvatar: conversation.partner.avatarUrl ?? "avatar",
                                humanActorID: humanActorID,
                                fetcher: detailFetcher
                            )) {
                                ChatListCell(
                                    avatar: AnyView(
                                        AsyncImage(url: resolvedAvatarURL(conversation.partner.avatarUrl)) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Image("avatar")
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                        }
                                        .frame(width: 56, height: 56)
                                        .clipShape(Circle())
                                    ),
                                    title: conversation.partner.username ?? conversation.partner.id,
                                    subtitle: conversation.lastMessage?.content ?? "No messages yet",
                                    time: formatConversationTime(conversation.lastMessage?.createdAt ?? conversation.createdAt),
                                    unreadCount: conversation.unreadCount
                                )
                            }
                            .accessibilityIdentifier("chat.conversation.\(conversation.id)")
                            
                            // 分割线（除了最后一个）
                            if index < chatManager.conversations.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.12))
                                    .padding(.leading, 92)
                            }
                        }
                        
                    }
                }
                .padding(.top, 8)
                .adaptiveContentGutter()
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                chatManager.refreshConversations()
            }
            Spacer()
        }
        }
        .accessibilityIdentifier("screen.chat.content")
        #if DEBUG
        .overlay(alignment: .topLeading) {
            Text([
                humanActorID,
                String(chatHistoryDependency.revision),
                String(chatHistoryDependency.isVisible(
                    timestampString: "2020-01-01T00:00:00Z",
                    actorID: humanActorID
                )),
                String(chatManager.conversations.count)
            ].joined(separator: "|"))
            .font(.system(size: 1))
            .foregroundColor(.clear)
            .frame(width: 1, height: 1)
            .accessibilityIdentifier("chat.visibility.contract")
        }
        #endif
        .onAppear {
            chatManager.bindVisibility(chatHistoryDependency)
            chatManager.loadConversations()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseAllPopups"))) { _ in
            print("收到关闭所有popup通知")
        }
    }
    
    // MARK: - 时间格式化
    private func formatConversationTime(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        
        guard let date = formatter.date(from: dateString) else {
            return "Unknown"
        }
        
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE"
            return dayFormatter.string(from: date)
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd"
            return dateFormatter.string(from: date)
        }
    }

    private func resolvedAvatarURL(_ rawValue: String?) -> URL? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        return URL(string: APIConfiguration.resourceURLString(rawValue))
    }
}

struct ChatListCell: View {
    let avatar: AnyView
    let title: String
    let subtitle: String
    let time: String
    let unreadCount: Int
    
    init(avatar: AnyView, title: String, subtitle: String, time: String, unreadCount: Int = 0) {
        self.avatar = avatar
        self.title = title
        self.subtitle = subtitle
        self.time = time
        self.unreadCount = unreadCount
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            avatar
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    HStack(spacing: 8) {
                        Text(time)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                        
                        // 未读消息数
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(
                                    Circle()
                                        .fill(Color.red)
                                )
                        }
                    }
                }
                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 14)
        .background(Color.clear)
    }
}

#Preview {
    ChatView(showSideMenu: .constant(false))
}
