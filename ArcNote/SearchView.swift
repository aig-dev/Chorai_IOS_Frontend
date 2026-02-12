import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCollection = "All"
    @State private var selectedLabel = "All"
    @State private var selectedTime = "All"
    @ObservedObject private var searchManager = SearchManager.shared
    @StateObject private var searchCardsManager = HomeCardsManager()
    @State private var selectedCardId: Int?
    @State private var navigateToDetail = false
    @State private var showPopupMenu = false
    @State private var popupMenuLayout: PopupMenuLayout = .grid3x3
    @State private var currentMenuCardData: UserCard?
    @FocusState private var isSearchFieldFocused: Bool
    @State private var lastSearchQuery = ""
    @State private var isShowingFilters = true
    
    // MARK: - 计算属性
    
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

    private var filteredSearchCards: [SearchCard] {
        searchManager.searchResults.filter { card in
            matchesCollection(card) && matchesLabel(card) && matchesTime(card)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("Please enter your search...", text: $searchText)
                            .foregroundColor(.white)
                            .textFieldStyle(PlainTextFieldStyle())
                            .placeholder(when: searchText.isEmpty) {
                                Text("Please enter your search...")
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .focused($isSearchFieldFocused)
                            .submitLabel(.search)
                            .onSubmit {
                                performSearch(reset: true)
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .background(searchInputBackground)
                }
                .padding(.horizontal, 20)
                
                
                ScrollView {
                    VStack(spacing: 30) {
                        if isShowingFilters {
                            filtersSection
                        } else {
                            searchResultsSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
                    .padding(.bottom, 120)
                }
                .refreshable {
                    if !lastSearchQuery.isEmpty {
                        performSearch(reset: true, queryOverride: lastSearchQuery)
                    }
                }
        }
        .popupMenu(
            isPresented: $showPopupMenu,
            layout: popupMenuLayout,
            cardData: currentMenuCardData,
            searchType: "own+favorited"
        )
        .background(
            Group {
                if let cardId = selectedCardId {
                    NavigationLink(
                        destination: DetailView(cardId: cardId),
                        isActive: $navigateToDetail
                    ) {
                        EmptyView()
                    }
                    .hidden()
                }
            }
        )
        .onAppear {
            isSearchFieldFocused = true
        }
        .onChange(of: searchText) { newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchManager.clearSearchResults()
                lastSearchQuery = ""
                withAnimation(.easeInOut(duration: 0.25)) {
                    isShowingFilters = true
                }
            }
        }
        .onChange(of: selectedCollection) { _ in
            showResultsIfNeeded()
        }
        .onChange(of: selectedLabel) { _ in
            showResultsIfNeeded()
        }
        .onChange(of: selectedTime) { _ in
            showResultsIfNeeded()
        }
        .navigationBarHidden(true)
        .background(
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
    }
    
    @ViewBuilder
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchManager.searchResults.isEmpty {
                Text("Type a keyword and press return to search across your notes and community cards.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                    )
            } else if searchManager.isLoading && searchManager.searchResults.isEmpty {
                HStack {
                    Spacer()
                    RotatingLoaderView()
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if filteredSearchCards.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.5))
                    Text("No results match the current filters")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVStack(spacing: 20) {
                    ForEach(Array(filteredSearchCards.enumerated()), id: \.element.id) { index, searchCard in
                        let userCard = convertToUserCard(searchCard)
                        Group {
                            if userCard.rate < 3 {
                                NotesCard(
                                    card: userCard,
                                    onShowMenu: { card in
                                        handleShowMenu(for: card)
                                    },
                                    cardsManager: searchCardsManager,
                                    onCardTap: { cardId in
                                        handleCardTap(cardId)
                                    }
                                )
                            } else {
                                NotesColorCard(
                                    card: userCard,
                                    onShowMenu: { card in
                                        handleShowMenu(for: card)
                                    },
                                    cardsManager: searchCardsManager,
                                    onCardTap: { cardId in
                                        handleCardTap(cardId)
                                    }
                                )
                            }
                        }
                        .onAppear {
                            handleLoadMoreIfNeeded(currentIndex: index)
                        }
                    }
                    
                    if searchManager.isLoading && !filteredSearchCards.isEmpty {
                        RotatingLoaderView()
                            .padding(.top, 10)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 16) {
                Text("My Collection")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                FlowLayout(
                    spacing: 12,
                    items: ["All", "My Notes", "Favorite", "Community"],
                    isSelected: { selectedCollection == $0 },
                    onTap: { selectedCollection = $0 }
                )
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Label")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                FlowLayout(
                    spacing: 12,
                    items: ["All", "Design", "UI", "My Notes", "User Experience", "Mobile App"],
                    isSelected: { selectedLabel == $0 },
                    onTap: { selectedLabel = $0 }
                )
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Time")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                FlowLayout(
                    spacing: 12,
                    items: ["All", "Within a week", "Within a month", "Within three months"],
                    isSelected: { selectedTime == $0 },
                    onTap: { selectedTime = $0 }
                )
            }
        }
    }
    
    private func performSearch(reset: Bool = false, queryOverride: String? = nil) {
        let query = (queryOverride ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchManager.clearSearchResults()
            lastSearchQuery = ""
            return
        }
        
        lastSearchQuery = query
        if reset {
            searchManager.clearSearchResults()
        }
        
        searchManager.searchCards(query: query) { _ in }
        showResultsIfNeeded(animated: true)
    }
    
    private func handleCardTap(_ cardId: Int) {
        selectedCardId = cardId
        navigateToDetail = true
    }
    
    private func handleShowMenu(for card: UserCard) {
        currentMenuCardData = card
        popupMenuLayout = .grid3x3
        showPopupMenu = true
    }
    
    private func handleLoadMoreIfNeeded(currentIndex: Int) {
        if currentIndex == filteredSearchCards.count - 1,
           searchManager.hasMoreData,
           !searchManager.isLoading,
           !lastSearchQuery.isEmpty {
            searchManager.loadMoreSearchResults(query: lastSearchQuery)
        }
    }
    
    private func matchesCollection(_ card: SearchCard) -> Bool {
        guard let currentUserId = AuthManager.shared.currentUser?.id else {
            return selectedCollection != "My Notes"
        }
        
        switch selectedCollection {
        case "All":
            return true
        case "My Notes":
            return card.author.id == currentUserId
        case "Favorite":
            return card.isFavorited ?? false
        case "Community":
            return card.author.id != currentUserId
        default:
            return true
        }
    }
    
    private func matchesLabel(_ card: SearchCard) -> Bool {
        guard selectedLabel != "All" else {
            return true
        }
        return card.tags.contains { tag in
            tag.localizedCaseInsensitiveContains(selectedLabel)
        }
    }
    
    private func matchesTime(_ card: SearchCard) -> Bool {
        guard selectedTime != "All" else {
            return true
        }
        guard let date = parseDate(card.updatedAt) ?? parseDate(card.createdAt) else {
            return true
        }
        let interval = Date().timeIntervalSince(date)
        switch selectedTime {
        case "Within a week":
            return interval <= 7 * 24 * 60 * 60
        case "Within a month":
            return interval <= 30 * 24 * 60 * 60
        case "Within three months":
            return interval <= 90 * 24 * 60 * 60
        default:
            return true
        }
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: dateString) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: dateString)
    }
    
    private func convertToUserCard(_ card: SearchCard) -> UserCard {
        return UserCard(
            id: card.id,
            title: card.title,
            content: card.content,
            contentHash: card.contentHash,
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
            rate: card.rate
        )
    }
    
    private func showResultsIfNeeded(animated: Bool = false) {
        guard !searchManager.searchResults.isEmpty else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                isShowingFilters = false
            }
        } else {
            isShowingFilters = false
        }
    }
}

