import Foundation

@main enum PrototypeModelTests {
    static func main() {
        var state = PrototypeState()
        precondition(state.visibleHomeNotes(scope: .notes).allSatisfy(\.isOwned), "Notes must contain only owned notes")
        precondition(state.visibleHomeNotes(scope: .collect).allSatisfy { !$0.isOwned }, "Collect must remain separate")
        state.query = "curiosity"
        precondition(state.searchResults.isEmpty, "Typing must not submit a search")
        state.submitSearch()
        precondition(state.searchResults.count == 1, "Submit should query sample bodies")
        state.query = "unmatched"
        precondition(state.searchResults.count == 1, "Editing query must preserve submitted results")
        state.cancelSearch()
        precondition(state.searchResults.isEmpty && state.submittedQuery == nil, "Cancel must clear search state")
        let collectedID = state.visibleHomeNotes(scope: .collect)[0].id
        state.collected.remove(collectedID)
        precondition(!state.visibleHomeNotes(scope: .collect).contains { $0.id == collectedID }, "Removing collection must update Collect")
        let original = state.notes[0]
        state.save(id: original.id, body: "A local revision", isPublic: true)
        precondition(state.notes[0].body == "A local revision" && state.notes[0].isPublic, "Local save must preserve body and privacy choice")
        let foreign = state.notes.first { !$0.isOwned }!
        state.save(id: foreign.id, body: "Invalid write", isPublic: false)
        precondition(state.notes.first { $0.id == foreign.id }!.body == foreign.body, "Another author's note must stay read-only")
        let added = state.createNote()
        precondition(added.body.isEmpty && !added.isPublic, "New notes start empty and private")
        precondition(state.notes.contains { $0.id == added.id }, "New note must be reachable from Home")
        state.discardEmptyDraft(id: added.id)
        precondition(!state.notes.contains { $0.id == added.id }, "Discarding a new unsaved draft must remove its empty row")
        state.discardEmptyDraft(id: original.id)
        precondition(state.notes.contains { $0.id == original.id }, "Discard must never delete an existing saved note")
        testExploreDecisions()
        print("Prototype model: 13 original checks and 24 swipe checks passed")
    }

    private static func testExploreDecisions() {
        var deck = ExploreDeckState()
        let first = UUID()
        let second = UUID()
        var saved: Set<UUID> = [second]
        precondition(deck.currentIndex(total: 0) == nil && !deck.canGoBack, "An empty feed must not expose a card or a previous action")
        deck.skip(total: 0)
        deck.collect(noteID: first, collected: &saved, total: 0)
        precondition(deck.cursor == 0 && deck.frontier == 0 && !saved.contains(first), "Empty feed actions must not invent a card or save")

        deck.skip(total: 4)
        precondition(deck.currentIndex(total: 4) == 1 && deck.frontier == 1, "Skipping must advance to the next unread card")
        precondition(saved == [second], "Skipping must preserve collection membership")
        deck.collect(noteID: second, collected: &saved, total: 4)
        precondition(deck.currentIndex(total: 4) == 2 && saved == [second], "Swiping an already-collected card must keep it collected and advance")
        precondition(deck.undoCollectionID == nil, "An existing collection must not produce a destructive undo")
        deck.undoCollection(collected: &saved)
        precondition(saved == [second], "Undo with no new collection must not remove an existing saved note")

        deck.previous()
        deck.previous()
        precondition(deck.currentIndex(total: 4) == 0 && deck.frontier == 2 && deck.isRevisiting, "Repeated previous must revisit earlier cards without losing the unread frontier")
        precondition(saved == [second], "Revisiting must not undo collection")
        deck.previous()
        precondition(deck.currentIndex(total: 4) == 0 && !deck.canGoBack, "Previous must stop at the first card")
        deck.collect(noteID: first, collected: &saved, total: 4)
        precondition(saved == [first, second] && deck.undoCollectionID == first, "Collecting a revisited unsaved card must add only that note and expose undo")
        precondition(deck.currentIndex(total: 4) == 1 && deck.frontier == 2, "Deciding on history must advance within history without consuming the unread frontier")
        deck.resume()
        precondition(deck.currentIndex(total: 4) == 2 && !deck.isRevisiting, "Continue exploring must return directly to the unread frontier")
        deck.undoCollection(collected: &saved)
        precondition(saved == [second] && deck.undoCollectionID == nil, "Undo must remove only the newly collected note and clear itself")
        precondition(deck.currentIndex(total: 4) == 2 && deck.frontier == 2, "Undo collection must not rewind navigation")

        deck.collect(noteID: first, collected: &saved, total: 4)
        precondition(saved.contains(first) && deck.currentIndex(total: 4) == 3, "A new collection from the frontier must save and advance")
        deck.dismissUndo()
        deck.undoCollection(collected: &saved)
        precondition(saved.contains(first), "An expired undo must not remove the saved note")
        deck.skip(total: 4)
        precondition(deck.currentIndex(total: 4) == nil && deck.frontier == 4 && deck.canGoBack, "The final decision must show an end state with history reachable")
        deck.skip(total: 4)
        deck.collect(noteID: UUID(), collected: &saved, total: 4)
        precondition(deck.cursor == 4 && deck.frontier == 4 && saved.count == 2, "Actions after the end must neither loop nor create phantom collections")
        deck.previous()
        precondition(deck.currentIndex(total: 4) == 3 && deck.isRevisiting, "Previous from the end must restore the last card")
        deck.resume()
        precondition(deck.currentIndex(total: 4) == nil, "Continue from completed history must return to the end, not repeat old cards")

        var replaceUndo = ExploreDeckState()
        var twoNew: Set<UUID> = []
        replaceUndo.collect(noteID: first, collected: &twoNew, total: 3)
        replaceUndo.collect(noteID: second, collected: &twoNew, total: 3)
        replaceUndo.undoCollection(collected: &twoNew)
        precondition(twoNew == [first], "Undo must apply only to the latest new collection")
        replaceUndo.previous()
        replaceUndo.previous()
        replaceUndo.collect(noteID: first, collected: &twoNew, total: 3)
        precondition(twoNew == [first] && replaceUndo.undoCollectionID == nil, "Re-collecting the first saved card must be idempotent")
        precondition(replaceUndo.frontier == 2, "Re-collecting history must preserve the furthest unread position")
    }
}
