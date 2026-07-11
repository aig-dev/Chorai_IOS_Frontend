import SwiftUI
import Combine
import CoreFlow

// MARK: 关联笔记数据模型
struct DetailRelatedNote: Identifiable {
    let id = UUID()
    let avatar: String
    let title: String
    let description: String
}

struct DetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPopupMenu = false
    @State private var navigateToUserProfile = false
    @State private var isRelatedNotesExpanded = false
    @State private var contentHeight: CGFloat = 200
    @StateObject private var cardDetailManager = CardDetailManager.shared
    
    // 状态管理
    @StateObject private var likeStore: CardLikeStore
    @State private var isFavorited = false
    @State private var favoriteCount = 0
    @State private var commentCount = 0
    @State private var cancellables = Set<AnyCancellable>()
    
    // 聊天相关状态
    @State private var navigateToChat = false
    @State private var conversationId: String? = nil
    @State private var isCreatingConversation = false
    
    // 关注相关状态
    @State private var isFollowing = false
    @State private var isFollowLoading = false
    
    let cardId: String
    
    init(cardId: String = "") {
        self.cardId = cardId
        _likeStore = StateObject(
            wrappedValue: CardLikeStore(
                state: CardLikeState(
                    cardID: cardId,
                    isLiked: false,
                    likeCount: 0
                ),
                service: NetworkCoreCardLikeService(),
                onCommit: CardEngagementCenter.shared.publish
            )
        )
    }
    
    private var isCurrentCardOwned: Bool {
        guard let authorId = cardDetailManager.cardDetail?.author?.actorId,
              let currentUserId = AuthManager.shared.currentUser?.id else {
            return false
        }
        return authorId == currentUserId
    }
    
    private var currentDetailUserCard: UserCard? {
        guard let detail = cardDetailManager.cardDetail else {
            return nil
        }
        return UserCard(
            id: detail.id,
            title: detail.title,
            content: detail.content,
            contentHash: detail.contentHash,
            isPublic: detail.isPublic,
            tags: detail.tags,
            createdAt: detail.createdAt,
            updatedAt: detail.updatedAt,
            likeCount: detail.likeCount,
            commentCount: detail.commentCount,
            isLiked: detail.isLiked,
            isPinned: detail.isPinned ?? false,
            pinnedAt: detail.pinnedAt,
            isFavorited: detail.isFavorited,
            favoriteCount: detail.favoriteCount,
            rate: detail.rate
        )
    }
    
    // 关联笔记数据
    @State private var relatedNotes: [CardLinkItem] = []
    @State private var isLoadingLinks = false
    @State private var navigateToRelatedDetail = false
    @State private var selectedRelatedCardId: String? = nil
    
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
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("detail.back")
                    
                    Spacer()
                    
                    Button(action: {
                        showPopupMenu = true
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .accessibilityIdentifier("detail.menu.open")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 60)
                
                // 主要内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // 用户资料和Follow按钮
                        HStack {
                            Button(action: {
                                // 导航到UserProfileView
                                if let userId = cardDetailManager.cardDetail?.author?.actorId {
                                    print("UserProfileView: userId=\(userId)")
                                navigateToUserProfile = true
                                } else {
                                    print("无法获取用户ID")
                                }
                            }) {
                                Group {
                                    if let avatarUrl = cardDetailManager.cardDetail?.author?.avatarUrl, !avatarUrl.isEmpty {
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
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(cardDetailManager.cardDetail?.author?.userName ?? "Unknown User")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("User")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            HStack(spacing: 12) {
                                Button(action: {
                                    createConversation()
                                }) {
                                    Image("send_chat")
                                        .resizable()
                                        .frame(width: 35, height: 35)
                                }
                                
                                Button(action: {
                                    toggleFollow()
                                }) {
                                    HStack(spacing: 4) {
                                        if isFollowLoading {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                .scaleEffect(0.8)
                                        } else {
                                            Text(isFollowing ? "Unfollow" : "Follow")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.black)
                                        }
                                    }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color.white)
                                        )
                                }
                                .disabled(isFollowLoading)
                            }
                            
                            Spacer()
                            
                        }
                        .padding(.horizontal, 20)
                        
                        // 主文章内容
                        VStack(alignment: .leading, spacing: 16) {
                            if let cardDetail = cardDetailManager.cardDetail {
                                AdaptiveHTMLWebView(htmlContent: cardDetail.content, height: $contentHeight)
                                    .frame(height: contentHeight)
                            } else {
                                Text("...")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // 时间戳和标签
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(formatDate(cardDetailManager.cardDetail?.createdAt ?? ""))
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.white.opacity(0.7))
                                
                                if cardDetailManager.cardDetail?.isPublic == true {
                                Image(systemName: "globe")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                }
                                
                                Spacer()
                                
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                    ForEach(cardDetailManager.cardDetail?.tags ?? [], id: \.self) { tag in
                                    Text(tag)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color(red: 0.2, green: 0.1, blue: 0.3))
                                        )
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 1) // 添加一点内边距避免标签贴边
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // 关联笔记展开/收起按钮
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isRelatedNotesExpanded.toggle()
                                }
                            }) {
                                Image(systemName: isRelatedNotesExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // 关联笔记列表
                        if isRelatedNotesExpanded {
                            if isLoadingLinks {
                                VStack {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Loading related notes...")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.top, 8)
                                }
                                .frame(height: 100)
                            } else if relatedNotes.isEmpty {
                               
                            } else {
                        VStack(spacing: 0) {
                                ForEach(Array(relatedNotes.enumerated()), id: \.element.id) { index, note in
                                        VStack {
                                HStack(spacing: 12) {
                                    Group {
                                        if let avatarUrl = note.author?.avatar, !avatarUrl.isEmpty {
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
                                        .frame(width: 40, height: 40)
                                                    .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                                    Text(note.author?.userName ?? note.title ?? "Related note")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                                        .lineLimit(1)
                                        
                                                    HTMLTextRenderer(htmlContent: note.content ?? "", maxLines: 2)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 16)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedRelatedCardId = note.linkedCardId
                                                DispatchQueue.main.async {
                                                    navigateToRelatedDetail = true
                                                }
                                            }
                                        }
                                        
                                    if index < relatedNotes.count - 1 {
                                            Rectangle()
                                                .fill(Color.white.opacity(0.1))
                                                .frame(height: 1)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
                
                Spacer()
                
                // 底部互动栏
                VStack(spacing: 8) {
                    HStack(spacing: 24) {
                        // 点赞按钮
                        Button(action: likeStore.toggle) {
                            HStack(spacing: 6) {
                            Image(likeStore.state.isLiked ? "like_active" : "like")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                Text("\(likeStore.state.likeCount)")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(likeStore.isMutating)
                        .accessibilityLabel(likeStore.state.isLiked ? "Unlike" : "Like")
                        .accessibilityValue(likeStore.state.isLiked ? "true" : "false")
                        .accessibilityIdentifier("detail.like.\(cardId)")
                    
                    // 评论按钮
                    CommentButton(cardId: cardId, commentCount: commentCount)
                        .scaleEffect(1.1)
                        .accessibilityIdentifier("detail.comment.open")
                    
                    // 收藏按钮
                    Button(action: {
                        toggleFavorite()
                    }) {
                    HStack(spacing: 6) {
                        Image(isFavorited ? "favorite_active" : "favorite")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 25, height: 25)
                            Text("\(favoriteCount)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        }
                    }
                    
                        Spacer()
                    }
                    if case .failed = likeStore.phase {
                        Text("Like failed. Try again.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.72))
                            .accessibilityIdentifier("detail.like.error.\(cardId)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.startLocation.x < 100 && value.translation.width > 100 {
                            dismiss()
                        }
                }
        )
        .popupMenu(
            isPresented: $showPopupMenu,
            layout: isCurrentCardOwned ? .grid3x3 : .grid2x2,
            cardData: currentDetailUserCard,
            isOwnCard: isCurrentCardOwned
        )
        .overlay(
            CommentPopupView()
        )
        .navigationDestination(isPresented: $navigateToUserProfile) {
            UserProfileView(actorId: cardDetailManager.cardDetail?.author?.actorId ?? "")
        }
        .navigationDestination(isPresented: $navigateToChat) {
            ChatDetailView(
                conversationId: conversationId ?? "",
                contactName: cardDetailManager.cardDetail?.author?.userName ?? "User",
                contactStatus: "Online",
                contactAvatar: "avatar"
            )
        }
        .navigationDestination(isPresented: $navigateToRelatedDetail) {
            if let relatedCardId = selectedRelatedCardId {
                DetailView(cardId: relatedCardId)
            } else {
                EmptyView()
            }
        }
        .onAppear {
            if !cardId.isEmpty {
                loadCardDetail()
            }
        }
        .onChange(of: cardId) { newCardId in
            if !newCardId.isEmpty {
                loadCardDetail()
                
            }
        }
        .overlay(alignment: .topLeading) {
            #if DEBUG
            Group {
                if cardDetailManager.isLoading {
                    Text("Detail loading")
                        .font(.system(size: 1))
                        .foregroundColor(.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("screen.detail.loading")
                } else if cardDetailManager.cardDetail != nil {
                    VStack(spacing: 0) {
                        Text("Detail loaded")
                            .accessibilityIdentifier("screen.detail.loaded")
                        Text(cardDetailManager.cardDetail?.id ?? "")
                            .accessibilityIdentifier("screen.detail.loaded-card-id")
                    }
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .frame(width: 1, height: 1)
                } else if cardDetailManager.error != nil {
                    Text("Detail error")
                        .font(.system(size: 1))
                        .foregroundColor(.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("screen.detail.error")
                } else {
                    Text("Detail idle")
                        .font(.system(size: 1))
                        .foregroundColor(.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("screen.detail.content")
                }
            }
            #endif
        }
        .overlay(alignment: .topTrailing) {
            #if DEBUG
            Text(cardId)
                .font(.system(size: 1))
                .foregroundColor(.white.opacity(0.01))
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("screen.detail.card-id")
            #endif
        }
        .onReceive(CardEngagementCenter.shared.likes) { state in
            likeStore.applyCommitted(state)
        }
    }
    
    // MARK: 加载卡片详情
    private func loadCardDetail() {
        // 先清空之前的数据，避免显示旧内容
        cardDetailManager.cardDetail = nil
        
        cardDetailManager.fetchCardDetail(cardId: cardId) { result in
            switch result {
            case .success(let cardDetail):
                print("详情加载成功: \(cardDetail.title ?? "")")
                
                // 初始化状态
                DispatchQueue.main.async {
                    self.likeStore.hydrate(
                        CardLikeState(
                            cardID: cardDetail.id,
                            isLiked: cardDetail.isLiked,
                            likeCount: cardDetail.likeCount
                        )
                    )
                    self.isFavorited = cardDetail.isFavorited ?? false
                    self.favoriteCount = cardDetail.favoriteCount ?? 0
                    self.commentCount = cardDetail.commentCount ?? 0
                }
                
                loadRelatedNotes()
                checkFollowStatus()
            case .failure(let error):
                print("详情加载失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 加载关联笔记
    private func loadRelatedNotes() {
      
        
        isLoadingLinks = true
        print("加载关联笔记: cardId=\(cardId)")
        
        NetworkManager.shared.getCardLinks(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoadingLinks = false
                    if case .failure(let error) = completion {
                        print("加载关联笔记失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    if response.success {
                        let allLinks = response.data.outgoingLinks + response.data.incomingLinks
                        self.relatedNotes = allLinks
                    } else {
                        print("关联笔记失败: \(response.message)")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 收藏功能
    private func toggleFavorite() {
        guard AuthManager.shared.currentUser != nil else {
            print("用户未登录")
            return
        }
        
        let networkManager = NetworkManager.shared
        
        if isFavorited {
            // 取消收藏
            networkManager.unfavoriteCard(cardId: cardId)
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
            networkManager.favoriteCard(cardId: cardId)
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
                            print("收藏成功")
                        }
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: 发起会话
    private func createConversation() {
        guard !isCreatingConversation else { return }
        
        guard let authorId = cardDetailManager.cardDetail?.author?.actorId else {
            print("无法获取作者ID")
            return
        }
        
        isCreatingConversation = true
        print("开始发起会话: participantId=\(authorId)")
        
        let request = CreateConversationRequest(participantId: authorId)
        
        NetworkManager.shared.createConversation(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isCreatingConversation = false
                    if case .failure(let error) = completion {
                        print("发起会话失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    if response.success {
                        DispatchQueue.main.async {
                            self.conversationId = response.conversation.id
                            print("设置 conversationId: \(self.conversationId ?? "")")
                            
                            // 延迟一点时间确保状态更新
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.navigateToChat = true
                                print("设置 navigateToChat: \(self.navigateToChat)")
                            }
                        }
                    } else {
                        print("发起会话失败: 服务器返回失败")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 关注功能
    private func checkFollowStatus() {
        guard let currentUserId = AuthManager.shared.currentUser?.id else {
            print("用户未登录，无法检查关注状态")
            return
        }
        
        guard let authorId = cardDetailManager.cardDetail?.author?.actorId else {
            print("无法获取作者ID")
            return
        }
        
        
        NetworkManager.shared.checkFollowStatus(targetActorIds: [authorId])
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("关注状态失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    if response.success {
                        let followStatus = response.data[authorId] ?? false
                        self.isFollowing = followStatus
                        print("关注状态: \(followStatus)")
                    } else {
                        print("检查关注状态失败: 服务器返回失败")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func toggleFollow() {
        guard !isFollowLoading else { return }
        guard let currentUserId = AuthManager.shared.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        guard let authorId = cardDetailManager.cardDetail?.author?.actorId else {
            print("无法获取作者ID")
            return
        }
        
        isFollowLoading = true
        
        if isFollowing {
            // 取消关注
            NetworkManager.shared.unfollowUser(targetActorId: authorId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        isFollowLoading = false
                        if case .failure(let error) = completion {
                            print("失败: \(error.localizedDescription)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFollowing = false
                            print("取消关注成功")
                        } else {
                            print("失败: 服务器返回失败")
                        }
                    }
                )
                .store(in: &cancellables)
        } else {
            // 关注
            
            NetworkManager.shared.followUser(targetActorId: authorId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        isFollowLoading = false
                        if case .failure(let error) = completion {
                            print("关注失败: \(error.localizedDescription)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFollowing = true
                            print("关注成功: \(response.message)")
                        } else {
                            print("关注失败: 服务器返回失败")
                        }
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: - 格式化日期
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
            } else if timeInterval < 2592000 {
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            } else {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "MMM dd, yyyy"
                return outputFormatter.string(from: date)
            }
        }
        
        return dateString
    }
}

#Preview {
    DetailView(cardId: "ast_preview")
}
