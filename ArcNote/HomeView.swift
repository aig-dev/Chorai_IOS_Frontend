import CoreFlow
import SwiftUI

struct HomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var showSideMenu: Bool
    let refreshID: UUID
    let committedCardID: String?
    var onboardingStore: OnboardingGuideStore?
    var contextualTipStore: ContextualGuideTipStore?
    let isOnboardingLibrarySurfaceActive: Bool
    let onNoteCreated: (String, String) -> Void
    let onCardRouteDismissed: (CardNavigationDismissal) -> Void
    let onCardRoutePresentationChanged: (Bool) -> Void
    let onLibrarySurfaceVisibilityChanged: (Bool) -> Void
    @State private var selectedSegment = 0 // 0: Notes, 1: AI

    @State private var showPopupMenu = false
    @State private var popupMenuLayout: PopupMenuLayout = .grid2x2
    @State private var showFilterTags = false
    @State private var selectedFilter = "Latest Edited" // 默认筛选
    @State private var librarySearchSession = LibrarySearchSession()
    @StateObject private var cardsManager = HomeCardsManager()
    @StateObject private var librarySearchManager = LibrarySearchManager()
    @FocusState private var isLibrarySearchFocused: Bool
    @State private var currentCardId: String? = nil
    @State private var currentMenuCardData: UserCard? = nil
    @StateObject private var favoritesManager = FavoritesManager.shared
    @State private var showDeleteConfirmation = false
    @State private var cardToDelete: UserCard? = nil
    @State private var animateDeleteConfirmation = false
    @State private var isDeletingCard = false
    @State private var deleteCardError: String?
    @State private var navigateToDetail = false
    @State private var navigateToEdit = false
    @State private var selectedCardId: String? = nil
    @State private var navigateToUserProfile = false
    @State private var selectedActorId: String? = nil
    @State private var handledCommittedCardID: String?

    init(
        showSideMenu: Binding<Bool>,
        refreshID: UUID,
        committedCardID: String? = nil,
        onboardingStore: OnboardingGuideStore? = nil,
        contextualTipStore: ContextualGuideTipStore? = nil,
        isOnboardingLibrarySurfaceActive: Bool = false,
        onNoteCreated: @escaping (String, String) -> Void = { _, _ in },
        onCardRouteDismissed: @escaping (CardNavigationDismissal) -> Void = { _ in },
        onCardRoutePresentationChanged: @escaping (Bool) -> Void = { _ in },
        onLibrarySurfaceVisibilityChanged: @escaping (Bool) -> Void = { _ in },
        librarySearchManager: LibrarySearchManager = LibrarySearchManager()
    ) {
        _showSideMenu = showSideMenu
        _librarySearchManager = StateObject(
            wrappedValue: librarySearchManager
        )
        self.refreshID = refreshID
        self.committedCardID = committedCardID
        self.onboardingStore = onboardingStore
        self.contextualTipStore = contextualTipStore
        self.isOnboardingLibrarySurfaceActive =
            isOnboardingLibrarySurfaceActive
        self.onNoteCreated = onNoteCreated
        self.onCardRouteDismissed = onCardRouteDismissed
        self.onCardRoutePresentationChanged = onCardRoutePresentationChanged
        self.onLibrarySurfaceVisibilityChanged = onLibrarySurfaceVisibilityChanged
    }

    // MARK: - 分段控制器背景
    private func segmentBackground(for segment: Int) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(selectedSegment == segment ? Color.white.opacity(0.2) : Color.clear)
            .overlay(selectedSegment == segment ? segmentTopLeftHighlight : nil)
            .overlay(selectedSegment == segment ? segmentBottomRightHighlight : nil)
            .overlay(selectedSegment == segment ? segmentTopEdgeHighlight : nil)
            .overlay(selectedSegment == segment ? segmentBottomEdgeHighlight : nil)
    }
    
    // MARK: - 获取当前卡片数据
    private func getCurrentCard() -> UserCard? {
        guard let cardId = currentCardId else { 
            return nil 
        }
        let card = cardsManager.cards.first { $0.id == cardId }
        if let card = card {
            print("找到卡片 id=\(card.id), isPublic=\(card.isPublic), isPinned=\(card.isPinned)")
        } else {
            print("未找到卡片 id=\(cardId)")
        }
        return card
    }
    
    // MARK: 加载用户卡片列表
    private func loadUserCards() {
        // 使用默认排序（Latest Edited）
        cardsManager.loadUserCards(refresh: true, sortBy: "updated_at", sortOrder: "desc")
    }

    private func presentCommittedCardIfNeeded(_ value: String?) {
        guard let cardID = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !cardID.isEmpty, handledCommittedCardID != cardID else {
            return
        }

        handledCommittedCardID = cardID
        if librarySearchSession.isActive {
            exitLibrarySearch()
        }
        selectedSegment = 0
        cardsManager.promoteCommittedCard(id: cardID)
    }

    // MARK: 应用排序
    private func applySort(sortBy: String, sortOrder: String) {
        print("应用排序: sortBy=\(sortBy), sortOrder=\(sortOrder)")
        if librarySearchSession.submittedQuery != nil {
            librarySearchManager.applySort(selectedSortOption)
            return
        }
        if selectedSegment == 0 {
            // NotesList 排序
            cardsManager.loadUserCards(refresh: true, sortBy: sortBy, sortOrder: sortOrder)
        } else {
            // Favorites list follows the Go API contract: page/per_page only.
            favoritesManager.loadFavorites(refresh: true)
        }
    }

    private var selectedSortOption: LibrarySortOption {
        LibrarySortOption(rawValue: selectedFilter) ?? .latestEdited
    }

    private var isLibraryTipVisible: Bool {
        contextualTipStore?.isVisible(
            .libraryCreate,
            onboardingState: onboardingStore?.contextualTipState,
            targetIsVisible: selectedSegment == 0
                && librarySearchSession.submittedQuery == nil
        ) ?? false
    }

    private var isOnboardingLibrarySurfacePresented: Bool {
        isOnboardingLibrarySurfaceActive
            && !showPopupMenu
            && !showFilterTags
            && !showDeleteConfirmation
            && !navigateToDetail
            && !navigateToEdit
            && !navigateToUserProfile
    }

    private func dismissLibraryTipIfVisible() {
        if isLibraryTipVisible {
            contextualTipStore?.dismiss(
                .libraryCreate,
                onboardingState: onboardingStore?.contextualTipState,
                targetIsVisible: true
            )
        }
        if contextualTipStore?.isVisible(
            .libraryMergeEntry,
            onboardingState: onboardingStore?.contextualTipState,
            targetIsVisible: !cardsManager.cards.isEmpty
        ) == true {
            contextualTipStore?.dismiss(
                .libraryMergeEntry,
                onboardingState: onboardingStore?.contextualTipState,
                targetIsVisible: true
            )
        }
    }

    private var librarySearchQuery: Binding<String> {
        Binding(
            get: { librarySearchSession.draftQuery },
            set: { value in
                librarySearchSession.updateDraft(value)
                if librarySearchSession.submittedQuery == nil {
                    librarySearchManager.clear()
                }
            }
        )
    }

    private func enterLibrarySearch() {
        dismissLibraryTipIfVisible()
        let scope: LibrarySearchScope = selectedSegment == 0
            ? .notes
            : .collect
        showFilterTags = false

        if reduceMotion {
            librarySearchSession.enter(scope: scope)
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                librarySearchSession.enter(scope: scope)
            }
        }

        DispatchQueue.main.async {
            isLibrarySearchFocused = true
        }
    }

    private func exitLibrarySearch() {
        isLibrarySearchFocused = false
        showFilterTags = false
        librarySearchManager.clear()

        if reduceMotion {
            librarySearchSession.exit()
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                librarySearchSession.exit()
            }
        }
    }

    private func clearLibrarySearch() {
        librarySearchManager.clear()
        librarySearchSession.clear()
        DispatchQueue.main.async {
            isLibrarySearchFocused = true
        }
    }

    private func submitLibrarySearch() {
        guard let query = librarySearchSession.submit(),
              let scope = librarySearchSession.scope else {
            librarySearchManager.clear()
            return
        }

        isLibrarySearchFocused = false
        librarySearchManager.search(
            query: query,
            scope: scope,
            sort: selectedSortOption
        )
    }

    private func retryLibrarySearch() {
        guard let query = librarySearchSession.submittedQuery,
              let scope = librarySearchSession.scope else {
            return
        }
        librarySearchManager.search(
            query: query,
            scope: scope,
            sort: selectedSortOption
        )
    }
    
    // MARK: - 分段控制器高光效果
    private var segmentTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 16)
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
    
    private var segmentBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 16)
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
    
    private var segmentTopEdgeHighlight: some View {
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
    
    private var segmentBottomEdgeHighlight: some View {
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

    private var libraryHeader: some View {
        ZStack {
            HStack {
                Button(action: {
                    dismissLibraryTipIfVisible()
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSideMenu = true
                    }
                }) {
                    Image("menu")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Open menu")
                .accessibilityIdentifier("side-menu.open")

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dismissLibraryTipIfVisible()
                            showFilterTags.toggle()
                        }
                    }) {
                        Image("filter")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Library filters")
                    .accessibilityIdentifier("home.filter")

                    Button(action: enterLibrarySearch) {
                        Image("search")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Search Library")
                    .accessibilityHint("Replaces the Library header with a search field")
                    .accessibilityIdentifier("home.search")
                }
            }

            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        dismissLibraryTipIfVisible()
                        selectedSegment = 0
                    }
                }) {
                    Image(selectedSegment == 0 ? "notes_active" : "notes")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .frame(width: 50, height: 32)
                        .background(segmentBackground(for: 0))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Notes")
                .accessibilityIdentifier("home.segment.notes")

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        dismissLibraryTipIfVisible()
                        selectedSegment = 1
                    }
                }) {
                    Image(selectedSegment == 1 ? "collect_active" : "collect")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .frame(width: 50, height: 32)
                        .background(segmentBackground(for: 1))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Collect")
                .accessibilityIdentifier("home.segment.collect")
            }
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
    }

    private var librarySearchHeader: some View {
        HStack(spacing: 8) {
            Button(action: exitLibrarySearch) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(minWidth: 44, minHeight: 52)
            }
            .frame(minWidth: 44, minHeight: 52)
            .accessibilityLabel("Close Library search")
            .accessibilityIdentifier("home.search.close")

            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .accessibilityHidden(true)

                TextField("Search your Library", text: librarySearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.white)
                    .tint(Color.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .focused($isLibrarySearchFocused)
                    .onSubmit {
                        submitLibrarySearch()
                    }
                    .accessibilityLabel("Search your Library")
                    .accessibilityIdentifier("home.search.input")

                if !librarySearchSession.draftQuery.isEmpty {
                    Button(action: clearLibrarySearch) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.58))
                            .frame(minWidth: 44, minHeight: 52)
                    }
                    .frame(minWidth: 44, minHeight: 52)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("home.search.clear")
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFilterTags.toggle()
                    }
                }) {
                    Image("filter")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 21, height: 21)
                        .frame(minWidth: 44, minHeight: 52)
                }
                .frame(minWidth: 44, minHeight: 52)
                .accessibilityLabel("Search filters")
                .accessibilityHint("Shows Library sort options")
                .accessibilityIdentifier("home.search.filter")
            }
            .frame(minHeight: 52)
            .padding(.trailing, 4)
            .background(librarySearchInputBackground)
        }
    }

    @ViewBuilder
    private var librarySearchInputBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        if reduceTransparency {
            shape
                .fill(Color(red: 0.12, green: 0.09, blue: 0.20))
                .overlay(shape.stroke(Color.white.opacity(0.3), lineWidth: 1))
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18).clipShape(shape))
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.52),
                                Color.white.opacity(0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
        }
    }

    var body: some View {
        KeyboardStableViewport(isFocused: isLibrarySearchFocused) { geometry in
            VStack(spacing: 0) {
            // 顶部导航栏
            Group {
                if librarySearchSession.isActive {
                    librarySearchHeader
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    libraryHeader
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .adaptiveContentGutter()
            .padding(.top, 60)

            if !librarySearchSession.isActive,
               let onboardingStore {
                OnboardingGuideLine(
                    store: onboardingStore,
                    allowedStates: [
                        "deepen_signal",
                        "elicit_signal",
                        "product_merge_intro",
                        "product_merge_preview",
                        "product_library_intro",
                        "build_ignite"
                    ]
                )
                .adaptiveContentGutter()
                .padding(.top, 10)
            }
            
            // 筛选标签
            if showFilterTags {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        HomeFilterTag(title: "Latest Edited", isSelected: selectedFilter == "Latest Edited") {
                            dismissLibraryTipIfVisible()
                            selectedFilter = "Latest Edited"
                            applySort(sortBy: "updated_at", sortOrder: "desc")
                        }
                        .frame(width: 120)
                        HomeFilterTag(title: "Latest Added", isSelected: selectedFilter == "Latest Added") {
                            dismissLibraryTipIfVisible()
                            selectedFilter = "Latest Added"
                            applySort(sortBy: "created_at", sortOrder: "desc")
                        }
                        .frame(width: 120)
                        HomeFilterTag(title: "Rarity-High Low", isSelected: selectedFilter == "Rarity-High Low") {
                            dismissLibraryTipIfVisible()
                            selectedFilter = "Rarity-High Low"
                            applySort(sortBy: "rate", sortOrder: "desc")
                        }
                        .frame(width: 140)
                        HomeFilterTag(title: "Rarity-Low High", isSelected: selectedFilter == "Rarity-Low High") {
                            dismissLibraryTipIfVisible()
                            selectedFilter = "Rarity-Low High"
                            applySort(sortBy: "rate", sortOrder: "asc")
                        }
                        .frame(width: 140)
                    }
                    .adaptiveContentGutter()
                }
                .padding(.top, 10)
            }
            
            // 主要内容区域
            if let submittedQuery = librarySearchSession.submittedQuery,
               let searchScope = librarySearchSession.scope {
                LibrarySearchResultsView(
                    scope: searchScope,
                    manager: librarySearchManager,
                    cardsManager: cardsManager,
                    query: submittedQuery,
                    onShowMenu: { result in
                        currentCardId = result.id
                        currentMenuCardData = result.card
                        popupMenuLayout = searchScope == .notes
                            ? .grid3x3
                            : .grid3x2
                        showPopupMenu = true
                    },
                    onCardTap: { cardID in
                        selectedCardId = cardID
                        DispatchQueue.main.async {
                            if searchScope == .notes {
                                navigateToEdit = true
                            } else {
                                navigateToDetail = true
                            }
                        }
                    },
                    onAvatarTap: { authorID in
                        selectedActorId = authorID
                        DispatchQueue.main.async {
                            navigateToUserProfile = true
                        }
                    },
                    onUnfavorite: { cardID in
                        favoritesManager.unfavoriteCard(cardId: cardID) { result in
                            if case .success = result {
                                favoritesManager.removeFavoriteFromList(cardId: cardID)
                                librarySearchManager.remove(cardID: cardID)
                            }
                        }
                    },
                    onRetry: retryLibrarySearch
                )
            } else if selectedSegment == 0 {
                // Notes 列表
                NotesListView(
                    cardsManager: cardsManager,
                    currentCardId: $currentCardId,
                    selectedCardId: $selectedCardId,
                    navigateToDetail: $navigateToDetail,
                    navigateToEdit: $navigateToEdit,
                    onShowMenu: { cardData in
                        // 设置当前卡片数据
                        currentMenuCardData = cardData
                        popupMenuLayout = .grid3x3
                        showPopupMenu = true
                    },
                    onboardingStore: onboardingStore,
                    contextualTipStore: contextualTipStore,
                    onNoteCreated: onNoteCreated
                )
            } else {
                // Collect 列表
                AIListView(
                    onShowMenu: { cardId in
                    // 找到对应的收藏卡片数据
                    if let favorite = favoritesManager.favorites.first(where: { $0.id == cardId }) {
                        let tempCard = UserCard(
                            id: cardId,
                            title: favorite.title ?? "",
                            content: favorite.content,
                            contentJSON: favorite.contentJSON,
                            backgroundMediaRef: favorite.backgroundMediaRef,
                            contentHash: "",
                            isPublic: false, // 收藏的卡片默认设为私有
                            tags: favorite.tags ?? [],
                            createdAt: favorite.createdAt,
                            updatedAt: favorite.createdAt,
                            likeCount: 0,
                            commentCount: 0,
                            isLiked: false,
                            isPinned: favorite.isPinned,
                            pinnedAt: favorite.pinnedAt,
                            isFavorited: true,
                                favoriteCount: favorite.favoriteCount ?? 0,
                                rate: favorite.rate
                        )
                        // 设置当前卡片数据并显示菜单
                        currentCardId = cardId
                        currentMenuCardData = tempCard
                        popupMenuLayout = .grid3x2
                        showPopupMenu = true
                    }
                    },
                    onAvatarTap: { authorId in
                        selectedActorId = authorId
                        DispatchQueue.main.async {
                            navigateToUserProfile = true
                        }
                    }
                )
            }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .top
            )
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.home.content")
        .overlay(alignment: .topLeading) {
            if isOnboardingLibrarySurfacePresented {
                LibraryOnboardingSurfacePresentationReporter(
                    onVisibilityChanged:
                        onLibrarySurfaceVisibilityChanged
                )
                .id(onboardingStore?.session?.sessionID ?? "no-session")
            }
        }
        .popupMenu(
            isPresented: $showPopupMenu,
            layout: popupMenuLayout,
            cardData: selectedSegment == 0
                ? (getCurrentCard() ?? currentMenuCardData)
                : currentMenuCardData,
            isOwnCard: librarySearchSession.scope == .notes
                || (!librarySearchSession.isActive && selectedSegment == 0),
            onRouteDismissed: onCardRouteDismissed,
            onRoutePresentationChanged: onCardRoutePresentationChanged
        )
        .onAppear {
            // 使用默认排序（Latest Edited）
            cardsManager.loadUserCards(refresh: true, sortBy: "updated_at", sortOrder: "desc")
            presentCommittedCardIfNeeded(committedCardID)
        }
        .onDisappear {
            onLibrarySurfaceVisibilityChanged(false)
        }
        .onChange(of: refreshID) { _ in
            cardsManager.loadUserCards(refresh: true, sortBy: "updated_at", sortOrder: "desc")
        }
        .onChange(of: committedCardID) { cardID in
            presentCommittedCardIfNeeded(cardID)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowCardMenu"))) { notification in
            if let userInfo = notification.userInfo,
               let cardData = userInfo["cardData"] as? UserCard,
               let layoutString = userInfo["layout"] as? String {
                // 设置当前卡片数据
                currentCardId = cardData.id
                currentMenuCardData = cardData
                
                // 设置菜单布局
                switch layoutString {
                case "grid3x2":
                    popupMenuLayout = .grid3x2
                case "grid3x3":
                    popupMenuLayout = .grid3x3
                default:
                    popupMenuLayout = .grid2x2
                }
                
                // 显示菜单
                showPopupMenu = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToNotesList"))) { _ in
            // 切换到NotesList (selectedSegment = 0)
            if librarySearchSession.isActive {
                exitLibrarySearch()
            }
            selectedSegment = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToAIList"))) { _ in
            // 切换到AIList (selectedSegment = 1)
            if librarySearchSession.isActive {
                exitLibrarySearch()
            }
            selectedSegment = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeleteCard"))) { _ in
            guard let cardId = currentCardId else {
                print("没有找到要删除的卡片ID")
                return
            }
            
            // 找到要删除的卡片数据
            if let card = cardsManager.cards.first(where: { $0.id == cardId })
                ?? currentMenuCardData.flatMap({ $0.id == cardId ? $0 : nil }) {
                cardToDelete = card
                deleteCardError = nil
                showDeleteConfirmation = true
                print("显示删除确认弹窗: cardId=\(cardId)")
            } else {
                print("未找到要删除的卡片数据: cardId=\(cardId)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleCardVisibility"))) { notification in
            guard let userInfo = notification.userInfo,
                  let cardId = userInfo["cardId"] as? String,
                  let _ = userInfo["isPublic"] as? Bool else {
                print("通知缺少必要参数")
                return
            }
            
            cardsManager.toggleCardVisibility(
                cardId: cardId,
                fallbackCard: currentMenuCardData
            ) { result in
                switch result {
                case .success:
                    print("卡片可见性切换成功")
                    if librarySearchSession.isActive {
                        retryLibrarySearch()
                    }
                case .failure(let error):
                    print("卡片可见性切换失败: \(error.localizedDescription)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleCardPin"))) { notification in
            guard let userInfo = notification.userInfo,
                  let cardId = userInfo["cardId"] as? String,
                  let _ = userInfo["isPinned"] as? Bool else {
                print("通知缺少必要参数")
                return
            }
            
            
            // 执行切换置顶状态操作
            cardsManager.toggleCardPin(
                cardId: cardId,
                fallbackCard: currentMenuCardData
            ) { result in
                switch result {
                case .success:
                    print("卡片置顶状态切换成功")
                    if librarySearchSession.isActive {
                        retryLibrarySearch()
                    }
                case .failure(let error):
                    print("卡片置顶状态切换失败: \(error.localizedDescription)")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CardTapped"))) { notification in
            guard let userInfo = notification.userInfo,
                  let cardId = userInfo["cardId"] as? String else {
                return
            }
            
            selectedCardId = cardId
            DispatchQueue.main.async {
                navigateToDetail = false
                navigateToDetail = true
                print("navigateToDetail: \(navigateToDetail) \(cardId)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseAllPopups"))) { _ in
            showPopupMenu = false
            showFilterTags = false
        }
        .overlay(
            // 确认删除对话框
            Group {
                if showDeleteConfirmation {
                    ZStack {
                        // 背景遮罩 - 带渐变动画
                        Color.black
                            .opacity(animateDeleteConfirmation ? 0.5 : 0)
                            .ignoresSafeArea()
                            .onTapGesture {
                                guard !isDeletingCard else { return }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    animateDeleteConfirmation = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showDeleteConfirmation = false
                                        cardToDelete = nil
                                        deleteCardError = nil
                                    }
                                }
                            }
                        
                        // 对话框 - 带渐变动画
                        VStack(spacing: 20) {
                            // 关闭按钮
                            HStack {
                                Spacer()
                                Button(action: {
                                    guard !isDeletingCard else { return }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        animateDeleteConfirmation = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showDeleteConfirmation = false
                                            cardToDelete = nil
                                            deleteCardError = nil
                                        }
                                    }
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                                .accessibilityIdentifier("home.delete.close")
                            }
                            
                            // 确认文本
                            Text("Confirm delete this note?")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            if let deleteCardError {
                                Text(deleteCardError)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.red.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .accessibilityIdentifier("home.delete.error")
                            }
                            
                            // 按钮
                            HStack(spacing: 16) {
                                // 取消按钮
                                Button(action: {
                                    guard !isDeletingCard else { return }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        animateDeleteConfirmation = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            showDeleteConfirmation = false
                                            cardToDelete = nil
                                            deleteCardError = nil
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 16, weight: .medium))
                                        Text("Cancel")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.gray.opacity(0.3))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 20)
                                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                                .disabled(isDeletingCard)
                                .accessibilityIdentifier("home.delete.cancel")
                                
                                // 确认删除按钮
                                Button(action: {
                                    guard let card = cardToDelete, !isDeletingCard else { return }
                                    isDeletingCard = true
                                    deleteCardError = nil
                                    cardsManager.deleteCard(cardId: card.id) { result in
                                        isDeletingCard = false
                                        switch result {
                                        case .success:
                                            print("卡片删除成功")
                                            librarySearchManager.remove(cardID: card.id)
                                            currentCardId = nil
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                animateDeleteConfirmation = false
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    showDeleteConfirmation = false
                                                    cardToDelete = nil
                                                    deleteCardError = nil
                                                }
                                            }
                                        case .failure(let error):
                                            print("卡片删除失败: \(error.localizedDescription)")
                                            deleteCardError = "Couldn’t move this note to Trash. Please try again."
                                        }
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        if isDeletingCard {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .medium))
                                        }
                                        Text("Yes")
                                            .font(.system(size: 16, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(Color.red)
                                    )
                                }
                                .disabled(isDeletingCard)
                                .accessibilityIdentifier("home.delete.confirm")
                            }
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial.opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                )
                        )
                        .padding(.horizontal, 20)
                        .opacity(animateDeleteConfirmation ? 1 : 0)
                        .scaleEffect(animateDeleteConfirmation ? 1 : 0.8)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home.delete.confirmation")
                    }
                    .onAppear {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            animateDeleteConfirmation = true
                        }
                    }
                }
            }
        )
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
        .navigationDestination(isPresented: $navigateToUserProfile) {
            if let actorId = selectedActorId {
                UserProfileView(actorId: actorId)
            } else {
                EmptyView()
            }
        }
    }
}

