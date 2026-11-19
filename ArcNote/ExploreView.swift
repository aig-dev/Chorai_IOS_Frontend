import CoreFlow
import SwiftUI

struct ExploreView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @StateObject private var searchEngagement = ExploreSearchEngagement()
    @StateObject private var flowStore = FlowDeckStore(service: NetworkCoreFlowService(), onFavoriteCommitted: CardEngagementCenter.shared.publishFavorite)
    @StateObject private var searchManager = ExploreSearchManager.shared

    // 导航状态
    @State private var navigateToUserProfile = false
    @State private var selectedActorId: String? = nil
    @State private var navigateToDetail = false
    @State private var selectedCardId: String? = nil
    
    // 搜索状态
    @State private var currentSearchIndex = 0
    @State private var hasSubmittedSearch = false

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
                ZStack {
                    FlowDeckView(
                        store: flowStore,
                        isGrid: gridMode,
                        loadsPreviews: !isSearchMode,
                        onOpenDetail: { card in selectedCardId = card.id; navigateToDetail = true },
                        onOpenAuthor: { card in
                            guard let actorID = card.author?.id else { return }
                            selectedActorId = actorID; navigateToUserProfile = true
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
                                CardPlainTextPreview(card: card).font(.body).lineLimit(3)
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
        #if DEBUG
        .onAppear { publishVisibleRecommendedCardForUITest() }
        .onReceive(flowStore.$cards) { _ in publishVisibleRecommendedCardForUITest() }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .cardReadSessionDidChange)) { _ in
            showsHistory = false
            searchManager.clearSearchResults()
            hasSubmittedSearch = false
            currentSearchIndex = 0
            Task { @MainActor in
                if AuthManager.shared.cardReadSession != nil { flowStore.loadInitialIfNeeded() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cardReadInvalidated)) { event in
            guard let cardID = event.object as? String else { return }
            searchManager.invalidateRead(cardID: cardID)
            currentSearchIndex = min(currentSearchIndex, max(0, searchManager.searchResults.count - 1))
        }
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
            let displayCard = convertSearchCardToCard(card)
            let isOwner = displayCard.isOwner ?? isOwnedByCurrentUser(ownerId: displayCard.ownerActorId)
            GeometryReader { viewport in
            VStack(spacing: 8) {
                ExploreSearchResultCard(
                    card: displayCard,
                    engagement: searchEngagement,
                    menuCardData: convertCardToUserCard(displayCard),
                    isOwner: isOwner,
                    onSwipe: applySearchSwipe,
                    onAvatarTap: { selectedActorId = $0; navigateToUserProfile = true },
                    onCardTap: { selectedCardId = $0; navigateToDetail = true }
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
    
    private func applySearchSwipe(_ decision: ExploreSearchSwipe) {
        switch decision {
        case .previous:
            if currentSearchIndex > 0 { currentSearchIndex -= 1 }
        case .next:
            if currentSearchIndex + 1 < searchManager.searchResults.count { currentSearchIndex += 1 }
        case .cancel:
            break
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
    
    private func isOwnedByCurrentUser(ownerId: String?) -> Bool {
        guard let ownerId,
              let currentUserId = AuthManager.shared.currentUser?.id else {
            return false
        }
        return ownerId == currentUserId
    }
}

private struct ExploreSearchResultCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let card: Card
    @ObservedObject var engagement: ExploreSearchEngagement
    let menuCardData: UserCard
    let isOwner: Bool
    let onSwipe: (ExploreSearchSwipe) -> Void
    let onAvatarTap: (String) -> Void
    let onCardTap: (String) -> Void
    @State private var offset: CGFloat = 0
    @State private var rotation: Double = 0

    private var moreMenuLabel: some View {
        Image(systemName: "ellipsis")
            .font(.title3)
            .foregroundStyle(ChoraiTheme.ink)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 用户信息
            HStack {
                // 头像
                Button {
                    if let author = card.author { onAvatarTap(author.id) }
                } label: {
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
                        .frame(width: 38, height: 38)
                    .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Open author")
                .accessibilityIdentifier("explore.search.author.\(card.id)")

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.author?.username ?? "AI")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundColor(ChoraiTheme.ink)

                    Text(formatDate(card.createdAt))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(ChoraiTheme.ink.opacity(0.7))
                }

                Spacer()

                NativeCardActionsMenu(cardData: menuCardData, layout: .grid2x2, isOwnCard: isOwner) {
                    moreMenuLabel
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Note actions")
                .accessibilityIdentifier("explore.search.menu.\(card.id)")
            }

            ChoraiLevelBadge(rate: card.rate, compact: true)

            FlowRichPreview(card: card.asFlowCard, compact: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                onCardTap(card.id)
            }
            .highPriorityGesture(summaryDragGesture)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Read full note")
            .accessibilityIdentifier("explore.search.summary.\(card.id)")
            .accessibilityAction { onCardTap(card.id) }

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
                    .accessibilityIdentifier("explore.search.tags.\(card.id)")
                }

                // 交互统计
                HStack {
                    // 左边一个 - 收藏按钮
                    if !isOwner {
                        Button(action: {
                            engagement.toggleFavorite(for: card.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: engagement.getFavoriteState(for: card.id) ? "bookmark.fill" : "bookmark")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 26, height: 26)
                                Text("\(engagement.getFavoriteCount(for: card.id))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ChoraiTheme.ink.opacity(0.8))
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Favorite")
                        .accessibilityValue(engagement.getFavoriteState(for: card.id) ? "true" : "false")
                        .accessibilityIdentifier("card.favorite.\(card.id)")
                    }

                    Spacer()

                    // 右边两个
                    HStack(spacing: 20) {
                        Button(action: {
                            engagement.toggleLike(for: card.id)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: engagement.getLikeState(for: card.id) ? "heart.fill" : "heart")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 20, height: 20)
                                Text("\(engagement.getLikeCount(for: card.id))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ChoraiTheme.ink.opacity(0.8))
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .disabled(engagement.isLikeMutationInFlight(for: card.id))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(engagement.getLikeState(for: card.id) ? "Unlike" : "Like")
                        .accessibilityValue(engagement.getLikeState(for: card.id) ? "true" : "false")
                        .accessibilityIdentifier("card.like.\(card.id)")

                        CommentButton(cardId: card.id, searchEngagement: engagement)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }

                if let error = engagement.likeError(for: card.id) {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ChoraiTheme.ink.opacity(0.72))
                        .accessibilityIdentifier("card.like.error.\(card.id)")
                }
            }
        }
        .padding(.vertical, 24)
        .adaptiveContentGutter()
        .frame(maxHeight: .infinity)
        .choraiCardLevel(rate: card.rate, showsChora: false, cornerRadius: 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("explore.search.surface.\(card.id)")
        .offset(x: offset)
        .rotationEffect(.degrees(rotation))
        #if DEBUG
        .onAppear {
            NotificationCenter.default.post(
                name: NSNotification.Name("ExploreVisibleRecommendedCardChanged"),
                object: nil,
                userInfo: ["cardId": card.id]
            )
        }
        #endif
    }

    private var summaryDragGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = value.translation.width
                rotation = reduceMotion ? 0 : Double(value.translation.width / 34)
            }
            .onEnded { value in
                let decision = ExploreSearchSwipe.resolve(
                    horizontal: Double(value.translation.width),
                    vertical: Double(value.translation.height)
                )
                onSwipe(decision)
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
                    offset = 0
                    rotation = 0
                }
            }
    }

    // MARK: - 辅助函数
    private func formatDate(_ dateString: String) -> String {
        CardTimestamp.dateOnly(from: dateString)
    }

}

// 标签组件
private struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(ChoraiTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.white.opacity(0.1))
            )
    }
}

#Preview {
    ExploreView(
        showSideMenu: .constant(false),
        onSpark: { _ in }
    )
}

struct RotatingLoaderView: View {
    var body: some View { ProgressView().controlSize(.large).tint(ChoraiTheme.accent) }
}
