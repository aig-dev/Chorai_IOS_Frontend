import SwiftUI
import UIKit
import Combine



// MARK: 选择卡片弹窗管理器
class SelectCardPopupManager: ObservableObject {
    @Published var isShowing = false
    @Published var noteCards: [NoteCard] = []
    @Published var selectedNotes: [NoteCard] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    static let shared = SelectCardPopupManager()
    private var cancellables = Set<AnyCancellable>()

    func show() {
        isShowing = true
        fetchCards()
    }

    func hide() {
        isShowing = false
    }

    func selectNote(_ note: NoteCard) {
        if !selectedNotes.contains(where: { $0.id == note.id }) {
            selectedNotes.append(note)
        }
    }

    func removeNote(_ note: NoteCard) {
        selectedNotes.removeAll { $0.id == note.id }
    }

    func fetchCards(searchText: String = "") {
        guard AuthManager.shared.currentUser != nil else {
            return
        }

        isLoading = true
        NetworkManager.shared.getUserAllCards(
            searchType: "own+favorited",
            search: searchText,
            limit: 100
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] completion in
            self?.isLoading = false
            if case .failure(let error) = completion {
                self?.errorMessage = error.localizedDescription
                print("加载卡片失败: \(error)")
            }
        } receiveValue: { [weak self] response in
            let ownCards = self?.convertCards(response.data.ownCards) ?? []
            let favoritedCards = self?.convertCards(response.data.favoritedCards) ?? []
            self?.noteCards = ownCards + favoritedCards
        }
        .store(in: &cancellables)
    }

    private func convertCards(_ cards: [UserAllCard]) -> [NoteCard] {
        return cards
            .filter { $0.isPublic }
            .map {
                NoteCard(
                    id: $0.id,
                    title: ($0.title?.isEmpty ?? true) ? "Untitled" : ($0.title ?? ""),
                    description: $0.content,
                    isPublic: $0.isPublic,
                    username: $0.author?.username ?? "Unknown",
                    avatarUrl: $0.author?.avatar
                )
            }
    }
}

// MARK: 消息数据模型
struct ChatMessage: Identifiable {
    let id: String
    let content: String
    let isFromMe: Bool
    let timestamp: String
    let avatarURL: String?
    let attachedNotes: [NoteCard]?
}

