import CoreFlow
import SwiftUI

struct ExploreView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    var sparkResumeRootSourceAssetID: String? = nil
    @State private var isSearchMode = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @StateObject private var cardsManager = RecommendedCardsManager(autoLoad: false)
    @StateObject private var flowStore = FlowDeckStore(service: NetworkCoreFlowService(), onFavoriteCommitted: CardEngagementCenter.shared.publishFavorite)
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

    private func bindCommentCreatedCallback() {
        let manager = cardsManager
        CommentPopupManager.shared.onCommentCreated = { [weak manager] cardID in
            manager?.incrementCommentCount(for: cardID)
        }
    }

    private func targetIsVisible(for tip: ContextualGuideTipID) -> Bool {
        guard !isSearchMode, flowStore.currentCard != nil else {
            return false
        }
        if tip == .sparkResume {
            return OnboardingSparkContinuationPolicy.shouldShowResumeTip(
                onboardingState: onboardingStore?.contextualTipState,
                resumeRootSourceAssetID: sparkResumeRootSourceAssetID
            )
        }
        return true
    }

    private func dismissVisibleFlowTip() {
        for tip in [
            ContextualGuideTipID.flowCard,
            .flowSpark,
            .sparkResume,
        ] {
            let targetIsVisible = targetIsVisible(for: tip)
            guard contextualTipStore?.isVisible(
                tip,
                onboardingState: onboardingStore?.contextualTipState,
                targetIsVisible: targetIsVisible
            ) == true else {
                continue
            }
            contextualTipStore?.dismiss(
                tip,
                onboardingState: onboardingStore?.contextualTipState,
                targetIsVisible: targetIsVisible
            )
        }
    }
    
    @State private var gridMode = false
    @State private var showsHistory = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        KeyboardStableViewport(isFocused: isSearchFocused) { _ in
            VStack(spacing: 12) {
                if isSearchMode { searchField.adaptiveContentGutter() }
                else { browseHeading.padding(.horizontal, 14) }
                if let onboardingStore, onboardingStore.guideScene != nil, !isSearchMode {
                    OnboardingGuideLine(store: onboardingStore)
                }
                if showFilterTags && !isSearchMode {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["All", "Follow", "Popular", "Trending"], id: \.self) { filter in
                                FilterTag(title: filter, isSelected: selectedFilter == filter) { selectedFilter = filter }
                            }
                        }
                    }
                }
                ZStack {
                    FlowDeckView(
                        store: flowStore,
                        isGrid: gridMode,
                        onOpenDetail: { card in selectedCardId = card.id; navigateToDetail = true },
                        onOpenAuthor: { card in
                            guard let actorID = card.author?.id else { return }
                            selectedActorId = actorID; navigateToUserProfile = true
                        },
                        onOpenMenu: { card in
                            currentExploreCardData = card.asUserCard
                            isCurrentExploreCardOwned = card.isOwner || isOwnedByCurrentUser(authorId: card.author?.id)
                            showExplorePopupMenu = true
                        },
                        onSpark: { onSpark($0.id) },
                        onCardVisible: { onFlowCardVisible($0.id) },
                        onCardSaved: onFlowCardSaved,
                        onCardDismissed: onFlowCardDismissed,
                        onboardingStore: onboardingStore,
                        contextualTipStore: contextualTipStore,
                        sparkResumeRootSourceAssetID: sparkResumeRootSourceAssetID
                    )
                    .opacity(isSearchMode ? 0 : 1)
                    .allowsHitTesting(!isSearchMode)
                    .accessibilityHidden(isSearchMode)
                    if isSearchMode { searchContent.adaptiveContentGutter() }
                }
            }
            .padding(.top, gridMode ? 12 : 8).padding(.bottom, 12)
        }
        .choraiPageBackground()
        .navigationTitle(isSearchMode ? "Search" : "Explore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { exploreToolbar }
        .sheet(isPresented: $showsHistory) {
            NavigationStack {
                List {
                    ForEach(Array(flowStore.history.enumerated()).reversed(), id: \.element.id) { index, card in
                        Button {
                            flowStore.revisitHistory(at: index)
                            showsHistory = false
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(FlowTextPreview.make(card.content)).font(.body).lineLimit(3)
                                Text(card.author?.username ?? "Chorai").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }
                        .accessibilityIdentifier("flow.history.item.\(card.id)")
                        .listRowBackground(ChoraiTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden).choraiPageBackground()
                .navigationTitle("Recently viewed").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsHistory = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            bindCommentCreatedCallback()
            #if DEBUG
            publishVisibleRecommendedCardForUITest()
            #endif
        }
        #if DEBUG
        .onReceive(flowStore.$cards) { _ in publishVisibleRecommendedCardForUITest() }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseAllPopups"))) { _ in
            showExplorePopupMenu = false; showFilterTags = false
        }
        .onChange(of: showFilterTags) { if $0 { dismissVisibleFlowTip() } }
        .popupMenu(isPresented: $showExplorePopupMenu, layout: .grid2x2, cardData: currentExploreCardData, isOwnCard: isCurrentExploreCardOwned)
        .navigationDestination(isPresented: $navigateToUserProfile) {
            if let actorID = selectedActorId { UserProfileView(actorId: actorID) }
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            if let cardID = selectedCardId {
                DetailView(cardId: cardID)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
    }

    @ToolbarContentBuilder
    private var exploreToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
                if isSearchMode {
                    Button(action: cancelSearch) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back").accessibilityIdentifier("explore.search.back")
                } else {
                    Button {
                        dismissVisibleFlowTip()
                        showSideMenu = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open sidebar").accessibilityIdentifier("side-menu.open")
                }
        }
        ToolbarItem(placement: .principal) {
            Text(isSearchMode ? "Search" : "Explore")
                .font(.headline)
                .foregroundStyle(.primary)
                #if DEBUG
                .accessibilityIdentifier(LocalDevelopmentPreview.isEnabled
                    ? "local-preview.indicator" : "explore.title")
                #endif
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if isSearchMode { Button("Cancel", action: cancelSearch) }
            else {
                HStack(spacing: 12) {
                    Button { gridMode.toggle() } label: {
                        Image(systemName: gridMode ? "rectangle.portrait" : "square.grid.2x2")
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(gridMode ? "Switch to swipe mode" : "Switch to grid mode")
                    .accessibilityValue(gridMode ? "Grid" : "Cards")
                    .accessibilityIdentifier("explore.browse-mode")
                    Button {
                        dismissVisibleFlowTip(); isSearchMode = true
                        DispatchQueue.main.async { isSearchFocused = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search").accessibilityIdentifier("explore.search.open")
                }
            }
        }
    }

    private var browseHeading: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout())
        return layout {
            if gridMode { Text("For you").font(.subheadline.weight(.medium)).foregroundStyle(.primary) }
            else {
                Label(flowStore.isRevisiting ? "Browsing history" : "For you", systemImage: flowStore.isRevisiting ? "clock.arrow.circlepath" : "sparkle")
                    .font(.subheadline.weight(.medium)).foregroundStyle(ChoraiTheme.ink)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            HStack(spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            if gridMode {
                Text("\(flowStore.browsingCards.count) NOTES").font(.caption2).tracking(1.2).foregroundStyle(.secondary)
            } else {
                if flowStore.isRevisiting {
                    Button { flowStore.resumeExploring() } label: {
                        Image(systemName: "arrow.right.to.line").font(.system(size: 20, weight: .medium))
                    }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Continue exploring").accessibilityIdentifier("flow.resume")
                }
                Button { showsHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 20, weight: .medium))
                }
                    .frame(width: 44, height: 44)
                    .disabled(flowStore.history.isEmpty)
                    .accessibilityLabel("Recently viewed").accessibilityIdentifier("flow.history")
            }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search notes and ideas", text: $searchText)
                .focused($isSearchFocused).submitLabel(.search)
                .accessibilityIdentifier("explore.search.input")
                .onSubmit(performSearch)
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Clear query")
            }
        }.padding(14).choraiGlassSurface(cornerRadius: 20)
    }

    private func cancelSearch() {
        isSearchFocused = false; isSearchMode = false; searchText = ""
        currentSearchIndex = 0; hasSubmittedSearch = false; searchManager.clearSearchResults()
    }

    @ViewBuilder
    private var searchContent: some View {
        if searchManager.isLoading {
            ProgressView("Searching…").frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("explore.search.loading")
        } else if let error = searchManager.error {
            VStack(spacing: 16) {
                Text("Search paused").font(.title3)
                Text(error.localizedDescription).font(.subheadline).foregroundStyle(ChoraiTheme.secondaryInk)
                Button("Retry", action: performSearch).buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if currentSearchIndex < searchManager.searchResults.count {
            let card = searchManager.searchResults[currentSearchIndex]
            GeometryReader { viewport in
            VStack(spacing: 8) {
                PostCard(
                    card: convertSearchCardToCard(card), cardsManager: cardsManager,
                    onShowMenu: { value in
                        currentExploreCardData = convertCardToUserCard(value)
                        isCurrentExploreCardOwned = value.isOwner ?? isOwnedByCurrentUser(authorId: value.author?.id)
                    },
                    onSwipe: { translation, ended in handleSearchSwipe(translation: CGSize(width: translation, height: 0), isEnded: ended) },
                    onAvatarTap: { selectedActorId = $0; navigateToUserProfile = true },
                    onCardTap: { selectedCardId = $0; navigateToDetail = true },
                    menuCardData: convertCardToUserCard(convertSearchCardToCard(card))
                )
                .frame(height: max(0, viewport.size.height - 52), alignment: .top)
                .id(card.id)
                HStack {
                    Button { currentSearchIndex -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(currentSearchIndex == 0).accessibilityLabel("Previous result")
                        .accessibilityIdentifier("explore.search.previous")
                    Spacer()
                    Button { currentSearchIndex += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(currentSearchIndex + 1 == searchManager.searchResults.count).accessibilityLabel("Next result")
                        .accessibilityIdentifier("explore.search.next")
                }.buttonStyle(.plain)
            }
                #if DEBUG
                .overlay(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Text("Search results").accessibilityIdentifier("explore.search.results")
                        Text(card.id).accessibilityIdentifier("explore.search.result.card-id")
                    }.font(.system(size: 1)).opacity(0.01).allowsHitTesting(false)
                }
                #endif
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(ChoraiTheme.secondaryInk)
                Text(hasSubmittedSearch ? "No results found" : "Follow a question").font(.title3)
                Text(hasSubmittedSearch ? "Try another keyword." : "Search notes and ideas. Submit to begin.")
                    .font(.subheadline).foregroundStyle(ChoraiTheme.secondaryInk)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(hasSubmittedSearch ? "explore.search.empty" : "explore.search.idle")
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
            rate: card.rate,
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

// Shared by existing filter call sites; theme changes do not alter selection.
struct FilterTag: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .foregroundStyle(isSelected ? ChoraiTheme.onAccent : ChoraiTheme.ink)
                .background(isSelected ? ChoraiTheme.accent : ChoraiTheme.raisedSurface, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct RotatingLoaderView: View {
    var body: some View { ProgressView().controlSize(.large).tint(ChoraiTheme.accent) }
}
