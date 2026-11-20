import SwiftUI
import Combine
import CoreFlow

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayoutMetrics) private var adaptiveLayout
    @State private var showPopupMenu = false
    @StateObject private var cardsManager = HomeCardsManager()
    @StateObject private var profileStore: CommunityProfileStore

    // 聊天相关状态
    @State private var navigateToChat = false
    @State private var conversationId: String? = nil
    @State private var isCreatingConversation = false
    @State private var cancellables = Set<AnyCancellable>()

    // 菜单相关状态
    @State private var popupMenuLayout: PopupMenuLayout = .grid2x2
    @State private var currentMenuCardData: UserCard? = nil

    // 导航状态
    @State private var navigateToDetail = false
    @State private var selectedCardId: String? = nil
    @State private var showReport = false
    @State private var showActionSheet = false
    @State private var showBlockConfirmation = false
    @State private var showFollowList = false
    @State private var followListKind: FollowListKind = .followers

    let actorId: String

    init(
        actorId: String,
        service: any CoreCommunityProfileServing = NetworkCommunityProfileService()
    ) {
        self.actorId = actorId
        _profileStore = StateObject(
            wrappedValue: CommunityProfileStore(service: service)
        )
    }

    private var isOwnProfile: Bool {
        actorId == AuthManager.shared.currentUser?.id
    }

    private var isFollowLoading: Bool {
        if case .mutatingFollow = profileStore.phase { return true }
        return false
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                profileHeader
                profileStatus
                Divider().overlay(ChoraiTheme.separator)
                if cardsManager.isLoading && cardsManager.cards.isEmpty {
                    ProgressView("Loading notes…")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else if cardsManager.cards.isEmpty {
                    Label("No notes", systemImage: "doc.text")
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(cardsManager.cards, id: \.id) { card in
                        UserPostCard(
                            card: card,
                            onShowMenu: { cardData in
                                currentMenuCardData = cardData
                                popupMenuLayout = .grid2x2
                            },
                            onCardTap: { cardId in
                                selectedCardId = cardId
                                DispatchQueue.main.async { navigateToDetail = true }
                            },
                            onChatTap: { createConversation() },
                            username: profileStore.profile?.username ?? "User",
                            avatarUrl: profileStore.profile?.avatarURL,
                            disableFavorite: false
                        )
                        Divider().overlay(ChoraiTheme.separator)
                    }
                }
            }
            .adaptiveContentGutter()
            .padding(.top, 24)
            .padding(.bottom, 32)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("profile.primary-surface")
        }
        .choraiPageBackground()
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isOwnProfile {
                    Button { showActionSheet = true } label: {
                        Image(systemName: "ellipsis")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Profile actions")
                    .accessibilityIdentifier("user-profile.actions")
                }
            }
        }
        .onAppear {
            profileStore.load(actorID: actorId)

            // 加载用户卡片数据
            print("开始加载用户公开卡片: actorId=\(actorId)")
            cardsManager.loadPublicProfileCards(actorId: actorId, refresh: true)
        }
        .confirmationDialog("", isPresented: $showActionSheet, titleVisibility: .hidden) {
            Button("Report this user", role: .destructive) {
                showReport = true
            }
            Button("Block this user", role: .destructive) {
                showBlockConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Block User", isPresented: $showBlockConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) {
                profileStore.block()
            }
        } message: {
            Text("Are you sure you want to block this user?")
        }
        .onChange(of: profileStore.didBlock) { didBlock in
            if didBlock { dismiss() }
        }
        .navigationDestination(isPresented: $navigateToChat) {
            ChatDetailView(
                conversationId: conversationId ?? "",
                contactName: profileStore.profile?.username ?? "User",
                contactStatus: "Online",
                contactAvatar: "avatar"
            )
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            if let cardId = selectedCardId {
                DetailView(cardId: cardId)
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showReport) {
            ContentReportView(targetType: .actor, targetID: actorId)
        }
        .sheet(isPresented: $showFollowList) {
            FollowListView(
                actorID: actorId,
                actorName: profileStore.profile?.username ?? "User",
                kind: followListKind,
                viewerActorID: AuthManager.shared.currentUser?.id ?? ""
            )
        }
        .popupMenu(isPresented: $showPopupMenu, layout: popupMenuLayout, cardData: currentMenuCardData, isOwnCard: false)
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text("User profile")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("screen.user-profile")
                Text(actorId)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("user-profile.actor-id")
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                ProfilePortrait(rawURL: profileStore.profile?.avatarURL)
                Text(profileStore.phase == .loading ? "Loading…" : profileStore.profile?.username ?? "User")
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundStyle(ChoraiTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 28) {
                ProfileCountButton(
                    count: profileStore.phase == .loading ? nil : profileStore.profile?.followingCount ?? 0,
                    label: "following", identifier: "user-profile.following-count"
                ) {
                    followListKind = .following
                    showFollowList = true
                }
                ProfileCountButton(
                    count: profileStore.phase == .loading ? nil : profileStore.profile?.followerCount ?? 0,
                    label: "followers", identifier: "user-profile.followers-count"
                ) {
                    followListKind = .followers
                    showFollowList = true
                }
                Spacer(minLength: 0)
            }
            if !isOwnProfile {
                HStack(spacing: 12) {
                    Button { profileStore.toggleFollow() } label: {
                        HStack(spacing: 8) {
                            if isFollowLoading {
                                ProgressView().tint(profileStore.profile?.isFollowing == true ? ChoraiTheme.ink : ChoraiTheme.onAccent)
                            }
                            Text(profileStore.profile?.isFollowing == true ? "Unfollow" : "Follow")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(minWidth: 90, minHeight: 44)
                        .foregroundStyle(profileStore.profile?.isFollowing == true ? ChoraiTheme.ink : ChoraiTheme.onAccent)
                    }
                    .choraiGlassButton(prominent: profileStore.profile?.isFollowing != true)
                    .disabled(isFollowLoading || profileStore.profile == nil)
                    .accessibilityIdentifier("user-profile.follow")
                    .accessibilityValue(profileStore.profile?.isFollowing == true ? "following" : "not-following")
                    Button(action: createConversation) {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .choraiGlassButton()
                    .accessibilityIdentifier("user-profile.chat")
                }
            }
        }
    }

    @ViewBuilder
    private var profileStatus: some View {
        if case .failed(let operation, _) = profileStore.phase {
            if operation == .load {
                HStack(spacing: 10) {
                    Text("Couldn’t load this profile.")
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                    Button("Try Again") { profileStore.load(actorID: actorId) }
                        .frame(minHeight: 44)
                }
                .font(.footnote)
                .accessibilityIdentifier("user-profile.load-error")
            } else if operation == .follow || operation == .block {
                Text(operation == .block ? "Couldn’t block this user. Try again." : "Couldn’t update follow. Try again.")
                    .font(.footnote)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                    .accessibilityIdentifier("user-profile.social-error")
            }
        }
    }

    // MARK: Helper Functions
    private func formatDate(_ dateString: String) -> String {
        CardTimestamp.dateOnly(from: dateString)
    }

    // MARK: 发起会话
    private func createConversation() {
        guard !isCreatingConversation else { return }

        isCreatingConversation = true
        let request = CreateConversationRequest(participantId: actorId)

        NetworkManager.shared.createConversation(request: request)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isCreatingConversation = false
                    if case .failure(let error) = completion {
                        print("发起会话失败: \(error.localizedDescription)")

                        if case .unauthorized = error {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("UnauthorizedError"),
                                object: nil
                            )
                        }
                    }
                },
                receiveValue: { response in
                    if response.success {
                        print("发起会话成功: conversationId=\(response.conversation.id)")
                        DispatchQueue.main.async {
                            self.conversationId = response.conversation.id
                            print("设置 conversationId: \(self.conversationId ?? "")")

                            // 延迟一点时间确保状态更新
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.navigateToChat = true
                                print("navigateToChat: \(self.navigateToChat)")
                            }
                        }
                    } else {
                        print("发起会话失败: 服务器返回失败")
                    }
                }
            )
            .store(in: &cancellables)
    }

}