private struct LibraryOnboardingSurfacePresentationReporter: View {
    let onVisibilityChanged: (Bool) -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }
                onVisibilityChanged(true)
            }
            .onDisappear {
                onVisibilityChanged(false)
            }
    }
}

// MARK: - Notes 列表视图
struct NotesListView: View {
    @ObservedObject var cardsManager: HomeCardsManager
    @Binding var currentCardId: String?
    @Binding var selectedCardId: String?
    @Binding var navigateToDetail: Bool
    @Binding var navigateToEdit: Bool
    let onShowMenu: (UserCard) -> Void
    var onboardingStore: OnboardingGuideStore?
    var contextualTipStore: ContextualGuideTipStore?
    let onNoteCreated: (String, String) -> Void
    @State private var navigateToCreate = false

    private var isLibraryTipVisible: Bool {
        contextualTipStore?.isVisible(
            .libraryCreate,
            onboardingState: onboardingStore?.contextualTipState,
            targetIsVisible: true
        ) ?? false
    }

    private func dismissLibraryTipIfVisible() {
        if isLibraryTipVisible {
            contextualTipStore?.dismiss(
                .libraryCreate,
                onboardingState: onboardingStore?.contextualTipState,
                targetIsVisible: true
            )
        }
        contextualTipStore?.dismiss(
            .libraryMergeEntry,
            onboardingState: onboardingStore?.contextualTipState,
            targetIsVisible: !cardsManager.cards.isEmpty
        )
    }

