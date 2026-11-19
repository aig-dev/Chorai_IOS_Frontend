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
    private let injectedReadSession: (@MainActor @Sendable () -> UInt64?)?
    private let injectedPublicFetch: (@MainActor @Sendable (String, Int, Int) -> AnyPublisher<UserCardsListResponse, NetworkError>)?
    private var readSession: UInt64? {
        if let injectedReadSession { return injectedReadSession() }
        return authManager.cardReadSession
    }
    private var profileActorID: String?
    private var profileSession: UInt64?
    private var profileReadID: UUID?
    private var profileReadPage: Int?
    private var profileRead: AnyCancellable?
    private var sessionObservation: AnyCancellable?
    private var loadingGeneration: UInt64 = 0
    private let projectionWorker: HomeCardProjectionWorker
    private let injectedLibrary: NoteLibraryStore?
    private var library: NoteLibraryStore { injectedLibrary ?? LocalNotesController.shared.library }
    private var libraryObservation: AnyCancellable?
    private var projectionTask: Task<Void, Never>?
    private var projectionGeneration: UInt64 = 0
    private var projectionScope: NoteStoreScope?
    private struct ProjectionReset {
        let notes: [OfflineNote]
        let scope: NoteStoreScope?
        let sortBy: String?
        let sortOrder: String?
    }
    private var pendingReset: ProjectionReset?
    private var pendingChanges: [String: OfflineNote] = [:]
    private var pendingRemovals = Set<String>()

    nonisolated init(projectionWorker: HomeCardProjectionWorker = HomeCardProjectionWorker(), library: NoteLibraryStore? = nil,
                     readSession: (@MainActor @Sendable () -> UInt64?)? = nil,
                     fetchPublicCards: (@MainActor @Sendable (String, Int, Int) -> AnyPublisher<UserCardsListResponse, NetworkError>)? = nil) {
        self.projectionWorker = projectionWorker
        self.injectedLibrary = library
        self.injectedReadSession = readSession
        self.injectedPublicFetch = fetchPublicCards
        Task { @MainActor [weak self] in self?.observeLibraryIfNeeded() }
    }

    private func observeLibraryIfNeeded() {
        guard libraryObservation == nil else { return }
        sessionObservation = NotificationCenter.default.publisher(for: .cardReadSessionDidChange).sink { [weak self] _ in
            guard let self, !self.isOwnedLibrary, self.profileSession != self.readSession else { return }
            self.retirePublicRead()
            self.profileActorID = nil; self.profileSession = nil
            self.cards = []; self.isLoading = false; self.hasMoreData = false
        }
        let library = library
        libraryObservation = library.changes.sink { [weak self, weak library] change in
            guard let self, self.isOwnedLibrary, let library else { return }
            switch change {
            case .reset: self.presentLocalNotes(library.notes, scope: library.scope)
            case let .updated(notes, removed): self.updateLocalCards(notes, removed: removed, scope: library.scope)
            }
        }
    }

    func loadUserCards(refresh: Bool = false, sortBy: String? = nil, sortOrder: String? = nil) {
        observeLibraryIfNeeded()
        let rebuild = !isOwnedLibrary || (sortBy != nil && sortBy != currentSortBy)
            || (sortOrder != nil && sortOrder != currentSortOrder)
        if !isOwnedLibrary { cards = []; retirePublicRead(); profileActorID = nil; profileSession = nil }
        isOwnedLibrary = true
        if let sortBy { currentSortBy = sortBy }
        if let sortOrder { currentSortOrder = sortOrder }
        hasMoreData = false
        if rebuild { presentLocalNotes(library.notes, scope: library.scope) }
        if injectedLibrary == nil { LocalNotesController.shared.refreshAccess() }
        loadingGeneration &+= 1
        let generation = loadingGeneration
        isLoading = true
        Task {
            await library.synchronize(forceRetry: refresh)
            // Offline synchronization can finish before the first display projection.
            await waitForLocalProjection()
            if isOwnedLibrary, generation == loadingGeneration { isLoading = false }
        }
    }

    private func presentLocalNotes(_ notes: [OfflineNote], scope: NoteStoreScope?) {
        projectionGeneration &+= 1
        if scope != projectionScope || scope == nil { cards = [] }
        projectionScope = scope
        pendingReset = ProjectionReset(notes: notes, scope: scope, sortBy: currentSortBy, sortOrder: currentSortOrder)
        pendingChanges.removeAll(); pendingRemovals.removeAll()
        startProjectionIfNeeded()
    }

    private func updateLocalCards(_ changed: [OfflineNote], removed: Set<String>, scope: NoteStoreScope?) {
        guard scope == projectionScope else { presentLocalNotes(library.notes, scope: scope); return }
        for note in changed { pendingChanges[note.localID] = note; pendingRemovals.remove(note.localID) }
        for id in removed { pendingChanges[id] = nil; pendingRemovals.insert(id) }
        startProjectionIfNeeded()
    }

    private func startProjectionIfNeeded() {
        guard projectionTask == nil else { return }
        projectionTask = Task { [weak self] in
            guard let self else { return }
            while self.pendingReset != nil || !self.pendingChanges.isEmpty || !self.pendingRemovals.isEmpty {
                let generation = self.projectionGeneration
                let reset = self.pendingReset
                let changed = Array(self.pendingChanges.values)
                let removed = self.pendingRemovals
                self.pendingReset = nil; self.pendingChanges.removeAll(); self.pendingRemovals.removeAll()
                var result: [UserCard] = []
                if let reset {
                    result = await self.projectionWorker.reset(notes: reset.notes, scope: reset.scope,
                                                               sortBy: reset.sortBy, sortOrder: reset.sortOrder)
                }
                if !changed.isEmpty || !removed.isEmpty {
                    result = await self.projectionWorker.update(changed: changed, removed: removed)
                }
                guard self.isOwnedLibrary, generation == self.projectionGeneration,
                      self.pendingReset == nil, self.pendingChanges.isEmpty, self.pendingRemovals.isEmpty else { continue }
                self.cards = result
            }
            self.projectionTask = nil
        }
    }

    func waitForLocalProjection() async { await projectionTask?.value }

    func promoteCommittedCard(id: String) {
        let library = library
        observeLibraryIfNeeded()
        if !isOwnedLibrary {
            cards = []; retirePublicRead(); profileActorID = nil; profileSession = nil
            presentLocalNotes(library.notes, scope: library.scope)
        }
        isOwnedLibrary = true
        // The commit already queued the download. Later inserts arrive via library.changes.
        if let note = library.notes.first(where: { $0.serverAssetID == id }) {
            updateLocalCards([note], removed: [], scope: library.scope)
        }
    }

    func loadPublicProfileCards(actorId: String, refresh: Bool = false) {
        observeLibraryIfNeeded()
        guard let session = readSession else {
            isOwnedLibrary = false
            projectionGeneration &+= 1; loadingGeneration &+= 1
            pendingReset = nil; pendingChanges.removeAll(); pendingRemovals.removeAll()
            retirePublicRead(); cards = []; isLoading = false; error = .unauthorized
            profileActorID = nil; profileSession = nil; hasMoreData = false
            return
        }
        let sameProfile = !isOwnedLibrary && profileActorID == actorId && profileSession == session
        if sameProfile, profileReadID != nil, !refresh || profileReadPage == 1 { return }
        if sameProfile, !refresh, !hasMoreData { return }
        projectionGeneration &+= 1
        pendingReset = nil; pendingChanges.removeAll(); pendingRemovals.removeAll()
        loadingGeneration &+= 1
        isOwnedLibrary = false
        retirePublicRead()
        if !sameProfile || refresh { currentPage = 1; cards = []; hasMoreData = true }
        profileActorID = actorId; profileSession = session
        let page = currentPage
        let requestID = UUID()
        profileReadID = requestID; profileReadPage = page
        isLoading = true; error = nil
        let publisher = injectedPublicFetch?(actorId, page, pageSize)
            ?? networkManager.getPublicProfileCards(actorId: actorId, page: page, perPage: pageSize)
        profileRead = publisher.receive(on: DispatchQueue.main).sink(
            receiveCompletion: { [weak self] completion in
                guard let self, self.acceptsPublicRead(requestID, session: session) else { return }
                self.isLoading = false
                self.profileReadID = nil; self.profileReadPage = nil; self.profileRead = nil
                if case .failure(let error) = completion { self.error = error }
            }, receiveValue: { [weak self] response in
                guard let self, self.acceptsPublicRead(requestID, session: session), self.currentPage == page else { return }
                guard response.success else { self.error = .decodingError; return }
                if page == 1 { self.cards = response.data }
                else { self.cards.append(contentsOf: response.data) }
                self.hasMoreData = response.data.count == self.pageSize
                self.currentPage = page + 1
            })
    }

    private func acceptsPublicRead(_ requestID: UUID, session: UInt64) -> Bool {
        !isOwnedLibrary && profileReadID == requestID && readSession == session && profileSession == session
    }

    private func retirePublicRead() {
        profileReadID = nil; profileReadPage = nil
        profileRead?.cancel(); profileRead = nil
    }

    func loadMoreCards() {
        guard hasMoreData && !isLoading else { return }
        if !isOwnedLibrary, let profileActorID { loadPublicProfileCards(actorId: profileActorID) }
        else { loadUserCards(refresh: false) }
    }

    func refreshCards() {
        if !isOwnedLibrary, let profileActorID { loadPublicProfileCards(actorId: profileActorID, refresh: true) }
        else { loadUserCards(refresh: true) }
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
                                isOwner: self?.cards[index].isOwner,
                                localPreviewIdentity: self?.cards[index].localPreviewIdentity
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
                                isOwner: self?.cards[index].isOwner,
                                localPreviewIdentity: self?.cards[index].localPreviewIdentity
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
