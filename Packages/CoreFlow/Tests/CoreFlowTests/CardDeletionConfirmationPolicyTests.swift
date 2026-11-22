import Foundation
import XCTest
@testable import CoreFlow

final class CardDeletionConfirmationPolicyTests: XCTestCase {
    private struct Card: Equatable {
        let id: String
    }

    private let cardA = Card(id: "card-a")
    private let cardB = Card(id: "card-b")

    func testMissingAndEmptyIDsCannotUsePreviouslyPreparedMenuCard() {
        for requestedID in [nil, "", "  \n"] as [String?] {
            XCTAssertNil(target(requestedID, cards: [cardA], menuCard: cardA))
        }
    }

    func testUnknownIDCannotFallBackToAnotherCachedOrMenuCard() {
        XCTAssertNil(target("missing-card", cards: [cardA], menuCard: cardB))
        XCTAssertNil(target("card-b", cards: [cardA], menuCard: cardA))
    }

    func testExplicitIDChoosesMatchingCardInsteadOfThePreviousMenuCard() {
        XCTAssertEqual(target("card-b", cards: [cardA, cardB], menuCard: cardA), cardB)
    }

    func testMenuCandidateIsAcceptedOnlyWhenItsIDExactlyMatches() {
        XCTAssertEqual(target("card-b", cards: [], menuCard: cardB), cardB)
        XCTAssertNil(target(" card-b ", cards: [], menuCard: cardB))
    }

    func testVisibleConfirmationAndActiveDeletionCannotBeRetargeted() {
        XCTAssertNil(target("card-b", cards: [cardB], isConfirmationPresented: true))
        XCTAssertNil(target("card-b", cards: [cardB], isDeleting: true))
    }

    private func target(
        _ requestedID: String?,
        cards: [Card],
        menuCard: Card? = nil,
        isConfirmationPresented: Bool = false,
        isDeleting: Bool = false
    ) -> Card? {
        CardDeletionConfirmationPolicy.target(
            requestedID: requestedID,
            candidates: cards,
            menuCandidate: menuCard,
            id: \.id,
            isConfirmationPresented: isConfirmationPresented,
            isDeleting: isDeleting
        )
    }

    func testDefaultDeleteUsesExactCardHostAndLegacyObserverStillRequiresConfirmation() throws {
        let popup = try source("ArcNote/PopupMenuView.swift")
        let home = try source("ArcNote/HomeView.swift")
        let deletion = try section(popup, from: "private func deleteCard()", to: "private func toggleCardVisibility()")
        XCTAssertTrue(deletion.contains("if let onDelete"))
        XCTAssertTrue(deletion.contains("guard let target = ownedState"))
        XCTAssertTrue(deletion.contains("ownedActions?.requestRemoval(of: target)"))
        XCTAssertFalse(deletion.contains("NotificationCenter"), "A default action must not depend on a mounted Home observer or be consumed twice")
        XCTAssertTrue(popup.contains("isOwned: isOwnCard && isOwner != false"))
        XCTAssertTrue(popup.contains(".confirmationDialog(\"Remove this note?\""))
        XCTAssertTrue(popup.contains("store.confirmRemoval(of: target)"))
        let observation = try section(home, from: "for: NSNotification.Name(\"DeleteCard\")", to: "for: NSNotification.Name(\"ToggleCardPin\")")
        XCTAssertTrue(observation.contains("notification.userInfo?[\"cardId\"] as? String"))
        XCTAssertTrue(observation.contains("CardDeletionConfirmationPolicy.target("))
        XCTAssertFalse(observation.contains("currentCardId"))
        XCTAssertFalse(observation.contains(".deleteCard("))
        XCTAssertTrue(observation.contains("cardToDelete = card"))
        XCTAssertTrue(observation.contains("showDeleteConfirmation = true"))
        XCTAssertTrue(home.contains("cardsManager.deleteCard(cardId: card.id)"))
    }

    private func source(_ path: String) throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func section(_ source: String, from: String, to: String) throws -> String {
        let start = try XCTUnwrap(source.range(of: from))
        let end = try XCTUnwrap(source.range(of: to, range: start.upperBound..<source.endIndex))
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
