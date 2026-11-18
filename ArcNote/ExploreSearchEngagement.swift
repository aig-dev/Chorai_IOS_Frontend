import Foundation
import Combine
import CoreFlow

@MainActor
final class ExploreSearchEngagement: ObservableObject {
    // 点赞状态管理
    @Published private var cardLikeStates: [String: Bool] = [:] // cardId -> isLiked
    @Published private var cardLikeCounts: [String: Int] = [:] // cardId -> likeCount
    @Published private var cardLikeMutationIDs: Set<String> = []
    @Published private var cardLikeErrors: [String: String] = [:]

    // 收藏状态管理
    @Published private var cardFavoriteStates: [String: Bool] = [:] // cardId -> isFavorited
    @Published private var cardFavoriteCounts: [String: Int] = [:] // cardId -> favoriteCount

    // 评论数量管理
    @Published private var cardCommentCounts: [String: Int] = [:] // cardId -> commentCount

    private let networkManager = NetworkManager.shared
    private let cardLikeService: any CoreCardLikeServing = NetworkCoreCardLikeService()
    private let authManager = AuthManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("CommentCountChanged"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let cardId = notification.userInfo?["cardId"] as? String,
                      let count = notification.userInfo?["newCount"] as? Int else { return }
                self?.cardCommentCounts[cardId] = count
            }
            .store(in: &cancellables)
        CardEngagementCenter.shared.likes
            .sink { [weak self] state in
                self?.applyLikeState(state)
            }
            .store(in: &cancellables)
    }

    func getFavoriteState(for cardId: String) -> Bool {
        return cardFavoriteStates[cardId] ?? false
    }

    func getFavoriteCount(for cardId: String) -> Int {
        return cardFavoriteCounts[cardId] ?? 0
    }

    // MARK: - 评论数量相关方法
    func getCommentCount(for cardId: String) -> Int {
        cardCommentCounts[cardId] ?? 0
    }

    func getLikeState(for cardId: String) -> Bool {
        return cardLikeStates[cardId] ?? false
    }

    func getLikeCount(for cardId: String) -> Int {
        return cardLikeCounts[cardId] ?? 0
    }

    func isLikeMutationInFlight(for cardId: String) -> Bool {
        cardLikeMutationIDs.contains(cardId)
    }

    func likeError(for cardId: String) -> String? {
        cardLikeErrors[cardId]
    }

    func toggleLike(for cardId: String) {
        guard authManager.currentUser != nil else {
            print("用户未登录")
            return
        }

        guard !cardLikeMutationIDs.contains(cardId) else { return }
        let committed = CardLikeState(
            cardID: cardId,
            isLiked: getLikeState(for: cardId),
            likeCount: getLikeCount(for: cardId)
        )
        let target = !committed.isLiked
        cardLikeErrors[cardId] = nil
        cardLikeMutationIDs.insert(cardId)

        Task { [weak self] in
            guard let self else { return }
            do {
                try await cardLikeService.setLiked(
                    cardID: cardId,
                    liked: target
                )
                guard cardLikeMutationIDs.contains(cardId) else { return }
                let next = CardLikeState(
                    cardID: cardId,
                    isLiked: target,
                    likeCount: committed.likeCount + (target ? 1 : -1)
                )
                cardLikeMutationIDs.remove(cardId)
                applyLikeState(next)
                CardEngagementCenter.shared.publish(next)
            } catch {
                cardLikeMutationIDs.remove(cardId)
                cardLikeErrors[cardId] = "Like failed. Try again."
            }
        }
    }

    func toggleFavorite(for cardId: String) {
        guard authManager.currentUser != nil else {
            return
        }

        let isCurrentlyFavorited = getFavoriteState(for: cardId)
        let currentCount = cardFavoriteCounts[cardId] ?? 0
        let generation = AuthManager.shared.sessionGeneration

        if isCurrentlyFavorited {
            // Optimistic update for immediate UI feedback.
            cardFavoriteStates[cardId] = false
            cardFavoriteCounts[cardId] = max(0, currentCount - 1)
            removeFavorite(cardId: cardId) { [weak self] success in
                guard let self, !success, AuthManager.shared.sessionGeneration == generation else { return }
                self.cardFavoriteStates[cardId] = true
                self.cardFavoriteCounts[cardId] = currentCount
            }
        } else {
            // Optimistic update for immediate UI feedback.
            cardFavoriteStates[cardId] = true
            cardFavoriteCounts[cardId] = currentCount + 1
            addFavorite(cardId: cardId) { [weak self] success in
                guard let self, !success, AuthManager.shared.sessionGeneration == generation else { return }
                self.cardFavoriteStates[cardId] = false
                self.cardFavoriteCounts[cardId] = currentCount
            }
        }
    }

    private func applyLikeState(_ state: CardLikeState) {
        cardLikeStates[state.cardID] = state.isLiked
        cardLikeCounts[state.cardID] = state.likeCount
        cardLikeErrors[state.cardID] = nil
    }

    private func addFavorite(cardId: String, completion: ((Bool) -> Void)? = nil) {
        networkManager.favoriteCard(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        print("收藏失败: \(error)")
                        completion?(false)
                    }
                },
                receiveValue: { (response: NetworkResponse<FavoriteResponseData>) in
                    if response.success {
                        NotificationCenter.default.post(name: .choraiFavoriteChanged, object: nil, userInfo: ["cardID": cardId, "isFavorited": true])
                        completion?(true)
                    } else {
                        completion?(false)
                    }
                }
            )
            .store(in: &cancellables)
    }

    private func removeFavorite(cardId: String, completion: ((Bool) -> Void)? = nil) {
        networkManager.unfavoriteCard(cardId: cardId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { result in
                    if case .failure(let error) = result {
                        print("取消收藏失败: \(error)")
                        completion?(false)
                    }
                },
                receiveValue: { (response: NetworkResponse<EmptyResponseData>) in
                    if response.success {
                        NotificationCenter.default.post(name: .choraiFavoriteChanged, object: nil, userInfo: ["cardID": cardId, "isFavorited": false])
                        completion?(true)
                    } else {
                        completion?(false)
                    }
                }
            )
            .store(in: &cancellables)
    }
}