    private func handleCreatedNote(cardID: String, content: String) {
        let shouldRevealNextOnboardingStep =
            onboardingStore?.contextualTipState == "elicit_signal"
        onNoteCreated(cardID, content)
        if shouldRevealNextOnboardingStep {
            navigateToCreate = false
        }
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: 20) {
            if cardsManager.isLoading && cardsManager.cards.isEmpty {
                VStack {
                            Spacer(minLength: 0)
                            RotatingLoaderView()
                                .padding(.top, 120)
                            Spacer(minLength: 0)
                }
                        .frame(maxWidth: .infinity)
            } else if cardsManager.cards.isEmpty {
                        VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                            Text("Your Chorai is empty")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                            Text("spark it to life by tapping this + in the bottom right")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 160)
            } else {
                        ForEach(Array(cardsManager.cards.enumerated()), id: \.element.id) { index, entry in
                            let card = entry
                            NotesCard(
                                card: card,
                                onShowMenu: { cardData in
                                    currentCardId = cardData.id
                                    print("设置当前卡片ID: \(cardData.id)")
                                    onShowMenu(cardData)
                                },
                                cardsManager: cardsManager,
                                showMergeGuide: index == 0,
                                onboardingState: onboardingStore?.contextualTipState,
                                contextualTipStore: contextualTipStore,
                                onCardTap: { cardId in
                                    print("收到卡片点击回调: cardId=\(cardId)")
                                    selectedCardId = cardId
                                    DispatchQueue.main.async {
                                        navigateToEdit = true
                                        print("navigateToEdit: \(navigateToEdit)")
                                    }
                                }
                            )
                            .onAppear {
                                if index == cardsManager.cards.count - 1,
                                   cardsManager.hasMoreData,
                                   !cardsManager.isLoading {
                                    cardsManager.loadMoreCards()
                                }
                            }
                        }
                        
                        if cardsManager.isLoading && !cardsManager.cards.isEmpty {
                            HStack {
                                Spacer()
                                RotatingLoaderView()
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    dismissLibraryTipIfVisible()
                    cardsManager.refreshCards()
                }
                .onTapGesture {
                    dismissLibraryTipIfVisible()
                }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12) {
                        if let contextualTipStore {
                            ContextualGuideCallout(
                                store: contextualTipStore,
                                tip: .libraryCreate,
                                onboardingState: onboardingStore?.contextualTipState,
                                targetIsVisible: true
                            )
                        }

                        ZStack {
                            Button {
                                contextualTipStore?.complete(
                                    .libraryCreate,
                                    onboardingState: onboardingStore?.contextualTipState,
                                    targetIsVisible: true
                                )
                                dismissLibraryTipIfVisible()
                                navigateToCreate = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial.opacity(0.3))
                                        .frame(width: 56, height: 56)
                                        .overlay(createButtonTopLeftHighlight)
                                        .overlay(createButtonBottomRightHighlight)
                                        .overlay(createButtonTopEdgeHighlight)
                                        .overlay(createButtonBottomEdgeHighlight)

                                    Image(systemName: "plus")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .anchorPreference(
                                key: MergeTaskRailAnchorPreferenceKey.self,
                                value: .bounds,
                                transform: { $0 }
                            )
                            .accessibilityIdentifier("note.create")
                            .accessibilityHint("Create a Library note")

                            ContextualGuideTargetHalo(isVisible: isLibraryTipVisible)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 130)
                }
            }
        }
        .navigationDestination(isPresented: $navigateToCreate) {
            NewNoteView(onCreated: handleCreatedNote)
        }
        .onDisappear {
            dismissLibraryTipIfVisible()
        }
    }
    
    // MARK: - 创建按钮高光效果
    private var createButtonTopLeftHighlight: some View {
        Circle()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .topLeading,
                            startRadius: 5,
                            endRadius: 25
                        )
                    )
            )
    }
    
    private var createButtonBottomRightHighlight: some View {
        Circle()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color.clear],
                            center: .bottomTrailing,
                            startRadius: 5,
                            endRadius: 25
                        )
                    )
            )
    }
    
    private var createButtonTopEdgeHighlight: some View {
        Circle()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.1)
                        )
                    )
            )
    }
    
    private var createButtonBottomEdgeHighlight: some View {
        Circle()
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.1)
                        )
                    )
            )
    }
}

