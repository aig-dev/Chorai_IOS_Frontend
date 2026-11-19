import XCTest
import SwiftUI
import CoreFlow
@testable import ArcNote

@MainActor
final class HomeCardRenderingTests: XCTestCase {
    func testGuideHaloTracksDismissalAndReeligibilityWithoutChangingTheCard() async {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ContextualGuideTipStore(persistence: UserDefaultsContextualGuideTipPersistence(defaults: defaults))
        store.load(actorID: "alice", sessionID: "first")
        let probe = GuideVisibilityProbe()
        let root = NotesCard(card: RenderingCardOwner.card(content: "Note"), onShowMenu: { _ in },
                             showMergeGuide: true, onboardingState: "product_merge_intro", contextualTipStore: store)
            .environment(\.notesCardGuideVisibilityObserver, { probe.visible = $0 })
            .environment(\.cardPreviewReader, CardPreviewReader.fixture)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded(); await settle()
        XCTAssertEqual(probe.visible, true)
        store.dismiss(.libraryMergeEntry, onboardingState: "product_merge_intro", targetIsVisible: true)
        await settle()
        XCTAssertEqual(probe.visible, false, "Dismissing the callout must remove the existing target halo")
        store.load(actorID: "alice", sessionID: "second")
        await settle()
        XCTAssertEqual(probe.visible, true, "The same mounted card must show newly eligible guidance")
    }
    func testUnrelatedLibraryChangesDoNotRecomputeCardButOwnInputDoes() async {
        let manager = HomeCardsManager()
        let owner = RenderingCardOwner()
        let probe = CardRenderProbe()
        let root = RenderingHost(owner: owner, manager: manager)
            .environment(\.notesCardRenderObserver, { id in probe.record(id) })
            .environment(\.cardPreviewReader, CardPreviewReader.fixture)
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        await settle()
        XCTAssertGreaterThan(probe.count, 0)
        let before = probe.count
        manager.isLoading.toggle()
        manager.cardFavoriteStates["unrelated"] = true
        manager.cards = [RenderingCardOwner.card(content: "Other note")]
        await settle()
        print("EXECUTION_METRIC home_row_unrelated_changes body_evaluations=\(probe.count - before)")
        XCTAssertEqual(probe.count, before, "Unrelated library state must not invalidate an unchanged card")
        owner.card = RenderingCardOwner.card(content: "Changed input")
        await settle()
        XCTAssertGreaterThan(probe.count, before, "The row must still respond to its own snapshot")
    }

    private func settle() async {
        let turn = expectation(description: "render scheduled work")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { turn.fulfill() }
        await fulfillment(of: [turn], timeout: 2)
    }
}

@MainActor
private final class GuideVisibilityProbe { var visible: Bool? }

@MainActor
private final class CardRenderProbe {
    var count = 0
    func record(_ id: String) { if id == "row-a" { count += 1 } }
}

@MainActor
private final class RenderingCardOwner: ObservableObject {
    @Published var card = card(content: "Original input")
    static func card(content: String) -> UserCard {
        .init(id: "row-a", title: "Title", content: content, contentHash: "",
              isPublic: false, tags: ["tag"], createdAt: "2026-11-19T10:00:00Z", updatedAt: "2026-11-19T10:00:00Z",
              likeCount: 0, commentCount: nil, isLiked: false, isPinned: false, pinnedAt: nil,
              isFavorited: nil, favoriteCount: nil, rate: 0)
    }
}

private struct RenderingHost: View {
    @ObservedObject var owner: RenderingCardOwner
    let manager: HomeCardsManager
    var body: some View {
        NotesCard(card: owner.card, onShowMenu: { _ in })
    }
}
