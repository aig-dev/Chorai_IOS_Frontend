import CoreFlow
import XCTest

final class LibraryCardPreviewCacheTests: XCTestCase {

    @MainActor
    func testConcurrentHashlessSnapshotsBothReceiveTheirOwnPresentation() async {
        let first = input("shared", version: nil, content: "Same body")
        let second = input("shared", version: nil, content: "Same body")
        let entered = expectation(description: "first parse")
        let finish = DispatchSemaphore(value: 0)
        let cache = LibraryCardPreviewCache(parse: { value in
            if value == first { entered.fulfill(); _ = finish.wait(timeout: .now() + 3) }
            return LibraryCardPreviewParser.presentation(content: value.content)
        })
        let one = Task { await read(first, cache: cache) }
        await fulfillment(of: [entered], timeout: 2)
        let two = await read(second, cache: cache)
        finish.signal()
        let oneValue = await one.value
        XCTAssertEqual(oneValue?.plainText, "Same body")
        XCTAssertEqual(two?.plainText, "Same body")
    }

    @MainActor
    func testCancellationOfOneVersionKeepsOtherVersionWaitersAlive() async {
        let first = input("shared", version: "one", content: "One")
        let second = input("shared", version: "two", content: "Two")
        let entered = expectation(description: "both parsers")
        entered.expectedFulfillmentCount = 2
        let finish = DispatchSemaphore(value: 0)
        let cache = LibraryCardPreviewCache(parse: { value in
            entered.fulfill(); _ = finish.wait(timeout: .now() + 3)
            return LibraryCardPreviewParser.presentation(content: value.content)
        })
        let one = Task { await read(first, cache: cache) }
        let two = Task { await read(second, cache: cache) }
        await fulfillment(of: [entered], timeout: 2)
        one.cancel()
        finish.signal(); finish.signal()
        let firstValue = await one.value
        let secondValue = await two.value
        XCTAssertNil(firstValue)
        XCTAssertEqual(secondValue?.plainText, "Two")
    }
    @MainActor
    func testLocalScopesAndRemoteInputNeverShare() async {
        let probe = ParseProbe()
        let cache = LibraryCardPreviewCache(parse: { probe.parse($0) })
        let a = NoteStoreScope(actorID: "alice", environmentID: "local")
        let b = NoteStoreScope(actorID: "bob", environmentID: "local")
        let one = LibraryCardPreviewInput(localNoteID: "same", scope: a, bodyRevision: 1, content: "Draft", contentJSON: nil)
        let two = LibraryCardPreviewInput(localNoteID: "same", scope: b, bodyRevision: 1, content: "Draft", contentJSON: nil)
        let revised = LibraryCardPreviewInput(localNoteID: "same", scope: a, bodyRevision: 2, content: "Draft", contentJSON: nil)
        for value in [one, two, input("same", content: "Draft"), revised] {
            let result = await cache.read(value, token: cache.token(for: value.cardID, localScope: value.localScope))
            XCTAssertEqual(result?.preview.text, "Draft")
        }
        XCTAssertEqual(probe.count, 4)
        let wrongScope = await cache.read(one, token: cache.token(for: one.cardID, localScope: b))
        XCTAssertNil(wrongScope)
    }

    @MainActor
    func testLocalInputAllowsMediaReferenceWhileRemoteDoesNot() async {
        let cache = LibraryCardPreviewCache()
        let json = #"[{"type":"image","props":{"mediaRef":"local-media","url":"chorai-note://image/local-media"}}]"#
        let local = LibraryCardPreviewInput(localNoteID: "same", scope: .init(actorID: "a", environmentID: "local"), bodyRevision: 1, content: "", contentJSON: json)
        let localResult = await cache.read(local, token: cache.token(for: local.cardID, localScope: local.localScope))
        let remote = await read(input("same", content: "", json: json), cache: cache)
        XCTAssertEqual(localResult?.preview.imageMediaRef, "local-media")
        XCTAssertNil(remote?.preview.imageMediaRef)
    }

    @MainActor
    func testRunningCancelledParsesRetainTheirCapacity() async {
        let started = expectation(description: "two parsers occupied")
        started.expectedFulfillmentCount = 2
        let unexpected = expectation(description: "third parser must remain queued")
        unexpected.isInverted = true
        let gate = DispatchSemaphore(value: 0)
        let cache = LibraryCardPreviewCache(parse: { input in
            if input.cardID == "third" { unexpected.fulfill() }
            else { started.fulfill() }
            _ = gate.wait(timeout: .now() + 3)
            XCTAssertFalse(Thread.isMainThread)
            return LibraryCardPreviewParser.presentation(content: input.content)
        })
        let first = Task { await read(input("first", content: "1"), cache: cache) }
        let second = Task { await read(input("second", content: "2"), cache: cache) }
        await fulfillment(of: [started], timeout: 2)
        cache.invalidate(cardID: "first")
        let third = Task { await read(input("third", content: "3"), cache: cache) }
        await fulfillment(of: [unexpected], timeout: 0.15)
        gate.signal(); gate.signal(); gate.signal()
        let stale = await first.value
        let next = await second.value
        let last = await third.value
        XCTAssertNil(stale)
        XCTAssertEqual(next?.preview.text, "2")
        XCTAssertEqual(last?.preview.text, "3")
    }

