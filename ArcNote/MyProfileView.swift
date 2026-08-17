import SwiftUI
import Combine
import CoreFlow

struct MyCompanionChatDestination: Equatable {
    let humanActorID: String
    let conversationID: String
    let companionName: String
    let companionAvatarURL: String?
}

protocol MyCompanionConversationCreating {
    func createConversation(
        participantActorID: String
    ) async throws -> CreateConversationData
}

protocol MyCompanionChatRouting {
    func openConversation(
        humanActorID: String
    ) async throws -> MyCompanionChatDestination
}

struct NetworkMyCompanionConversationCreator:
    MyCompanionConversationCreating
{
    func createConversation(
        participantActorID: String
    ) async throws -> CreateConversationData {
        var iterator = NetworkManager.shared.createConversation(
            request: CreateConversationRequest(
                participantId: participantActorID
            )
        )
        .values
        .makeAsyncIterator()

        guard let response = try await iterator.next() else {
            throw NetworkError.noData
        }
        guard response.success else {
            throw ChoraProfileError.requestFailed
        }
        return response.conversation
    }
}

struct NetworkMyCompanionChatRouter: MyCompanionChatRouting {
    private let profileService: any CoreChoraProfileServing
    private let conversationCreator: any MyCompanionConversationCreating

    init(
        profileService: any CoreChoraProfileServing =
            NetworkChoraProfileService(),
        conversationCreator: any MyCompanionConversationCreating =
            NetworkMyCompanionConversationCreator()
    ) {
        self.profileService = profileService
        self.conversationCreator = conversationCreator
    }

    func openConversation(
        humanActorID rawHumanActorID: String
    ) async throws -> MyCompanionChatDestination {
        let humanActorID = rawHumanActorID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !humanActorID.isEmpty else {
            throw ChoraProfileError.invalidHumanActor
        }

        let identity = try await profileService.identity(
            humanActorID: humanActorID
        )
        guard identity.humanActorID == humanActorID else {
            throw ChoraProfileError.humanActorMismatch
        }
        guard !identity.agentActorID.isEmpty,
              identity.agentActorID != humanActorID else {
            throw ChoraProfileError.humanActorUsedAsAgent
        }

        let conversation = try await conversationCreator.createConversation(
            participantActorID: identity.agentActorID
        )
        guard conversation.participant.id == identity.agentActorID else {
            throw ChoraProfileError.agentActorChanged
        }

        return MyCompanionChatDestination(
            humanActorID: humanActorID,
            conversationID: conversation.id,
            companionName: identity.displayName,
            companionAvatarURL: identity.avatarURL
        )
    }
}

