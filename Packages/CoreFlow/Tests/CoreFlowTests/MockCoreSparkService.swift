import Combine
import Foundation
@testable import CoreFlow

final class MockCoreSparkService: CoreSparkServing {
    struct TriggerCall: Equatable {
        let sourceAssetID: String
        let parentActivityID: String?
    }

    struct MoreCall: Equatable {
        let sourceAssetID: String
        let cursor: String?
        let limit: Int
    }

    struct FavoriteCall: Equatable {
        let assetID: String
        let sparkActivityID: String
    }

    private(set) var requestedCardIDs: [String] = []
    private(set) var triggerCalls: [TriggerCall] = []
    private(set) var requestedActivityIDs: [String] = []
    private(set) var historyCalls: [(sourceAssetID: String, limit: Int)] = []
    private(set) var moreCalls: [MoreCall] = []
    private(set) var favoriteCalls: [FavoriteCall] = []
    private(set) var unfavoriteAssetIDs: [String] = []

    private var cardSubjects: [PassthroughSubject<FlowCard, CoreSparkError>] = []
    private var triggerSubjects: [PassthroughSubject<SparkActivityPage, CoreSparkError>] = []
    private var activitySubjects: [PassthroughSubject<SparkActivityPage, CoreSparkError>] = []
    private var historySubjects: [PassthroughSubject<[SparkHistoryEntry], CoreSparkError>] = []
    private var moreSubjects: [PassthroughSubject<SparkMorePage, CoreSparkError>] = []
    private var favoriteSubjects: [PassthroughSubject<Void, CoreSparkError>] = []
    private var unfavoriteSubjects: [PassthroughSubject<Void, CoreSparkError>] = []

    func enqueueCard() -> PassthroughSubject<FlowCard, CoreSparkError> {
        let subject = PassthroughSubject<FlowCard, CoreSparkError>()
        cardSubjects.append(subject)
        return subject
    }

    func enqueueTrigger() -> PassthroughSubject<SparkActivityPage, CoreSparkError> {
        let subject = PassthroughSubject<SparkActivityPage, CoreSparkError>()
        triggerSubjects.append(subject)
        return subject
    }

    func enqueueActivityResults() -> PassthroughSubject<SparkActivityPage, CoreSparkError> {
        let subject = PassthroughSubject<SparkActivityPage, CoreSparkError>()
        activitySubjects.append(subject)
        return subject
    }

    func enqueueHistory() -> PassthroughSubject<[SparkHistoryEntry], CoreSparkError> {
        let subject = PassthroughSubject<[SparkHistoryEntry], CoreSparkError>()
        historySubjects.append(subject)
        return subject
    }

    func enqueueMore() -> PassthroughSubject<SparkMorePage, CoreSparkError> {
        let subject = PassthroughSubject<SparkMorePage, CoreSparkError>()
        moreSubjects.append(subject)
        return subject
    }

    func enqueueFavorite() -> PassthroughSubject<Void, CoreSparkError> {
        let subject = PassthroughSubject<Void, CoreSparkError>()
        favoriteSubjects.append(subject)
        return subject
    }

    func enqueueUnfavorite() -> PassthroughSubject<Void, CoreSparkError> {
        let subject = PassthroughSubject<Void, CoreSparkError>()
        unfavoriteSubjects.append(subject)
        return subject
    }

    func card(assetID: String) -> AnyPublisher<FlowCard, CoreSparkError> {
        requestedCardIDs.append(assetID)
        return dequeue(&cardSubjects).eraseToAnyPublisher()
    }

    func trigger(
        sourceAssetID: String,
        parentActivityID: String?
    ) -> AnyPublisher<SparkActivityPage, CoreSparkError> {
        triggerCalls.append(
            TriggerCall(
                sourceAssetID: sourceAssetID,
                parentActivityID: parentActivityID
            )
        )
        return dequeue(&triggerSubjects).eraseToAnyPublisher()
    }

    func activityResults(
        activityID: String
    ) -> AnyPublisher<SparkActivityPage, CoreSparkError> {
        requestedActivityIDs.append(activityID)
        return dequeue(&activitySubjects).eraseToAnyPublisher()
    }

    func history(
        sourceAssetID: String,
        limit: Int
    ) -> AnyPublisher<[SparkHistoryEntry], CoreSparkError> {
        historyCalls.append((sourceAssetID, limit))
        return dequeue(&historySubjects).eraseToAnyPublisher()
    }

    func more(
        sourceAssetID: String,
        cursor: String?,
        limit: Int
    ) -> AnyPublisher<SparkMorePage, CoreSparkError> {
        moreCalls.append(
            MoreCall(
                sourceAssetID: sourceAssetID,
                cursor: cursor,
                limit: limit
            )
        )
        return dequeue(&moreSubjects).eraseToAnyPublisher()
    }

    func favorite(
        assetID: String,
        sparkActivityID: String
    ) -> AnyPublisher<Void, CoreSparkError> {
        favoriteCalls.append(
            FavoriteCall(
                assetID: assetID,
                sparkActivityID: sparkActivityID
            )
        )
        return dequeue(&favoriteSubjects).eraseToAnyPublisher()
    }

    func unfavorite(
        assetID: String
    ) -> AnyPublisher<Void, CoreSparkError> {
        unfavoriteAssetIDs.append(assetID)
        return dequeue(&unfavoriteSubjects).eraseToAnyPublisher()
    }

    private func dequeue<Output>(
        _ subjects: inout [PassthroughSubject<Output, CoreSparkError>]
    ) -> PassthroughSubject<Output, CoreSparkError> {
        precondition(!subjects.isEmpty, "A publisher must be enqueued before the service call")
        return subjects.removeFirst()
    }
}

final class InMemorySparkSessionPersistence: SparkSessionPersisting {
    private var snapshots: [String: SparkSessionSnapshot] = [:]
    private(set) var saves: [SparkSessionSnapshot] = []
    private(set) var removals: [(actorID: String, rootSourceAssetID: String)] = []

    var lastSaved: SparkSessionSnapshot? { saves.last }

    func snapshot(
        actorID: String,
        rootSourceAssetID: String
    ) -> SparkSessionSnapshot? {
        snapshots[key(actorID: actorID, rootSourceAssetID: rootSourceAssetID)]
    }

    func save(_ snapshot: SparkSessionSnapshot) {
        snapshots[key(
            actorID: snapshot.actorID,
            rootSourceAssetID: snapshot.rootSourceAssetID
        )] = snapshot
        saves.append(snapshot)
    }

    func remove(
        actorID: String,
        rootSourceAssetID: String
    ) {
        snapshots[key(actorID: actorID, rootSourceAssetID: rootSourceAssetID)] = nil
        removals.append((actorID, rootSourceAssetID))
    }

    func seed(_ snapshot: SparkSessionSnapshot) {
        snapshots[key(
            actorID: snapshot.actorID,
            rootSourceAssetID: snapshot.rootSourceAssetID
        )] = snapshot
    }

    private func key(
        actorID: String,
        rootSourceAssetID: String
    ) -> String {
        "\(actorID)|\(rootSourceAssetID)"
    }
}
