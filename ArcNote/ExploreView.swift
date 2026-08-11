import CoreFlow
import SwiftUI

struct ExploreView: View {
    @Binding var showPopupMenu: Bool
    @Binding var selectedFilter: String
    @Binding var showFilterTags: Bool
    @Binding var showSideMenu: Bool
    let onSpark: (String) -> Void
    var onFlowCardVisible: (String) -> Void = { _ in }
    var onFlowCardSaved: (String) -> Void = { _ in }
    var onFlowCardDismissed: (String) -> Void = { _ in }
    var onboardingStore: OnboardingGuideStore? = nil
    var contextualTipStore: ContextualGuideTipStore? = nil
    @State private var isSearchMode = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @StateObject private var cardsManager = RecommendedCardsManager(autoLoad: false)
    @StateObject private var flowStore = FlowDeckStore(service: NetworkCoreFlowService())
    @StateObject private var searchManager = SearchManager.shared

    // ExploreView自己的弹窗状态
    @State private var showExplorePopupMenu = false
    @State private var currentExploreCardData: UserCard? = nil
    @State private var isCurrentExploreCardOwned = false
    
    // 导航状态
    @State private var navigateToUserProfile = false
    @State private var selectedActorId: String? = nil
    @State private var navigateToDetail = false
    @State private var selectedCardId: String? = nil
    
    // 搜索状态
    @State private var currentSearchIndex = 0
    @State private var hasSubmittedSearch = false

    private var isFlowSparkTipVisible: Bool {
        contextualTipStore?.isVisible(
            .flowSpark,
            onboardingState: onboardingStore?.session?.state,
            targetIsVisible: !isSearchMode && flowStore.currentCard != nil
        ) ?? false
    }

    private func dismissFlowSparkTipIfVisible() {
        guard isFlowSparkTipVisible else { return }
        contextualTipStore?.dismiss(
            .flowSpark,
            onboardingState: onboardingStore?.session?.state,
            targetIsVisible: true
        )
    }
    
    // MARK: - 计算属性
    
    #if DEBUG
    private var isUITestSession: Bool {
        ProcessInfo.processInfo.environment["CHORAI_UI_TEST"] == "1"
    }
    #endif

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
    
    // MARK: Background Card Views
    