struct MyProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayoutMetrics) private var adaptiveLayout
    @State private var showPopupMenu = false
    @StateObject private var cardsManager: HomeCardsManager
    @ObservedObject private var userProfileManager: UserProfileManager
    private let loadsDataOnAppear: Bool
    private let companionChatRouter: any MyCompanionChatRouting
    private let chatDetailFetcher: any ChatDetailFetching

    // 聊天相关状态
    @State private var navigateToChat = false
    @State private var chatDestination: MyCompanionChatDestination?
    @State private var isCreatingConversation = false

    // 菜单相关状态
    @State private var popupMenuLayout: PopupMenuLayout = .grid2x2
    @State private var currentMenuCardData: UserCard? = nil

    // 自己卡片的菜单动作状态
    @State private var cardPendingDeletion: UserCard? = nil
    @State private var showDeleteConfirmation = false
    @State private var isDeletingCard = false
    @State private var deleteErrorMessage: String? = nil

    // 导航状态
    @State private var navigateToDetail = false
    @State private var selectedCardId: String? = nil
    @State private var showFollowList = false
    @State private var followListKind: FollowListKind = .followers

    init(
        userProfileManager: UserProfileManager = .shared,
        cardsManager: HomeCardsManager = HomeCardsManager(),
        loadsDataOnAppear: Bool = true,
        companionChatRouter: any MyCompanionChatRouting =
            NetworkMyCompanionChatRouter(),
        chatDetailFetcher: any ChatDetailFetching = NetworkManager.shared
    ) {
        _cardsManager = StateObject(wrappedValue: cardsManager)
        _userProfileManager = ObservedObject(
            wrappedValue: userProfileManager
        )
        self.loadsDataOnAppear = loadsDataOnAppear
        self.companionChatRouter = companionChatRouter
        self.chatDetailFetcher = chatDetailFetcher
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text(userProfileManager.userProfile?.username ?? "My Profile")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // 占位符，保持标题居中
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, adaptiveLayout.horizontalGutter)
            .padding(.bottom, 20)
            
            // 主要内容
            ScrollView {
                VStack(spacing: 0) {
                    // 顶部间距，为头像留出空间
                    Spacer().frame(height: 30)
                    
                    // 用户资料卡片全屏宽度
                    ZStack(alignment: .topLeading) {
                        // 主卡片内容
                        VStack(spacing: 0) {
                            // 头像占位空间
                            HStack {
                                Spacer().frame(width: 60, height: 15) // 头像占位空间
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 15)
                            
                            // 用户信息区域
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    if userProfileManager.isLoading {
                                        Text("Loading...")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.7))
                                    } else {
                                        Text(userProfileManager.userProfile?.username ?? "User")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    Spacer()

                                    Button(action: createConversation) {
                                        Image("send_chat")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 24, height: 24)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Chat")
                                    .accessibilityIdentifier("my-profile.chat")
                                }
                                
                                // 第二行：统计数据
                                HStack(spacing: 20) {
                                    Button {
                                        followListKind = .following
                                        showFollowList = true
                                    } label: {
                                    HStack(spacing: 4) {
                                        if userProfileManager.isLoading {
                                            Text("--")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white.opacity(0.7))
                                        } else {
                                            Text("\(userProfileManager.userProfile?.followingCount ?? 0)")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        Text("following")
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("my-profile.following-count")
                                    
                                    Spacer()
                                    Button {
                                        followListKind = .followers
                                        showFollowList = true
                                    } label: {
                                    HStack(spacing: 4) {
                                        if userProfileManager.isLoading {
                                            Text("--")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white.opacity(0.7))
                                        } else {
                                            Text("\(userProfileManager.userProfile?.followersCount ?? 0)")
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        Text("followers")
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("my-profile.followers-count")
                                    
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 15)
                            
                            // 笔记卡片列表 在同一个卡片内
                            VStack(spacing: 20) {
                                if cardsManager.isLoading && cardsManager.cards.isEmpty {
                                    // 加载状态
                                } else if cardsManager.cards.isEmpty {
                                    // 空状态
                                    VStack(spacing: 12) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 32))
                                            .foregroundColor(.white.opacity(0.5))
                                        Text("No notes")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .frame(height: 100)
                                } else {
                                    // 真实数据
                                    ForEach(cardsManager.cards, id: \.id) { card in
                                        UserPostCard(
                                            card: card,
                                            onShowMenu: { cardData in
                                                // 设置当前卡片数据
                                                currentMenuCardData = cardData
                                                popupMenuLayout = .grid3x3
                                                showPopupMenu = true
                                            },
                                            onCardTap: { cardId in
                                                print("cardId=\(cardId)")
                                                selectedCardId = cardId
                                                DispatchQueue.main.async {
                                                    navigateToDetail = true
                                                    print("navigateToDetail: \(navigateToDetail)")
                                                }
                                            },
                                            username: userProfileManager.userProfile?.username ?? "User",
                                            avatarUrl: userProfileManager.userProfile?.avatar,
                                            disableFavorite: true
                                        )
                                        .onAppear {
                                            print("数据: id=\(card.id), commentCount=\(card.commentCount ?? -1), likeCount=\(card.likeCount)")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                        .background(
                            RoundedRectangle(
                                cornerRadius: AdaptiveLayoutMetrics.surfaceCornerRadius,
                                style: .continuous
                            )
                                .background(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: AdaptiveLayoutMetrics.surfaceCornerRadius,
                                        style: .continuous
                                    )
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: AdaptiveLayoutMetrics.surfaceCornerRadius,
                                        style: .continuous
                                    )
                                )
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("profile.primary-surface")
                        
                        // 头像 骑在边框线上
                        HStack {
                            Group {
                                if let avatarUrl = userProfileManager.userProfile?.avatar, !avatarUrl.isEmpty {
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
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            )
                            .offset(y: -36) // 向上偏移36，使头像中心在卡片上边框
                            
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .padding(.trailing, 20)
                    }
                    .padding(.top, 30)
                }
                .adaptiveContentGutter()
            }
        }
        .background(
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea(.all)
        )
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .overlay(
            CommentPopupView()
        )
        .onAppear {
            guard loadsDataOnAppear else { return }
            // 加载当前用户资料
            userProfileManager.fetchCurrentUserProfile()
            
            cardsManager.loadUserCards(refresh: true)
        }
        .navigationDestination(isPresented: $navigateToDetail) {
            if let cardId = selectedCardId {
                DetailView(cardId: cardId)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(isPresented: $navigateToChat) {
            if let chatDestination {
                ChatDetailView(
                    conversationId: chatDestination.conversationID,
                    contactName: chatDestination.companionName,
                    contactStatus: "Online",
                    contactAvatar: chatDestination.companionAvatarURL,
                    humanActorID: chatDestination.humanActorID,
                    fetcher: chatDetailFetcher
                )
            } else {
                EmptyView()
            }
        }
        .popupMenu(
            isPresented: $showPopupMenu,
            layout: popupMenuLayout,
            cardData: currentMenuCardData,
            isOwnCard: true,
            onDelete: requestCardDeletion,
            onToggleVisibility: toggleCardVisibility,
            onTogglePin: toggleCardPin
        )
        .confirmationDialog(
            "Remove this note?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {
                cardPendingDeletion = nil
            }
            Button("Remove", role: .destructive) {
                confirmCardDeletion()
            }
            .disabled(isDeletingCard)
            .accessibilityIdentifier("my-profile.delete.confirm")
        } message: {
            Text("This moves the note to Trash.")
        }
        .alert(
            "Couldn’t complete this action",
            isPresented: deleteErrorPresented
        ) {
            Button("OK", role: .cancel) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? "Please try again.")
        }
        .sheet(isPresented: $showFollowList) {
            FollowListView(
                actorID: userProfileManager.userProfile?.id
                    ?? AuthManager.shared.currentUser?.id
                    ?? "",
                actorName: userProfileManager.userProfile?.username ?? "User",
                kind: followListKind,
                viewerActorID: AuthManager.shared.currentUser?.id ?? ""
            )
        }
        .linkPopup()
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deleteErrorMessage = nil
                }
            }
        )
    }

    private func requestCardDeletion() {
        guard let card = currentMenuCardData else { return }
        cardPendingDeletion = card
        showDeleteConfirmation = true
    }

    private func confirmCardDeletion() {
        guard let card = cardPendingDeletion, !isDeletingCard else { return }

        isDeletingCard = true
        cardsManager.deleteCard(cardId: card.id) { result in
            isDeletingCard = false
            switch result {
            case .success:
                cardPendingDeletion = nil
            case .failure:
                deleteErrorMessage = "Please try again."
            }
        }
    }

    private func toggleCardVisibility(_ card: UserCard) {
        cardsManager.toggleCardVisibility(
            cardId: card.id,
            fallbackCard: card
        ) { result in
            if case .failure = result {
                deleteErrorMessage = "Couldn’t update this note. Please try again."
            }
        }
    }

    private func toggleCardPin(_ card: UserCard) {
        cardsManager.toggleCardPin(
            cardId: card.id,
            fallbackCard: card
        ) { result in
            if case .failure = result {
                deleteErrorMessage = "Couldn’t update this note. Please try again."
            }
        }
    }

    private func createConversation() {
        guard !isCreatingConversation else { return }
        guard let humanActorID = currentHumanActorID else {
            return
        }

        isCreatingConversation = true

        Task { @MainActor in
            defer { isCreatingConversation = false }

            do {
                let destination = try await companionChatRouter.openConversation(
                    humanActorID: humanActorID
                )
                guard !Task.isCancelled else { return }
                chatDestination = destination
                navigateToChat = true
            } catch {
                guard !Task.isCancelled else { return }
                if let error = error as? NetworkError,
                   case .unauthorized = error {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("UnauthorizedError"),
                        object: nil
                    )
                }
            }
        }
    }

    private var currentHumanActorID: String? {
        let value = userProfileManager.userProfile?.id
            ?? AuthManager.shared.currentUser?.id
        let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized?.isEmpty == false ? normalized : nil
    }
}

#Preview {
    MyProfileView()
}
