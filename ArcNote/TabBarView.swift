import SwiftUI
import Combine
import CoreFlow
import WebKit

struct TabBarView: View {
    @StateObject private var coordinator = CoreFlowCoordinator()
    @StateObject private var captureStore = QuickCaptureStore(
        service: NetworkCoreFlowService(),
        draftStore: UserDefaultsCaptureDraftStore()
    )
    @State private var showPopupMenu = false
    @State private var selectedFilter = "All"
    @State private var showFilterTags = false
    @State private var showSideMenu = false
    @State private var currentMenuCardData: UserCard? = nil
    @State private var navigationPath = NavigationPath()
    @State private var navigateToEdit = false
    @State private var selectedEditCardId: String? = nil
    @State private var navigateToMerge = false
    @State private var selectedMergeCardId: String? = nil
    @State private var navigateToReport = false

    #if DEBUG
    @State private var exploreSearchSmokeInvoked = false
    @State private var exploreSearchSmokeInFlight = false
    @State private var exploreSearchSmokeCompleted = false
    @State private var exploreDetailSmokeInvoked = false
    @State private var exploreDetailSmokeInFlight = false
    @State private var selectedDetailSmokeCardId: String? = nil
    @State private var navigateToDetailSmoke = false
    @State private var detailSmokeCancellable: AnyCancellable?
    @State private var exploreDetailSmokeAutoStarted = false
    @State private var visibleExploreCardId: String? = nil
    #endif

    private enum TabRoute: Hashable {
        case spark(String)
    }

    #if DEBUG
    private var activeScreenAutomationAnchor: some View {
        let identifier: String
        let label: String

        switch coordinator.selectedTab {
        case .library:
            identifier = "screen.home.content"
            label = "Library screen"
        case .chat:
            identifier = "screen.chat.content"
            label = "Chat screen"
        case .flow:
            identifier = "screen.flow.content"
            label = "Flow screen"
        }

        return Text(label)
            .font(.system(size: 1))
            .foregroundColor(.white.opacity(0.01))
            .frame(width: 1, height: 1)
            .accessibilityIdentifier(identifier)
    }

    private func submitExploreSearchSmoke() {
        print("Explore search smoke invoked")
        exploreSearchSmokeInvoked = true
        exploreSearchSmokeCompleted = false
        exploreSearchSmokeInFlight = true

        SearchManager.shared.searchCards(query: "go api ui smoke unlikely result") { _ in
            DispatchQueue.main.async {
                print("Explore search smoke completed")
                exploreSearchSmokeInFlight = false
                exploreSearchSmokeCompleted = true
            }
        }
    }

