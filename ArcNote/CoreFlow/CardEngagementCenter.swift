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
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let payload = notification.userInfo,
                      let cardID = payload["cardID"] as? String,
                      let isFavorited = payload["isFavorited"] as? Bool else { return }
                self?.favorites.send(CardFavoriteState(
                    cardID: cardID,
                    isFavorited: isFavorited,
                    favoriteCount: payload["count"] as? Int
                ))
            }
    }

    func publishFavorite(_ state: CardFavoriteState) {
        var payload: [String: Any] = ["cardID": state.cardID, "isFavorited": state.isFavorited]
        if let count = state.favoriteCount { payload["count"] = count }
        NotificationCenter.default.post(name: .choraiFavoriteChanged, object: nil, userInfo: payload)
    }

    func publish(_ state: CardLikeState) {
        likes.send(state)
    }
}
