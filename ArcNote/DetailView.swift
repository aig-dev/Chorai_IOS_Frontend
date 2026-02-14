import SwiftUI
import Combine

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
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var isFavorited = false
    @State private var favoriteCount = 0
    @State private var commentCount = 0
    @State private var cancellables = Set<AnyCancellable>()
    
    // 聊天相关状态
    @State private var navigateToChat = false
    @State private var conversationId: Int? = nil
    @State private var isCreatingConversation = false
    
    // 关注相关状态
    @State private var isFollowing = false
    @State private var isFollowLoading = false
    
    let cardId: Int
    
    init(cardId: Int = 0) {
        self.cardId = cardId
    }
    
    // 关联笔记数据
    @State private var relatedNotes: [CardLinkItem] = []
    @State private var isLoadingLinks = false
    @State private var navigateToRelatedDetail = false
    @State private var selectedRelatedCardId: Int? = nil
    
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
                    
                    Button(action: {
                        showPopupMenu = true
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
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
                                if let userId = cardDetailManager.cardDetail?.author?.userId {
                                    print("UserProfileView: userId=\(userId)")
                                navigateToUserProfile = true
                                } else {
                                    print("无法获取用户ID")
                                }
                            }) {
                                Group {
                                    if let avatarUrl = cardDetailManager.cardDetail?.author?.avatarUrl, !avatarUrl.isEmpty {
                                        let fullAvatarUrl = avatarUrl.hasPrefix("http://") || avatarUrl.hasPrefix("https://") 
                                            ? avatarUrl 
                                            : "https://api.zhizuo.site/\(avatarUrl.hasPrefix("/") ? String(avatarUrl.dropFirst()) : avatarUrl)"
                                        
                                        
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
                                        if let avatarUrl = note.author.avatar, !avatarUrl.isEmpty {
                                            let fullAvatarUrl = avatarUrl.hasPrefix("http://") || avatarUrl.hasPrefix("https://") 
                                                ? avatarUrl 
                                                : "https://api.zhizuo.site/\(avatarUrl.hasPrefix("/") ? String(avatarUrl.dropFirst()) : avatarUrl)"
                                            
                                        
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
                                                    Text(note.author.userName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                                        .lineLimit(1)
                                        
                                                    HTMLTextRenderer(htmlContent: note.content, maxLines: 2)
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
                HStack(spacing: 24) {
                    // 点赞按钮
                    Button(action: {
                        toggleLike()
                    }) {
                    HStack(spacing: 6) {
                            Image(isLiked ? "like_active" : "like")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            Text("\(likeCount)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        }
                    }
                    
                    // 评论按钮
                    CommentButton(cardId: cardId, commentCount: commentCount)
                        .scaleEffect(1.1)
                    
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
        .popupMenu(isPresented: $showPopupMenu, layout: .grid2x2)
        .overlay(
            CommentPopupView()
        )
        .navigationDestination(isPresented: $navigateToUserProfile) {
            UserProfileView(userId: cardDetailManager.cardDetail?.author?.userId ?? 0)
        }
        .navigationDestination(isPresented: $navigateToChat) {
            ChatDetailView(
                conversationId: conversationId ?? 0,
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
            if cardId > 0 {
                loadCardDetail()
            }
        }
        .onChange(of: cardId) { newCardId in
            if newCardId > 0 {
                loadCardDetail()
                
            }
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
                    self.isLiked = cardDetail.isLiked
                    self.likeCount = cardDetail.likeCount
                    self.isFavorited = cardDetail.isFavorited ?? false
                    self.favoriteCount = cardDetail.favoriteCount ?? 0
                    self.commentCount = cardDetail.commentCount ?? 0
                }
                
                loadRelatedNotes(cardDetail.author?.userId ?? 0)
                checkFollowStatus()
            case .failure(let error):
                print("详情加载失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 加载关联笔记
    private func loadRelatedNotes(_ userId: Int) {
      
        
        isLoadingLinks = true
        print("加载关联笔记: cardId=\(cardId), userId=\(userId)")
        
        NetworkManager.shared.getCardLinks(cardId: cardId, userId: userId)
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
    
    // MARK: 点赞功能
    private func toggleLike() {
        guard let userId = AuthManager.shared.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        let networkManager = NetworkManager.shared
        
        if isLiked {
            // 取消点赞
            networkManager.unlikeCard(cardId: cardId, userId: userId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("取消点赞失败: \(error)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isLiked = false
                            self.likeCount = max(0, self.likeCount - 1)
                            print("取消点赞成功")
                        }
                    }
                )
                .store(in: &cancellables)
        } else {
            // 点赞
            networkManager.likeCard(cardId: cardId, userId: userId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("点赞失败: \(error)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isLiked = true
                            self.likeCount += 1
                            print("点赞成功")
                        }
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: - 收藏功能
    private func toggleFavorite() {
        guard let userId = AuthManager.shared.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        let networkManager = NetworkManager.shared
        
        if isFavorited {
            // 取消收藏
            networkManager.unfavoriteCard(cardId: cardId, userId: userId)
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
            networkManager.favoriteCard(cardId: cardId, userId: userId)
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
        
        guard let authorId = cardDetailManager.cardDetail?.author?.userId else {
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
                            print("设置 conversationId: \(self.conversationId ?? -1)")
                            
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
        
        guard let authorId = cardDetailManager.cardDetail?.author?.userId else {
            print("无法获取作者ID")
            return
        }
        
        
        NetworkManager.shared.checkFollowStatus(userId: currentUserId, targetUserIds: [authorId])
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("关注状态失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    if response.success {
                        let followStatus = response.data[String(authorId)] ?? false
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
        
        guard let authorId = cardDetailManager.cardDetail?.author?.userId else {
            print("无法获取作者ID")
            return
        }
        
        isFollowLoading = true
        
        if isFollowing {
            // 取消关注
            NetworkManager.shared.unfollowUser(userId: currentUserId, targetUserId: authorId)
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
            
            NetworkManager.shared.followUser(userId: currentUserId, targetUserId: authorId)
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
                            print("关注成功: \(response.data.targetUser.username)")
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
    DetailView(cardId: 123)
}
