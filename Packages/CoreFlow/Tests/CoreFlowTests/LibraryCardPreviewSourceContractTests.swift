import Foundation
import XCTest

final class LibraryCardPreviewSourceContractTests: XCTestCase {
    func testEveryLibraryCardStyleUsesTheSharedRichPreview() throws {
        let home = try source(at: "ArcNote/HomeView.swift")

        XCTAssertEqual(
            home.components(
                separatedBy: "LibraryCardContentPreview("
            ).count - 1,
            2
        )
        XCTAssertTrue(home.contains("CardEditingMediaURLResolver.resolve("))
        XCTAssertTrue(home.contains("image.resizable()"))
        XCTAssertTrue(home.contains(".scaledToFit()"))
        XCTAssertTrue(
            home.contains(
                #".accessibilityIdentifier("library.card.image.\(cardID)")"#
            )
        )
    }

    func testEveryLibraryCardStyleUsesTheSharedBackgroundSurface() throws {
        let home = try source(at: "ArcNote/HomeView.swift")

        XCTAssertEqual(
            home.components(
                separatedBy: "LibraryCardBackgroundSurface("
            ).count - 1,
            2
        )
        XCTAssertGreaterThanOrEqual(
            home.components(
                separatedBy: "CardEditingMediaURLResolver.resolve("
            ).count - 1,
            2
        )

        let surfaceStart = try XCTUnwrap(
            home.range(of: "struct LibraryCardBackgroundSurface")
        )
        let notesCardStart = try XCTUnwrap(
            home.range(
                of: "struct NotesCard: View",
                range: surfaceStart.upperBound..<home.endIndex
            )
        )
        let surface = String(
            home[surfaceStart.lowerBound..<notesCardStart.lowerBound]
        )

        XCTAssertTrue(surface.contains(".scaledToFill()"))
        XCTAssertTrue(surface.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(surface.contains("@Environment(\\.colorSchemeContrast)"))
        XCTAssertTrue(surface.contains("@Environment(\\.accessibilityReduceTransparency)"))
    }

    func testEveryRateSurfaceConsumesCanonicalLevelStyle() throws {
        let home = try source(at: "ArcNote/HomeView.swift")
        let merge = try source(at: "ArcNote/MergeView.swift")
        let newInsight = try source(at: "ArcNote/NewInsightView.swift")
        let mergeLifecycle = try source(
            at: "ArcNote/CoreFlow/MergeLifecycleViews.swift"
        )
        let discoveryPath = try source(at: "ArcNote/RootView.swift")

        XCTAssertEqual(
            home.components(
                separatedBy: "LibraryCardBackgroundSurface("
            ).count - 1,
            2
        )
        for rateSurface in [home, newInsight, mergeLifecycle] {
            XCTAssertTrue(rateSurface.contains("CardLevelStyle(rate:"))
            XCTAssertFalse(rateSurface.contains("LibraryCardRateStyle"))
            XCTAssertFalse(rateSurface.contains("Critical"))
        }
        XCTAssertTrue(newInsight.contains("Text(levelStyle.label)"))
        XCTAssertTrue(
            mergeLifecycle.contains(
                "rate: store.artifactDraft?.rate ?? artifact.presentation.rate"
            )
        )
        XCTAssertTrue(
            home.contains(
                "backgroundMediaRef: card.backgroundMediaRef,\n"
                    + "                rate: card.rate"
            )
        )
        XCTAssertTrue(
            home.contains(
                "backgroundMediaRef: backgroundMediaRef,\n"
                    + "                rate: rate"
            )
        )
        XCTAssertTrue(
            merge.contains(
                "backgroundMediaRef: card.backgroundMediaRef,\n"
                    + "                rate: card.rate"
            )
        )
        XCTAssertTrue(home.contains("rate: favorite.rate"))
        XCTAssertTrue(discoveryPath.contains("rate: card.rate"))
        XCTAssertFalse(home.contains("rate: 0 // 收藏卡片"))
        XCTAssertFalse(home.contains("backgroundImageForRate"))
        XCTAssertFalse(merge.contains("backgroundImageForRate"))
        XCTAssertFalse(discoveryPath.contains("backgroundImageForRate"))

        for legacyRange in [
            "rate < 3",
            "rate >= 3 && rate <= 8",
            "rate >= 9 && rate <= 26",
            "rate >= 27 && rate <= 80",
            "rate >= 81 && rate <= 242",
            "rate > 242",
        ] {
            for source in [
                home,
                merge,
                newInsight,
                mergeLifecycle,
                discoveryPath,
            ] {
                XCTAssertFalse(source.contains(legacyRange))
            }
        }

        let panelStart = try XCTUnwrap(
            mergeLifecycle.range(of: "private struct MergeArtifactReviewPanel")
        )
        let panelEnd = try XCTUnwrap(
            mergeLifecycle.range(
                of: "private struct MergeArtifactTextAction",
                range: panelStart.upperBound..<mergeLifecycle.endIndex
            )
        )
        let panel = String(
            mergeLifecycle[panelStart.lowerBound..<panelEnd.lowerBound]
        )
        XCTAssertTrue(panel.contains("CardLevelStyle(rate: rate)"))
        XCTAssertTrue(panel.contains(".accessibilityLabel(style.label)"))
        XCTAssertFalse(panel.contains(#"\(rate)"#))
        XCTAssertFalse(panel.contains("String(rate)"))
        XCTAssertFalse(panel.contains(".accessibilityValue"))
    }

    func testImageBearingLibraryListsAreLazyAndPreserveCanonicalContent() throws {
        let home = try source(at: "ArcNote/HomeView.swift")

        XCTAssertGreaterThanOrEqual(
            home.components(
                separatedBy: "LazyVStack(spacing: 20)"
            ).count - 1,
            2
        )
        XCTAssertEqual(
            home.components(
                separatedBy: "contentJSON: favorite.contentJSON"
            ).count - 1,
            2
        )
    }

    func testLibraryListModelDecodesCanonicalDocument() throws {
        let models = try source(at: "ArcNote/NetworkModels.swift")
        let userCardStart = try XCTUnwrap(
            models.range(of: "struct UserCard: Codable, Identifiable")
        )
        let createCardStart = try XCTUnwrap(
            models.range(
                of: "// MARK: - 创建卡片响应数据模型",
                range: userCardStart.upperBound..<models.endIndex
            )
        )
        let userCard = String(
            models[userCardStart.lowerBound..<createCardStart.lowerBound]
        )

        XCTAssertTrue(userCard.contains("let contentJSON: String?"))
        XCTAssertTrue(userCard.contains(#"case contentJSON = "content_json""#))
        XCTAssertTrue(userCard.contains("let backgroundMediaRef: String?"))
        XCTAssertTrue(userCard.contains(#"case backgroundMediaRef = "background_media_ref""#))

        let cardStart = try XCTUnwrap(
            models.range(of: "struct Card: Codable, Identifiable")
        )
        let cardEnd = try XCTUnwrap(
            models.range(
                of: "// MARK: 创建卡片请求模型",
                range: cardStart.upperBound..<models.endIndex
            )
        )
        let card = String(models[cardStart.lowerBound..<cardEnd.lowerBound])
        XCTAssertTrue(card.contains("let contentJSON: String?"))
        XCTAssertTrue(card.contains(#"contentJSON = "content_json""#))
        XCTAssertTrue(card.contains("let backgroundMediaRef: String?"))
        XCTAssertTrue(card.contains(#"backgroundMediaRef = "background_media_ref""#))

        let favorites = try source(at: "ArcNote/Models/FavoritesModels.swift")
        XCTAssertTrue(favorites.contains("contentJSON = card.contentJSON"))
        XCTAssertTrue(favorites.contains("let backgroundMediaRef: String?"))
        XCTAssertTrue(favorites.contains("backgroundMediaRef = card.backgroundMediaRef"))
    }

    func testLibraryBackgroundSurvivesStateProjections() throws {
        let home = try source(at: "ArcNote/HomeView.swift")
        XCTAssertEqual(
            home.components(
                separatedBy: "backgroundMediaRef: favorite.backgroundMediaRef"
            ).count - 1,
            2
        )

        let manager = try source(at: "ArcNote/HomeCardsManager.swift")
        XCTAssertEqual(
            manager.components(
                separatedBy: "backgroundMediaRef: self?.cards[index].backgroundMediaRef"
            ).count - 1,
            2
        )

        let detail = try source(at: "ArcNote/DetailView.swift")
        XCTAssertTrue(detail.contains("backgroundMediaRef: detail.backgroundMediaRef"))

        let explore = try source(at: "ArcNote/ExploreView.swift")
        XCTAssertTrue(explore.contains("backgroundMediaRef: card.backgroundMediaRef"))
    }

    func testSearchAndFlowProjectionsPreserveLibraryBackgrounds() throws {
        let searchModels = try source(at: "ArcNote/Models/SearchModels.swift")
        XCTAssertTrue(searchModels.contains("let backgroundMediaRef: String?"))
        XCTAssertTrue(
            searchModels.contains(
                #"case backgroundMediaRef = "background_media_ref""#
            )
        )
        XCTAssertTrue(
            searchModels.contains(
                "backgroundMediaRef = try container.decodeIfPresent"
            )
        )

        let search = try source(at: "ArcNote/SearchView.swift")
        XCTAssertTrue(
            search.contains(
                "backgroundMediaRef: result.card.backgroundMediaRef"
            )
        )

        let librarySearchModels = try source(
            at: "ArcNote/Models/UserAllCardsModels.swift"
        )
        XCTAssertTrue(
            librarySearchModels.contains("let backgroundMediaRef: String?")
        )
        XCTAssertTrue(
            librarySearchModels.contains(
                "backgroundMediaRef: backgroundMediaRef"
            )
        )

        let explore = try source(at: "ArcNote/ExploreView.swift")
        XCTAssertTrue(
            explore.contains(
                "backgroundMediaRef: searchCard.backgroundMediaRef"
            )
        )

        let flowModels = try source(
            at: "Packages/CoreFlow/Sources/CoreFlow/CoreFlowModels.swift"
        )
        XCTAssertTrue(flowModels.contains("public let backgroundMediaRef: String?"))
        XCTAssertEqual(
            flowModels.components(
                separatedBy: "backgroundMediaRef: backgroundMediaRef"
            ).count - 1,
            2
        )

        let flowService = try source(
            at: "ArcNote/CoreFlow/NetworkCoreFlowService.swift"
        )
        XCTAssertEqual(
            flowService.components(
                separatedBy: "backgroundMediaRef: backgroundMediaRef"
            ).count - 1,
            2
        )
    }

    private func source(at path: String) throws -> String {
        try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
