import SwiftUI
import Combine
import CoreFlow

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPopupMenu = false
    @StateObject private var cardsManager = HomeCardsManager()
    @StateObject private var profileStore: CommunityProfileStore
    
    // 聊天相关状态
    @State private var navigateToChat = false
    @State private var conversationId: String? = nil
    @State private var isCreatingConversation = false
    @State private var cancellables = Set<AnyCancellable>()
    
    // 菜单相关状态
    @State private var popupMenuLayout: PopupMenuLayout = .grid2x2
    @State private var currentMenuCardData: UserCard? = nil
    
    // 导航状态
    @State private var navigateToDetail = false
    @State private var navigateToEdit = false
    @State private var selectedCardId: String? = nil
    @State private var showReport = false
    @State private var showActionSheet = false
    @State private var showBlockConfirmation = false
    @State private var showFollowList = false
    @State private var followListKind: FollowListKind = .followers
    
    let actorId: String

    init(
        actorId: String,
        service: any CoreCommunityProfileServing = NetworkCommunityProfileService()
    ) {
        self.actorId = actorId
        _profileStore = StateObject(
            wrappedValue: CommunityProfileStore(service: service)
        )
    }

    private var isOwnProfile: Bool {
        actorId == AuthManager.shared.currentUser?.id
    }

    private var isFollowLoading: Bool {
        if case .mutatingFollow = profileStore.phase { return true }
        return false
    }
    
    var body: some View {
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
                
                Text(profileStore.profile?.username ?? "User Profile")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                if isOwnProfile {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .foregroundColor(.clear)
                } else {
                    Button(action: {
                        showActionSheet = true
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .accessibilityLabel("Profile actions")
                    .accessibilityIdentifier("user-profile.actions")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
//            .padding(.top, 60)
            
            // 主要内容
            ScrollView {
                VStack(spacing: 0) {
                        // 顶部间距，为头像留出空间
                        Spacer().frame(height: 30)
                        
                        // 用户资料卡片 全屏宽度
                        ZStack(alignment: .topLeading) {
                            // 主卡片内容
                            VStack(spacing: 0) {
                                // 头像占位空间
                                HStack {
                                    Spacer().frame(width: 60, height: 15) // 头像占位空间
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 15)
                            
                            // 用户信息区域
                            VStack(alignment: .leading, spacing: 12) {
                                // 第一行：用户名和按钮
                                HStack {
                                    if profileStore.phase == .loading {
                                        Text("Loading...")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.7))
                                    } else {
                                        Text(profileStore.profile?.username ?? "User")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Spacer()
                                    
                                    if !isOwnProfile {
                                        HStack(spacing: 12) {
                                        Button(action: {
                                            createConversation()
                                        }) {
                                            Image("send_chat")
                                                .resizable()
                                                .frame(width: 42, height: 42)
                                        }
                                        .accessibilityIdentifier("user-profile.chat")
                                        
                                        Button(action: {
                                            profileStore.toggleFollow()
                                        }) {
                                            HStack(spacing: 4) {
                                                if isFollowLoading {
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                        .scaleEffect(0.96)
                                                } else {
                                                    Text(profileStore.profile?.isFollowing == true ? "Unfollow" : "Follow")
                                                        .font(.system(size: 17, weight: .light))
                                                        .foregroundColor(.black)
                                                }
                                            }
                                            .padding(.horizontal, 19)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule()
                                                    .fill(Color.white)
                                            )
                                        }
                                        .disabled(isFollowLoading || profileStore.profile == nil)
                                        .accessibilityIdentifier("user-profile.follow")
                                        .accessibilityValue(
                                            profileStore.profile?.isFollowing == true
                                                ? "following"
                                                : "not-following"
                                        )
                                        }
                                    }
                                }

                                if case .failed(let operation, _) = profileStore.phase {
                                    if operation == .load {
                                        HStack(spacing: 10) {
                                            Text("Couldn’t load this profile.")
                                                .font(.footnote)
                                                .foregroundColor(.white.opacity(0.72))

                                            Button("Try Again") {
                                                profileStore.load(actorID: actorId)
                                            }
                                            .font(.footnote.weight(.semibold))
                                            .foregroundColor(.white)
                                        }
                                        .accessibilityIdentifier("user-profile.load-error")
                                    } else if operation == .follow || operation == .block {
                                        Text(
                                            operation == .block
                                                ? "Couldn’t block this user. Try again."
                                                : "Couldn’t update follow. Try again."
                                        )
                                        .font(.footnote)
                                        .foregroundColor(.white.opacity(0.72))
                                        .accessibilityIdentifier("user-profile.social-error")
                                    }
                                }
                                
                                // 第二行：统计数据
                                HStack(spacing: 20) {
                                    Button {
                                        followListKind = .following
                                        showFollowList = true
                                    } label: {
                                    HStack(spacing: 4) {
                                        if profileStore.phase == .loading {
                                            Text("--")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white.opacity(0.7))
                                        } else {
                                            Text("\(profileStore.profile?.followingCount ?? 0)")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        Text("following")
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("user-profile.following-count")
                                    .accessibilityValue(
                                        "\(profileStore.profile?.followingCount ?? 0)"
                                    )
                                    
                                    Spacer()
                                    Button {
                                        followListKind = .followers
                                        showFollowList = true
                                    } label: {
                                    HStack(spacing: 4) {
                                        if profileStore.phase == .loading {
                                            Text("--")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white.opacity(0.7))
                                        } else {
                                            Text("\(profileStore.profile?.followerCount ?? 0)")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        Text("followers")
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("user-profile.followers-count")
                                    .accessibilityValue(
                                        "\(profileStore.profile?.followerCount ?? 0)"
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)
                            
                            // 笔记卡片列表
                            VStack(spacing: 20) {
                                if cardsManager.isLoading && cardsManager.cards.isEmpty {
                                    // 加载状态
//                                    VStack(spacing: 12) {
//                                        ProgressView()
//                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
//                                        Text("加载中...")
//                                            .font(.system(size: 14, weight: .medium))
//                                            .foregroundColor(.white.opacity(0.7))
//                                    }
//                                    .frame(height: 100)
                                } else if cardsManager.cards.isEmpty {
                                    // 空状态
                                    VStack(spacing: 12) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text("No notes")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .frame(height: 100)
                                } else {
                                    // 真实数据
                                    ForEach(cardsManager.cards, id: \.id) { card in
                                        UserPostCard(
                                            card: card,
                                            onShowMenu: { cardData in
                                                // 设置当前卡片数据
                                                currentMenuCardData = cardData
                                                popupMenuLayout = .grid2x2
                                                showPopupMenu = true
                                            },
                                            onCardTap: { cardId in
                                                selectedCardId = cardId
                                                DispatchQueue.main.async {
                                                    navigateToDetail = true
                                                }
                                            },
                                            onChatTap: {
                                                createConversation()
                                            },
                                            username: profileStore.profile?.username ?? "User",
                                            avatarUrl: profileStore.profile?.avatarURL,
                                            disableFavorite: false
                                        )
                                        .onAppear {
                                            print("卡片数据: id=\(card.id), commentCount=\(card.commentCount ?? -1), likeCount=\(card.likeCount)")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .background(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .cornerRadius(16)
                        )
                        
                        // 头像 - 骑在边框线上
                        HStack {
                            Group {
                                if let avatarUrl = profileStore.profile?.avatarURL, !avatarUrl.isEmpty {
                                    let fullAvatarUrl = APIConfiguration.resourceURLString(avatarUrl)
                                    
                                    AsyncImage(url: URL(string: fullAvatarUrl)) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                            Image("avatar")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                    }
                                } else {
                                    Image("avatar")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                }
                            }
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 3)
                                )
                                .offset(y: -36) // 向上偏移36，使头像中心在卡片上边框
                            
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 30)
                }
            }
        }
        .background(
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea(.all)
        )
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .overlay(
            CommentPopupView()
        )
        .onAppear {
            profileStore.load(actorID: actorId)

            // 加载用户卡片数据
            print("开始加载用户公开卡片: actorId=\(actorId)")
            cardsManager.loadPublicProfileCards(actorId: actorId, refresh: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToDetail"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? String {
                selectedCardId = cardId
                DispatchQueue.main.async {
                    navigateToDetail = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEdit"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? String {
                print("到编辑页通知: cardId=\(cardId)")
                selectedCardId = cardId
                DispatchQueue.main.async {
                    navigateToEdit = true
                }
            }
        }
        .confirmationDialog("", isPresented: $showActionSheet, titleVisibility: .hidden) {
            Button("Report this user", role: .destructive) {
                showReport = true
            }
            Button("Block this user", role: .destructive) {
                showBlockConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Block User", isPresented: $showBlockConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) {
                profileStore.block()
            }
        } message: {
            Text("Are you sure you want to block this user?")
        }
        .onChange(of: profileStore.didBlock) { didBlock in
            if didBlock { dismiss() }
        }
        .navigationDestination(isPresented: $navigateToChat) {
            ChatDetailView(
                conversationId: conversationId ?? "",
                contactName: profileStore.profile?.username ?? "User",
                contactStatus: "Online",
                contactAvatar: "avatar"
            )
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            if let cardId = selectedCardId {
                DetailView(cardId: cardId)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $navigateToEdit) {
            if let cardId = selectedCardId {
                NewNoteView(cardId: cardId)
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showReport) {
            ContentReportView(targetType: .actor, targetID: actorId)
        }
        .sheet(isPresented: $showFollowList) {
            FollowListView(
                actorID: actorId,
                actorName: profileStore.profile?.username ?? "User",
                kind: followListKind,
                viewerActorID: AuthManager.shared.currentUser?.id ?? ""
            )
        }
        .popupMenu(isPresented: $showPopupMenu, layout: popupMenuLayout, cardData: currentMenuCardData, isOwnCard: false)
        .linkPopup()
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text("User profile")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("screen.user-profile")
                Text(actorId)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("user-profile.actor-id")
            }
            .accessibilityElement(children: .contain)
        }
    }
    
    // MARK: Helper Functions
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 60 {
                return "just now"
            } else if timeInterval < 3600 {
                let minutes = Int(timeInterval / 60)
                return "\(minutes) minutes ago"
            } else if timeInterval < 86400 {
                let hours = Int(timeInterval / 3600)
                return "\(hours) hours ago"
            } else {
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            }
        }
        
        return dateString
    }
    
    // MARK: 发起会话
    private func createConversation() {
        guard !isCreatingConversation else { return }
        
        isCreatingConversation = true
        let request = CreateConversationRequest(participantId: actorId)
        
        NetworkManager.shared.createConversation(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isCreatingConversation = false
                    if case .failure(let error) = completion {
                        print("发起会话失败: \(error.localizedDescription)")
                        
                        if case .unauthorized = error {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("UnauthorizedError"),
                                object: nil
                            )
                        }
                    }
                },
                receiveValue: { response in
                    if response.success {
                        print("发起会话成功: conversationId=\(response.conversation.id)")
                        DispatchQueue.main.async {
                            self.conversationId = response.conversation.id
                            print("设置 conversationId: \(self.conversationId ?? "")")
                            
                            // 延迟一点时间确保状态更新
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.navigateToChat = true
                                print("navigateToChat: \(self.navigateToChat)")
                            }
                        }
                    } else {
                        print("发起会话失败: 服务器返回失败")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
}

// MARK: - User Post Card
struct UserPostCard: View {
    let card: UserCard
    let onShowMenu: (UserCard) -> Void
    let onCardTap: ((String) -> Void)?
    let onChatTap: (() -> Void)?
    let username: String
    let avatarUrl: String?
    let disableFavorite: Bool
    
    init(card: UserCard, onShowMenu: @escaping (UserCard) -> Void, onCardTap: ((String) -> Void)? = nil, onChatTap: (() -> Void)? = nil, username: String, avatarUrl: String? = nil, disableFavorite: Bool = false) {
        self.card = card
        self.onShowMenu = onShowMenu
        self.onCardTap = onCardTap
        self.onChatTap = onChatTap
        self.username = username
        self.avatarUrl = avatarUrl
        self.disableFavorite = disableFavorite
        _likeStore = StateObject(
            wrappedValue: CardLikeStore(
                state: CardLikeState(
                    cardID: card.id,
                    isLiked: card.isLiked,
                    likeCount: card.likeCount
                ),
                service: NetworkCoreCardLikeService(),
                onCommit: CardEngagementCenter.shared.publish
            )
        )
    }
    
    // 状态管理
    @StateObject private var likeStore: CardLikeStore
    @State private var isFavorited = false
    @State private var favoriteCount = 0
    @State private var commentCount = 0
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 作者信息
            HStack {
                Group {
                    if let avatarUrl = avatarUrl, !avatarUrl.isEmpty {
                        let fullAvatarUrl = APIConfiguration.resourceURLString(avatarUrl)
                        
                        AsyncImage(url: URL(string: fullAvatarUrl)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                Image("avatar")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                        }
                    } else {
                        Image("avatar")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(username)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(formatDate(card.createdAt))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // 菜单按钮
                Button(action: {
                    onShowMenu(card)
                }) {
                    Image(systemName: "ellipsis")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            
            // 内容文本
            HTMLTextRenderer(htmlContent: card.content, maxLines: 7)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .onTapGesture {
                    // 点击内容文本跳转到详情页
                    onCardTap?(card.id)
                }
            
            // 标签 横向滚动视图
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(card.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tagBackground)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
            }
            
            // 互动统计
            HStack(spacing: 16) {
                // 收藏按钮
                Button(action: {
                    if !disableFavorite {
                    toggleFavorite()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(isFavorited ? "favorite_active" : "favorite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                        Text("\(favoriteCount)")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .disabled(disableFavorite)
                .opacity(disableFavorite ? 0.5 : 1.0)
                
                Spacer()
                
                // 点赞按钮
                Button(action: likeStore.toggle) {
                    HStack(spacing: 4) {
                        Image(likeStore.state.isLiked ? "like_active" : "like")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 19, height: 19)
                        Text("\(likeStore.state.likeCount)")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                .disabled(likeStore.isMutating)
                .accessibilityLabel(likeStore.state.isLiked ? "Unlike" : "Like")
                .accessibilityValue(likeStore.state.isLiked ? "true" : "false")
                .accessibilityIdentifier("profile.like.\(card.id)")
                
                // 评论按钮
                CommentButton(cardId: card.id, commentCount: commentCount)
                    .scaleEffect(0.9)
                
                // Chat 按钮（如果提供了回调）
                if let onChatTap = onChatTap {
                    Button(action: {
                        onChatTap()
                    }) {
                        Image("send_chat")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                }
            }

            if case .failed = likeStore.phase {
                Text("Like failed. Try again.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.72))
                    .accessibilityIdentifier("profile.like.error.\(card.id)")
            }
        }
        .padding(20)
        .background(cardBackground)
        .onAppear {
            // 初始化状态
            likeStore.hydrate(
                CardLikeState(
                    cardID: card.id,
                    isLiked: card.isLiked,
                    likeCount: card.likeCount
                )
            )
            isFavorited = card.isFavorited ?? false
            favoriteCount = card.favoriteCount ?? 0
            commentCount = card.commentCount ?? 0
        }
        .onReceive(CardEngagementCenter.shared.likes) { state in
            likeStore.applyCommitted(state)
        }
    }
    // MARK: 收藏功能
    private func toggleFavorite() {
        guard AuthManager.shared.currentUser != nil else {
            print("用户未登录")
            return
        }
        
        let networkManager = NetworkManager.shared
        
        if isFavorited {
            // 取消收藏
            networkManager.unfavoriteCard(cardId: card.id)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("取消收藏失败: \(error)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFavorited = false
                            self.favoriteCount = max(0, self.favoriteCount - 1)
                            print("取消收藏成功")
                        }
                    }
                )
                .store(in: &cancellables)
        } else {
            // 收藏
            networkManager.favoriteCard(cardId: card.id)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("收藏失败: \(error)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFavorited = true
                            self.favoriteCount += 1
                        }
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Helper Functions
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 60 {
                return "just now"
            } else if timeInterval < 3600 {
                let minutes = Int(timeInterval / 60)
                return "\(minutes) minutes ago"
            } else if timeInterval < 86400 {
                let hours = Int(timeInterval / 3600)
                return "\(hours) hours ago"
            } else {
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            }
        }
        
        return dateString
    }
    
    // MARK: Background Views
    
    private var tagBackground: some View {
        Capsule()
            .fill(Color.white.opacity(0.2))
            .overlay(userPostCardTagTopLeftHighlight)
            .overlay(userPostCardTagBottomRightHighlight)
            .overlay(userPostCardTagTopEdgeHighlight)
            .overlay(userPostCardTagBottomEdgeHighlight)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial.opacity(0.2))
//            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }
    
    // MARK: 标签高光效果
    private var userPostCardTagTopLeftHighlight: some View {
        Capsule()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 15
                        )
                    )
            )
    }
    
    private var userPostCardTagBottomRightHighlight: some View {
        Capsule()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 15
                        )
                    )
            )
    }
    
    private var userPostCardTagTopEdgeHighlight: some View {
        Capsule()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var userPostCardTagBottomEdgeHighlight: some View {
        Capsule()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    // MARK: 卡片高光效果
    private var topLeftHighlight: some View {
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
    
    private var bottomRightHighlight: some View {
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
    
    private var topEdgeHighlight: some View {
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
    
    private var bottomEdgeHighlight: some View {
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

#Preview {
    UserProfileView(actorId: "act_preview")
} 
