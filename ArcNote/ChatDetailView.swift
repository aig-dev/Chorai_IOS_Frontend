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
                .accessibilityLabel("Back")
                
                HStack(spacing: 10) {
                    ChatAvatarView(
                        rawValue: chatDetailManager.conversation?.partner.avatarUrl
                            ?? contactAvatar,
                        size: 40
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chatDetailManager.conversation?.partner.username ?? contactName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text(contactStatus)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                // 占位，保持标题居中
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.clear)
            }
            .adaptiveContentGutter()
            .padding(.bottom, 20)
            
            // 聊天内容
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if chatDetailManager.isLoading {
                            VStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                                Text("Loading conversation...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
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
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("Start a conversation")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.white.opacity(0.5))
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
                    .padding(.bottom, selectCardManager.selectedNotes.isEmpty ? 100 : 200) // 为底部输入框和选中notes留出空间
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
                                        maxLines: 1
                                    )
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.72))
                                    .lineLimit(1)
                                    .accessibilityLabel(note.description)
                                    .accessibilityIdentifier(
                                        "chat.attachment.preview.\(note.id)"
                                    )
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        selectCardManager.removeNote(note)
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                
                                // 间隔线（除了最后一个）
                                if index < selectCardManager.selectedNotes.count - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 1)
                                        .padding(.leading, 64)
                                        .padding(.trailing, 16)
                                }
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .frame(
                        maxWidth: adaptiveLayout.size.width * 0.8,
                        alignment: .leading
                    )
                    
                    Spacer()
                }
                .padding(.bottom, 16)
            }
            
            // 底部输入栏
            HStack(spacing: 12) {
                // 附件按钮
                Button(action: {
                    selectCardManager.show()
                }) {
                    Image("notes")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                // 输入框
                HStack(spacing: 12) {
                    TextField("Type a message...", text: $messageText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("chat.message.input")
                        .placeholder(when: messageText.isEmpty) {
                            Text("Type a message...")
                                .foregroundColor(Color(red: 0.627, green: 0.627, blue: 0.627)) // A0A0A0
                        }
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
                        Image("send")
                            .resizable()
                            .frame(width: 40, height: 40)
                    }
                    .accessibilityIdentifier("chat.message.send")
                    .disabled(messageText.isEmpty)
                }
                .padding(.leading, 16)
                .padding(.trailing, 2)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .background(.ultraThinMaterial)
                        .roundedButtonHighlightEffect(cornerRadius: 30)
                )
                .cornerRadius(30)
            }
            .adaptiveContentGutter()
            .padding(.bottom, 10)
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .background(
            Image("home_bg")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
        )
        .overlay(
            SelectCardPopupView()
        )
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
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !chatDetailManager.messages.isEmpty else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("chatBottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("chatBottom", anchor: .bottom)
            }
        }
    }
}

// MARK: - 选择卡片弹窗视图
struct SelectCardPopupView: View {
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
        if manager.isShowing {
            ZStack {
                // 背景遮罩
                Color.black.opacity(0.1)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isSearchFocused = false
                        manager.hide()
                    }
                
                // 弹窗内容
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // 弹窗头部
                        HStack {
                            Text("Select Card")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button(action: {
                                isSearchFocused = false
                                manager.hide()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                        
                        // 搜索栏
                        HStack {
                            TextField("Search cards", text: $searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(.white)
                                .focused($isSearchFocused)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 30)
                                        .fill(.ultraThinMaterial.opacity(0.2))
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        
                        // 卡片列表
                        ScrollView {
                            if manager.isLoading {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Text("Loading cards...")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                            } else if filteredCards.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white.opacity(0.5))
                                    Text("No cards found")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                            } else {
                            LazyVStack(spacing: 16) {
                                ForEach(filteredCards) { card in
                                    NoteCardView(card: card)
                                        .onTapGesture {
                                            manager.selectNote(card)
                                            manager.hide()
                                        }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                            }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .frame(maxHeight: .infinity)
                    }
                    .frame(
                        maxWidth: geometry.size.width,
                        maxHeight: geometry.size.height * 0.4
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .background(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .cardHighlightEffect()
                            .cornerRadius(16)
                    )
                    .clipShape(
                        RoundedCorner(radius: 20, corners: [.topLeft, .topRight])
                    )
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height - (geometry.size.height * 0.4) / 2
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                .animation(.easeInOut(duration: 0.3), value: manager.isShowing)
                .onAppear {
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                }
                .onChange(of: searchText) { newValue in
                    searchWorkItem?.cancel()
                    let workItem = DispatchWorkItem { [weak manager] in
                        manager?.fetchCards(searchText: newValue)
                    }
                    searchWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
                }
            }
        }
    }
}

// MARK: - 卡片视图
struct NoteCardView: View {
    let card: NoteCard
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NoteAuthorAvatarView(note: card, size: 28)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(card.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HTMLTextRenderer(htmlContent: card.description, maxLines: 2)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
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
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - 聊天消息视图
struct ChatMessageView: View {
    @Environment(\.adaptiveLayoutMetrics) private var adaptiveLayout
    let message: ChatMessage

    private var messageBubbleWidth: CGFloat {
        max(0, adaptiveLayout.contentWidth - 122)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // 时间戳
            Text(message.timestamp)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity)
            // 消息气泡
            HStack {
                if message.isFromMe {
                    HStack(alignment: .top, spacing: 16) {
                        Spacer()
                        
                        // 消息内容
                        VStack(alignment: .trailing, spacing: 8) {
                            Text(message.content)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .background(
                                    CustomRoundedCorners(topLeft: 20, topRight: 6, bottomLeft: 20, bottomRight: 20)
                                        .fill(.ultraThinMaterial.opacity(0.2))
                                        .overlay(
                                            CustomRoundedCorners(topLeft: 20, topRight: 6, bottomLeft: 20, bottomRight: 20)
                                                .stroke(.white.opacity(0.1), lineWidth: 1)
                                        )
                                        .customRoundedButtonHighlightEffect(topLeft: 20, topRight: 6, bottomLeft: 20, bottomRight: 20)
                                )
                            
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
                            size: 50,
                            accessibilityIdentifier: "chat.message.avatar.\(message.id)"
                        )
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        // 头像
                        ChatAvatarView(
                            rawValue: message.avatarURL,
                            size: 50,
                            accessibilityIdentifier: "chat.message.avatar.\(message.id)"
                        )
                        
                        // 消息内容
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message.content)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 18)
                                .background(
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Color.gray.opacity(0.3))
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            HTMLTextRenderer(htmlContent: note.description, maxLines: 2)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    
                    if index < notes.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
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
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - 聊天气泡附件列表
struct AttachedNotesBubbleView: View {
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
                                maxLines: 1
                            )
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .accessibilityLabel(note.description)
                                .accessibilityIdentifier(
                                    "chat.attachment.preview.\(note.id)"
                                )
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityIdentifier("chat.attachment.\(note.id)")
                    
                    if index < notes.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                    }
                }
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
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
                Image("logo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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
            .stroke(Color.white.opacity(0.2), lineWidth: 2)
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
            .stroke(Color.white.opacity(0.2), lineWidth: 2)
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
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
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
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
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
 
