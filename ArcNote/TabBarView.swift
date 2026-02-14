import SwiftUI
import Combine
import WebKit

struct TabBarView: View {
    @State private var selectedTab = 0
    @State private var showPopupMenu = false
    @State private var selectedFilter = "All"
    @State private var showFilterTags = false
    @State private var showSideMenu = false
    @State private var currentMenuCardData: UserCard? = nil
    @State private var navigationPath = NavigationPath()
    @State private var navigateToEdit = false
    @State private var selectedEditCardId: Int? = nil
    @State private var navigateToMerge = false
    @State private var selectedMergeCardId: Int? = nil
    @State private var navigateToReport = false

    private enum TabRoute: Hashable {
        case spark(Int)
    }

    // MARK: - My Notes 点击处理
    private func onMyNotesTapped() {
        // 切换到Home页面 (tag = 1)
        selectedTab = 1
        
        // 关闭所有 popup
        closeAllPopups()
        
        // 通知HomeView切换到NotesList
        NotificationCenter.default.post(
            name: NSNotification.Name("SwitchToNotesList"),
            object: nil
        )
    }
    
    // MARK: - Favorites 点击处理
    private func onFavoritesTapped() {
        // 切换到Home页面 (tag = 1)
        selectedTab = 1
        
        // 关闭所有 popup
        closeAllPopups()
        
        // 通知HomeView切换到AIList
        NotificationCenter.default.post(
            name: NSNotification.Name("SwitchToAIList"),
            object: nil
        )
    }
    