// MARK: - 聊天详情视图
struct ChatDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var chatHistoryDependency:
        ChatHistoryVisibilityDependency
    @Environment(\.dismiss) private var dismiss
    @Environment(\.adaptiveLayoutMetrics) private var adaptiveLayout
    @State private var messageText = ""
    @State private var contactName: String
    @State private var contactStatus: String
    @State private var contactAvatar: String?
    @State private var searchText = ""
    @FocusState private var isTextFieldFocused: Bool
    @ObservedObject private var selectCardManager = SelectCardPopupManager.shared
    @StateObject private var chatDetailManager: ChatDetailManager

    let conversationId: String


    init(
        conversationId: String,
        contactName: String = "Thompson",
        contactStatus: String = "5 minutes ago online",
        contactAvatar: String? = nil,
        humanActorID: String = AuthManager.shared.currentUser?.id ?? "",
        fetcher: any ChatDetailFetching = NetworkManager.shared
    ) {
        self.conversationId = conversationId
        self._contactName = State(initialValue: contactName)
        self._contactStatus = State(initialValue: contactStatus)
        self._contactAvatar = State(initialValue: contactAvatar)
        _chatDetailManager = StateObject(
            wrappedValue: ChatDetailManager(
                humanActorID: humanActorID,
                participantAvatarURL: contactAvatar,
                fetcher: fetcher
            )
        )
    }

    private var chatPartnerName: String {
        let name = chatDetailManager.conversation?.partner.username
            ?? contactName
        let trimmedName = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmedName.isEmpty ? "Chora" : trimmedName
    }

    private var chatPartnerAvatar: String? {
        chatDetailManager.conversation?.partner.avatarUrl ?? contactAvatar
    }

    private var isAgentTyping: Bool {
        if case .thinking = chatDetailManager.agentDeliveryState {
            return true
        }
        return false
    }



    var body: some View {
        VStack(spacing: 0) {
            // 聊天内容
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if chatDetailManager.isLoading {
                            VStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: ChoraiTheme.accent))
                                    .scaleEffect(1.2)
                                Text("Loading conversation...")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(ChoraiTheme.secondaryInk)
                                    .padding(.top, 10)
                                Spacer()
                            }
                            .frame(height: 200)
                        } else {
                            let messages = chatDetailManager.convertToChatMessages()
                            if messages.isEmpty {
                                VStack {
                                    Spacer()
                                    Text("No messages yet")
                                        .font(.body.weight(.medium))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                    Text("Start a conversation")
                                        .font(.subheadline.weight(.regular))
                                        .foregroundColor(ChoraiTheme.secondaryInk)
                                        .padding(.top, 5)
                                    Spacer()
                                }
                                .frame(height: 200)
                                .onAppear {
                                    print("转换后的消息数量: \(messages.count)")
                                }
                            } else {
                                ForEach(messages) { message in
                                    ChatMessageView(message: message)
                                }
                                Color.clear
                                    .frame(height: 1)
                                    .id("chatBottom")
                                .onAppear {
                                    print("转换后的消息数量: \(messages.count)")
                                }
                            }
                        }
                    }
                    .adaptiveContentGutter()
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    scrollToBottom(proxy, animated: false)
                }
                .onChange(of: chatDetailManager.messages.count) { _ in
                    scrollToBottom(proxy, animated: true)
                }
                .onChange(of: selectCardManager.selectedNotes.count) { _ in
                    scrollToBottom(proxy, animated: false)
                }
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
            // 选中的notes展示区域
            if !selectCardManager.selectedNotes.isEmpty {
                HStack {
                    VStack(spacing: 0) {
                        ForEach(Array(selectCardManager.selectedNotes.enumerated()), id: \.element.id) { index, note in
                            VStack(spacing: 0) {
                                HStack(spacing: 10) {
                                    NoteAuthorAvatarView(note: note, size: 22)

                                    HTMLTextRenderer(
                                        htmlContent: note.description,
                                        maxLines: dynamicTypeSize.isAccessibilitySize ? 3 : 1,
                                        font: .caption,
                                        foregroundColor: ChoraiTheme.secondaryInk
                                    )
                                    .accessibilityLabel(note.description)
                                    .accessibilityIdentifier(
                                        "chat.attachment.preview.\(note.id)"
                                    )

                                    Spacer()

                                    Button(action: {
                                        selectCardManager.removeNote(note)
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(ChoraiTheme.secondaryInk)
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove attached note")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)

                                // 间隔线（除了最后一个）
                                if index < selectCardManager.selectedNotes.count - 1 {
                                    Rectangle()
                                        .fill(ChoraiTheme.surface)
                                        .frame(height: 1)
                                        .padding(.leading, 64)
                                        .padding(.trailing, 16)
                                }
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ChoraiTheme.separator, lineWidth: 1)
                    )
                    .frame(
                        maxWidth: adaptiveLayout.size.width * 0.8,
                        alignment: .leading
                    )

                    Spacer()
                }
                .adaptiveContentGutter()
                .padding(.bottom, 8)
            }

            if case .retryAvailable(let sourceMessageID) = chatDetailManager.agentDeliveryState {
                HStack(spacing: 10) {
                    ChatAvatarView(
                        rawValue: chatPartnerAvatar,
                        size: 28
                    )

                    Button {
                        chatDetailManager.retryAgentReply(
                            conversationId: conversationId,
                            sourceMessageId: sourceMessageID
                        )
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                            Text("Continue \(chatPartnerName)'s reply")
                                .font(.footnote.weight(.medium))
                        }
                        .foregroundColor(ChoraiTheme.ink)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 44)
                        .background(
                            Capsule()
                                .fill(ChoraiTheme.surface)
                                .overlay(
                                    Capsule()
                                        .stroke(ChoraiTheme.separator, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Continue \(chatPartnerName)'s reply")
                    .accessibilityIdentifier("chat.agent.retry")

                    Spacer()
                }
                .adaptiveContentGutter()
                .padding(.bottom, 8)
            }

            // 底部输入栏
            HStack(alignment: .bottom, spacing: 12) {
                // 附件按钮
                Button(action: {
                    selectCardManager.show()
                }) {
                    ChatComposerIconLabel(symbol: "doc.text")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach a note")
                .accessibilityIdentifier("chat.attachment.add")

                // 输入框
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Type a message...", text: $messageText, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.body)
                        .foregroundColor(ChoraiTheme.ink)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("chat.message.input")
                        .focused($isTextFieldFocused)

                    Button(action: {
                        if !messageText.isEmpty {
                            let attachedNotes = selectCardManager.selectedNotes
                            // 发送消息到API
                            chatDetailManager.sendMessage(conversationId: conversationId, content: messageText, attachedNotes: attachedNotes)
                            messageText = ""
                            isTextFieldFocused = false
                            // 清空选中的卡片
                            selectCardManager.selectedNotes.removeAll()
                        }
                    }) {
                        ChatComposerIconLabel(symbol: "arrow.up", prominent: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send message")
                    .accessibilityIdentifier("chat.message.send")
                    .disabled(messageText.isEmpty)
                }
                .padding(.leading, 16)
                .padding(.trailing, 2)
                .padding(.vertical, 2)
                .choraiGlassSurface(cornerRadius: 26)
            }
            .adaptiveContentGutter()
            .padding(.bottom, 10)
            }
            .padding(.top, 8)
            .background(ChoraiTheme.background)
        }
        .foregroundStyle(ChoraiTheme.ink)
        .tint(ChoraiTheme.accent)
        .navigationTitle(chatPartnerName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: dismiss.callAsFunction) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    ChatAvatarView(rawValue: chatPartnerAvatar, size: 32)
                    ChatHeaderIdentity(name: chatPartnerName, status: contactStatus, isTyping: isAgentTyping)
                }
            }
        }
        .background(
            ChoraiBackground()
                .ignoresSafeArea()
        )
        .sheet(isPresented: Binding(
            get: { selectCardManager.isShowing },
            set: { if !$0 { selectCardManager.hide() } }
        )) {
            SelectCardPopupView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if let conversation = chatDetailManager.conversation {
                VStack(spacing: 0) {
                    Text("Chat detail loaded")
                        .font(.system(size: 1))
                        .foregroundColor(.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("chat.detail.loaded")

                    Text(conversation.id)
                        .font(.system(size: 1))
                        .foregroundColor(.white.opacity(0.01))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("chat.detail.conversation-id")
                }
            }
        }
        #endif
        .onAppear {
            chatDetailManager.bindVisibility(chatHistoryDependency)
            chatDetailManager.loadConversationDetail(conversationId: conversationId)
            // loadMessages会在对话详情加载完成后自动调用
        }
        .onDisappear {
            chatDetailManager.stopConversationEvents()
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !chatDetailManager.messages.isEmpty else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    proxy.scrollTo("chatBottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("chatBottom", anchor: .bottom)
            }
        }
    }
}

/// A fixed control surface keeps the native glass effect from adding a second
/// layer of button padding around the minimum touch target.
private struct ChatComposerIconLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let symbol: String
    var prominent = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: prominent ? .semibold : .regular))
            .foregroundStyle(
                isEnabled
                    ? (prominent ? ChoraiTheme.onAccent : ChoraiTheme.ink)
                    : ChoraiTheme.secondaryInk
            )
            .frame(width: 44, height: 44)
            .background { surface }
            .contentShape(Circle())
    }

    @ViewBuilder
    private var surface: some View {
        if !isEnabled {
            Circle().fill(ChoraiTheme.raisedSurface)
        } else if reduceTransparency || contrast == .increased {
            Circle()
                .fill(prominent ? ChoraiTheme.accent : ChoraiTheme.surface)
                .overlay(Circle().stroke(ChoraiTheme.separator, lineWidth: 1))
        } else if #available(iOS 26.0, *) {
            Circle()
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(prominent ? ChoraiTheme.accent : .clear).interactive(),
                    in: Circle()
                )
        } else {
            Circle()
                .fill(prominent ? ChoraiTheme.accent : ChoraiTheme.surface)
                .overlay(Circle().stroke(ChoraiTheme.separator.opacity(0.55), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
    }
}

private struct ChatHeaderIdentity: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ellipsisIsDimmed = false

    let name: String
    let status: String
    let isTyping: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(ChoraiTheme.ink)

                Text(status)
                    .font(.caption.weight(.regular))
                    .foregroundColor(.green)
            }
            .opacity(isTyping ? 0 : 1)
            .offset(y: isTyping ? -4 : 0)

            HStack(spacing: 0) {
                Text("\(name) is typing")
                    .foregroundColor(ChoraiTheme.ink)
                Text("…")
                    .foregroundColor(ChoraiTheme.secondaryInk)
                    .opacity(
                        reduceMotion || !isTyping
                            ? 1
                            : (ellipsisIsDimmed ? 0.38 : 1)
                    )
            }
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .opacity(isTyping ? 1 : 0)
            .offset(y: isTyping ? 0 : 4)
        }
        .frame(height: 40, alignment: .leading)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: isTyping
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isTyping ? "\(name) is typing" : "\(name), \(status)"
        )
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("chat.header.identity")
        .onAppear {
            updateEllipsisAnimation()
        }
        .onChange(of: isTyping) { _ in
            updateEllipsisAnimation()
        }
        .onChange(of: reduceMotion) { _ in
            updateEllipsisAnimation()
        }
    }

    private func updateEllipsisAnimation() {
        ellipsisIsDimmed = false
        guard isTyping, !reduceMotion else { return }
        withAnimation(
            .easeInOut(duration: 0.85).repeatForever(autoreverses: true)
        ) {
            ellipsisIsDimmed = true
        }
    }
}

