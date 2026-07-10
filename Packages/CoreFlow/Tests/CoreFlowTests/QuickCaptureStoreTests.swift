import Combine
import Foundation
import XCTest
@testable import CoreFlow

final class InMemoryDraftStore: CaptureDraftPersisting {
    private var values: [String: String] = [:]

    func text(for actorID: String) -> String {
        values[actorID] ?? ""
    }

    func save(_ text: String, for actorID: String) {
        values[actorID] = text
    }

    func remove(for actorID: String) {
        values[actorID] = nil
    }
}

final class DeferredCaptureService: CoreFlowServing {
    let createdCard = PassthroughSubject<CreatedCard, CoreFlowError>()

    func recommendedCards(
        limit: Int,
        refreshToken: String?
    ) -> AnyPublisher<FlowPage, CoreFlowError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }

    func favorite(assetID: String) -> AnyPublisher<Void, CoreFlowError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }

    func unfavorite(assetID: String) -> AnyPublisher<Void, CoreFlowError> {
        Fail(error: .unknown).eraseToAnyPublisher()
    }

    func createPrivateCard(content: String) -> AnyPublisher<CreatedCard, CoreFlowError> {
        createdCard.eraseToAnyPublisher()
    }
}

final class QuickCaptureStoreTests: XCTestCase {
    func testUserDefaultsDraftStoreKeepsActorKeysIndependent() throws {
        let suiteName = "CoreFlowTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let drafts = UserDefaultsCaptureDraftStore(
            defaults: defaults,
            keyPrefix: "capture"
        )

        drafts.save("Keep A", for: "act_a")
        drafts.save("Keep B", for: "act_b")
        drafts.remove(for: "act_a")