    // MARK: - 关闭所有 Popup
    private func closeAllPopups() {
        // 关闭 popup 菜单
        showPopupMenu = false
        
        // 关闭筛选标签
        showFilterTags = false
        
        // 关闭侧边菜单
        showSideMenu = false
        
        // 发送通知关闭所有 popup
        NotificationCenter.default.post(
            name: NSNotification.Name("CloseAllPopups"),
            object: nil
        )
        
        print("已关闭所有 popup")
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
            // 背景图片
//                Image("home_bg")
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
//                    .clipped()
//                    .ignoresSafeArea()
            
            // 主要内容区域 - 全屏显示
            TabView(selection: $selectedTab) {
                // Explore 页面
                ExploreView(
                    showPopupMenu: $showPopupMenu,
                    selectedFilter: $selectedFilter,
                    showFilterTags: $showFilterTags,
                    showSideMenu: $showSideMenu
                )
                .tag(0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .background(
                    Image("home_bg")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea(.all)
                )
                
                // Home 页面
                HomeView(showSideMenu: $showSideMenu)
                    .tag(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .background(
                    Image("home_bg")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea(.all)
                )
                
                // Chat 页面
                ChatView(showSideMenu: $showSideMenu)
                    .tag(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .background(
                    Image("home_bg")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea(.all)
                )
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.all)
            .background(
                Image("home_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea(.all)
            )
            .onAppear {
                // 禁用 TabView 的侧滑手势
                UIScrollView.appearance().isScrollEnabled = false
            }
            .onChange(of: selectedTab) { newTab in
                // 切换 tab 时关闭所有 popup
                closeAllPopups()
            }
            
            // 底部 TabBar - 浮在内容之上
            VStack {
                Spacer()
                
                HStack(spacing: 0) {
                    // Explore Tab
                    Button(action: {
                        selectedTab = 0
                        closeAllPopups()
                    }) {
                        VStack(spacing: 4) {
                            Image(selectedTab == 0 ? "tab_explore_active" : "tab_explore")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: selectedTab == 0 ? 35 : 26, height: selectedTab == 0 ? 35 : 26)
                                .scaleEffect(selectedTab == 0 ? 1.1 : 1.0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: selectedTab == 0)
                            
                            Text("Explore")
                                .font(.system(size: 12, weight: selectedTab == 0 ? .semibold : .medium))
                                .foregroundColor(selectedTab == 0 ? .white : .white.opacity(0.7))
                                .animation(.easeInOut(duration: 0.3), value: selectedTab == 0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Home Tab
                    Button(action: {
                        selectedTab = 1
                        closeAllPopups()
                    }) {
                        VStack(spacing: 4) {
                            Image(selectedTab == 1 ? "tab_home_active" : "tab_home")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: selectedTab == 1 ? 35 : 26, height: selectedTab == 1 ? 35 : 26)
                                .scaleEffect(selectedTab == 1 ? 1.1 : 1.0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: selectedTab == 1)
                            
                            Text("Home")
                                .font(.system(size: 12, weight: selectedTab == 1 ? .semibold : .medium))
                                .foregroundColor(selectedTab == 1 ? .white : .white.opacity(0.7))
                                .animation(.easeInOut(duration: 0.3), value: selectedTab == 1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Chat Tab
                    Button(action: {
                        selectedTab = 2
                        closeAllPopups()
                    }) {
                        VStack(spacing: 4) {
                            Image(selectedTab == 2 ? "tab_chat_active" : "tab_chat")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: selectedTab == 2 ? 35 : 26, height: selectedTab == 2 ? 35 : 26)
                                .scaleEffect(selectedTab == 2 ? 1.1 : 1.0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: selectedTab == 2)
                            
                            Text("Chat")
                                .font(.system(size: 12, weight: selectedTab == 2 ? .semibold : .medium))
                                .foregroundColor(selectedTab == 2 ? .white : .white.opacity(0.7))
                                .animation(.easeInOut(duration: 0.3), value: selectedTab == 2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.9))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 0)
            }
            
            // 全局弹窗 - 最顶层
            // 使用 modifier 方式，不需要额外的 if 语句
            
            // 侧边菜单
            SideMenuView(
                isPresented: $showSideMenu,
                onMyNotesTapped: {
                    onMyNotesTapped()
                },
                onFavoritesTapped: {
                    onFavoritesTapped()
                }
            )
            
            // 评论弹窗
            CommentPopupView()
        }
        .popupMenu(isPresented: $showPopupMenu, layout: .grid2x2, cardData: currentMenuCardData)
        .linkPopup()
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToEdit) {
            NewNoteView(cardId: selectedEditCardId ?? 0)
        }
        .navigationDestination(isPresented: $navigateToMerge) {
            MergeView(cardId: selectedMergeCardId ?? 0)
        }
        .navigationDestination(isPresented: $navigateToReport) {
            WebViewPage(url: URL(string: "https://www.chorai.app/report")!, title: "Help & Report")
        }
        .navigationDestination(for: TabRoute.self) { route in
            switch route {
            case .spark(let cardId):
                SparkView(cardId: cardId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEdit"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? Int {
                selectedEditCardId = cardId
                DispatchQueue.main.async {
                    navigateToEdit = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSpark"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? Int {
                DispatchQueue.main.async {
                    navigationPath.append(TabRoute.spark(cardId))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMerge"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? Int {
                selectedMergeCardId = cardId
                DispatchQueue.main.async {
                    navigateToMerge = false
                    navigateToMerge = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToReport"))) { _ in
            DispatchQueue.main.async {
                navigateToReport = false
                navigateToReport = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowCardMenu"))) { notification in
            if let userInfo = notification.userInfo,
               let cardData = userInfo["cardData"] as? UserCard {
                currentMenuCardData = cardData
                // 显示菜单
                showPopupMenu = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToHome"))) { _ in
            navigationPath.removeLast(navigationPath.count)
            selectedTab = 1
            // 关闭所有 popup
            closeAllPopups()
        }
        }
    }
}



// 帖子卡片组件
struct PostCard: View {
    let card: Card
    @ObservedObject var cardsManager: RecommendedCardsManager
    @State private var offset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var isLoadingAuthor = false
    @State private var isMenuButtonPressed = false
    var onShowMenu: (Card) -> Void
    var onSwipe: (CGFloat, Bool) -> Void
    var onAvatarTap: ((Int) -> Void)? = nil
    var onCardTap: ((Int) -> Void)? = nil
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }
    
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 用户信息
            HStack {
                // 头像
                Button(action: {
                    print("card.author: \(String(describing: card.author))")
                    if let author = card.author {
                        print(" author.id: \(author.id)")
                        onAvatarTap?(author.id)
                    } else {
                        loadAuthorFromCardDetail()
                    }
                }) {
                    Group {
                        if let avatarUrl = card.author?.avatar, !avatarUrl.isEmpty {
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
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.author?.username ?? "AI")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(formatDate(card.createdAt))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Button(action: {
                    isMenuButtonPressed = true
                    onShowMenu(card)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isMenuButtonPressed = false
                    }
                }) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 16)
            
            // 帖子内容 填充剩余空间
            VStack(alignment: .leading, spacing: 0) {
                HTMLWebView(htmlContent: card.content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                // 整个内容区域都可以点击
                onCardTap?(card.id)
            }
            
            // 底部内容 - 固定在底部
            VStack(spacing: 16) {
                // 标签
                if !card.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(card.tags, id: \.self) { tag in
                                TagView(text: tag)
                            }
                            Spacer()
                        }
                    }
                }
                
                // 交互统计
                HStack {
                    // 左边一个 - 收藏按钮
                    Button(action: {
                        cardsManager.toggleFavorite(for: card.id)
                    }) {
                        HStack(spacing: 4) {
                            Image(cardsManager.getFavoriteState(for: card.id) ? "favorite_active" : "favorite")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 26, height: 26)
                            Text("\(cardsManager.getFavoriteCount(for: card.id))")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    Spacer()
                    
                    // 右边两个
                    HStack(spacing: 20) {
                        Button(action: {
                            cardsManager.toggleLike(for: card.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(cardsManager.getLikeState(for: card.id) ? "like_active" : "like")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                Text("\(cardsManager.getLikeCount(for: card.id))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        
                        CommentButton(cardId: card.id, cardsManager: cardsManager)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity)
        .background(
            cardBackground
        )
        .offset(x: offset)
        .rotationEffect(.degrees(rotation))
        .scaleEffect(scale)
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    offset = value.translation.width
                    rotation = Double(value.translation.width / 10)
                    scale = 1.0 - abs(value.translation.width) / 1000
                    onSwipe(value.translation.width, false)
                }
                .onEnded { value in
                    let threshold: CGFloat = 100
                    if abs(value.translation.width) > threshold {
                        // 滑动距离足够，切换到下一张
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = value.translation.width > 0 ? 500 : -500
                            rotation = value.translation.width > 0 ? 30 : -30
                            scale = 0.8
                        }
                        
                        // 通知父组件切换卡片
                        onSwipe(value.translation.width, true)
                        
                        // 重置状态
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            offset = 0
                            rotation = 0
                            scale = 1.0
                        }
                    } else {
                        // 滑动距离不够，回到原位
                        withAnimation(.easeInOut(duration: 0.3)) {
                            offset = 0
                            rotation = 0
                            scale = 1.0
                        }
                    }
                }
        )
        .onAppear {
            // 点赞状态现在由 RecommendedCardsManager 管理
        }
    }
    
    // MARK: - 获取作者信息
    private func loadAuthorFromCardDetail() {
        guard !isLoadingAuthor else { return }
        
        isLoadingAuthor = true
        print("获取卡片详情: cardId=\(card.id)")
        
        guard let userId = AuthManager.shared.currentUser?.id else {
            print("用户未登录")
            isLoadingAuthor = false
            return
        }
        
        NetworkManager.shared.getCardDetail(cardId: card.id, userId: userId) { result in
            DispatchQueue.main.async {
                self.isLoadingAuthor = false
                switch result {
                case .success(let response):
                    if let author = response.data.author {
                        print("成功: userId=\(author.userId)")
                        self.onAvatarTap?(author.userId)
                    } else {
                    }
                case .failure(let error):
                    print("获取卡片详情失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - 辅助函数
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        if let date = formatter.date(from: dateString) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 3600 {
                let minutes = Int(timeInterval / 60)
                return "\(minutes) minutes ago"
            } else if timeInterval < 86400 {
                let hours = Int(timeInterval / 3600)
                return "\(hours) hours ago"
            } else if timeInterval < 604800 { // 7天内
                let days = Int(timeInterval / 86400)
                return "\(days) days ago"
            } else {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "MMM dd"
                return displayFormatter.string(from: date)
            }
        }
        
        return "Recently"
    }
    
}

// 标签组件
struct TagView: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white.opacity(0.1))
            )
    }
}

#Preview {
    TabBarView()
}



// MARK: - HTMLWebView 组件
struct HTMLWebView1: UIViewRepresentable {
    let html: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    margin: 0;
                    padding: 0;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: 14px;
                    line-height: 1.4;
                    color: rgba(255, 255, 255, 0.9);
                    background: transparent;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                p {
                    margin: 0 0 8px 0;
                }
                p:last-child {
                    margin-bottom: 0;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin: 0 0 8px 0;
                    font-weight: 600;
                }
                ul, ol {
                    margin: 0 0 8px 0;
                    padding-left: 20px;
                }
                li {
                    margin: 0 0 4px 0;
                }
                blockquote {
                    margin: 0 0 8px 0;
                    padding-left: 16px;
                    border-left: 3px solid rgba(255, 255, 255, 0.3);
                }
                code {
                    background: rgba(255, 255, 255, 0.1);
                    padding: 2px 4px;
                    border-radius: 3px;
                    font-family: 'SF Mono', Monaco, monospace;
                    font-size: 12px;
                }
                pre {
                    background: rgba(255, 255, 255, 0.1);
                    padding: 8px;
                    border-radius: 6px;
                    overflow-x: auto;
                    margin: 0 0 8px 0;
                }
                pre code {
                    background: none;
                    padding: 0;
                }
                a {
                    color: rgba(255, 255, 255, 0.8);
                    text-decoration: underline;
                }
                img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 4px;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
        
        webView.loadHTMLString(htmlString, baseURL: nil)
    }
}

// PopupMenuView 和 MenuButton 已移至 PopupMenuView.swift 文件中 
