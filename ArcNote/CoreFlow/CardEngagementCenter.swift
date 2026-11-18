import Combine
import CoreFlow
import Foundation

@MainActor
final class CardEngagementCenter {
    static let shared = CardEngagementCenter()

    let likes = PassthroughSubject<CardLikeState, Never>()

    let favorites = PassthroughSubject<CardFavoriteState, Never>()
    private var favoriteObserver: AnyCancellable?

    private init() {
        favoriteObserver = NotificationCenter.default.publisher(for: .choraiFavoriteChanged)
            .sink { [weak self] notification in
                guard let payload = notification.userInfo,
                      let cardID = payload["cardID"] as? String,
                      let isFavorited = payload["isFavorited"] as? Bool else { return }
                let state = CardFavoriteState(
                    cardID: cardID,
                    isFavorited: isFavorited,
                    favoriteCount: payload["count"] as? Int
                )
                CardDetailReader.shared.didCommit(state)
                self?.favorites.send(state)
            }
    }

    func publishFavorite(_ state: CardFavoriteState) {
        var payload: [String: Any] = ["cardID": state.cardID, "isFavorited": state.isFavorited]
        if let count = state.favoriteCount { payload["count"] = count }
        NotificationCenter.default.post(name: .choraiFavoriteChanged, object: nil, userInfo: payload)
    }

    func publish(_ state: CardLikeState) {
        CardDetailReader.shared.didCommit(state)
        likes.send(state)
    }
}