// MARK: - AI 列表视图
struct AIListView: View {
    let onShowMenu: (String) -> Void
    let onAvatarTap: ((String) -> Void)?
    @StateObject private var favoritesManager = FavoritesManager.shared
    
    init(onShowMenu: @escaping (String) -> Void, onAvatarTap: ((String) -> Void)? = nil) {
        self.onShowMenu = onShowMenu
        self.onAvatarTap = onAvatarTap
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if favoritesManager.isLoading && favoritesManager.favorites.isEmpty {
                    VStack {
                        Spacer(minLength: 0)
                        RotatingLoaderView()
                            .padding(.top, 120)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                } else if favoritesManager.favorites.isEmpty {
                    VStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.white.opacity(0.5))
                        Text("No favorites yet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 160)
                } else {
                    ForEach(Array(favoritesManager.favorites.enumerated()), id: \.element.id) { index, favorite in
                        HomePostCard(
                            profileImage: favorite.author.avatar ?? "",
                            name: favorite.author.username,
                            time: formatFavoriteDate(favorite.favoritedAt),
                            content: favorite.content,
                            contentJSON: favorite.contentJSON,
                            backgroundMediaRef: favorite.backgroundMediaRef,
                            tags: favorite.tags ?? [],
                            showSpark: true,
                            favoriteCount: favorite.favoriteCount ?? 0,
                            cardId: favorite.id,
                            rate: favorite.rate,
                            authorId: favorite.author.id,
                            onShowMenu: { cardId in
                                onShowMenu(cardId)
                            },
                            onCardTap: { cardId in
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("CardTapped"),
                                    object: nil,
                                    userInfo: ["cardId": cardId]
                                )
                            },
                            onUnfavorite: { cardId in
                                favoritesManager.unfavoriteCard(cardId: cardId) { result in
                                    switch result {
                                    case .success:
                                        print("取消收藏成功: cardId=\(cardId)")
                                        favoritesManager.removeFavoriteFromList(cardId: cardId)
                                    case .failure(let error):
                                        print("取消收藏失败: \(error.localizedDescription)")
                                    }
                                }
                            },
                            onAvatarTap: { authorId in
                                onAvatarTap?(authorId)
                            }
                        )
                        .onAppear {
                            if index == favoritesManager.favorites.count - 1,
                               favoritesManager.hasMoreData,
                               !favoritesManager.isLoading {
                            favoritesManager.loadMoreFavorites()
                            }
                        }
                    }
                    
                    if favoritesManager.isLoading && !favoritesManager.favorites.isEmpty {
                        HStack {
                            Spacer()
                            RotatingLoaderView()
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 100)
        }
        .refreshable {
            favoritesManager.refreshFavorites()
        }
        .onAppear {
            if favoritesManager.favorites.isEmpty {
                favoritesManager.loadFavorites(refresh: true)
            }
        }
    }
    
    private func formatFavoriteDate(_ dateString: String) -> String {
        CardTimestamp.dateOnly(from: dateString)
    }
}

// MARK: - Library card background
struct LibraryCardBackgroundSurface<Fallback: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let backgroundMediaRef: String?
    let rate: Int
    @ViewBuilder let fallback: () -> Fallback

