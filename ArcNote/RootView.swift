import SwiftUI

struct RootView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPopupMenu = false
    @State private var currentMenuCardData: UserCard? = nil
    @State private var isCurrentMenuCardOwned = false
    @StateObject private var sparkHistoryManager = SparkHistoryManager()
    @State private var currentCard: CardDetail? = nil
    @State private var isLoadingCurrentCard = false
    @State private var navigateToDetail = false
    @State private var navigateToEdit = false
    @State private var navigateToProfile = false
    @State private var selectedCardId: String? = nil
    @State private var selectedActorId: String? = nil
    @State private var navigationPath = NavigationPath()
    
    let cardId: String
    let type: String?
    
    init(cardId: String = "", type: String? = nil) {
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
                                    handleCardTap(cardId: currentCard.id, authorId: currentCard.author?.actorId)
                                },
                                onAvatarTap: {
                                    handleAvatarTap(actorId: currentCard.author?.actorId)
                                }
                            )
                        }
                        
                        if sparkHistoryManager.isLoading {
                            // 加载状态
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                                Text("Loading Spark history...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.top, 10)
                            }
                            .frame(maxHeight: .infinity)
                        } else if sparkHistoryManager.historyItems.isEmpty {
                            // 无数据状态
                            VStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.6))
                                Text("No Spark history found")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.top, 16)
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(sparkHistoryManager.historyItems) { item in
                                    SparkHistoryRow(
                                        item: item,
                                        timeText: formatFlexibleDate(item.createdAt)
                                    )
                                }
                            }
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
                if let actorId = selectedActorId {
                    UserProfileView(actorId: actorId)
                        .onAppear {
                            print("navigationDestination - 创建 UserProfileView with actorId: \(actorId)")
                        }
                } else {
                    EmptyView()
                        .onAppear {
                            print("navigationDestination - selectedActorId 为空")
                        }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEdit"))) { notification in
                if let cardId = notification.userInfo?["cardId"] as? String {
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
            if !cardId.isEmpty {
                loadCurrentCard()
                sparkHistoryManager.fetchSparkHistory(cardId: cardId)
            }
        }
    }
    
    // MARK: 处理卡片点击
    private func handleCardTap(cardId: String, authorId: String?) {
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
        isCurrentMenuCardOwned = (card.author?.actorId == currentUserId)
        
        currentMenuCardData = userCard
        showPopupMenu = true
    }
    
    // MARK: 处理头像点击
    private func handleAvatarTap(actorId: String?) {
        guard let actorId = actorId else {
            print("actorId 为空")
            return
        }
        
        selectedActorId = actorId
        print("selectedActorId 设置为: \(selectedActorId ?? "")")
        navigateToProfile = true
        print("navigateToProfile 设置为: \(navigateToProfile)")
    }
    
    // MARK: 加载当前卡片详情
    private func loadCurrentCard() {
        guard AuthManager.shared.currentUser != nil else {
            print("用户未登录")
            return
        }
        
        isLoadingCurrentCard = true
        print("开始加载当前卡片详情: cardId=\(cardId)")
        
        NetworkManager.shared.getCardDetail(cardId: cardId) { result in
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

    private func formatFlexibleDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        let date = isoFormatter.date(from: dateString) ?? fallbackFormatter.date(from: dateString)
        guard let date = date else {
            return dateString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d, HH:mm"
        return displayFormatter.string(from: date)
    }
}

struct SparkHistoryRow: View {
    let item: SparkHistoryItem
    let timeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Spark", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Text(timeText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.65))
            }

            HStack(spacing: 14) {
                metric("Results", "\(item.resultCount)")
                metric("Depth", "\(item.chainDepth)")
                metric("Credits", "\(item.creditsDeducted)")
            }

            Text(item.activityId)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
