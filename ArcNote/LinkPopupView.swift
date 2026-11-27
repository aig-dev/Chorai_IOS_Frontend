import SwiftUI
import Combine
import CoreFlow
import UIKit

// MARK: - Link数据模型
struct LinkItem: Identifiable {
    let id: String
    let avatar: String
    let title: String
    let description: String
    let username: String
    let authorId: String?
    let labels: [String]

    init(id: String, avatar: String, title: String, description: String, username: String, authorId: String? = nil, labels: [String] = []) {
        self.id = id
        self.avatar = avatar
        self.title = title
        self.description = description
        self.username = username
        self.authorId = authorId
        self.labels = labels
    }
}

enum LinkPopupPresentationMode {
    case createLink
    case selectionOnly
}

// MARK: - Link弹窗管理器
@MainActor
final class LinkPopupManager: ObservableObject {
    @Published var isShowing = false
    @Published var searchText = ""
    @Published var linkItems: [LinkItem] = []
    @Published var isLoading = false
    @Published var isLinking = false
    @Published var showErrorAlert = false
    @Published var errorMessage = ""

    // 选择回调
    var onCardSelected: ((LinkItem) -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var currentCardId: String? = nil
    private var searchType: String = "own+favorite" // 默认搜索类型
    private var isInitiatingCardOwned = true
    private var navigateAfterLink = true
    private var presentationMode: LinkPopupPresentationMode = .createLink
    private var onNavigate: (@MainActor @Sendable (CardNavigationRoute) -> Void)?
    private var presentationID = UUID()
    private var linkRequestTask: Task<Void, Never>?
    private var searchRequestID = UUID()
    private var searchRequestCancellable: AnyCancellable?

    static let shared = LinkPopupManager()

    private init() {
        // 监听搜索文本变化
        $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] searchText in
                self?.searchCards(keyword: searchText)
            }
            .store(in: &cancellables)
    }

    func show(
        cardId: String? = nil,
        isInitiatingCardOwned: Bool = true,
        navigateAfterLink: Bool = true,
        mode: LinkPopupPresentationMode = .createLink,
        onNavigate: (@MainActor @Sendable (CardNavigationRoute) -> Void)? = nil
    ) {
        linkRequestTask?.cancel()
        linkRequestTask = nil
        searchRequestCancellable?.cancel()
        searchRequestCancellable = nil
        isLinking = false
        isLoading = false
        presentationID = UUID()
        searchRequestID = UUID()
        showErrorAlert = false
        errorMessage = ""
        isShowing = true
        currentCardId = cardId
        self.isInitiatingCardOwned = isInitiatingCardOwned
        self.navigateAfterLink = navigateAfterLink
        self.presentationMode = mode
        self.onNavigate = onNavigate
        self.searchType = isInitiatingCardOwned ? "own+favorite" : "own"
        // 打开时获取初始数据（不带关键词）
        searchCards(keyword: "")
    }

    func hide() {
        linkRequestTask?.cancel()
        linkRequestTask = nil
        searchRequestCancellable?.cancel()
        searchRequestCancellable = nil
        isLinking = false
        isLoading = false
        presentationID = UUID()
        searchRequestID = UUID()
        isShowing = false
        showErrorAlert = false
        errorMessage = ""
        searchText = ""
        linkItems = []
        currentCardId = nil
        isInitiatingCardOwned = true
        navigateAfterLink = true
        onNavigate = nil
    }

    // MARK: - Link 卡片
    func linkCard(linkItem: LinkItem) {
        guard !isLinking else { return }

        if presentationMode == .selectionOnly {
            hide()
            onCardSelected?(linkItem)
            return
        }

        if let cardId = currentCardId {
            // 如果有cardId，调用API关联卡片
            guard let currentActorId = AuthManager.shared.currentUser?.id else {
                return
            }

            isLinking = true

            // card_id 必须属于发起用户的卡片
            let actualCardId: String
            let actualLinkedCardId: String

            if isInitiatingCardOwned {
                // 发起卡片属于当前用户
                actualCardId = cardId
                actualLinkedCardId = linkItem.id
                print("开始关联卡片: cardId=\(actualCardId), linkedCardId=\(actualLinkedCardId)")
            } else {
                // 发起卡片不属于当前用户，改用搜索结果中的自有卡片作为 card_id
                actualCardId = linkItem.id
                actualLinkedCardId = cardId
                print("开始关联卡片own: cardId=\(actualCardId), linkedCardId=\(actualLinkedCardId)")
            }

            let linkRequest = LinkRequest(linkedCardId: actualLinkedCardId)
            let requestPresentationID = presentationID
            let shouldNavigate = navigateAfterLink
            let navigate = onNavigate
            let selectionCallback = onCardSelected

            linkRequestTask = Task { [weak self] in
                do {
                    let response = try await NetworkManager.shared.createCardLink(
                        cardId: actualCardId, reques: linkRequest, presentsError: false
                    )
                    guard let self, self.presentationID == requestPresentationID else { return }
                    self.isLinking = false
                    guard response.success else {
                        self.errorMessage = "关联失败，请重试"
                        self.showErrorAlert = true
                        return
                    }
                    self.hide()
                    if shouldNavigate {
                        let isOwnCard = linkItem.authorId == currentActorId
                        navigate?(isOwnCard ? .editor(linkItem.id) : .detail(linkItem.id))
                    }
                    selectionCallback?(linkItem)
                } catch is CancellationError {
                    // A retired presentation cannot publish a late result.
                } catch {
                    guard let self, self.presentationID == requestPresentationID else { return }
                    self.isLinking = false
                    if case NetworkError.api(_, let code, _, _) = error,
                       code == "link_previous_request_recovered" {
                        self.errorMessage = "上次操作已恢复，请刷新后重试"
                    } else if case NetworkError.api(_, let code, _, _) = error,
                              code == "NOTE_LINK_ACTIVE_CONFLICT" {
                        self.errorMessage = "卡片已有关联，请刷新后查看"
                    } else {
                        self.errorMessage = "关联失败，请重试"
                    }
                    self.showErrorAlert = true
                }
            }

        } else {
            print("选择卡片: \(linkItem.title)")
            hide()
            onCardSelected?(linkItem)
        }
    }

    // 搜索卡片
    private func searchCards(keyword: String) {
        guard isShowing else { return }

        #if DEBUG
        if LinkPresentationFixture.isEnabled {
            isLoading = false
            linkItems = LinkPresentationFixture.items(matching: keyword)
            return
        }
        #endif

        searchRequestCancellable?.cancel()
        searchRequestCancellable = nil
        let requestPresentationID = presentationID
        let requestSearchID = UUID()
        searchRequestID = requestSearchID

        guard AuthManager.shared.currentUser != nil else {
            isLoading = false
            print("用户未登录")
            return
        }

        isLoading = true

        // 根据关键词决定搜索类型
        let searchValue = keyword.isEmpty ? "" : keyword

        searchRequestCancellable = NetworkManager.shared.getUserAllCards(
            searchType: searchType,
            search: searchValue,
            limit: 50,
            cardId: currentCardId
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self,
                      self.presentationID == requestPresentationID,
                      self.searchRequestID == requestSearchID else {
                    return
                }
                self.isLoading = false
                if case .failure(let error) = completion {
                    print("搜索卡片失败: \(error.localizedDescription)")
                }
            },
            receiveValue: { [weak self] response in
                guard let self,
                      self.presentationID == requestPresentationID,
                      self.searchRequestID == requestSearchID else {
                    return
                }
                self.isLoading = false
                if response.success {
                    // 合并所有类型的卡片
                    var allCards: [UserAllCard] = []
                    allCards.append(contentsOf: response.data.ownCards)
                    allCards.append(contentsOf: response.data.favoritedCards)
                    allCards.append(contentsOf: response.data.likedCards)
                    allCards.append(contentsOf: response.data.linkedCards)

                    self.linkItems = allCards.map { card in
                        LinkItem(
                            id: card.id,
                            avatar: card.author?.avatar ?? "", // 使用author的avatar字段
                            title: card.title ?? "",
                            description: card.content,
                            username: card.author?.username ?? "Unknown", // 使用author的username字段
                            authorId: card.author?.id,
                            labels: card.tags
                        )
                    }
                } else {
                    print("搜索失败: 服务器返回失败")
                }
            }
        )
    }

    var pickerTitle: String {
        presentationMode == .selectionOnly ? "Choose a note" : "Link"
    }

    var candidateHeading: String {
        isInitiatingCardOwned ? "Your notes and collections" : "Choose one of your notes"
    }

    var candidateExplanation: String {
        if presentationMode == .selectionOnly { return "Select a note to continue." }
        return isInitiatingCardOwned
            ? "Connect this note to one of your notes or a collected note."
            : "The connection belongs to your selected note; the other author’s note stays unchanged."
    }

    // 过滤后的Link项目
    var filteredItems: [LinkItem] {
        return linkItems
    }

}