    init(
        backgroundMediaRef: String?,
        rate: Int = 1,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.backgroundMediaRef = backgroundMediaRef
        self.rate = rate
        self.fallback = fallback
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var backgroundURL: URL? {
        guard let backgroundMediaRef else { return nil }
        let trimmedRef = backgroundMediaRef.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedRef.isEmpty else { return nil }
        let normalizedRef = trimmedRef.hasPrefix("chorai-assets/")
            ? "/\(trimmedRef)"
            : trimmedRef
        return CardEditingMediaURLResolver.resolve(
            normalizedRef,
            canonicalizeRelativePath: APIConfiguration.resourceURLString
        )
    }

    private var veilOpacity: Double {
        LibraryCardReadabilityPolicy.veilOpacity(
            reduceTransparency: reduceTransparency,
            increasedContrast: contrast == .increased
        )
    }

    private var bottomShadeOpacity: Double {
        reduceTransparency || contrast == .increased ? 0.30 : 0.22
    }

    private var levelStyle: CardLevelStyle {
        CardLevelStyle(rate: rate)
    }

    private var rateGlowOpacity: Double {
        if reduceTransparency { return 0.14 }
        return contrast == .increased ? 0.24 : 0.22
    }

    private var rateBorderOpacity: Double {
        contrast == .increased ? 0.52 : 0.32
    }

    @ViewBuilder
    private var rateTreatment: some View {
        if let rateAccent = levelStyle.materialAccentColor {
            GeometryReader { geometry in
                RadialGradient(
                    colors: [
                        rateAccent.opacity(rateGlowOpacity),
                        rateAccent.opacity(rateGlowOpacity * 0.32),
                        Color.clear,
                    ],
                    center: .top,
                    startRadius: 1,
                    endRadius: max(
                        geometry.size.width,
                        geometry.size.height
                    ) * 0.86
                )
            }

            shape.stroke(
                rateAccent.opacity(rateBorderOpacity),
                lineWidth: contrast == .increased ? 1.5 : 1
            )
        }
    }

    var body: some View {
        ZStack {
            fallback()

            if let backgroundURL {
                GeometryReader { geometry in
                    AsyncImage(
                        url: backgroundURL,
                        transaction: Transaction(
                            animation: reduceMotion
                                ? nil
                                : .easeOut(duration: 0.22)
                        )
                    ) { phase in
                        switch phase {
                        case .success(let image):
                            ZStack {
                                image
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFill()
                                    .saturation(0.88)
                                    .frame(
                                        width: geometry.size.width,
                                        height: geometry.size.height
                                    )
                                    .clipped()

                                ZStack {
                                    Color.black.opacity(veilOpacity)
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.08),
                                            Color.clear,
                                            Color.black.opacity(bottomShadeOpacity),
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }

                                shape
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            }
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                            .transition(.opacity)
                        case .empty, .failure:
                            Color.clear
                        @unknown default:
                            Color.clear
                        }
                    }
                }
            }

            rateTreatment
        }
        .clipShape(shape)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Notes 卡片组件
struct NotesCard: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let card: UserCard
    let onShowMenu: (UserCard) -> Void
    let onCardTap: ((String) -> Void)?
    @ObservedObject var cardsManager: HomeCardsManager
    let showMergeGuide: Bool
    let onboardingState: String?
    let contextualTipStore: ContextualGuideTipStore?
    
    init(
        card: UserCard,
        onShowMenu: @escaping (UserCard) -> Void,
        cardsManager: HomeCardsManager,
        showMergeGuide: Bool = false,
        onboardingState: String? = nil,
        contextualTipStore: ContextualGuideTipStore? = nil,
        onCardTap: ((String) -> Void)? = nil
    ) {
        self.card = card
        self.onShowMenu = onShowMenu
        self.cardsManager = cardsManager
        self.showMergeGuide = showMergeGuide
        self.onboardingState = onboardingState
        self.contextualTipStore = contextualTipStore
        self.onCardTap = onCardTap
    }

    private var isMergeEntryTipVisible: Bool {
        showMergeGuide
            && (contextualTipStore?.isVisible(
                .libraryMergeEntry,
                onboardingState: onboardingState,
                targetIsVisible: true
            ) ?? false)
    }

    private func openMenu() {
        if showMergeGuide {
            contextualTipStore?.complete(
                .libraryMergeEntry,
                onboardingState: onboardingState,
                targetIsVisible: true
            )
        } else {
            contextualTipStore?.dismiss(
                .libraryMergeEntry,
                onboardingState: onboardingState,
                targetIsVisible: true
            )
        }
        onShowMenu(card)
    }

    private func openCard() {
        contextualTipStore?.dismiss(
            .libraryMergeEntry,
            onboardingState: onboardingState,
            targetIsVisible: true
        )
        onCardTap?(card.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息 - 左上角：open图标 + 时间 + pin图标
            HStack {
                HStack(spacing: 6) {
                    // 只有当卡片是公开状态时才显示open图标
                    if card.isPublic {
                        Image("open")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                    }
                    
                    Text(formatDate(card.updatedAt))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(metadataOpacity))
                    
                    // 只有当卡片是置顶状态时才显示pin图标
                    if card.isPinned {
                        Image("pin")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 15, height: 15)
                    }
                }
                
                Spacer()
                
                Button(action: openMenu) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Card menu")
                .accessibilityIdentifier("home.card.menu.\(card.id)")
                .overlay {
                    ContextualGuideTargetHalo(
                        isVisible: isMergeEntryTipVisible
                    )
                }
            }

            if isMergeEntryTipVisible, let contextualTipStore {
                HStack {
                    Spacer(minLength: 0)
                    ContextualGuideCallout(
                        store: contextualTipStore,
                        tip: .libraryMergeEntry,
                        onboardingState: onboardingState,
                        targetIsVisible: true
                    )
                }
            }
            
            // 内容文本
            VStack(alignment: .leading, spacing: 8) {
                LibraryCardContentPreview(
                    content: card.content,
                    contentJSON: card.contentJSON,
                    cardID: card.id,
                    onTap: openCard
                )
            }
            
            // 底部标签 - 横向滚动视图
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(card.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(notesCardTagBackground)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
            }
            
        }
        .padding(20)
        .background {
            LibraryCardBackgroundSurface(
                backgroundMediaRef: card.backgroundMediaRef,
                rate: card.rate
            ) {
                notesCardBackground
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.home.\(card.id)")
    }
    
    // MARK: Background Views

    private var hasCustomBackground: Bool {
        guard let backgroundMediaRef = card.backgroundMediaRef else {
            return false
        }
        return !backgroundMediaRef.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private var metadataOpacity: Double {
        LibraryCardReadabilityPolicy.metadataOpacity(
            hasBackground: hasCustomBackground,
            increasedContrast: contrast == .increased
        )
    }
    
    private var notesCardTagBackground: some View {
        RoundedRectangle(cornerRadius: 15)
            .fill(
                (hasCustomBackground ? Color.black : Color.white)
                    .opacity(
                        LibraryCardReadabilityPolicy.tagSurfaceOpacity(
                            hasBackground: hasCustomBackground
                        )
                    )
            )
            .overlay(tagTopLeftHighlight)
            .overlay(tagBottomRightHighlight)
            .overlay(tagTopEdgeHighlight)
            .overlay(tagBottomEdgeHighlight)
    }
    
    private var notesCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }
    
    // MARK: - 标签高光效果
    private var tagTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 15)
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
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 15)
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
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 15)
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
        RoundedRectangle(cornerRadius: 15)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .bottom,
                            endPoint: UnitPoint(x: 1, y: 0.05)
                        )
                    )
            )
    }
    
    // MARK: - 高光效果
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
    
    // MARK: - 日期格式化方法
    private func formatDate(_ dateString: String) -> String {
        CardTimestamp.dateOnly(from: dateString)
    }
}

