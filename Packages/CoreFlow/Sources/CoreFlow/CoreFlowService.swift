import Combine
import Foundation

public protocol CoreFlowServing {
    func recommendedCards(limit: Int, refreshToken: String?) -> AnyPublisher<FlowPage, CoreFlowError>
    func favorite(assetID: String) -> AnyPublisher<Void, CoreFlowError>
    func unfavorite(assetID: String) -> AnyPublisher<Void, CoreFlowError>
}