    private func openExploreRecommendedDetailSmoke() {
        print("Explore detail smoke invoked")
        exploreDetailSmokeInvoked = true
        exploreDetailSmokeInFlight = true
        selectedDetailSmokeCardId = nil
        navigateToDetailSmoke = false

        if let requestedCardId = ProcessInfo.processInfo.environment["CHORAI_UI_TEST_DETAIL_CARD_ID"],
           !requestedCardId.isEmpty {
            exploreDetailSmokeInFlight = false
            selectedDetailSmokeCardId = requestedCardId
            navigateToDetailSmoke = true
            return
        }

        detailSmokeCancellable = NetworkManager.shared
            .getRecommendedCards(limit: 1)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    exploreDetailSmokeInFlight = false
                    if case .failure(let error) = completion {
                        print("Explore detail smoke failed: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    guard let card = response.data.first else {
                        print("Explore detail smoke has no recommended card")
                        return
                    }

                    selectedDetailSmokeCardId = card.id
                    navigateToDetailSmoke = true
                }
            )
    }

    private func startExploreDetailSmokeIfRequested() {
        guard !exploreDetailSmokeAutoStarted,
              ProcessInfo.processInfo.arguments.contains("--ui-test-open-recommended-detail") else {
            return
        }

        exploreDetailSmokeAutoStarted = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            coordinator.selectedTab = .flow
            openExploreRecommendedDetailSmoke()
        }
    }
    #endif

    // MARK: - My Notes 点击处理
    private func onMyNotesTapped() {
        // 切换到Home页面 (tag = 1)
        coordinator.selectedTab = .library
        
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
        coordinator.selectedTab = .library
        
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
            TabView(selection: $coordinator.selectedTab) {
                // Explore 页面
	            ExploreView(
	                showPopupMenu: $showPopupMenu,
	                selectedFilter: $selectedFilter,
	                showFilterTags: $showFilterTags,
	                showSideMenu: $showSideMenu,
	                onSpark: { cardId in
	                    navigationPath.append(TabRoute.spark(cardId))
	                }
	            )
                .tag(CoreTab.flow)
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
                HomeView(
                    showSideMenu: $showSideMenu,
                    refreshID: coordinator.libraryRefreshID
                )
                    .tag(CoreTab.library)
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
                    .tag(CoreTab.chat)
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
                #if DEBUG
                startExploreDetailSmokeIfRequested()
                #endif
            }
            .onChange(of: coordinator.selectedTab) { _ in
                // 切换 tab 时关闭所有 popup
                closeAllPopups()
            }

            #if DEBUG
            activeScreenAutomationAnchor
            if coordinator.selectedTab == .flow {
                VStack(alignment: .leading, spacing: 4) {
                    Button(action: {
                        submitExploreSearchSmoke()
                    }) {
                        Color.white.opacity(0.01)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Explore search smoke")
                    .accessibilityIdentifier("explore.search")

                    Button(action: {
                        openExploreRecommendedDetailSmoke()
                    }) {
                        Color.white.opacity(0.01)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Explore detail smoke")
                    .accessibilityIdentifier("explore.card-detail")

                    if exploreSearchSmokeInvoked {
                        Text("Explore search invoked")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.search.invoked")
                    }

                    if exploreSearchSmokeInFlight {
                        Text("Explore search loading")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.search.loading")
                    }

                    if exploreSearchSmokeCompleted {
                        Text("Explore search completed")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.search.completed")
                    }

                    if exploreDetailSmokeInvoked {
                        Text("Explore detail invoked")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.card-detail.invoked")
                    }

                    if exploreDetailSmokeInFlight {
                        Text("Explore detail loading")
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.card-detail.loading")
                    }

                    if let visibleExploreCardId {
                        Text(visibleExploreCardId)
                            .font(.system(size: 1))
                            .foregroundColor(.white.opacity(0.01))
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("explore.visible-card.id")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 90)
                .padding(.leading, 8)
            }
            #endif

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CoreTabBar(
                selectedTab: $coordinator.selectedTab,
                onRecord: coordinator.presentCapture
            )
            .padding(.bottom, 6)
        }
        .sheet(isPresented: $coordinator.isCapturePresented) {
            if let actorID = AuthManager.shared.currentUser?.id {
                QuickCaptureSheet(
                    store: captureStore,
                    actorID: actorID,
                    onCreated: coordinator.captureCompleted,
                    onDismiss: coordinator.dismissCapture
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if let acknowledgementID = coordinator.recordAcknowledgementID {
                    Label("Recorded", systemImage: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                        .accessibilityIdentifier("record.acknowledgement")
                        .task(id: acknowledgementID) {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            guard !Task.isCancelled else { return }
                            coordinator.clearRecordAcknowledgement(cardID: acknowledgementID)
                        }
                }

                if let cardID = coordinator.lastCreatedCardID {
                    Text(cardID)
                        .font(.system(size: 1))
                        .foregroundStyle(Color.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("record.created-card-id")
                }
            }
            .padding(.top, 54)
        }
        .popupMenu(isPresented: $showPopupMenu, layout: .grid2x2, cardData: currentMenuCardData)
        .linkPopup()
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $navigateToEdit) {
            NewNoteView(cardId: selectedEditCardId ?? "")
        }
        .navigationDestination(isPresented: $navigateToMerge) {
            MergeView(cardId: selectedMergeCardId ?? "")
        }
        .navigationDestination(isPresented: $navigateToReport) {
            WebViewPage(url: URL(string: "https://www.chorai.app/report")!, title: "Help & Report")
        }
        #if DEBUG
        .navigationDestination(isPresented: $navigateToDetailSmoke) {
            if let cardId = selectedDetailSmokeCardId {
                DetailView(cardId: cardId)
            } else {
                EmptyView()
            }
        }
        #endif
        .navigationDestination(for: TabRoute.self) { route in
            switch route {
            case .spark(let cardId):
                SparkView(cardId: cardId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToEdit"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? String {
                selectedEditCardId = cardId
                DispatchQueue.main.async {
                    navigateToEdit = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSpark"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? String {
                DispatchQueue.main.async {
                    navigationPath.append(TabRoute.spark(cardId))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToMerge"))) { notification in
            if let cardId = notification.userInfo?["cardId"] as? String {
                selectedMergeCardId = cardId
                DispatchQueue.main.async {
                    navigateToMerge = false
                    navigateToMerge = true
                }
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ExploreVisibleRecommendedCardChanged"))) { notification in
            visibleExploreCardId = notification.userInfo?["cardId"] as? String
        }
        #endif
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
            coordinator.selectedTab = .library
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
    var onAvatarTap: ((String) -> Void)? = nil
    var onCardTap: ((String) -> Void)? = nil
    
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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Favorite")
                    .accessibilityValue(cardsManager.getFavoriteState(for: card.id) ? "true" : "false")
                    .accessibilityIdentifier("card.favorite.\(card.id)")
                    
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
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Like")
                        .accessibilityValue(cardsManager.getLikeState(for: card.id) ? "true" : "false")
                        .accessibilityIdentifier("card.like.\(card.id)")
                        
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
            #if DEBUG
            NotificationCenter.default.post(
                name: NSNotification.Name("ExploreVisibleRecommendedCardChanged"),
                object: nil,
                userInfo: ["cardId": card.id]
            )
            #endif
        }
    }
    
    // MARK: - 获取作者信息
    private func loadAuthorFromCardDetail() {
        guard !isLoadingAuthor else { return }
        
        isLoadingAuthor = true
        print("获取卡片详情: cardId=\(card.id)")
        
        guard AuthManager.shared.currentUser != nil else {
            print("用户未登录")
            isLoadingAuthor = false
            return
        }
        
        NetworkManager.shared.getCardDetail(cardId: card.id) { result in
            DispatchQueue.main.async {
                self.isLoadingAuthor = false
                switch result {
                case .success(let response):
                    if let author = response.data.author {
                        print("成功: actorId=\(author.actorId)")
                        self.onAvatarTap?(author.actorId)
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