// MARK: - Link弹窗视图
struct LinkPopupView: View {
    @ObservedObject private var manager = LinkPopupManager.shared
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                        TextField("Search notes", text: $manager.searchText)
                            .focused($isTextFieldFocused)
                            .submitLabel(.search)
                            .accessibilityIdentifier("linkPopupSearch")
                    }
                    .frame(minHeight: 44)
                }
                .listRowBackground(ChoraiTheme.surface)

                Section {
                    if manager.isLoading {
                        HStack(spacing: 12) {
                            ProgressView().tint(ChoraiTheme.ink)
                            Text("Loading…")
                        }
                        .frame(minHeight: 60)
                    } else if manager.filteredItems.isEmpty {
                        Label("No cards found", systemImage: "doc.text")
                            .foregroundStyle(ChoraiTheme.secondaryInk)
                            .frame(minHeight: 60)
                    } else {
                        ForEach(manager.filteredItems) { item in
                            Button {
                                isTextFieldFocused = false
                                manager.linkCard(linkItem: item)
                            } label: {
                                HStack(spacing: 12) {
                                    LinkItemView(item: item)
                                    Image(systemName: "link")
                                        .font(.title3)
                                        .foregroundStyle(ChoraiTheme.gold)
                                        .accessibilityHidden(true)
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .disabled(manager.isLinking)
                            .accessibilityIdentifier("linkPopupCard.\(item.id)")
                        }
                    }
                } header: {
                    Text(manager.candidateHeading)
                } footer: {
                    Text(manager.candidateExplanation)
                        .foregroundStyle(ChoraiTheme.secondaryInk)
                }
                .listRowBackground(ChoraiTheme.surface)

                if manager.isLinking {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView().tint(ChoraiTheme.gold)
                            Text("Connecting…")
                        }
                    }
                    .listRowBackground(ChoraiTheme.surface)
                }
                if manager.showErrorAlert {
                    Section {
                        Text(manager.errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("linkPopupError")
                    }
                    .listRowBackground(ChoraiTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ChoraiTheme.background)
            .foregroundStyle(ChoraiTheme.ink)
            .tint(ChoraiTheme.ink)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(manager.pickerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isTextFieldFocused = false
                        manager.hide()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Cancel")
                    .accessibilityIdentifier("linkPopupCancel")
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Text("Link cards")
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .frame(width: 1, height: 1)
                .accessibilityIdentifier("linkPopup")
        }
    }
}

