import CoreFlow
import SwiftUI

struct HomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var showSideMenu: Bool
    let refreshID: UUID
    let committedCardID: String?
    let librarySelectionRequest: LibrarySelectionRequest?
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
    @State private var selectedFilter = "Latest Edited" // 默认筛选
    @State private var librarySearchSession = LibrarySearchSession()
    @StateObject private var cardsManager = HomeCardsManager()
    @StateObject private var librarySearchManager = LibrarySearchManager()
    @FocusState private var isLibrarySearchFocused: Bool
    @State private var currentCardId: String? = nil
    @State private var currentMenuCardData: UserCard? = nil
    @State private var ownedCardActionRefresh: OwnedCardActionRefresh?
    @State private var ownedCardRefreshRequestID: UUID?
    @State private var ownedCardRefreshFailedID: String?
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
    @State private var handledLibrarySelectionRequestID: UUID?

    init(
        showSideMenu: Binding<Bool>,
        refreshID: UUID,
        committedCardID: String? = nil,
        librarySelectionRequest: LibrarySelectionRequest? = nil,
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
        self.librarySelectionRequest = librarySelectionRequest
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
        let descriptor = selectedSortOption.descriptor
        cardsManager.loadUserCards(
            refresh: true,
            sortBy: descriptor.field.apiName,
            sortOrder: descriptor.order.apiName
        )
    }

    private func handleOwnedCardActionCommit(_ commit: OwnedCardActionCommit) {
        if case .removed(let cardID) = commit {
            cardsManager.cards.removeAll { $0.id == cardID }
            librarySearchManager.remove(cardID: cardID)
            if currentCardId == cardID { currentCardId = nil }
            if currentMenuCardData?.id == cardID { currentMenuCardData = nil }
            if cardToDelete?.id == cardID {
                cardToDelete = nil
                showDeleteConfirmation = false
                deleteCardError = nil
            }
            if selectedCardId == cardID {
                selectedCardId = nil
                navigateToDetail = false
                navigateToEdit = false
            }
        }
        // Reload the current API sort and current submitted query, without resetting
        // the user's segment, search text, or selected sort to a visual sample value.
        loadUserCards()
        if librarySearchSession.isActive { retryLibrarySearch() }
    }

    private func handleCardRouteDismissal(_ dismissal: CardNavigationDismissal) {
        onCardRouteDismissed(dismissal)
        if case .editor(let cardID) = dismissal.route {
            refreshOwnedCardAfterEditing(cardID)
        }
    }

    private func refreshOwnedCardAfterEditing(_ cardID: String) {
        guard AuthManager.shared.currentUser != nil else { return }
        if cardID.hasPrefix("local-note:") {
            // Returning from a local editor must not send its identity to the cloud.
            ownedCardRefreshRequestID = nil
            ownedCardRefreshFailedID = nil
            loadUserCards()
            if let note = LocalNotesController.shared.library.notes.first(where: { NoteLibraryStore.identifier($0) == cardID }) {
                // Action state reads the committed note; display projection may still be running.
                ownedCardActionRefresh = OwnedCardActionRefresh(snapshot: OwnedCardActionSnapshot(
                    cardID: cardID, isOwned: true,
                    isPublic: note.isPublic, isPinned: note.isPinned ?? false, pinnedAt: nil
                ))
            }
            if librarySearchSession.isActive { retryLibrarySearch() }
            return
        }
        let requestID = UUID()
        ownedCardRefreshRequestID = requestID
        Task { @MainActor in
            do {
                let detail = try await CardDetailReader.shared.confirmed(cardID: cardID, requiringNewRead: true)
                guard ownedCardRefreshRequestID == requestID else { return }
                ownedCardRefreshRequestID = nil
                let snapshot = OwnedCardActionSnapshot(
                    cardID: detail.id,
                    isOwned: detail.isOwner ?? (AuthManager.shared.currentUser.map { detail.author?.actorId == $0.id } ?? false),
                    isPublic: detail.isPublic, isPinned: detail.isPinned ?? false, pinnedAt: detail.pinnedAt
                )
                ownedCardActionRefresh = OwnedCardActionRefresh(snapshot: snapshot)
                ownedCardRefreshFailedID = nil
                loadUserCards()
                if librarySearchSession.isActive { retryLibrarySearch() }
            } catch {
                guard ownedCardRefreshRequestID == requestID else { return }
                ownedCardRefreshRequestID = nil
                ownedCardRefreshFailedID = cardID
            }
        }
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

    private func applyLibrarySelectionRequest() {
        guard let request = librarySelectionRequest,
              handledLibrarySelectionRequestID != request.id else { return }
        handledLibrarySelectionRequestID = request.id
        if librarySearchSession.isActive {
            exitLibrarySearch()
        }
        selectedSegment = request.scope == .notes ? 0 : 1
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

    private var librarySegmentSelection: Binding<Int> {
        Binding(get: { selectedSegment }, set: { value in
            dismissLibraryTipIfVisible()
            selectedSegment = value
        })
    }

    private var librarySortSelection: Binding<LibrarySortOption> {
        Binding(get: { selectedSortOption }, set: { option in
            dismissLibraryTipIfVisible()
            isLibrarySearchFocused = false
            selectedFilter = option.rawValue
            applySort(sortBy: option.descriptor.field.apiName,
                      sortOrder: option.descriptor.order.apiName)
        })
    }

    private func sortLabel(_ option: LibrarySortOption) -> String {
        switch option {
        case .latestEdited: return "Latest edited"
        case .latestAdded: return "Latest added"
        case .rarityHighLow: return "Card level: high to low"
        case .rarityLowHigh: return "Card level: low to high"
        }
    }

    private var librarySortOptions: some View {
        Picker("Sort by", selection: librarySortSelection) {
            ForEach(LibrarySortOption.allCases) { option in
                Text(sortLabel(option)).tag(option)
                    .accessibilityIdentifier("home.sort.\(option.id)")
            }
        }
        .pickerStyle(.inline)
    }

    private var libraryHeader: some View {
        VStack(spacing: 24) {
            Picker("Library", selection: librarySegmentSelection) {
                Text("My Notes").tag(0).accessibilityIdentifier("home.segment.notes")
                Text("Collections").tag(1).accessibilityIdentifier("home.segment.collect")
            }
            .pickerStyle(.segmented)
            HStack {
                Text(selectedSegment == 0 ? "Your thinking, in progress." : "Ideas worth returning to.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if selectedSegment == 0 {
                    Menu { librarySortOptions } label: {
                        Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44)
                    }
                    .choraiGlassButton()
                    .simultaneousGesture(TapGesture().onEnded { dismissLibraryTipIfVisible() })
                    .accessibilityLabel("Sort notes")
                    .accessibilityValue(sortLabel(selectedSortOption))
                    .accessibilityIdentifier("home.filter")
                }
            }
        }
    }

    @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                dismissLibraryTipIfVisible()
                showSideMenu = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open menu")
            .accessibilityIdentifier("side-menu.open")
        }
        ToolbarItem(placement: .principal) {
            Text("Home")
                .font(.headline)
                .foregroundStyle(.primary)
                #if DEBUG
                .accessibilityIdentifier(LocalDevelopmentPreview.isEnabled
                    ? "local-preview.indicator" : "home.title")
                #endif
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if librarySearchSession.isActive {
                Button("Cancel", action: exitLibrarySearch)
                    .accessibilityIdentifier("home.search.cancel")
            } else {
                Button(action: enterLibrarySearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search Library")
                .accessibilityHint("Replaces the Library header with a search field")
                .accessibilityIdentifier("home.search")
            }
        }
    }

    private var librarySearchHeader: some View {
        HStack(spacing: 8) {
            Button(action: exitLibrarySearch) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ChoraiTheme.ink)
                    .frame(minWidth: 44, minHeight: 52)
            }
            .frame(minWidth: 44, minHeight: 52)
            .accessibilityLabel("Close Library search")
            .accessibilityIdentifier("home.search.close")

            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(ChoraiTheme.ink.opacity(0.62))
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .accessibilityHidden(true)

                TextField("Search your Library", text: librarySearchQuery)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.regular))
                    .foregroundStyle(ChoraiTheme.ink)
                    .tint(ChoraiTheme.ink)
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
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ChoraiTheme.ink.opacity(0.58))
                            .frame(minWidth: 44, minHeight: 52)
                    }
                    .frame(minWidth: 44, minHeight: 52)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("home.search.clear")
                }

                Menu { librarySortOptions } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .frame(minWidth: 44, minHeight: 52)
                }
                .frame(minWidth: 44, minHeight: 52)
                .simultaneousGesture(TapGesture().onEnded { dismissLibraryTipIfVisible() })
                .accessibilityLabel("Sort search results")
                .accessibilityValue(sortLabel(selectedSortOption))
                .accessibilityIdentifier("home.search.filter")
            }
            .frame(minHeight: 52)
            .padding(.trailing, 4)
            .background(librarySearchInputBackground)
        }
    }

    private var librarySearchInputBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(ChoraiTheme.raisedSurface)
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
            .padding(.horizontal, 24)
            .padding(.top, 16)

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
                                NotificationCenter.default.post(name: .choraiFavoriteChanged, object: nil, userInfo: ["cardID": cardID, "isFavorited": false])
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
                    },
                    onboardingStore: onboardingStore,
                    contextualTipStore: contextualTipStore,
                    onNoteCreated: onNoteCreated,
                    onCardRoutePresentationChanged: onCardRoutePresentationChanged
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
        .choraiPageBackground()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { libraryToolbar }
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
            onRouteDismissed: handleCardRouteDismissal,
            onRoutePresentationChanged: onCardRoutePresentationChanged,
            ownedCardActionRefresh: ownedCardActionRefresh,
            ownedCardActionRefreshInFlight: ownedCardRefreshRequestID != nil,
            onOwnedCardActionCommitted: handleOwnedCardActionCommit
        )
        .alert("Couldn’t refresh this note", isPresented: Binding(
            get: { ownedCardRefreshFailedID != nil },
            set: { if !$0 { ownedCardRefreshFailedID = nil } }
        ), presenting: ownedCardRefreshFailedID) { cardID in
            Button("Retry") { refreshOwnedCardAfterEditing(cardID) }
            Button("Cancel", role: .cancel) { ownedCardRefreshFailedID = nil }
        } message: { _ in
            Text("The last confirmed status is still shown. Try again to load your changes.")
        }
        .onChange(of: navigateToEdit) { isPresented in
            if !isPresented, let cardID = selectedCardId { refreshOwnedCardAfterEditing(cardID) }
        }
        .onAppear {
            loadUserCards()
            presentCommittedCardIfNeeded(committedCardID)
            applyLibrarySelectionRequest()
        }
        .onDisappear {
            onLibrarySurfaceVisibilityChanged(false)
        }
        .onChange(of: refreshID) { _ in
            loadUserCards()
        }
        .onChange(of: committedCardID) { cardID in
            presentCommittedCardIfNeeded(cardID)
        }
        .onChange(of: librarySelectionRequest?.id) { _ in
            applyLibrarySelectionRequest()
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeleteCard"))) { notification in
            guard let card = CardDeletionConfirmationPolicy.target(
                requestedID: notification.userInfo?["cardId"] as? String,
                candidates: cardsManager.cards,
                menuCandidate: currentMenuCardData,
                id: \.id,
                isConfirmationPresented: showDeleteConfirmation,
                isDeleting: isDeletingCard
            ) else { return }
            cardToDelete = card
            deleteCardError = nil
            showDeleteConfirmation = true
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
                                        .foregroundColor(ChoraiTheme.ink)
                                }
                                .accessibilityIdentifier("home.delete.close")
                            }
                            
                            // 确认文本
                            Text("Confirm delete this note?")
                                .font(.headline.weight(.medium))
                                .foregroundColor(ChoraiTheme.ink)
                                .multilineTextAlignment(.center)

                            if let deleteCardError {
                                Text(deleteCardError)
                                    .font(.footnote.weight(.regular))
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
                                            .font(.body.weight(.medium))
                                        Text("Cancel")
                                            .font(.body.weight(.medium))
                                    }
                                    .foregroundColor(ChoraiTheme.ink)
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
                                                .tint(ChoraiTheme.ink)
                                        } else {
                                            Image(systemName: "checkmark")
                                                .font(.body.weight(.medium))
                                        }
                                        Text("Yes")
                                            .font(.body.weight(.medium))
                                    }
                                    .foregroundColor(ChoraiTheme.ink)
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
        .onChange(of: navigateToEdit) { isPresented in
            // Direct row/search navigation must cover Home just like menu routes.
            // Report the route binding, not editor appearance: nested pushes and
            // keyboard changes must not briefly reveal the browsing tab bar.
            onCardRoutePresentationChanged(isPresented)
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
    let onCardRoutePresentationChanged: (Bool) -> Void
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

    private var onboardingFinishAction: ((String, String) -> Bool)? {
        guard onboardingStore?.contextualTipState == "elicit_signal" else { return nil }
        return finishOnboardingNote
    }

    private func finishOnboardingNote(cardID: String, content: String) -> Bool {
        guard navigateToCreate, let onboardingStore,
              onboardingStore.contextualTipState == "elicit_signal" else { return false }
        navigateToCreate = false
        onboardingStore.receive(.noteCreated(cardID: cardID, content: content))
        return true
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
                        .foregroundColor(ChoraiTheme.ink.opacity(0.5))
                            Text("Your Chorai is empty")
                        .font(.body.weight(.medium))
                        .foregroundColor(ChoraiTheme.ink.opacity(0.7))
                            Text("Start with a sentence, a question, or a small observation.")
                        .font(.subheadline.weight(.regular))
                        .foregroundColor(ChoraiTheme.ink.opacity(0.5))
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
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 84)
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
                                Label("New note", systemImage: "square.and.pencil")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ChoraiTheme.onAccent)
                                    .padding(.horizontal, 16)
                                    .frame(height: 52)
                            }
                            .choraiGlassButton(prominent: true)
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
                    .padding(.trailing, 24)
                    .padding(.bottom, 18)
                }
            }
        }
        .navigationDestination(isPresented: $navigateToCreate) {
            NewNoteView(
                onCreated: onNoteCreated,
                onFinishCreation: onboardingFinishAction
            )
        }
        .onChange(of: navigateToCreate) { isPresented in
            // Pair one coverage update with each actual push/pop transition.
            onCardRoutePresentationChanged(isPresented)
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
                            .foregroundColor(ChoraiTheme.ink.opacity(0.5))
                        Text("No favorites yet")
                            .font(.body.weight(.medium))
                            .foregroundColor(ChoraiTheme.ink.opacity(0.7))
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
                            menuCardData: UserCard(id: favorite.id, title: favorite.title ?? "", content: favorite.content,
                                contentJSON: favorite.contentJSON, backgroundMediaRef: favorite.backgroundMediaRef,
                                contentHash: "", isPublic: false, tags: favorite.tags ?? [],
                                createdAt: favorite.createdAt, updatedAt: favorite.createdAt,
                                likeCount: 0, commentCount: 0, isLiked: false, isPinned: favorite.isPinned,
                                pinnedAt: favorite.pinnedAt, isFavorited: true, favoriteCount: favorite.favoriteCount ?? 0, rate: favorite.rate),
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
                                        NotificationCenter.default.post(name: .choraiFavoriteChanged, object: nil, userInfo: ["cardID": cardId, "isFavorited": false])
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
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 84)
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
        RoundedRectangle(cornerRadius: 20, style: .continuous)
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

    private var rateTreatment: some View {
        ZStack {
            shape.stroke(ChoraiCardLevel(rate: rate).color.opacity(contrast == .increased ? 1 : 0.55), lineWidth: contrast == .increased ? 1.5 : 1)
            ChoraiLevelBrush(rate: rate)
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
                                    ChoraiTheme.background.opacity(veilOpacity)
                                    LinearGradient(
                                        colors: [
                                            ChoraiTheme.background.opacity(0.08),
                                            Color.clear,
                                            ChoraiTheme.background.opacity(bottomShadeOpacity),
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
private struct NotesCardGuideDecoration<Content: View>: View {
    @ObservedObject var store: ContextualGuideTipStore
    let onboardingState: String?
    let enabled: Bool
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        content(enabled && store.isVisible(.libraryMergeEntry, onboardingState: onboardingState, targetIsVisible: true))
    }
}

struct NotesCard: View {
    #if DEBUG
    @Environment(\.notesCardRenderObserver) private var renderObserver
    @Environment(\.notesCardGuideVisibilityObserver) private var guideObserver
    #endif
    @Environment(\.colorSchemeContrast) private var contrast
    let card: UserCard
    let onShowMenu: (UserCard) -> Void
    let onCardTap: ((String) -> Void)?
    let showMergeGuide: Bool
    let onboardingState: String?
    let contextualTipStore: ContextualGuideTipStore?
    
    init(
        card: UserCard,
        onShowMenu: @escaping (UserCard) -> Void,
        showMergeGuide: Bool = false,
        onboardingState: String? = nil,
        contextualTipStore: ContextualGuideTipStore? = nil,
        onCardTap: ((String) -> Void)? = nil
    ) {
        self.card = card
        self.onShowMenu = onShowMenu
        self.showMergeGuide = showMergeGuide
        self.onboardingState = onboardingState
        self.contextualTipStore = contextualTipStore
        self.onCardTap = onCardTap
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
        #if DEBUG
        let _ = renderObserver?(card.id)
        #endif
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Text(formatDate(card.updatedAt).uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(1.2)
                if card.isPinned { Image(systemName: "pin.fill").font(.caption2) }
                Spacer()
                Image(systemName: card.isPublic ? "globe" : "lock").font(.caption2)
            }.foregroundStyle(.secondary)
            LibraryCardContentPreview(content: card.content, contentJSON: card.contentJSON,
                                      cardID: card.id,
                                      contentHash: card.contentHash,
                                      localPreviewIdentity: card.localPreviewIdentity,
                                      onTap: openCard)
                .accessibilityIdentifier("home.card.body.\(card.id)")
            HStack(spacing: 7) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(card.tags, id: \.self) { tag in
                            Text("#\(tag)").font(.caption).foregroundStyle(ChoraiTheme.ink.opacity(0.8))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, 44)
            .accessibilityIdentifier("home.card.tags.\(card.id)")
            .overlay(alignment: .trailing) {
                NativeCardActionsMenu(cardData: card, layout: .grid3x3, isOwnCard: true, onPrepare: openMenu) {
                    Image(systemName: "ellipsis").font(.caption)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Card menu")
                .accessibilityIdentifier("home.card.menu.\(card.id)")
                .overlay {
                    if let contextualTipStore {
                        NotesCardGuideDecoration(store: contextualTipStore, onboardingState: onboardingState, enabled: showMergeGuide) { visible in
                            ContextualGuideTargetHalo(isVisible: visible)
                                #if DEBUG
                                .onAppear { guideObserver?(visible) }
                                .onChange(of: visible) { guideObserver?($0) }
                                #endif
                        }
                    }
                }
            }
            .padding(.bottom, 20)
            if showMergeGuide, let contextualTipStore {
                NotesCardGuideDecoration(store: contextualTipStore, onboardingState: onboardingState, enabled: true) { visible in
                    if visible {
                        HStack {
                            Spacer(minLength: 0)
                            ContextualGuideCallout(store: contextualTipStore, tip: .libraryMergeEntry,
                                onboardingState: onboardingState, targetIsVisible: true)
                        }
                    }
                }
            }
            Divider()
        }
        .padding(.top, 10).padding(.bottom, 4)
        .background {
            if hasCustomBackground {
                LibraryCardBackgroundSurface(backgroundMediaRef: card.backgroundMediaRef, rate: card.rate) {
                    Color.clear
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.home.\(card.id)")
    }

    // MARK: Background Views

    private var localNoteScope: NoteStoreScope? {
        guard let identity = card.localPreviewIdentity,
              identity.scope == LocalNotesController.shared.library.scope,
              identity.scope == AuthManager.shared.currentNoteScope,
              card.ownerActorId == identity.scope.actorID else { return nil }
        return identity.scope
    }

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
                (hasCustomBackground ? ChoraiTheme.background : ChoraiTheme.raisedSurface)
                    .opacity(
                        LibraryCardReadabilityPolicy.tagSurfaceOpacity(
                            hasBackground: hasCustomBackground
                        )
                    )
            )




    }
    
    private var notesCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ChoraiTheme.surface)
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
    let menuCardData: UserCard?
    let onShowMenu: (String) -> Void
    let onCardTap: ((String) -> Void)?
    let onUnfavorite: ((String) -> Void)?
    let onAvatarTap: ((String) -> Void)?
    
    init(profileImage: String, name: String, time: String, content: String, contentJSON: String? = nil, backgroundMediaRef: String? = nil, tags: [String], showSpark: Bool, favoriteCount: Int, cardId: String, rate: Int = 1, authorId: String? = nil, menuCardData: UserCard? = nil, onShowMenu: @escaping (String) -> Void, onCardTap: ((String) -> Void)? = nil, onUnfavorite: ((String) -> Void)? = nil, onAvatarTap: ((String) -> Void)? = nil) {
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
        self.menuCardData = menuCardData
        self.onShowMenu = onShowMenu
        self.onCardTap = onCardTap
        self.onUnfavorite = onUnfavorite
        self.onAvatarTap = onAvatarTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 7) {
                Text(time.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.2)
                Text("·")
                Button(name) { if let authorId { onAvatarTap?(authorId) } }
                    .font(.caption).buttonStyle(.plain).disabled(authorId == nil)
                Spacer()
                if showSpark {
                    Label("\(favoriteCount)", systemImage: "bookmark.fill")
                        .font(.caption2).monospacedDigit()
                        .accessibilityLabel("\(favoriteCount) collections")
                        .accessibilityIdentifier("home.card.collection-count.\(cardId)")
                }
            }.foregroundStyle(.secondary)
            LibraryCardContentPreview(content: content, contentJSON: contentJSON,
                cardID: cardId, onTap: { onCardTap?(cardId) })
                .accessibilityIdentifier("home.card.body.\(cardId)")
            HStack(spacing: 7) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)").font(.caption).foregroundStyle(ChoraiTheme.ink.opacity(0.8))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.trailing, showSpark ? 88 : 44)
            .accessibilityIdentifier("home.card.tags.\(cardId)")
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                if showSpark {
                    Button { onUnfavorite?(cardId) } label: {
                        Image(systemName: "bookmark.fill").font(.caption)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Remove from collection")
                        .accessibilityValue("\(favoriteCount) collections")
                }
                Group {
                    if let menuCardData {
                        NativeCardActionsMenu(cardData: menuCardData, layout: .grid3x2, isOwnCard: false,
                                              onPrepare: { onShowMenu(cardId) }) {
                            Image(systemName: "ellipsis").font(.caption)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                    } else {
                        Button { onShowMenu(cardId) } label: {
                            Image(systemName: "ellipsis").font(.caption)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                    }
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Card menu")
                    .accessibilityIdentifier("home.card.menu.\(cardId)")
                }
            }
            .padding(.bottom, 20)
            Divider()
        }
        .padding(.top, 10).padding(.bottom, 4)
        .background {
            if hasCustomBackground {
                LibraryCardBackgroundSurface(backgroundMediaRef: backgroundMediaRef, rate: rate) {
                    Color.clear
                }
            }
        }
        .contentShape(Rectangle())
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
                (hasCustomBackground ? ChoraiTheme.background : ChoraiTheme.raisedSurface)
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
        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ChoraiTheme.surface)
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
    let content: String
    let contentJSON: String?
    let cardID: String
    var textFont: Font? = nil
    var contentHash: String? = nil
    var localPreviewIdentity: LocalNotePreviewIdentity? = nil
    var onTap: (() -> Void)? = nil
    @State private var snapshotID = UUID()

    private var input: LibraryCardPreviewInput? {
        if let local = localPreviewIdentity {
            return LibraryCardPreviewInput(
                localNoteID: cardID, scope: local.scope, bodyRevision: local.bodyRevision,
                content: content, contentJSON: contentJSON
            )
        }
        guard !cardID.hasPrefix("local-note:") else { return nil }
        return LibraryCardPreviewInput(
            cardID: cardID, contentHash: contentHash, snapshotID: snapshotID,
            content: content, contentJSON: contentJSON
        )
    }

    var body: some View {
        CardPreviewValue(input: input) { presentation in
            LibraryCardPreviewBody(
                preview: presentation?.preview ?? LibraryCardPreviewContent(
                    text: "", imageSource: nil, imageAlternativeText: nil
                ),
                cardID: cardID, textFont: textFont, localPreviewIdentity: localPreviewIdentity, onTap: onTap
            )
        }
    }
}

private struct LibraryCardPreviewBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let preview: LibraryCardPreviewContent
    let cardID: String
    let textFont: Font?
    let localPreviewIdentity: LocalNotePreviewIdentity?
    let onTap: (() -> Void)?
    @ScaledMetric(relativeTo: .body) private var readingSize = 21.0

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
            if let mediaRef = preview.imageMediaRef, let local = localPreviewIdentity {
                libraryImage {
                    LocalNoteThumbnail(scope: local.scope, cardID: cardID, bodyRevision: local.bodyRevision,
                                       source: .reference(mediaRef), content: imageContent)
                        .id(local.scope)
                }
            } else if let url = imageURL {
                libraryImage {
                    if let local = localPreviewIdentity, url.scheme == NoteAttachmentFiles.previewScheme {
                        LocalNoteThumbnail(scope: local.scope, cardID: cardID, bodyRevision: local.bodyRevision,
                                           source: .previewURL(url), content: imageContent)
                            .id(local.scope)
                    } else {
                        AsyncImage(
                            url: url,
                            transaction: Transaction(animation: reduceMotion ? nil : .easeInOut(duration: 0.2)),
                            content: imageContent
                        )
                    }
                }
            }

            if !preview.text.isEmpty {
                Text(preview.text)
                    .font(textFont ?? .system(size: readingSize, design: .serif))
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imageURL: URL? {
        guard let source = preview.imageSource else { return nil }
        if localPreviewIdentity != nil, let url = URL(string: source), url.scheme == NoteAttachmentFiles.previewScheme {
            return url
        }
        let normalizedSource = source.hasPrefix("chorai-assets/")
            ? "/\(source)"
            : source
        return CardEditingMediaURLResolver.resolve(
            normalizedSource,
            canonicalizeRelativePath: APIConfiguration.resourceURLString
        )
    }

    private func libraryImage(@ViewBuilder _ image: () -> some View) -> some View {
        image()
        .id(cardID)
        .frame(maxWidth: .infinity)
        .background(ChoraiTheme.raisedSurface)
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

    @ViewBuilder
    private func imageContent(_ phase: AsyncImagePhase) -> some View {
        switch phase {
        case .success(let image):
            image.resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 480)
        case .empty:
            imageLoading
        case .failure:
            imageUnavailable
        @unknown default:
            imageUnavailable
        }
    }

    private var imageLoading: some View {
        ZStack {
            ChoraiTheme.raisedSurface
            ProgressView()
                .tint(ChoraiTheme.ink.opacity(0.8))
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
        .foregroundColor(ChoraiTheme.ink.opacity(0.55))
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

private struct LocalNoteThumbnail<Content: View>: View {
    let scope: NoteStoreScope
    let cardID: String
    let bodyRevision: Int64
    let source: NoteThumbnailSource
    let content: (AsyncImagePhase) -> Content
    @ObservedObject private var reader = LocalNoteThumbnailReader.shared
    @State private var phase = AsyncImagePhase.empty
    @State private var loadedRequest: Request?

    private struct Request: Hashable {
        let scope: NoteStoreScope
        let cardID: String
        let bodyRevision: Int64
        let source: NoteThumbnailSource
        let generation: UInt64
    }

    var body: some View {
        let request = Request(scope: scope, cardID: cardID, bodyRevision: bodyRevision,
                              source: source, generation: reader.invalidationGeneration)
        content(loadedRequest == request && reader.allows(scope) ? phase : .empty).task(id: request) {
            phase = .empty
            loadedRequest = nil
            do {
                let thumbnail = try await reader.image(source: source, cardID: cardID, scope: scope,
                                                       bodyRevision: bodyRevision, pixelSize: 1024)
                guard !Task.isCancelled, reader.invalidationGeneration == request.generation else { return }
                loadedRequest = request
                phase = .success(Image(uiImage: thumbnail))
            } catch {
                guard !Task.isCancelled, reader.invalidationGeneration == request.generation else { return }
                loadedRequest = request
                phase = .failure(error)
            }
        }
        .onDisappear { loadedRequest = nil; phase = .empty }
    }
}

// MARK: - HTML 文本渲染组件
struct HTMLTextRenderer: View {
    let cardID: String
    let htmlContent: String
    let maxLines: Int
    let font: Font
    let foregroundColor: Color
    
    init(
        cardID: String,
        htmlContent: String,
        maxLines: Int = 3,
        font: Font = .system(size: 17, weight: .regular),
        foregroundColor: Color = ChoraiTheme.ink
    ) {
        self.cardID = cardID
        self.htmlContent = htmlContent
        self.maxLines = maxLines
        self.font = font
        self.foregroundColor = foregroundColor
    }
    
    var body: some View {
        HTMLTextValue(cardID: cardID, html: htmlContent, reader: .shared) { text in
            Text(text)
                .font(font)
                .foregroundColor(foregroundColor)
                .lineLimit(maxLines)
                .multilineTextAlignment(.leading)
        }
    }
}
