import XCTest
import CoreFlow
@testable import ArcNote

@MainActor
final class CardPreviewReaderTests: XCTestCase {

    func testOverlappingViewsWithDistinctSnapshotIDsBothReceivePreview() async throws {
        let first = LibraryCardPreviewInput(cardID: "shared", contentHash: nil, snapshotID: UUID(), content: "Shared", contentJSON: nil)
        let second = LibraryCardPreviewInput(cardID: "shared", contentHash: nil, snapshotID: UUID(), content: "Shared", contentJSON: nil)
        let entered = expectation(description: "first view parsing")
        let finish = DispatchSemaphore(value: 0)
        let cache = LibraryCardPreviewCache(parse: { value in
            if value == first { entered.fulfill(); _ = finish.wait(timeout: .now() + 3) }
            return LibraryCardPreviewParser.presentation(content: value.content)
        })
        let reader = CardPreviewReader(remoteSession: { 1 }, localScope: { nil }, cache: cache, notifications: NotificationCenter())
        let firstScope = try XCTUnwrap(reader.scope(for: first))
        let secondScope = try XCTUnwrap(reader.scope(for: second))
        let one = Task { await reader.read(first, scope: firstScope) }
        await fulfillment(of: [entered], timeout: 2)
        let two = await reader.read(second, scope: secondScope)
        finish.signal()
        let firstValue = await one.value
        XCTAssertEqual(firstValue?.plainText, "Shared")
        XCTAssertEqual(two?.plainText, "Shared")
    }
    func testLocalScopeMismatchRejectsReadAndNeverFallsBackToRemote() async {
        let alice = NoteStoreScope(actorID: "alice", environmentID: "local")
        let bob = NoteStoreScope(actorID: "bob", environmentID: "local")
        var currentScope: NoteStoreScope? = alice
        let reader = CardPreviewReader(remoteSession: { 7 }, localScope: { currentScope }, notifications: NotificationCenter())
        let input = LibraryCardPreviewInput(localNoteID: "local-note:a", scope: alice, bodyRevision: 2, content: "Private", contentJSON: nil)
        let scope = try! XCTUnwrap(reader.scope(for: input))
        let first = await reader.read(input, scope: scope)
        XCTAssertEqual(first?.preview.text, "Private")
        currentScope = bob
        XCTAssertNil(reader.scope(for: input))
        let stale = await reader.read(input, scope: scope)
        XCTAssertNil(stale)
        let missingIdentity = LibraryCardPreviewInput(cardID: "local-note:a", contentHash: nil, snapshotID: UUID(), content: "Private", contentJSON: nil)
        XCTAssertNil(reader.scope(for: missingIdentity))
    }

    func testRemoteSessionChangeRejectsOldScope() async {
        var session: UInt64? = 1
        let reader = CardPreviewReader(remoteSession: { session }, localScope: { nil }, notifications: NotificationCenter())
        let input = LibraryCardPreviewInput(cardID: "a", contentHash: "hash", snapshotID: UUID(), content: "Public", contentJSON: nil)
        let scope = try! XCTUnwrap(reader.scope(for: input))
        session = 2
        let value = await reader.read(input, scope: scope)
        XCTAssertNil(value)
        session = nil
        XCTAssertNil(reader.scope(for: input))
    }

    func testLocalPreviewIdentityNeverEntersWireJSON() throws {
        var card = try JSONDecoder().decode(UserCard.self, from: Self.cardJSON)
        card.localPreviewIdentity = .init(scope: .init(actorID: "alice", environmentID: "local"), bodyRevision: 9)
        let encoded = try JSONEncoder().encode(card)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["localPreviewIdentity"])
        let decoded = try JSONDecoder().decode(UserCard.self, from: encoded)
        XCTAssertNil(decoded.localPreviewIdentity)
        XCTAssertEqual(decoded.content, "body")
    }

    func testMissingLocalIdentityDoesNotBecomeRemotePreview() throws {
        let card = try JSONDecoder().decode(UserCard.self, from: Self.cardJSON)
        XCTAssertNil(card.previewInput(snapshotID: UUID()))
    }

    func testLocalProjectionPreservesOriginalScopeAndRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let scope = NoteStoreScope(actorID: "original-actor", environmentID: "local")
        let store = try await NoteLocalStore.open(rootURL: root, scope: scope)
        let note = try await store.create(body: .init(content: "First"), localID: "one")
        let changed = try await store.saveBody(localID: note.localID, body: .init(content: "Second"))
        let cards = await HomeCardProjectionWorker().reset(notes: [changed], scope: scope, sortBy: "updated_at", sortOrder: "desc")
        let card = try XCTUnwrap(cards.first)
        XCTAssertEqual(card.ownerActorId, "original-actor")
        XCTAssertEqual(card.localPreviewIdentity?.scope, scope)
        XCTAssertEqual(card.localPreviewIdentity?.bodyRevision, 2)
        let input = try XCTUnwrap(card.previewInput(snapshotID: UUID()))
        XCTAssertEqual(input.localScope, scope)
        XCTAssertEqual(input.content, "Second")
        try await store.close()
    }

    func testSyntheticFixtureReaderIsIsolatedFromProductAuthorization() async throws {
        let input = LibraryCardPreviewInput(cardID: "fixture", contentHash: nil, snapshotID: UUID(), content: "Fixture body", contentJSON: nil)
        let fixture = CardPreviewReader.fixture
        let scope = try XCTUnwrap(fixture.scope(for: input))
        let value = await fixture.read(input, scope: scope)
        XCTAssertEqual(value?.plainText, "Fixture body")
        let signedOut = CardPreviewReader(remoteSession: { nil }, localScope: { nil }, notifications: NotificationCenter())
        XCTAssertNil(signedOut.scope(for: input))
    }

    private static let cardJSON = Data(#"""
    {"id":"local-note:one","title":"title","content":"body","content_hash":"","is_public":false,"tags":[],"created_at":"2026-11-19","updated_at":"2026-11-19","like_count":0,"is_liked":false,"is_pinned":false,"rate":0}
    """#.utf8)
}
