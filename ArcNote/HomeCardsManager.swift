import Foundation
import Combine
import CoreFlow
import SwiftUI

@MainActor
class HomeCardsManager: ObservableObject {
    @Published var cards: [UserCard] = []
    @Published var isLoading: Bool = false
    @Published var error: NetworkError?
    @Published var hasMoreData: Bool = true
    
    // 收藏状态管理
    @Published var cardFavoriteStates: [String: Bool] = [:] // cardId -> isFavorited
    
    private let networkManager = NetworkManager.shared
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentPage: Int = 1
    private let pageSize: Int = 20
    private var currentSortBy: String? = "updated_at" // 默认排序字段
    private var currentSortOrder: String? = "desc" // 默认排序顺序
    
    private var isOwnedLibrary = false

    nonisolated init() {
        Task { @MainActor [weak self] in
        guard let self else { return }
        LocalNotesController.shared.library.$notes
            .sink { [weak self] notes in
                guard let self, self.isOwnedLibrary else { return }
                self.presentLocalNotes(notes)
            }.store(in: &cancellables)
        }
    }

    func loadUserCards(refresh: Bool = false, sortBy: String? = nil, sortOrder: String? = nil) {
        isOwnedLibrary = true
        if let sortBy { currentSortBy = sortBy }
        if let sortOrder { currentSortOrder = sortOrder }
        hasMoreData = false
        presentLocalNotes(LocalNotesController.shared.library.notes)
        LocalNotesController.shared.refreshAccess()
        Task {
            isLoading = true
            defer { isLoading = false }
            await LocalNotesController.shared.library.synchronize(forceRetry: refresh)
        }
    }

    private func presentLocalNotes(_ notes: [OfflineNote]) {
        let formatter = ISO8601DateFormatter()
        let sorted = notes.filter { $0.desiredLifecycle == .active }.sorted { lhs, rhs in
            if (lhs.isPinned ?? false) != (rhs.isPinned ?? false) { return lhs.isPinned ?? false }
            let a = currentSortBy == "created_at" ? lhs.createdAt : lhs.updatedAt
            let b = currentSortBy == "created_at" ? rhs.createdAt : rhs.updatedAt
            return currentSortOrder == "asc" ? a < b : a > b
        }
        cards = sorted.map { note in
            UserCard(id: NoteLibraryStore.identifier(note), title: note.body.title, content: note.body.content,
                contentJSON: note.body.contentJSON, backgroundMediaRef: note.backgroundMediaRef, contentHash: "",
                isPublic: note.isPublic, tags: note.body.tags, createdAt: formatter.string(from: note.createdAt),
                updatedAt: formatter.string(from: note.updatedAt), likeCount: 0, commentCount: nil, isLiked: false,
                isPinned: note.isPinned ?? false, pinnedAt: nil, isFavorited: nil, favoriteCount: nil, rate: 0,
                ownerActorId: authManager.currentUser?.id, isOwner: true)
        }
    }

    func promoteCommittedCard(id: String) {
        isOwnedLibrary = true
        Task {
            do {
                _ = try await LocalNotesController.shared.library.open(identifier: id)
                presentLocalNotes(LocalNotesController.shared.library.notes)
            } catch {
                // A failed cloud read never removes an already saved local note.
                self.error = .networkError(error)
            }
        }
    }

