import CoreFlow
import XCTest

final class LibraryCardPreviewCacheTests: XCTestCase {
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
        let cache = LibraryCardPreviewCache(byteLimit: 128, parse: { probe.parse($0) })
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