// MARK: - 搜索筛选标签组件
struct SearchFilterTag: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .lineLimit(1)
                .padding(.horizontal, 16)
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

#Preview {
    SearchView()
}

// MARK: - FlowLayout 组件
struct FlowLayout: View {
    let spacing: CGFloat
    let items: [String]
    let isSelected: (String) -> Bool
    let onTap: (String) -> Void
    
    init(spacing: CGFloat = 12, items: [String], isSelected: @escaping (String) -> Bool, onTap: @escaping (String) -> Void) {
        self.spacing = spacing
        self.items = items
        self.isSelected = isSelected
        self.onTap = onTap
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: spacing) {
                    ForEach(rows[rowIndex], id: \.self) { item in
                        SearchFilterTag(title: item, isSelected: isSelected(item)) {
                            onTap(item)
                        }
                    }
                    Spacer()
                }
            }
        }
    }
    
    private var rows: [[String]] {
        var result: [[String]] = [[]]
        var currentRow = 0
        var currentWidth: CGFloat = 0
        let maxWidth: CGFloat = UIScreen.main.bounds.width - 40 // 减去左右边距
        
        for item in items {
            let itemWidth = estimateWidth(for: item)
            
            if currentWidth + itemWidth > maxWidth && !result[currentRow].isEmpty {
                currentRow += 1
                result.append([])
                currentWidth = itemWidth + spacing
            } else {
                currentWidth += itemWidth + spacing
            }
            
            result[currentRow].append(item)
        }
        
        return result
    }
    
    private func estimateWidth(for text: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 14, weight: .medium)
        let attributes = [NSAttributedString.Key.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return size.width + 32 + spacing // 32是左右内边距
    }
} 