struct ProfilePortrait: View {
    let rawURL: String?
    var size: CGFloat = 72

    var body: some View {
        Group {
            if let rawURL, !rawURL.isEmpty {
                AsyncImage(url: URL(string: APIConfiguration.resourceURLString(rawURL))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image("avatar").resizable().scaledToFill()
                }
            } else {
                Image("avatar").resizable().scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct ProfileCountButton: View {
    let count: Int?
    let label: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(count.map(String.init) ?? "—")
                    .font(.headline).monospacedDigit()
                Text(label).font(.subheadline)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(count.map(String.init) ?? "Loading")
    }
}

// MARK: - User Post Card
struct UserPostCard: View {
    let card: UserCard
    let onShowMenu: (UserCard) -> Void
    let onCardTap: ((String) -> Void)?
    let onChatTap: (() -> Void)?
    let username: String
    let avatarUrl: String?
    let disableFavorite: Bool
    let ownsMenuActions: Bool
    let onDelete: (@MainActor @Sendable () -> Void)?
    let onToggleVisibility: (@MainActor @Sendable (UserCard) -> Void)?
    let onTogglePin: (@MainActor @Sendable (UserCard) -> Void)?

    init(card: UserCard, onShowMenu: @escaping (UserCard) -> Void, onCardTap: ((String) -> Void)? = nil, onChatTap: (() -> Void)? = nil, username: String, avatarUrl: String? = nil, disableFavorite: Bool = false, ownsMenuActions: Bool = false, onDelete: (@MainActor @Sendable () -> Void)? = nil, onToggleVisibility: (@MainActor @Sendable (UserCard) -> Void)? = nil, onTogglePin: (@MainActor @Sendable (UserCard) -> Void)? = nil) {
        self.card = card
        self.onShowMenu = onShowMenu
        self.onCardTap = onCardTap
        self.onChatTap = onChatTap
        self.username = username
        self.avatarUrl = avatarUrl
        self.disableFavorite = disableFavorite
        self.ownsMenuActions = ownsMenuActions
        self.onDelete = onDelete
        self.onToggleVisibility = onToggleVisibility
        self.onTogglePin = onTogglePin
        _likeStore = StateObject(
            wrappedValue: CardLikeStore(
                state: CardLikeState(
                    cardID: card.id,
                    isLiked: card.isLiked,
                    likeCount: card.likeCount
                ),
                service: NetworkCoreCardLikeService(),
                onCommit: { CardEngagementCenter.shared.publish($0) }
            )
        )
    }

    // 状态管理
    @StateObject private var likeStore: CardLikeStore
    @State private var isFavorited = false
    @State private var favoriteCount = 0
    @State private var commentCount = 0
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProfilePortrait(rawURL: avatarUrl, size: 32)
                Text(username).font(.subheadline.weight(.semibold))
                Spacer()
                Text(formatDate(card.createdAt))
                    .font(.caption).foregroundStyle(ChoraiTheme.secondaryInk)
            }
            Button { onCardTap?(card.id) } label: {
                HTMLTextRenderer(cardID: card.id, htmlContent: card.content, maxLines: 7)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(ChoraiTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.card.open.\(card.id)")

            if !card.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(card.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundStyle(ChoraiTheme.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                if !disableFavorite && card.isOwner != true {
                    Button(action: toggleFavorite) {
                        Label("\(favoriteCount)", systemImage: isFavorited ? "bookmark.fill" : "bookmark")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(isFavorited ? "Remove from collection" : "Collect")
                }
                Button(action: likeStore.toggle) {
                    Label("\(likeStore.state.likeCount)", systemImage: likeStore.state.isLiked ? "heart.fill" : "heart")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(likeStore.isMutating)
                .accessibilityLabel(likeStore.state.isLiked ? "Unlike" : "Like")
                .accessibilityValue(likeStore.state.isLiked ? "true" : "false")
                .accessibilityIdentifier("profile.like.\(card.id)")
                CommentButton(cardId: card.id, commentCount: commentCount)
                    .frame(minWidth: 44, minHeight: 44)
                if let onChatTap {
                    Button(action: onChatTap) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Chat about this note")
                    .accessibilityIdentifier("profile.chat.\(card.id)")
                }
                Spacer(minLength: 0)
                NativeCardActionsMenu(
                    cardData: card, layout: ownsMenuActions ? .grid3x3 : .grid2x2,
                    isOwnCard: ownsMenuActions, onPrepare: { onShowMenu(card) },
                    onDelete: onDelete, onToggleVisibility: onToggleVisibility, onTogglePin: onTogglePin
                ) {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More note actions")
                .accessibilityIdentifier("profile.card.menu.\(card.id)")
            }
            .font(.subheadline)
            .foregroundStyle(ChoraiTheme.secondaryInk)
            .buttonStyle(.plain)

            if case .failed = likeStore.phase {
                Text("Like failed. Try again.")
                    .font(.footnote)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                    .accessibilityIdentifier("profile.like.error.\(card.id)")
            }
        }
        .onAppear {
            // 初始化状态
            likeStore.hydrate(
                CardLikeState(
                    cardID: card.id,
                    isLiked: card.isLiked,
                    likeCount: card.likeCount
                )
            )
            isFavorited = card.isFavorited ?? false
            favoriteCount = card.favoriteCount ?? 0
            commentCount = card.commentCount ?? 0
        }
        .onReceive(CardEngagementCenter.shared.likes) { state in
            likeStore.applyCommitted(state)
        }
    }
    // MARK: 收藏功能
    private func toggleFavorite() {
        guard AuthManager.shared.currentUser != nil else {
            print("用户未登录")
            return
        }
        guard !disableFavorite, card.isOwner != true else { return }

        let networkManager = NetworkManager.shared

        if isFavorited {
            // 取消收藏
            networkManager.unfavoriteCard(cardId: card.id)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("取消收藏失败: \(error)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFavorited = false
                            self.favoriteCount = max(0, self.favoriteCount - 1)
                            print("取消收藏成功")
                        }
                    }
                )
                .store(in: &cancellables)
        } else {
            // 收藏
            networkManager.favoriteCard(cardId: card.id)
                .receive(on: DispatchQueue.main)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("收藏失败: \(error)")
                        }
                    },
                    receiveValue: { response in
                        if response.success {
                            self.isFavorited = true
                            self.favoriteCount += 1
                        }
                    }
                )
                .store(in: &cancellables)
        }
    }

    // MARK: - Helper Functions
    private func formatDate(_ dateString: String) -> String {
        CardTimestamp.dateOnly(from: dateString)
    }


}

#Preview {
    UserProfileView(actorId: "act_preview")
}