    private var thirdCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.1))
            .frame(maxHeight: .infinity)
            .overlay(thirdCardTopLeftHighlight)
            .overlay(thirdCardBottomRightHighlight)
            .overlay(thirdCardTopEdgeHighlight)
            .overlay(thirdCardBottomEdgeHighlight)
            .offset(x: 60, y: 32)
            .opacity(0.2)
    }
    
    private var thirdCardTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.3), Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var thirdCardBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.3), Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var thirdCardTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var thirdCardBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
            .offset(x: -1, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    private var secondCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.1))
            .frame(maxHeight: .infinity)
            .overlay(secondCardTopLeftHighlight)
            .overlay(secondCardBottomRightHighlight)
            .overlay(secondCardTopEdgeHighlight)
            .overlay(secondCardBottomEdgeHighlight)
            .offset(x: 40, y: 14)
            .opacity(0.2)
    }
    
    private var secondCardTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.4), Color.clear],
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var secondCardBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.4), Color.clear],
                            center: .bottomTrailing,
                            startRadius: 10,
                            endRadius: 35
                        )
                    )
            )
    }
    
    private var secondCardTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var secondCardBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.4), lineWidth: 1)
            .offset(x: -1, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.clear],
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
            HStack {
                if isSearchMode {
                    // 搜索模式 - 返回按钮
                    Button(action: {
                        isSearchFocused = false
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSearchMode = false
                            searchText = ""
                            currentSearchIndex = 0
                            hasSubmittedSearch = false
                            // 退出搜索模式时清除搜索结果
                            searchManager.clearSearchResults()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("explore.search.back")
                    
                    Spacer()
                    
                    // 搜索输入框
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Please enter your search...", text: $searchText)
                            .foregroundColor(.white)
                            .textFieldStyle(PlainTextFieldStyle())
                            .focused($isSearchFocused)
                            .accessibilityIdentifier("explore.search.input")
                            .submitLabel(.search)
                            .placeholder(when: searchText.isEmpty) {
                                Text("Please enter your search...")
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .onSubmit {
                                // 按回车键时触发搜索
                                performSearch()
                            }
                        
//                        if !searchText.isEmpty {
//                            Button(action: {
//                                searchText = ""
//                            }) {
//                                Image(systemName: "xmark.circle.fill")
//                                    .foregroundColor(.white.opacity(0.7))
//                            }
//                        }
                    }
                    .padding(.horizontal, 25)
                    .padding(.vertical, 13)
                    .frame(maxWidth: 280)
                    .background(searchInputBackground)
                    
                    Spacer()
                } else {
                    // 正常模式
                    Button(action: {
                        dismissFlowSparkTipIfVisible()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSideMenu = true
                        }
                    }) {
                        Image("menu")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }
                    .accessibilityIdentifier("side-menu.open")
                    
                    Spacer()
                    
                    Text("Explore")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        dismissFlowSparkTipIfVisible()
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSearchMode = true
                        }
                        DispatchQueue.main.async {
                            isSearchFocused = true
                        }
                    }) {
                        ZStack {
                            Color.white.opacity(0.01)
                                .frame(width: 44, height: 44)
                            Image("search")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Search")
                        .accessibilityIdentifier("explore.search.open")
                    }
                }
            }
            .adaptiveContentGutter()
            .padding(.top, 60)

            if let onboardingStore,
               onboardingStore.guideScene != nil,
               !isSearchMode {
                OnboardingGuideLine(store: onboardingStore)
                    .adaptiveContentGutter()
                    .padding(.top, 8)
            }

            // 筛选标签
            if showFilterTags && !isSearchMode {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterTag(title: "All", isSelected: selectedFilter == "All") {
                            selectedFilter = "All"
                        }
                        .frame(width: 95)
                        FilterTag(title: "Follow", isSelected: selectedFilter == "Follow") {
                            selectedFilter = "Follow"
                        }
                        .frame(width: 95)
                        FilterTag(title: "Popular", isSelected: selectedFilter == "Popular") {
                            selectedFilter = "Popular"
                        }
                        .frame(width: 95)
                        FilterTag(title: "Trending", isSelected: selectedFilter == "Trending") {
                            selectedFilter = "Trending"
                        }
                        .frame(width: 95)
                    }
                    .adaptiveContentGutter()
                }
                .padding(.top, 10)
            }
            
            // 卡片内容
            ZStack {
                if isSearchMode {
                    // Search keeps the familiar stack; Flow owns its own restrained next-card hint.
                    thirdCardBackground
                    secondCardBackground
                }
                
                // 第一张卡片（最顶层）- 有内容的卡片
                if isSearchMode {
                    if searchManager.isLoading {
                        VStack {
                            RotatingLoaderView()
                        }
                        .frame(maxHeight: .infinity)
                        .accessibilityIdentifier("explore.search.loading")
                    } else if !searchManager.searchResults.isEmpty {
                        // 显示搜索结果
                        if currentSearchIndex < searchManager.searchResults.count {
                            let currentSearchCard = searchManager.searchResults[currentSearchIndex]
                            ZStack(alignment: .topLeading) {
                                PostCard(
                                    card: convertSearchCardToCard(currentSearchCard),
                                    cardsManager: cardsManager,
                                    onShowMenu: { cardData in
                                        currentExploreCardData = convertCardToUserCard(cardData)
                                        isCurrentExploreCardOwned = cardData.isOwner
                                            ?? isOwnedByCurrentUser(authorId: cardData.author?.id)
                                        showExplorePopupMenu = true
                                    },
                                    onSwipe: { translation, isEnded in
                                        handleSearchSwipe(translation: CGSize(width: translation, height: 0), isEnded: isEnded)
                                    },
                                    onAvatarTap: { actorId in
                                        selectedActorId = actorId
                                        DispatchQueue.main.async {
                                            navigateToUserProfile = true
                                            print("设置 navigateToUserProfile: \(navigateToUserProfile)")
                                        }
                                    },
                                    onCardTap: { cardId in
                                        print("收到卡片点击回调: cardId=\(cardId)")
                                        selectedCardId = cardId
                                        DispatchQueue.main.async {
                                            navigateToDetail = true
                                            print("设置 navigateToDetail: \(navigateToDetail)")
                                        }
                                    }
                                )
                                .opacity(1.0)

                                #if DEBUG
                                Text("Search results")
                                    .font(.system(size: 1))
                                    .foregroundColor(.white.opacity(0.01))
                                    .frame(width: 1, height: 1)
                                    .accessibilityIdentifier("explore.search.results")

                                Text(currentSearchCard.id)
                                    .font(.system(size: 1))
                                    .foregroundColor(.white.opacity(0.01))
                                    .frame(width: 1, height: 1)
                                    .accessibilityIdentifier("explore.search.result.card-id")
                                #endif
                            }
                        }
                    } else if !hasSubmittedSearch {
                        VStack(spacing: 12) {
                            Text("Type a keyword")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            Text("Press return to search")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxHeight: .infinity)
                        .accessibilityIdentifier("explore.search.idle")
                    } else {
                        VStack(spacing: 12) {
                            Text("No results found")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            Text("Try another keyword")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(maxHeight: .infinity)
                        .accessibilityIdentifier("explore.search.empty")
                    }
                } else {
                    FlowDeckView(
                        store: flowStore,
                        onOpenDetail: { card in
                            selectedCardId = card.id
                            navigateToDetail = true
                        },
                        onOpenAuthor: { card in
                            guard let actorId = card.author?.id else { return }
                            selectedActorId = actorId
                            navigateToUserProfile = true
                        },
                        onOpenMenu: { card in
                            currentExploreCardData = card.asUserCard
                            isCurrentExploreCardOwned = isOwnedByCurrentUser(authorId: card.author?.id)
                            showExplorePopupMenu = true
                        },
                        onSpark: { card in
                            onSpark(card.id)
                        },
                        onCardVisible: { card in
                            onFlowCardVisible(card.id)
                        },
                        onCardSaved: onFlowCardSaved,
                        onCardDismissed: onFlowCardDismissed,
                        onboardingStore: onboardingStore,
                        contextualTipStore: contextualTipStore
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSearchMode {
                    isSearchFocused = false
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, showFilterTags ? 15 : 15)
            .padding(.bottom, 150)
        }
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            if isUITestSession && !isSearchMode {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isSearchMode = true
                    }
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                }) {
                    Color.white.opacity(0.01)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Open Explore search")
                .accessibilityIdentifier("explore.search.open.test-hook")
                .padding(.top, 60)
                .padding(.trailing, 20)
            }
        }
        #endif
        .onAppear {
            // 设置评论创建回调
            CommentPopupManager.shared.onCommentCreated = { [weak cardsManager] (cardId: String) in
                print("收到评论创建通知: cardId=\(cardId)")
                cardsManager?.incrementCommentCount(for: cardId)
            }
            #if DEBUG
            publishVisibleRecommendedCardForUITest()
            #endif
        }
        #if DEBUG
        .onReceive(flowStore.$cards) { _ in
            publishVisibleRecommendedCardForUITest()
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseAllPopups"))) { _ in
            print("收到关闭所有popup通知")
            // 关闭所有 popup
            showExplorePopupMenu = false
            showFilterTags = false
        }
        .onChange(of: showFilterTags) { isPresented in
            if isPresented {
                dismissFlowSparkTipIfVisible()
            }
        }
        .onDisappear {
            dismissFlowSparkTipIfVisible()
        }
        .popupMenu(isPresented: $showExplorePopupMenu, layout: .grid2x2, cardData: currentExploreCardData, isOwnCard: isCurrentExploreCardOwned)
        .navigationDestination(isPresented: $navigateToUserProfile) {
            if let actorId = selectedActorId {
                UserProfileView(actorId: actorId)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            if let cardId = selectedCardId {
                DetailView(cardId: cardId)
            } else {
                EmptyView()
            }
        }
    }

    #if DEBUG
    private func publishVisibleRecommendedCardForUITest() {
        guard !isSearchMode, let cardId = flowStore.currentCard?.id else {
            return
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("ExploreVisibleRecommendedCardChanged"),
            object: nil,
            userInfo: ["cardId": cardId]
        )
    }
    #endif

    // MARK: - 执行搜索
    private func performSearch() {
        let trimmedText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearchFocused = false
        
        if !trimmedText.isEmpty {
            currentSearchIndex = 0 // 重置搜索索引
            hasSubmittedSearch = true
            searchManager.searchCards(query: trimmedText) { result in
                switch result {
                case .success(let searchCards):
                    print("搜索成功: \(searchCards.count) 张卡片")
                case .failure(let error):
                    print("搜索失败: \(error.localizedDescription)")
                }
            }
        } else {
            // 如果搜索文本为空，清除搜索结果
            currentSearchIndex = 0
            hasSubmittedSearch = false
            searchManager.clearSearchResults()
        }
    }
    
    // MARK: - 转换SearchCard为Card
    private func convertSearchCardToCard(_ searchCard: SearchCard) -> Card {
        return Card(
            id: searchCard.id,
            title: searchCard.title ?? "",
            content: searchCard.content,
            contentJSON: searchCard.contentJSON,
            backgroundMediaRef: searchCard.backgroundMediaRef,
            contentHash: searchCard.contentHash,
            tags: searchCard.tags,
            isPublic: searchCard.isPublic,
            createdAt: searchCard.createdAt,
            updatedAt: searchCard.updatedAt,
            favoriteCount: searchCard.favoriteCount,
            likeCount: searchCard.likeCount,
            viewCount: searchCard.viewCount,
            commentCount: searchCard.commentCount,
            rate: searchCard.rate,
            isFavorited: searchCard.isFavorited ?? false,
            isLiked: searchCard.isLiked ?? false,
            isPinned: searchCard.isPinned ?? false,
            pinnedAt: searchCard.pinnedAt,
            author: UserInfo(
                id: searchCard.author.id,
                username: searchCard.author.username,
                avatar: searchCard.author.avatarUrl,
                bio: nil,
                followersCount: nil,
                followingCount: nil,
                isFollowing: nil
            ),
            ownerActorId: searchCard.ownerActorId,
            isOwner: searchCard.isOwner
        )
    }
    
    // MARK: - 处理搜索滑动
    private func handleSearchSwipe(translation: CGSize, isEnded: Bool) {
        if isEnded {
            let threshold: CGFloat = 100
            if abs(translation.width) > threshold {
                if translation.width > 0 {
                    // 向右滑上一张搜索结果
                    if currentSearchIndex > 0 {
                        currentSearchIndex -= 1
                        print("搜索向右滑动，显示第 \(currentSearchIndex + 1) 张")
                    }
                } else {
                    // 向左滑下一张搜索结果
                    if currentSearchIndex < searchManager.searchResults.count - 1 {
                        currentSearchIndex += 1
                        print("搜索向左滑动，显示第 \(currentSearchIndex + 1) 张")
                    }
                }
            }
        }
    }
    
    // MARK: - 转换Card为UserCard
    private func convertCardToUserCard(_ card: Card) -> UserCard {
        return UserCard(
            id: card.id,
            title: card.title,
            content: card.content,
            contentJSON: card.contentJSON,
            backgroundMediaRef: card.backgroundMediaRef,
            contentHash: card.contentHash ?? "",
            isPublic: card.isPublic,
            tags: card.tags,
            createdAt: card.createdAt,
            updatedAt: card.updatedAt,
            likeCount: card.likeCount,
            commentCount: card.commentCount,
            isLiked: card.isLiked ?? false,
            isPinned: card.isPinned ?? false,
            pinnedAt: card.pinnedAt,
            isFavorited: card.isFavorited,
            favoriteCount: card.favoriteCount,
            rate: 0, // Card 模型没有 rate 字段，默认为 0
            ownerActorId: card.ownerActorId,
            isOwner: card.isOwner
        )
    }
    
    private func isOwnedByCurrentUser(authorId: String?) -> Bool {
        guard let authorId = authorId,
              let currentUserId = AuthManager.shared.currentUser?.id else {
            return false
        }
        return authorId == currentUserId
    }
}

#Preview {
    ExploreView(
        showPopupMenu: .constant(false),
        selectedFilter: .constant("All"),
        showFilterTags: .constant(false),
        showSideMenu: .constant(false),
        onSpark: { _ in }
    )
}

// MARK: - 筛选标签组件
struct FilterTag: View {
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

// MARK: - 旋转加载视图
struct RotatingLoaderView: View {
    @State private var isRotating = false
    
    var body: some View {
        Image("Loading")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 60, height: 60)
            .rotationEffect(.degrees(isRotating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    isRotating = true
                }
            }
    }
} 
