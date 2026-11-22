import XCTest
@testable import CoreFlow

@MainActor
final class OwnedCardActionStoreTests: XCTestCase {
    private func card(_ id: String = "outside-home", owned: Bool = true, publicValue: Bool = false, pinned: Bool = false) -> OwnedCardActionSnapshot {
        .init(cardID: id, isOwned: owned, isPublic: publicValue, isPinned: pinned, pinnedAt: nil)
    }

    func testDeleteNeedsConfirmationAndCancelSendsNothing() async {
        let service = ActionService()
        let store = OwnedCardActionStore(service: service)
        store.requestRemoval(of: card("A"))
        store.requestRemoval(of: card("B"))
        XCTAssertEqual(store.removalTarget?.cardID, "A")
        XCTAssertTrue(service.requests.isEmpty)
        store.cancelRemoval()
        store.confirmRemoval()
        await Task.yield()
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertNil(store.lastCommit)
    }

    func testDialogDismissalBeforeConfirmKeepsCapturedTargetButCancelRevokesIt() async {
        let service = ActionService()
        let store = OwnedCardActionStore(service: service)
        let target = card("A")
        store.requestRemoval(of: target)
        store.dismissRemovalDialog()
        XCTAssertNil(store.removalTarget)
        store.confirmRemoval(of: target)
        await waitFor { store.commitRevision == 1 }
        XCTAssertEqual(service.requests, [.init(cardID: "A", operation: .remove)])

        let cancelled = card("B")
        store.requestRemoval(of: cancelled)
        store.dismissRemovalDialog()
        store.cancelRemoval()
        store.confirmRemoval(of: cancelled)
        await Task.yield()
        XCTAssertEqual(service.requests.count, 1)
    }

    func testDismissedConfirmationCannotDeleteAfterAnotherTargetReplacesIt() async {
        let service = ActionService()
        let store = OwnedCardActionStore(service: service)
        store.requestRemoval(of: card("A"))
        store.dismissRemovalDialog()
        store.requestRemoval(of: card("B"))
        store.confirmRemoval(of: card("A"))
        await Task.yield()
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertEqual(store.removalTarget?.cardID, "B")
        store.cancelRemoval()
    }

    func testConfirmedDeleteUsesCapturedTargetOutsideAnyHomeList() async {
        let service = ActionService()
        let store = OwnedCardActionStore(service: service)
        store.requestRemoval(of: card("A"))
        store.confirmRemoval()
        await waitFor { store.commitRevision == 1 }
        XCTAssertEqual(service.requests, [.init(cardID: "A", operation: .remove)])
        XCTAssertEqual(store.lastCommit, .removed(cardID: "A"))
        XCTAssertTrue(store.isRemoved(cardID: "A"))
    }

    func testFailureKeepsStateAndRetriesTheSameConfirmedOperation() async {
        let service = ActionService()
        service.shouldFail = true
        let store = OwnedCardActionStore(service: service)
        store.toggleVisibility(of: card())
        await waitFor { store.failure != nil }
        XCTAssertFalse(store.resolved(card()).isPublic)
        XCTAssertNil(store.lastCommit)
        let failure = store.failure!
        store.dismissFailure()
        service.shouldFail = false
        store.retry(failure)
        await waitFor { store.commitRevision == 1 }
        XCTAssertEqual(service.requests.count, 2)
        XCTAssertEqual(service.requests[0], service.requests[1])
        XCTAssertTrue(store.resolved(card()).isPublic)
    }

    func testNextVisibilityToggleUsesServerConfirmedStateEvenWithStaleViewInput() async {
        let service = ActionService()
        service.visibilityResult = false
        let store = OwnedCardActionStore(service: service)
        let stale = card()
        store.toggleVisibility(of: stale)
        await waitFor { store.commitRevision == 1 }
        XCTAssertFalse(store.resolved(stale).isPublic)
        service.visibilityResult = true
        store.toggleVisibility(of: stale)
        await waitFor { store.commitRevision == 2 }
        XCTAssertEqual(service.requests[1].operation, .setVisibility(true))
        store.toggleVisibility(of: stale)
        await waitFor { store.commitRevision == 3 }
        XCTAssertEqual(service.requests[2].operation, .setVisibility(false))
    }

