import XCTest
@testable import CoreFlow

@MainActor
final class InvitationRedemptionStoreTests: XCTestCase {
    func testLoadRestoresOnlyExactActorPendingIntent() async {
        let service = InvitationCreditServiceStub()
        let persistence = PendingInvitationCodeMemoryStore()
        persistence.save(.init(actorID: "act_a", code: "CodeA", needsRetry: true))
        let store = InvitationRedemptionStore(
            service: service,
            persistence: persistence
        )

        await store.load(actorID: "act_a")
        XCTAssertEqual(store.draft, "CodeA")
        XCTAssertEqual(store.phase, .pendingRetry)

        await store.load(actorID: "act_b")
        XCTAssertEqual(store.draft, "")
        XCTAssertEqual(store.phase, .idle)
    }

    func testInvalidCodeDoesNotRedeemOrPersist() async {
        let service = InvitationCreditServiceStub()
        await service.setValidationResults([.success(.init(valid: false))])
        let persistence = PendingInvitationCodeMemoryStore()
        let store = InvitationRedemptionStore(
            service: service,
            persistence: persistence
        )
        await store.load(actorID: "act_a")
        store.setDraft("CodeA")

        await store.submit()

        let redemptionCallCount = await service.redemptionCallCount()
        XCTAssertEqual(store.phase, .failed(.invalidCode))
        XCTAssertEqual(redemptionCallCount, 0)
        XCTAssertNil(persistence.pending(actorID: "act_a"))
    }

    func testRedeemFailureRetainsCaseAndPersistsExactActorIntent() async {
        let service = InvitationCreditServiceStub()
        await service.setValidationResults([.success(.init(valid: true))])
        await service.setRedemptionResults([
            .failure(InvitationCreditError.requestFailed(message: "Try again"))
        ])
        let persistence = PendingInvitationCodeMemoryStore()
        let store = InvitationRedemptionStore(
            service: service,
            persistence: persistence
        )
        await store.load(actorID: "act_a")
        store.setDraft("  MixedCase  ")

        await store.submit()

        XCTAssertEqual(store.draft, "MixedCase")
        XCTAssertEqual(
            store.phase,
            .failed(.requestFailed(message: "Try again"))
        )
        XCTAssertEqual(
            persistence.pending(actorID: "act_a")?.code,
            "MixedCase"
        )
    }

    func testSuccessClearsDraftAndPersistence() async {
        let service = InvitationCreditServiceStub()
        await service.setValidationResults([.success(.init(valid: true))])
        await service.setRedemptionResults([
            .success(.init(recordID: "inv_1", status: .registered))
        ])
        let persistence = PendingInvitationCodeMemoryStore()
        persistence.save(.init(actorID: "act_a", code: "CodeA", needsRetry: true))
        let store = InvitationRedemptionStore(
            service: service,
            persistence: persistence
        )
        await store.load(actorID: "act_a")

        await store.submit()

        XCTAssertEqual(
            store.phase,
            .succeeded(.init(recordID: "inv_1", status: .registered))
        )
        XCTAssertEqual(store.draft, "")
        XCTAssertNotNil(store.successfulRedemptionID)
        XCTAssertNil(persistence.pending(actorID: "act_a"))
    }

    func testActorChangeMakesDelayedValidationCompletionInert() async {
        let service = InvitationCreditServiceStub()
        await service.setValidationResults([.success(.init(valid: true))])
        await service.setValidationDelay(nanoseconds: 80_000_000)
        let persistence = PendingInvitationCodeMemoryStore()
        let store = InvitationRedemptionStore(
            service: service,
            persistence: persistence
        )
        await store.load(actorID: "act_a")
        store.setDraft("CodeA")

        let oldSubmission = Task { await store.submit() }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await store.load(actorID: "act_b")
        await oldSubmission.value

        let redemptionCallCount = await service.redemptionCallCount()
        XCTAssertEqual(store.actorID, "act_b")
        XCTAssertEqual(store.phase, .idle)
        XCTAssertEqual(redemptionCallCount, 0)
        XCTAssertNil(persistence.pending(actorID: "act_a"))
        XCTAssertNil(persistence.pending(actorID: "act_b"))
    }

    func testDiscardClearsOnlyCurrentActorPendingIntent() async {
        let service = InvitationCreditServiceStub()
        let persistence = PendingInvitationCodeMemoryStore()
        persistence.save(.init(actorID: "act_a", code: "CodeA", needsRetry: true))
        persistence.save(.init(actorID: "act_b", code: "CodeB", needsRetry: true))
        let store = InvitationRedemptionStore(
            service: service,
            persistence: persistence
        )
        await store.load(actorID: "act_a")

        store.discard()

        XCTAssertNil(persistence.pending(actorID: "act_a"))
        XCTAssertEqual(persistence.pending(actorID: "act_b")?.code, "CodeB")
        XCTAssertEqual(store.phase, .idle)
    }
}
