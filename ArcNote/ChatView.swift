import SwiftUI
import Combine

struct ChatView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var chatHistoryDependency:
        ChatHistoryVisibilityDependency
    @Binding var showSideMenu: Bool
    @State private var isSearchMode = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedChat: String? = nil
    @StateObject private var chatManager: ChatManager
    private let humanActorID: String
    private let detailFetcher: any ChatDetailFetching
    private let onExplore: (() -> Void)?

    init(
        showSideMenu: Binding<Bool>,
        humanActorID: String = AuthManager.shared.currentUser?.id ?? "",
        conversationFetcher: any ChatConversationFetching =
            NetworkManager.shared,
        detailFetcher: any ChatDetailFetching = NetworkManager.shared,
        onExplore: (() -> Void)? = nil
    ) {
        _showSideMenu = showSideMenu
        self.humanActorID = humanActorID
        self.detailFetcher = detailFetcher
        self.onExplore = onExplore
        _chatManager = StateObject(
            wrappedValue: ChatManager(
                humanActorID: humanActorID,
                fetcher: conversationFetcher
            )
        )
    }

    var body: some View {
        KeyboardStableViewport(isFocused: isSearchFocused) { _ in
            VStack(spacing: 0) {
                if isSearchMode {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                        TextField("Please enter your search...", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .accessibilityIdentifier("chat.search.input")
                            .submitLabel(.search)
                            .onSubmit { isSearchFocused = false }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .choraiGlassSurface(cornerRadius: 24)
                    .adaptiveContentGutter()
                    .padding(.vertical, 12)
                }

                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                        if chatManager.conversations.isEmpty {
                            if chatManager.isLoading {
                                loadingConversations
                                    .frame(minHeight: geometry.size.height)
                            } else if let error = chatManager.error {
                                conversationFailure(error)
                                    .frame(minHeight: geometry.size.height)
                            } else {
                                emptyConversations
                                    .frame(minHeight: geometry.size.height)
                            }
                        } else {
                            conversationList
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        chatManager.refreshConversations()
                    }
                }
            }
        }
        .choraiPageBackground()
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Chat")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                if isSearchMode {
                    Button("Cancel") {
                        isSearchFocused = false
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            isSearchMode = false
                            searchText = ""
                        }
                    }
                    .frame(minHeight: 44)
                } else {
                    Button {
                        showSideMenu = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open menu")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isSearchMode {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            isSearchMode = true
                        }
                        DispatchQueue.main.async { isSearchFocused = true }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search conversations")
                    .accessibilityIdentifier("chat.search")
                }
            }
        }
        .accessibilityIdentifier("screen.chat.content")
        #if DEBUG
        .overlay(alignment: .topLeading) {
            Text([
                humanActorID,
                String(chatHistoryDependency.revision),
                String(chatHistoryDependency.isVisible(
                    timestampString: "2020-01-01T00:00:00Z",
                    actorID: humanActorID
                )),
                String(chatManager.conversations.count)
            ].joined(separator: "|"))
            .font(.system(size: 1))
            .foregroundColor(.clear)
            .frame(width: 1, height: 1)
            .accessibilityIdentifier("chat.visibility.contract")
        }
        #endif
        .onAppear {
            chatManager.bindVisibility(chatHistoryDependency)
            chatManager.loadConversations()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloseAllPopups"))) { _ in
            print("收到关闭所有popup通知")
        }
    }

    private var loadingConversations: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(ChoraiTheme.accent)
            Text("Loading conversations...")
                .font(.subheadline)
                .foregroundStyle(ChoraiTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .accessibilityIdentifier("chat.loading")
    }

    private func conversationFailure(_ error: String) -> some View {
        VStack(spacing: 16) {
            Text("Couldn’t load conversations")
                .font(.headline)
                .foregroundStyle(ChoraiTheme.ink)
            Text(error)
                .font(.subheadline)
                .foregroundStyle(ChoraiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                chatManager.refreshConversations()
            }
            .frame(minWidth: 100, minHeight: 48)
            .choraiGlassButton()
            .accessibilityIdentifier("chat.retry")
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .adaptiveContentGutter()
        .padding(.vertical, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.error")
    }

    private var emptyConversations: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)

            VStack(spacing: 20) {
                Image("chat-chora-pair")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 110)
                    .accessibilityHidden(true)

                Text("Your next conversation starts with a note.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ChoraiTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("chat.empty.headline")

                Text("Find a note you like, then message its author.")
                    .font(.body)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 290)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 336)

            Spacer(minLength: 44)

            VStack(spacing: 22) {
                Text("Your conversations will appear here.")
                    .font(.footnote)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let onExplore {
                    Button(action: onExplore) {
                        Text("Explore notes")
                            .font(.headline)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(ChoraiTheme.onAccent)
                            .background(ChoraiTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat.empty.explore")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .adaptiveContentGutter()
        .padding(.top, 24)
        .padding(.bottom, 32)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.empty")
    }

    private var conversationList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(chatManager.conversations.enumerated()), id: \.element.id) { index, conversation in
                NavigationLink(destination: ChatDetailView(
                    conversationId: conversation.id,
                    contactName: conversation.partner.username ?? conversation.partner.id,
                    contactStatus: "Online",
                    contactAvatar: conversation.partner.avatarUrl,
                    humanActorID: humanActorID,
                    fetcher: detailFetcher
                )) {
                    ChatListCell(
                        avatar: AnyView(
                            ChatAvatarView(
                                rawValue: conversation.partner.avatarUrl,
                                size: 56,
                                accessibilityIdentifier:
                                    "chat.conversation.avatar.\(conversation.id)"
                            )
                        ),
                        title: conversation.partner.username ?? conversation.partner.id,
                        subtitle: conversation.lastMessage?.content ?? "No messages yet",
                        time: formatConversationTime(conversation.lastMessage?.createdAt ?? conversation.createdAt),
                        unreadCount: conversation.unreadCount
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat.conversation.\(conversation.id)")

                // 分割线（除了最后一个）
                if index < chatManager.conversations.count - 1 {
                    Divider()
                        .overlay(ChoraiTheme.separator)
                        .padding(.leading, 72)
                }
            }

        }
        .padding(.top, 8)
        .adaptiveContentGutter()
        .padding(.bottom, 20)
    }

    // MARK: - 时间格式化
    private func formatConversationTime(_ dateString: String) -> String {
        guard let date = ChatTimestamp.parse(dateString) else {
            return "Unknown"
        }

        let now = Date()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            return timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE"
            return dayFormatter.string(from: date)
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd"
            return dateFormatter.string(from: date)
        }
    }

}

struct ChatListCell: View {
    let avatar: AnyView
    let title: String
    let subtitle: String
    let time: String
    let unreadCount: Int

    init(avatar: AnyView, title: String, subtitle: String, time: String, unreadCount: Int = 0) {
        self.avatar = avatar
        self.title = title
        self.subtitle = subtitle
        self.time = time
        self.unreadCount = unreadCount
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            avatar
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(ChoraiTheme.ink)
                    Spacer()
                    HStack(spacing: 8) {
                        Text(time)
                            .font(.subheadline.weight(.regular))
                            .foregroundColor(ChoraiTheme.secondaryInk)

                        // 未读消息数
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(
                                    Circle()
                                        .fill(Color.red)
                                )
                        }
                    }
                }
                Text(subtitle)
                    .font(.subheadline.weight(.regular))
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    ChatView(showSideMenu: .constant(false))
}