// MARK: - 选择卡片弹窗视图
struct SelectCardPopupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var manager = SelectCardPopupManager.shared
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var searchWorkItem: DispatchWorkItem?

    // 过滤后的卡片
    private var filteredCards: [NoteCard] {
        if searchText.isEmpty {
            return manager.noteCards
        } else {
            return manager.noteCards.filter { card in
                card.title.localizedCaseInsensitiveContains(searchText) ||
                card.description.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search cards", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .choraiGlassSurface(cornerRadius: 24)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                ScrollView {
                    if manager.isLoading {
                        ProgressView("Loading cards…")
                            .frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else if filteredCards.isEmpty {
                        Label("No cards found", systemImage: "doc.text")
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                            .frame(maxWidth: .infinity).padding(.vertical, 60)
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredCards) { card in
                                Button {
                                    manager.selectNote(card)
                                    isSearchFocused = false
                                    manager.hide()
                                } label: {
                                    NoteCardView(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .choraiPageBackground()
            .navigationTitle("Select Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isSearchFocused = false
                        manager.hide()
                    }
                    .frame(minHeight: 44)
                }
            }
            .onAppear {
                DispatchQueue.main.async { isSearchFocused = true }
            }
            .onChange(of: searchText) { newValue in
                searchWorkItem?.cancel()
                let workItem = DispatchWorkItem { [weak manager] in
                    manager?.fetchCards(searchText: newValue)
                }
                searchWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
            }
            .onDisappear {
                searchWorkItem?.cancel()
            }
        }
    }

}

// MARK: - 卡片视图
struct NoteCardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let card: NoteCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NoteAuthorAvatarView(note: card, size: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(card.username)
                    .font(.body.weight(.semibold))
                    .foregroundColor(ChoraiTheme.ink)
                    .lineLimit(1)

                HTMLTextRenderer(
                    htmlContent: card.description,
                    maxLines: dynamicTypeSize.isAccessibilitySize ? 3 : 2,
                    font: .caption,
                    foregroundColor: ChoraiTheme.secondaryInk
                )
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(ChoraiTheme.separator, lineWidth: 1)
                )
        )
    }
}

