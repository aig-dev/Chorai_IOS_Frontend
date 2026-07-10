import Combine
import Foundation

public protocol CoreSparkServing {
    func card(assetID: String) -> AnyPublisher<FlowCard, CoreSparkError>

    func trigger(
        sourceAssetID: String,
        parentActivityID: String?
    ) -> AnyPublisher<SparkActivityPage, CoreSparkError>

    func activityResults(
        activityID: String
    ) -> AnyPublisher<SparkActivityPage, CoreSparkError>

    func history(
        sourceAssetID: String,
        limit: Int
    ) -> AnyPublisher<[SparkHistoryEntry], CoreSparkError>

    func more(
        sourceAssetID: String,
        cursor: String?,
        limit: Int
    ) -> AnyPublisher<SparkMorePage, CoreSparkError>

    func favorite(
        assetID: String,
        sparkActivityID: String
    ) -> AnyPublisher<Void, CoreSparkError>

    func unfavorite(
        assetID: String
    ) -> AnyPublisher<Void, CoreSparkError>
}