        XCTAssertEqual(drafts.text(for: "act_a"), "")
        XCTAssertEqual(drafts.text(for: "act_b"), "Keep B")
    }

    @MainActor
    func testDraftsAreActorScopedAndSurviveCancellation() {
        let drafts = InMemoryDraftStore()
        let first = QuickCaptureStore(
            service: MockCoreFlowService(),
            draftStore: drafts
        )
        first.load(actorID: "act_a")
        first.text = "Keep A"

        let second = QuickCaptureStore(
            service: MockCoreFlowService(),
            draftStore: drafts
        )
        second.load(actorID: "act_b")
        second.text = "Keep B"

        let restored = QuickCaptureStore(
            service: MockCoreFlowService(),
            draftStore: drafts
        )
        restored.load(actorID: "act_a")

        XCTAssertEqual(restored.text, "Keep A")
    }

    @MainActor
    func testWhitespaceDoesNotCreate() {
        let service = MockCoreFlowService()
        let store = QuickCaptureStore(
            service: service,
            draftStore: InMemoryDraftStore()
        )
        store.load(actorID: "act_a")
        store.text = "  \n  "

        store.save { _ in
            XCTFail("Whitespace must not create")
        }

        XCTAssertTrue(service.createdContents.isEmpty)
        XCTAssertFalse(store.canSave)
    }

    @MainActor
    func testCreateFailureRetainsDraft() async {
        let service = MockCoreFlowService()
        service.createResults = [.failure(.offline)]
        let drafts = InMemoryDraftStore()
        let store = QuickCaptureStore(service: service, draftStore: drafts)
        store.load(actorID: "act_a")
        store.text = "Keep this thought"

        store.save { _ in
            XCTFail("Failure must not complete capture")
        }
        await settle()

        XCTAssertEqual(store.text, "Keep this thought")
        XCTAssertEqual(drafts.text(for: "act_a"), "Keep this thought")
        XCTAssertEqual(
            store.phase,
            .failed("Couldn't save. Your draft is safe.")
        )
    }

    @MainActor
    func testCreateSuccessClearsOnlyCurrentActorDraft() async {
        let service = MockCoreFlowService()
        service.createResults = [
            .success(CreatedCard(id: "card_1", content: "New", isPublic: false))
        ]
        let drafts = InMemoryDraftStore()
        drafts.save("Other", for: "act_b")
        let store = QuickCaptureStore(service: service, draftStore: drafts)
        store.load(actorID: "act_a")
        store.text = "New"
        var created: CreatedCard?

        store.save { created = $0 }
        await settle()

        XCTAssertEqual(created?.id, "card_1")
        XCTAssertEqual(store.text, "")
        XCTAssertEqual(drafts.text(for: "act_a"), "")
        XCTAssertEqual(drafts.text(for: "act_b"), "Other")
    }

    @MainActor
    func testRetryAfterFailureCreatesAndClearsDraft() async {
        let service = MockCoreFlowService()
        service.createResults = [
            .failure(.timeout),
            .success(
                CreatedCard(
                    id: "card_retry",
                    content: "Retry me",
                    isPublic: false
                )
            )
        ]
        let drafts = InMemoryDraftStore()
        let store = QuickCaptureStore(service: service, draftStore: drafts)
        store.load(actorID: "act_a")
        store.text = "Retry me"

        store.save { _ in
            XCTFail("First request must fail")
        }
        await settle()

        var createdID: String?
        store.save { createdID = $0.id }
        await settle()

        XCTAssertEqual(service.createdContents, ["Retry me", "Retry me"])
        XCTAssertEqual(createdID, "card_retry")
        XCTAssertEqual(drafts.text(for: "act_a"), "")
    }

    @MainActor
    func testSaveSuppressesDuplicateCreateWhileInFlight() async {
        let service = MockCoreFlowService()
        service.createResults = [
            .success(CreatedCard(id: "card_1", content: "Once", isPublic: false))
        ]
        let store = QuickCaptureStore(
            service: service,
            draftStore: InMemoryDraftStore()
        )
        store.load(actorID: "act_a")
        store.text = "Once"

        store.save { _ in }
        store.save { _ in
            XCTFail("Duplicate request must be ignored")
        }
        await settle()

        XCTAssertEqual(service.createdContents, ["Once"])
    }

    @MainActor
    func testActorSwitchIgnoresPreviousActorCompletion() async {
        let service = DeferredCaptureService()
        let drafts = InMemoryDraftStore()
        drafts.save("Actor B draft", for: "act_b")
        let store = QuickCaptureStore(service: service, draftStore: drafts)
        store.load(actorID: "act_a")
        store.text = "Actor A draft"
        var createdIDs: [String] = []
        store.save { createdIDs.append($0.id) }

        store.load(actorID: "act_b")
        service.createdCard.send(
            CreatedCard(id: "card_a", content: "Actor A draft", isPublic: false)
        )
        service.createdCard.send(completion: .finished)
        await settle()

        XCTAssertEqual(store.text, "Actor B draft")
        XCTAssertEqual(drafts.text(for: "act_b"), "Actor B draft")
        XCTAssertTrue(createdIDs.isEmpty)
    }

    @MainActor
    func testDiscardIsIgnoredWhileCreateIsInFlight() {
        let service = DeferredCaptureService()
        let drafts = InMemoryDraftStore()
        let store = QuickCaptureStore(service: service, draftStore: drafts)
        store.load(actorID: "act_a")
        store.text = "Still saving"
        store.save { _ in }

        store.discard()

        XCTAssertEqual(store.text, "Still saving")
        XCTAssertEqual(drafts.text(for: "act_a"), "Still saving")
        XCTAssertEqual(store.phase, .saving)
    }

    @MainActor
    func testExplicitDiscardClearsCurrentDraft() {
        let drafts = InMemoryDraftStore()
        let store = QuickCaptureStore(
            service: MockCoreFlowService(),
            draftStore: drafts
        )
        store.load(actorID: "act_a")
        store.text = "Discard me"

        store.discard()

        XCTAssertEqual(store.text, "")
        XCTAssertEqual(drafts.text(for: "act_a"), "")
    }

    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