// MARK: - 聊天消息视图
struct ChatMessageView: View {
    @Environment(\.adaptiveLayoutMetrics) private var adaptiveLayout
    let message: ChatMessage

    private var messageBubbleWidth: CGFloat {
        max(0, adaptiveLayout.contentWidth - 76)
    }

    var body: some View {
        VStack(spacing: 8) {
            // 时间戳
            Text(message.timestamp)
                .font(.caption.weight(.regular))
                .foregroundColor(ChoraiTheme.secondaryInk)
                .frame(maxWidth: .infinity)
            // 消息气泡
            HStack {
                if message.isFromMe {
                    HStack(alignment: .bottom, spacing: 10) {
                        Spacer()

                        // 消息内容
                        VStack(alignment: .trailing, spacing: 8) {
                            Text(message.content)
                                .font(.body.weight(.regular))
                                .foregroundColor(ChoraiTheme.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(ChoraiTheme.selection, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                            // 附件笔记
                            if let attachedNotes = message.attachedNotes {
                                AttachedNotesBubbleView(
                                    notes: attachedNotes,
                                    maxWidth: max(0, messageBubbleWidth - 32)
                                )
                            }
                        }
                        .frame(maxWidth: messageBubbleWidth, alignment: .trailing)
//                        50 * 2 + 20 * 2 + 16 * 2
                        // 头像
                        ChatAvatarView(
                            rawValue: message.avatarURL,
                            size: 32,
                            accessibilityIdentifier: "chat.message.avatar.\(message.id)"
                        )
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 10) {
                        // 头像
                        ChatAvatarView(
                            rawValue: message.avatarURL,
                            size: 32,
                            accessibilityIdentifier: "chat.message.avatar.\(message.id)"
                        )

                        // 消息内容
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message.content)
                                .font(.body.weight(.regular))
                                .foregroundColor(ChoraiTheme.ink)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(ChoraiTheme.raisedSurface)
                                )

                            // 附件笔记
                            if let attachedNotes = message.attachedNotes {
                                AttachedNotesBubbleView(
                                    notes: attachedNotes,
                                    maxWidth: max(0, messageBubbleWidth - 10)
                                )
                            }
                        }
                        .frame(maxWidth: messageBubbleWidth, alignment: .leading)

                        Spacer()
                    }
                }
            }

        }
        .accessibilityValue(message.avatarURL ?? "default")
        .accessibilityIdentifier("chat.message.\(message.id)")
    }
}

