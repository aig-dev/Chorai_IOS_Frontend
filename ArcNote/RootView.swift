import SwiftUI

struct RootView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPopupMenu = false
    @State private var currentMenuCardData: UserCard? = nil
    @State private var isCurrentMenuCardOwned = false
    @StateObject private var mergeHistoryManager = MergeHistoryManager()
    @State private var currentCard: CardDetail? = nil
    @State private var isLoadingCurrentCard = false
    @State private var navigateToDetail = false
    @State private var navigateToEdit = false
    @State private var navigateToProfile = false
    @State private var selectedCardId: Int? = nil
    @State private var selectedUserId: Int? = nil
    @State private var navigationPath = NavigationPath()
    
    let cardId: Int
    let type: String?
    
    init(cardId: Int = 0, type: String? = nil) {
        self.cardId = cardId
        self.type = type
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
                    
                    Text("Card Traceability")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // 占位符，保持标题居中
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 20)
                 .padding(.top, 10)
                
                // 主要内容
                ScrollView {
                    VStack(spacing: 30) {
                        // 当前卡片（第一张）
                        if let currentCard = currentCard {
                            RootCardView(
                                avatar: "avatar",
                                name: currentCard.author?.userName ?? "Unknown",
                                time: formatDate(currentCard.createdAt),
                                content: currentCard.content,
                                tags: currentCard.tags.isEmpty ? ["Current", "Card"] : currentCard.tags,
                                rate: currentCard.rate,
                                onMenuTap: {
                                    handleMenuTap(card: currentCard)
                                },
                                onCardTap: {
                                    handleCardTap(cardId: currentCard.id, authorId: currentCard.author?.userId)
                                },
                                onAvatarTap: {
                                    handleAvatarTap(userId: currentCard.author?.userId)
                                }
                            )
                        }
                        
                        if mergeHistoryManager.isLoading {
                            // 加载状态
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                                Text("Loading merge history...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.top, 10)
                            }
                            .frame(maxHeight: .infinity)
                        } else if let mergeHistory = mergeHistoryManager.mergeHistory {
                            // 显示合并历史数据
                            VStack(spacing: 30) {
                                // 源卡片列表
                                ForEach(mergeHistory.sourceCards, id: \.id) { sourceCard in
                                    RootCardView(
                                        avatar: "avatar",
                                        name: sourceCard.author.userName,
                                        time: formatDate(sourceCard.createdAt),
                                        content: sourceCard.content,
                                        tags: sourceCard.tags.isEmpty ? ["Source", "Card"] : sourceCard.tags,
                                        rate: sourceCard.rate,
                                        onMenuTap: {
                                            handleSourceCardMenuTap(sourceCard: sourceCard)
                                        },
                                        onCardTap: {
                                            handleCardTap(cardId: sourceCard.id, authorId: sourceCard.author.userId)
                                        },
                                        onAvatarTap: {
                                            handleAvatarTap(userId: sourceCard.author.userId)
                                        }
                                    )
                                }
                            }
                        } else {
                            // 无数据状态
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.6))
                                Text("No merge history found")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.top, 16)
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 30)
                }
                
                Spacer()
            }
            .background(
                Image("home_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
            )
            .popupMenu(isPresented: $showPopupMenu, layout: .grid2x2, cardData: currentMenuCardData, isOwnCard: isCurrentMenuCardOwned)
            .linkPopup()
            
            // 导航处理
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
            .navigationDestination(isPresented: $navigateToProfile) {
                if let userId = selectedUserId {
                    UserProfileView(userId: userId)
                        .onAppear {
                            print("navigationDestination - 创建 UserProfileView with userId: \(userId)")
                        }
                } else {
                    EmptyView()
                        .onAppear {
                            print("navigationDestination - selectedUserId 为空")
                        }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEdit"))) { notification in
                if let cardId = notification.userInfo?["cardId"] as? Int {
                    selectedCardId = cardId
                    DispatchQueue.main.async {
                        navigateToEdit = true
                    }
                }
            }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .gesture(
            DragGesture()
                .onEnded { value in
                    // 侧滑返回手势
                    if value.translation.width > 100 && abs(value.translation.height) < 50 {
                        dismiss()
                    }
                }
        )
        .onAppear {
            if cardId > 0 {
                if let userId = AuthManager.shared.currentUser?.id {
                    // 加载当前卡片详情
                    loadCurrentCard()
                    // 加载合并历史，传递 type 参数
                    mergeHistoryManager.fetchMergeHistory(cardId: cardId, userId: userId, type: type)
                }
            }
        }
    }
    
    // MARK: 处理卡片点击
    private func handleCardTap(cardId: Int, authorId: Int?) {
        guard let currentUserId = AuthManager.shared.currentUser?.id else {
            return
        }
        
        selectedCardId = cardId
        
        if let authorId = authorId, authorId == currentUserId {
            // 自己的卡片，跳转到编辑页
            navigateToEdit = true
        } else {
            // 其他人的卡片，跳转到详情页
            navigateToDetail = true
        }
    }
    
    // MARK: 处理菜单点击
    private func handleMenuTap(card: CardDetail) {
        // 将 CardDetail 转换为 UserCard
        let userCard = UserCard(
            id: card.id,
            title: card.title ?? "",
            content: card.content,
            contentHash: card.contentHash,
            isPublic: card.isPublic,
            tags: card.tags,
            createdAt: card.createdAt,
            updatedAt: card.updatedAt,
            likeCount: card.likeCount,
            commentCount: card.commentCount ?? 0,
            isLiked: card.isLiked,
            isPinned: card.isPinned ?? false,
            pinnedAt: card.pinnedAt,
            isFavorited: card.isFavorited ?? false,
            favoriteCount: card.favoriteCount ?? 0,
            rate: card.rate
        )
        
        // 判断是否是自己的卡片
        let currentUserId = AuthManager.shared.currentUser?.id
        isCurrentMenuCardOwned = (card.author?.userId == currentUserId)
        
        currentMenuCardData = userCard
        showPopupMenu = true
    }
    
    private func handleSourceCardMenuTap(sourceCard: MergeHistorySourceCard) {
        // 将 MergeHistorySourceCard 转换为 UserCard
        let userCard = UserCard(
            id: sourceCard.id,
            title: sourceCard.title ?? "",
            content: sourceCard.content,
            contentHash: "",
            isPublic: true, // 源卡片默认为公开
            tags: sourceCard.tags,
            createdAt: sourceCard.createdAt,
            updatedAt: sourceCard.createdAt,
            likeCount: 0,
            commentCount: 0,
            isLiked: false,
            isPinned: false,
            pinnedAt: nil,
            isFavorited: false,
            favoriteCount: 0,
            rate: sourceCard.rate
        )
        
        // 判断是否是自己的卡片
        let currentUserId = AuthManager.shared.currentUser?.id
        isCurrentMenuCardOwned = (sourceCard.author.userId == currentUserId)
        
        currentMenuCardData = userCard
        showPopupMenu = true
    }
    
    // MARK: 处理头像点击
    private func handleAvatarTap(userId: Int?) {
        guard let userId = userId else {
            print("用户ID为空")
            return
        }
        
        selectedUserId = userId
        print("selectedUserId 设置为: \(selectedUserId ?? -1)")
        navigateToProfile = true
        print("navigateToProfile 设置为: \(navigateToProfile)")
    }
    
    // MARK: 加载当前卡片详情
    private func loadCurrentCard() {
        guard let userId = AuthManager.shared.currentUser?.id else {
            print("用户未登录")
            return
        }
        
        isLoadingCurrentCard = true
        print("开始加载当前卡片详情: cardId=\(cardId), userId=\(userId)")
        
        NetworkManager.shared.getCardDetail(cardId: cardId, userId: userId) { result in
            DispatchQueue.main.async {
                isLoadingCurrentCard = false
                
                switch result {
                case .success(let response):
                    self.currentCard = response.data
                case .failure(let error):
                    print("加载当前卡片详情失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: 格式化日期
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
            } else if timeInterval < 604800 {
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            } else {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "MM-dd HH:mm"
                return displayFormatter.string(from: date)
            }
        }
        
        return dateString
    }
}

// MARK: Root Card View
struct RootCardView: View {
    let avatar: String
    let name: String
    let time: String
    let content: String
    let tags: [String]
    let rate: Int
    let onMenuTap: () -> Void
    let onCardTap: (() -> Void)?
    let onAvatarTap: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧时间线
            GeometryReader { geometry in
                ZStack {
                    // 垂直线条
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .position(x: 1, y: geometry.size.height / 2)
                    
                    // 中间的圆点
                    Circle()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 8, height: 8)
                        .position(x: 1, y: geometry.size.height / 2)
                }
            }
            .frame(width: 20)
            
            // 卡片内容
            VStack(alignment: .leading, spacing: 16) {
                // 头部信息
                HStack {
                    Button(action: {
                        onAvatarTap?()
                    }) {
                        Image(avatar)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(time)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        onMenuTap()
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                
                // 内容文本
                HTMLTextRenderer(htmlContent: content, maxLines: 3)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.9))
                
                // 标签 横向滚动
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.2))
                                )
                        }
                    }
                    .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
                }
            }
            .padding(20)
            .background(
                ZStack {
                    // 根据 rate 值显示不同的背景
                    backgroundImageForRate(rate)
                    
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .onTapGesture {
                onCardTap?()
            }
        }
    }
    
    // MARK: 根据 rate 值返回背景图片
    private func backgroundImageForRate(_ rate: Int) -> some View {
        Group {
            if rate < 3 {
                // 普通卡片样式
                Color(red: 0.2, green: 0.1, blue: 0.3).opacity(0.8)
            } else if rate >= 3 && rate <= 8 {
                // note_bg_green
                Image("note_bg_green")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate > 8 && rate <= 26 {
                // note_bg_blue
                Image("note_bg_blue")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate > 27 && rate <= 80 {
                // note_bg_purple
                Image("note_bg_purple")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate > 80 && rate <= 242 {
                // note_bg_yellow
                Image("note_bg_yellow")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else if rate > 242 {
                // note_bg_red
                Image("note_bg_red")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                // 默认样式
                Color(red: 0.2, green: 0.1, blue: 0.3).opacity(0.8)
            }
        }
    }
}

#Preview {
    RootView()
} 
