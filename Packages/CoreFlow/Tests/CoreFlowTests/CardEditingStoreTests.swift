import Foundation
import XCTest
@testable import CoreFlow

@MainActor
final class CardEditingStoreTests: XCTestCase {
    func testHydrateReplacesCanonicalEditorStateWithoutCallingService() {
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Old", tags: [], isPublic: false),
            backgroundMediaRef: "med_old",
            links: [],
            service: service
        )
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )

        store.hydrate(
            draft: .init(
                title: "Canonical",
                content: "Server body",
                tags: ["#idea", " idea ", "work"],
                isPublic: true
            ),
            backgroundMediaRef: "med_server",
            links: [link]
        )

        XCTAssertEqual(
            store.draft,
            .init(
                title: "Canonical",
                content: "Server body",
                tags: ["idea", "work"],
                isPublic: true
            )
        )
        XCTAssertEqual(store.backgroundMediaRef, "med_server")
        XCTAssertEqual(store.links, [link])
        XCTAssertEqual(store.phase, .ready)
        XCTAssertTrue(service.saveRequests.isEmpty)
    }

    func testUpdateDraftNormalizesTagsWithoutCallingService() {
        let service = MockCardEditingService()
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Old", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        store.updateDraft(
            .init(
                title: "Local",
                content: "Typed body",
                tags: ["#one", " one ", "two"],
                isPublic: false
            )
        )

        XCTAssertEqual(store.draft.tags, ["one", "two"])
        XCTAssertEqual(store.draft.content, "Typed body")
        XCTAssertTrue(service.saveRequests.isEmpty)
    }

    func testSaveFailureKeepsNormalizedDraftForExactRetry() async {
        let service = MockCardEditingService()
        service.saveResults = [
            .failure(.transport(code: "offline")),
            .success(snapshot(content: "Revised", tags: ["idea", "work"]))
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(
                title: "Revised",
                content: "Revised",
                tags: ["#idea", " work ", "idea", "", "extra"],
                isPublic: false
            ),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        store.save()
        await waitForStore { store.phase == .failed(.transport(code: "offline")) }

        XCTAssertEqual(store.draft.tags, ["idea", "work", "extra"])
        XCTAssertEqual(service.saveRequests.count, 1)
        XCTAssertEqual(service.saveRequests[0].draft, store.draft)

        store.save()
        await waitForStore { store.phase == .ready }

        XCTAssertEqual(service.saveRequests.count, 2)
        XCTAssertEqual(service.saveRequests[0], service.saveRequests[1])
    }

    func testDeleteLinkFailureRetainsLinkUntilCanonicalSuccess() async {
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )
        let service = MockCardEditingService()
        service.deleteLinkResults = [
            .failure(.transport(code: "offline")),
            .success(())
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [link],
            service: service
        )

        store.deleteLink(link)
        await waitForStore { store.phase == .failed(.transport(code: "offline")) }
        XCTAssertEqual(store.links, [link])

        store.deleteLink(link)
        await waitForStore { store.phase == .ready }
        XCTAssertTrue(store.links.isEmpty)
        XCTAssertEqual(service.deleteLinkRequests, [link, link])
    }

    func testCreateLinkFailureDoesNotPublishLocalRelationship() async {
        let link = CardEditingLink(
            sourceCardID: "ast_1",
            targetCardID: "ast_2",
            title: "Companion"
        )
        let service = MockCardEditingService()
        service.createLinkResults = [
            .failure(.transport(code: "conflict")),
            .success(())
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: nil,
            links: [],
            service: service
        )

        store.createLink(link)
        await waitForStore { store.phase == .failed(.transport(code: "conflict")) }
        XCTAssertTrue(store.links.isEmpty)

        store.createLink(link)
        await waitForStore { store.phase == .ready }
        XCTAssertEqual(store.links, [link])
        XCTAssertEqual(service.createLinkRequests, [link, link])
    }

    func testBackgroundFailureKeepsCommittedRefUntilRetrySucceeds() async {
        let image = CardEditingImage(
            data: Data("image".utf8),
            filename: "background.png",
            mimeType: "image/png"
        )
        let service = MockCardEditingService()
        service.replaceBackgroundResults = [
            .failure(.transport(code: "upload_failed")),
            .success("med_new")
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_old",
            links: [],
            service: service
        )

        store.replaceBackground(with: image)
        await waitForStore {
            store.phase == .failed(.transport(code: "upload_failed"))
        }
        XCTAssertEqual(store.backgroundMediaRef, "med_old")

        store.replaceBackground(with: image)
        await waitForStore { store.phase == .ready }
        XCTAssertEqual(store.backgroundMediaRef, "med_new")
        XCTAssertEqual(service.replaceBackgroundRequests.count, 2)
    }

    func testInvalidBackgroundNeverCallsServiceOrReplacesCommittedRef() {
        let service = MockCardEditingService()
        service.replaceBackgroundResults = [.success("med_unexpected")]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )
        let oversized = CardEditingImage(
            data: Data(count: CardEditingImage.maxBackgroundBytes + 1),
            filename: "background.png",
            mimeType: "image/png"
        )

        store.replaceBackground(with: oversized)

        XCTAssertEqual(
            store.phase,
            .failed(.invalidDraft(code: "invalid_background_image"))
        )
        XCTAssertEqual(store.backgroundMediaRef, "med_existing")
        XCTAssertTrue(service.replaceBackgroundRequests.isEmpty)
    }

    func testRemoveBackgroundFailureKeepsCommittedRefUntilRetrySucceeds() async {
        let service = MockCardEditingService()
        service.removeBackgroundResults = [
            .failure(.transport(code: "remove_failed")),
            .success(())
        ]
        let store = CardEditingStore(
            cardID: "ast_1",
            draft: .init(title: nil, content: "Body", tags: [], isPublic: false),
            backgroundMediaRef: "med_existing",
            links: [],
            service: service
        )

        store.removeBackground()
        await waitForStore {
            store.phase == .failed(.transport(code: "remove_failed"))
        }
        XCTAssertEqual(store.backgroundMediaRef, "med_existing")

        store.removeBackground()
        await waitForStore { store.phase == .ready }
        XCTAssertNil(store.backgroundMediaRef)
        XCTAssertEqual(service.removeBackgroundRequests, ["ast_1", "ast_1"])
    }

    private func snapshot(
        content: String,
        tags: [String]
    ) -> CardEditingSnapshot {
        CardEditingSnapshot(
            id: "ast_1",
            title: "Revised",
            content: content,
            tags: tags,
            isPublic: false,
            backgroundMediaRef: nil
        )
    }

    private func waitForStore(
        timeoutIterations: Int = 500,
        _ predicate: @escaping () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for card editing store state")
    }
}

