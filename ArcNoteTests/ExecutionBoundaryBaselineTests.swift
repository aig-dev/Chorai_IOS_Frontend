import XCTest
import CoreFlow
@testable import ArcNote

final class ExecutionBoundaryBaselineTests: XCTestCase {
    func testExistingPreviewProjection() {
        let preview = LibraryCardPreviewParser.parse(content: "A note", contentJSON: nil)
        XCTAssertEqual(preview.text, "A note")
        XCTAssertNil(preview.imageSource)
    }

    @MainActor
    func testCachedLongDocumentAndTwoHundredCardWorkload() async throws {
        let json = try ExecutionFixtures.blockNoteDocument(blocks: 1000)
        let cache = LibraryCardPreviewCache()
        let input = LibraryCardPreviewInput(cardID: "hot", contentHash: "v1", snapshotID: UUID(), content: "", contentJSON: json)
        var hot: [Double] = []
        for iteration in 0..<25 {
            let start = ProcessInfo.processInfo.systemUptime
            let result = await cache.read(input, token: cache.token(for: input.cardID))
            XCTAssertEqual(result?.blocks.count, 1000)
            if iteration >= 5 { hot.append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
        }
        ExecutionFixtures.report("cached_1000_blocks", samples: hot)
        let small = try ExecutionFixtures.blockNoteDocument(blocks: 20)
        var pages: [Double] = []
        for iteration in 0..<25 {
            let start = ProcessInfo.processInfo.systemUptime
            for card in 0..<200 {
                let input = LibraryCardPreviewInput(cardID: "card-\(card)", contentHash: "v1", snapshotID: UUID(), content: "", contentJSON: small)
                let result = await cache.read(input, token: cache.token(for: input.cardID))
                XCTAssertEqual(result?.blocks.count, 20)
            }
            if iteration >= 5 { pages.append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
        }
        ExecutionFixtures.report("200_distinct_cards_20_blocks_each", samples: pages)
    }

    func testLongDocumentBaseline() throws {
        let blocks = (0..<1000).map { i in
            ["id": "b-\(i)", "type": "paragraph", "content": [["type": "text", "text": "A deliberate sentence number \(i)"]]] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: blocks, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        var durations: [Double] = []
        for iteration in 0..<25 {
            let start = ProcessInfo.processInfo.systemUptime
            let result = LibraryCardPreviewParser.presentation(content: "", contentJSON: json)
            XCTAssertEqual(result.blocks.count, 1000)
            if iteration >= 5 { durations.append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
        }
        durations.sort()
        print("EXECUTION_BASELINE blocks=1000 bytes=\(data.count) samples=20 p50_ms=\(durations[9]) p95_ms=\(durations[18])")
    }
}