// MARK: - 附件卡片列表
struct AttachedNotesView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let notes: [NoteCard]
    let maxWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 10) {
                        NoteAuthorAvatarView(note: note, size: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.username)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(ChoraiTheme.ink)
                                .lineLimit(1)

                            HTMLTextRenderer(
                                htmlContent: note.description,
                                maxLines: dynamicTypeSize.isAccessibilitySize ? 3 : 2,
                                font: .caption2,
                                foregroundColor: ChoraiTheme.secondaryInk
                            )
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    if index < notes.count - 1 {
                        Rectangle()
                            .fill(ChoraiTheme.surface)
                            .frame(height: 1)
                            .padding(.leading, 50)
                            .padding(.trailing, 12)
                    }
                }
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ChoraiTheme.separator, lineWidth: 1)
        )
    }
}

// MARK: - 聊天气泡附件列表
struct AttachedNotesBubbleView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let notes: [NoteCard]
    let maxWidth: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                VStack(spacing: 0) {
                    NavigationLink(destination: DetailView(cardId: note.id)) {
                        HStack(spacing: 10) {
                            NoteAuthorAvatarView(note: note, size: 20)

                            HTMLTextRenderer(
                                htmlContent: note.description,
                                maxLines: dynamicTypeSize.isAccessibilitySize ? 3 : 1,
                                font: .caption,
                                foregroundColor: ChoraiTheme.ink
                            )
                                .accessibilityLabel(note.description)
                                .accessibilityIdentifier(
                                    "chat.attachment.preview.\(note.id)"
                                )

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("chat.attachment.\(note.id)")

                    if index < notes.count - 1 {
                        Rectangle()
                            .fill(ChoraiTheme.surface)
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ChoraiTheme.separator, lineWidth: 1)
        )
    }
}

struct ChatAvatarView: View {
    let rawValue: String?
    let size: CGFloat
    let accessibilityIdentifier: String

    init(
        rawValue: String?,
        size: CGFloat,
        accessibilityIdentifier: String = "chat.avatar"
    ) {
        self.rawValue = rawValue
        self.size = size
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    private var resolvedAvatarValue: String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              rawValue != "avatar",
              !Self.isBackendDefaultAvatar(rawValue)
        else {
            return nil
        }
        return rawValue
    }

    private static func isBackendDefaultAvatar(_ rawValue: String) -> Bool {
        URL(string: rawValue)?.path == "/uploads/avatars/default.png"
            || rawValue == "/uploads/avatars/default.png"
    }