    func loadPublicProfileCards(actorId: String, refresh: Bool = false) {
        isOwnedLibrary = false
        guard authManager.currentUser != nil else {
            error = .unauthorized
            return
        }

        if refresh {
            currentPage = 1
            cards = []
            hasMoreData = true
        }

        isLoading = true
        error = nil

        networkManager.getPublicProfileCards(actorId: actorId, page: currentPage, perPage: pageSize)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.error = error
                        print("获取公开用户卡片失败: \(error)")
                    }
                },
                receiveValue: { [weak self] response in
                    guard let self = self else { return }

                    if refresh {
                        self.cards = response.data
                    } else {
                        self.cards.append(contentsOf: response.data)
                    }

                    self.hasMoreData = response.data.count == self.pageSize
                    self.currentPage += 1
                }
            )
            .store(in: &cancellables)
    }
    
    func loadMoreCards() {
        guard hasMoreData && !isLoading else { return }
        loadUserCards(refresh: false)
    }
    
    func refreshCards() {
        loadUserCards(refresh: true)
    }
    
    // MARK: 删除卡片功能
    func deleteCard(cardId: String, completion: @escaping (Result<Bool, NetworkError>) -> Void) {
        Task {
            do {
                try await LocalNotesController.shared.setLifecycle(identifier: cardId, lifecycle: .trashed)
                completion(.success(true))
            } catch { completion(.failure(.networkError(error))) }
        }
    }

    // MARK: - 收藏相关方法
    func getFavoriteState(for cardId: String) -> Bool {
        return cardFavoriteStates[cardId] ?? false
    }
    
    func toggleFavorite(for cardId: String) {
        guard authManager.currentUser != nil else {
            return
        }
        guard cards.first(where: { $0.id == cardId })?.isOwner != true else {
            return
        }
        
        let isCurrentlyFavorited = getFavoriteState(for: cardId)
        
        if isCurrentlyFavorited {
            removeFavorite(cardId: cardId)
        } else {
            addFavorite(cardId: cardId)
        }
    }
    
    private func addFavorite(cardId: String) {
        networkManager.favoriteCard(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("收藏失败: \(error)")
                    }
                },
                receiveValue: { [weak self] (response: NetworkResponse<FavoriteResponseData>) in
                    if response.success {
                        self?.cardFavoriteStates[cardId] = true
                        print("收藏成功")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    private func removeFavorite(cardId: String) {
        networkManager.unfavoriteCard(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("取消收藏失败: \(error)")
                    }
                },
                receiveValue: { [weak self] (response: NetworkResponse<EmptyResponseData>) in
                    if response.success {
                        self?.cardFavoriteStates[cardId] = false
                        print("取消收藏成功")
                    }
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - 切换卡片可见性
    func toggleCardVisibility(
        cardId: String,
        fallbackCard: UserCard? = nil,
        completion: @escaping (Result<Bool, NetworkError>) -> Void
    ) {
        guard authManager.currentUser != nil else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        // 获取当前卡片的可见性状态，然后切换
        let matchingFallbackCard = fallbackCard.flatMap {
            $0.id == cardId ? $0 : nil
        }
        guard let currentCard = cards.first(where: { $0.id == cardId })
            ?? matchingFallbackCard else {
            print("未找到卡片: cardId=\(cardId)")
            completion(.failure(.serverError(404, "卡片未找到")))
            return
        }
        
        guard let scope = authManager.currentNoteScope, authManager.canEnterProduct,
              let serverID = LocalNotesController.shared.library.serverID(for: cardId) else {
            completion(.failure(.forbidden)); return
        }
        let newIsPublic = !currentCard.isPublic
        
        networkManager.toggleCardVisibility(cardId: serverID, isPublic: newIsPublic) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.success {
                        Task { try? await LocalNotesController.shared.library.recordMetadata(identifier: cardId, isPublic: response.data.isPublic, scope: scope) }
                        // 更新本地卡片数据
                        if let index = self?.cards.firstIndex(where: { $0.id == cardId }) {
                            self?.cards[index] = UserCard(
                                id: self?.cards[index].id ?? "",
                                title: self?.cards[index].title ?? "",
                                content: self?.cards[index].content ?? "",
                                contentJSON: self?.cards[index].contentJSON,
                                backgroundMediaRef: self?.cards[index].backgroundMediaRef,
                                contentHash: self?.cards[index].contentHash ?? "",
                                isPublic: response.data.isPublic,
                                tags: self?.cards[index].tags ?? [],
                                createdAt: self?.cards[index].createdAt ?? "",
                                updatedAt: self?.cards[index].updatedAt ?? "",
                                likeCount: self?.cards[index].likeCount ?? 0,
                                commentCount: self?.cards[index].commentCount,
                                isLiked: self?.cards[index].isLiked ?? false,
                                isPinned: self?.cards[index].isPinned ?? false,
                                pinnedAt: self?.cards[index].pinnedAt,
                                isFavorited: self?.cards[index].isFavorited,
                                favoriteCount: self?.cards[index].favoriteCount,
                                rate: self?.cards[index].rate ?? 0,
                                ownerActorId: self?.cards[index].ownerActorId,
                                isOwner: self?.cards[index].isOwner
                            )
                        }
                        // The visibility response is the committed source state. The card
                        // list is an asynchronous projection and can briefly lag behind it,
                        // so an immediate reload would overwrite this value with stale data.
                        completion(.success(true))
                    } else {
                        print("卡片可见性切换失败: \(response.message ?? "未知错误")")
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    print("卡片可见性切换失败: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 切换卡片置顶状态
    func toggleCardPin(
        cardId: String,
        fallbackCard: UserCard? = nil,
        completion: @escaping (Result<Bool, NetworkError>) -> Void
    ) {
        guard authManager.currentUser != nil else {
            print("用户未登录")
            completion(.failure(.unauthorized))
            return
        }
        
        // 获取当前卡片的置顶状态，然后选择调用Pin还是Unpin API
        let matchingFallbackCard = fallbackCard.flatMap {
            $0.id == cardId ? $0 : nil
        }
        guard let currentCard = cards.first(where: { $0.id == cardId })
            ?? matchingFallbackCard else {
            print("未找到卡片: cardId=\(cardId)")
            completion(.failure(.serverError(404, "卡片未找到")))
            return
        }
        
        let isCurrentlyPinned = currentCard.isPinned
        print("卡片置顶状态: cardId=\(cardId), 当前状态: \(isCurrentlyPinned)")
        
        // 根据当前状态选择调用Pin还是Unpin API
        let apiCall: (String, @escaping (Result<ToggleCardPinResponse, NetworkError>) -> Void) -> Void
        
        if isCurrentlyPinned {
            apiCall = networkManager.unpinCard
        } else {
            apiCall = networkManager.toggleCardPin
        }
        
        guard let scope = authManager.currentNoteScope, authManager.canEnterProduct,
              let serverID = LocalNotesController.shared.library.serverID(for: cardId) else {
            completion(.failure(.forbidden)); return
        }
        apiCall(serverID) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if response.success, let updatedCard = response.data {
                        Task { try? await LocalNotesController.shared.library.recordMetadata(identifier: cardId, isPinned: updatedCard.isPinned, scope: scope) }
                        // 更新本地卡片数据
                        if let index = self?.cards.firstIndex(where: { $0.id == cardId }) {
                            self?.cards[index] = UserCard(
                                id: self?.cards[index].id ?? "",
                                title: self?.cards[index].title ?? "",
                                content: self?.cards[index].content ?? "",
                                contentJSON: self?.cards[index].contentJSON,
                                backgroundMediaRef: self?.cards[index].backgroundMediaRef,
                                contentHash: self?.cards[index].contentHash ?? "",
                                isPublic: self?.cards[index].isPublic ?? false,
                                tags: self?.cards[index].tags ?? [],
                                createdAt: self?.cards[index].createdAt ?? "",
                                updatedAt: self?.cards[index].updatedAt ?? "",
                                likeCount: self?.cards[index].likeCount ?? 0,
                                commentCount: self?.cards[index].commentCount,
                                isLiked: self?.cards[index].isLiked ?? false,
                                isPinned: updatedCard.isPinned ?? false,
                                pinnedAt: updatedCard.pinnedAt,
                                isFavorited: self?.cards[index].isFavorited,
                                favoriteCount: self?.cards[index].favoriteCount,
                                rate: self?.cards[index].rate ?? 0,
                                ownerActorId: self?.cards[index].ownerActorId,
                                isOwner: self?.cards[index].isOwner
                            )
                        }
                        print("置顶状态切换成功: cardId=\(cardId), isPinned=\(updatedCard.isPinned ?? false)")
                        // 刷新Notes列表
                        self?.loadUserCards(refresh: true)
                        completion(.success(true))
                    } else {
                        completion(.failure(.serverError(500, response.message)))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}
