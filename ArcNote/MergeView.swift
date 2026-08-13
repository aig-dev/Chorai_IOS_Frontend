import SwiftUI
import Combine
import CoreFlow

private struct LegacyMergeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) var presentationMode
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedCards: Set<String> = []
    @State private var showLoading = false
    @State private var showNewInsight = false
    @State private var animationPhase = 0
    @State private var animationTimer: Timer?
    @StateObject private var searchManager = SearchManager.shared
    @StateObject private var cardDetailManager = CardDetailManager.shared
    @StateObject private var mergeCardsManager = MergeCardsManager.shared
    @StateObject private var networkManager = NetworkManager.shared
    
    let cardId: String
    
    // 可选择的卡片数据
    @State private var selectableCards: [MergeCard] = []
    @State private var allCards: [MergeCard] = [] // 所有卡片数据
    @State private var isLoadingCards = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var previewData: MergePreviewResponse? = nil
    @State private var mergeErrorMessage: String?
    @State private var cardsErrorMessage: String?
    
    // MARK: 搜索框高光效果
    private var searchBarTopLeftHighlight: some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 25)
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
    
    private var searchBarBottomRightHighlight: some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 0)
            .mask(
                RoundedRectangle(cornerRadius: 25)
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
    
    private var searchBarTopEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: -1)
            .mask(
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }
    
    private var searchBarBottomEdgeHighlight: some View {
        RoundedRectangle(cornerRadius: 25)
            .stroke(Color.white, lineWidth: 1)
            .offset(x: 0, y: 1)
            .mask(
                RoundedRectangle(cornerRadius: 25)
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
        KeyboardStableViewport(isFocused: isSearchFocused) { _ in
            ZStack {
            // 背景图片
//            Image("home_bg")
//                .resizable()
//                .aspectRatio(contentMode: .fill)
//                .frame(maxWidth: .infinity, maxHeight: .infinity)
//                .clipped()
//                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部导航栏
                HStack {
                    Spacer()
                    
                    // Merge 标题
                    HStack(spacing: 8) {
                            Image("menu_merge")
                                .resizable().frame(width: 28, height: 28)
                        
                        Text("Merge")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
                .adaptiveContentGutter()
//                .padding(.top, 60)
                
                                // 主要内容
                VStack(spacing: 0) {
                    // 固定的第一张卡片
                    if let cardDetail = cardDetailManager.cardDetail {
                        FixedMergeCardView(card: convertCardDetailToMergeCard(cardDetail))
                            .padding(.top, 20)
                    } else if cardDetailManager.isLoading {
                        // 加载状态
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                            
                            Text("Loading card...")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        // 错误状态
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.5))
                            
                            Text("Failed to load card")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    }
                    
                    // 分割线
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.white.opacity(0.2))
                        .adaptiveContentGutter()
                        .padding(.vertical, 20)
                    
                    // 搜索栏
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.7))
                        
                        TextField("", text: $searchText)
                            .foregroundColor(.white)
                            .textFieldStyle(PlainTextFieldStyle())
                            .focused($isSearchFocused)
                            .accessibilityIdentifier("merge.search.input")
                            .placeholder(when: searchText.isEmpty) {
                                Text("Please enter your search...")
                                    .foregroundColor(.white).font(.system(size: 13))
                            }
                        
                        Button(action: {
                            // 搜索按钮
                        }) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color(red: 0.2, green: 0.1, blue: 0.3))
                            .overlay(searchBarTopLeftHighlight)
                            .overlay(searchBarBottomRightHighlight)
                            .overlay(searchBarTopEdgeHighlight)
                            .overlay(searchBarBottomEdgeHighlight)
                    )
                    .adaptiveContentGutter()
                    .padding(.bottom, 30)
                    
                    // 可选择的卡片列表
                    ScrollView {
                        VStack(spacing: 20) {
                            if searchManager.isLoading && searchManager.searchResults.isEmpty {
                                // 加载状态
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.2)
                                    
                                    Text("Searching...")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                            } else if selectableCards.isEmpty && !isLoadingCards {
                                // 无卡片数据
                                VStack(spacing: 16) {
//                                    Image(systemName: "doc.text")
//                                        .font(.system(size: 48))
//                                        .foregroundColor(.white.opacity(0.5))
                                    
                                    Text(cardsErrorMessage ?? "No linked cards found")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .multilineTextAlignment(.center)
                                        .accessibilityIdentifier(cardsErrorMessage == nil ? "merge.cards.empty-message" : "merge.cards.error")
                                    
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                            } else if isLoadingCards {
                                // 加载状态
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.2)
                                    
                                    Text("Loading linked cards...")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                            } else {
                                // 显示卡片列表（支持本地搜索筛选）
                                ForEach(selectableCards) { card in
                                    MergeCardView(
                                        card: card,
                                        isSelected: selectedCards.contains(card.id),
                                        onToggleSelection: {
                                            if selectedCards.contains(card.id) {
                                                selectedCards.remove(card.id)
                                            } else {
                                                selectedCards.insert(card.id)
                                            }
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.bottom, 100) // 为悬浮按钮留出空间
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }.background(
                Image("home_bg")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            )
            
            // 底部悬浮的合并按钮
            VStack {
                Spacer()
                Button(action: {
                    performMerge()
                }) {
                    Text(selectedCards.isEmpty ? "Merge Selected Cards (1)" : "Merge Selected Cards (\(selectedCards.count + 1))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(selectedCards.isEmpty ? .white.opacity(0.5) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(selectedCards.isEmpty ? Color.gray.opacity(0.3) : Color.gray.opacity(0.3))
                        )
                }
                .disabled(selectedCards.isEmpty)
                .accessibilityIdentifier("merge.action")
                .adaptiveContentGutter()
                .padding(.bottom, 30)
            }
            
            // 加载效果
            if mergeCardsManager.isMerging {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    
                    HStack(spacing: 30) {
                        // 四个白点动画
                        HStack(spacing: 12) {
                            ForEach(0..<4, id: \.self) { index in
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                                    .scaleEffect(animationPhase == index ? 1.5 : 1.0)
                                    .animation(.easeInOut(duration: 0.3), value: animationPhase)
                            }
                        }
                        .frame(height: 20) // 固定白点容器高度
                        
                        // Logo
                        Image("loading_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .accessibilityIdentifier("merge.loading")
                .transition(.opacity)
            }

            if let mergeErrorMessage {
                VStack {
                    Spacer()
                    Text(mergeErrorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .adaptiveContentGutter()
                        .padding(.bottom, 92)
                        .accessibilityIdentifier("merge.error")
                    Spacer().frame(height: 0)
                }
            }
            
            // 新洞察弹窗
            if showNewInsight {
                NewInsightView(
                    isPresented: $showNewInsight, 
                    mergeResult: mergeCardsManager.mergeResult, 
                    previewData: previewData,
                    selectedCards: getSelectedCardsForPreview()
                )
                .transition(.opacity.combined(with: .scale))
            }
            
            // 返回按钮 放在最上层
            VStack {
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .adaptiveContentGutter()
//                    .padding(.top, 60)
                    
                    Spacer()
                }
                Spacer()
            }

            #if DEBUG
            mergeDebugAnchors
            #endif
        }
        }
        .navigationBarHidden(true)
        .gesture(
            DragGesture()
                .onEnded { value in
                    // 侧滑返回手势
                    if value.translation.width > 100 && abs(value.translation.height) < 50 {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
        )
        .animation(.easeInOut(duration: 0.3), value: mergeCardsManager.isMerging)
        .animation(.easeInOut(duration: 0.3), value: showNewInsight)
        .onAppear {
            loadCardDetail()
            loadUserAllCards() // 改为加载用户所有卡片
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exitMergePage)) { _ in
            // 发布成功后退出Merge页面
            presentationMode.wrappedValue.dismiss()
        }
        .onChange(of: searchText) { newValue in
            // 调用搜索接口
            performSearch()
        }
    }

    #if DEBUG
    private var mergeDebugAnchors: some View {
        VStack(spacing: 1) {
            Text("loaded")
                .font(.system(size: 1))
                .foregroundColor(.white.opacity(0.01))
                .accessibilityIdentifier("screen.merge.loaded")
            if let cardDetail = cardDetailManager.cardDetail {
                Text(cardDetail.id)
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .accessibilityIdentifier("merge.source.card-id")
            }
            if isLoadingCards {
                Text("loading")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .accessibilityIdentifier("merge.cards.loading")
            } else if selectableCards.isEmpty {
                Text("empty")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .accessibilityIdentifier("merge.cards.empty")
            } else {
                Text("loaded")
                    .font(.system(size: 1))
                    .foregroundColor(.white.opacity(0.01))
                    .accessibilityIdentifier("merge.cards.loaded")
            }
        }
        .frame(width: 1, height: 1)
        .accessibilityElement(children: .contain)
    }
    #endif
    
    // MARK: 加载卡片详细信息
    private func loadCardDetail() {
        cardDetailManager.fetchCardDetail(cardId: cardId) { result in
            switch result {
            case .success:
                print("卡片详细信息加载成功")
            case .failure(let error):
                print("详细信息加载失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: 加载用户所有卡片
    private func loadUserAllCards() {
        isLoadingCards = true
        cardsErrorMessage = nil
        print("开始加载用户所有卡片")
        
        networkManager.getUserAllCards(searchType: "own+favorited", cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoadingCards = false
                    switch completion {
                    case .finished:
                        print("用户所有卡片加载完成")
                    case .failure(let error):
                        print("用户所有卡片加载失败: \(error.localizedDescription)")
                        self.cardsErrorMessage = error.localizedDescription
                    }
                },
                receiveValue: { response in
                    print("用户所有卡片加载成功")
                    self.cardsErrorMessage = nil
                    
                    // 合并所有卡片数据
                    var allUserCards: [MergeCard] = []
                    
                    allUserCards.append(contentsOf: response.data.ownCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    allUserCards.append(contentsOf: response.data.favoritedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: true)
                    })
                    
                    allUserCards.append(contentsOf: response.data.likedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    allUserCards.append(contentsOf: response.data.linkedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    self.allCards = allUserCards
                    self.filterCards() // 初始显示所有卡片
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 本地搜索筛选
    private func filterCards() {
        if searchText.isEmpty {
            selectableCards = allCards
        } else {
            let searchLowercased = searchText.lowercased()
            selectableCards = allCards.filter { card in
                card.content.lowercased().contains(searchLowercased) ||
                card.tags.contains { $0.lowercased().contains(searchLowercased) }
            }
        }
    }
    
    // MARK: 转换CardDetail为MergeCard
    private func convertCardDetailToMergeCard(_ cardDetail: CardDetail) -> MergeCard {
        // 格式化日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let displayDate: String
        if let date = dateFormatter.date(from: cardDetail.createdAt) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 86400 { // 24小时内
                displayDate = "Today"
            } else if timeInterval < 172800 { // 48小时内
                displayDate = "Yesterday"
            } else {
                let days = Int(timeInterval / 86400)
                displayDate = "\(days) days ago"
            }
        } else {
            displayDate = "Unknown"
        }
        
        return MergeCard(
            id: cardDetail.id,
            versionID: cardDetail.noteDocumentVersionID,
            date: displayDate,
            content: cardDetail.content,
            contentJSON: cardDetail.contentJSON,
            backgroundMediaRef: cardDetail.backgroundMediaRef,
            tags: cardDetail.tags,
            isUserCard: true,
            userName: cardDetail.author?.userName ?? "Unknown",
            avatarUrl: cardDetail.author?.avatarUrl,
            favoriteCount: cardDetail.favoriteCount ?? 0,
            rate: cardDetail.rate
        )
    }
    
    // MARK: 执行合并
    private func performMerge() {
        guard !selectedCards.isEmpty else {
            print("没有选择要合并的卡片")
            return
        }

        mergeErrorMessage = nil
        
        // 获取头部固定卡片的内容
        guard let cardDetail = cardDetailManager.cardDetail else {
            print("头部卡片数据未加载")
            return
        }
        guard let anchorVersionID = cardDetail.noteDocumentVersionID,
              !anchorVersionID.isEmpty else {
            mergeErrorMessage = "Card version unavailable"
            return
        }
        
        // 构建选择的卡片列表，包含头部卡片
        var selectedCardsList: [SelectedCard] = []
        
        // 添加头部卡片（当前卡片）
        selectedCardsList.append(
            SelectedCard(
                id: cardDetail.id,
                versionID: anchorVersionID,
                content: cardDetail.content
            )
        )
        
        // 添加选中的链接卡片
        for cardId in selectedCards {
            if let linkedCard = allCards.first(where: { $0.id == cardId }) {
                guard let versionID = linkedCard.versionID,
                      !versionID.isEmpty else {
                    mergeErrorMessage = "Card version unavailable"
                    return
                }
                selectedCardsList.append(
                    SelectedCard(
                        id: linkedCard.id,
                        versionID: versionID,
                        content: linkedCard.content
                    )
                )
            }
        }
        
        print("开始合并 \(selectedCardsList.count) 张卡片")
        print("包含当前卡片: \(cardDetail.id)")
        print("选中卡片: \(selectedCards)")
        
        mergeCardsManager.mergeCards(selectedCards: selectedCardsList) { result in
            switch result {
            case .success(let previewResponse):
                print("合并预览成功: \(previewResponse.message)")
                DispatchQueue.main.async {
                    self.previewData = previewResponse
                    self.showNewInsight = true
                }
            case .failure(let error):
                print("卡片合并失败: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.mergeErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: 执行搜索
    private func performSearch() {
        // 如果搜索框为空，显示所有卡片
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectableCards = allCards
            return
        }
        
        print("搜索: \(searchText)")
        
        isLoadingCards = true
        cardsErrorMessage = nil
        
        networkManager.getUserAllCards(searchType: "own+favorited", search: searchText, limit: 50, cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoadingCards = false
                    switch completion {
                    case .finished:
                        print("搜索完成")
                    case .failure(let error):
                        print("搜索失败: \(error.localizedDescription)")
                        self.cardsErrorMessage = error.localizedDescription
                    }
                },
                receiveValue: { response in
                    self.cardsErrorMessage = nil
                    
                    var searchResults: [MergeCard] = []
                    
                    searchResults.append(contentsOf: response.data.ownCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: true)
                    })
                    
                    searchResults.append(contentsOf: response.data.favoritedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    // 添加点赞的卡片
                    searchResults.append(contentsOf: response.data.likedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    // 添加链接的卡片
                    searchResults.append(contentsOf: response.data.linkedCards.map { card in
                        self.convertUserAllCardToMergeCard(card, isOwnCard: false)
                    })
                    
                    // 更新可选择的卡片列表
                    self.selectableCards = searchResults
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 获取预览用的选中卡片
    private func getSelectedCardsForPreview() -> [SelectedCard] {
        guard let cardDetail = cardDetailManager.cardDetail else {
            return []
        }
        guard let anchorVersionID = cardDetail.noteDocumentVersionID,
              !anchorVersionID.isEmpty else {
            return []
        }
        
        var selectedCardsList: [SelectedCard] = []
        
        selectedCardsList.append(
            SelectedCard(
                id: cardDetail.id,
                versionID: anchorVersionID,
                content: cardDetail.content
            )
        )
        
        // 添加选中的链接卡片
        for cardId in selectedCards {
            if let linkedCard = allCards.first(where: { $0.id == cardId }) {
                guard let versionID = linkedCard.versionID,
                      !versionID.isEmpty else {
                    return []
                }
                selectedCardsList.append(
                    SelectedCard(
                        id: linkedCard.id,
                        versionID: versionID,
                        content: linkedCard.content
                    )
                )
            }
        }
        
        return selectedCardsList
    }
    
    // MARK: 动画控制
    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                animationPhase = (animationPhase + 1) % 4
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    // MARK: - 转换SearchCard为MergeCard
    private func convertSearchCardToMergeCard(_ searchCard: SearchCard) -> MergeCard {
        // 格式化日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let displayDate: String
        if let date = dateFormatter.date(from: searchCard.createdAt) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 86400 { // 24小时内
                displayDate = "Today"
            } else if timeInterval < 172800 { // 48小时内
                displayDate = "Yesterday"
            } else {
                let days = Int(timeInterval / 86400)
                displayDate = "\(days) days ago"
            }
        } else {
            displayDate = "Unknown"
        }
        
        return MergeCard(
            id: searchCard.id,
            versionID: searchCard.noteDocumentVersionID,
            date: displayDate,
            content: searchCard.content,
            contentJSON: searchCard.contentJSON,
            backgroundMediaRef: searchCard.backgroundMediaRef,
            tags: searchCard.tags,
            isUserCard: true,
            userName: searchCard.author.username,
            avatarUrl: searchCard.author.avatarUrl,
            favoriteCount: searchCard.favoriteCount,
            rate: searchCard.rate
        )
    }
    
    // MARK: 转换UserAllCard为MergeCard
    private func convertUserAllCardToMergeCard(_ userAllCard: UserAllCard, isOwnCard: Bool) -> MergeCard {
        // 格式化日期
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let displayDate: String
        if let date = dateFormatter.date(from: userAllCard.createdAt) {
            let now = Date()
            let timeInterval = now.timeIntervalSince(date)
            
            if timeInterval < 86400 { // 24小时内
                displayDate = "Today"
            } else if timeInterval < 172800 { // 48小时内
                displayDate = "Yesterday"
            } else {
                let days = Int(timeInterval / 86400)
                displayDate = "\(days) days ago"
            }
        } else {
            displayDate = "Unknown"
        }
        
        return MergeCard(
            id: userAllCard.id,
            versionID: userAllCard.noteDocumentVersionID,
            date: displayDate,
            content: userAllCard.content,
            contentJSON: userAllCard.contentJSON,
            backgroundMediaRef: userAllCard.backgroundMediaRef,
            tags: userAllCard.tags,
            isUserCard: isOwnCard,
            userName: isOwnCard ? userAllCard.author?.username : nil,
            avatarUrl: isOwnCard ? userAllCard.author?.avatar : nil,
            favoriteCount: userAllCard.favoriteCount,
            rate: userAllCard.rate // 使用真实的 rate 值
        )
    }
}

// MARK: - Merge Card Data Model
struct MergeCard: Identifiable {
    let id: String
    let versionID: String?
    let date: String
    let content: String
    let contentJSON: String?
    let backgroundMediaRef: String?
    let tags: [String]
    let isUserCard: Bool
    let userName: String?
    let avatarUrl: String?
    let favoriteCount: Int
    let rate: Int
    
    init(
        id: String,
        versionID: String? = nil,
        date: String,
        content: String,
        contentJSON: String? = nil,
        backgroundMediaRef: String? = nil,
        tags: [String],
        isUserCard: Bool,
        userName: String? = nil,
        avatarUrl: String? = nil,
        favoriteCount: Int = 0,
        rate: Int = 1
    ) {
        self.id = id
        self.versionID = versionID
        self.date = date
        self.content = content
        self.contentJSON = contentJSON
        self.backgroundMediaRef = backgroundMediaRef
        self.tags = tags
        self.isUserCard = isUserCard
        self.userName = userName
        self.avatarUrl = avatarUrl
        self.favoriteCount = favoriteCount
        self.rate = rate
    }
}

// MARK: - Merge Card View
struct MergeCardView: View {
    let card: MergeCard
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let isSelectable: Bool

    init(
        card: MergeCard,
        isSelected: Bool,
        onToggleSelection: @escaping () -> Void,
        isSelectable: Bool = true
    ) {
        self.card = card
        self.isSelected = isSelected
        self.onToggleSelection = onToggleSelection
        self.isSelectable = isSelectable
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if card.isUserCard {
                    mergeCardAvatar
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.userName ?? "Chorai")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(card.date)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    // 普通卡片日期
                    Text(card.date)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
            }
            
            LibraryCardContentPreview(
                content: card.content,
                contentJSON: card.contentJSON,
                cardID: card.id,
                textFont: .system(size: 14, weight: .regular)
            )
            
            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(card.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(mergeCardTagBackground)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 1)
                }
                
                if card.isUserCard {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image("favorite")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                            Text("\(card.favoriteCount)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background {
            LibraryCardBackgroundSurface(
                backgroundMediaRef: card.backgroundMediaRef,
                rate: card.rate
            ) {
                mergeCardBackground
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isSelected
                        ? Color(red: 198 / 255, green: 89 / 255, blue: 231 / 255)
                        : Color.clear,
                    lineWidth: 2
                )
        }
        .contentShape(Rectangle())
        .adaptiveContentGutter()
        .onTapGesture {
            guard isSelectable else { return }
            onToggleSelection()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("merge.card.\(card.id)")
        .accessibilityValue(isSelected ? "selected" : "unselected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isSelectable else { return }
            onToggleSelection()
        }
    }

    private var mergeCardAvatar: some View {
        Group {
            if let avatarURL = avatarURL {
                AsyncImage(url: avatarURL) { image in
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
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var avatarURL: URL? {
        guard let avatarURL = card.avatarUrl?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !avatarURL.isEmpty else {
            return nil
        }
        if avatarURL.hasPrefix("http://") || avatarURL.hasPrefix("https://") {
            return URL(string: avatarURL)
        }
        return URL(string: APIConfiguration.resourceURLString(avatarURL))
    }

    private var hasCustomBackground: Bool {
        guard let backgroundMediaRef = card.backgroundMediaRef else {
            return false
        }
        return !backgroundMediaRef.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private var mergeCardTagBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                (hasCustomBackground ? Color.black : Color.white)
                    .opacity(
                        LibraryCardReadabilityPolicy.tagSurfaceOpacity(
                            hasBackground: hasCustomBackground
                        )
                    )
            )
            .overlay(mergeCardTagTopLeftHighlight)
            .overlay(mergeCardTagBottomRightHighlight)
            .overlay(mergeCardTagTopEdgeHighlight)
            .overlay(mergeCardTagBottomEdgeHighlight)
    }

    private var mergeCardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .background(.ultraThinMaterial.opacity(0.55))
            .cornerRadius(16)
            .overlay(topLeftHighlight)
            .overlay(bottomRightHighlight)
            .overlay(topEdgeHighlight)
            .overlay(bottomEdgeHighlight)
    }
    
    // MARK: 标签高光效果
    private var mergeCardTagTopLeftHighlight: some View {
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
    
    private var mergeCardTagBottomRightHighlight: some View {
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
    
    private var mergeCardTagTopEdgeHighlight: some View {
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
    
    private var mergeCardTagBottomEdgeHighlight: some View {
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
    
    // MARK: 高光效果
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

// MARK: 固定卡片视图
struct FixedMergeCardView: View {
    let card: MergeCard
    
    var body: some View {
        MergeCardView(
            card: card,
            isSelected: false,
            onToggleSelection: {},
            isSelectable: false
        )
    }
}


#Preview {
    MergeView(cardId: "ast_preview")
} 