    @MainActor
    func testOlderVersionCompletesItsOwnReaderWithoutReplacingLatestCacheEntry() async {
        let started = expectation(description: "old computation started")
        let finish = DispatchSemaphore(value: 0)
        let probe = ParseProbe()
        let cache = LibraryCardPreviewCache(parse: { input in
            if input.content == "Old" {
                started.fulfill()
                _ = finish.wait(timeout: .now() + 3)
            }
            return probe.parse(input)
        })
        let old = input("a", version: "old", content: "Old")
        let oldTask = Task { await read(old, cache: cache) }
        await fulfillment(of: [started], timeout: 2)
        let fresh = await read(input("a", version: "new", content: "New"), cache: cache)
        finish.signal()
        let stale = await oldTask.value
        XCTAssertEqual(fresh?.preview.text, "New")
        XCTAssertEqual(stale?.preview.text, "Old")
        let cached = await read(input("a", version: "new", content: "New"), cache: cache)
        XCTAssertEqual(cached?.preview.text, "New")
        XCTAssertEqual(probe.count, 2, "Late old completion must not evict the newer cached input")
    }

    @MainActor
    func testHotReadsShareOneParseAndANewVersionParsesOnce() async {
        let probe = ParseProbe()
        let cache = LibraryCardPreviewCache(parse: { probe.parse($0) })
        let original = input("a", version: "v1", content: "First")
        let reloadedSnapshot = input("a", version: "v1", content: "First")
        let revised = input("a", version: "v2", content: "Updated")

        let first = await read(original, cache: cache)
        let hot = await read(reloadedSnapshot, cache: cache)
        XCTAssertEqual(first?.preview.text, "First")
        XCTAssertEqual(hot, first)
        XCTAssertEqual(probe.count, 1)

        let update = await read(revised, cache: cache)
        let hotUpdate = await read(revised, cache: cache)
        XCTAssertEqual(update?.preview.text, "Updated")
        XCTAssertEqual(hotUpdate, update)
        XCTAssertEqual(probe.count, 2)
    }

    @MainActor
    func testHashlessCardsReuseOnlyTheirUnchangedLoadedSnapshot() async {
        let probe = ParseProbe()
        let cache = LibraryCardPreviewCache(parse: { probe.parse($0) })
        let snapshot = UUID()
        let original = input("a", version: nil, snapshot: snapshot, content: "Original")
        let changed = input("a", version: nil, snapshot: snapshot, content: "Replacement")
        let reloaded = input("a", version: "", content: "Replacement")

        _ = await read(original, cache: cache)
        _ = await read(original, cache: cache)
        XCTAssertEqual(probe.count, 1)
        let update = await read(changed, cache: cache)
        XCTAssertEqual(update?.preview.text, "Replacement")
        XCTAssertEqual(probe.count, 2)
        _ = await read(reloaded, cache: cache)
        XCTAssertEqual(probe.count, 3)
    }

    @MainActor
    func testSameVersionReceivesFreshDisplayMediaURL() async {
        let cache = LibraryCardPreviewCache()
        let old = input(
            "a", version: "same", content: "",
            json: #"[{"type":"image","props":{"url":"https://cdn.example/image?expired=1","name":"Picture","mediaRef":"same-image"}}]"#
        )
        let refreshed = input(
            "a", version: "same", content: "",
            json: #"[{"type":"image","props":{"url":"https://cdn.example/image?renewed=1","name":"Picture","mediaRef":"same-image"}}]"#
        )

        let first = await read(old, cache: cache)
        let next = await read(refreshed, cache: cache)
        XCTAssertEqual(first?.preview.imageSource, "https://cdn.example/image?expired=1")
        XCTAssertEqual(next?.preview.imageSource, "https://cdn.example/image?renewed=1")
        XCTAssertEqual(next?.preview.imageAlternativeText, "Picture")
    }

    @MainActor
    func testConcurrentColdReadsShareOneParseEvenWhenTheResultExceedsBudget() async {
        let started = expectation(description: "First parse started")
        let secondStarted = expectation(description: "Second read entered")
        let finish = DispatchSemaphore(value: 0)
        let probe = ParseProbe()
        let cache = LibraryCardPreviewCache(byteLimit: 1, parse: { input in
            started.fulfill()
            _ = finish.wait(timeout: .now() + 2)
            return probe.parse(input)
        })
        let card = input("a", content: "Shared")

        let one = Task { await read(card, cache: cache) }
        await fulfillment(of: [started], timeout: 2)
        let two = Task {
            secondStarted.fulfill()
            return await read(card, cache: cache)
        }
        await fulfillment(of: [secondStarted], timeout: 2)
        finish.signal()

        let first = await one.value
        let second = await two.value
        XCTAssertEqual(first?.preview.text, "Shared")
        XCTAssertEqual(second, first)
        XCTAssertEqual(probe.count, 1)
    }

