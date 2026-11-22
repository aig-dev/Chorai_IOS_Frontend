import SwiftUI
import Combine
import CoreFlow

struct MyCompanionChatDestination: Equatable, Sendable {
    let humanActorID: String
    let conversationID: String
    let companionName: String
    let companionAvatarURL: String?
}

protocol MyCompanionConversationCreating: Sendable {
    func createConversation(
        participantActorID: String
    ) async throws -> CreateConversationData
}

protocol MyCompanionChatRouting: Sendable {
    func openConversation(
        humanActorID: String
    ) async throws -> MyCompanionChatDestination
}

struct NetworkMyCompanionConversationCreator:
    MyCompanionConversationCreating
{
    @MainActor
    func createConversation(
        participantActorID: String
    ) async throws -> CreateConversationData {
        let publisher = NetworkManager.shared.createConversation(
            request: CreateConversationRequest(
                participantId: participantActorID
            )
        )
        guard let response = try await NetworkManager.firstValue(publisher) else {
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

    @MainActor
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                profileHeader
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
                                popupMenuLayout = .grid3x3
                            },
                            onCardTap: { cardId in
                                selectedCardId = cardId
                                DispatchQueue.main.async { navigateToDetail = true }
                            },
                            username: userProfileManager.userProfile?.username ?? "User",
                            avatarUrl: userProfileManager.userProfile?.avatar,
                            disableFavorite: true,
                            ownsMenuActions: true,
                            onDelete: { requestCardDeletion() },
                            onToggleVisibility: toggleCardVisibility,
                            onTogglePin: { toggleCardPin($0) }
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
        .navigationTitle("My Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Back")
            }
        }
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
            onDelete: { requestCardDeletion() },
            onToggleVisibility: toggleCardVisibility,
            onTogglePin: { toggleCardPin($0) }
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
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                ProfilePortrait(rawURL: userProfileManager.userProfile?.avatar)
                Text(userProfileManager.isLoading ? "Loading…" : userProfileManager.userProfile?.username ?? "User")
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundStyle(ChoraiTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: createConversation) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .frame(width: 44, height: 44)
                }
                .choraiGlassButton()
                .accessibilityLabel("Chat")
                .accessibilityIdentifier("my-profile.chat")
            }
            HStack(spacing: 28) {
                ProfileCountButton(
                    count: userProfileManager.isLoading ? nil : userProfileManager.userProfile?.followingCount ?? 0,
                    label: "following",
                    identifier: "my-profile.following-count"
                ) {
                    followListKind = .following
                    showFollowList = true
                }
                ProfileCountButton(
                    count: userProfileManager.isLoading ? nil : userProfileManager.userProfile?.followersCount ?? 0,
                    label: "followers",
                    identifier: "my-profile.followers-count"
                ) {
                    followListKind = .followers
                    showFollowList = true
                }
                Spacer(minLength: 0)
            }
        }
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

    private func toggleCardVisibility(_ card: UserCard, observation: NotePrivacyObservation, desired: Bool) {
        Task {
            do {
                try await cardsManager.toggleCardVisibility(cardId: card.id, observation: observation, desired: desired)
            } catch {
                guard AuthManager.shared.currentNoteScope == observation.scope,
                      AuthManager.shared.sessionGeneration == observation.session else { return }
                deleteErrorMessage = (error as? NotePrivacyError)?.errorDescription ?? "Open the note audience to check the previous change."
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