    private var avatarURL: URL? {
        guard let resolvedAvatarValue else {
            return nil
        }
        return URL(string: APIConfiguration.resourceURLString(resolvedAvatarValue))
    }

    var body: some View {
        AsyncImage(url: avatarURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            default:
                ChoraiDefaultAvatar()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            resolvedAvatarValue == nil ? "Chora default avatar" : "Chat avatar"
        )
        .accessibilityValue(resolvedAvatarValue ?? "default")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct NoteAuthorAvatarView: View {
    let note: NoteCard
    let size: CGFloat

    var body: some View {
        ChatAvatarView(
            rawValue: note.avatarUrl,
            size: size,
            accessibilityIdentifier: "chat.attachment.avatar.\(note.id)"
        )
        .accessibilityLabel("\(note.username) avatar")
    }
}

// MARK: - 自定义高光效果适配不对称圆角
fileprivate extension View {
    func customRoundedButtonHighlightEffect(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> some View {
        self
            .overlay(customTopLeftHighlight(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight))
            .overlay(customBottomRightHighlight(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight))
            .overlay(customTopEdgeHighlight(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight))
            .overlay(customBottomEdgeHighlight(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight))
    }

    private func customTopLeftHighlight(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> some View {
        CustomRoundedCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
            .stroke(ChoraiTheme.separator, lineWidth: 1)
            .mask(
                CustomRoundedCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
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

    private func customBottomRightHighlight(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> some View {
        CustomRoundedCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
            .stroke(ChoraiTheme.separator, lineWidth: 1)
            .mask(
                CustomRoundedCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
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

    private func customTopEdgeHighlight(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> some View {
        CustomRoundedCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
            .stroke(ChoraiTheme.separator, lineWidth: 1)
            .offset(y: -1)
            .mask(
                CustomRoundedCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0, y: 0.05)
                        )
                    )
            )
    }

    private func customBottomEdgeHighlight(topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) -> some View {
        CustomRoundedCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
            .stroke(ChoraiTheme.separator, lineWidth: 1)
            .offset(x: -1, y: 1)
            .mask(
                CustomRoundedCorners(topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
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

// MARK: - 自定义圆角形状
struct CustomRoundedCorners: Shape {
    var topLeft: CGFloat = 0
    var topRight: CGFloat = 0
    var bottomLeft: CGFloat = 0
    var bottomRight: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let topLeftRadius = min(min(topLeft, rect.width / 2), rect.height / 2)
        let topRightRadius = min(min(topRight, rect.width / 2), rect.height / 2)
        let bottomLeftRadius = min(min(bottomLeft, rect.width / 2), rect.height / 2)
        let bottomRightRadius = min(min(bottomRight, rect.width / 2), rect.height / 2)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + topLeftRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRightRadius, y: rect.minY))
        if topRightRadius > 0 {
            path.addArc(withCenter: CGPoint(x: rect.maxX - topRightRadius, y: rect.minY + topRightRadius), radius: topRightRadius, startAngle: -CGFloat.pi / 2, endAngle: 0, clockwise: true)
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRightRadius))
        if bottomRightRadius > 0 {
            path.addArc(withCenter: CGPoint(x: rect.maxX - bottomRightRadius, y: rect.maxY - bottomRightRadius), radius: bottomRightRadius, startAngle: 0, endAngle: CGFloat.pi / 2, clockwise: true)
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX + bottomLeftRadius, y: rect.maxY))
        if bottomLeftRadius > 0 {
            path.addArc(withCenter: CGPoint(x: rect.minX + bottomLeftRadius, y: rect.maxY - bottomLeftRadius), radius: bottomLeftRadius, startAngle: CGFloat.pi / 2, endAngle: CGFloat.pi, clockwise: true)
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeftRadius))
        if topLeftRadius > 0 {
            path.addArc(withCenter: CGPoint(x: rect.minX + topLeftRadius, y: rect.minY + topLeftRadius), radius: topLeftRadius, startAngle: CGFloat.pi, endAngle: 3 * CGFloat.pi / 2, clockwise: true)
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.close()
        return Path(path.cgPath)
    }
}

#Preview {
    ChatDetailView(conversationId: "cnv_preview")
}