// MARK: - Home 页面卡片组件
struct HomePostCard: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let profileImage: String
    let name: String
    let time: String
    let content: String
    let contentJSON: String?
    let backgroundMediaRef: String?
    let tags: [String]
    let showSpark: Bool
    let favoriteCount: Int
    let cardId: String
    let rate: Int
    let authorId: String?
    let onShowMenu: (String) -> Void
    let onCardTap: ((String) -> Void)?
    let onUnfavorite: ((String) -> Void)?
    let onAvatarTap: ((String) -> Void)?
    
    init(profileImage: String, name: String, time: String, content: String, contentJSON: String? = nil, backgroundMediaRef: String? = nil, tags: [String], showSpark: Bool, favoriteCount: Int, cardId: String, rate: Int = 1, authorId: String? = nil, onShowMenu: @escaping (String) -> Void, onCardTap: ((String) -> Void)? = nil, onUnfavorite: ((String) -> Void)? = nil, onAvatarTap: ((String) -> Void)? = nil) {
        self.profileImage = profileImage
        self.name = name
        self.time = time
        self.content = content
        self.contentJSON = contentJSON
        self.backgroundMediaRef = backgroundMediaRef
        self.tags = tags
        self.showSpark = showSpark
        self.favoriteCount = favoriteCount
        self.cardId = cardId
        self.rate = rate
        self.authorId = authorId
        self.onShowMenu = onShowMenu
        self.onCardTap = onCardTap
        self.onUnfavorite = onUnfavorite
        self.onAvatarTap = onAvatarTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息
            HStack {
                // 头像 - 可点击跳转到用户资料
                Button(action: {
                    if let authorId = authorId {
                        onAvatarTap?(authorId)
                    }
                }) {
                    Group {
                        if !profileImage.isEmpty && (profileImage.hasPrefix("http://") || profileImage.hasPrefix("https://")) {
                            // 完整 URL
                            AsyncImage(url: URL(string: profileImage)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image("avatar")
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        } else if !profileImage.isEmpty {
                            // 相对路径，拼接域名
                            let fullAvatarUrl = APIConfiguration.resourceURLString(profileImage)
                 
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
                            // 空字符串，使用占位符
                            Image("avatar")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                }
                .disabled(authorId == nil)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(time)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(metadataOpacity))
                }
                
                Spacer()
                
                Button(action: {
                    onShowMenu(cardId)
                }) {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .accessibilityLabel("Card menu")
                .accessibilityIdentifier("home.card.menu.\(cardId)")
            }
            
            // 内容预览
            LibraryCardContentPreview(
                content: content,
                contentJSON: contentJSON,
                cardID: cardId,
                textFont: .system(size: 14, weight: .regular),
                onTap: { onCardTap?(cardId) }
            )
            
            // 底部标签和交互
            VStack(spacing: 12) {
                // 标签 - 横向滚动视图
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(homePostCardTagBackground)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 1) // 添加一点内边距，避免标签贴边
                }
                
                // 交互统计
                if showSpark {
                    HStack {
                        Spacer()
                        Button(action: {
                            // 取消收藏
                            onUnfavorite?(cardId)
                        }) {
                        HStack(spacing: 4) {
                            Image("favorite_active")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                            Text("\(favoriteCount)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(engagementOpacity))
                        }
                        }
                        .foregroundColor(.white.opacity(engagementOpacity))
                    }
                }
            }
        }
        .padding(20)
        .background {
            LibraryCardBackgroundSurface(
                backgroundMediaRef: backgroundMediaRef,
                rate: rate
            ) {
                homePostCardBackground
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.home.\(cardId)")
    }
    
    // MARK: - Background Views

    private var hasCustomBackground: Bool {
        guard let backgroundMediaRef else { return false }
        return !backgroundMediaRef.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private var metadataOpacity: Double {
        LibraryCardReadabilityPolicy.metadataOpacity(
            hasBackground: hasCustomBackground,
            increasedContrast: contrast == .increased
        )
    }

    private var engagementOpacity: Double {
        LibraryCardReadabilityPolicy.engagementOpacity(
            hasBackground: hasCustomBackground,
            increasedContrast: contrast == .increased
        )
    }
    
    private var homePostCardTagBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                (hasCustomBackground ? Color.black : Color.white)
                    .opacity(
                        LibraryCardReadabilityPolicy.tagSurfaceOpacity(
                            hasBackground: hasCustomBackground
                        )
                    )
            )
            .overlay(homePostCardTagTopLeftHighlight)
            .overlay(homePostCardTagBottomRightHighlight)
            .overlay(homePostCardTagTopEdgeHighlight)
            .overlay(homePostCardTagBottomEdgeHighlight)
    }
    
    private var homePostCardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }
    
    // MARK: 标签高光效果
    private var homePostCardTagTopLeftHighlight: some View {
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
                            endRadius: 15
                        )
                    )
            )
    }
    
    private var homePostCardTagBottomRightHighlight: some View {
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
                            endRadius: 15
                        )
                    )
            )
    }
    
    private var homePostCardTagTopEdgeHighlight: some View {
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
    
    private var homePostCardTagBottomEdgeHighlight: some View {
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
    
    // MARK: - 高光效果
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
    HomeView(showSideMenu: .constant(false), refreshID: UUID())
}

// MARK: - Library 富内容预览
struct LibraryCardContentPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let preview: LibraryCardPreviewContent
    private let cardID: String
    private let textFont: Font
    private let onTap: (() -> Void)?

    init(
        content: String,
        contentJSON: String?,
        cardID: String,
        textFont: Font = .system(size: 17, weight: .regular),
        onTap: (() -> Void)? = nil
    ) {
        preview = LibraryCardPreviewParser.parse(
            content: content,
            contentJSON: contentJSON
        )
        self.cardID = cardID
        self.textFont = textFont
        self.onTap = onTap
    }

    var body: some View {
        if let onTap {
            previewContent
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        } else {
            previewContent
        }
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageURL {
                libraryImage(url: imageURL)
            }

            if !preview.text.isEmpty {
                Text(preview.text)
                    .font(textFont)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imageURL: URL? {
        guard let source = preview.imageSource else { return nil }
        let normalizedSource = source.hasPrefix("chorai-assets/")
            ? "/\(source)"
            : source
        return CardEditingMediaURLResolver.resolve(
            normalizedSource,
            canonicalizeRelativePath: APIConfiguration.resourceURLString
        )
    }

    private func libraryImage(url: URL) -> some View {
        AsyncImage(
            url: url,
            transaction: Transaction(
                animation: reduceMotion ? nil : .easeInOut(duration: 0.2)
            )
        ) { phase in
            switch phase {
            case .success(let image):
                image.resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 480)
            case .failure:
                imageUnavailable
            case .empty:
                imageLoading
            @unknown default:
                imageUnavailable
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            preview.imageAlternativeText ?? "Note image"
        )
        .accessibilityIdentifier("library.card.image.\(cardID)")
    }

    private var imageLoading: some View {
        ZStack {
            Color.white.opacity(0.04)
            ProgressView()
                .tint(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 240)
    }

    private var imageUnavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.system(size: 26, weight: .light))
            Text("Image unavailable")
                .font(.caption)
        }
        .foregroundColor(.white.opacity(0.55))
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

// MARK: - HTML 文本渲染组件
struct HTMLTextRenderer: View {
    let htmlContent: String
    let maxLines: Int
    let font: Font
    let foregroundColor: Color
    
    init(
        htmlContent: String,
        maxLines: Int = 3,
        font: Font = .system(size: 17, weight: .regular),
        foregroundColor: Color = .white.opacity(0.9)
    ) {
        self.htmlContent = htmlContent
        self.maxLines = maxLines
        self.font = font
        self.foregroundColor = foregroundColor
    }
    
    var body: some View {
        Text(plainText)
            .font(font)
            .foregroundColor(foregroundColor)
            .lineLimit(maxLines)
            .multilineTextAlignment(.leading)
    }
    
    private var plainText: String {
        // 移除 HTML 标签，保留纯文本
        var text = htmlContent
        
        // 处理常见的 HTML 标签
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        text = text.replacingOccurrences(of: "</p>", with: "\n")
        text = text.replacingOccurrences(of: "</div>", with: "\n")
        text = text.replacingOccurrences(of: "</li>", with: "\n")
        
        // 移除所有 HTML 标签
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        
        // 解码 HTML 实体
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        
        // 清理多余的空白字符和换行
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 筛选标签组件
struct HomeFilterTag: View {
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