    func testPinUsesCommittedStateAndPreservesOtherCardFields() async {
        let service = ActionService()
        let store = OwnedCardActionStore(service: service)
        let stale = card(publicValue: true)
        store.togglePin(of: stale)
        await waitFor { store.commitRevision == 1 }
        XCTAssertTrue(store.resolved(stale).isPinned)
        XCTAssertTrue(store.resolved(stale).isPublic)
        XCTAssertEqual(store.resolved(stale).pinnedAt, "server-time")
        store.togglePin(of: stale)
        await waitFor { store.commitRevision == 2 }
        XCTAssertEqual(service.requests[1].operation, .setPinned(false))
        XCTAssertFalse(store.resolved(stale).isPinned)
    }

    func testConcurrentActionsCannotReplaceAnInflightTarget() async {
        let service = ActionService()
        service.suspends = true
        let store = OwnedCardActionStore(service: service)
        store.togglePin(of: card("A"))
        await waitFor { service.pending != nil }
        store.toggleVisibility(of: card("B"))
        store.requestRemoval(of: card("B"))
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertNil(store.removalTarget)
        service.pending?.resume(returning: .pin(cardID: "A", isPinned: true, pinnedAt: "t"))
        service.pending = nil
        await waitFor { store.commitRevision == 1 }
        XCTAssertEqual(store.lastCommit, .pin(cardID: "A", isPinned: true, pinnedAt: "t"))
        XCTAssertFalse(store.resolved(card("B")).isPinned)
    }

    func testUnownedAndBlankTargetsNeverMutateOrRequestConfirmation() async {
        let service = ActionService()
        let store = OwnedCardActionStore(service: service)
        for value in [card("", owned: true), card("  ", owned: true), card("other", owned: false)] {
            store.requestRemoval(of: value)
            store.confirmRemoval()
            store.toggleVisibility(of: value)
            store.togglePin(of: value)
        }
        await Task.yield()
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertNil(store.removalTarget)
    }

    func testMismatchedResponseCannotUpdateAnotherCardOrReportSuccess() async {
        let service = ActionService()
        service.forcedCommit = .pin(cardID: "different", isPinned: true, pinnedAt: nil)
        let store = OwnedCardActionStore(service: service)
        store.togglePin(of: card("A"))
        await waitFor { store.failure != nil }
        XCTAssertNil(store.lastCommit)
        XCTAssertFalse(store.resolved(card("A")).isPinned)
        XCTAssertEqual(store.commitRevision, 0)
    }

    func testDeleteFailureRetainsExactConfirmedTargetForRetry() async {
        let service = ActionService()
        service.shouldFail = true
        let store = OwnedCardActionStore(service: service)
        store.requestRemoval(of: card("A")); store.confirmRemoval()
        await waitFor { store.failure != nil }
        let failure = store.failure!
        XCTAssertFalse(store.isRemoved(cardID: "A"))
        service.shouldFail = false
        store.retry(failure)
        await waitFor { store.commitRevision == 1 }
        XCTAssertEqual(service.requests.map(\.cardID), ["A", "A"])
        XCTAssertEqual(store.lastCommit, .removed(cardID: "A"))
    }