    @MainActor
    func testInvalidatedCardRejectsAnOlderCompletion() async {
        let started = expectation(description: "Old parse started")
        let finish = DispatchSemaphore(value: 0)
        let cache = LibraryCardPreviewCache(parse: { input in
            if input.content == "Old" {
                started.fulfill()
                _ = finish.wait(timeout: .now() + 2)
            }
            return LibraryCardPreviewParser.presentation(content: input.content)
        })
        let old = input("a", content: "Old")
        let oldRead = cache.token(for: old.cardID)
        let pending = Task { await cache.read(old, token: oldRead) }
        await fulfillment(of: [started], timeout: 2)

        cache.invalidate(cardID: old.cardID)
        let fresh = await read(input("a", content: "New"), cache: cache)
        finish.signal()

        let obsolete = await pending.value
        XCTAssertNil(obsolete)
        XCTAssertFalse(cache.isCurrent(oldRead))
        XCTAssertEqual(fresh?.preview.text, "New")
    }

    @MainActor
    func testInvalidatingSessionRejectsOlderTokensAndDropsMultipleCards() async {
        let probe = ParseProbe()
        let cache = LibraryCardPreviewCache(parse: { probe.parse($0) })
        let first = input("a", content: "First")
        let second = input("b", content: "Second")
        let priorRead = cache.token(for: first.cardID)
        _ = await read(first, cache: cache)
        _ = await read(second, cache: cache)

        cache.invalidateAll()

        let oldRead = await cache.read(first, token: priorRead)
        XCTAssertNil(oldRead)
        XCTAssertFalse(cache.isCurrent(priorRead))
        _ = await read(first, cache: cache)
        _ = await read(second, cache: cache)
        XCTAssertEqual(probe.count, 4)
    }

    @MainActor
    func testCacheEvictsLeastRecentlyUsedEntry() async {
        let probe = ParseProbe()
        let cache = LibraryCardPreviewCache(entryLimit: 2, parse: { probe.parse($0) })
        let a = input("a", content: "One")
        let b = input("b", content: "Two")
        let c = input("c", content: "Three")

        _ = await read(a, cache: cache)
        _ = await read(b, cache: cache)
        _ = await read(a, cache: cache)
        _ = await read(c, cache: cache)
        _ = await read(a, cache: cache)
        XCTAssertEqual(probe.count, 3)
        _ = await read(b, cache: cache)
        XCTAssertEqual(probe.count, 4)
    }

    @MainActor
    func testCacheAccountsForCombinedBytesAndOversizedPreviewsOnlyServeTheirRead() async {
        let probe = ParseProbe()
        let cache = LibraryCardPreviewCache(byteLimit: 160, parse: { probe.parse($0) })
        let a = input("a", content: String(repeating: "A", count: 20))
        let b = input("b", content: String(repeating: "B", count: 20))
        let large = input("large", content: String(repeating: "L", count: 200))

        _ = await read(a, cache: cache)
        _ = await read(a, cache: cache)
        XCTAssertEqual(probe.count, 1)
        _ = await read(b, cache: cache)
        _ = await read(a, cache: cache)
        XCTAssertEqual(probe.count, 3)
        let firstLarge = await read(large, cache: cache)
        let secondLarge = await read(large, cache: cache)
        XCTAssertEqual(firstLarge?.preview.text, large.content)
        XCTAssertEqual(firstLarge, secondLarge)
        _ = await read(a, cache: cache)
        XCTAssertEqual(probe.count, 5)

        cache.removeCachedPreviews()
        _ = await read(a, cache: cache)
        XCTAssertEqual(probe.count, 6)
    }

    private func input(
        _ id: String,
        version: String? = "hash",
        snapshot: UUID = UUID(),
        content: String,
        json: String? = nil
    ) -> LibraryCardPreviewInput {
        LibraryCardPreviewInput(cardID: id, contentHash: version, snapshotID: snapshot, content: content, contentJSON: json)
    }

    @MainActor
    private func read(_ input: LibraryCardPreviewInput, cache: LibraryCardPreviewCache) async -> LibraryCardPresentation? {
        await cache.read(input, token: cache.token(for: input.cardID))
    }
}

private final class ParseProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var parses = 0

    var count: Int {
        lock.withLock { parses }
    }

    func parse(_ input: LibraryCardPreviewInput) -> LibraryCardPresentation {
        lock.withLock { parses += 1 }
        return LibraryCardPreviewParser.presentation(content: input.content, contentJSON: input.contentJSON)
    }
}