private final class MockCardEditingService: CoreCardEditingServing, @unchecked Sendable {
    struct SaveRequest: Equatable {
        let cardID: String
        let draft: CardEditingDraft
    }

    var saveResults: [Result<CardEditingSnapshot, CardEditingError>] = []
    var createLinkResults: [Result<Void, CardEditingError>] = []
    var deleteLinkResults: [Result<Void, CardEditingError>] = []
    var replaceBackgroundResults: [Result<String, CardEditingError>] = []
    var removeBackgroundResults: [Result<Void, CardEditingError>] = []

    private(set) var saveRequests: [SaveRequest] = []
    private(set) var createLinkRequests: [CardEditingLink] = []
    private(set) var deleteLinkRequests: [CardEditingLink] = []
    private(set) var replaceBackgroundRequests: [CardEditingImage] = []
    private(set) var removeBackgroundRequests: [String] = []

    func save(cardID: String, draft: CardEditingDraft) async throws -> CardEditingSnapshot {
        saveRequests.append(.init(cardID: cardID, draft: draft))
        return try saveResults.removeFirst().get()
    }

    func createLink(_ link: CardEditingLink) async throws {
        createLinkRequests.append(link)
        try createLinkResults.removeFirst().get()
    }

    func deleteLink(_ link: CardEditingLink) async throws {
        deleteLinkRequests.append(link)
        try deleteLinkResults.removeFirst().get()
    }

    func replaceBackground(
        cardID: String,
        image: CardEditingImage
    ) async throws -> String {
        replaceBackgroundRequests.append(image)
        return try replaceBackgroundResults.removeFirst().get()
    }

    func removeBackground(cardID: String) async throws {
        removeBackgroundRequests.append(cardID)
        try removeBackgroundResults.removeFirst().get()
    }
}
