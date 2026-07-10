import Combine
@testable import CoreFlow

final class MockCoreFlowService: CoreFlowServing {
    var recommendedResults: [Result<FlowPage, CoreFlowError>] = []
    var favoriteResults: [Result<Void, CoreFlowError>] = []
    var unfavoriteResults: [Result<Void, CoreFlowError>] = []
    var createResults: [Result<CreatedCard, CoreFlowError>] = []

    private(set) var requestedRefreshTokens: [String?] = []
    private(set) var favoritedAssetIDs: [String] = []
    private(set) var unfavoritedAssetIDs: [String] = []
    private(set) var createdContents: [String] = []

    func recommendedCards(
        limit: Int,
        refreshToken: String?
    ) -> AnyPublisher<FlowPage, CoreFlowError> {
        requestedRefreshTokens.append(refreshToken)
        return pop(&recommendedResults).publisher.eraseToAnyPublisher()
    }

    func favorite(assetID: String) -> AnyPublisher<Void, CoreFlowError> {
        favoritedAssetIDs.append(assetID)
        return pop(&favoriteResults).publisher.eraseToAnyPublisher()
    }

    func unfavorite(assetID: String) -> AnyPublisher<Void, CoreFlowError> {
        unfavoritedAssetIDs.append(assetID)
        return pop(&unfavoriteResults).publisher.eraseToAnyPublisher()
    }

    func createPrivateCard(content: String) -> AnyPublisher<CreatedCard, CoreFlowError> {
        createdContents.append(content)
        return pop(&createResults).publisher.eraseToAnyPublisher()
    }

    private func pop<T>(
        _ values: inout [Result<T, CoreFlowError>]
    ) -> Result<T, CoreFlowError> {
        values.isEmpty ? .failure(.unknown) : values.removeFirst()
    }
}