    func testExplicitPostEditorRefreshReplacesReceiptsAndControlsTheNextToggle() async {
        let service = ActionService()
        let store = OwnedCardActionStore(service: service)
        let stale = card("A")
        store.toggleVisibility(of: stale)
        await waitFor { store.commitRevision == 1 }
        store.togglePin(of: stale)
        await waitFor { store.commitRevision == 2 }
        XCTAssertTrue(store.resolved(stale).isPublic)
        XCTAssertTrue(store.resolved(stale).isPinned)

        let refreshed = OwnedCardActionRefresh(snapshot: card("A", publicValue: false, pinned: false))
        store.applyAuthoritativeRefresh(refreshed)
        XCTAssertFalse(store.resolved(stale).isPublic)
        XCTAssertFalse(store.resolved(stale).isPinned)
        store.toggleVisibility(of: stale)
        await waitFor { store.commitRevision == 3 }
        XCTAssertEqual(service.requests.last?.operation, .setVisibility(true))
        store.applyAuthoritativeRefresh(refreshed)
        XCTAssertTrue(store.resolved(stale).isPublic, "Re-rendering the same refresh cannot overwrite a newer receipt")
        store.togglePin(of: stale)
        await waitFor { store.commitRevision == 4 }
        XCTAssertEqual(service.requests.last?.operation, .setPinned(true))
    }

    func testAuthorityRefreshDoesNotOverwriteAnInflightMutation() async {
        let service = ActionService()
        service.suspends = true
        let store = OwnedCardActionStore(service: service)
        store.toggleVisibility(of: card("A"))
        await waitFor { service.pending != nil }
        store.applyAuthoritativeRefresh(.init(snapshot: card("A", publicValue: true, pinned: true)))
        XCTAssertFalse(store.resolved(card("A")).isPinned)
        service.pending?.resume(returning: .visibility(cardID: "A", isPublic: true))
        service.pending = nil
        await waitFor { store.commitRevision == 1 }
        XCTAssertTrue(store.resolved(card("A")).isPublic)
        XCTAssertFalse(store.resolved(card("A")).isPinned)
    }

    func testRetiringSessionDiscardsLateVisibilityAndStaleDecisionCannotRetry() async throws {
        let service = ActionService()
        service.suspends = true
        let store = OwnedCardActionStore(service: service)
        store.toggleVisibility(of: card())
        await waitFor { service.pending != nil }
        store.retireSession()
        service.pending?.resume(returning: .visibility(cardID: "outside-home", isPublic: true))
        service.pending = nil
        await Task.yield()
        XCTAssertNil(store.lastCommit)
        XCTAssertFalse(store.resolved(card()).isPublic)
        store.toggleVisibility(of: card())
        await waitFor { service.pending != nil }
        service.pending?.resume(throwing: NotePrivacyError.stalePolicy)
        service.pending = nil
        await waitFor { store.failure != nil }
        let failure = try XCTUnwrap(store.failure)
        XCTAssertFalse(failure.error.mayRetry)
        store.retry(failure)
        XCTAssertEqual(service.requests.count, 2)
        XCTAssertNil(store.workingRequest)
    }

    private func waitFor(_ predicate: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let end = Date().addingTimeInterval(2)
        while !predicate(), Date() < end { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(predicate(), file: file, line: line)
    }
}

@MainActor private final class ActionService: OwnedCardActionServing {
    var requests: [OwnedCardActionRequest] = []
    var shouldFail = false
    var visibilityResult: Bool?
    var forcedCommit: OwnedCardActionCommit?
    var suspends = false
    var pending: CheckedContinuation<OwnedCardActionCommit, Error>?
    func perform(_ request: OwnedCardActionRequest) async throws -> OwnedCardActionCommit {
        requests.append(request)
        if shouldFail { throw OwnedCardActionError.requestFailed }
        if suspends { return try await withCheckedThrowingContinuation { pending = $0 } }
        if let forcedCommit { return forcedCommit }
        switch request.operation {
        case .remove: return .removed(cardID: request.cardID)
        case .setVisibility(let value): return .visibility(cardID: request.cardID, isPublic: visibilityResult ?? value)
        case .setPinned(let value): return .pin(cardID: request.cardID, isPinned: value, pinnedAt: value ? "server-time" : nil)
        }
    }
}