// MARK: - Link项目视图
struct LinkItemView: View {
    let item: LinkItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HTMLTextRenderer(cardID: item.id, htmlContent: item.description, maxLines: 3)
                .font(.body)
                .foregroundColor(ChoraiTheme.ink)
            Text(item.username)
                .font(.caption)
                .foregroundStyle(ChoraiTheme.secondaryInk)
            if !item.labels.isEmpty {
                Text(item.labels.map { "#" + $0 }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(ChoraiTheme.secondaryInk)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }
}

/// Installed once at the app root, while callbacks stay with the manager's origin.
struct LinkPopupPresenter: View {
    @ObservedObject private var manager = LinkPopupManager.shared

    private var isPresented: Binding<Bool> {
        Binding(
            get: { manager.isShowing },
            set: { if !$0 { manager.hide() } }
        )
    }

    var body: some View {
        ChoraiNativeSheetPresenter(
            isPresented: isPresented,
            detents: [.large()],
            initialDetent: .large
        ) { _ in
            LinkPopupView()
        }
        .frame(width: 0, height: 0)
    }
}

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()

        VStack {
            Text("Test Content")
                .foregroundColor(ChoraiTheme.ink)

            Button("Show Link Popup") {
                LinkPopupManager.shared.show()
            }
        }
    }
    .overlay { LinkPopupPresenter() }
}

#if DEBUG
enum LinkPresentationFixture {
    static var isEnabled: Bool {
        LocalDevelopmentPreview.isEnabled
            && ProcessInfo.processInfo.arguments.contains("--ui-test-link-presentation")
    }

    static func items(matching keyword: String) -> [LinkItem] {
        let items = [
            LinkItem(id: "fixture-link-note", avatar: "", title: "", description: "A note about an unfinished thought.", username: "You", authorId: LocalPreviewFixtures.actorID, labels: ["Writing"]),
            LinkItem(id: "fixture-link-collected", avatar: "", title: "", description: "Attention is a kind of generosity.", username: "Mira Chen", authorId: "preview-author", labels: ["Attention"])
        ]
        guard !keyword.isEmpty else { return items }
        return items.filter { $0.description.localizedCaseInsensitiveContains(keyword) }
    }
}

/// Exercises the production picker and its existing selection-only callback.
/// Both origins use the same app-root presenter; the second is already a sheet.
struct LinkPresentationFixtureScreen: View {
    @State private var showsOriginSheet = false
    @State private var rootSelection = "none"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Choose a note") { openSelection() }
                        .accessibilityIdentifier("link.fixture.open-root")
                    Button("Open sheet origin") { showsOriginSheet = true }
                        .accessibilityIdentifier("link.fixture.open-origin-sheet")
                }
                Text(rootSelection)
                    .accessibilityIdentifier("link.fixture.root-selection")
            }
            .navigationTitle("Link presentation fixture")
            .sheet(isPresented: $showsOriginSheet) {
                LinkPresentationFixtureOriginSheet()
            }
        }
    }

    private func openSelection() {
        LinkPopupManager.shared.onCardSelected = { rootSelection = $0.id }
        LinkPopupManager.shared.show(mode: .selectionOnly)
    }
}

private struct LinkPresentationFixtureOriginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection = "none"

    var body: some View {
        NavigationStack {
            Form {
                Button("Choose a note") {
                    LinkPopupManager.shared.onCardSelected = { selection = $0.id }
                    LinkPopupManager.shared.show(mode: .selectionOnly)
                }
                .accessibilityIdentifier("link.fixture.open-from-sheet")
                Text(selection)
                    .accessibilityIdentifier("link.fixture.sheet-selection")
            }
            .navigationTitle("Sheet origin")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                        .accessibilityIdentifier("link.fixture.close-origin-sheet")
                }
            }
        }
    }
}
#endif
