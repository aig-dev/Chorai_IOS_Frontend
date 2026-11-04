import SwiftUI
import Combine
import CoreFlow

// MARK: 关联笔记数据模型
struct DetailRelatedNote: Identifiable {
    let id = UUID()
    let avatar: String
    let title: String
    let description: String
}

struct DetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showPopupMenu = false
    @State private var committedOwnedCardState: OwnedCardActionSnapshot?
    @State private var ownedCardActionRefresh: OwnedCardActionRefresh?
    @State private var ownedCardRefreshFailed = false
    @State private var ownedCardRefreshRequestID: UUID?
    @State private var navigateToUserProfile = false
    @State private var isRelatedNotesExpanded = false
    @State private var contentHeight: CGFloat = 200
    @StateObject private var cardDetailManager = CardDetailManager.shared
    
    // 状态管理
    @StateObject private var likeStore: CardLikeStore
    @State private var isFavorited = false
    @State private var favoriteCount = 0
    @State private var isFavoriteLoading = false
    @State private var favoriteError: String?
    @State private var commentCount = 0
    @State private var cancellables = Set<AnyCancellable>()
    
    // 聊天相关状态
    @State private var navigateToChat = false
    @State private var conversationId: String? = nil
    @State private var isCreatingConversation = false
    
    // 关注相关状态
    @State private var isFollowing = false
    @State private var isFollowLoading = false
    
    let cardId: String
    
    init(cardId: String = "") {
        self.cardId = cardId
        _likeStore = StateObject(
            wrappedValue: CardLikeStore(
                state: CardLikeState(
                    cardID: cardId,
                    isLiked: false,
                    likeCount: 0
                ),
                service: NetworkCoreCardLikeService(),
                onCommit: CardEngagementCenter.shared.publish
            )
        )
    }
    
    private var isCurrentCardOwned: Bool {
        guard cardDetailManager.cardDetail?.id == cardId else { return false }
        if let isOwner = cardDetailManager.cardDetail?.isOwner {
            return isOwner
        }
        guard let authorId = cardDetailManager.cardDetail?.author?.actorId,
              let currentUserId = AuthManager.shared.currentUser?.id else {
            return false
        }
        return authorId == currentUserId
    }
    
    private var currentDetailUserCard: UserCard? {
        guard let detail = cardDetailManager.cardDetail, detail.id == cardId else {
            return nil
        }
        return UserCard(
            id: detail.id,
            title: detail.title,
            content: detail.content,
            contentJSON: detail.contentJSON,
            backgroundMediaRef: detail.backgroundMediaRef,
            contentHash: detail.contentHash,
            isPublic: committedOwnedCardState?.isPublic ?? detail.isPublic,
            tags: detail.tags,
            createdAt: detail.createdAt,
            updatedAt: detail.updatedAt,
            likeCount: detail.likeCount,
            commentCount: detail.commentCount,
            isLiked: detail.isLiked,
            isPinned: committedOwnedCardState?.isPinned ?? detail.isPinned ?? false,
            pinnedAt: committedOwnedCardState.map { $0.pinnedAt } ?? detail.pinnedAt,
            isFavorited: detail.isFavorited,
            favoriteCount: detail.favoriteCount,
            rate: detail.rate,
            ownerActorId: detail.ownerActorId,
            isOwner: detail.isOwner
        )
    }
    
    private func handleOwnedCardActionCommit(_ commit: OwnedCardActionCommit) {
        guard commit.cardID == cardId else { return }
        if case .removed = commit {
            if cardDetailManager.cardDetail?.id == cardId {
                cardDetailManager.clearCardDetail()
            }
            dismiss()
            return
        }
        guard let card = currentDetailUserCard else { return }
        var state = committedOwnedCardState ?? OwnedCardActionSnapshot(
            cardID: card.id, isOwned: isCurrentCardOwned,
            isPublic: card.isPublic, isPinned: card.isPinned, pinnedAt: card.pinnedAt
        )
        switch commit {
        case .visibility(_, let isPublic): state.isPublic = isPublic
        case .pin(_, let isPinned, let pinnedAt):
            state.isPinned = isPinned
            state.pinnedAt = pinnedAt
        case .removed: return
        }
        // A list/detail projection may lag a successful mutation; use its exact
        // service receipt immediately without making a second request.
        committedOwnedCardState = state
    }

    private func handleOwnedCardRouteDismissal(_ dismissal: CardNavigationDismissal) {
        guard case .editor(let editedID) = dismissal.route, editedID == cardId else { return }
        loadCardDetail(refreshOwnedCardActions: true)
    }

    // 关联笔记数据
    @State private var relatedNotes: [CardLinkItem] = []
    @State private var isLoadingLinks = false
    @State private var navigateToRelatedDetail = false
    @State private var selectedRelatedCardId: String? = nil
    
    var body: some View {
        ZStack {
            // 背景图片
            ChoraiBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 主要内容
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        readerCard
                            .padding(.horizontal, 24)
                            .padding(.top, 18)

                        // 时间戳和标签
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(formatDate(cardDetailManager.cardDetail?.createdAt ?? ""))
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                
                                if currentDetailUserCard?.isPublic == true {
                                Image(systemName: "globe")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                }
                                
                                Spacer()
                                
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(cardDetailManager.cardDetail?.tags ?? [], id: \.self) { tag in
                                        CardMetadataTagCapsule(
                                            tag: tag,
                                            showsRemoveIndicator: false
                                        )
                                    }
                                }
                                .padding(.horizontal, 1)
                            }
                        }
                        .padding(.horizontal, 20)

                        if !relatedNotes.isEmpty {
                            HStack {
                                Spacer()
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                        isRelatedNotesExpanded.toggle()
                                    }
                                } label: {
                                    Image(
                                        systemName: isRelatedNotesExpanded
                                            ? "chevron.up"
                                            : "chevron.down"
                                    )
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(ChoraiTheme.secondaryInk)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Related notes")
                                .accessibilityValue(isRelatedNotesExpanded ? "Expanded" : "Collapsed")
                                .accessibilityIdentifier(
                                    "detailRelatedLinksDisclosure"
                                )
                            }
                            .padding(.horizontal, 20)

                            if isRelatedNotesExpanded {
                                VStack(spacing: 0) {
                                    ForEach(
                                        Array(relatedNotes.enumerated()),
                                        id: \.element.id
                                    ) { index, note in
                                        Button {
                                            selectedRelatedCardId = note.linkedCardId
                                            DispatchQueue.main.async {
                                                navigateToRelatedDetail = true
                                            }
                                        } label: {
                                            CardMetadataRelatedRow(
                                                avatarURL: note.author?.avatar,
                                                title: note.author?.userName
                                                    ?? note.title
                                                    ?? "Related note",
                                                previewHTML: note.content
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(
                                            note.author?.userName
                                                ?? note.title
                                                ?? "Related note"
                                        )

                                        if index < relatedNotes.count - 1 {
                                            Rectangle()
                                                .fill(ChoraiTheme.ink.opacity(0.1))
                                                .frame(height: 1)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .transition(
                                    .opacity.combined(with: .move(edge: .top))
                                )
                            }
                        }
                        readerEngagement
                    }
                    .padding(.bottom, 24)
                }
                

            }
        }
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .choraiFavoriteChanged)) { notification in
            guard notification.userInfo?["cardID"] as? String == cardId,
                  let saved = notification.userInfo?["isFavorited"] as? Bool else { return }
            isFavorited = saved
            if let count = notification.userInfo?["count"] as? Int { favoriteCount = count }
        }
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !isCurrentCardOwned {
                    Button(action: toggleFavorite) {
                        Image(systemName: isFavorited ? "bookmark.fill" : "bookmark")
                    }
                    .disabled(isFavoriteLoading)
                    .accessibilityLabel(isFavorited ? "Remove from collection" : "Collect note")
                }
                if let card = currentDetailUserCard {
                    NativeCardActionsMenu(cardData: card, layout: isCurrentCardOwned ? .grid3x3 : .grid2x2, isOwnCard: isCurrentCardOwned) {
                        Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("More actions").accessibilityIdentifier("detail.menu.open")
                    .disabled(cardDetailManager.isLoading)
                }
            }
        }
        .popupMenu(
            isPresented: $showPopupMenu,
            layout: isCurrentCardOwned ? .grid3x3 : .grid2x2,
            cardData: currentDetailUserCard,
            isOwnCard: isCurrentCardOwned,
            onRouteDismissed: handleOwnedCardRouteDismissal,
            ownedCardActionRefresh: ownedCardActionRefresh,
            ownedCardActionRefreshInFlight: ownedCardRefreshRequestID != nil,
            onOwnedCardActionCommitted: handleOwnedCardActionCommit
        )
        .alert("Couldn’t refresh this note", isPresented: $ownedCardRefreshFailed) {
            Button("Retry") { loadCardDetail(refreshOwnedCardActions: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The last confirmed status is still shown. Try again to load your changes.")
        }
        .navigationDestination(isPresented: $navigateToUserProfile) {
            UserProfileView(actorId: cardDetailManager.cardDetail?.author?.actorId ?? "")
        }
        .navigationDestination(isPresented: $navigateToChat) {
            ChatDetailView(
                conversationId: conversationId ?? "",
                contactName: cardDetailManager.cardDetail?.author?.userName ?? "User",
                contactStatus: "Online",
                contactAvatar: "avatar"
            )
        }
        .navigationDestination(isPresented: $navigateToRelatedDetail) {
            if let relatedCardId = selectedRelatedCardId {
                DetailView(cardId: relatedCardId)
            } else {
                EmptyView()
            }
        }
        .onAppear {
            if !cardId.isEmpty {
                loadCardDetail()
            }
        }
        .onChange(of: cardId) { newCardId in
            committedOwnedCardState = nil
            ownedCardActionRefresh = nil
            ownedCardRefreshFailed = false
            if !newCardId.isEmpty {
                loadCardDetail()
                
            }
        }
        .overlay(alignment: .topLeading) {
            #if DEBUG
            Group {
                if cardDetailManager.isLoading {
                    Text("Detail loading")
                        .font(.system(size: 1))
                        .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("screen.detail.loading")
                } else if cardDetailManager.cardDetail != nil {
                    VStack(spacing: 0) {
                        Text("Detail loaded")
                            .accessibilityIdentifier("screen.detail.loaded")
                        Text(cardDetailManager.cardDetail?.id ?? "")
                            .accessibilityIdentifier("screen.detail.loaded-card-id")
                    }
                    .font(.system(size: 1))
                    .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                    .frame(width: 1, height: 1)
                } else if cardDetailManager.error != nil {
                    Text("Detail error")
                        .font(.system(size: 1))
                        .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("screen.detail.error")
                } else {
                    Text("Detail idle")
                        .font(.system(size: 1))
                        .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("screen.detail.content")
                }
            }
            #endif
        }
        .overlay(alignment: .topTrailing) {
            #if DEBUG
            Text(cardId)
                .font(.system(size: 1))
                .foregroundColor(ChoraiTheme.ink.opacity(0.01))
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("screen.detail.card-id")
            #endif
        }
        .onReceive(CardEngagementCenter.shared.likes) { state in
            likeStore.applyCommitted(state)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var readerEngagement: some View {
                VStack(spacing: 8) {
                    HStack(spacing: 24) {
                        // 点赞按钮
                        Button(action: likeStore.toggle) {
                            HStack(spacing: 6) {
                            Image(systemName: likeStore.state.isLiked ? "heart.fill" : "heart")
                                .font(.body)
                                .foregroundStyle(likeStore.state.isLiked ? ChoraiTheme.gold : ChoraiTheme.ink)
                                Text("\(likeStore.state.likeCount)")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(ChoraiTheme.ink)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(likeStore.isMutating)
                        .accessibilityLabel(likeStore.state.isLiked ? "Unlike" : "Like")
                        .accessibilityValue(likeStore.state.isLiked ? "true" : "false")
                        .accessibilityIdentifier("detail.like.\(cardId)")

                    // 评论按钮
                    CommentButton(cardId: cardId, commentCount: commentCount)
                        .scaleEffect(1.1)
                        .accessibilityIdentifier("detail.comment.open")

                    // 收藏按钮
                    if !isCurrentCardOwned {
                        Button(action: {
                            toggleFavorite()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isFavorited ? "bookmark.fill" : "bookmark")
                                    .font(.body)
                                    .foregroundStyle(isFavorited ? ChoraiTheme.gold : ChoraiTheme.ink)
                            Text("\(favoriteCount)")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(ChoraiTheme.ink)
                            }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(isFavoriteLoading)
                        .accessibilityLabel(isFavorited ? "Unfavorite" : "Favorite")
                        .accessibilityValue(isFavorited ? "true" : "false")
                        .accessibilityIdentifier("detail.favorite.\(cardId)")
                    }

                        Spacer()
                    }
                    if let favoriteError {
                        Text(favoriteError)
                            .font(.footnote)
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                            .accessibilityIdentifier("detail.favorite.error")
                    }
                    if case .failed = likeStore.phase {
                        Text("Like failed. Try again.")
                            .font(.footnote)
                            .foregroundColor(ChoraiTheme.secondaryInk)
                            .accessibilityIdentifier("detail.like.error.\(cardId)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .padding(.bottom, 8)
    }

    private var readerCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let cardDetail = cardDetailManager.cardDetail {
                VStack(alignment: .leading, spacing: 4) {
                    ChoraiReadingIdentity(rate: cardDetail.rate)
                    readerAuthorRow
                }
                AdaptiveHTMLWebView(htmlContent: cardDetail.content, height: $contentHeight)
                    .frame(height: contentHeight)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("Loading note")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.reader.document")
    }

    private var readerAuthorRow: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    readerAuthorButton
                    HStack(spacing: 12) {
                        readerMessageButton
                        readerFollowButton
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    readerAuthorButton
                    readerMessageButton
                    readerFollowButton
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(ChoraiTheme.secondaryInk)
    }

    private var readerAuthorButton: some View {
        Button {
                guard cardDetailManager.cardDetail?.author?.actorId != nil else { return }
                navigateToUserProfile = true
            } label: {
                HStack(spacing: 8) {
                    readerAuthorAvatar
                    Text(readerAuthorName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .frame(minHeight: 44)
            .accessibilityLabel("Open author, \(readerAuthorName)")
            .accessibilityIdentifier("detail.author")
            .disabled(cardDetailManager.cardDetail?.author?.actorId == nil)
    }

    private var readerMessageButton: some View {
        Button(action: createConversation) {
                Group {
                    if isCreatingConversation { ProgressView().controlSize(.small) }
                    else { Image(systemName: "bubble.left").font(.subheadline) }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Message author")
            .accessibilityIdentifier("detail.author.chat")
            .disabled(isCreatingConversation || cardDetailManager.cardDetail?.author?.actorId == nil)
    }

    private var readerFollowButton: some View {
        Button(action: toggleFollow) {
                Group {
                    if isFollowLoading { ProgressView().controlSize(.small) }
                    else { Text(isFollowing ? "Unfollow" : "Follow").font(.subheadline.weight(.medium)) }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(isFollowing ? "Unfollow author" : "Follow author")
            .accessibilityValue(isFollowing ? "Following" : "Not following")
            .accessibilityIdentifier("detail.author.follow")
            .disabled(isFollowLoading || cardDetailManager.cardDetail?.author?.actorId == nil)
    }

    private var readerAuthorAvatar: some View {
        Group {
            if let rawURL = cardDetailManager.cardDetail?.author?.avatarUrl,
               !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let url = URL(string: APIConfiguration.resourceURLString(rawURL)) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                    else { readerAuthorPlaceholder }
                }
            } else { readerAuthorPlaceholder }
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var readerAuthorPlaceholder: some View {
        Text(readerAuthorInitials)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(ChoraiTheme.secondaryInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ChoraiTheme.ink.opacity(0.08), in: Circle())
    }

    private var readerAuthorName: String {
        let name = cardDetailManager.cardDetail?.author?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Unknown User" : name
    }

    private var readerAuthorInitials: String {
        readerAuthorName.split(whereSeparator: \.isWhitespace)
            .prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    // MARK: 加载卡片详情
    private func loadCardDetail(refreshOwnedCardActions: Bool = false) {
        // An explicit return from Edit establishes a new metadata authority.
        // Keep the last confirmed state if that refresh fails.
        if !refreshOwnedCardActions { cardDetailManager.cardDetail = nil }
        let refreshRequestID = UUID()
        if refreshOwnedCardActions { ownedCardRefreshRequestID = refreshRequestID }

        cardDetailManager.fetchCardDetail(cardId: cardId) { result in
            if refreshOwnedCardActions {
                guard ownedCardRefreshRequestID == refreshRequestID else { return }
                ownedCardRefreshRequestID = nil
            }
            switch result {
            case .success(let cardDetail):
                guard cardDetail.id == cardId else { return }
                if refreshOwnedCardActions {
                    let snapshot = OwnedCardActionSnapshot(
                        cardID: cardDetail.id,
                        isOwned: cardDetail.isOwner ?? (AuthManager.shared.currentUser.map { cardDetail.author?.actorId == $0.id } ?? false),
                        isPublic: cardDetail.isPublic, isPinned: cardDetail.isPinned ?? false,
                        pinnedAt: cardDetail.pinnedAt
                    )
                    committedOwnedCardState = snapshot
                    ownedCardActionRefresh = OwnedCardActionRefresh(snapshot: snapshot)
                    ownedCardRefreshFailed = false
                }
                print("详情加载成功: \(cardDetail.title ?? "")")
                
                // 初始化状态
                DispatchQueue.main.async {
                    self.likeStore.hydrate(
                        CardLikeState(
                            cardID: cardDetail.id,
                            isLiked: cardDetail.isLiked,
                            likeCount: cardDetail.likeCount
                        )
                    )
                    self.isFavorited = cardDetail.isFavorited ?? false
                    self.favoriteCount = cardDetail.favoriteCount ?? 0
                    self.commentCount = cardDetail.commentCount ?? 0
                }
                
                loadRelatedNotes()
                checkFollowStatus()
            case .failure(let error):
                if refreshOwnedCardActions { ownedCardRefreshFailed = true }
                print("详情加载失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 加载关联笔记
    private func loadRelatedNotes() {
      
        
        isLoadingLinks = true
        print("加载关联笔记: cardId=\(cardId)")
        
        NetworkManager.shared.getCardLinks(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    self.isLoadingLinks = false
                    if case .failure(let error) = completion {
                        print("加载关联笔记失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    if response.success {
                        let allLinks = response.data.outgoingLinks + response.data.incomingLinks
                        self.relatedNotes = allLinks
                    } else {
                        print("关联笔记失败: \(response.message ?? "未知错误")")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 收藏功能
    private func toggleFavorite() {
        guard AuthManager.shared.currentUser != nil else {
            print("用户未登录")
            return
        }
        guard !isCurrentCardOwned, !isFavoriteLoading else { return }
        isFavoriteLoading = true
        favoriteError = nil
        let networkManager = NetworkManager.shared
        
        if isFavorited {
            // 取消收藏
            networkManager.unfavoriteCard(cardId: cardId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        isFavoriteLoading = false
                        if case .failure = completion { favoriteError = "Couldn’t update collection. Try again." }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFavorited = false
                            self.favoriteCount = max(0, self.favoriteCount - 1)
                            publishFavoriteChange()
                        } else {
                            favoriteError = "Couldn’t update collection. Try again."
                        }
                    }
                )
                .store(in: &cancellables)
        } else {
            // 收藏
            networkManager.favoriteCard(cardId: cardId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        isFavoriteLoading = false
                        if case .failure = completion { favoriteError = "Couldn’t update collection. Try again." }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFavorited = true
                            self.favoriteCount += 1
                            publishFavoriteChange()
                        } else {
                            favoriteError = "Couldn’t update collection. Try again."
                        }
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    private func publishFavoriteChange() {
        NotificationCenter.default.post(
            name: .choraiFavoriteChanged,
            object: nil,
            userInfo: ["cardID": cardId, "isFavorited": isFavorited, "count": favoriteCount]
        )
    }

    // MARK: 发起会话
    private func createConversation() {
        guard !isCreatingConversation else { return }
        
        guard let authorId = cardDetailManager.cardDetail?.author?.actorId else {
            print("无法获取作者ID")
            return
        }
        
        isCreatingConversation = true
        print("开始发起会话: participantId=\(authorId)")
        
        let request = CreateConversationRequest(participantId: authorId)
        
        NetworkManager.shared.createConversation(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isCreatingConversation = false
                    if case .failure(let error) = completion {
                        print("发起会话失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    if response.success {
                        DispatchQueue.main.async {
                            self.conversationId = response.conversation.id
                            print("设置 conversationId: \(self.conversationId ?? "")")
                            
                            // 延迟一点时间确保状态更新
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.navigateToChat = true
                                print("设置 navigateToChat: \(self.navigateToChat)")
                            }
                        }
                    } else {
                        print("发起会话失败: 服务器返回失败")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: 关注功能
    private func checkFollowStatus() {
        guard AuthManager.shared.currentUser != nil else {
            print("用户未登录，无法检查关注状态")
            return
        }
        
        guard let authorId = cardDetailManager.cardDetail?.author?.actorId else {
            print("无法获取作者ID")
            return
        }
        
        
        NetworkManager.shared.checkFollowStatus(targetActorIds: [authorId])
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("关注状态失败: \(error.localizedDescription)")
                    }
                },
                receiveValue: { response in
                    if response.success {
                        let followStatus = response.data[authorId] ?? false
                        self.isFollowing = followStatus
                        print("关注状态: \(followStatus)")
                    } else {
                        print("检查关注状态失败: 服务器返回失败")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func toggleFollow() {
        guard !isFollowLoading else { return }
        guard AuthManager.shared.currentUser != nil else {
            print("用户未登录")
            return
        }
        
        guard let authorId = cardDetailManager.cardDetail?.author?.actorId else {
            print("无法获取作者ID")
            return
        }
        
        isFollowLoading = true
        
        if isFollowing {
            // 取消关注
            NetworkManager.shared.unfollowUser(targetActorId: authorId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        isFollowLoading = false
                        if case .failure(let error) = completion {
                            print("失败: \(error.localizedDescription)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFollowing = false
                            print("取消关注成功")
                        } else {
                            print("失败: 服务器返回失败")
                        }
                    }
                )
                .store(in: &cancellables)
        } else {
            // 关注
            
            NetworkManager.shared.followUser(targetActorId: authorId)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        isFollowLoading = false
                        if case .failure(let error) = completion {
                            print("关注失败: \(error.localizedDescription)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFollowing = true
                            print("关注成功: \(response.message)")
                        } else {
                            print("关注失败: 服务器返回失败")
                        }
                    }
                )
                .store(in: &cancellables)
        }
    }
    
    // MARK: - 格式化日期
    private func formatDate(_ dateString: String) -> String {
        CardTimestamp.dateOnly(from: dateString)
    }
}

#Preview {
    DetailView(cardId: "ast_preview")
}
