import XCTest
@testable import CoreFlow

@MainActor
final class InvitationRegistrationStoreTests: XCTestCase {
    private let request = InvitationAccountRegistrationRequest(
        username: "avery",
        email: "avery@example.com",
        password: "secret123",
        verificationCode: "123456"
    )

    func testBlankCodeRegistersWithoutValidationOrRedemption() async {
        let service = InvitationCreditServiceStub()
        let registrar = InvitationRegistrarStub(results: [
            .success(.init(actorID: "act_new", isNewUser: true))
        ])
        let store = InvitationRegistrationStore(
            registrar: registrar,
            invitationService: service,
            persistence: PendingInvitationCodeMemoryStore()
        )

        await store.submit(request: request, invitationCode: "  ")

        let validationCodes = await service.recordedValidationCodes()
        let redemptionCallCount = await service.redemptionCallCount()
        let registrationCount = await registrar.requestCount()
        XCTAssertEqual(
            store.phase,
            .complete(.init(actorID: "act_new", isNewUser: true))
        )
        XCTAssertEqual(validationCodes, [])
        XCTAssertEqual(redemptionCallCount, 0)
        XCTAssertEqual(registrationCount, 1)
    }

    func testInvalidCodePreventsRegistration() async {
        let service = InvitationCreditServiceStub()
        await service.setValidationResults([.success(.init(valid: false))])
        let registrar = InvitationRegistrarStub(results: [
            .success(.init(actorID: "act_new", isNewUser: true))
        ])
        let store = InvitationRegistrationStore(
            registrar: registrar,
            invitationService: service,
            persistence: PendingInvitationCodeMemoryStore()
        )

        await store.submit(request: request, invitationCode: "CodeA")

        let registrationCount = await registrar.requestCount()
        XCTAssertEqual(store.phase, .failedBeforeAccount(.invalidCode))
        XCTAssertEqual(registrationCount, 0)
    }

    func testValidCodeRegistersAfterValidationAndRedeemsAfterSession() async {
        let recorder = InvitationCallRecorder()
        let service = InvitationCreditServiceStub(recorder: recorder)
        await service.setValidationResults([.success(.init(valid: true))])
        await service.setRedemptionResults([
            .success(.init(recordID: "inv_1", status: .registered))
        ])
        let registrar = InvitationRegistrarStub(
            results: [.success(.init(actorID: "act_new", isNewUser: true))],
            recorder: recorder
        )
        let store = InvitationRegistrationStore(
            registrar: registrar,
            invitationService: service,
            persistence: PendingInvitationCodeMemoryStore()
        )

        await store.submit(request: request, invitationCode: " CodeA ")

        let events = await recorder.snapshot()
        XCTAssertEqual(
            events,
            ["validate", "register", "session-established", "redeem"]
        )
        XCTAssertEqual(
            store.phase,
            .complete(.init(actorID: "act_new", isNewUser: true))
        )
    }

    func testRetryAfterAccountSuccessDoesNotRegisterTwice() async {
        let service = InvitationCreditServiceStub()
        await service.setValidationResults([.success(.init(valid: true))])
        await service.setRedemptionResults([
            .failure(InvitationCreditError.requestFailed(message: "Try again")),
            .success(.init(recordID: "inv_1", status: .registered))
        ])
        let registrar = InvitationRegistrarStub(results: [
            .success(.init(actorID: "act_new", isNewUser: true))
        ])
        let persistence = PendingInvitationCodeMemoryStore()
        let store = InvitationRegistrationStore(
            registrar: registrar,
            invitationService: service,
            persistence: persistence
        )

        await store.submit(request: request, invitationCode: "CodeA")
        XCTAssertEqual(
            store.phase,
            .accountCreatedPendingRedemption(
                .init(actorID: "act_new", isNewUser: true),
                .requestFailed(message: "Try again")
            )
        )
        XCTAssertEqual(persistence.pending(actorID: "act_new")?.code, "CodeA")

        await store.retryRedemption()

        let registrationCount = await registrar.requestCount()
        let redemptionCallCount = await service.redemptionCallCount()
        XCTAssertEqual(registrationCount, 1)
        XCTAssertEqual(redemptionCallCount, 2)
        XCTAssertEqual(
            store.completedAccount,
            .init(actorID: "act_new", isNewUser: true)
        )
        XCTAssertNil(persistence.pending(actorID: "act_new"))
    }

    func testContinueAfterPartialSuccessKeepsPendingIntent() async {
        let service = InvitationCreditServiceStub()
        await service.setValidationResults([.success(.init(valid: true))])
        await service.setRedemptionResults([
            .failure(InvitationCreditError.requestFailed(message: nil))
        ])
        let registrar = InvitationRegistrarStub(results: [
            .success(.init(actorID: "act_new", isNewUser: false))
        ])
        let persistence = PendingInvitationCodeMemoryStore()
        let store = InvitationRegistrationStore(
            registrar: registrar,
            invitationService: service,
            persistence: persistence
        )
        await store.submit(request: request, invitationCode: "CodeA")

        store.continueAfterPartialSuccess()

        XCTAssertEqual(
            store.completedAccount,
            .init(actorID: "act_new", isNewUser: false)
        )
        XCTAssertEqual(persistence.pending(actorID: "act_new")?.code, "CodeA")
    }
}
