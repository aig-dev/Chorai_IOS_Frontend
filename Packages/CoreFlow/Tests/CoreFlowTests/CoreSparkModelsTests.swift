import XCTest
@testable import CoreFlow

final class CoreSparkModelsTests: XCTestCase {
    func testOrderedResultsUsesAllBucketsAndKeepsFirstAssetOccurrence() {
        let groups: [SparkBucket: [SparkResult]] = [
            .related: [result("ast_same", bucket: .related)],
            .angles: [result("ast_angle", bucket: .angles)],
            .keywords: [
                result("ast_same", bucket: .keywords),
                result("ast_keyword", bucket: .keywords)
            ]
        ]

        let ordered = SparkResultOrdering.flatten(groups: groups)

        XCTAssertEqual(ordered.map(\.id), ["ast_same", "ast_angle", "ast_keyword"])
        XCTAssertEqual(ordered.first?.bucket, .related)
    }

    func testEmptyRelatedStillReturnsAnglesAndKeywords() {
        let groups: [SparkBucket: [SparkResult]] = [
            .related: [],
            .angles: [result("ast_angle", bucket: .angles)],
            .keywords: [result("ast_keyword", bucket: .keywords)]
        ]

        XCTAssertEqual(
            SparkResultOrdering.flatten(groups: groups).map(\.id),
            ["ast_angle", "ast_keyword"]
        )
    }

    func testGestureResolverRequiresDominantAxis() {
        XCTAssertEqual(
            resolve(x: -90, y: 10, predictedX: -100, predictedY: 12),
            .next
        )
        XCTAssertEqual(
            resolve(x: 92, y: 8, predictedX: 120, predictedY: 10),
            .save
        )
        XCTAssertEqual(
            resolve(x: 5, y: -90, predictedX: 8, predictedY: -120),
            .sparkDeeper
        )
        XCTAssertEqual(
            resolve(x: 90, y: -80, predictedX: 100, predictedY: -90),
            .cancel
        )
    }

    func testGestureResolverUsesPredictedEndAfterShortDrag() {
        XCTAssertEqual(
            resolve(x: -42, y: 4, predictedX: -145, predictedY: 7),
            .next
        )
        XCTAssertEqual(
            resolve(x: 6, y: -38, predictedX: 8, predictedY: -150),
            .sparkDeeper
        )
    }

    func testDownwardDragNeverSparks() {
        XCTAssertEqual(
            resolve(x: 2, y: 100, predictedX: 5, predictedY: 150),
            .cancel
        )
    }

    private func resolve(
        x: Double,
        y: Double,
        predictedX: Double,
        predictedY: Double
    ) -> SparkGestureDecision {
        SparkGestureResolver.resolve(
            translationX: x,
            translationY: y,
            predictedEndX: predictedX,
            predictedEndY: predictedY
        )
    }

    private func result(_ id: String, bucket: SparkBucket) -> SparkResult {
        SparkResult(
            card: FlowCard(
                id: id,
                title: nil,
                content: id,
                contentHash: nil,
                tags: [],
                isPublic: true,
                createdAt: "",
                updatedAt: "",
                favoriteCount: 0,
                likeCount: 0,
                commentCount: 0,
                rate: 0,
                isFavorited: false,
                isLiked: false,
                isPinned: false,
                pinnedAt: nil,
                author: nil
            ),
            bucket: bucket,
            score: 1,
            resultID: "sr_\(id)"
        )
    }
}
